extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterMaterial = preload("res://scripts/simulation/matter/contracts/matter_material_definition.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Profile = preload("res://scripts/research/fabric_bake0/cooling_coolant_profile_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/cooling_loop_graph_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Dependencies = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")

const LANES := 64
const SOURCE_THERMAL_NODES := LANES * 4
const COMPILER_VERSION := "FABRIC_R5_2_T8_COOLING_LOOP_COMPILER_R1"

static func _material(
	material_id: String,
	name: String,
	family: String,
	phase: String,
	density: float,
	cp: float,
	k: float,
	melting_k: float,
	vaporization_k: float,
	tensile: float = 1.0e6,
	compressive: float = 1.0e6
) -> Dictionary:
	return MatterMaterial.create({
		"material_id": material_id,
		"display_name": name,
		"family": family,
		"phase": phase,
		"density_kg_m3": density,
		"hardness_pa": 1.0e6,
		"compressive_strength_pa": compressive,
		"tensile_strength_pa": tensile,
		"fracture_toughness_pa_m_sqrt": 1.0e5,
		"cohesion_pa": 1.0e5,
		"abrasiveness_ratio": 0.1,
		"porosity_ratio": 0.001,
		"permeability_m2": 1.0e-20,
		"heat_capacity_j_kg_k": cp,
		"thermal_conductivity_w_m_k": k,
		"melting_temperature_k": melting_k,
		"vaporization_temperature_k": vaporization_k,
		"mining_energy_j_kg": 5.0e5,
		"tags": ["matter-tag/cooling", "matter-tag/thermal"],
	})

static func material_catalog(reverse_input: bool = false) -> Dictionary:
	var materials: Array = [
		_material("matter/cooling-copper", "Cooling copper plate", "matter-family/metal", "SOLID", 8960.0, 385.0, 400.0, 1357.0, 2835.0, 2.0e8, 5.0e8),
		_material("matter/cooling-aluminum", "Cooling aluminum radiator", "matter-family/metal", "SOLID", 2700.0, 900.0, 205.0, 933.0, 2743.0, 3.0e8, 4.5e8),
		_material("matter/coolant-water", "Water-like coolant", "matter-family/coolant", "LIQUID", 997.0, 4180.0, 0.60, 273.15, 373.15),
		_material("matter/coolant-glycol", "Glycol-like coolant", "matter-family/coolant", "LIQUID", 1110.0, 3500.0, 0.25, 250.0, 470.0),
	]
	if reverse_input:
		materials.reverse()
	return MatterCatalog.create(materials, "matter-catalog/r5-t8-cooling", "1.0.0")

static func coolant_profile(catalog: Dictionary, kind: String) -> Dictionary:
	var glycol := kind == "GLYCOL"
	var material_id := "matter/coolant-glycol" if glycol else "matter/coolant-water"
	var material := MatterCatalog.material_by_id(catalog, material_id)
	return Profile.create(
		"profile/cooling-glycol-characterized" if glycol else "profile/cooling-water-characterized",
		material,
		0.0040 if glycol else 0.0010,
		40.0,
		2000.0
	)

static func make_graph(
	kind: String = "WATER",
	asymmetric_lane: bool = false,
	disabled_lane: bool = false,
	reverse_input: bool = false
) -> Dictionary:
	var catalog := material_catalog(reverse_input)
	var profile := coolant_profile(catalog, kind)
	var coolant_id := "matter/coolant-glycol" if kind == "GLYCOL" else "matter/coolant-water"
	var lanes: Array = []
	for index in range(LANES):
		var flow_area := 1.0e-5
		if asymmetric_lane and index == 5:
			flow_area *= 1.05
		lanes.append({
			"lane_id": "cooling-lane/%03d" % index,
			"plate_material_id": "matter/cooling-copper",
			"radiator_material_id": "matter/cooling-aluminum",
			"coolant_material_id": coolant_id,
			"plate_volume_m3": 3.0e-6,
			"plate_contact_area_m2": 1.0e-3,
			"plate_wall_thickness_m": 2.0e-3,
			"hot_coolant_volume_m3": 2.0e-6,
			"cold_coolant_volume_m3": 2.0e-6,
			"radiator_volume_m3": 1.0e-5,
			"radiator_contact_area_m2": 2.0e-3,
			"radiator_wall_thickness_m": 1.5e-3,
			"radiator_ambient_area_m2": 2.5e-2,
			"channel_flow_area_m2": flow_area,
			"channel_hydraulic_diameter_m": 3.0e-3,
			"channel_flow_length_m": 2.0,
			"quality_ratio": 0.98,
			"enabled": not (disabled_lane and index == 7),
		})
	if reverse_input:
		lanes.reverse()
	return Graph.create("graph/r5-t8-cooling-64lane", catalog, profile, lanes)

static func build_request(graph: Dictionary, revision: int = 0) -> Dictionary:
	var dependency_hash := U.canonical_hash({"dependency": "r5-t8-cooling-loop"})
	var construction := SourceRevision.create(
		"CONSTRUCTION", "construct/r5-t8-cooling-loop", 20, 800 + revision,
		String(graph.graph_hash), dependency_hash
	)
	var matter := SourceRevision.create(
		"MATTER", "matter/r5-t8-cooling-materials", 20, 1,
		String(graph.material_catalog.catalog_hash), dependency_hash
	)
	var frontier := Frontier.create([construction, matter])
	var authority := Authority.create(
		"server/fabric-r5",
		[
			{"source_domain": "CONSTRUCTION", "source_id": "construct/r5-t8-cooling-loop", "authority_epoch": 20, "owner_id": "server/fabric-r5"},
			{"source_domain": "MATTER", "source_id": "matter/r5-t8-cooling-materials", "authority_epoch": 20, "owner_id": "server/fabric-r5"},
		],
		[
			U.source_key("CONSTRUCTION", "construct/r5-t8-cooling-loop"),
			U.source_key("MATTER", "matter/r5-t8-cooling-materials"),
		]
	)
	var dependencies := Dependencies.create([
		{"dependency_id": "dependency/r5-t8-cooling-compiler", "dependency_hash": U.canonical_hash({"version": COMPILER_VERSION})},
		{"dependency_id": "dependency/r5-t8-coolant-floor", "dependency_hash": U.canonical_hash({"profile_schema": Profile.SCHEMA})},
	])
	return {
		"artifact_id": "artifact/r5-t8-cooling-loop",
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
