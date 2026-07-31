extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")

const SCHEMA := "planet_simulator.construction_salvage_policy.v1"
const FIELDS: Array[String] = ["schema", "minimum_split_parts", "salvage_relation", "allow_destroyed_salvage", "checksum"]

static func create(minimum_split_parts: int = 2, salvage_relation: Dictionary = {}, allow_destroyed_salvage: bool = false) -> Dictionary:
	var relation := salvage_relation if not salvage_relation.is_empty() else ProjectionScript.world_relation()
	var value := {
		"schema": SCHEMA,
		"minimum_split_parts": minimum_split_parts,
		"salvage_relation": relation.duplicate(true),
		"allow_destroyed_salvage": allow_destroyed_salvage,
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_SALVAGE_POLICY_SCHEMA")
	if not UtilsScript.is_json_integer(value.get("minimum_split_parts")) or int(value["minimum_split_parts"]) < 1:
		return _failure("INVALID_CONSTRUCTION_SALVAGE_MINIMUM_SPLIT_PARTS")
	if typeof(value.get("salvage_relation")) != TYPE_DICTIONARY:
		return _failure("INVALID_CONSTRUCTION_SALVAGE_RELATION")
	var relation_validation := ProjectionScript.validate_relation(value["salvage_relation"])
	if not bool(relation_validation.get("success", false)): return relation_validation
	if String(value["salvage_relation"].get("kind", "")) not in [ProjectionScript.WORLD, ProjectionScript.CONTAINER]:
		return _failure("CONSTRUCTION_SALVAGE_RELATION_NOT_TRANSFERABLE")
	if typeof(value.get("allow_destroyed_salvage")) != TYPE_BOOL:
		return _failure("INVALID_CONSTRUCTION_DESTROYED_SALVAGE_FLAG")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value):
		return _failure("CONSTRUCTION_SALVAGE_POLICY_CHECKSUM_MISMATCH")
	return UtilsScript.validation_success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)

static func _failure(code: String) -> Dictionary:
	return UtilsScript.validation_failure(code, code)
