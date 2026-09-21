extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterMaterial = preload("res://scripts/simulation/matter/contracts/matter_material_definition.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Graph = preload("res://scripts/research/fabric_bake0/thermal_pack_graph_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Dependencies = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")

const LAYERS := 8
const LANES := 64
const CELL_COUNT := LAYERS * LANES
const COMPILER_VERSION := "FABRIC_R5_2_T4_THERMAL_FILTER_COMPILER_R1"

static func _material(
	material_id: String,
	name: String,
	family: String,
	density: float,
	heat_capacity: float,
	thermal_conductivity: float,
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
		"hardness_pa": 1.0e7,
		"compressive_strength_pa": 1.0e8,
		"tensile_strength_pa": 1.0e8,
		"fracture_toughness_pa_m_sqrt": 1.0e6,
		"cohesion_pa": 1.0e7,
		"abrasiveness_ratio": 0.2,
		"porosity_ratio": 0.01,
		"permeability_m2": 1.0e-20,
		"heat_capacity_j_kg_k": heat_capacity,
		"thermal_conductivity_w_m_k": thermal_conductivity,
		"melting_temperature_k": melting_k,
		"vaporization_temperature_k": vaporization_k,
		"mining_energy_j_kg": 5.0e5,
		"tags": tags,
	})

static func material_catalog(reverse_input: bool = false) -> Dictionary:
	var materials: Array = [
		_material("matter/thermal-aluminum", "Thermal aluminum", "matter-family/metal", 2700.0, 900.0, 205.0, 933.0, 2743.0, ["matter-tag/structural", "matter-tag/thermal"]),
		_material("matter/thermal-steel", "Thermal steel", "matter-family/metal", 7850.0, 500.0, 16.0, 1700.0, 3134.0, ["matter-tag/structural", "matter-tag/thermal"]),
	]
	if reverse_input:
		materials.reverse()
	return MatterCatalog.create(materials, "matter-catalog/r5-t4-thermal", "1.0.0")

static func make_graph(asymmetric_lane: bool = false, reverse_input: bool = false) -> Dictionary:
	var catalog := material_catalog(reverse_input)
	var material_pattern := [
		"matter/thermal-aluminum",
		"matter/thermal-aluminum",
		"matter/thermal-steel",
		"matter/thermal-steel",
		"matter/thermal-aluminum",
		"matter/thermal-steel",
		"matter/thermal-steel",
		"matter/thermal-aluminum",
	]
	var volume_pattern := [1.8e-5, 2.0e-5, 2.2e-5, 2.4e-5, 2.0e-5, 2.4e-5, 2.2e-5, 1.8e-5]
	var cells: Array = []
	for layer in range(LAYERS):
		for lane in range(LANES):
			var volume := float(volume_pattern[layer])
			if asymmetric_lane and layer == 3 and lane == 7:
				volume *= 1.01
			cells.append({
				"cell_id": "thermal-cell/l%02d-n%03d" % [layer, lane],
				"layer_index": layer,
				"lane_index": lane,
				"material_id": String(material_pattern[layer]),
				"volume_m3": volume,
				"enabled": true,
			})
	if reverse_input:
		cells.reverse()
	return Graph.create(
		"graph/r5-t4-thermal-pack-8x64",
		catalog,
		LAYERS,
		LANES,
		cells,
		4.0e-4,
		0.012,
		3.0e-4,
		0.010
	)

static func build_request(graph: Dictionary, revision: int = 0) -> Dictionary:
	var dependency_hash := U.canonical_hash({"dependency": "r5-t4-thermal-filter"})
	var construction := SourceRevision.create(
		"CONSTRUCTION", "construct/r5-t4-thermal-pack", 15, 400 + revision,
		String(graph.graph_hash), dependency_hash
	)
	var matter := SourceRevision.create(
		"MATTER", "matter/r5-t4-thermal-materials", 15, 1,
		String(graph.material_catalog.catalog_hash), dependency_hash
	)
	var frontier := Frontier.create([construction, matter])
	var authority := Authority.create(
		"server/fabric-r5",
		[
			{"source_domain": "CONSTRUCTION", "source_id": "construct/r5-t4-thermal-pack", "authority_epoch": 15, "owner_id": "server/fabric-r5"},
			{"source_domain": "MATTER", "source_id": "matter/r5-t4-thermal-materials", "authority_epoch": 15, "owner_id": "server/fabric-r5"},
		],
		[
			U.source_key("CONSTRUCTION", "construct/r5-t4-thermal-pack"),
			U.source_key("MATTER", "matter/r5-t4-thermal-materials"),
		]
	)
	var dependencies := Dependencies.create([
		{"dependency_id": "dependency/r5-t4-thermal-filter-compiler", "dependency_hash": U.canonical_hash({"version": COMPILER_VERSION})},
		{"dependency_id": "dependency/r5-t4-matter-thermal-properties", "dependency_hash": U.canonical_hash({"catalog_hash": graph.material_catalog.catalog_hash})},
	])
	return {
		"artifact_id": "artifact/r5-t4-thermal-filter",
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
