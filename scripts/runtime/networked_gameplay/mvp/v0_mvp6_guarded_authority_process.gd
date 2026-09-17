extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_authority_process.gd"

const Guard6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_enet_long_operation_guard.gd")
const Protocol6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")

var _guard6_count := 0
var _guard6_last: Dictionary = {}


func handle_rpc(body: Dictionary) -> Dictionary:
	var kind := String(body.get("kind", ""))
	if kind.begins_with("MVP6_"):
		var guarded: Dictionary = Guard6.apply(boundary, gateway_peer)
		if not bool(guarded.get("success", false)):
			return Protocol6.failure(String(guarded.get("error_code", "MVP6_ENET_GUARD_FAILED")))
		_guard6_count += 1
		_guard6_last = Dictionary(guarded.get("details", {})).duplicate(true)
	return super.handle_rpc(body)


func report(passed: bool, phase: String) -> Dictionary:
	var value: Dictionary = super.report(passed, phase)
	value["mvp6_transport_guard"] = {
		"apply_count": _guard6_count,
		"last": _guard6_last.duplicate(true),
		"shared_transport_changed": false,
	}
	return value
