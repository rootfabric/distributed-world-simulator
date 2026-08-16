extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_closure.gd"

const TARGET_EXIT_AFTER_PREWARM_ACK := "target-exit-after-prewarm-ack-v1"

var _p4_fault_profile := ""
var _p4_fault_triggered := false


func setup(config: Dictionary) -> Dictionary:
	_p4_fault_profile = String(config.get("p4_fault_profile", "")).strip_edges().to_lower()
	if _p4_fault_profile != TARGET_EXIT_AFTER_PREWARM_ACK:
		return _failure("SM0_P4_FAULT_PROFILE_UNSUPPORTED", {"profile": _p4_fault_profile})
	return super.setup(config)


func _send_p4_prewarmed(request_id: String, prewarm: Dictionary, success: bool, error_code: String) -> void:
	super._send_p4_prewarmed(request_id, prewarm, success, error_code)
	if (
		_p4_fault_triggered
		or not success
		or _p4_fault_profile != TARGET_EXIT_AFTER_PREWARM_ACK
		or _authority_id != Contracts.AUTHORITY_B
	):
		return
	_p4_fault_triggered = true
	_event("SM0_P4_FAULT_TARGET_EXIT_AFTER_PREWARM_ACK_ARMED", {
		"prewarm_id": String(prewarm.get("prewarm_id", "")),
		"prewarm_checksum": String(prewarm.get("checksum", "")),
		"fault_profile": _p4_fault_profile,
	})
	# The ACK was already put on the UDP socket by the inherited method after the
	# reservation durability gate. Exit deferred so the current packet handler can
	# return normally; the harness restarts this authority with the same recovery
	# directory but without the fault profile.
	call_deferred("_p4_fault_exit_after_prewarm_ack")


func _p4_fault_exit_after_prewarm_ack() -> void:
	_event("SM0_P4_FAULT_TARGET_EXIT_AFTER_PREWARM_ACK", {"fault_profile": _p4_fault_profile})
	_shutdown(86, "p4-target-exit-after-prewarm-ack")
