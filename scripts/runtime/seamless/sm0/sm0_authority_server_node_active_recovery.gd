extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_resume.gd"

const ACTIVE_OWNER_PHASE := "ACTIVE_OWNER"
const ACTIVE_OWNER_KIND := "ACTIVE_OWNER"

var _active_recovery_metadata: Dictionary = {}
var _active_persisted_signature := ""


func _send_gameplay(host: String, port: int, message_type: String, payload: Dictionary, request_id: String = "") -> void:
	if _requires_active_owner_durability(message_type, payload):
		var persisted := _ensure_active_owner_persisted_for_ack(host, port, message_type, payload)
		if not bool(persisted.get("success", false)):
			_invariant("SM0_ACTIVE_OWNER_ACK_PERSIST_FAILED", {
				"message_type": message_type,
				"request_id": request_id,
				"cause": persisted,
			})
			return
	super._send_gameplay(host, port, message_type, payload, request_id)


func _handle_client_activate(request_id: String, payload: Dictionary, remote_ip: String, remote_port: int) -> void:
	super._handle_client_activate(request_id, payload, remote_ip, remote_port)
	if (
		not _active_recovery_metadata.is_empty()
		and _active_session_id != ""
		and _active_client_ip == remote_ip
		and _active_client_port == remote_port
	):
		_active_recovery_metadata.clear()


func _handle_client_move(request_id: String, payload: Dictionary, remote_ip: String, remote_port: int) -> void:
	if not _active_recovery_metadata.is_empty() and _active_session_id.is_empty():
		_handle_recovered_active_move(request_id, payload, remote_ip, remote_port)
		return
	super._handle_client_move(request_id, payload, remote_ip, remote_port)


func _requires_active_owner_durability(message_type: String, payload: Dictionary) -> bool:
	if _recovery_root.is_empty():
		return false
	if message_type == "JOIN_ACK" or message_type == "ACTIVATE_ACK":
		return true
	return message_type == "MOVE_ACK" and bool(payload.get("accepted", false))


func _ensure_active_owner_persisted_for_ack(
	host: String,
	port: int,
	message_type: String,
	payload: Dictionary
) -> Dictionary:
	if _recovery_authority_dir.is_empty():
		return _failure("SM0_ACTIVE_OWNER_RECOVERY_DIRECTORY_NOT_READY")
	if String(_directory.get("owner_authority_id", "")) != _authority_id:
		return _failure("SM0_ACTIVE_OWNER_DIRECTORY_OWNER_MISMATCH")
	if _active_session_id.is_empty() or _active_client_ip.is_empty() or _active_client_port < 1:
		return _failure("SM0_ACTIVE_OWNER_SESSION_NOT_BOUND")
	if host != _active_client_ip or port != _active_client_port:
		return _failure("SM0_ACTIVE_OWNER_ACK_ENDPOINT_MISMATCH")
	var player: Dictionary = _authority.get_player("a")
	if player.is_empty() or not bool(player.get("connected", false)):
		return _failure("SM0_ACTIVE_OWNER_PLAYER_NOT_CONNECTED")
	if String(player.get("transport_session_id", "")) != _active_session_id:
		return _failure("SM0_ACTIVE_OWNER_PLAYER_SESSION_MISMATCH")
	var signature_payload := {
		"directory_checksum": String(_directory.get("checksum", "")),
		"session_id": _active_session_id,
		"client_ip": _active_client_ip,
		"client_port": _active_client_port,
		"player_entity_id": String(player.get("player_entity_id", "")),
		"ownership_epoch": int(player.get("ownership_epoch", 0)),
		"last_input_sequence": int(player.get("last_input_sequence", 0)),
		"state_revision": int(player.get("state_revision", 0)),
	}
	var signature := RecoveryUtils.payload_hash(signature_payload)
	if signature == _active_persisted_signature and _recovery_last_phase == ACTIVE_OWNER_PHASE:
		return _success({
			"generation": _recovery_generation,
			"replay": true,
			"message_type": message_type,
		})
	var persisted := _persist_recovery_snapshot(ACTIVE_OWNER_PHASE, "")
	if not bool(persisted.get("success", false)):
		return persisted
	_active_persisted_signature = signature
	_event("SM0_ACTIVE_OWNER_ACK_DURABLE", {
		"generation": _recovery_generation,
		"message_type": message_type,
		"request_id": String(payload.get("request_id", "")),
		"player_entity_id": String(player.get("player_entity_id", "")),
		"ownership_epoch": int(player.get("ownership_epoch", 0)),
		"last_input_sequence": int(player.get("last_input_sequence", 0)),
		"state_revision": int(player.get("state_revision", 0)),
		"position": Dictionary(player.get("position", {})).duplicate(true),
	})
	return persisted


func _export_source_transfer_metadata(phase: String) -> Dictionary:
	if phase != ACTIVE_OWNER_PHASE:
		return super._export_source_transfer_metadata(phase)
	var player: Dictionary = _authority.get_player("a")
	return {
		"kind": ACTIVE_OWNER_KIND,
		"logical_player_id": "a",
		"player_entity_id": String(player.get("player_entity_id", "")),
		"session_id": _active_session_id,
		"client_ip": _active_client_ip,
		"client_port": _active_client_port,
		"ownership_epoch": int(player.get("ownership_epoch", 0)),
		"last_input_sequence": int(player.get("last_input_sequence", 0)),
		"state_revision": int(player.get("state_revision", 0)),
	}


func _validate_recovery_snapshot(value: Dictionary) -> Dictionary:
	if String(value.get("phase", "")) != ACTIVE_OWNER_PHASE:
		return super._validate_recovery_snapshot(value)
	var expected_checksum := String(value.get("checksum", ""))
	var checksum_payload: Dictionary = value.duplicate(true)
	checksum_payload.erase("checksum")
	if expected_checksum.is_empty() or expected_checksum != RecoveryUtils.payload_hash(checksum_payload):
		return _failure("SM0_RECOVERY_CHECKSUM_MISMATCH")

	# Reuse the established handoff snapshot validation for every shared section.
	# Only phase/source_transfer are specialized by H2.4.
	var normalized: Dictionary = value.duplicate(true)
	normalized["phase"] = "TARGET_COMMITTED"
	normalized["source_transfer"] = {}
	normalized["checksum"] = ""
	normalized = RecoveryUtils.finalize_json_checksum(normalized)
	var base_check := super._validate_recovery_snapshot(normalized)
	if not bool(base_check.get("success", false)):
		return _failure("SM0_ACTIVE_OWNER_BASE_SNAPSHOT_INVALID", {"cause": base_check})

	if not String(value.get("transfer_id", "")).is_empty():
		return _failure("SM0_ACTIVE_OWNER_TRANSFER_ID_MUST_BE_EMPTY")
	var directory: Dictionary = Dictionary(value.get("directory", {}))
	if String(directory.get("owner_authority_id", "")) != _authority_id:
		return _failure("SM0_ACTIVE_OWNER_DIRECTORY_OWNER_MISMATCH")
	var metadata: Dictionary = Dictionary(value.get("source_transfer", {}))
	if String(metadata.get("kind", "")) != ACTIVE_OWNER_KIND:
		return _failure("SM0_ACTIVE_OWNER_METADATA_KIND_INVALID")
	if String(metadata.get("logical_player_id", "")) != "a" or String(metadata.get("player_entity_id", "")) != "player/a":
		return _failure("SM0_ACTIVE_OWNER_IDENTITY_INVALID")
	var session_id := String(metadata.get("session_id", "")).strip_edges()
	var client_ip := String(metadata.get("client_ip", "")).strip_edges()
	var client_port := int(metadata.get("client_port", 0))
	if session_id.is_empty() or client_ip.is_empty() or client_port < 1 or client_port > 65535:
		return _failure("SM0_ACTIVE_OWNER_ENDPOINT_INVALID")
	if int(metadata.get("ownership_epoch", 0)) < 1 or int(metadata.get("last_input_sequence", -1)) < 0 or int(metadata.get("state_revision", 0)) < 1:
		return _failure("SM0_ACTIVE_OWNER_REVISION_INVALID")

	var gameplay_state: Dictionary = Dictionary(value.get("gameplay_state", {}))
	var player_section: Dictionary = Dictionary(gameplay_state.get("players", {}))
	var durable_players: Array = Array(player_section.get("players", []))
	var found := false
	for record_value in durable_players:
		if not record_value is Dictionary:
			continue
		var record: Dictionary = Dictionary(record_value)
		if String(record.get("logical_player_id", "")) != "a":
			continue
		found = true
		if (
			String(record.get("player_entity_id", "")) != String(metadata.get("player_entity_id", ""))
			or bool(record.get("connected", true))
			or not String(record.get("transport_session_id", "")).is_empty()
			or int(record.get("ownership_epoch", 0)) != int(metadata.get("ownership_epoch", 0))
			or int(record.get("last_input_sequence", -1)) != int(metadata.get("last_input_sequence", -2))
			or int(record.get("state_revision", 0)) != int(metadata.get("state_revision", -1))
		):
			return _failure("SM0_ACTIVE_OWNER_DURABLE_PLAYER_MISMATCH")
		break
	if not found:
		return _failure("SM0_ACTIVE_OWNER_DURABLE_PLAYER_MISSING")
	return _success()


func _apply_recovery_snapshot(snapshot: Dictionary, path: String) -> Dictionary:
	var result := super._apply_recovery_snapshot(snapshot, path)
	if not bool(result.get("success", false)):
		return result
	if String(snapshot.get("phase", "")) == ACTIVE_OWNER_PHASE:
		_active_recovery_metadata = Dictionary(snapshot.get("source_transfer", {})).duplicate(true)
		_active_persisted_signature = ""
		_event("SM0_RECOVERY_ACTIVE_OWNER_PENDING", {
			"generation": _recovery_generation,
			"player_entity_id": String(_active_recovery_metadata.get("player_entity_id", "")),
			"ownership_epoch": int(_active_recovery_metadata.get("ownership_epoch", 0)),
			"last_input_sequence": int(_active_recovery_metadata.get("last_input_sequence", 0)),
			"directory": _directory,
		})
	return result


func _handle_recovered_active_move(request_id: String, payload: Dictionary, remote_ip: String, remote_port: int) -> void:
	var metadata: Dictionary = _active_recovery_metadata
	if not _active_recovery_request_matches(payload, remote_ip, remote_port):
		_send_gameplay(remote_ip, remote_port, "SM0_ERROR", {
			"error_code": "SM0_RECOVERY_ACTIVE_SESSION_MISMATCH",
			"directory": _directory,
		}, request_id)
		return
	var before: Dictionary = _authority.get_player("a")
	if before.is_empty() or bool(before.get("connected", true)):
		_invariant("SM0_RECOVERY_ACTIVE_PLAYER_NOT_DISCONNECTED", {"player": before})
		return
	var durable_sequence := int(before.get("last_input_sequence", -1))
	var requested_sequence := int(payload.get("input_sequence", -1))
	if requested_sequence < durable_sequence:
		_send_gameplay(remote_ip, remote_port, "MOVE_ACK", {
			"accepted": false,
			"error_code": "SM0_RECOVERY_STALE_INPUT_SEQUENCE",
			"handoff_pending": false,
			"directory": _directory,
		}, request_id)
		return

	var duplicate_durable_input := requested_sequence == durable_sequence
	if duplicate_durable_input:
		var replay: Dictionary = _authority.move_player(
			"a",
			String(metadata.get("session_id", "")),
			int(metadata.get("ownership_epoch", 0)),
			requested_sequence,
			float(payload.get("delta_x", 0.0)),
			float(payload.get("delta_z", 0.0)),
			"operation/sm0/client/a/move/%d" % requested_sequence
		)
		if not bool(replay.get("success", false)) or not bool(replay.get("replay", replay.get("details", {}).get("replay", false))):
			_send_gameplay(remote_ip, remote_port, "SM0_ERROR", {
				"error_code": "SM0_RECOVERY_ACTIVE_REPLAY_MISMATCH",
				"directory": _directory,
			}, request_id)
			return

	var session_id := String(metadata.get("session_id", ""))
	var joined: Dictionary = _authority.join(
		"a",
		session_id,
		"operation/sm0/%s/active-rebind/%d" % [_authority_id.get_slice("/", 2), _recovery_generation]
	)
	if not bool(joined.get("success", false)):
		_send_gameplay(remote_ip, remote_port, "SM0_ERROR", {
			"error_code": "SM0_RECOVERY_ACTIVE_REBIND_FAILED",
			"directory": _directory,
		}, request_id)
		return
	var rebound_player: Dictionary = Dictionary(joined.get("details", {}).get("player", {}))
	if (
		String(rebound_player.get("player_entity_id", "")) != String(before.get("player_entity_id", ""))
		or not _same_position(Dictionary(rebound_player.get("position", {})), Dictionary(before.get("position", {})))
		or int(rebound_player.get("last_input_sequence", -1)) != durable_sequence
	):
		_invariant("SM0_RECOVERY_ACTIVE_REBIND_MUTATED_STATE", {
			"before": before,
			"after": rebound_player,
		})
		return

	_active_session_id = session_id
	_active_client_ip = remote_ip
	_active_client_port = remote_port
	_mark_current_committed_rebound(rebound_player)
	_event("SM0_RECOVERY_ACTIVE_OWNER_REBOUND", {
		"generation": _recovery_generation,
		"session_id": session_id,
		"previous_ownership_epoch": int(before.get("ownership_epoch", 0)),
		"ownership_epoch": int(rebound_player.get("ownership_epoch", 0)),
		"last_input_sequence": durable_sequence,
		"duplicate_durable_input": duplicate_durable_input,
		"position": Dictionary(rebound_player.get("position", {})).duplicate(true),
		"player_entity_id": String(rebound_player.get("player_entity_id", "")),
	})

	if duplicate_durable_input:
		_active_recovery_metadata.clear()
		_send_gameplay(remote_ip, remote_port, "MOVE_ACK", {
			"accepted": true,
			"error_code": "",
			"handoff_pending": false,
			"authority_id": _authority_id,
			"directory": _directory,
			"player": rebound_player,
		}, request_id)
		if _should_begin_handoff(rebound_player):
			_begin_handoff(rebound_player)
		return

	var normalized_payload: Dictionary = payload.duplicate(true)
	normalized_payload["ownership_epoch"] = int(rebound_player.get("ownership_epoch", 0))
	_active_recovery_metadata.clear()
	super._handle_client_move(request_id, normalized_payload, remote_ip, remote_port)


func _active_recovery_request_matches(payload: Dictionary, remote_ip: String, remote_port: int) -> bool:
	if _active_recovery_metadata.is_empty():
		return false
	return (
		String(_directory.get("owner_authority_id", "")) == _authority_id
		and String(payload.get("logical_player_id", "")) == "a"
		and String(payload.get("session_id", "")) == String(_active_recovery_metadata.get("session_id", ""))
		and int(payload.get("ownership_epoch", 0)) == int(_active_recovery_metadata.get("ownership_epoch", -1))
		and remote_ip == String(_active_recovery_metadata.get("client_ip", ""))
		and remote_port == int(_active_recovery_metadata.get("client_port", 0))
	)


func _mark_current_committed_rebound(player: Dictionary) -> void:
	for transfer_id_value in _committed_transfers.keys():
		var transfer_id := String(transfer_id_value)
		var committed: Dictionary = Dictionary(_committed_transfers[transfer_id_value])
		if not _same_directory(Dictionary(committed.get("directory", {})), _directory):
			continue
		committed["needs_session_rebind"] = false
		committed["player"] = player.duplicate(true)
		_committed_transfers[transfer_id] = committed
