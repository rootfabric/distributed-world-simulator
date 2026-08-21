extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_active_recovery.gd"

const FAULT_PROFILE_H2_ACTIVE_OWNER_CRASH_AFTER_MOVE_PERSIST_V1 := "h2-active-owner-crash-after-move-persist-v1"

var _h24_fault_profile := ""
var _h24_crash_point_emitted := false


func setup(config: Dictionary) -> Dictionary:
	_h24_fault_profile = String(config.get("fault_profile", "")).strip_edges()
	if _h24_fault_profile != FAULT_PROFILE_H2_ACTIVE_OWNER_CRASH_AFTER_MOVE_PERSIST_V1:
		return _failure("SM0_UNKNOWN_ACTIVE_RECOVERY_FAULT_PROFILE", {"fault_profile": _h24_fault_profile})
	if String(config.get("recovery_dir", "")).strip_edges().is_empty():
		return _failure("SM0_H2_4_RECOVERY_DIR_REQUIRED")
	var result: Dictionary = super.setup(config)
	if bool(result.get("success", false)):
		_event("SM0_FAULT_PROFILE_ENABLED", {"fault_profile": _h24_fault_profile})
	return result


func _handle_client_move(request_id: String, payload: Dictionary, remote_ip: String, remote_port: int) -> void:
	if _h24_crash_point_emitted:
		return
	super._handle_client_move(request_id, payload, remote_ip, remote_port)


func _send_gameplay(host: String, port: int, message_type: String, payload: Dictionary, request_id: String = "") -> void:
	if (
		_h24_fault_profile == FAULT_PROFILE_H2_ACTIVE_OWNER_CRASH_AFTER_MOVE_PERSIST_V1
		and not _h24_crash_point_emitted
		and message_type == "MOVE_ACK"
		and bool(payload.get("accepted", false))
	):
		var persisted := _ensure_active_owner_persisted_for_ack(host, port, message_type, payload)
		if not bool(persisted.get("success", false)):
			_invariant("SM0_H2_4_ACTIVE_MOVE_PERSIST_FAILED", {"cause": persisted})
			return
		var player: Dictionary = _authority.get_player("a")
		_h24_crash_point_emitted = true
		_event("SM0_H2_CRASH_POINT", {
			"fault_profile": _h24_fault_profile,
			"crash_point": "ACTIVE_OWNER_AFTER_MOVE_PERSIST_BEFORE_ACK",
			"message_type": message_type,
			"request_id": request_id,
			"recovery_generation": _recovery_generation,
			"recovery_phase": _recovery_last_phase,
			"player_entity_id": String(player.get("player_entity_id", "")),
			"ownership_epoch": int(player.get("ownership_epoch", 0)),
			"last_input_sequence": int(player.get("last_input_sequence", 0)),
			"state_revision": int(player.get("state_revision", 0)),
			"position": Dictionary(player.get("position", {})).duplicate(true),
		})
		# Suppress the successful ACK until the external supervisor kills this
		# process. The client therefore retries the exact durable movement against
		# the recovered process.
		return
	if _h24_crash_point_emitted and message_type in ["MOVE_ACK", "JOIN_ACK", "ACTIVATE_ACK", "HANDOFF_REDIRECT"]:
		return
	super._send_gameplay(host, port, message_type, payload, request_id)
