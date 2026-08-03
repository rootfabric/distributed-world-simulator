extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")

const SCHEMA: String = "planet_simulator.construction_ghost_state.v1"
const STATUS_GHOST: String = "GHOST"
const STATUS_IN_PROGRESS: String = "IN_PROGRESS"
const STATUS_COMPLETE: String = "COMPLETE"
const STATUS_CANCELLED: String = "CANCELLED"
const STATUSES: Array[String] = [STATUS_GHOST, STATUS_IN_PROGRESS, STATUS_COMPLETE, STATUS_CANCELLED]
const FIELDS: Array[String] = [
	"schema",
	"ghost_id",
	"build_plan_id",
	"build_plan_checksum",
	"construct_id",
	"root_item_instance_id",
	"relation",
	"status",
	"next_stage_index",
	"completed_stage_ids",
	"completed_operation_ids",
	"completed_transaction_checksums",
	"state_revision",
	"checksum",
]


static func create(build_plan: Dictionary) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"ghost_id": "ghost/%s" % String(build_plan.get("build_plan_id", "")).trim_prefix("build-plan/"),
		"build_plan_id": String(build_plan.get("build_plan_id", "")),
		"build_plan_checksum": String(build_plan.get("checksum", "")),
		"construct_id": String(build_plan.get("construct_id", "")),
		"root_item_instance_id": String(build_plan.get("root_item_instance_id", "")),
		"relation": Dictionary(build_plan.get("ghost_relation", {})).duplicate(true),
		"status": STATUS_GHOST,
		"next_stage_index": 0,
		"completed_stage_ids": [],
		"completed_operation_ids": [],
		"completed_transaction_checksums": [],
		"state_revision": 0,
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_GHOST_STATE_SCHEMA")
	if not _is_identifier(String(value.get("ghost_id", "")), "ghost/"):
		return _failure("INVALID_CONSTRUCTION_GHOST_ID")
	if not _is_identifier(String(value.get("build_plan_id", "")), "build-plan/"):
		return _failure("INVALID_CONSTRUCTION_GHOST_BUILD_PLAN_ID")
	if not _is_sha256(String(value.get("build_plan_checksum", ""))):
		return _failure("INVALID_CONSTRUCTION_GHOST_BUILD_PLAN_CHECKSUM")
	if not _is_identifier(String(value.get("construct_id", "")), "construct/"):
		return _failure("INVALID_CONSTRUCTION_GHOST_CONSTRUCT_ID")
	if not _is_identifier(String(value.get("root_item_instance_id", "")), "item/"):
		return _failure("INVALID_CONSTRUCTION_GHOST_ROOT_ITEM_ID")
	if typeof(value.get("relation")) != TYPE_DICTIONARY:
		return _failure("INVALID_CONSTRUCTION_GHOST_RELATION")
	var relation_validation: Dictionary = ProjectionScript.validate_relation(value["relation"])
	if not bool(relation_validation.get("success", false)):
		return relation_validation
	if String(value["relation"].get("kind", "")) != ProjectionScript.WORLD:
		return _failure("CONSTRUCTION_GHOST_RELATION_MUST_BE_WORLD")
	var status: String = String(value.get("status", ""))
	if not STATUSES.has(status):
		return _failure("INVALID_CONSTRUCTION_GHOST_STATUS")
	if not UtilsScript.is_json_integer(value.get("next_stage_index")) or int(value["next_stage_index"]) < 0:
		return _failure("INVALID_CONSTRUCTION_GHOST_STAGE_INDEX")
	if not UtilsScript.is_json_integer(value.get("state_revision")) or int(value["state_revision"]) < 0:
		return _failure("INVALID_CONSTRUCTION_GHOST_REVISION")
	for field in ["completed_stage_ids", "completed_operation_ids", "completed_transaction_checksums"]:
		if typeof(value.get(field)) != TYPE_ARRAY:
			return _failure("INVALID_CONSTRUCTION_GHOST_COMPLETION_COLLECTION")
	var stage_ids: Array = value["completed_stage_ids"]
	var operation_ids: Array = value["completed_operation_ids"]
	var transaction_checksums: Array = value["completed_transaction_checksums"]
	if stage_ids.size() != operation_ids.size() or stage_ids.size() != transaction_checksums.size():
		return _failure("CONSTRUCTION_GHOST_COMPLETION_COLLECTION_SIZE_MISMATCH")
	if stage_ids.size() != int(value["next_stage_index"]):
		return _failure("CONSTRUCTION_GHOST_PROGRESS_INDEX_MISMATCH")
	var seen_stages: Dictionary = {}
	var seen_operations: Dictionary = {}
	for index in range(stage_ids.size()):
		var stage_id: String = String(stage_ids[index])
		var operation_id: String = String(operation_ids[index])
		var transaction_checksum: String = String(transaction_checksums[index])
		if not _is_identifier(stage_id, "stage/") or seen_stages.has(stage_id):
			return _failure("INVALID_CONSTRUCTION_GHOST_COMPLETED_STAGE")
		seen_stages[stage_id] = true
		if not operation_id.is_empty():
			if not _is_identifier(operation_id, "operation/") or seen_operations.has(operation_id):
				return _failure("INVALID_CONSTRUCTION_GHOST_COMPLETED_OPERATION")
			seen_operations[operation_id] = true
		if not transaction_checksum.is_empty() and not _is_sha256(transaction_checksum):
			return _failure("INVALID_CONSTRUCTION_GHOST_TRANSACTION_CHECKSUM")
		if operation_id.is_empty() != transaction_checksum.is_empty():
			return _failure("CONSTRUCTION_GHOST_OPERATION_CHECKSUM_PAIR_MISMATCH")
	if status == STATUS_GHOST and (int(value["next_stage_index"]) != 0 or not stage_ids.is_empty()):
		return _failure("CONSTRUCTION_GHOST_STATUS_PROGRESS_MISMATCH")
	if status == STATUS_CANCELLED and int(value["next_stage_index"]) != 0:
		return _failure("CANCELLED_CONSTRUCTION_GHOST_HAS_PROGRESS")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value):
		return _failure("CONSTRUCTION_GHOST_STATE_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("CONSTRUCTION_GHOST_STATE_NOT_JSON_SAFE")
	return _success()


static func with_progress(
	ghost: Dictionary,
	completed_stage_ids: Array,
	completed_operation_ids: Array,
	completed_transaction_checksums: Array,
	stage_count: int
) -> Dictionary:
	var value: Dictionary = ghost.duplicate(true)
	value["completed_stage_ids"] = completed_stage_ids.duplicate(true)
	value["completed_operation_ids"] = completed_operation_ids.duplicate(true)
	value["completed_transaction_checksums"] = completed_transaction_checksums.duplicate(true)
	value["next_stage_index"] = completed_stage_ids.size()
	if completed_stage_ids.is_empty():
		value["status"] = STATUS_GHOST
	elif completed_stage_ids.size() >= stage_count:
		value["status"] = STATUS_COMPLETE
	else:
		value["status"] = STATUS_IN_PROGRESS
	value["state_revision"] = int(ghost.get("state_revision", 0)) + 1
	value["checksum"] = ""
	value["checksum"] = compute_checksum(value)
	return value


static func cancelled(ghost: Dictionary) -> Dictionary:
	var value: Dictionary = ghost.duplicate(true)
	value["status"] = STATUS_CANCELLED
	value["state_revision"] = int(ghost.get("state_revision", 0)) + 1
	value["checksum"] = ""
	value["checksum"] = compute_checksum(value)
	return value


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


static func _is_identifier(value: String, prefix: String) -> bool:
	return value.begins_with(prefix) and value.length() > prefix.length() and value == value.strip_edges()


static func _is_sha256(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]:
			return false
	return true


static func _success() -> Dictionary:
	return {"success": true, "error_code": "", "message": ""}


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
