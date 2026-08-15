extends Node

signal finished(exit_code: int)

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const Authority = preload("res://scripts/runtime/host_client/multiplayer_gameplay_authority.gd")

const HELLO_INTERVAL_MS := 500
const RETRY_INTERVAL_MS := 200
const STOP_POLL_INTERVAL_MS := 250
const MAX_STAGE_RETRIES := 100

var _authority_id := ""
var _zone_id := ""
var _gameplay_host := "127.0.0.1"
var _gameplay_port := 0
var _control_host := "127.0.0.1"
var _control_port := 0
var _peer_control_host := "127.0.0.1"
var _peer_control_port := 0
var _peer_authority_id := ""
var _peer_zone_id := ""
var _stop_file := ""
var _manifest_hash := "sm0-two-zone-v1"

var _gameplay_socket: PacketPeerUDP
var _control_socket: PacketPeerUDP
var _authority: Authority
var _directory: Dictionary = {}
var _peer_synced := false
var _directory_ready_logged := false
var _last_hello_ms := 0
var _last_stop_poll_ms := 0
var _transfer_counter := 0

var _active_client_ip := ""
var _active_client_port := 0
var _active_session_id := ""
var _frozen_transfer_id := ""
var _source_transfer: Dictionary = {}
var _prepared_transfers: Dictionary = {}
var _committed_transfers: Dictionary = {}


func setup(config: Dictionary) -> Dictionary:
	_authority_id = String(config.get("authority_id", "")).strip_edges()
	_zone_id = String(config.get("zone_id", "")).strip_edges()
	_gameplay_host = String(config.get("gameplay_host", "127.0.0.1")).strip_edges()
	_gameplay_port = int(config.get("gameplay_port", 0))
	_control_host = String(config.get("control_host", "127.0.0.1")).strip_edges()
	_control_port = int(config.get("control_port", 0))
	_peer_control_host = String(config.get("peer_control_host", "127.0.0.1")).strip_edges()
	_peer_control_port = int(config.get("peer_control_port", 0))
	_peer_authority_id = Contracts.peer_authority(_authority_id)
	_peer_zone_id = Contracts.peer_zone(_zone_id)
	_stop_file = String(config.get("stop_file", "")).strip_edges()
	_manifest_hash = String(config.get("manifest_hash", _manifest_hash)).strip_edges()
	if (
		_authority_id not in [Contracts.AUTHORITY_A, Contracts.AUTHORITY_B]
		or Contracts.authority_for_zone(_zone_id) != _authority_id
		or _gameplay_port < 1
		or _control_port < 1
		or _peer_control_port < 1
	):
		return _failure("SM0_INVALID_SERVER_CONFIGURATION")

	_authority = Authority.new()
	var authority_setup: Dictionary = _authority.setup(_authority_id, 1, 0)
	if not bool(authority_setup.get("success", false)):
		return _failure("SM0_AUTHORITY_SETUP_FAILED", {"cause": authority_setup})

	_directory = Contracts.create_directory(Contracts.AUTHORITY_A, 1, 1)
	var directory_check: Dictionary = Contracts.validate_directory(_directory)
	if not bool(directory_check.get("success", false)):
		return directory_check

	_gameplay_socket = PacketPeerUDP.new()
	var gameplay_bind := _gameplay_socket.bind(_gameplay_port, _gameplay_host)
	if gameplay_bind != OK:
		return _failure("SM0_GAMEPLAY_BIND_FAILED", {"error": gameplay_bind, "port": _gameplay_port})
	_control_socket = PacketPeerUDP.new()
	var control_bind := _control_socket.bind(_control_port, _control_host)
	if control_bind != OK:
		_gameplay_socket.close()
		return _failure("SM0_CONTROL_BIND_FAILED", {"error": control_bind, "port": _control_port})

	set_process(true)
	_event("SM0_SERVER_READY", {
		"authority_id": _authority_id,
		"zone_id": _zone_id,
		"gameplay_port": _gameplay_port,
		"control_port": _control_port,
		"directory": _directory,
	})
	return _success()


func _process(_delta: float) -> void:
	_poll_socket(_control_socket, true)
	_poll_socket(_gameplay_socket, false)
	var now := Time.get_ticks_msec()
	if now - _last_hello_ms >= HELLO_INTERVAL_MS:
		_last_hello_ms = now
		_send_hello()
	_retry_source_transfer(now)
	if not _stop_file.is_empty() and now - _last_stop_poll_ms >= STOP_POLL_INTERVAL_MS:
		_last_stop_poll_ms = now
		if FileAccess.file_exists(_stop_file):
			_shutdown(0, "stop-file")


func _poll_socket(socket: PacketPeerUDP, control: bool) -> void:
	if socket == null:
		return
	while socket.get_available_packet_count() > 0:
		var packet := socket.get_packet()
		var remote_ip := socket.get_packet_ip()
		var remote_port := socket.get_packet_port()
		var message := Contracts.decode_message(packet)
		var validation := Contracts.validate_message(message)
		if not bool(validation.get("success", false)):
			_event("SM0_INVARIANT_VIOLATION", {
				"error_code": String(validation.get("error_code", "SM0_INVALID_PACKET")),
				"channel": "control" if control else "gameplay",
			})
			continue
		if control:
			_handle_control_message(message, remote_ip, remote_port)
		else:
			_handle_gameplay_message(message, remote_ip, remote_port)


func _handle_gameplay_message(message: Dictionary, remote_ip: String, remote_port: int) -> void:
	var message_type := String(message.get("type", ""))
	var request_id := String(message.get("request_id", ""))
	var payload: Dictionary = Dictionary(message.get("payload", {}))
	match message_type:
		"CLIENT_JOIN":
			_handle_client_join(request_id, payload, remote_ip, remote_port)
		"CLIENT_MOVE":
			_handle_client_move(request_id, payload, remote_ip, remote_port)
		"CLIENT_ACTIVATE":
			_handle_client_activate(request_id, payload, remote_ip, remote_port)
		"CLIENT_REDIRECT_ACK":
			_handle_redirect_ack(request_id, payload, remote_ip, remote_port)
		"CLIENT_STATUS":
			_send_gameplay(remote_ip, remote_port, "STATUS", _status_payload(), request_id)
		_:
			_send_gameplay(remote_ip, remote_port, "SM0_ERROR", {"error_code": "SM0_UNKNOWN_GAMEPLAY_MESSAGE"}, request_id)


func _handle_client_join(request_id: String, payload: Dictionary, remote_ip: String, remote_port: int) -> void:
	if String(_directory.get("owner_authority_id", "")) != _authority_id:
		_send_gameplay(remote_ip, remote_port, "SM0_ERROR", {
			"error_code": "SM0_AUTHORITY_NOT_ACTIVE",
			"directory": _directory,
		}, request_id)
		return
	var logical_id := String(payload.get("logical_player_id", "")).strip_edges().to_lower()
	var session_id := String(payload.get("session_id", "")).strip_edges()
	if logical_id != "a" or session_id.is_empty():
		_send_gameplay(remote_ip, remote_port, "SM0_ERROR", {"error_code": "SM0_INVALID_JOIN"}, request_id)
		return
	var join := _authority.join(logical_id, session_id, "operation/sm0/%s/join/%s" % [_authority_id.get_slice("/", 2), request_id.sha256_text().left(12)])
	if not bool(join.get("success", false)):
		_send_gameplay(remote_ip, remote_port, "SM0_ERROR", {"error_code": String(join.get("error_code", "SM0_JOIN_FAILED"))}, request_id)
		return
	_active_client_ip = remote_ip
	_active_client_port = remote_port
	_active_session_id = session_id
	var player: Dictionary = Dictionary(join.get("details", {}).get("player", {}))
	_event("SM0_CLIENT_JOINED", {"player": player, "directory": _directory})
	_send_gameplay(remote_ip, remote_port, "JOIN_ACK", {
		"authority_id": _authority_id,
		"zone_id": _zone_id,
		"directory": _directory,
		"session_id": _active_session_id,
		"player": player,
	}, request_id)


func _handle_client_move(request_id: String, payload: Dictionary, remote_ip: String, remote_port: int) -> void:
	if String(_directory.get("owner_authority_id", "")) != _authority_id:
		_send_gameplay(remote_ip, remote_port, "SM0_ERROR", {"error_code": "SM0_STALE_SOURCE_AUTHORITY", "directory": _directory}, request_id)
		return
	if not _frozen_transfer_id.is_empty():
		_send_gameplay(remote_ip, remote_port, "MOVE_ACK", {
			"accepted": false,
			"error_code": "SM0_PLAYER_FROZEN_FOR_HANDOFF",
			"handoff_pending": true,
			"directory": _directory,
		}, request_id)
		return
	var session_id := String(payload.get("session_id", ""))
	if session_id != _active_session_id or remote_ip != _active_client_ip or remote_port != _active_client_port:
		_send_gameplay(remote_ip, remote_port, "SM0_ERROR", {"error_code": "SM0_STALE_CLIENT_SESSION"}, request_id)
		return
	var result := _authority.move_player(
		"a",
		session_id,
		int(payload.get("ownership_epoch", 0)),
		int(payload.get("input_sequence", 0)),
		float(payload.get("delta_x", 0.0)),
		float(payload.get("delta_z", 0.0)),
		"operation/sm0/client/a/move/%d" % int(payload.get("input_sequence", 0))
	)
	if not bool(result.get("success", false)):
		_send_gameplay(remote_ip, remote_port, "MOVE_ACK", {
			"accepted": false,
			"error_code": String(result.get("error_code", "SM0_MOVE_FAILED")),
			"directory": _directory,
		}, request_id)
		return
	var player: Dictionary = Dictionary(result.get("details", {}).get("player", {}))
	_send_gameplay(remote_ip, remote_port, "MOVE_ACK", {
		"accepted": true,
		"error_code": "",
		"handoff_pending": false,
		"authority_id": _authority_id,
		"directory": _directory,
		"player": player,
	}, request_id)
	if _should_begin_handoff(player):
		_begin_handoff(player)


func _should_begin_handoff(player: Dictionary) -> bool:
	if not _source_transfer.is_empty() or not _frozen_transfer_id.is_empty():
		return false
	var position: Dictionary = Dictionary(player.get("position", {}))
	var x := float(position.get("x", 0.0))
	return (_zone_id == Contracts.ZONE_A and x >= 0.0) or (_zone_id == Contracts.ZONE_B and x < 0.0)


func _begin_handoff(player: Dictionary) -> void:
	_transfer_counter += 1
	var source_epoch := int(_directory.get("authority_epoch", 1))
	var target_epoch := source_epoch + 1
	var transfer_id := "handoff/sm0/%s/%d/%d" % [_authority_id.get_slice("/", 2), target_epoch, _transfer_counter]
	var package := Contracts.create_handoff_package(
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
	var package_check := Contracts.validate_handoff_package(package)
	if not bool(package_check.get("success", false)):
		_invariant(String(package_check.get("error_code", "SM0_HANDOFF_PACKAGE_INVALID")), {"transfer_id": transfer_id})
		return
	_frozen_transfer_id = transfer_id
	_source_transfer = {
		"transfer_id": transfer_id,
		"package": package,
		"stage": "PREPARE_SENT",
		"last_send_ms": 0,
		"retries": 0,
		"client_ip": _active_client_ip,
		"client_port": _active_client_port,
	}
	_event("SM0_HANDOFF_BEGIN", {"transfer_id": transfer_id, "package": package})
	_event("SM0_SOURCE_FROZEN", {"transfer_id": transfer_id, "player": player})
	_send_source_prepare()


func _handle_control_message(message: Dictionary, _remote_ip: String, _remote_port: int) -> void:
	var message_type := String(message.get("type", ""))
	var request_id := String(message.get("request_id", ""))
	var payload: Dictionary = Dictionary(message.get("payload", {}))
	match message_type:
		"AUTHORITY_HELLO":
			_handle_authority_hello(request_id, payload)
		"AUTHORITY_HELLO_ACK":
			_handle_authority_hello_ack(payload)
		"PLAYER_HANDOFF_PREPARE":
			_handle_handoff_prepare(request_id, payload)
		"PLAYER_HANDOFF_PREPARED":
			_handle_handoff_prepared(request_id, payload)
		"PLAYER_HANDOFF_COMMIT":
			_handle_handoff_commit(request_id, payload)
		"PLAYER_HANDOFF_COMMITTED":
			_handle_handoff_committed(request_id, payload)
		_:
			pass


func _send_hello() -> void:
	_send_control("AUTHORITY_HELLO", {
		"authority_id": _authority_id,
		"zone_id": _zone_id,
		"manifest_hash": _manifest_hash,
		"directory": _directory,
	}, "hello/%s/%d" % [_authority_id.get_slice("/", 2), int(Time.get_ticks_msec() / HELLO_INTERVAL_MS)])


func _handle_authority_hello(request_id: String, payload: Dictionary) -> void:
	if (
		String(payload.get("authority_id", "")) != _peer_authority_id
		or String(payload.get("zone_id", "")) != _peer_zone_id
		or String(payload.get("manifest_hash", "")) != _manifest_hash
	):
		_invariant("SM0_AUTHORITY_HELLO_MISMATCH", payload)
		return
	_adopt_newer_directory(Dictionary(payload.get("directory", {})))
	if not _peer_synced:
		_peer_synced = true
		_event("SM0_AUTHORITY_PEER_SYNCED", {"peer_authority_id": _peer_authority_id, "directory": _directory})
	_log_directory_ready()
	_send_control("AUTHORITY_HELLO_ACK", {
		"authority_id": _authority_id,
		"manifest_hash": _manifest_hash,
		"directory": _directory,
	}, request_id)


func _handle_authority_hello_ack(payload: Dictionary) -> void:
	if String(payload.get("authority_id", "")) != _peer_authority_id or String(payload.get("manifest_hash", "")) != _manifest_hash:
		_invariant("SM0_AUTHORITY_HELLO_ACK_MISMATCH", payload)
		return
	_adopt_newer_directory(Dictionary(payload.get("directory", {})))
	if not _peer_synced:
		_peer_synced = true
		_event("SM0_AUTHORITY_PEER_SYNCED", {"peer_authority_id": _peer_authority_id, "directory": _directory})
	_log_directory_ready()


func _log_directory_ready() -> void:
	if _peer_synced and not _directory_ready_logged:
		_directory_ready_logged = true
		_event("SM0_DIRECTORY_READY", {"directory": _directory})


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
		_send_control("PLAYER_HANDOFF_PREPARED", {"success": false, "error_code": "SM0_HANDOFF_WRONG_TARGET", "transfer_id": transfer_id}, request_id)
		return
	if int(package.get("source_authority_epoch", 0)) != int(_directory.get("authority_epoch", 0)) or String(_directory.get("owner_authority_id", "")) != String(package.get("source_authority_id", "")):
		_send_control("PLAYER_HANDOFF_PREPARED", {"success": false, "error_code": "SM0_HANDOFF_STALE_DIRECTORY", "transfer_id": transfer_id}, request_id)
		return
	if _prepared_transfers.has(transfer_id):
		var existing: Dictionary = Dictionary(_prepared_transfers[transfer_id])
		if String(existing.get("checksum", "")) != String(package.get("checksum", "")):
			_send_control("PLAYER_HANDOFF_PREPARED", {"success": false, "error_code": "SM0_HANDOFF_PREPARE_CONFLICT", "transfer_id": transfer_id}, request_id)
			return
	else:
		_prepared_transfers[transfer_id] = package.duplicate(true)
		_event("SM0_HANDOFF_PREPARED", {"transfer_id": transfer_id, "package_checksum": String(package.get("checksum", ""))})
	_send_control("PLAYER_HANDOFF_PREPARED", {
		"success": true,
		"error_code": "",
		"transfer_id": transfer_id,
		"package_checksum": String(package.get("checksum", "")),
	}, request_id)


func _handle_handoff_prepared(_request_id: String, payload: Dictionary) -> void:
	if _source_transfer.is_empty() or String(payload.get("transfer_id", "")) != String(_source_transfer.get("transfer_id", "")):
		return
	if not bool(payload.get("success", false)):
		_invariant(String(payload.get("error_code", "SM0_HANDOFF_PREPARE_REJECTED")), {"transfer_id": String(payload.get("transfer_id", ""))})
		return
	if String(payload.get("package_checksum", "")) != String(Dictionary(_source_transfer.get("package", {})).get("checksum", "")):
		_invariant("SM0_HANDOFF_PREPARED_CHECKSUM_MISMATCH", payload)
		return
	_commit_source_transfer()


func _commit_source_transfer() -> void:
	var transfer_id := String(_source_transfer.get("transfer_id", ""))
	var package: Dictionary = Dictionary(_source_transfer.get("package", {}))
	var target_epoch := int(package.get("target_authority_epoch", 0))
	var next_revision := int(_directory.get("revision", 0)) + 1
	_directory = Contracts.create_directory(_peer_authority_id, target_epoch, next_revision)
	var leave := _authority.leave("a", _active_session_id, "operation/sm0/%s/leave/%s" % [_authority_id.get_slice("/", 2), transfer_id.sha256_text().left(12)])
	if not bool(leave.get("success", false)):
		_invariant("SM0_SOURCE_RETIRE_FAILED", {"transfer_id": transfer_id, "cause": leave})
		return
	_event("SM0_DIRECTORY_COMMITTED", {"transfer_id": transfer_id, "directory": _directory})
	_event("SM0_SOURCE_RETIRED", {"transfer_id": transfer_id, "directory": _directory})
	_source_transfer["stage"] = "COMMIT_SENT"
	_source_transfer["last_send_ms"] = 0
	_source_transfer["retries"] = 0
	_send_source_commit()
	_send_client_redirect()


func _handle_handoff_commit(request_id: String, payload: Dictionary) -> void:
	var transfer_id := String(payload.get("transfer_id", ""))
	var directory: Dictionary = Dictionary(payload.get("directory", {}))
	var directory_check := Contracts.validate_directory(directory)
	if not bool(directory_check.get("success", false)):
		_send_control("PLAYER_HANDOFF_COMMITTED", {"success": false, "error_code": String(directory_check.get("error_code", "SM0_DIRECTORY_INVALID")), "transfer_id": transfer_id}, request_id)
		return
	if String(directory.get("owner_authority_id", "")) != _authority_id:
		_send_control("PLAYER_HANDOFF_COMMITTED", {"success": false, "error_code": "SM0_COMMIT_WRONG_TARGET_OWNER", "transfer_id": transfer_id}, request_id)
		return
	if _committed_transfers.has(transfer_id):
		_send_control("PLAYER_HANDOFF_COMMITTED", {"success": true, "error_code": "", "transfer_id": transfer_id, "directory": _directory}, request_id)
		return
	if not _prepared_transfers.has(transfer_id):
		_send_control("PLAYER_HANDOFF_COMMITTED", {"success": false, "error_code": "SM0_COMMIT_WITHOUT_PREPARE", "transfer_id": transfer_id}, request_id)
		return
	var package: Dictionary = Dictionary(_prepared_transfers[transfer_id])
	if int(directory.get("authority_epoch", 0)) != int(package.get("target_authority_epoch", 0)):
		_send_control("PLAYER_HANDOFF_COMMITTED", {"success": false, "error_code": "SM0_COMMIT_EPOCH_MISMATCH", "transfer_id": transfer_id}, request_id)
		return
	_directory = directory.duplicate(true)
	var activated := _activate_imported_player(package)
	if not bool(activated.get("success", false)):
		_send_control("PLAYER_HANDOFF_COMMITTED", {"success": false, "error_code": String(activated.get("error_code", "SM0_TARGET_IMPORT_FAILED")), "transfer_id": transfer_id}, request_id)
		return
	_committed_transfers[transfer_id] = {
		"package": package.duplicate(true),
		"session_id": String(activated.get("details", {}).get("session_id", "")),
		"player": Dictionary(activated.get("details", {}).get("player", {})).duplicate(true),
		"directory": _directory.duplicate(true),
	}
	_event("SM0_TARGET_AUTHORITY_COMMITTED", {"transfer_id": transfer_id, "directory": _directory, "player": activated.get("details", {}).get("player", {})})
	_send_control("PLAYER_HANDOFF_COMMITTED", {"success": true, "error_code": "", "transfer_id": transfer_id, "directory": _directory}, request_id)


func _activate_imported_player(package: Dictionary) -> Dictionary:
	var target_session := "transport-session/sm0/a/%s/epoch/%d" % [_authority_id.get_slice("/", 2), int(package.get("target_authority_epoch", 0))]
	var join := _authority.join("a", target_session, "operation/sm0/%s/import-join/%s" % [_authority_id.get_slice("/", 2), String(package.get("transfer_id", "")).sha256_text().left(12)])
	if not bool(join.get("success", false)):
		return _failure("SM0_TARGET_JOIN_FAILED", {"cause": join})
	var current: Dictionary = Dictionary(join.get("details", {}).get("player", {}))
	var source_position: Dictionary = Dictionary(package.get("position", {}))
	var current_position: Dictionary = Dictionary(current.get("position", {}))
	var delta_x := float(source_position.get("x", 0.0)) - float(current_position.get("x", 0.0))
	var delta_z := float(source_position.get("z", 0.0)) - float(current_position.get("z", 0.0))
	if absf(delta_x) > 10.0 or absf(delta_z) > 10.0:
		return _failure("SM0_TARGET_IMPORT_DELTA_TOO_LARGE", {"delta_x": delta_x, "delta_z": delta_z})
	var imported_sequence := maxi(int(package.get("last_input_sequence", 0)), int(current.get("last_input_sequence", 0)) + 1)
	var moved := _authority.move_player(
		"a", target_session, int(current.get("ownership_epoch", 0)), imported_sequence,
		delta_x, delta_z,
		"operation/sm0/%s/import-move/%s" % [_authority_id.get_slice("/", 2), String(package.get("transfer_id", "")).sha256_text().left(12)]
	)
	if not bool(moved.get("success", false)):
		return _failure("SM0_TARGET_IMPORT_MOVE_FAILED", {"cause": moved})
	var player: Dictionary = Dictionary(moved.get("details", {}).get("player", {}))
	if String(player.get("player_entity_id", "")) != String(package.get("player_entity_id", "")):
		return _failure("SM0_TARGET_IMPORT_PLAYER_ID_CHANGED")
	_active_session_id = target_session
	_active_client_ip = ""
	_active_client_port = 0
	_frozen_transfer_id = ""
	return _success({"session_id": target_session, "player": player})


func _handle_handoff_committed(_request_id: String, payload: Dictionary) -> void:
	if _source_transfer.is_empty() or String(payload.get("transfer_id", "")) != String(_source_transfer.get("transfer_id", "")):
		return
	if not bool(payload.get("success", false)):
		_invariant(String(payload.get("error_code", "SM0_HANDOFF_COMMIT_REJECTED")), payload)
		return
	_adopt_newer_directory(Dictionary(payload.get("directory", {})))
	_source_transfer["stage"] = "AWAIT_CLIENT_REDIRECT_ACK"
	_source_transfer["last_send_ms"] = 0
	_source_transfer["retries"] = 0
	_send_client_redirect()


func _handle_client_activate(request_id: String, payload: Dictionary, remote_ip: String, remote_port: int) -> void:
	var transfer_id := String(payload.get("transfer_id", ""))
	if String(_directory.get("owner_authority_id", "")) != _authority_id or not _committed_transfers.has(transfer_id):
		_send_gameplay(remote_ip, remote_port, "SM0_ERROR", {"error_code": "SM0_TARGET_NOT_COMMITTED", "directory": _directory}, request_id)
		return
	var committed: Dictionary = Dictionary(_committed_transfers[transfer_id])
	var player: Dictionary = Dictionary(committed.get("player", {})).duplicate(true)
	if String(payload.get("logical_player_id", "")) != "a" or String(payload.get("player_entity_id", "")) != String(player.get("player_entity_id", "")):
		_send_gameplay(remote_ip, remote_port, "SM0_ERROR", {"error_code": "SM0_ACTIVATE_PLAYER_IDENTITY_MISMATCH"}, request_id)
		return
	if int(payload.get("authority_epoch", 0)) != int(_directory.get("authority_epoch", 0)):
		_send_gameplay(remote_ip, remote_port, "SM0_ERROR", {"error_code": "SM0_ACTIVATE_STALE_AUTHORITY_EPOCH", "directory": _directory}, request_id)
		return
	_active_client_ip = remote_ip
	_active_client_port = remote_port
	_active_session_id = String(committed.get("session_id", ""))
	player = _authority.get_player("a")
	_event("SM0_TARGET_ACTIVATED", {"transfer_id": transfer_id, "directory": _directory, "player": player})
	_send_gameplay(remote_ip, remote_port, "ACTIVATE_ACK", {
		"authority_id": _authority_id,
		"zone_id": _zone_id,
		"directory": _directory,
		"session_id": _active_session_id,
		"player": player,
		"transfer_id": transfer_id,
	}, request_id)


func _handle_redirect_ack(_request_id: String, payload: Dictionary, _remote_ip: String, _remote_port: int) -> void:
	if _source_transfer.is_empty() or String(payload.get("transfer_id", "")) != String(_source_transfer.get("transfer_id", "")):
		return
	_event("SM0_SOURCE_REDIRECT_ACKNOWLEDGED", {"transfer_id": String(payload.get("transfer_id", "")), "directory": _directory})
	_source_transfer.clear()
	_active_client_ip = ""
	_active_client_port = 0
	_active_session_id = ""


func _retry_source_transfer(now: int) -> void:
	if _source_transfer.is_empty():
		return
	var last_send := int(_source_transfer.get("last_send_ms", 0))
	if last_send > 0 and now - last_send < RETRY_INTERVAL_MS:
		return
	var retries := int(_source_transfer.get("retries", 0)) + 1
	_source_transfer["retries"] = retries
	if retries > MAX_STAGE_RETRIES:
		_invariant("SM0_HANDOFF_STAGE_TIMEOUT", {"transfer_id": String(_source_transfer.get("transfer_id", "")), "stage": String(_source_transfer.get("stage", ""))})
		return
	match String(_source_transfer.get("stage", "")):
		"PREPARE_SENT":
			_send_source_prepare()
		"COMMIT_SENT":
			_send_source_commit()
			_send_client_redirect()
		"AWAIT_CLIENT_REDIRECT_ACK":
			_send_client_redirect()


func _send_source_prepare() -> void:
	if _source_transfer.is_empty():
		return
	_source_transfer["last_send_ms"] = Time.get_ticks_msec()
	_send_control("PLAYER_HANDOFF_PREPARE", {"package": Dictionary(_source_transfer.get("package", {}))}, String(_source_transfer.get("transfer_id", "")))


func _send_source_commit() -> void:
	if _source_transfer.is_empty():
		return
	_source_transfer["last_send_ms"] = Time.get_ticks_msec()
	_send_control("PLAYER_HANDOFF_COMMIT", {
		"transfer_id": String(_source_transfer.get("transfer_id", "")),
		"directory": _directory,
	}, String(_source_transfer.get("transfer_id", "")))


func _send_client_redirect() -> void:
	if _source_transfer.is_empty():
		return
	var client_ip := String(_source_transfer.get("client_ip", ""))
	var client_port := int(_source_transfer.get("client_port", 0))
	if client_ip.is_empty() or client_port < 1:
		return
	var package: Dictionary = Dictionary(_source_transfer.get("package", {}))
	_send_gameplay(client_ip, client_port, "HANDOFF_REDIRECT", {
		"transfer_id": String(_source_transfer.get("transfer_id", "")),
		"target_authority_id": _peer_authority_id,
		"target_zone_id": _peer_zone_id,
		"target_host": _gameplay_host,
		"target_port": 24581 if _peer_authority_id == Contracts.AUTHORITY_B else 24580,
		"authority_epoch": int(package.get("target_authority_epoch", 0)),
		"player_entity_id": String(package.get("player_entity_id", "")),
		"directory": _directory,
	}, String(_source_transfer.get("transfer_id", "")))


func _adopt_newer_directory(candidate: Dictionary) -> void:
	var validation := Contracts.validate_directory(candidate)
	if not bool(validation.get("success", false)):
		return
	if int(candidate.get("revision", 0)) > int(_directory.get("revision", 0)):
		_directory = candidate.duplicate(true)
		_event("SM0_DIRECTORY_CONVERGED", {"directory": _directory})


func _send_control(message_type: String, payload: Dictionary, request_id: String = "") -> void:
	_send_packet(_control_socket, _peer_control_host, _peer_control_port, Contracts.create_message(message_type, payload, request_id))


func _send_gameplay(host: String, port: int, message_type: String, payload: Dictionary, request_id: String = "") -> void:
	_send_packet(_gameplay_socket, host, port, Contracts.create_message(message_type, payload, request_id))


func _send_packet(socket: PacketPeerUDP, host: String, port: int, message: Dictionary) -> void:
	if socket == null or host.is_empty() or port < 1:
		return
	if socket.set_dest_address(host, port) != OK:
		return
	socket.put_packet(Contracts.encode_message(message))


func _status_payload() -> Dictionary:
	return {
		"authority_id": _authority_id,
		"zone_id": _zone_id,
		"peer_synced": _peer_synced,
		"directory": _directory,
		"writer_count": _writer_count(),
		"player": _authority.get_player("a") if _authority != null else {},
		"frozen_transfer_id": _frozen_transfer_id,
	}


func _writer_count() -> int:
	if String(_directory.get("owner_authority_id", "")) != _authority_id or not _frozen_transfer_id.is_empty():
		return 0
	var player: Dictionary = _authority.get_player("a") if _authority != null else {}
	return 1 if not player.is_empty() and bool(player.get("connected", false)) else 0


func _event(event_name: String, details: Dictionary = {}) -> void:
	var event := {
		"schema": "distributed_world_simulator.sm0_event.v1",
		"event": event_name,
		"severity": "INFO",
		"process_role": "server-a" if _authority_id == Contracts.AUTHORITY_A else "server-b",
		"process_id": OS.get_process_id(),
		"time_msec": Time.get_ticks_msec(),
		"authority_id": _authority_id,
		"zone_id": _zone_id,
		"writer_count": _writer_count(),
	}
	for key in details.keys():
		event[key] = details[key]
	print("[SM0_EVENT] %s" % JSON.stringify(event, "", false, true))


func _invariant(error_code: String, details: Dictionary = {}) -> void:
	var payload := details.duplicate(true)
	payload["error_code"] = error_code
	_event("SM0_INVARIANT_VIOLATION", payload)


func _shutdown(exit_code: int, reason: String) -> void:
	_event("SM0_PROCESS_EXIT", {"exit_code": exit_code, "reason": reason})
	if _gameplay_socket != null:
		_gameplay_socket.close()
	if _control_socket != null:
		_control_socket.close()
	set_process(false)
	finished.emit(exit_code)


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
