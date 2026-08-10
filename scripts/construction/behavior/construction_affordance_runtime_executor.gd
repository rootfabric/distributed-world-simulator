extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const FingerprintScript = preload("res://scripts/items/services/item_operation_fingerprint.gd")
const OperationLedgerScript = preload("res://scripts/items/services/item_operation_ledger.gd")

const COMMAND_SCHEMA: String = "planet_simulator.construction_affordance_runtime_command.v1"
const COMMAND_FIELDS: Array[String] = [
	"schema",
	"operation_id",
	"action_kind",
	"runtime_id",
	"expected_revision",
	"payload",
]

var _store
var _ledger
var _handler: Callable
var _effect_committer: Callable = Callable()
var _configured: bool = false


func setup(store, ledger, handler: Callable, effect_committer: Callable = Callable()) -> Dictionary:
	if store == null or not store.has_method("get_subject") or not store.has_method("update_subject"):
		return _failure("CONSTRUCTION_RUNTIME_STATE_STORE_REQUIRED")
	if ledger == null or not ledger.has_method("resolve") or not ledger.has_method("remember_terminal"):
		return _failure("CONSTRUCTION_RUNTIME_OPERATION_LEDGER_REQUIRED")
	if not handler.is_valid():
		return _failure("CONSTRUCTION_RUNTIME_HANDLER_REQUIRED")
	if effect_committer.is_valid() and (not store.has_method("to_dict") or not store.has_method("load_dict")):
		return _failure("CONSTRUCTION_RUNTIME_TRANSACTIONAL_STATE_STORE_REQUIRED")
	_store = store
	_ledger = ledger
	_handler = handler
	_effect_committer = effect_committer
	_configured = true
	return _success()


static func create_command(
	operation_id: String,
	action_kind: String,
	runtime_id: String,
	expected_revision: int,
	payload: Dictionary = {}
) -> Dictionary:
	return {
		"schema": COMMAND_SCHEMA,
		"operation_id": operation_id,
		"action_kind": action_kind,
		"runtime_id": runtime_id,
		"expected_revision": expected_revision,
		"payload": payload.duplicate(true),
	}


static func validate_command(command: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(command, COMMAND_FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if command.get("schema") != COMMAND_SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_RUNTIME_COMMAND_SCHEMA")
	if not _is_path(String(command.get("operation_id", "")), "operation/"):
		return _failure("INVALID_CONSTRUCTION_RUNTIME_OPERATION_ID")
	if not _is_upper_kind(String(command.get("action_kind", ""))):
		return _failure("INVALID_CONSTRUCTION_RUNTIME_ACTION_KIND")
	if not _is_path(String(command.get("runtime_id", "")), "runtime/"):
		return _failure("INVALID_CONSTRUCTION_RUNTIME_COMMAND_TARGET")
	if not UtilsScript.is_json_integer(command.get("expected_revision")) or int(command["expected_revision"]) < 0:
		return _failure("INVALID_CONSTRUCTION_RUNTIME_EXPECTED_REVISION")
	if typeof(command.get("payload")) != TYPE_DICTIONARY:
		return _failure("INVALID_CONSTRUCTION_RUNTIME_COMMAND_PAYLOAD")
	var canonical: Dictionary = UtilsScript.canonicalize(command["payload"])
	if not bool(canonical.get("success", false)):
		return _failure("CONSTRUCTION_RUNTIME_COMMAND_PAYLOAD_NOT_JSON_SAFE")
	return _success()


func execute(command: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_RUNTIME_EXECUTOR_NOT_CONFIGURED")
	var validation: Dictionary = validate_command(command)
	if not bool(validation.get("success", false)):
		return validation
	var operation_id: String = String(command["operation_id"])
	var action_kind: String = String(command["action_kind"])
	var runtime_id: String = String(command["runtime_id"])
	var expected_revision: int = int(command["expected_revision"])
	var command_type := "CONSTRUCTION_AFFORDANCE_%s" % action_kind
	var fingerprint: Dictionary = FingerprintScript.build(
		command_type,
		runtime_id,
		expected_revision,
		Dictionary(command["payload"])
	)
	if not bool(fingerprint.get("success", false)):
		return _failure("CONSTRUCTION_RUNTIME_PAYLOAD_FINGERPRINT_FAILED", {"cause": fingerprint})
	var payload_hash: String = String(fingerprint["payload_hash"])
	var resolved: Dictionary = _ledger.resolve(
		operation_id,
		command_type,
		payload_hash,
		runtime_id,
		expected_revision
	)
	if bool(resolved.get("found", false)):
		return Dictionary(resolved.get("result", {})).duplicate(true)

	var subject: Dictionary = _store.get_subject(runtime_id)
	if subject.is_empty():
		return _remember_rejected(
			operation_id, command_type, payload_hash, runtime_id, expected_revision, -1,
			"CONSTRUCTION_RUNTIME_SUBJECT_NOT_FOUND"
		)
	var current_revision: int = int(subject.get("revision", -1))
	if current_revision != expected_revision:
		return _remember_rejected(
			operation_id, command_type, payload_hash, runtime_id, expected_revision, current_revision,
			"CONSTRUCTION_RUNTIME_REVISION_MISMATCH",
			{"current_revision": current_revision}
		)

	var handled_value = _handler.call(command.duplicate(true), subject.duplicate(true))
	if not handled_value is Dictionary:
		return _remember_rejected(
			operation_id, command_type, payload_hash, runtime_id, expected_revision, current_revision,
			"CONSTRUCTION_RUNTIME_HANDLER_RESULT_INVALID"
		)
	var handled: Dictionary = handled_value
	if not bool(handled.get("success", false)):
		return _remember_rejected(
			operation_id, command_type, payload_hash, runtime_id, expected_revision, current_revision,
			String(handled.get("error_code", "CONSTRUCTION_RUNTIME_ACTION_REJECTED")),
			Dictionary(handled.get("details", {}))
		)

	var mutates: bool = bool(handled.get("mutates", false))
	var has_effect := handled.has("effect")
	var effect: Dictionary = {}
	if has_effect:
		var effect_value = handled.get("effect")
		if not effect_value is Dictionary:
			return _remember_rejected(
				operation_id, command_type, payload_hash, runtime_id, expected_revision, current_revision,
				"CONSTRUCTION_RUNTIME_EFFECT_INVALID"
			)
		if not mutates:
			return _remember_rejected(
				operation_id, command_type, payload_hash, runtime_id, expected_revision, current_revision,
				"CONSTRUCTION_RUNTIME_EFFECT_REQUIRES_MUTATION"
			)
		if not _effect_committer.is_valid():
			return _remember_rejected(
				operation_id, command_type, payload_hash, runtime_id, expected_revision, current_revision,
				"CONSTRUCTION_RUNTIME_EFFECT_COMMITTER_REQUIRED"
			)
		effect = Dictionary(effect_value).duplicate(true)

	var result_revision := current_revision
	var after: Dictionary = subject.duplicate(true)
	var store_before: Dictionary = {}
	if mutates:
		if has_effect:
			store_before = _store.to_dict()
		var next_state_value = handled.get("next_state", {})
		if not next_state_value is Dictionary:
			return _remember_rejected(
				operation_id, command_type, payload_hash, runtime_id, expected_revision, current_revision,
				"CONSTRUCTION_RUNTIME_NEXT_STATE_REQUIRED"
			)
		var updated: Dictionary = _store.update_subject(runtime_id, expected_revision, Dictionary(next_state_value))
		if not bool(updated.get("success", false)):
			return _remember_rejected(
				operation_id, command_type, payload_hash, runtime_id, expected_revision, current_revision,
				String(updated.get("error_code", "CONSTRUCTION_RUNTIME_STATE_UPDATE_FAILED")),
				Dictionary(updated.get("details", {}))
			)
		after = Dictionary(updated["after"])
		result_revision = int(after["revision"])

	if has_effect:
		var committed_value = _effect_committer.call(
			command.duplicate(true),
			subject.duplicate(true),
			after.duplicate(true),
			effect.duplicate(true)
		)
		var committed: Dictionary = Dictionary(committed_value) if committed_value is Dictionary else _failure("CONSTRUCTION_RUNTIME_EFFECT_COMMIT_RESULT_INVALID")
		if not bool(committed.get("success", false)):
			var rollback: Dictionary = _store.load_dict(store_before)
			if not bool(rollback.get("success", false)):
				return _failure("CONSTRUCTION_RUNTIME_EFFECT_ROLLBACK_FAILED", {
					"cause": committed,
					"rollback": rollback,
					"runtime_id": runtime_id,
					"operation_id": operation_id,
				})
			return _remember_rejected(
				operation_id, command_type, payload_hash, runtime_id, expected_revision, current_revision,
				String(committed.get("error_code", "CONSTRUCTION_RUNTIME_EFFECT_COMMIT_FAILED")),
				{"cause": committed, "runtime_state_rolled_back": true}
			)

	var details: Dictionary = Dictionary(handled.get("details", {})).duplicate(true)
	details["runtime_id"] = runtime_id
	details["action_kind"] = action_kind
	details["mutated"] = mutates
	details["subject"] = after.duplicate(true)
	details["transactional_effect_committed"] = has_effect
	return _ledger.remember_terminal(
		operation_id,
		command_type,
		payload_hash,
		runtime_id,
		expected_revision,
		result_revision,
		OperationLedgerScript.STATUS_SUCCEEDED,
		{"success": true, "error_code": "", "details": details}
	)


func _remember_rejected(
	operation_id: String,
	command_type: String,
	payload_hash: String,
	runtime_id: String,
	expected_revision: int,
	result_revision: int,
	error_code: String,
	details: Dictionary = {}
) -> Dictionary:
	return _ledger.remember_terminal(
		operation_id,
		command_type,
		payload_hash,
		runtime_id,
		expected_revision,
		result_revision,
		OperationLedgerScript.STATUS_REJECTED,
		{"success": false, "error_code": error_code, "details": details.duplicate(true)}
	)


static func _is_path(value: String, prefix: String) -> bool:
	if not value.begins_with(prefix) or value.length() <= prefix.length() or value != value.to_lower() or value.contains("//"):
		return false
	for segment in value.split("/", true):
		if segment.is_empty():
			return false
		for character in segment:
			if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_":
				return false
	return true


static func _is_upper_kind(value: String) -> bool:
	if value.is_empty() or value != value.to_upper():
		return false
	for character in value:
		if not String(character) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_":
			return false
	return true


static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
