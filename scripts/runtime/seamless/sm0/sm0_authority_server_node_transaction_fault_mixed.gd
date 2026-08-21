extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_transaction_fault.gd"

# H4.2 reuses each recovered authority in the next alternating transfer before
# that process is crashed again. The base transaction-fault node intentionally
# keeps a one-shot suppression-log flag, which is sufficient for the earlier
# single-boundary campaigns but is too coarse for the mixed-boundary campaign:
# a recovery redirect from transfer N can consume the flag needed to record the
# distinct COMMITTED/ACTIVATE suppression for transfer N+1.
#
# Keep suppression behavior unchanged and only scope evidence de-duplication to
# the exact logical send being suppressed. Repeated retries of the same
# boundary/message/transfer still produce exactly one evidence event.
var _h42_suppressed_send_keys: Dictionary = {}


func _h42_emit_send_suppressed(boundary: String, message_type: String, transfer_id: String, request_id: String = "") -> void:
	var key := "%s|%s|%s" % [boundary, message_type, transfer_id]
	if _h42_suppressed_send_keys.has(key):
		return
	_h42_suppressed_send_keys[key] = true
	_event("SM0_H4_MIXED_SEND_SUPPRESSED", {
		"fault_profile": _transaction_fault_profile,
		"boundary": boundary,
		"message_type": message_type,
		"transfer_id": transfer_id,
		"request_id": request_id,
		"target_epoch": int(_directory.get("authority_epoch", 0)),
		"authority_id": _authority_id,
		"recovery_generation": _recovery_generation,
	})
