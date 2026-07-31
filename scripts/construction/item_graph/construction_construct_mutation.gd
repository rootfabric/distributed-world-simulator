extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")

const SCHEMA: String = "planet_simulator.construction_construct_mutation.v1"
const OP_CREATE: String = "CREATE"
const OP_UPDATE: String = "UPDATE"
const OP_DELETE: String = "DELETE"
const OPERATION_KINDS: Array[String] = [OP_CREATE, OP_UPDATE, OP_DELETE]
const FIELDS: Array[String] = ["schema", "operation_kind", "construct_id", "before_snapshot", "after_snapshot"]

static func create(
	operation_kind: String,
	construct_id: String,
	before_snapshot: Dictionary = {},
	after_snapshot: Dictionary = {}
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"operation_kind": operation_kind,
		"construct_id": construct_id,
		"before_snapshot": before_snapshot.duplicate(true),
		"after_snapshot": after_snapshot.duplicate(true),
	}

static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_CONSTRUCT_MUTATION_SCHEMA")
	var kind: String = String(value.get("operation_kind", ""))
	var construct_id: String = String(value.get("construct_id", ""))
	if not OPERATION_KINDS.has(kind):
		return _failure("INVALID_CONSTRUCTION_CONSTRUCT_OPERATION_KIND")
	if not construct_id.begins_with("construct/") or construct_id.length() <= 10:
		return _failure("INVALID_CONSTRUCTION_CONSTRUCT_ID")
	if typeof(value.get("before_snapshot")) != TYPE_DICTIONARY or typeof(value.get("after_snapshot")) != TYPE_DICTIONARY:
		return _failure("INVALID_CONSTRUCTION_CONSTRUCT_MUTATION_SNAPSHOTS")
	var before: Dictionary = value["before_snapshot"]
	var after: Dictionary = value["after_snapshot"]
	match kind:
		OP_CREATE:
			if not before.is_empty():
				return _failure("CREATE_CONSTRUCT_MUTATION_HAS_BEFORE_STATE")
			var after_validation: Dictionary = SnapshotScript.validate(after)
			if not bool(after_validation.get("success", false)):
				return after_validation
			if String(after["construct_id"]) != construct_id:
				return _failure("CREATED_CONSTRUCT_IDENTITY_MISMATCH")
		OP_UPDATE:
			var before_validation: Dictionary = SnapshotScript.validate(before)
			if not bool(before_validation.get("success", false)):
				return before_validation
			var after_validation: Dictionary = SnapshotScript.validate(after)
			if not bool(after_validation.get("success", false)):
				return after_validation
			if String(before["construct_id"]) != construct_id or String(after["construct_id"]) != construct_id:
				return _failure("UPDATED_CONSTRUCT_IDENTITY_MISMATCH")
			if int(after["state_revision"]) <= int(before["state_revision"]):
				return _failure("CONSTRUCT_MUTATION_REVISION_DID_NOT_ADVANCE")
		OP_DELETE:
			var before_validation: Dictionary = SnapshotScript.validate(before)
			if not bool(before_validation.get("success", false)):
				return before_validation
			if String(before["construct_id"]) != construct_id:
				return _failure("DELETED_CONSTRUCT_IDENTITY_MISMATCH")
			if not after.is_empty():
				return _failure("DELETE_CONSTRUCT_MUTATION_HAS_AFTER_STATE")
	return _success()

static func _success() -> Dictionary:
	return {"success": true, "error_code": "", "message": ""}

static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
