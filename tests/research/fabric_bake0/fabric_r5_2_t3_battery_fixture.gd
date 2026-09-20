extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterMaterial = preload("res://scripts/simulation/matter/contracts/matter_material_definition.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Profile = preload("res://scripts/research/fabric_bake0/battery_electrochemical_profile_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/battery_cell_graph_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Dependencies = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")

const SERIES := 12
const PARALLEL := 8
const CELL_COUNT := SERIES * PARALLEL
const COMPILER_VERSION := "FABRIC_R5_2_T3_BATTERY_COMPILER_R1"

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
		"hardness_pa": 1.0e6,
		"compressive_strength_pa": 1.0e6,
		"tensile_strength_pa": 1.0e5,
		"fracture_toughness_pa_m_sqrt": 1.0e4,
		"cohesion_pa": 1.0e5,
		"abrasiveness_ratio": 0.1,
		"porosity_ratio": 0.05,
		"permeability_m2": 1.0e-18,
		"heat_capacity_j_kg_k": heat_capacity,
		"thermal_conductivity_w_m_k": thermal_conductivity,
		"melting_temperature_k": melting_k,
		"vaporization_temperature_k": vaporization_k,
		"mining_energy_j_kg": 1.0e5,
		"tags": tags,
	})

static func material_catalog(reverse_input: bool = false) -> Dictionary:
	var materials: Array = [
		_material("matter/lfp-active", "LFP active composite", "matter-family/electrochemical-active", 3600.0, 900.0, 3.0, 900.0, 1800.0, ["matter-tag/battery", "matter-tag/electrochemical"]),
		_material("matter/nmc-active", "NMC active composite", "matter-family/electrochemical-active", 4800.0, 800.0, 4.0, 850.0, 1700.0, ["matter-tag/battery", "matter-tag/electrochemical"]),
		_material("matter/cell-case-polymer", "Cell case polymer", "matter-family/polymer", 1200.0, 1500.0, 0.25, 520.0, 900.0, ["matter-tag/battery", "matter-tag/structural"]),
	]
	if reverse_input:
		materials.reverse()
	return MatterCatalog.create(materials, "matter-catalog/r5-t3-battery", "1.0.0")

static func profiles(catalog: Dictionary, reverse_input: bool = false) -> Array:
	var lfp := MatterCatalog.material_by_id(catalog, "matter/lfp-active")
	var nmc := MatterCatalog.material_by_id(catalog, "matter/nmc-active")
	var values: Array = [
		Profile.create("profile/lfp-characterized", lfp, 2.8, 3.2, 3.6, 612000.0, 5.0, 2.0e-5, 600.0, 0.0035, 298.15, 260.0, 360.0),
		Profile.create("profile/nmc-characterized", nmc, 3.0, 3.7, 4.2, 720000.0, 4.0, 1.8e-5, 550.0, 0.0040, 298.15, 260.0, 350.0),
	]
	if reverse_input:
		values.reverse()
	return values

static func make_graph(
	chemistry: String = "LFP",
	quality_scale: float = 1.0,
	damage_one_cell: bool = false,
	unsafe_geometry: bool = false,
	mixed_parallel_profile: bool = false,
	open_first_group: bool = false,
	reverse_input: bool = false
) -> Dictionary:
	var catalog := material_catalog(reverse_input)
	var profile_values := profiles(catalog, reverse_input)
	var selected_profile := "profile/nmc-characterized" if chemistry == "NMC" else "profile/lfp-characterized"
	var quality_pattern := [0.94, 0.96, 0.98, 1.0, 0.95, 0.97, 0.99, 0.93]
	var cells: Array = []
	for series_index in range(SERIES):
		for parallel_index in range(PARALLEL):
			var profile_id := selected_profile
			if mixed_parallel_profile and series_index == 0 and parallel_index == 0:
				profile_id = "profile/nmc-characterized" if selected_profile == "profile/lfp-characterized" else "profile/lfp-characterized"
			var active_volume := 1.5e-5
			if unsafe_geometry and series_index == 0 and parallel_index == 1:
				active_volume *= 1.07
			var enabled := true
			if damage_one_cell and series_index == 5 and parallel_index == 3:
				enabled = false
			if open_first_group and series_index == 0:
				enabled = false
			cells.append({
				"cell_id": "cell/s%02d-p%02d" % [series_index, parallel_index],
				"series_index": series_index,
				"parallel_index": parallel_index,
				"profile_id": profile_id,
				"case_material_id": "matter/cell-case-polymer",
				"active_volume_m3": active_volume,
				"case_volume_m3": 8.0e-6,
				"electrode_area_m2": 0.015,
				"current_path_length_m": 0.0002,
				"case_surface_area_m2": 0.0015,
				"case_wall_thickness_m": 0.0015,
				"quality_ratio": clampf(float(quality_pattern[parallel_index]) * quality_scale, 0.5, 1.0),
				"enabled": enabled,
			})
	if reverse_input:
		cells.reverse()
	return Graph.create(
		"graph/r5-t3-battery-12s8p",
		catalog,
		profile_values,
		SERIES,
		PARALLEL,
		cells
	)

static func build_request(graph: Dictionary, revision: int = 0) -> Dictionary:
	var dependency_hash := U.canonical_hash({"dependency": "r5-t3-battery"})
	var construction := SourceRevision.create(
		"CONSTRUCTION", "construct/r5-t3-battery", 14, 300 + revision,
		String(graph.graph_hash), dependency_hash
	)
	var matter := SourceRevision.create(
		"MATTER", "matter/r5-t3-battery-materials", 14, 1,
		String(graph.material_catalog.catalog_hash), dependency_hash
	)
	var frontier := Frontier.create([construction, matter])
	var authority := Authority.create(
		"server/fabric-r5",
		[
			{"source_domain": "CONSTRUCTION", "source_id": "construct/r5-t3-battery", "authority_epoch": 14, "owner_id": "server/fabric-r5"},
			{"source_domain": "MATTER", "source_id": "matter/r5-t3-battery-materials", "authority_epoch": 14, "owner_id": "server/fabric-r5"},
		],
		[
			U.source_key("CONSTRUCTION", "construct/r5-t3-battery"),
			U.source_key("MATTER", "matter/r5-t3-battery-materials"),
		]
	)
	var dependencies := Dependencies.create([
		{"dependency_id": "dependency/r5-t3-battery-compiler", "dependency_hash": U.canonical_hash({"version": COMPILER_VERSION})},
		{"dependency_id": "dependency/r5-t3-electrochemical-floor", "dependency_hash": U.canonical_hash({"profile_schema": Profile.SCHEMA})},
	])
	return {
		"artifact_id": "artifact/r5-t3-battery",
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
