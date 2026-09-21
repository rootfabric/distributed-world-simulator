extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterMaterial = preload("res://scripts/simulation/matter/contracts/matter_material_definition.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Graph = preload("res://scripts/research/fabric_bake0/gearbox_graph_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Dependencies = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")

const STAGES := 3
const GEAR_COUNT := 6
const TOOTH_COUNT := 232
const SOURCE_COMPONENT_COUNT := GEAR_COUNT + TOOTH_COUNT
const COMPILER_VERSION := "FABRIC_R5_2_T7_GEARBOX_COMPILER_R1"

static func _material(
	material_id: String,
	name: String,
	density: float,
	tensile: float,
	compressive: float,
	heat_capacity: float,
	thermal_conductivity: float,
	melting_k: float
) -> Dictionary:
	return MatterMaterial.create({
		"material_id": material_id,
		"display_name": name,
		"family": "matter-family/gear-material",
		"phase": "SOLID",
		"density_kg_m3": density,
		"hardness_pa": 2.0e9,
		"compressive_strength_pa": compressive,
		"tensile_strength_pa": tensile,
		"fracture_toughness_pa_m_sqrt": 2.0e6,
		"cohesion_pa": 1.0e8,
		"abrasiveness_ratio": 0.2,
		"porosity_ratio": 0.001,
		"permeability_m2": 1.0e-22,
		"heat_capacity_j_kg_k": heat_capacity,
		"thermal_conductivity_w_m_k": thermal_conductivity,
		"melting_temperature_k": melting_k,
		"vaporization_temperature_k": melting_k * 1.8,
		"mining_energy_j_kg": 8.0e5,
		"tags": ["matter-tag/mechanical", "matter-tag/gear"],
	})

static func material_catalog(reverse_input: bool = false) -> Dictionary:
	var materials: Array = [
		_material("matter/gear-steel", "Gear steel", 7850.0, 650.0e6, 900.0e6, 500.0, 45.0, 1750.0),
		_material("matter/gear-aluminum", "Gear aluminum", 2700.0, 300.0e6, 450.0e6, 900.0, 160.0, 900.0),
	]
	if reverse_input:
		materials.reverse()
	return MatterCatalog.create(materials, "matter-catalog/r5-t7-gearbox", "1.0.0")

static func make_graph(
	material_kind: String = "STEEL",
	weak_tooth: bool = false,
	disabled_tooth: bool = false,
	module_mismatch: bool = false,
	reverse_input: bool = false
) -> Dictionary:
	var catalog := material_catalog(reverse_input)
	var material_id := "matter/gear-aluminum" if material_kind == "ALUMINUM" else "matter/gear-steel"
	var specs := [
		{"stage": 0, "role": "DRIVER", "count": 20},
		{"stage": 0, "role": "DRIVEN", "count": 60},
		{"stage": 1, "role": "DRIVER", "count": 18},
		{"stage": 1, "role": "DRIVEN", "count": 54},
		{"stage": 2, "role": "DRIVER", "count": 16},
		{"stage": 2, "role": "DRIVEN", "count": 64},
	]
	var gears: Array = []
	var teeth: Array = []
	for spec in specs:
		var stage: int = int(spec.stage)
		var role: String = String(spec.role)
		var count: int = int(spec.count)
		var gear_id := "gear/s%02d-%s" % [stage, role.to_lower()]
		var module_m := 0.003
		if module_mismatch and stage == 1 and role == "DRIVEN":
			module_m = 0.00315
		gears.append({
			"gear_id": gear_id,
			"stage_index": stage,
			"role": role,
			"material_id": material_id,
			"tooth_count": count,
			"module_m": module_m,
			"face_width_m": 0.020,
			"body_thickness_m": 0.008,
			"quality_ratio": 0.97,
			"enabled": true,
		})
		for tooth_index in range(count):
			var quality := 0.96 + 0.01 * float(tooth_index % 4)
			var enabled := true
			if weak_tooth and stage == 1 and role == "DRIVEN" and tooth_index == 7:
				quality = 0.55
			if disabled_tooth and stage == 2 and role == "DRIVER" and tooth_index == 3:
				enabled = false
			teeth.append({
				"tooth_id": "tooth/s%02d-%s-%03d" % [stage, role.to_lower(), tooth_index],
				"gear_id": gear_id,
				"quality_ratio": quality,
				"enabled": enabled,
			})
	if reverse_input:
		gears.reverse()
		teeth.reverse()
	return Graph.create("graph/r5-t7-gearbox-3stage", catalog, gears, teeth)

static func build_request(graph: Dictionary, revision: int = 0) -> Dictionary:
	var dependency_hash := U.canonical_hash({"dependency": "r5-t7-gearbox"})
	var construction := SourceRevision.create(
		"CONSTRUCTION", "construct/r5-t7-gearbox", 18, 700 + revision,
		String(graph.graph_hash), dependency_hash
	)
	var matter := SourceRevision.create(
		"MATTER", "matter/r5-t7-gearbox-materials", 18, 1,
		String(graph.material_catalog.catalog_hash), dependency_hash
	)
	var frontier := Frontier.create([construction, matter])
	var authority := Authority.create(
		"server/fabric-r5",
		[
			{"source_domain": "CONSTRUCTION", "source_id": "construct/r5-t7-gearbox", "authority_epoch": 18, "owner_id": "server/fabric-r5"},
			{"source_domain": "MATTER", "source_id": "matter/r5-t7-gearbox-materials", "authority_epoch": 18, "owner_id": "server/fabric-r5"},
		],
		[
			U.source_key("CONSTRUCTION", "construct/r5-t7-gearbox"),
			U.source_key("MATTER", "matter/r5-t7-gearbox-materials"),
		]
	)
	var dependencies := Dependencies.create([
		{"dependency_id": "dependency/r5-t7-gearbox-compiler", "dependency_hash": U.canonical_hash({"version": COMPILER_VERSION})},
	])
	return {
		"artifact_id": "artifact/r5-t7-gearbox",
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
