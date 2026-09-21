extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterMaterial = preload("res://scripts/simulation/matter/contracts/matter_material_definition.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Profile = preload("res://scripts/research/fabric_bake0/motor_electromagnetic_profile_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/motor_generator_graph_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Dependencies = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")

const WINDINGS := 192
const ROTOR_SECTORS := 64
const COMPONENT_COUNT := WINDINGS + ROTOR_SECTORS
const COMPILER_VERSION := "FABRIC_R5_2_T5_MOTOR_GENERATOR_COMPILER_R1"

static func _material(
	material_id: String,
	name: String,
	family: String,
	density: float,
	heat_capacity: float,
	thermal_conductivity: float,
	tensile_strength: float,
	melting_k: float,
	vaporization_k: float,
	tags: Array
) -> Dictionary:
	return MatterMaterial.create({
		"material_id": material_id,
		"display_name": name,
		"family": family,
		"phase": "SOLID",
		"density_kg_m3": density,
		"hardness_pa": 1.0e8,
		"compressive_strength_pa": maxf(tensile_strength, 1.0e8),
		"tensile_strength_pa": tensile_strength,
		"fracture_toughness_pa_m_sqrt": 1.0e6,
		"cohesion_pa": 1.0e7,
		"abrasiveness_ratio": 0.2,
		"porosity_ratio": 0.01,
		"permeability_m2": 1.0e-20,
		"heat_capacity_j_kg_k": heat_capacity,
		"thermal_conductivity_w_m_k": thermal_conductivity,
		"melting_temperature_k": melting_k,
		"vaporization_temperature_k": vaporization_k,
		"mining_energy_j_kg": 8.0e5,
		"tags": tags,
	})

static func material_catalog(reverse_input: bool = false) -> Dictionary:
	var materials: Array = [
		_material("matter/motor-copper", "Motor copper winding", "matter-family/metal", 8960.0, 385.0, 400.0, 2.0e8, 1357.0, 2835.0, ["matter-tag/electrical", "matter-tag/motor"]),
		_material("matter/motor-ndfeb", "Motor NdFeB magnet", "matter-family/magnetic", 7500.0, 450.0, 9.0, 8.0e7, 1300.0, 2500.0, ["matter-tag/magnetic", "matter-tag/motor"]),
		_material("matter/motor-steel", "Motor rotor steel", "matter-family/metal", 7800.0, 500.0, 45.0, 6.0e8, 1750.0, 3100.0, ["matter-tag/motor", "matter-tag/structural"]),
		_material("matter/motor-aluminum", "Motor rotor aluminum", "matter-family/metal", 2700.0, 900.0, 205.0, 3.0e8, 933.0, 2743.0, ["matter-tag/motor", "matter-tag/structural"]),
	]
	if reverse_input:
		materials.reverse()
	return MatterCatalog.create(materials, "matter-catalog/r5-t5-motor-generator", "1.0.0")

static func profiles(catalog: Dictionary) -> Array:
	var copper := MatterCatalog.material_by_id(catalog, "matter/motor-copper")
	var magnet := MatterCatalog.material_by_id(catalog, "matter/motor-ndfeb")
	return [
		Profile.create(
			"profile/motor-copper-ndfeb-characterized",
			copper,
			magnet,
			1.68e-8,
			1.10,
			8.0e6
		)
	]

static func make_graph(
	winding_quality_scale: float = 1.0,
	rotor_material_id: String = "matter/motor-steel",
	open_winding: bool = false,
	incomplete_rotor: bool = false,
	reverse_input: bool = false
) -> Dictionary:
	var catalog := material_catalog(reverse_input)
	var profile_values := profiles(catalog)
	var quality_pattern := [0.94, 0.96, 0.98, 1.0, 0.95, 0.97, 0.99, 0.93]
	var windings: Array = []
	for index in range(WINDINGS):
		var q := clampf(float(quality_pattern[index % quality_pattern.size()]) * winding_quality_scale, 0.5, 1.0)
		windings.append({
			"winding_id": "winding/segment-%03d" % index,
			"profile_id": "profile/motor-copper-ndfeb-characterized",
			"wire_length_m": 0.09,
			"wire_area_m2": 2.0e-6,
			"active_length_m": 0.020,
			"lever_arm_m": 0.040,
			"turns": 2,
			"quality_ratio": q,
			"enabled": not (open_winding and index == 17),
		})
	var sectors: Array = []
	for index in range(ROTOR_SECTORS):
		sectors.append({
			"sector_id": "rotor/sector-%03d" % index,
			"material_id": rotor_material_id,
			"volume_m3": 7.0e-6,
			"radius_m": 0.055,
			"quality_ratio": 0.97,
			"enabled": not (incomplete_rotor and index == 9),
		})
	if reverse_input:
		windings.reverse()
		sectors.reverse()
	return Graph.create(
		"graph/r5-t5-motor-generator-192w64r",
		catalog,
		profile_values,
		windings,
		sectors
	)

static func build_request(graph: Dictionary, revision: int = 0) -> Dictionary:
	var dependency_hash := U.canonical_hash({"dependency": "r5-t5-motor-generator"})
	var construction := SourceRevision.create(
		"CONSTRUCTION", "construct/r5-t5-motor-generator", 16, 500 + revision,
		String(graph.graph_hash), dependency_hash
	)
	var matter := SourceRevision.create(
		"MATTER", "matter/r5-t5-motor-generator-materials", 16, 1,
		String(graph.material_catalog.catalog_hash), dependency_hash
	)
	var frontier := Frontier.create([construction, matter])
	var authority := Authority.create(
		"server/fabric-r5",
		[
			{"source_domain": "CONSTRUCTION", "source_id": "construct/r5-t5-motor-generator", "authority_epoch": 16, "owner_id": "server/fabric-r5"},
			{"source_domain": "MATTER", "source_id": "matter/r5-t5-motor-generator-materials", "authority_epoch": 16, "owner_id": "server/fabric-r5"},
		],
		[
			U.source_key("CONSTRUCTION", "construct/r5-t5-motor-generator"),
			U.source_key("MATTER", "matter/r5-t5-motor-generator-materials"),
		]
	)
	var dependencies := Dependencies.create([
		{"dependency_id": "dependency/r5-t5-motor-generator-compiler", "dependency_hash": U.canonical_hash({"version": COMPILER_VERSION})},
		{"dependency_id": "dependency/r5-t5-electromagnetic-floor", "dependency_hash": U.canonical_hash({"profile_schema": Profile.SCHEMA})},
	])
	return {
		"artifact_id": "artifact/r5-t5-motor-generator",
		"canonical_source_frontier": frontier,
		"authority_envelope": authority,
		"dependency_set": dependencies,
		"build_generation": 1 + revision,
	}

static func live_from(artifact: Dictionary) -> Dictionary:
	return {
		"artifact_state": "READY",
		"invalidations": [],
		"canonical_source_frontier": artifact.canonical_source_frontier.duplicate(true),
		"authority_envelope": artifact.authority_envelope.duplicate(true),
		"dependency_set": artifact.dependency_set.duplicate(true),
		"graph_hash": String(artifact.graph_hash),
		"material_catalog_hash": String(artifact.material_catalog_hash),
		"interface_hash": String(artifact.interface_contract.interface_hash),
	}
