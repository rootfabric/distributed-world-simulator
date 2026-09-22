extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterMaterial = preload("res://scripts/simulation/matter/contracts/matter_material_definition.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Profile = preload("res://scripts/research/fabric_bake0/laser_emitter_photonic_profile_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/laser_emitter_graph_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Dependencies = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")

const CELLS := 128
const COMPILER_VERSION := "FABRIC_R5_2_T9_LASER_EMITTER_COMPILER_R1"

static func _material(
	material_id: String,
	name: String,
	density: float,
	cp: float,
	k: float,
	melting_k: float,
	vaporization_k: float
) -> Dictionary:
	return MatterMaterial.create({
		"material_id": material_id,
		"display_name": name,
		"family": "matter-family/photonic-semiconductor",
		"phase": "SOLID",
		"density_kg_m3": density,
		"hardness_pa": 5.0e9,
		"compressive_strength_pa": 1.0e9,
		"tensile_strength_pa": 2.0e8,
		"fracture_toughness_pa_m_sqrt": 1.0e6,
		"cohesion_pa": 1.0e8,
		"abrasiveness_ratio": 0.2,
		"porosity_ratio": 0.001,
		"permeability_m2": 1.0e-22,
		"heat_capacity_j_kg_k": cp,
		"thermal_conductivity_w_m_k": k,
		"melting_temperature_k": melting_k,
		"vaporization_temperature_k": vaporization_k,
		"mining_energy_j_kg": 1.0e6,
		"tags": ["matter-tag/optical", "matter-tag/semiconductor"],
	})

static func material_catalog(reverse_input: bool = false) -> Dictionary:
	var materials: Array = [
		_material("matter/laser-gaas", "GaAs-like laser active material", 5317.0, 330.0, 55.0, 1511.0, 2800.0),
		_material("matter/laser-gan", "GaN-like laser active material", 6150.0, 490.0, 130.0, 2773.0, 4000.0),
	]
	if reverse_input:
		materials.reverse()
	return MatterCatalog.create(materials, "matter-catalog/r5-t9-laser-emitter", "1.0.0")

static func profiles(catalog: Dictionary, reverse_input: bool = false) -> Array:
	var gaas := MatterCatalog.material_by_id(catalog, "matter/laser-gaas")
	var gan := MatterCatalog.material_by_id(catalog, "matter/laser-gan")
	var values: Array = [
		Profile.create("profile/laser-gaas-905nm", gaas, 1.0e6, 4.0e6, 5.0e-4, 1.60, 0.55, 0.0020, 300.0, 250.0, 420.0, 905.0e-9, 1.30),
		Profile.create("profile/laser-gan-450nm", gan, 1.5e6, 5.0e6, 8.0e-4, 3.20, 0.42, 0.0015, 300.0, 250.0, 450.0, 450.0e-9, 1.50),
	]
	if reverse_input:
		values.reverse()
	return values

static func make_graph(
	kind: String = "GAAS",
	disable_one: bool = false,
	geometry_mismatch: bool = false,
	mixed_profile: bool = false,
	reverse_input: bool = false
) -> Dictionary:
	var catalog := material_catalog(reverse_input)
	var profile_values := profiles(catalog, reverse_input)
	var selected := "profile/laser-gan-450nm" if kind == "GAN" else "profile/laser-gaas-905nm"
	var cells: Array = []
	for index in range(CELLS):
		var area := 2.0e-6
		if geometry_mismatch and index == 11:
			area *= 1.02
		var profile_id := selected
		if mixed_profile and index == 17:
			profile_id = "profile/laser-gan-450nm" if selected == "profile/laser-gaas-905nm" else "profile/laser-gaas-905nm"
		cells.append({
			"cell_id": "laser-gain/%03d" % index,
			"profile_id": profile_id,
			"active_area_m2": area,
			"current_path_length_m": 1.0e-4,
			"quality_ratio": 0.98,
			"enabled": not (disable_one and index == 9),
		})
	if reverse_input:
		cells.reverse()
	return Graph.create("graph/r5-t9-laser-emitter-128", catalog, profile_values, cells)

static func build_request(graph: Dictionary, revision: int = 0) -> Dictionary:
	var dependency_hash := U.canonical_hash({"dependency": "r5-t9-laser-emitter"})
	var construction := SourceRevision.create(
		"CONSTRUCTION", "construct/r5-t9-laser-emitter", 21, 900 + revision,
		String(graph.graph_hash), dependency_hash
	)
	var matter := SourceRevision.create(
		"MATTER", "matter/r5-t9-laser-materials", 21, 1,
		String(graph.material_catalog.catalog_hash), dependency_hash
	)
	var frontier := Frontier.create([construction, matter])
	var authority := Authority.create(
		"server/fabric-r5",
		[
			{"source_domain": "CONSTRUCTION", "source_id": "construct/r5-t9-laser-emitter", "authority_epoch": 21, "owner_id": "server/fabric-r5"},
			{"source_domain": "MATTER", "source_id": "matter/r5-t9-laser-materials", "authority_epoch": 21, "owner_id": "server/fabric-r5"},
		],
		[
			U.source_key("CONSTRUCTION", "construct/r5-t9-laser-emitter"),
			U.source_key("MATTER", "matter/r5-t9-laser-materials"),
		]
	)
	var dependencies := Dependencies.create([
		{"dependency_id": "dependency/r5-t9-laser-compiler", "dependency_hash": U.canonical_hash({"version": COMPILER_VERSION})},
		{"dependency_id": "dependency/r5-t9-photonic-floor", "dependency_hash": U.canonical_hash({"profile_schema": Profile.SCHEMA})},
	])
	return {
		"artifact_id": "artifact/r5-t9-laser-emitter",
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
