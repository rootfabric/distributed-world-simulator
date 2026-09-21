extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterMaterial = preload("res://scripts/simulation/matter/contracts/matter_material_definition.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Profile = preload("res://scripts/research/fabric_bake0/power_stage_semiconductor_profile_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/power_stage_graph_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Dependencies = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")

const BANKS := 4
const DIES_PER_BANK := 64
const DIE_COUNT := BANKS * DIES_PER_BANK
const COMPILER_VERSION := "FABRIC_R5_2_T6_POWER_STAGE_COMPILER_R1"

static func _material(
	material_id: String,
	name: String,
	family: String,
	density: float,
	heat_capacity: float,
	thermal_conductivity: float,
	melting_k: float,
	vaporization_k: float
) -> Dictionary:
	return MatterMaterial.create({
		"material_id": material_id,
		"display_name": name,
		"family": family,
		"phase": "SOLID",
		"density_kg_m3": density,
		"hardness_pa": 1.0e9,
		"compressive_strength_pa": 1.0e9,
		"tensile_strength_pa": 2.0e8,
		"fracture_toughness_pa_m_sqrt": 1.0e6,
		"cohesion_pa": 1.0e8,
		"abrasiveness_ratio": 0.2,
		"porosity_ratio": 0.001,
		"permeability_m2": 1.0e-22,
		"heat_capacity_j_kg_k": heat_capacity,
		"thermal_conductivity_w_m_k": thermal_conductivity,
		"melting_temperature_k": melting_k,
		"vaporization_temperature_k": vaporization_k,
		"mining_energy_j_kg": 1.0e6,
		"tags": ["matter-tag/electrical", "matter-tag/power-semiconductor"],
	})

static func material_catalog(reverse_input: bool = false) -> Dictionary:
	var materials: Array = [
		_material("matter/power-sic", "Power SiC effective die", "matter-family/semiconductor", 3210.0, 750.0, 120.0, 3000.0, 4200.0),
		_material("matter/power-si", "Power silicon effective die", "matter-family/semiconductor", 2330.0, 700.0, 150.0, 1687.0, 3538.0),
	]
	if reverse_input:
		materials.reverse()
	return MatterCatalog.create(materials, "matter-catalog/r5-t6-power-stage", "1.0.0")

static func profiles(catalog: Dictionary, reverse_input: bool = false) -> Array:
	var sic := MatterCatalog.material_by_id(catalog, "matter/power-sic")
	var si := MatterCatalog.material_by_id(catalog, "matter/power-si")
	var values: Array = [
		Profile.create("profile/power-sic-characterized", sic, 2.0e-3, 5.0e5, 80.0e-9, 0.0040, 300.0, 250.0, 450.0, 800.0),
		Profile.create("profile/power-si-characterized", si, 3.0e-3, 4.0e5, 150.0e-9, 0.0050, 300.0, 250.0, 425.0, 650.0),
	]
	if reverse_input:
		values.reverse()
	return values

static func make_graph(
	kind: String = "SIC",
	damage_one_die: bool = false,
	unsafe_geometry: bool = false,
	mixed_profile: bool = false,
	open_bank: bool = false,
	reverse_input: bool = false
) -> Dictionary:
	var catalog := material_catalog(reverse_input)
	var profile_values := profiles(catalog, reverse_input)
	var selected := "profile/power-si-characterized" if kind == "SI" else "profile/power-sic-characterized"
	var quality_pattern := [0.94, 0.96, 0.98, 1.0, 0.95, 0.97, 0.99, 0.93]
	var dies: Array = []
	for bank in range(BANKS):
		for lane in range(DIES_PER_BANK):
			var profile_id := selected
			if mixed_profile and bank == 0 and lane == 3:
				profile_id = "profile/power-si-characterized" if selected == "profile/power-sic-characterized" else "profile/power-sic-characterized"
			var path_length := 2.0e-4
			if unsafe_geometry and bank == 0 and lane == 5:
				path_length *= 1.07
			var enabled := true
			if damage_one_die and bank == 0 and lane == 9:
				enabled = false
			if open_bank and bank == 2:
				enabled = false
			dies.append({
				"die_id": "switch/b%02d-d%03d" % [bank, lane],
				"bank_index": bank,
				"profile_id": profile_id,
				"current_path_length_m": path_length,
				"active_area_m2": 2.0e-5,
				"quality_ratio": float(quality_pattern[lane % quality_pattern.size()]),
				"enabled": enabled,
			})
	if reverse_input:
		dies.reverse()
	return Graph.create(
		"graph/r5-t6-power-stage-4x64",
		catalog,
		profile_values,
		dies
	)

static func build_request(graph: Dictionary, revision: int = 0) -> Dictionary:
	var dependency_hash := U.canonical_hash({"dependency": "r5-t6-power-stage"})
	var construction := SourceRevision.create(
		"CONSTRUCTION", "construct/r5-t6-power-stage", 17, 600 + revision,
		String(graph.graph_hash), dependency_hash
	)
	var matter := SourceRevision.create(
		"MATTER", "matter/r5-t6-power-stage-materials", 17, 1,
		String(graph.material_catalog.catalog_hash), dependency_hash
	)
	var frontier := Frontier.create([construction, matter])
	var authority := Authority.create(
		"server/fabric-r5",
		[
			{"source_domain": "CONSTRUCTION", "source_id": "construct/r5-t6-power-stage", "authority_epoch": 17, "owner_id": "server/fabric-r5"},
			{"source_domain": "MATTER", "source_id": "matter/r5-t6-power-stage-materials", "authority_epoch": 17, "owner_id": "server/fabric-r5"},
		],
		[
			U.source_key("CONSTRUCTION", "construct/r5-t6-power-stage"),
			U.source_key("MATTER", "matter/r5-t6-power-stage-materials"),
		]
	)
	var dependencies := Dependencies.create([
		{"dependency_id": "dependency/r5-t6-power-stage-compiler", "dependency_hash": U.canonical_hash({"version": COMPILER_VERSION})},
		{"dependency_id": "dependency/r5-t6-semiconductor-floor", "dependency_hash": U.canonical_hash({"profile_schema": Profile.SCHEMA})},
	])
	return {
		"artifact_id": "artifact/r5-t6-power-stage",
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
