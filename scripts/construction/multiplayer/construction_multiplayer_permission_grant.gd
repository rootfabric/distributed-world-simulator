extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")

const SCHEMA := "planet_simulator.construction_multiplayer_permission_grant.v1"
const ACTION_BUILD := "BUILD_STAGE"
const ACTION_EDIT := "EDIT_GEOMETRY"
const ACTION_DAMAGE := "APPLY_DAMAGE"
const ACTION_REPAIR := "APPLY_REPAIR"
const ACTION_READ := "READ_CONSTRUCTION"
const ACTIONS: Array[String] = [ACTION_BUILD, ACTION_DAMAGE, ACTION_EDIT, ACTION_READ, ACTION_REPAIR]
const FIELDS: Array[String] = ["schema", "grant_id", "subject_id", "construct_id", "allowed_actions", "issued_epoch", "expires_epoch", "metadata", "checksum"]

static func create(grant_id: String, subject_id: String, construct_id: String, allowed_actions: Array, issued_epoch: int, expires_epoch: int = 0, metadata: Dictionary = {}) -> Dictionary:
	var actions: Array = []
	for value in allowed_actions: actions.append(String(value))
	actions.sort()
	var result := {
		"schema": SCHEMA,
		"grant_id": grant_id,
		"subject_id": subject_id,
		"construct_id": construct_id,
		"allowed_actions": actions,
		"issued_epoch": issued_epoch,
		"expires_epoch": expires_epoch,
		"metadata": metadata.duplicate(true),
		"checksum": "",
	}
	result["checksum"] = compute_checksum(result)
	return result

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return ParametricUtils.failure("UNSUPPORTED_CONSTRUCTION_MULTIPLAYER_PERMISSION_SCHEMA")
	if not _path_id(String(value.get("grant_id", "")), "permission/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_PERMISSION_ID")
	if not _path_id(String(value.get("subject_id", "")), "client/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_PERMISSION_SUBJECT")
	var construct_id := String(value.get("construct_id", ""))
	if construct_id != "*" and not _path_id(construct_id, "construct/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_PERMISSION_TARGET")
	if typeof(value.get("allowed_actions")) != TYPE_ARRAY or Array(value["allowed_actions"]).is_empty(): return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_PERMISSION_ACTIONS")
	var actions: Array = []
	for action_value in value["allowed_actions"]:
		if typeof(action_value) != TYPE_STRING or not ACTIONS.has(String(action_value)): return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_PERMISSION_ACTION")
		actions.append(String(action_value))
	var sorted := actions.duplicate(); sorted.sort()
	if actions != sorted: return ParametricUtils.failure("NON_CANONICAL_CONSTRUCTION_MULTIPLAYER_PERMISSION_ACTIONS")
	var unique := {}; for action in actions:
		if unique.has(action): return ParametricUtils.failure("DUPLICATE_CONSTRUCTION_MULTIPLAYER_PERMISSION_ACTION")
		unique[action] = true
	for field in ["issued_epoch", "expires_epoch"]:
		if not UtilsScript.is_json_integer(value.get(field)) or int(value[field]) < 0: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_PERMISSION_EPOCH")
	if int(value["expires_epoch"]) > 0 and int(value["expires_epoch"]) < int(value["issued_epoch"]): return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_PERMISSION_EXPIRY")
	if typeof(value.get("metadata")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["metadata"]).get("success", false)): return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_PERMISSION_METADATA")
	if String(value.get("checksum", "")) != compute_checksum(value): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_PERMISSION_CHECKSUM_MISMATCH")
	return ParametricUtils.success()

static func authorizes(value: Dictionary, subject_id: String, construct_id: String, action: String, epoch: int) -> bool:
	return bool(validate(value).get("success", false)) \
		and String(value["subject_id"]) == subject_id \
		and (String(value["construct_id"]) == "*" or String(value["construct_id"]) == construct_id) \
		and Array(value["allowed_actions"]).has(action) \
		and int(value["issued_epoch"]) <= epoch \
		and (int(value["expires_epoch"]) == 0 or epoch <= int(value["expires_epoch"]))

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)

static func _path_id(value: String, prefix: String) -> bool:
	return value.begins_with(prefix) and value.length() > prefix.length() and value == value.strip_edges()
