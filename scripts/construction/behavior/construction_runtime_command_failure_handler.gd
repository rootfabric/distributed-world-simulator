extends RefCounted

const POLICY_REQUIRE_ONLINE: String = "REQUIRE_ONLINE"
const POLICY_ALLOW_DEGRADED: String = "ALLOW_DEGRADED"
const POLICY_ALLOW_OFFLINE: String = "ALLOW_OFFLINE"

const OPERABILITY_ONLINE: String = "ONLINE"
const OPERABILITY_DEGRADED: String = "DEGRADED"
const OPERABILITY_OFFLINE: String = "OFFLINE"

const VALID_POLICIES: Array[String] = [
	POLICY_REQUIRE_ONLINE,
	POLICY_ALLOW_DEGRADED,
	POLICY_ALLOW_OFFLINE,
]

var _base_handler: Callable = Callable()
var _policy_by_action: Dictionary = {}
var _configured: bool = false


func setup(base_handler: Callable, policy_by_action: Dictionary) -> Dictionary:
	if not base_handler.is_valid():
		return _failure("CONSTRUCTION_RUNTIME_BASE_HANDLER_REQUIRED")
	if policy_by_action.is_empty():
		return _failure("CONSTRUCTION_RUNTIME_COMMAND_FAILURE_POLICY_REQUIRED")
	var canonical: Dictionary = {}
	for raw_action in policy_by_action:
		var action_kind: String = String(raw_action)
		var policy: String = String(policy_by_action[raw_action])
		if not _is_upper_kind(action_kind):
			return _failure("INVALID_CONSTRUCTION_RUNTIME_ACTION_KIND", {"action_kind": action_kind})
		if policy not in VALID_POLICIES:
			return _failure("INVALID_CONSTRUCTION_RUNTIME_COMMAND_FAILURE_POLICY", {
				"action_kind": action_kind,
				"policy": policy,
			})
		canonical[action_kind] = policy
	_base_handler = base_handler
	_policy_by_action = canonical
	_configured = true
	return _success({"action_count": _policy_by_action.size()})


func handle(command: Dictionary, subject: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_RUNTIME_COMMAND_FAILURE_HANDLER_NOT_CONFIGURED")
	var action_kind: String = String(command.get("action_kind", ""))
	if not _policy_by_action.has(action_kind):
		return _failure("CONSTRUCTION_RUNTIME_COMMAND_FAILURE_POLICY_MISSING", {
			"action_kind": action_kind,
			"runtime_id": String(subject.get("runtime_id", "")),
		})
	var state: Dictionary = Dictionary(subject.get("state", {}))
	var operability: String = String(state.get("operability", OPERABILITY_ONLINE))
	if operability not in [OPERABILITY_ONLINE, OPERABILITY_DEGRADED, OPERABILITY_OFFLINE]:
		return _failure("INVALID_CONSTRUCTION_RUNTIME_OPERABILITY", {
			"runtime_id": String(subject.get("runtime_id", "")),
			"operability": operability,
		})
	var policy: String = String(_policy_by_action[action_kind])
	var failure_codes: Array = Array(state.get("failure_codes", [])).duplicate(true)

	if operability == OPERABILITY_OFFLINE and policy != POLICY_ALLOW_OFFLINE:
		return _failure("CONSTRUCTION_RUNTIME_SUBJECT_OFFLINE", {
			"runtime_id": String(subject.get("runtime_id", "")),
			"action_kind": action_kind,
			"operability": operability,
			"policy": policy,
			"failure_codes": failure_codes,
		})
	if operability == OPERABILITY_DEGRADED and policy == POLICY_REQUIRE_ONLINE:
		return _failure("CONSTRUCTION_RUNTIME_SUBJECT_DEGRADED", {
			"runtime_id": String(subject.get("runtime_id", "")),
			"action_kind": action_kind,
			"operability": operability,
			"policy": policy,
			"failure_codes": failure_codes,
		})

	var handled_value = _base_handler.call(command.duplicate(true), subject.duplicate(true))
	if not handled_value is Dictionary:
		return _failure("CONSTRUCTION_RUNTIME_BASE_HANDLER_RESULT_INVALID")
	var handled: Dictionary = Dictionary(handled_value).duplicate(true)
	if not bool(handled.get("success", false)):
		return handled
	var details_value = handled.get("details", {})
	if not details_value is Dictionary:
		return _failure("CONSTRUCTION_RUNTIME_BASE_HANDLER_DETAILS_INVALID")
	var details: Dictionary = Dictionary(details_value).duplicate(true)
	details["runtime_operability"] = operability
	details["command_failure_policy"] = policy
	details["degraded_execution"] = operability == OPERABILITY_DEGRADED
	details["failure_codes"] = failure_codes
	handled["details"] = details
	return handled


func report() -> Dictionary:
	var actions: Array = _policy_by_action.keys()
	actions.sort()
	var rows: Array = []
	for action_kind in actions:
		rows.append({"action_kind": String(action_kind), "policy": String(_policy_by_action[action_kind])})
	return {
		"configured": _configured,
		"actions": rows,
		"policy_count": rows.size(),
		"mutates_canonical_state": false,
		"owns_operation_ledger": false,
		"owns_transaction_commit": false,
	}


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
