extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const MutationScript = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")

const SCHEMA: String = "planet_simulator.construction_construct_store.v1"
const FIELDS: Array[String] = ["schema", "constructs", "checksum"]

var _constructs: Dictionary = {}


func get_snapshot(construct_id: String) -> Dictionary:
	if not _constructs.has(construct_id):
		return {}
	return Dictionary(_constructs[construct_id]).duplicate(true)


func has_construct(construct_id: String) -> bool:
	return _constructs.has(construct_id)


func size() -> int:
	return _constructs.size()


func apply_mutation(mutation: Dictionary) -> Dictionary:
	var validation: Dictionary = MutationScript.validate(mutation)
	if not bool(validation.get("success", false)):
		return validation
	var construct_id: String = String(mutation["construct_id"])
	var before: Dictionary = mutation["before_snapshot"]
	match String(mutation["operation_kind"]):
		MutationScript.OP_CREATE:
			if _constructs.has(construct_id):
				return _failure("CONSTRUCT_STORE_CREATE_CONFLICT")
			_constructs[construct_id] = _canonical_dict(Dictionary(mutation["after_snapshot"]))
		MutationScript.OP_UPDATE:
			if not _constructs.has(construct_id) or UtilsScript.canonical_json(_constructs[construct_id]) != UtilsScript.canonical_json(before):
				return _failure("CONSTRUCT_STORE_UPDATE_PRECONDITION_FAILED")
			_constructs[construct_id] = _canonical_dict(Dictionary(mutation["after_snapshot"]))
		MutationScript.OP_DELETE:
			if not _constructs.has(construct_id) or UtilsScript.canonical_json(_constructs[construct_id]) != UtilsScript.canonical_json(before):
				return _failure("CONSTRUCT_STORE_DELETE_PRECONDITION_FAILED")
			_constructs.erase(construct_id)
		_:
			return _failure("CONSTRUCT_STORE_OPERATION_UNSUPPORTED")
	return _success()


func to_dict() -> Dictionary:
	var rows: Array = []
	var ids: Array = _constructs.keys()
	ids.sort()
	for construct_id in ids:
		rows.append(_canonical_dict(Dictionary(_constructs[construct_id])))
	var state: Dictionary = {
		"schema": SCHEMA,
		"constructs": rows,
		"checksum": "",
	}
	state["checksum"] = compute_checksum(state)
	return state


func load_dict(state: Dictionary) -> Dictionary:
	var validation: Dictionary = validate_state(state)
	if not bool(validation.get("success", false)):
		return validation
	var next: Dictionary = {}
	for snapshot in state["constructs"]:
		next[String(snapshot["construct_id"])] = _canonical_dict(Dictionary(snapshot))
	_constructs = next
	return _success({"construct_count": _constructs.size()})


func replace_from(other) -> void:
	assert(other != null)
	_constructs = other._constructs.duplicate(true)


static func validate_state(state: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(state, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if state.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCT_STORE_SCHEMA")
	if typeof(state.get("constructs")) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCT_STORE_ROWS")
	if typeof(state.get("checksum")) != TYPE_STRING or String(state["checksum"]) != compute_checksum(state):
		return _failure("CONSTRUCT_STORE_CHECKSUM_MISMATCH")
	var previous_id: String = ""
	var seen: Dictionary = {}
	for raw in state["constructs"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCT_STORE_ROW")
		var snapshot: Dictionary = raw
		var validation: Dictionary = SnapshotScript.validate(snapshot)
		if not bool(validation.get("success", false)):
			return validation
		var construct_id: String = String(snapshot["construct_id"])
		if seen.has(construct_id) or (not previous_id.is_empty() and construct_id < previous_id):
			return _failure("NON_CANONICAL_CONSTRUCT_STORE_ROWS")
		seen[construct_id] = true
		previous_id = construct_id
	if not bool(UtilsScript.canonicalize(state).get("success", false)):
		return _failure("CONSTRUCT_STORE_NOT_JSON_SAFE")
	return _success()


static func compute_checksum(state: Dictionary) -> String:
	var payload: Dictionary = state.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


static func _canonical_dict(value: Dictionary) -> Dictionary:
	var result: Dictionary = UtilsScript.canonicalize(value)
	if not bool(result.get("success", false)):
		return value.duplicate(true)
	return Dictionary(result.get("value", {}))


static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": false, "error_code": code, "message": code}
	for key in details:
		result[key] = details[key]
	return result
