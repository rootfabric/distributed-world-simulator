extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")

const SCHEMA := "planet_simulator.construction_structural_load_case.v1"
const FIELDS: Array[String] = [
	"schema", "load_case_id", "construct_id", "source_snapshot_checksum", "gravity_m_s2",
	"support_part_ids", "external_part_loads_n", "safety_factor", "degraded_capacity_factor",
	"collapse_utilization", "maximum_cascade_steps", "minimum_split_parts", "salvage_relation", "checksum",
]

static func create(
	load_case_id: String,
	construct_id: String,
	source_snapshot_checksum: String,
	gravity_m_s2: float,
	support_part_ids: Array,
	external_part_loads_n: Dictionary = {},
	safety_factor: float = 1.0,
	degraded_capacity_factor: float = 0.5,
	collapse_utilization: float = 1.5,
	maximum_cascade_steps: int = 16,
	minimum_split_parts: int = 2,
	salvage_relation: Dictionary = {}
) -> Dictionary:
	var relation := ProjectionScript.world_relation() if salvage_relation.is_empty() else salvage_relation.duplicate(true)
	var value := {
		"schema": SCHEMA,
		"load_case_id": load_case_id,
		"construct_id": construct_id,
		"source_snapshot_checksum": source_snapshot_checksum,
		"gravity_m_s2": gravity_m_s2,
		"support_part_ids": _sorted_strings(support_part_ids),
		"external_part_loads_n": _sorted_dictionary(external_part_loads_n),
		"safety_factor": safety_factor,
		"degraded_capacity_factor": degraded_capacity_factor,
		"collapse_utilization": collapse_utilization,
		"maximum_cascade_steps": maximum_cascade_steps,
		"minimum_split_parts": minimum_split_parts,
		"salvage_relation": relation,
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_STRUCTURAL_LOAD_CASE_SCHEMA")
	if not _path_id(String(value.get("load_case_id", "")), "load-case/"): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_LOAD_CASE_ID")
	if not _path_id(String(value.get("construct_id", "")), "construct/"): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_CONSTRUCT_ID")
	if not _hex64(String(value.get("source_snapshot_checksum", ""))): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_SOURCE_CHECKSUM")
	if not _positive_finite(value.get("gravity_m_s2")): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_GRAVITY")
	if typeof(value.get("support_part_ids")) != TYPE_ARRAY or Array(value["support_part_ids"]).is_empty() or value["support_part_ids"] != _sorted_strings(value["support_part_ids"]):
		return _failure("INVALID_CONSTRUCTION_STRUCTURAL_SUPPORT_PARTS")
	var support_seen := {}
	for raw_id in value["support_part_ids"]:
		if typeof(raw_id) != TYPE_STRING or not _path_id(String(raw_id), "part/") or support_seen.has(raw_id): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_SUPPORT_PART")
		support_seen[raw_id] = true
	if typeof(value.get("external_part_loads_n")) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_EXTERNAL_LOADS")
	var load_keys: Array = value["external_part_loads_n"].keys()
	var sorted_keys := load_keys.duplicate(); sorted_keys.sort()
	if load_keys != sorted_keys: return _failure("NON_CANONICAL_CONSTRUCTION_STRUCTURAL_EXTERNAL_LOADS")
	for raw_key in load_keys:
		if typeof(raw_key) != TYPE_STRING or not _path_id(String(raw_key), "part/"): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_EXTERNAL_LOAD_PART")
		if not _non_negative_finite(value["external_part_loads_n"][raw_key]): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_EXTERNAL_LOAD")
	if not _positive_finite(value.get("safety_factor")) or float(value["safety_factor"]) < 1.0: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_SAFETY_FACTOR")
	if not _positive_finite(value.get("degraded_capacity_factor")) or float(value["degraded_capacity_factor"]) > 1.0: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_DEGRADED_CAPACITY_FACTOR")
	if not _positive_finite(value.get("collapse_utilization")) or float(value["collapse_utilization"]) <= 1.0: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_COLLAPSE_UTILIZATION")
	if not UtilsScript.is_json_integer(value.get("maximum_cascade_steps")) or int(value["maximum_cascade_steps"]) < 1 or int(value["maximum_cascade_steps"]) > 128:
		return _failure("INVALID_CONSTRUCTION_STRUCTURAL_MAXIMUM_CASCADE_STEPS")
	if not UtilsScript.is_json_integer(value.get("minimum_split_parts")) or int(value["minimum_split_parts"]) < 1:
		return _failure("INVALID_CONSTRUCTION_STRUCTURAL_MINIMUM_SPLIT_PARTS")
	if typeof(value.get("salvage_relation")) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_SALVAGE_RELATION")
	var relation_validation := ProjectionScript.validate_relation(value["salvage_relation"])
	if not bool(relation_validation.get("success", false)): return relation_validation
	if String(value["salvage_relation"].get("kind", "")) not in [ProjectionScript.WORLD, ProjectionScript.CONTAINER]: return _failure("CONSTRUCTION_STRUCTURAL_SALVAGE_RELATION_NOT_TRANSFERABLE")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_STRUCTURAL_LOAD_CASE_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)): return _failure("CONSTRUCTION_STRUCTURAL_LOAD_CASE_NOT_JSON_SAFE")
	return UtilsScript.validation_success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)

static func _sorted_strings(values: Array) -> Array:
	var output := values.duplicate(); output.sort(); return output
static func _sorted_dictionary(value: Dictionary) -> Dictionary:
	var output := {}; var keys := value.keys(); keys.sort(); for key in keys: output[key] = value[key]
	return output
static func _positive_finite(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and not is_nan(float(value)) and not is_inf(float(value)) and float(value) > 0.0
static func _non_negative_finite(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and not is_nan(float(value)) and not is_inf(float(value)) and float(value) >= 0.0
static func _path_id(value: String, prefix: String) -> bool:
	if not value.begins_with(prefix) or value.length() <= prefix.length() or value != value.to_lower() or value.contains("//"): return false
	for segment in value.split("/", true):
		if segment.is_empty(): return false
		for character in segment:
			if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_": return false
	return true
static func _hex64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower(): return false
	for character in value:
		if not String(character) in "0123456789abcdef": return false
	return true
static func _failure(code: String) -> Dictionary:
	return UtilsScript.validation_failure(code, code)
