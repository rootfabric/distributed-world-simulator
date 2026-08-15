extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_v2.gd"

const RecoveryUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const RECOVERY_SCHEMA := "distributed_world_simulator.sm0_handoff_recovery_snapshot.v1"
const RECOVERY_PREFIX := "recovery-"
const RECOVERY_SUFFIX := ".json"

var _recovery_root := ""
var _recovery_authority_dir := ""
var _recovery_generation := 0
var _recovery_last_phase := ""
var _recovery_last_transfer_id := ""
var _recovery_restored := false
var _recovery_persisted_commits: Dictionary = {}


func setup(config: Dictionary) -> Dictionary:
	_recovery_root = String(config.get("recovery_dir", "")).strip_edges()
	var result: Dictionary = super.setup(config)
	if not bool(result.get("success", false)) or _recovery_root.is_empty():
		return result
	var authority_slug := "authority-a" if _authority_id == Contracts.AUTHORITY_A else "authority-b"
	_recovery_authority_dir = _recovery_root.path_join(authority_slug)
	var make_error := DirAccess.make_dir_recursive_absolute(_recovery_authority_dir)
	if make_error != OK:
		return _failure("SM0_RECOVERY_DIRECTORY_CREATE_FAILED", {"error": make_error, "path": _recovery_authority_dir})
	var restore := _restore_latest_recovery()
	if not bool(restore.get("success", false)):
		return restore
	_event("SM0_RECOVERY_ENABLED", {
		"recovery_dir": _recovery_authority_dir,
		"generation": _recovery_generation,
		"restored": _recovery_restored,
		"phase": _recovery_last_phase,
		"transfer_id": _recovery_last_transfer_id,
	})
	return result


func _send_control(message_type: String, payload: Dictionary, request_id: String = "") -> void:
	if message_type == "PLAYER_HANDOFF_COMMITTED" and bool(payload.get("success", false)):
		var transfer_id := String(payload.get("transfer_id", "")).strip_edges()
		var persisted := _ensure_target_commit_persisted(transfer_id)
		if not bool(persisted.get("success", false)):
			_invariant("SM0_RECOVERY_PERSIST_BEFORE_COMMITTED_ACK_FAILED", {
				"transfer_id": transfer_id,
				"cause": persisted,
			})
			return
	super._send_control(message_type, payload, request_id)


func _handle_client_activate(request_id: String, payload: Dictionary, remote_ip: String, remote_port: int) -> void:
	var transfer_id := String(payload.get("transfer_id", "")).strip_edges()
	if _committed_transfers.has(transfer_id):
		var committed: Dictionary = Dictionary(_committed_transfers[transfer_id])
		var committed_directory: Dictionary = Dictionary(committed.get("directory", {}))
		if (
			String(_directory.get("owner_authority_id", "")) == _authority_id
			and not _same_directory(committed_directory, _directory)
		):
			_send_gameplay(remote_ip, remote_port, "SM0_ERROR", {
				"error_code": "SM0_RECOVERY_STALE_COMMITTED_TRANSFER",
				"directory": _directory,
			}, request_id)
			return
		if bool(committed.get("needs_session_rebind", false)):
			var rebound := _rebind_committed_session(transfer_id)
			if not bool(rebound.get("success", false)):
				_send_gameplay(remote_ip, remote_port, "SM0_ERROR", {
					"error_code": String(rebound.get("error_code", "SM0_RECOVERY_SESSION_REBIND_FAILED")),
					"directory": _directory,
				}, request_id)
				return
	super._handle_client_activate(request_id, payload, remote_ip, remote_port)


func _commit_source_transfer() -> void:
	var transfer_id := String(_source_transfer.get("transfer_id", ""))
	super._commit_source_transfer()
	if _recovery_root.is_empty() or transfer_id.is_empty():
		return
	if (
		not _source_transfer.is_empty()
		and String(_source_transfer.get("stage", "")) == "COMMIT_SENT"
		and String(_directory.get("owner_authority_id", "")) != _authority_id
	):
		var persisted := _persist_recovery_snapshot("SOURCE_RETIRED", transfer_id)
		if not bool(persisted.get("success", false)):
			_invariant("SM0_RECOVERY_SOURCE_RETIRE_PERSIST_FAILED", {
				"transfer_id": transfer_id,
				"cause": persisted,
			})


func _ensure_target_commit_persisted(transfer_id: String) -> Dictionary:
	if _recovery_root.is_empty():
		return _success({"persistence": "disabled"})
	if transfer_id.is_empty() or not _committed_transfers.has(transfer_id):
		return _failure("SM0_RECOVERY_COMMITTED_TRANSFER_REQUIRED", {"transfer_id": transfer_id})
	if _recovery_persisted_commits.has(transfer_id):
		return _success({
			"generation": int(_recovery_persisted_commits[transfer_id]),
			"replay": true,
		})
	var persisted := _persist_recovery_snapshot("TARGET_COMMITTED", transfer_id)
	if bool(persisted.get("success", false)):
		_recovery_persisted_commits[transfer_id] = int(persisted.get("details", {}).get("generation", _recovery_generation))
	return persisted


func _persist_recovery_snapshot(phase: String, transfer_id: String) -> Dictionary:
	if _recovery_authority_dir.is_empty():
		return _failure("SM0_RECOVERY_DIRECTORY_NOT_READY")
	var next_generation := _recovery_generation + 1
	var gameplay_state: Dictionary = _authority.export_durable_state()
	var replay_state: Dictionary = _authority.export_replay_state()
	if gameplay_state.is_empty() or replay_state.is_empty():
		return _failure("SM0_RECOVERY_CANONICAL_STATE_EXPORT_FAILED")
	var snapshot := {
		"schema": RECOVERY_SCHEMA,
		"generation": next_generation,
		"authority_id": _authority_id,
		"zone_id": _zone_id,
		"phase": phase,
		"transfer_id": transfer_id,
		"directory": _directory.duplicate(true),
		"transfer_counter": _transfer_counter,
		"source_transfer": _export_source_transfer_metadata(phase),
		"prepared_transfers": _prepared_transfers.duplicate(true),
		"committed_transfers": _export_committed_metadata(),
		"gameplay_state": gameplay_state,
		"gameplay_replay_state": replay_state,
		"checksum": "",
	}
	snapshot = RecoveryUtils.finalize_json_checksum(snapshot)
	var validation := _validate_recovery_snapshot(snapshot)
	if not bool(validation.get("success", false)):
		return _failure("SM0_RECOVERY_SNAPSHOT_INVALID_BEFORE_WRITE", {"cause": validation})

	var stem := "%s%08d%s" % [RECOVERY_PREFIX, next_generation, RECOVERY_SUFFIX]
	var final_path := _recovery_authority_dir.path_join(stem)
	var temp_path := "%s.tmp" % final_path
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _failure("SM0_RECOVERY_SNAPSHOT_OPEN_FAILED", {
			"error": FileAccess.get_open_error(),
			"path": temp_path,
		})
	file.store_string(JSON.stringify(snapshot, "", false, true))
	file.flush()
	file.close()
	var rename_error := DirAccess.rename_absolute(temp_path, final_path)
	if rename_error != OK:
		DirAccess.remove_absolute(temp_path)
		return _failure("SM0_RECOVERY_SNAPSHOT_RENAME_FAILED", {
			"error": rename_error,
			"path": final_path,
		})

	_recovery_generation = next_generation
	_recovery_last_phase = phase
	_recovery_last_transfer_id = transfer_id
	_event("SM0_RECOVERY_SNAPSHOT_PERSISTED", {
		"generation": _recovery_generation,
		"phase": phase,
		"transfer_id": transfer_id,
		"path": final_path,
		"gameplay_checksum": String(gameplay_state.get("checksum", "")),
		"replay_checksum": String(replay_state.get("checksum", "")),
	})
	return _success({"generation": _recovery_generation, "path": final_path})


func _restore_latest_recovery() -> Dictionary:
	var dir := DirAccess.open(_recovery_authority_dir)
	if dir == null:
		return _failure("SM0_RECOVERY_DIRECTORY_OPEN_FAILED", {"path": _recovery_authority_dir})
	var candidates: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if (
			not dir.current_is_dir()
			and name.begins_with(RECOVERY_PREFIX)
			and name.ends_with(RECOVERY_SUFFIX)
		):
			candidates.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	candidates.sort()
	candidates.reverse()
	if candidates.is_empty():
		_event("SM0_RECOVERY_EMPTY", {"recovery_dir": _recovery_authority_dir})
		return _success({"restored": false})

	var rejected: Array[String] = []
	for candidate in candidates:
		var path := _recovery_authority_dir.path_join(candidate)
		var loaded := _load_recovery_snapshot(path)
		if not bool(loaded.get("success", false)):
			rejected.append(candidate)
			_event("SM0_RECOVERY_SNAPSHOT_SKIPPED", {
				"path": path,
				"error_code": String(loaded.get("error_code", "SM0_RECOVERY_SNAPSHOT_INVALID")),
			})
			continue
		var snapshot: Dictionary = Dictionary(loaded.get("details", {}).get("snapshot", {}))
		var applied := _apply_recovery_snapshot(snapshot, path)
		if bool(applied.get("success", false)):
			return applied
		rejected.append(candidate)
		_event("SM0_RECOVERY_SNAPSHOT_SKIPPED", {
			"path": path,
			"error_code": String(applied.get("error_code", "SM0_RECOVERY_APPLY_FAILED")),
		})
	return _failure("SM0_RECOVERY_NO_VALID_SNAPSHOT", {"rejected": rejected})


func _load_recovery_snapshot(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("SM0_RECOVERY_SNAPSHOT_READ_FAILED", {"path": path, "error": FileAccess.get_open_error()})
	var text := file.get_as_text()
	file.close()
	var decoded = JSON.parse_string(text)
	if not decoded is Dictionary:
		return _failure("SM0_RECOVERY_SNAPSHOT_JSON_INVALID", {"path": path})
	var snapshot: Dictionary = Dictionary(decoded)
	var validation := _validate_recovery_snapshot(snapshot)
	if not bool(validation.get("success", false)):
		return validation
	return _success({"snapshot": snapshot})


func _validate_recovery_snapshot(value: Dictionary) -> Dictionary:
	if String(value.get("schema", "")) != RECOVERY_SCHEMA:
		return _failure("SM0_RECOVERY_SCHEMA_INVALID")
	if String(value.get("authority_id", "")) != _authority_id or String(value.get("zone_id", "")) != _zone_id:
		return _failure("SM0_RECOVERY_AUTHORITY_MISMATCH")
	if int(value.get("generation", 0)) < 1:
		return _failure("SM0_RECOVERY_GENERATION_INVALID")
	var phase := String(value.get("phase", ""))
	if phase not in ["TARGET_COMMITTED", "SOURCE_RETIRED"]:
		return _failure("SM0_RECOVERY_PHASE_INVALID")
	var directory: Dictionary = Dictionary(value.get("directory", {}))
	var directory_check := Contracts.validate_directory(directory)
	if not bool(directory_check.get("success", false)):
		return _failure("SM0_RECOVERY_DIRECTORY_INVALID", {"cause": directory_check})
	if typeof(value.get("source_transfer", {})) != TYPE_DICTIONARY:
		return _failure("SM0_RECOVERY_SOURCE_TRANSFER_INVALID")
	if typeof(value.get("prepared_transfers")) != TYPE_DICTIONARY or typeof(value.get("committed_transfers")) != TYPE_DICTIONARY:
		return _failure("SM0_RECOVERY_TRANSFER_MAP_INVALID")
	if typeof(value.get("gameplay_state")) != TYPE_DICTIONARY or typeof(value.get("gameplay_replay_state")) != TYPE_DICTIONARY:
		return _failure("SM0_RECOVERY_GAMEPLAY_STATE_REQUIRED")
	var durable_check := _authority.validate_durable_state(Dictionary(value.get("gameplay_state", {})))
	if not bool(durable_check.get("success", false)):
		return _failure("SM0_RECOVERY_GAMEPLAY_STATE_INVALID", {"cause": durable_check})
	var replay_check := _authority.validate_replay_state(Dictionary(value.get("gameplay_replay_state", {})))
	if not bool(replay_check.get("success", false)):
		return _failure("SM0_RECOVERY_REPLAY_STATE_INVALID", {"cause": replay_check})

	var source_transfer: Dictionary = Dictionary(value.get("source_transfer", {}))
	if phase == "SOURCE_RETIRED":
		var source_check := _validate_source_transfer_metadata(
			source_transfer,
			String(value.get("transfer_id", "")),
			directory,
			Dictionary(value.get("gameplay_state", {}))
		)
		if not bool(source_check.get("success", false)):
			return source_check
	elif not source_transfer.is_empty():
		return _failure("SM0_RECOVERY_TARGET_SNAPSHOT_HAS_SOURCE_TRANSFER")

	for transfer_id_value in Dictionary(value.get("prepared_transfers", {})).keys():
		var transfer_id := String(transfer_id_value)
		var package: Dictionary = Dictionary(value["prepared_transfers"][transfer_id_value])
		var package_check := Contracts.validate_handoff_package(package)
		if (
			not bool(package_check.get("success", false))
			or String(package.get("transfer_id", "")) != transfer_id
			or String(package.get("target_authority_id", "")) != _authority_id
		):
			return _failure("SM0_RECOVERY_PREPARED_TRANSFER_INVALID", {"transfer_id": transfer_id})

	for transfer_id_value in Dictionary(value.get("committed_transfers", {})).keys():
		var transfer_id := String(transfer_id_value)
		var entry_value = value["committed_transfers"][transfer_id_value]
		if not entry_value is Dictionary:
			return _failure("SM0_RECOVERY_COMMITTED_TRANSFER_INVALID", {"transfer_id": transfer_id})
		var entry: Dictionary = Dictionary(entry_value)
		var package: Dictionary = Dictionary(entry.get("package", {}))
		var committed_directory: Dictionary = Dictionary(entry.get("directory", {}))
		var package_check := Contracts.validate_handoff_package(package)
		var committed_directory_check := Contracts.validate_directory(committed_directory)
		if (
			not bool(package_check.get("success", false))
			or not bool(committed_directory_check.get("success", false))
			or String(package.get("transfer_id", "")) != transfer_id
			or String(package.get("target_authority_id", "")) != _authority_id
			or String(committed_directory.get("owner_authority_id", "")) != _authority_id
			or int(committed_directory.get("authority_epoch", 0)) != int(package.get("target_authority_epoch", 0))
			or String(entry.get("session_id", "")).is_empty()
		):
			return _failure("SM0_RECOVERY_COMMITTED_TRANSFER_INVALID", {"transfer_id": transfer_id})

	var expected_checksum := String(value.get("checksum", ""))
	var checksum_payload := value.duplicate(true)
	checksum_payload.erase("checksum")
	if expected_checksum.is_empty() or expected_checksum != RecoveryUtils.payload_hash(checksum_payload):
		return _failure("SM0_RECOVERY_CHECKSUM_MISMATCH")
	return _success()


func _validate_source_transfer_metadata(value: Dictionary, transfer_id: String, directory: Dictionary, gameplay_state: Dictionary) -> Dictionary:
	if value.is_empty() or transfer_id.is_empty():
		return _failure("SM0_RECOVERY_SOURCE_TRANSFER_REQUIRED")
	if String(value.get("transfer_id", "")) != transfer_id or String(value.get("stage", "")) != "COMMIT_SENT":
		return _failure("SM0_RECOVERY_SOURCE_TRANSFER_STAGE_INVALID", {"transfer_id": transfer_id})
	var package: Dictionary = Dictionary(value.get("package", {}))
	var package_check := Contracts.validate_handoff_package(package)
	if not bool(package_check.get("success", false)):
		return _failure("SM0_RECOVERY_SOURCE_PACKAGE_INVALID", {"cause": package_check})
	if (
		String(package.get("transfer_id", "")) != transfer_id
		or String(package.get("source_authority_id", "")) != _authority_id
		or String(package.get("target_authority_id", "")) != _peer_authority_id
		or String(directory.get("owner_authority_id", "")) != _peer_authority_id
		or int(directory.get("authority_epoch", 0)) != int(package.get("target_authority_epoch", 0))
		or int(directory.get("revision", 0)) != int(package.get("directory_revision", 0)) + 1
	):
		return _failure("SM0_RECOVERY_SOURCE_ROUTE_INVALID", {"transfer_id": transfer_id})
	var client_ip := String(value.get("client_ip", "")).strip_edges()
	var client_port := int(value.get("client_port", 0))
	if client_ip.is_empty() or client_port < 1 or client_port > 65535:
		return _failure("SM0_RECOVERY_SOURCE_CLIENT_ENDPOINT_INVALID", {"transfer_id": transfer_id})
	if bool(value.get("target_committed", true)) or bool(value.get("client_redirect_acked", true)):
		return _failure("SM0_RECOVERY_SOURCE_ACK_STATE_INVALID", {"transfer_id": transfer_id})
	var durable_players: Array = Array(Dictionary(gameplay_state.get("players", {})).get("players", []))
	var found_player := false
	for record_value in durable_players:
		if not record_value is Dictionary:
			continue
		var record: Dictionary = Dictionary(record_value)
		if String(record.get("logical_player_id", "")) != "a":
			continue
		found_player = true
		if (
			String(record.get("player_entity_id", "")) != String(package.get("player_entity_id", ""))
			or bool(record.get("connected", true))
			or not String(record.get("transport_session_id", "")).is_empty()
		):
			return _failure("SM0_RECOVERY_SOURCE_PLAYER_NOT_RETIRED", {"transfer_id": transfer_id})
		break
	if not found_player:
		return _failure("SM0_RECOVERY_SOURCE_PLAYER_MISSING", {"transfer_id": transfer_id})
	return _success()


func _apply_recovery_snapshot(snapshot: Dictionary, path: String) -> Dictionary:
	var durable_result := _authority.restore_durable_state(Dictionary(snapshot.get("gameplay_state", {})))
	if not bool(durable_result.get("success", false)):
		return _failure("SM0_RECOVERY_GAMEPLAY_RESTORE_FAILED", {"cause": durable_result})
	var replay_result := _authority.restore_replay_state(Dictionary(snapshot.get("gameplay_replay_state", {})))
	if not bool(replay_result.get("success", false)):
		return _failure("SM0_RECOVERY_REPLAY_RESTORE_FAILED", {"cause": replay_result})

	_directory = Dictionary(snapshot.get("directory", {})).duplicate(true)
	_transfer_counter = int(snapshot.get("transfer_counter", 0))
	_prepared_transfers = Dictionary(snapshot.get("prepared_transfers", {})).duplicate(true)
	_committed_transfers.clear()
	_recovery_persisted_commits.clear()
	var canonical_player: Dictionary = _authority.get_player("a")
	for transfer_id_value in Dictionary(snapshot.get("committed_transfers", {})).keys():
		var transfer_id := String(transfer_id_value)
		var entry: Dictionary = Dictionary(snapshot["committed_transfers"][transfer_id_value])
		var committed_directory: Dictionary = Dictionary(entry.get("directory", {})).duplicate(true)
		var is_current := (
			String(_directory.get("owner_authority_id", "")) == _authority_id
			and _same_directory(committed_directory, _directory)
		)
		var player_projection: Dictionary = canonical_player.duplicate(true) if is_current else {
			"player_entity_id": String(Dictionary(entry.get("package", {})).get("player_entity_id", "")),
		}
		_committed_transfers[transfer_id] = {
			"package": Dictionary(entry.get("package", {})).duplicate(true),
			"session_id": String(entry.get("session_id", "")),
			"player": player_projection,
			"directory": committed_directory,
			"needs_session_rebind": is_current,
		}
		_recovery_persisted_commits[transfer_id] = int(snapshot.get("generation", 0))

	_active_session_id = ""
	_active_client_ip = ""
	_active_client_port = 0
	_frozen_transfer_id = ""
	_source_transfer.clear()
	var phase := String(snapshot.get("phase", ""))
	if phase == "SOURCE_RETIRED":
		var source_metadata: Dictionary = Dictionary(snapshot.get("source_transfer", {}))
		var source_transfer_id := String(source_metadata.get("transfer_id", ""))
		_source_transfer = {
			"transfer_id": source_transfer_id,
			"package": Dictionary(source_metadata.get("package", {})).duplicate(true),
			"stage": "COMMIT_SENT",
			"last_send_ms": 0,
			"retries": 0,
			"client_ip": String(source_metadata.get("client_ip", "")),
			"client_port": int(source_metadata.get("client_port", 0)),
			"target_committed": false,
			"client_redirect_acked": false,
		}
		_frozen_transfer_id = source_transfer_id

	_recovery_generation = int(snapshot.get("generation", 0))
	_recovery_last_phase = phase
	_recovery_last_transfer_id = String(snapshot.get("transfer_id", ""))
	_recovery_restored = true
	_event("SM0_RECOVERY_RESTORED", {
		"generation": _recovery_generation,
		"phase": _recovery_last_phase,
		"transfer_id": _recovery_last_transfer_id,
		"path": path,
		"directory": _directory,
		"gameplay_checksum": String(Dictionary(snapshot.get("gameplay_state", {})).get("checksum", "")),
		"replay_checksum": String(Dictionary(snapshot.get("gameplay_replay_state", {})).get("checksum", "")),
	})
	if phase == "SOURCE_RETIRED":
		_event("SM0_RECOVERY_SOURCE_TRANSFER_RESUMED", {
			"generation": _recovery_generation,
			"transfer_id": _recovery_last_transfer_id,
			"stage": String(_source_transfer.get("stage", "")),
			"directory": _directory,
		})
	return _success({"restored": true, "generation": _recovery_generation, "path": path})


func _rebind_committed_session(transfer_id: String) -> Dictionary:
	if not _committed_transfers.has(transfer_id):
		return _failure("SM0_RECOVERY_COMMITTED_TRANSFER_REQUIRED", {"transfer_id": transfer_id})
	var committed: Dictionary = Dictionary(_committed_transfers[transfer_id])
	var package: Dictionary = Dictionary(committed.get("package", {}))
	var session_id := String(committed.get("session_id", "")).strip_edges()
	if session_id.is_empty():
		return _failure("SM0_RECOVERY_TARGET_SESSION_REQUIRED")
	var before: Dictionary = _authority.get_player("a")
	if before.is_empty() or bool(before.get("connected", true)):
		return _failure("SM0_RECOVERY_PLAYER_NOT_DURABLY_DISCONNECTED")
	if String(before.get("player_entity_id", "")) != String(package.get("player_entity_id", "")):
		return _failure("SM0_RECOVERY_PLAYER_IDENTITY_MISMATCH")
	var operation_id := "operation/sm0/%s/recovery-rebind/%s/%d" % [
		_authority_id.get_slice("/", 2),
		transfer_id.sha256_text().left(12),
		_recovery_generation,
	]
	var joined: Dictionary = _authority.join("a", session_id, operation_id)
	if not bool(joined.get("success", false)):
		return _failure("SM0_RECOVERY_SESSION_REBIND_FAILED", {"cause": joined})
	var player: Dictionary = Dictionary(joined.get("details", {}).get("player", {}))
	if String(player.get("player_entity_id", "")) != String(before.get("player_entity_id", "")):
		return _failure("SM0_RECOVERY_PLAYER_IDENTITY_CHANGED")
	if not _same_position(Dictionary(player.get("position", {})), Dictionary(before.get("position", {}))):
		return _failure("SM0_RECOVERY_PLAYER_POSITION_CHANGED")
	if int(player.get("last_input_sequence", -1)) != int(before.get("last_input_sequence", -2)):
		return _failure("SM0_RECOVERY_INPUT_SEQUENCE_CHANGED")
	committed["player"] = player.duplicate(true)
	committed["needs_session_rebind"] = false
	_committed_transfers[transfer_id] = committed
	_event("SM0_RECOVERY_SESSION_REBOUND", {
		"generation": _recovery_generation,
		"transfer_id": transfer_id,
		"session_id": session_id,
		"previous_ownership_epoch": int(before.get("ownership_epoch", 0)),
		"ownership_epoch": int(player.get("ownership_epoch", 0)),
		"player_entity_id": String(player.get("player_entity_id", "")),
	})
	return _success({"player": player})


func _export_source_transfer_metadata(phase: String) -> Dictionary:
	if phase != "SOURCE_RETIRED" or _source_transfer.is_empty():
		return {}
	return {
		"transfer_id": String(_source_transfer.get("transfer_id", "")),
		"package": Dictionary(_source_transfer.get("package", {})).duplicate(true),
		"stage": String(_source_transfer.get("stage", "")),
		"client_ip": String(_source_transfer.get("client_ip", "")),
		"client_port": int(_source_transfer.get("client_port", 0)),
		"target_committed": bool(_source_transfer.get("target_committed", false)),
		"client_redirect_acked": bool(_source_transfer.get("client_redirect_acked", false)),
	}


func _export_committed_metadata() -> Dictionary:
	var result: Dictionary = {}
	var transfer_ids := _committed_transfers.keys()
	transfer_ids.sort()
	for transfer_id_value in transfer_ids:
		var transfer_id := String(transfer_id_value)
		var entry: Dictionary = Dictionary(_committed_transfers[transfer_id_value])
		result[transfer_id] = {
			"package": Dictionary(entry.get("package", {})).duplicate(true),
			"session_id": String(entry.get("session_id", "")),
			"directory": Dictionary(entry.get("directory", {})).duplicate(true),
		}
	return result


func _same_directory(a: Dictionary, b: Dictionary) -> bool:
	return (
		not a.is_empty()
		and not b.is_empty()
		and String(a.get("checksum", "")) == String(b.get("checksum", ""))
	)


func _same_position(a: Dictionary, b: Dictionary) -> bool:
	return (
		absf(float(a.get("x", 0.0)) - float(b.get("x", 0.0))) <= 0.000001
		and absf(float(a.get("y", 0.0)) - float(b.get("y", 0.0))) <= 0.000001
		and absf(float(a.get("z", 0.0)) - float(b.get("z", 0.0))) <= 0.000001
	)
