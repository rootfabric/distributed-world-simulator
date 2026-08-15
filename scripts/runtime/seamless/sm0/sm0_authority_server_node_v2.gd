extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node.gd"

# First executable SM0 hardening layer:
# - redirect ACK and target COMMIT ACK may arrive in either order;
# - source keeps retrying COMMIT until target confirms it;
# - delayed duplicate PREPARE remains an exact replay even after directory advance;
# - duplicate PREPARED after source already committed is ignored;
# - target import preserves trusted source motion state instead of treating
#   relocation-to-boundary as ordinary movement.


func _activate_imported_player(package: Dictionary) -> Dictionary:
	var target_session := "transport-session/sm0/a/%s/epoch/%d" % [
		_authority_id.get_slice("/", 2),
		int(package.get("target_authority_epoch", 0)),
	]
	var transfer_id := String(package.get("transfer_id", ""))
	var join: Dictionary = _authority.join(
		"a",
		target_session,
		"operation/sm0/%s/import-join/%s" % [
			_authority_id.get_slice("/", 2),
			transfer_id.sha256_text().left(12),
		]
	)
	if not bool(join.get("success", false)):
		return _failure("SM0_TARGET_JOIN_FAILED", {"cause": join})
	var current: Dictionary = Dictionary(join.get("details", {}).get("player", {}))
	var source_position: Dictionary = Dictionary(package.get("position", {}))
	var current_position: Dictionary = Dictionary(current.get("position", {}))
	var delta_x := float(source_position.get("x", 0.0)) - float(current_position.get("x", 0.0))
	var delta_z := float(source_position.get("z", 0.0)) - float(current_position.get("z", 0.0))
	if absf(delta_x) > 10.0 or absf(delta_z) > 10.0:
		return _failure("SM0_TARGET_IMPORT_DELTA_TOO_LARGE", {
			"delta_x": delta_x,
			"delta_z": delta_z,
		})

	var imported: Dictionary = _authority.import_handoff_player_state(
		"a",
		target_session,
		int(current.get("ownership_epoch", 0)),
		{
			"player_entity_id": String(package.get("player_entity_id", "")),
			"position": source_position.duplicate(true),
			"velocity": Dictionary(package.get("velocity", {})).duplicate(true),
			"orientation_yaw": float(package.get("orientation_yaw", 0.0)),
			"last_input_sequence": int(package.get("last_input_sequence", 0)),
			"source_state_revision": int(package.get("state_revision", 0)),
		},
		"operation/sm0/%s/import-state/%s" % [
			_authority_id.get_slice("/", 2),
			transfer_id.sha256_text().left(12),
		]
	)
	if not bool(imported.get("success", false)):
		return _failure("SM0_TARGET_IMPORT_STATE_FAILED", {"cause": imported})
	var player: Dictionary = Dictionary(imported.get("details", {}).get("player", {}))
	if String(player.get("player_entity_id", "")) != String(package.get("player_entity_id", "")):
		return _failure("SM0_TARGET_IMPORT_PLAYER_ID_CHANGED")
	_active_session_id = target_session
	_active_client_ip = ""
	_active_client_port = 0
	_frozen_transfer_id = ""
	return _success({"session_id": target_session, "player": player})


func _handle_handoff_prepare(request_id: String, payload: Dictionary) -> void:
	var package: Dictionary = Dictionary(payload.get("package", {}))
	var check := Contracts.validate_handoff_package(package)
	if not bool(check.get("success", false)):
		_send_control("PLAYER_HANDOFF_PREPARED", {
			"success": false,
			"error_code": String(check.get("error_code", "SM0_HANDOFF_PACKAGE_INVALID")),
			"transfer_id": String(package.get("transfer_id", "")),
		}, request_id)
		return
	var transfer_id := String(package.get("transfer_id", ""))
	if String(package.get("target_authority_id", "")) != _authority_id:
		_send_control("PLAYER_HANDOFF_PREPARED", {
			"success": false,
			"error_code": "SM0_HANDOFF_WRONG_TARGET",
			"transfer_id": transfer_id,
		}, request_id)
		return

	# Exact PREPARE replay wins over current directory revision. The directory may
	# already have advanced because COMMIT/HELLO crossed this delayed UDP packet.
	if _prepared_transfers.has(transfer_id):
		var existing: Dictionary = Dictionary(_prepared_transfers[transfer_id])
		if String(existing.get("checksum", "")) != String(package.get("checksum", "")):
			_send_control("PLAYER_HANDOFF_PREPARED", {
				"success": false,
				"error_code": "SM0_HANDOFF_PREPARE_CONFLICT",
				"transfer_id": transfer_id,
			}, request_id)
			return
		_send_control("PLAYER_HANDOFF_PREPARED", {
			"success": true,
			"error_code": "",
			"transfer_id": transfer_id,
			"package_checksum": String(package.get("checksum", "")),
		}, request_id)
		return

	if (
		int(package.get("source_authority_epoch", 0)) != int(_directory.get("authority_epoch", 0))
		or String(_directory.get("owner_authority_id", "")) != String(package.get("source_authority_id", ""))
	):
		_send_control("PLAYER_HANDOFF_PREPARED", {
			"success": false,
			"error_code": "SM0_HANDOFF_STALE_DIRECTORY",
			"transfer_id": transfer_id,
		}, request_id)
		return

	_prepared_transfers[transfer_id] = package.duplicate(true)
	_event("SM0_HANDOFF_PREPARED", {
		"transfer_id": transfer_id,
		"package_checksum": String(package.get("checksum", "")),
	})
	_send_control("PLAYER_HANDOFF_PREPARED", {
		"success": true,
		"error_code": "",
		"transfer_id": transfer_id,
		"package_checksum": String(package.get("checksum", "")),
	}, request_id)


func _handle_handoff_prepared(_request_id: String, payload: Dictionary) -> void:
	if _source_transfer.is_empty():
		return
	if String(payload.get("transfer_id", "")) != String(_source_transfer.get("transfer_id", "")):
		return
	if String(_source_transfer.get("stage", "")) != "PREPARE_SENT":
		return
	if not bool(payload.get("success", false)):
		_invariant(String(payload.get("error_code", "SM0_HANDOFF_PREPARE_REJECTED")), {
			"transfer_id": String(payload.get("transfer_id", "")),
		})
		return
	if String(payload.get("package_checksum", "")) != String(Dictionary(_source_transfer.get("package", {})).get("checksum", "")):
		_invariant("SM0_HANDOFF_PREPARED_CHECKSUM_MISMATCH", payload)
		return
	_commit_source_transfer()


func _handle_redirect_ack(_request_id: String, payload: Dictionary, _remote_ip: String, _remote_port: int) -> void:
	if _source_transfer.is_empty():
		return
	if String(payload.get("transfer_id", "")) != String(_source_transfer.get("transfer_id", "")):
		return
	_source_transfer["client_redirect_acked"] = true
	_event("SM0_SOURCE_REDIRECT_ACKNOWLEDGED", {
		"transfer_id": String(payload.get("transfer_id", "")),
		"directory": _directory,
	})
	_try_finish_source_transfer_tracking()


func _handle_handoff_committed(_request_id: String, payload: Dictionary) -> void:
	if _source_transfer.is_empty():
		return
	if String(payload.get("transfer_id", "")) != String(_source_transfer.get("transfer_id", "")):
		return
	if not bool(payload.get("success", false)):
		_invariant(String(payload.get("error_code", "SM0_HANDOFF_COMMIT_REJECTED")), payload)
		return
	_adopt_newer_directory(Dictionary(payload.get("directory", {})))
	_source_transfer["target_committed"] = true
	_source_transfer["stage"] = "AWAIT_CLIENT_REDIRECT_ACK"
	_source_transfer["last_send_ms"] = 0
	_source_transfer["retries"] = 0
	if not bool(_source_transfer.get("client_redirect_acked", false)):
		_send_client_redirect()
	_try_finish_source_transfer_tracking()


func _try_finish_source_transfer_tracking() -> void:
	if _source_transfer.is_empty():
		return
	if not bool(_source_transfer.get("target_committed", false)):
		return
	if not bool(_source_transfer.get("client_redirect_acked", false)):
		return
	_event("SM0_SOURCE_TRANSFER_COMPLETE", {
		"transfer_id": String(_source_transfer.get("transfer_id", "")),
		"directory": _directory,
	})
	_source_transfer.clear()
	_active_client_ip = ""
	_active_client_port = 0
	_active_session_id = ""
