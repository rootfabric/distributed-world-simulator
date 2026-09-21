extends RefCounted
## Canonical-derived multi-stage gear train with explicit teeth.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")

const SCHEMA := "planet_simulator.fabric_gearbox_graph.v1"
const ROLES := ["DRIVER", "DRIVEN"]
const FIELDS: Array[String] = [
	"schema", "graph_id", "material_catalog", "gears", "teeth", "graph_hash", "checksum",
]
const GEAR_FIELDS: Array[String] = [
	"gear_id", "stage_index", "role", "material_id", "tooth_count",
	"module_m", "face_width_m", "body_thickness_m", "quality_ratio", "enabled",
]
const TOOTH_FIELDS: Array[String] = [
	"tooth_id", "gear_id", "quality_ratio", "enabled",
]

static func create(graph_id: String, material_catalog: Dictionary, gears: Array, teeth: Array) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"graph_id": graph_id,
		"material_catalog": material_catalog.duplicate(true),
		"gears": U.sorted_dicts(gears, "gear_id"),
		"teeth": U.sorted_dicts(teeth, "tooth_id"),
		"graph_hash": "",
		"checksum": "",
	}
	value.graph_hash = U.canonical_hash(_identity(value))
	value.checksum = U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA:
		return U.failure("UNSUPPORTED_GEARBOX_GRAPH_SCHEMA")
	if not U.is_canonical_id(value.get("graph_id"), 2):
		return U.failure("INVALID_GEARBOX_GRAPH_ID")
	if typeof(value.get("material_catalog")) != TYPE_DICTIONARY or not bool(MatterCatalog.validate(value.material_catalog).get("success", false)):
		return U.failure("INVALID_GEARBOX_MATERIAL_CATALOG")
	if typeof(value.get("gears")) != TYPE_ARRAY or value.gears.size() < 2:
		return U.failure("INVALID_GEARBOX_GEARS")
	var gear_ids := {}
	var stage_roles := {}
	var previous_gear := ""
	var max_stage := -1
	for index in range(value.gears.size()):
		var raw = value.gears[index]
		if typeof(raw) != TYPE_DICTIONARY:
			return U.failure("INVALID_GEARBOX_GEAR", {"index": index})
		var gear: Dictionary = raw
		checked = U.validate_exact_fields(gear, GEAR_FIELDS)
		if not checked.success:
			return checked
		if not U.is_canonical_id(gear.get("gear_id"), 2):
			return U.failure("INVALID_GEARBOX_GEAR_ID", {"index": index})
		if not U.is_json_integer(gear.get("stage_index")) or int(gear.stage_index) < 0:
			return U.failure("INVALID_GEARBOX_STAGE_INDEX", {"index": index})
		if not ROLES.has(String(gear.get("role", ""))):
			return U.failure("INVALID_GEARBOX_GEAR_ROLE", {"index": index})
		if MatterCatalog.material_by_id(value.material_catalog, String(gear.get("material_id", ""))).is_empty():
			return U.failure("GEARBOX_GEAR_MATERIAL_MISSING", {"index": index})
		if not U.is_json_integer(gear.get("tooth_count")) or int(gear.tooth_count) < 6:
			return U.failure("INVALID_GEARBOX_TOOTH_COUNT", {"index": index})
		for field in ["module_m", "face_width_m", "body_thickness_m", "quality_ratio"]:
			if not U.is_positive_number(gear.get(field)):
				return U.failure("INVALID_GEARBOX_GEAR_PROPERTY", {"index": index, "field": field})
		if float(gear.quality_ratio) > 1.0:
			return U.failure("INVALID_GEARBOX_GEAR_QUALITY", {"index": index})
		if typeof(gear.get("enabled")) != TYPE_BOOL:
			return U.failure("INVALID_GEARBOX_GEAR_ENABLED", {"index": index})
		var gear_id := String(gear.gear_id)
		if gear_ids.has(gear_id):
			return U.failure("GEARBOX_GEAR_ID_DUPLICATE", {"gear_id": gear_id})
		gear_ids[gear_id] = int(gear.tooth_count)
		var stage := int(gear.stage_index)
		max_stage = maxi(max_stage, stage)
		if not stage_roles.has(stage):
			stage_roles[stage] = {}
		var role := String(gear.role)
		if Dictionary(stage_roles[stage]).has(role):
			return U.failure("GEARBOX_STAGE_ROLE_DUPLICATE", {"stage": stage, "role": role})
		var roles: Dictionary = stage_roles[stage]
		roles[role] = gear_id
		stage_roles[stage] = roles
		if index > 0 and gear_id <= previous_gear:
			return U.failure("GEARBOX_GEARS_NOT_SORTED_UNIQUE")
		previous_gear = gear_id

	for stage in range(max_stage + 1):
		if not stage_roles.has(stage):
			return U.failure("GEARBOX_STAGE_GAP", {"stage": stage})
		var roles: Dictionary = stage_roles[stage]
		if not roles.has("DRIVER") or not roles.has("DRIVEN") or roles.size() != 2:
			return U.failure("GEARBOX_STAGE_INCOMPLETE", {"stage": stage})

	if typeof(value.get("teeth")) != TYPE_ARRAY or value.teeth.is_empty():
		return U.failure("INVALID_GEARBOX_TEETH")
	var tooth_counts := {}
	var previous_tooth := ""
	for index in range(value.teeth.size()):
		var raw_tooth = value.teeth[index]
		if typeof(raw_tooth) != TYPE_DICTIONARY:
			return U.failure("INVALID_GEARBOX_TOOTH", {"index": index})
		var tooth: Dictionary = raw_tooth
		checked = U.validate_exact_fields(tooth, TOOTH_FIELDS)
		if not checked.success:
			return checked
		if not U.is_canonical_id(tooth.get("tooth_id"), 2):
			return U.failure("INVALID_GEARBOX_TOOTH_ID", {"index": index})
		var owner := String(tooth.get("gear_id", ""))
		if not gear_ids.has(owner):
			return U.failure("GEARBOX_TOOTH_OWNER_MISSING", {"index": index})
		if not U.is_positive_number(tooth.get("quality_ratio")) or float(tooth.quality_ratio) > 1.0:
			return U.failure("INVALID_GEARBOX_TOOTH_QUALITY", {"index": index})
		if typeof(tooth.get("enabled")) != TYPE_BOOL:
			return U.failure("INVALID_GEARBOX_TOOTH_ENABLED", {"index": index})
		tooth_counts[owner] = int(tooth_counts.get(owner, 0)) + 1
		var tooth_id := String(tooth.tooth_id)
		if index > 0 and tooth_id <= previous_tooth:
			return U.failure("GEARBOX_TEETH_NOT_SORTED_UNIQUE")
		previous_tooth = tooth_id
	for gear_id in gear_ids.keys():
		if int(tooth_counts.get(gear_id, 0)) != int(gear_ids[gear_id]):
			return U.failure("GEARBOX_TOOTH_COVERAGE_MISMATCH", {"gear_id": gear_id})

	if not U.is_lower_hex_64(value.get("graph_hash")) or String(value.graph_hash) != U.canonical_hash(_identity(value)):
		return U.failure("GEARBOX_GRAPH_HASH_MISMATCH")
	return U.validate_checksum(value)

static func gear_by_stage_role(value: Dictionary, stage_index: int, role: String) -> Dictionary:
	for raw in value.get("gears", []):
		if int(raw.get("stage_index", -1)) == stage_index and String(raw.get("role", "")) == role:
			return Dictionary(raw).duplicate(true)
	return {}

static func teeth_for_gear(value: Dictionary, gear_id: String) -> Array:
	var output: Array = []
	for raw in value.get("teeth", []):
		if String(raw.get("gear_id", "")) == gear_id:
			output.append(Dictionary(raw).duplicate(true))
	return output

static func stage_count(value: Dictionary) -> int:
	var maximum := -1
	for raw in value.get("gears", []):
		maximum = maxi(maximum, int(raw.get("stage_index", -1)))
	return maximum + 1

static func _identity(value: Dictionary) -> Dictionary:
	return {
		"graph_id": value.graph_id,
		"material_catalog": value.material_catalog,
		"gears": value.gears,
		"teeth": value.teeth,
	}
