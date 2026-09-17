extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_gateway_process.gd"

const Guard6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_enet_long_operation_guard.gd")
const Protocol6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")

var _guard6_counts := {"authority/a": 0, "authority/b": 0}
var _guard6_last: Dictionary = {}


func _authority6(authority_id: String, actor: String, request: Dictionary) -> Dictionary:
	var link = links.get(authority_id)
	if link == null or link.boundary == null:
		return Protocol6.failure("MVP6_ENET_GUARD_BACKEND_LINK_MISSING")
	var guarded: Dictionary = Guard6.apply(link.boundary, String(link.peer))
	if not bool(guarded.get("success", false)):
		return Protocol6.failure(String(guarded.get("error_code", "MVP6_ENET_GUARD_FAILED")))
	_guard6_counts[authority_id] = int(_guard6_counts.get(authority_id, 0)) + 1
	_guard6_last[authority_id] = Dictionary(guarded.get("details", {})).duplicate(true)
	return super._authority6(authority_id, actor, request)


func base_report(schema: String, passed: bool, graphical: bool) -> Dictionary:
	var value: Dictionary = super.base_report(schema, passed, graphical)
	value["mvp6_transport_guard"] = {
		"counts": _guard6_counts.duplicate(true),
		"last": _guard6_last.duplicate(true),
		"shared_transport_changed": false,
	}
	return value
