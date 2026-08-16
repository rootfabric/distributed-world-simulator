extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node.gd"

# First executable SM0 hardening layer plus opt-in P4 prewarmed fast handoff:
# - redirect ACK and target COMMIT ACK may arrive in either order;
# - source keeps retrying COMMIT until target confirms it;
# - delayed duplicate PREPARE remains an exact replay even after directory advance;
# - duplicate PREPARED after source already committed is ignored;
# - target import preserves trusted source motion state instead of treating
#   relocation-to-boundary as ordinary movement;
# - an exact late MOVE from the client of a retired-but-pending source transfer
#   remains a non-fatal handoff-pending response while ownership stays retired;
# - P4 prewarm is metadata-only and opt-in through SM0_P4_FAST_HANDOFF=1;
# - P4 uses process-local expiry derived from transported ttl_ms, never a
#   cross-process Time.get_ticks_msec() absolute timestamp;
# - missing/stale/rejected prewarm always falls back to the proven legacy path.

const P4_PREWARM_DISTANCE_M := 1.0
const P4_PREWARM_TTL_MS := 3000
const P4_PREWARM_RETRY_INTERVAL_MS := 100
const P4_PREWARM_MAX_RETRIES := 30
const P4_FAST_RETRY_INTERVAL_MS := 200
const P4_FAST_MAX_RETRIES := 100

var _p4_enabled := false
var _p4_prewarm_counter := 0
var _source_prewarm: Dictionary = {}
var _prewarmed_transfers: Dictionary = {}


func setup(config: Dictionary) -> Dictionary:
	_p4_enabled = _p4_env_enabled()
	var result: Dictionary = super.setup(config)
	if bool(result.get("success", false)):
		_event("SM0_P4_MODE", {
			"enabled": _p4_enabled,
			"prewarm_distance_m": P4_PREWARM_DISTANCE_M,
			"prewarm_ttl_ms": P4_PREWARM_TTL_MS,
		})
	return result


func _process(delta: float) -> void:
	super._process(delta)
	if not _p4_enabled:
		return
	var now := Time.get_ticks_msec()
	_p4_purge_expired_reservations(now)
	_p4_tick_source_prewarm(now)
	_p4_maybe_start_prewarm()


func _handle_control_message(message: Dictionary, remote_ip: String, remote_port: int) -> void:
	if _p4_enabled:
		var message_type := String(message.get("type", ""))
		var request_id := String(message.get("request_id", ""))
		var payload: Dictionary = Dictionary(message.get("payload", {}))
		match message_type:
			"PLAYER_HANDOFF_PREWARM":
				_handle_p4_prewarm(request_id, payload)
				return
			"PLAYER_HANDOFF_PREWARMED":
				_handle_p4_prewarmed(request_id, payload)
				return
			"PLAYER_HANDOFF_PREWARM_CANCEL":
				_handle_p4_prewarm_cancel(payload)
				return
			"PLAYER_HANDOFF_FAST_COMMIT":
				_handle_p4_fast_commit(request_id, payload)
				return
	super._handle_control_message(message, remote_ip, remote_port)


func _handle_client_move(request_id: String, payload: Dictionary, remote_ip: String, remote_port: int) -> void:
	if _is_retired_source_pending_move(payload, remote_ip, remote_port):
		_event("SM0_SOURCE_LATE_MOVE_HELD", {
			"transfer_id": String(_source_transfer.get("transfer_id", "")),
			"request_id": request_id,
			"directory": _directory,
		})
		_send_gameplay(remote_ip, remote_port, "MOVE_ACK", {
			"accepted": false,
			"error_code": "SM0_PLAYER_FROZEN_FOR_HANDOFF",
			"handoff_pending": true,
			"transfer_id": String(_source_transfer.get("transfer_id", "")),
			"directory": _directory,
		}, request_id)
		return
	super._handle_client_move(request_id, payload, remote_ip, remote_port)
	if _p4_enabled:
		_p4_maybe_start_prewarm()


func _is_retired_source_pending_move(payload: Dictionary, remote_ip: String, remote_port: int) -> bool:
	if _source_transfer.is_empty() or _frozen_transfer_id.is_empty():
		return false
	if String(_directory.get("owner_authority_id", "")) == _authority_id:
		return false
	var transfer_id := String(_source_transfer.get("transfer_id", ""))
	if transfer_id.is_empty() or transfer_id != _frozen_transfer_id:
		return false
	if String(_source_transfer.get("stage", "")) not in ["COMMIT_SENT", "FAST_COMMIT_SENT", "AWAIT_CLIENT_REDIRECT_ACK"]:
		return false
	if String(payload.get("logical_player_id", "")) != "a":
		return false
	return (
		remote_ip == String(_source_transfer.get("client_ip", ""))
		and remote_port == int(_source_transfer.get("client_port", 0))
	)


func _begin_handoff(player: Dictionary) -> void:
	if not _p4_enabled or not _p4_can_fast_handoff(player):
		if _p4_enabled:
			_event("SM0_P4_FAST_FALLBACK", {
				"reason": _p4_fast_unavailable_reason(player),
				"directory": _directory,
			})
			_p4_cancel_source_prewarm("fallback")
		super._begin_handoff(player)
		return
	_begin_p4_fast_handoff(player)


func _begin_p4_fast_handoff(player: Dictionary) -> void:
	var prewarm: Dictionary = Dictionary(_source_prewarm.get("prewarm", {})).duplicate(true)
	_transfer_counter += 1
	var source_epoch := int(_directory.get("authority_epoch", 1))
	var target_epoch := source_epoch + 1
	var transfer_id := "handoff/sm0/%s/%d/%d" % [_authority_id.get_slice("/", 2), target_epoch, _transfer_counter]
	var package: Dictionary = Contracts.create_handoff_package(
		transfer_id,
		player,
		_authority_id,
		_peer_authority_id,
		_zone_id,
		_peer_zone_id,
		source_epoch,
		target_epoch,
		int(_directory.get("revision", 1))
	)
	var package_check: Dictionary = Contracts.validate_handoff_package(package)
	if not bool(package_check.get("success", false)):
		_invariant(String(package_check.get("error_code", "SM0_HANDOFF_PACKAGE_INVALID")), {"transfer_id": transfer_id})
		return
	var next_directory: Dictionary = Contracts.create_directory(
		_peer_authority_id,
		target_epoch,
		int(_directory.get("revision", 0)) + 1
	)
	var directory_check: Dictionary = Contracts.validate_directory(next_directory)
	if not bool(directory_check.get("success", false)):
		_invariant(String(directory_check.get("error_code", "SM0_DIRECTORY_INVALID")), {"transfer_id": transfer_id})
		return

	_frozen_transfer_id = transfer_id
	_source_transfer = {
		"transfer_id": transfer_id,
		"package": package,
		"prewarm": prewarm,
		"prewarm_id": String(prewarm.get("prewarm_id", "")),
		"stage": "FAST_COMMIT_SENT",
		"last_send_ms": 0,
		"retries": 0,
		"client_ip": _active_client_ip,
		"client_port": _active_client_port,
		"target_committed": false,
		"client_redirect_acked": false,
		"p4_fast": true,
	}
	_source_prewarm.clear()
	_event("SM0_HANDOFF_BEGIN", {"transfer_id": transfer_id, "package": package, "path": "P4_FAST"})
	_event("SM0_P4_FAST_HANDOFF_BEGIN", {
		"transfer_id": transfer_id,
		"prewarm_id": String(prewarm.get("prewarm_id", "")),
		"prewarm_checksum": String(prewarm.get("checksum", "")),
		"package_checksum": String(package.get("checksum", "")),
	})
	_event("SM0_SOURCE_FROZEN", {"transfer_id": transfer_id, "player": player, "path": "P4_FAST"})

	var leave: Dictionary = _authority.leave(
		"a",
		_active_session_id,
		"operation/sm0/%s/leave/%s" % [_authority_id.get_slice("/", 2), transfer_id.sha256_text().left(12)]
	)
	if not bool(leave.get("success", false)):
		_invariant("SM0_SOURCE_RETIRE_FAILED", {"transfer_id": transfer_id, "cause": leave, "path": "P4_FAST"})
		return
	_directory = next_directory
	_event("SM0_DIRECTORY_COMMITTED", {"transfer_id": transfer_id, "directory": _directory, "path": "P4_FAST"})
	_event("SM0_SOURCE_RETIRED", {"transfer_id": transfer_id, "directory": _directory, "path": "P4_FAST"})
	_send_p4_fast_commit()
	_send_client_redirect()


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
	var check: Dictionary = Contracts.validate_handoff_package(package)
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
		"path": "P4_FAST" if bool(_source_transfer.get("p4_fast", false)) else "LEGACY",
	})
	_source_transfer.clear()
	_active_client_ip = ""
	_active_client_port = 0
	_active_session_id = ""


func _retry_source_transfer(now: int) -> void:
	if _source_transfer.is_empty() or String(_source_transfer.get("stage", "")) != "FAST_COMMIT_SENT":
		super._retry_source_transfer(now)
		return
	var last_send := int(_source_transfer.get("last_send_ms", 0))
	if last_send > 0 and now - last_send < P4_FAST_RETRY_INTERVAL_MS:
		return
	var retries := int(_source_transfer.get("retries", 0)) + 1
	_source_transfer["retries"] = retries
	if retries > P4_FAST_MAX_RETRIES:
		_invariant("SM0_HANDOFF_STAGE_TIMEOUT", {
			"transfer_id": String(_source_transfer.get("transfer_id", "")),
			"stage": "FAST_COMMIT_SENT",
		})
		return
	_send_p4_fast_commit()
	_send_client_redirect()


func _send_p4_fast_commit() -> void:
	if _source_transfer.is_empty():
		return
	_source_transfer["last_send_ms"] = Time.get_ticks_msec()
	var package: Dictionary = Dictionary(_source_transfer.get("package", {}))
	var prewarm: Dictionary = Dictionary(_source_transfer.get("prewarm", {}))
	_event("SM0_P4_FAST_COMMIT_SENT", {
		"transfer_id": String(_source_transfer.get("transfer_id", "")),
		"prewarm_id": String(prewarm.get("prewarm_id", "")),
		"package_checksum": String(package.get("checksum", "")),
		"directory": _directory,
	})
	_send_control("PLAYER_HANDOFF_FAST_COMMIT", {
		"transfer_id": String(_source_transfer.get("transfer_id", "")),
		"prewarm_id": String(prewarm.get("prewarm_id", "")),
		"prewarm_checksum": String(prewarm.get("checksum", "")),
		"package": package,
		"directory": _directory,
	}, String(_source_transfer.get("transfer_id", "")))


func _handle_p4_prewarm(request_id: String, payload: Dictionary) -> void:
	var prewarm: Dictionary = Dictionary(payload.get("prewarm", {}))
	var check: Dictionary = Contracts.validate_handoff_prewarm(prewarm)
	if not bool(check.get("success", false)):
		_send_p4_prewarmed(request_id, prewarm, false, String(check.get("error_code", "SM0_HANDOFF_PREWARM_INVALID")))
		return
	var prewarm_id := String(prewarm.get("prewarm_id", ""))
	if String(prewarm.get("target_authority_id", "")) != _authority_id:
		_send_p4_prewarmed(request_id, prewarm, false, "SM0_HANDOFF_PREWARM_WRONG_TARGET")
		return
	var now := Time.get_ticks_msec()
	if _prewarmed_transfers.has(prewarm_id):
		var existing: Dictionary = Dictionary(_prewarmed_transfers[prewarm_id])
		var existing_prewarm: Dictionary = Dictionary(existing.get("prewarm", {}))
		if String(existing_prewarm.get("checksum", "")) != String(prewarm.get("checksum", "")):
			_send_p4_prewarmed(request_id, prewarm, false, "SM0_HANDOFF_PREWARM_CONFLICT")
			return
		if now >= int(existing.get("expires_at_local_ms", 0)):
			_prewarmed_transfers.erase(prewarm_id)
			_send_p4_prewarmed(request_id, prewarm, false, "SM0_HANDOFF_PREWARM_EXPIRED")
			return
		_send_p4_prewarmed(request_id, prewarm, true, "")
		return
	if (
		String(_directory.get("owner_authority_id", "")) != String(prewarm.get("source_authority_id", ""))
		or int(_directory.get("authority_epoch", 0)) != int(prewarm.get("source_authority_epoch", 0))
		or int(_directory.get("revision", 0)) != int(prewarm.get("source_directory_revision", 0))
	):
		_send_p4_prewarmed(request_id, prewarm, false, "SM0_HANDOFF_PREWARM_STALE_DIRECTORY")
		return
	var expires_at_local_ms := now + int(prewarm.get("ttl_ms", 0))
	_prewarmed_transfers[prewarm_id] = {
		"prewarm": prewarm.duplicate(true),
		"expires_at_local_ms": expires_at_local_ms,
	}
	_event("SM0_P4_PREWARM_RESERVED", {
		"prewarm_id": prewarm_id,
		"prewarm_checksum": String(prewarm.get("checksum", "")),
		"expires_in_ms": int(prewarm.get("ttl_ms", 0)),
		"directory": _directory,
	})
	_send_p4_prewarmed(request_id, prewarm, true, "")


func _send_p4_prewarmed(request_id: String, prewarm: Dictionary, success: bool, error_code: String) -> void:
	_send_control("PLAYER_HANDOFF_PREWARMED", {
		"success": success,
		"error_code": error_code,
		"prewarm_id": String(prewarm.get("prewarm_id", "")),
		"prewarm_checksum": String(prewarm.get("checksum", "")),
	}, request_id)


func _handle_p4_prewarmed(_request_id: String, payload: Dictionary) -> void:
	if _source_prewarm.is_empty():
		return
	var prewarm: Dictionary = Dictionary(_source_prewarm.get("prewarm", {}))
	if String(payload.get("prewarm_id", "")) != String(prewarm.get("prewarm_id", "")):
		return
	if not bool(payload.get("success", false)):
		_event("SM0_P4_PREWARM_REJECTED", {
			"prewarm_id": String(prewarm.get("prewarm_id", "")),
			"error_code": String(payload.get("error_code", "SM0_HANDOFF_PREWARM_REJECTED")),
		})
		_source_prewarm.clear()
		return
	if String(payload.get("prewarm_checksum", "")) != String(prewarm.get("checksum", "")):
		_event("SM0_P4_PREWARM_REJECTED", {
			"prewarm_id": String(prewarm.get("prewarm_id", "")),
			"error_code": "SM0_HANDOFF_PREWARM_ACK_CHECKSUM_MISMATCH",
		})
		_source_prewarm.clear()
		return
	_source_prewarm["stage"] = "ACKED"
	_event("SM0_P4_PREWARMED", {
		"prewarm_id": String(prewarm.get("prewarm_id", "")),
		"prewarm_checksum": String(prewarm.get("checksum", "")),
		"directory": _directory,
	})


func _handle_p4_prewarm_cancel(payload: Dictionary) -> void:
	var prewarm_id := String(payload.get("prewarm_id", ""))
	if not _prewarmed_transfers.has(prewarm_id):
		return
	var existing: Dictionary = Dictionary(_prewarmed_transfers[prewarm_id])
	var prewarm: Dictionary = Dictionary(existing.get("prewarm", {}))
	if String(payload.get("prewarm_checksum", "")) != String(prewarm.get("checksum", "")):
		return
	_prewarmed_transfers.erase(prewarm_id)
	_event("SM0_P4_PREWARM_CANCELLED", {"prewarm_id": prewarm_id, "side": "target"})


func _handle_p4_fast_commit(request_id: String, payload: Dictionary) -> void:
	var transfer_id := String(payload.get("transfer_id", ""))
	var prewarm_id := String(payload.get("prewarm_id", ""))
	var package: Dictionary = Dictionary(payload.get("package", {}))
	var directory: Dictionary = Dictionary(payload.get("directory", {}))
	var package_check: Dictionary = Contracts.validate_handoff_package(package)
	if not bool(package_check.get("success", false)):
		_send_p4_fast_committed(request_id, transfer_id, false, String(package_check.get("error_code", "SM0_HANDOFF_PACKAGE_INVALID")))
		return
	var directory_check: Dictionary = Contracts.validate_directory(directory)
	if not bool(directory_check.get("success", false)):
		_send_p4_fast_committed(request_id, transfer_id, false, String(directory_check.get("error_code", "SM0_DIRECTORY_INVALID")))
		return
	if String(package.get("transfer_id", "")) != transfer_id:
		_send_p4_fast_committed(request_id, transfer_id, false, "SM0_P4_FAST_TRANSFER_ID_MISMATCH")
		return
	if String(package.get("target_authority_id", "")) != _authority_id or String(directory.get("owner_authority_id", "")) != _authority_id:
		_send_p4_fast_committed(request_id, transfer_id, false, "SM0_P4_FAST_WRONG_TARGET")
		return

	if _committed_transfers.has(transfer_id):
		var committed: Dictionary = Dictionary(_committed_transfers[transfer_id])
		var committed_package: Dictionary = Dictionary(committed.get("package", {}))
		if (
			String(committed_package.get("checksum", "")) != String(package.get("checksum", ""))
			or String(committed.get("prewarm_id", "")) != prewarm_id
			or String(Dictionary(committed.get("directory", {})).get("checksum", "")) != String(directory.get("checksum", ""))
		):
			_send_p4_fast_committed(request_id, transfer_id, false, "SM0_P4_FAST_COMMIT_CONFLICT")
			return
		_send_p4_fast_committed(request_id, transfer_id, true, "")
		return

	if not _prewarmed_transfers.has(prewarm_id):
		_send_p4_fast_committed(request_id, transfer_id, false, "SM0_P4_FAST_COMMIT_WITHOUT_PREWARM")
		return
	var reservation: Dictionary = Dictionary(_prewarmed_transfers[prewarm_id])
	var prewarm: Dictionary = Dictionary(reservation.get("prewarm", {}))
	if Time.get_ticks_msec() >= int(reservation.get("expires_at_local_ms", 0)):
		_prewarmed_transfers.erase(prewarm_id)
		_send_p4_fast_committed(request_id, transfer_id, false, "SM0_P4_FAST_PREWARM_EXPIRED")
		return
	if String(payload.get("prewarm_checksum", "")) != String(prewarm.get("checksum", "")):
		_send_p4_fast_committed(request_id, transfer_id, false, "SM0_P4_FAST_PREWARM_CHECKSUM_MISMATCH")
		return
	if not _p4_prewarm_matches_package(prewarm, package, directory):
		_send_p4_fast_committed(request_id, transfer_id, false, "SM0_P4_FAST_PREWARM_PACKAGE_MISMATCH")
		return
	if not _p4_target_directory_allows_fast_commit(prewarm, directory):
		_send_p4_fast_committed(request_id, transfer_id, false, "SM0_P4_FAST_STALE_DIRECTORY")
		return

	var activated: Dictionary = _activate_imported_player(package)
	if not bool(activated.get("success", false)):
		_send_p4_fast_committed(request_id, transfer_id, false, String(activated.get("error_code", "SM0_TARGET_IMPORT_FAILED")))
		return
	_directory = directory.duplicate(true)
	_committed_transfers[transfer_id] = {
		"package": package.duplicate(true),
		"prewarm_id": prewarm_id,
		"prewarm_checksum": String(prewarm.get("checksum", "")),
		"session_id": String(activated.get("details", {}).get("session_id", "")),
		"player": Dictionary(activated.get("details", {}).get("player", {})).duplicate(true),
		"directory": _directory.duplicate(true),
		"p4_fast": true,
	}
	_prewarmed_transfers.erase(prewarm_id)
	_event("SM0_P4_FAST_COMMIT_ACCEPTED", {
		"transfer_id": transfer_id,
		"prewarm_id": prewarm_id,
		"directory": _directory,
		"player": activated.get("details", {}).get("player", {}),
	})
	_event("SM0_TARGET_AUTHORITY_COMMITTED", {
		"transfer_id": transfer_id,
		"directory": _directory,
		"player": activated.get("details", {}).get("player", {}),
		"path": "P4_FAST",
	})
	_send_p4_fast_committed(request_id, transfer_id, true, "")
	_p4_maybe_start_prewarm()


func _send_p4_fast_committed(request_id: String, transfer_id: String, success: bool, error_code: String) -> void:
	_send_control("PLAYER_HANDOFF_COMMITTED", {
		"success": success,
		"error_code": error_code,
		"transfer_id": transfer_id,
		"directory": _directory,
		"path": "P4_FAST",
	}, request_id)


func _p4_maybe_start_prewarm() -> void:
	if not _p4_enabled or not _source_transfer.is_empty() or not _frozen_transfer_id.is_empty():
		return
	if String(_directory.get("owner_authority_id", "")) != _authority_id:
		if not _source_prewarm.is_empty():
			_p4_cancel_source_prewarm("not-owner")
		return
	if _authority == null:
		return
	var player: Dictionary = _authority.get_player("a")
	if player.is_empty() or not bool(player.get("connected", false)):
		return
	var position: Dictionary = Dictionary(player.get("position", {}))
	var x := float(position.get("x", 0.0))
	var in_band := (
		(_zone_id == Contracts.ZONE_A and x >= -P4_PREWARM_DISTANCE_M and x < 0.0)
		or (_zone_id == Contracts.ZONE_B and x >= 0.0 and x < P4_PREWARM_DISTANCE_M)
	)
	if not in_band:
		if not _source_prewarm.is_empty():
			_p4_cancel_source_prewarm("left-band")
		return
	if not _source_prewarm.is_empty():
		return

	_p4_prewarm_counter += 1
	var source_epoch := int(_directory.get("authority_epoch", 1))
	var target_epoch := source_epoch + 1
	var prewarm_id := "prewarm/sm0/%s/%d/%d" % [_authority_id.get_slice("/", 2), target_epoch, _p4_prewarm_counter]
	var prewarm: Dictionary = Contracts.create_handoff_prewarm(
		prewarm_id,
		String(player.get("logical_player_id", "")),
		String(player.get("player_entity_id", "")),
		_authority_id,
		_peer_authority_id,
		_zone_id,
		_peer_zone_id,
		source_epoch,
		target_epoch,
		int(_directory.get("revision", 1)),
		P4_PREWARM_TTL_MS
	)
	var check: Dictionary = Contracts.validate_handoff_prewarm(prewarm)
	if not bool(check.get("success", false)):
		_invariant(String(check.get("error_code", "SM0_HANDOFF_PREWARM_INVALID")), {"prewarm_id": prewarm_id})
		return
	_source_prewarm = {
		"prewarm": prewarm,
		"stage": "SENT",
		"expires_at_local_ms": Time.get_ticks_msec() + P4_PREWARM_TTL_MS,
		"last_send_ms": 0,
		"retries": 0,
	}
	_event("SM0_P4_PREWARM_SENT", {
		"prewarm_id": prewarm_id,
		"prewarm_checksum": String(prewarm.get("checksum", "")),
		"directory": _directory,
	})
	_p4_send_source_prewarm()


func _p4_tick_source_prewarm(now: int) -> void:
	if _source_prewarm.is_empty():
		return
	if now >= int(_source_prewarm.get("expires_at_local_ms", 0)):
		_event("SM0_P4_PREWARM_EXPIRED", {
			"prewarm_id": String(Dictionary(_source_prewarm.get("prewarm", {})).get("prewarm_id", "")),
			"side": "source",
		})
		_source_prewarm.clear()
		return
	if String(_source_prewarm.get("stage", "")) != "SENT":
		return
	var last_send := int(_source_prewarm.get("last_send_ms", 0))
	if last_send > 0 and now - last_send < P4_PREWARM_RETRY_INTERVAL_MS:
		return
	var retries := int(_source_prewarm.get("retries", 0)) + 1
	_source_prewarm["retries"] = retries
	if retries > P4_PREWARM_MAX_RETRIES:
		_event("SM0_P4_PREWARM_REJECTED", {
			"prewarm_id": String(Dictionary(_source_prewarm.get("prewarm", {})).get("prewarm_id", "")),
			"error_code": "SM0_HANDOFF_PREWARM_TIMEOUT",
		})
		_source_prewarm.clear()
		return
	_p4_send_source_prewarm()


func _p4_send_source_prewarm() -> void:
	if _source_prewarm.is_empty():
		return
	var prewarm: Dictionary = Dictionary(_source_prewarm.get("prewarm", {}))
	_source_prewarm["last_send_ms"] = Time.get_ticks_msec()
	_send_control("PLAYER_HANDOFF_PREWARM", {"prewarm": prewarm}, String(prewarm.get("prewarm_id", "")))


func _p4_cancel_source_prewarm(reason: String) -> void:
	if _source_prewarm.is_empty():
		return
	var prewarm: Dictionary = Dictionary(_source_prewarm.get("prewarm", {}))
	_send_control("PLAYER_HANDOFF_PREWARM_CANCEL", {
		"prewarm_id": String(prewarm.get("prewarm_id", "")),
		"prewarm_checksum": String(prewarm.get("checksum", "")),
	}, String(prewarm.get("prewarm_id", "")))
	_event("SM0_P4_PREWARM_CANCELLED", {
		"prewarm_id": String(prewarm.get("prewarm_id", "")),
		"side": "source",
		"reason": reason,
	})
	_source_prewarm.clear()


func _p4_purge_expired_reservations(now: int) -> void:
	var expired_ids: Array[String] = []
	for key in _prewarmed_transfers.keys():
		var prewarm_id := String(key)
		var reservation: Dictionary = Dictionary(_prewarmed_transfers[key])
		if now >= int(reservation.get("expires_at_local_ms", 0)):
			expired_ids.append(prewarm_id)
	for prewarm_id in expired_ids:
		_prewarmed_transfers.erase(prewarm_id)
		_event("SM0_P4_PREWARM_EXPIRED", {"prewarm_id": prewarm_id, "side": "target"})


func _p4_can_fast_handoff(player: Dictionary) -> bool:
	if _source_prewarm.is_empty() or String(_source_prewarm.get("stage", "")) != "ACKED":
		return false
	if Time.get_ticks_msec() >= int(_source_prewarm.get("expires_at_local_ms", 0)):
		return false
	var prewarm: Dictionary = Dictionary(_source_prewarm.get("prewarm", {}))
	var check: Dictionary = Contracts.validate_handoff_prewarm(prewarm)
	if not bool(check.get("success", false)):
		return false
	return (
		String(player.get("logical_player_id", "")) == String(prewarm.get("logical_player_id", ""))
		and String(player.get("player_entity_id", "")) == String(prewarm.get("player_entity_id", ""))
		and String(prewarm.get("source_authority_id", "")) == _authority_id
		and String(prewarm.get("target_authority_id", "")) == _peer_authority_id
		and int(prewarm.get("source_authority_epoch", 0)) == int(_directory.get("authority_epoch", 0))
		and int(prewarm.get("source_directory_revision", 0)) == int(_directory.get("revision", 0))
	)


func _p4_fast_unavailable_reason(player: Dictionary) -> String:
	if _source_prewarm.is_empty():
		return "NO_PREWARM"
	if String(_source_prewarm.get("stage", "")) != "ACKED":
		return "PREWARM_NOT_ACKED"
	if Time.get_ticks_msec() >= int(_source_prewarm.get("expires_at_local_ms", 0)):
		return "PREWARM_EXPIRED"
	var prewarm: Dictionary = Dictionary(_source_prewarm.get("prewarm", {}))
	if String(player.get("player_entity_id", "")) != String(prewarm.get("player_entity_id", "")):
		return "PLAYER_IDENTITY_MISMATCH"
	if int(prewarm.get("source_authority_epoch", 0)) != int(_directory.get("authority_epoch", 0)):
		return "AUTHORITY_EPOCH_CHANGED"
	if int(prewarm.get("source_directory_revision", 0)) != int(_directory.get("revision", 0)):
		return "DIRECTORY_REVISION_CHANGED"
	return "PREWARM_INVALID"


func _p4_prewarm_matches_package(prewarm: Dictionary, package: Dictionary, directory: Dictionary) -> bool:
	return (
		String(prewarm.get("logical_player_id", "")) == String(package.get("logical_player_id", ""))
		and String(prewarm.get("player_entity_id", "")) == String(package.get("player_entity_id", ""))
		and String(prewarm.get("source_authority_id", "")) == String(package.get("source_authority_id", ""))
		and String(prewarm.get("target_authority_id", "")) == String(package.get("target_authority_id", ""))
		and String(prewarm.get("source_zone_id", "")) == String(package.get("source_zone_id", ""))
		and String(prewarm.get("target_zone_id", "")) == String(package.get("target_zone_id", ""))
		and int(prewarm.get("source_authority_epoch", 0)) == int(package.get("source_authority_epoch", 0))
		and int(prewarm.get("target_authority_epoch", 0)) == int(package.get("target_authority_epoch", 0))
		and int(prewarm.get("source_directory_revision", 0)) == int(package.get("directory_revision", 0))
		and int(directory.get("authority_epoch", 0)) == int(package.get("target_authority_epoch", 0))
		and int(directory.get("revision", 0)) == int(prewarm.get("source_directory_revision", 0)) + 1
	)


func _p4_target_directory_allows_fast_commit(prewarm: Dictionary, directory: Dictionary) -> bool:
	var current_owner := String(_directory.get("owner_authority_id", ""))
	var current_epoch := int(_directory.get("authority_epoch", 0))
	var current_revision := int(_directory.get("revision", 0))
	var source_state_matches := (
		current_owner == String(prewarm.get("source_authority_id", ""))
		and current_epoch == int(prewarm.get("source_authority_epoch", 0))
		and current_revision == int(prewarm.get("source_directory_revision", 0))
	)
	var committed_directory_already_observed := (
		String(_directory.get("checksum", "")) == String(directory.get("checksum", ""))
		and current_owner == _authority_id
		and current_epoch == int(prewarm.get("target_authority_epoch", 0))
	)
	return source_state_matches or committed_directory_already_observed


func _p4_env_enabled() -> bool:
	return OS.get_environment("SM0_P4_FAST_HANDOFF").strip_edges().to_lower() in ["1", "true", "yes", "on"]
