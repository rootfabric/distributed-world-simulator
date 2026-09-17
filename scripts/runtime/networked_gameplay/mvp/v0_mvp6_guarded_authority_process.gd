extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_authority_process.gd"

const Guard6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_enet_long_operation_guard.gd")
const Protocol6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")

var _guard6_count := 0
var _guard6_last: Dictionary = {}
var _guard6_restore_count := 0
var _guard6_restore_last: Dictionary = {}
var _guard6_active := false


func handle_rpc(body: Dictionary) -> Dictionary:
	var kind := String(body.get("kind", ""))
	if not kind.begins_with("MVP6_"):
		return super.handle_rpc(body)
	var guarded: Dictionary = Guard6.apply(boundary, gateway_peer)
	if not bool(guarded.get("success", false)):
		return Protocol6.failure(String(guarded.get("error_code", "MVP6_ENET_GUARD_FAILED")))
	_guard6_count += 1
	_guard6_last = Dictionary(guarded.get("details", {})).duplicate(true)
	_guard6_active = true
	var result: Dictionary = super.handle_rpc(body)
	var restored: Dictionary = Guard6.restore(boundary, gateway_peer)
	if not bool(restored.get("success", false)):
		return Protocol6.failure(String(restored.get("error_code", "MVP6_ENET_GUARD_RESTORE_FAILED")))
	_guard6_restore_count += 1
	_guard6_restore_last = Dictionary(restored.get("details", {})).duplicate(true)
	_guard6_active = false
	return result


func report(passed: bool, phase: String) -> Dictionary:
	var value: Dictionary = super.report(passed, phase)
	value["mvp6_transport_guard"] = {
		"apply_count": _guard6_count,
		"last": _guard6_last.duplicate(true),
		"restore_count": _guard6_restore_count,
		"restore_last": _guard6_restore_last.duplicate(true),
		"active": _guard6_active,
		"restored_after_each_rpc": _guard6_count > 0 and _guard6_restore_count == _guard6_count and not _guard6_active,
		"restored_before_finish": _guard6_count > 0 and _guard6_restore_count == _guard6_count and not _guard6_active,
		"shared_transport_changed": false,
		"payload_limit_changed": false,
		"reconnect_policy_changed": false,
	}
	return value
