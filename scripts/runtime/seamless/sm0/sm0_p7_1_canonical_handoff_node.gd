extends Node

signal finished(exit_code: int)

const Topology = preload("res://scripts/runtime/seamless/sm0/sm0_p7_three_authority_topology.gd")
const TransferContract = preload("res://scripts/runtime/seamless/sm0/sm0_p7_1_transfer_contract.gd")
const Authority = preload("res://scripts/runtime/host_client/multiplayer_gameplay_authority.gd")

const STOP_POLL_INTERVAL_MS := 100
const AUTO_RETURN_DELAY_MS := 250

var _authority_id := ""
var _zone_id := ""
var _listen_host := "127.0.0.1"
var _listen_port := 0
var _neighbor_endpoints: Dictionary = {}
var _stop_file := ""
var _start_file := ""
var _auto_start_target := ""
var _auto_return_target := ""
var _auto_start_sent := false
var _auto_return_sent := false
var _auto_return_due_ms := 0
var _last_stop_poll_ms := 0

var _socket: PacketPeerUDP
var _authority: Authority
var _active_session_id := ""
var _owner_authority_id := Topology.AUTHORITY_A
var _authority_epoch := 1
var _directory_revision := 1
var _frozen_transfer_id := ""
var _source_transfer: Dictionary = {}
var _prepared_transfers: Dictionary = {}
var _completed_transfers: Dictionary = {}
var _route_ledger: Dictionary = {}
var _forwarded_count := 0
var _delivered_count := 0
var _replay_count := 0
var _rejected_count := 0
var _transfer_counter := 0


func setup(config: Dictionary) -> Dictionary:
	_authority_id = String(config.get("authority_id", "")).strip_edges()
	_zone_id = String(config.get("zone_id", Topology.zone_for_authority(_authority_id))).strip_edges()
	_listen_host = String(config.get("listen_host", "127.0.0.1")).strip_edges()
	_listen_port = int(config.get("listen_port", 0))
	_neighbor_endpoints = Dictionary(config.get("neighbor_endpoints", {})).duplicate(true)
	_stop_file = String(config.get("stop_file", "")).strip_edges()
	_start_file = String(config.get("start_file", "")).strip_edges()
	_auto_start_target = String(config.get("auto_start_target", "")).strip_edges()
	_auto_return_target = String(config.get("auto_return_target", "")).strip_edges()
	_owner_authority_id = String(config.get("initial_owner_authority_id", Topology.AUTHORITY_A)).strip_edges()
	_authority_epoch = int(config.get("initial_authority_epoch", 1))
	_directory_revision = int(config.get("initial_directory_revision", 1))
	if (
		_authority_id not in Topology.AUTHORITIES
		or _zone_id != Topology.zone_for_authority(_authority_id)
		or _listen_host.is_empty()
		or _listen_port < 1
		or _owner_authority_id not in [Topology.AUTHORITY_A, Topology.AUTHORITY_C]
		or _authority_epoch < 1
		or _directory_revision < 1
	):
		return _failure("SM0_P7_1_CONFIGURATION_INVALID")
	for neighbor in Topology.neighbors(_authority_id):
		if not _neighbor_endpoints.has(neighbor):
			return _failure("SM0_P7_1_NEIGHBOR_ENDPOINT_REQUIRED", {"neighbor_authority_id": neighbor})
		var endpoint: Dictionary = Dictionary(_neighbor_endpoints[neighbor])
		if String(endpoint.get("host", "")).strip_edges().is_empty() or int(endpoint.get("port", 0)) < 1:
			return _failure("SM0_P7_1_NEIGHBOR_ENDPOINT_INVALID", {"neighbor_authority_id": neighbor})
	for configured in _neighbor_endpoints.keys():
		if String(configured) not in Topology.neighbors(_authority_id):
			return _failure("SM0_P7_1_NON_NEIGHBOR_ENDPOINT_FORBIDDEN", {"neighbor_authority_id": String(configured)})
	if not _auto_start_target.is_empty() and _auto_start_target not in [Topology.AUTHORITY_A, Topology.AUTHORITY_C]:
		return _failure("SM0_P7_1_AUTO_START_TARGET_INVALID")
	if not _auto_return_target.is_empty() and _auto_return_target not in [Topology.AUTHORITY_A, Topology.AUTHORITY_C]:
		return _failure("SM0_P7_1_AUTO_RETURN_TARGET_INVALID")

	if _authority_id != Topology.AUTHORITY_B:
		_authority = Authority.new()
		var authority_setup: Dictionary = _authority.setup(_authority_id, 1, 0)
		if not bool(authority_setup.get("success", false)):
			return _failure("SM0_P7_1_AUTHORITY_SETUP_FAILED", {"cause": authority_setup})
		if _owner_authority_id == _authority_id:
			var joined := _join_local_owner(_authority_epoch, "bootstrap")
			if not bool(joined.get("success", false)):
				return joined

	_socket = PacketPeerUDP.new()
	var bind_result := _socket.bind(_listen_port, _listen_host)
	if bind_result != OK:
		return _failure("SM0_P7_1_BIND_FAILED", {"error": bind_result, "port": _listen_port})
	set_process(true)
	_event("SM0_P7_1_READY", {
		"listen_port": _listen_port,
		"neighbors": Topology.neighbors(_authority_id),
		"owner_authority_id": _owner_authority_id,
		"authority_epoch": _authority_epoch,
		"authority_present": _authority != null,
		"transit_only": _authority_id == Topology.AUTHORITY_B,
	})
	return _success()


func _process(_delta: float) -> void:
	_poll_socket()
	var now := Time.get_ticks_msec()
	if (
		not _auto_start_sent
		and not _auto_start_target.is_empty()
		and not _start_file.is_empty()
		and FileAccess.file_exists(_start_file)
	):
		_auto_start_sent = true
		var started := begin_transfer_for_tests(_auto_start_target)
		if not bool(started.get("success", false)):
			_event("SM0_P7_1_AUTO_START_FAILED", {"error_code": String(started.get("error_code", "SM0_P7_1_AUTO_START_FAILED"))})
	if (
		not _auto_return_sent
		and not _auto_return_target.is_empty()
		and _owner_authority_id == _authority_id
		and _auto_return_due_ms > 0
		and now >= _auto_return_due_ms
	):
		_auto_return_sent = true
		var returned := begin_transfer_for_tests(_auto_return_target)
		if not bool(returned.get("success", false)):
			_event("SM0_P7_1_AUTO_RETURN_FAILED", {"error_code": String(returned.get("error_code", "SM0_P7_1_AUTO_RETURN_FAILED"))})
	if not _stop_file.is_empty() and now - _last_stop_poll_ms >= STOP_POLL_INTERVAL_MS:
		_last_stop_poll_ms = now
		if FileAccess.file_exists(_stop_file):
			shutdown(0, "stop-file")


func begin_transfer_for_tests(target_authority_id: String) -> Dictionary:
	if _authority_id == Topology.AUTHORITY_B or _authority == null:
		return _failure("SM0_P7_1_TRANSIT_CANNOT_OWN")
	if target_authority_id not in [Topology.AUTHORITY_A, Topology.AUTHORITY_C] or target_authority_id == _authority_id:
		return _failure("SM0_P7_1_TRANSFER_TARGET_INVALID")
	if _owner_authority_id != _authority_id:
		return _failure("SM0_P7_1_NOT_OWNER")
	if not _frozen_transfer_id.is_empty() or not _source_transfer.is_empty():
		return _failure("SM0_P7_1_TRANSFER_ALREADY_ACTIVE")
	var player: Dictionary = _authority.get_player("a")
	if player.is_empty() or not bool(player.get("connected", false)):
		return _failure("SM0_P7_1_CANONICAL_PLAYER_REQUIRED")
	_transfer_counter += 1
	var transfer_id := "handoff/sm0/p7-1/%s-to-%s/%d/%d" % [
		_authority_id.get_slice("/", 2),
		target_authority_id.get_slice("/", 2),
		_authority_epoch + 1,
		_transfer_counter,
	]
	var package := _package_from_player(player)
	var package_check := TransferContract.validate_player_package(package)
	if not bool(package_check.get("success", false)):
		return package_check
	_source_transfer = {
		"transfer_id": transfer_id,
		"source_authority_id": _authority_id,
		"target_authority_id": target_authority_id,
		"source_epoch": _authority_epoch,
		"target_epoch": _authority_epoch + 1,
		"package": package.duplicate(true),
		"package_hash": "",
		"stage": TransferContract.PHASE_PREPARE,
	}
	# Recompute with the exact contract canonicalization/fingerprint surface.
	var prepare := TransferContract.create(
		"%s/prepare" % transfer_id, transfer_id, TransferContract.PHASE_PREPARE,
		_authority_id, target_authority_id, _authority_epoch, _authority_epoch + 1, package
	)
	_source_transfer["package_hash"] = String(prepare.get("package_hash", ""))
	_frozen_transfer_id = transfer_id
	_event("SM0_P7_1_SOURCE_FROZEN", {
		"transfer_id": transfer_id,
		"target_authority_id": target_authority_id,
		"player_entity_id": String(package.get("player_entity_id", "")),
		"source_epoch": _authority_epoch,
		"target_epoch": _authority_epoch + 1,
	})
	return _originate(prepare)


func move_owner_for_tests(delta_x: float, delta_z: float) -> Dictionary:
	if _authority_id == Topology.AUTHORITY_B or _authority == null:
		return _failure("SM0_P7_1_TRANSIT_CANNOT_OWN")
	if _owner_authority_id != _authority_id or not _frozen_transfer_id.is_empty():
		return _failure("SM0_P7_1_NOT_MUTABLE_OWNER")
	var player: Dictionary = _authority.get_player("a")
	if player.is_empty() or not bool(player.get("connected", false)):
		return _failure("SM0_P7_1_CANONICAL_PLAYER_REQUIRED")
	return _authority.move_player(
		"a", _active_session_id, int(player.get("ownership_epoch", 0)),
		int(player.get("last_input_sequence", 0)) + 1,
		delta_x, delta_z,
		"operation/sm0/p7-1/%s/move/%d" % [_authority_id.get_slice("/", 2), int(player.get("last_input_sequence", 0)) + 1]
	)


func accept_envelope_for_tests(envelope: Dictionary, previous_authority_id: String) -> Dictionary:
	return _accept_envelope(envelope, previous_authority_id, "127.0.0.1", 0, false)


func _poll_socket() -> void:
	if _socket == null:
		return
	while _socket.get_available_packet_count() > 0:
		var bytes := _socket.get_packet()
		var remote_ip := _socket.get_packet_ip()
		var remote_port := _socket.get_packet_port()
		var decoded = JSON.parse_string(bytes.get_string_from_utf8())
		if not decoded is Dictionary:
			_reject("SM0_P7_1_JSON_INVALID", {}, remote_ip, remote_port)
			continue
		var envelope: Dictionary = Dictionary(decoded)
		_accept_envelope(envelope, TransferContract.previous_authority(envelope), remote_ip, remote_port, true)


func _accept_envelope(envelope: Dictionary, previous_authority_id: String, remote_ip: String, remote_port: int, verify_network_sender: bool) -> Dictionary:
	var validation := TransferContract.validate(envelope)
	if not bool(validation.get("success", false)):
		return _reject(String(validation.get("error_code", "SM0_P7_1_TRANSFER_INVALID")), envelope, remote_ip, remote_port)
	if TransferContract.current_authority(envelope) != _authority_id:
		return _reject("SM0_P7_1_CURRENT_HOP_MISMATCH", envelope, remote_ip, remote_port)
	var expected_previous := TransferContract.previous_authority(envelope)
	if expected_previous.is_empty() or previous_authority_id != expected_previous:
		return _reject("SM0_P7_1_PREVIOUS_HOP_MISMATCH", envelope, remote_ip, remote_port)
	if not Topology.are_adjacent(expected_previous, _authority_id):
		return _reject("SM0_P7_1_PREVIOUS_HOP_NOT_ADJACENT", envelope, remote_ip, remote_port)
	if verify_network_sender:
		if not _neighbor_endpoints.has(expected_previous):
			return _reject("SM0_P7_1_SENDER_NOT_NEIGHBOR", envelope, remote_ip, remote_port)
		var endpoint: Dictionary = Dictionary(_neighbor_endpoints[expected_previous])
		if remote_port != int(endpoint.get("port", 0)):
			return _reject("SM0_P7_1_SENDER_PORT_MISMATCH", envelope, remote_ip, remote_port)
	var replay := _record_route(envelope)
	if not bool(replay.get("success", false)):
		return replay
	if bool(replay.get("details", {}).get("replay", false)):
		_replay_count += 1
		_event("SM0_P7_1_ROUTE_REPLAY", {"route_id": String(envelope.get("route_id", ""))})
	if String(envelope.get("route_destination_authority_id", "")) == _authority_id:
		_delivered_count += 1
		return _handle_delivered_phase(envelope)
	return _forward(envelope)


func _originate(envelope: Dictionary) -> Dictionary:
	var validation := TransferContract.validate(envelope)
	if not bool(validation.get("success", false)):
		return validation
	if TransferContract.current_authority(envelope) != _authority_id:
		return _failure("SM0_P7_1_ORIGIN_HOP_INVALID")
	var replay := _record_route(envelope)
	if not bool(replay.get("success", false)):
		return replay
	_event("SM0_P7_1_ROUTE_ORIGINATED", {
		"route_id": String(envelope.get("route_id", "")),
		"transfer_id": String(envelope.get("transfer_id", "")),
		"phase": String(envelope.get("phase", "")),
		"route_path": envelope.get("route_path", []),
	})
	return _forward(envelope)


func _record_route(envelope: Dictionary) -> Dictionary:
	var route_id := String(envelope.get("route_id", ""))
	var fingerprint := TransferContract.immutable_fingerprint(envelope)
	if _route_ledger.has(route_id):
		if String(_route_ledger[route_id]) != fingerprint:
			return _reject("SM0_P7_1_ROUTE_REPLAY_CONFLICT", envelope, "", 0)
		return _success({"replay": true})
	_route_ledger[route_id] = fingerprint
	return _success({"replay": false})


func _forward(envelope: Dictionary) -> Dictionary:
	var next_authority := TransferContract.next_authority(envelope)
	if next_authority.is_empty() or not Topology.are_adjacent(_authority_id, next_authority):
		return _reject("SM0_P7_1_NEXT_HOP_INVALID", envelope, "", 0)
	if not _neighbor_endpoints.has(next_authority):
		return _reject("SM0_P7_1_NEXT_HOP_ENDPOINT_MISSING", envelope, "", 0)
	var advanced := TransferContract.advance(envelope)
	var validation := TransferContract.validate(advanced)
	if not bool(validation.get("success", false)):
		return _reject(String(validation.get("error_code", "SM0_P7_1_ADVANCE_INVALID")), advanced, "", 0)
	var endpoint: Dictionary = Dictionary(_neighbor_endpoints[next_authority])
	if _socket.set_dest_address(String(endpoint.get("host", "")), int(endpoint.get("port", 0))) != OK:
		return _failure("SM0_P7_1_DESTINATION_SET_FAILED")
	var put_error := _socket.put_packet(JSON.stringify(advanced, "", false, true).to_utf8_buffer())
	if put_error != OK:
		return _failure("SM0_P7_1_SEND_FAILED", {"error": put_error})
	_forwarded_count += 1
	_event("SM0_P7_1_ROUTE_FORWARDED", {
		"route_id": String(envelope.get("route_id", "")),
		"transfer_id": String(envelope.get("transfer_id", "")),
		"phase": String(envelope.get("phase", "")),
		"current_authority_id": _authority_id,
		"next_authority_id": next_authority,
		"hop_index": int(envelope.get("hop_index", 0)),
		"route_path": envelope.get("route_path", []),
	})
	return _success({"forwarded": true})


func _handle_delivered_phase(envelope: Dictionary) -> Dictionary:
	var phase := String(envelope.get("phase", ""))
	match phase:
		TransferContract.PHASE_PREPARE:
			return _handle_prepare(envelope)
		TransferContract.PHASE_PREPARED:
			return _handle_prepared(envelope)
		TransferContract.PHASE_COMMIT:
			return _handle_commit(envelope)
		TransferContract.PHASE_COMMITTED:
			return _handle_committed(envelope)
		_:
			return _reject("SM0_P7_1_PHASE_UNSUPPORTED", envelope, "", 0)


func _handle_prepare(envelope: Dictionary) -> Dictionary:
	if _authority_id == Topology.AUTHORITY_B or _authority == null:
		return _reject("SM0_P7_1_TRANSIT_DELIVERY_FORBIDDEN", envelope, "", 0)
	var transfer_id := String(envelope.get("transfer_id", ""))
	var source := String(envelope.get("transfer_source_authority_id", ""))
	var target := String(envelope.get("transfer_target_authority_id", ""))
	if target != _authority_id or source != _owner_authority_id or int(envelope.get("source_epoch", 0)) != _authority_epoch:
		return _reject("SM0_P7_1_PREPARE_STALE_OWNER", envelope, "", 0)
	if _prepared_transfers.has(transfer_id):
		var existing: Dictionary = Dictionary(_prepared_transfers[transfer_id])
		if String(existing.get("package_hash", "")) != String(envelope.get("package_hash", "")):
			return _reject("SM0_P7_1_PREPARE_CONFLICT", envelope, "", 0)
	else:
		_prepared_transfers[transfer_id] = {
			"package": Dictionary(envelope.get("player_package", {})).duplicate(true),
			"package_hash": String(envelope.get("package_hash", "")),
			"source_authority_id": source,
			"target_authority_id": target,
			"source_epoch": int(envelope.get("source_epoch", 0)),
			"target_epoch": int(envelope.get("target_epoch", 0)),
		}
		_event("SM0_P7_1_TARGET_PREPARED", {
			"transfer_id": transfer_id,
			"source_authority_id": source,
			"target_authority_id": target,
			"player_entity_id": String(Dictionary(envelope.get("player_package", {})).get("player_entity_id", "")),
			"shadow_only": true,
		})
	var ack := TransferContract.create(
		"%s/prepared" % transfer_id, transfer_id, TransferContract.PHASE_PREPARED,
		source, target, int(envelope.get("source_epoch", 0)), int(envelope.get("target_epoch", 0)),
		Dictionary(envelope.get("player_package", {}))
	)
	return _originate(ack)


func _handle_prepared(envelope: Dictionary) -> Dictionary:
	var transfer_id := String(envelope.get("transfer_id", ""))
	if _source_transfer.is_empty() or transfer_id != String(_source_transfer.get("transfer_id", "")):
		return _reject("SM0_P7_1_PREPARED_WITHOUT_SOURCE", envelope, "", 0)
	if String(envelope.get("package_hash", "")) != String(_source_transfer.get("package_hash", "")):
		return _reject("SM0_P7_1_PREPARED_PACKAGE_MISMATCH", envelope, "", 0)
	var leave: Dictionary = _authority.leave(
		"a", _active_session_id,
		"operation/sm0/p7-1/%s/leave/%s" % [_authority_id.get_slice("/", 2), transfer_id.sha256_text().left(12)]
	)
	if not bool(leave.get("success", false)):
		return _reject("SM0_P7_1_SOURCE_RETIRE_FAILED", envelope, "", 0)
	_owner_authority_id = String(_source_transfer.get("target_authority_id", ""))
	_authority_epoch = int(_source_transfer.get("target_epoch", 0))
	_directory_revision += 1
	_active_session_id = ""
	_source_transfer["stage"] = TransferContract.PHASE_COMMIT
	var retire_proof := TransferContract.create_retire_proof(
		transfer_id, String(_source_transfer.get("package_hash", "")),
		int(_source_transfer.get("source_epoch", 0)), int(_source_transfer.get("target_epoch", 0))
	)
	_source_transfer["retire_proof"] = retire_proof
	_event("SM0_P7_1_SOURCE_RETIRED", {
		"transfer_id": transfer_id,
		"owner_authority_id": _owner_authority_id,
		"authority_epoch": _authority_epoch,
		"directory_revision": _directory_revision,
		"retire_proof": retire_proof,
	})
	var commit := TransferContract.create(
		"%s/commit" % transfer_id, transfer_id, TransferContract.PHASE_COMMIT,
		String(_source_transfer.get("source_authority_id", "")), String(_source_transfer.get("target_authority_id", "")),
		int(_source_transfer.get("source_epoch", 0)), int(_source_transfer.get("target_epoch", 0)),
		Dictionary(_source_transfer.get("package", {})), retire_proof
	)
	return _originate(commit)


func _handle_commit(envelope: Dictionary) -> Dictionary:
	if _authority_id == Topology.AUTHORITY_B or _authority == null:
		return _reject("SM0_P7_1_TRANSIT_COMMIT_FORBIDDEN", envelope, "", 0)
	var transfer_id := String(envelope.get("transfer_id", ""))
	if _completed_transfers.has(transfer_id):
		var completed: Dictionary = Dictionary(_completed_transfers[transfer_id])
		var replay_ack := TransferContract.create(
			"%s/committed" % transfer_id, transfer_id, TransferContract.PHASE_COMMITTED,
			String(envelope.get("transfer_source_authority_id", "")), String(envelope.get("transfer_target_authority_id", "")),
			int(envelope.get("source_epoch", 0)), int(envelope.get("target_epoch", 0)),
			Dictionary(completed.get("package", {})), String(envelope.get("retire_proof", ""))
		)
		return _originate(replay_ack)
	if not _prepared_transfers.has(transfer_id):
		return _reject("SM0_P7_1_COMMIT_WITHOUT_PREPARE", envelope, "", 0)
	var prepared: Dictionary = Dictionary(_prepared_transfers[transfer_id])
	if String(prepared.get("package_hash", "")) != String(envelope.get("package_hash", "")):
		return _reject("SM0_P7_1_COMMIT_PACKAGE_MISMATCH", envelope, "", 0)
	if _owner_authority_id != String(envelope.get("transfer_source_authority_id", "")) or _authority_epoch != int(envelope.get("source_epoch", 0)):
		return _reject("SM0_P7_1_COMMIT_STALE_TARGET_DIRECTORY", envelope, "", 0)
	var target_epoch := int(envelope.get("target_epoch", 0))
	var joined := _join_local_owner(target_epoch, transfer_id)
	if not bool(joined.get("success", false)):
		return _reject(String(joined.get("error_code", "SM0_P7_1_TARGET_JOIN_FAILED")), envelope, "", 0)
	var current: Dictionary = _authority.get_player("a")
	var package: Dictionary = Dictionary(envelope.get("player_package", {}))
	var imported := _authority.import_handoff_player_state(
		"a", _active_session_id, int(current.get("ownership_epoch", 0)),
		{
			"player_entity_id": String(package.get("player_entity_id", "")),
			"position": Dictionary(package.get("position", {})).duplicate(true),
			"velocity": Dictionary(package.get("velocity", {})).duplicate(true),
			"orientation_yaw": float(package.get("orientation_yaw", 0.0)),
			"last_input_sequence": int(package.get("last_input_sequence", 0)),
			"source_state_revision": int(package.get("state_revision", 0)),
		},
		"operation/sm0/p7-1/%s/import/%s" % [_authority_id.get_slice("/", 2), transfer_id.sha256_text().left(12)]
	)
	if not bool(imported.get("success", false)):
		return _reject("SM0_P7_1_TARGET_IMPORT_FAILED", envelope, "", 0)
	var player: Dictionary = Dictionary(imported.get("details", {}).get("player", {}))
	if String(player.get("player_entity_id", "")) != String(package.get("player_entity_id", "")):
		return _reject("SM0_P7_1_TARGET_PLAYER_ID_CHANGED", envelope, "", 0)
	_owner_authority_id = _authority_id
	_authority_epoch = target_epoch
	_directory_revision += 1
	_prepared_transfers.erase(transfer_id)
	_completed_transfers[transfer_id] = {"package": package.duplicate(true), "player": player.duplicate(true)}
	_event("SM0_P7_1_TARGET_COMMITTED", {
		"transfer_id": transfer_id,
		"owner_authority_id": _owner_authority_id,
		"authority_epoch": _authority_epoch,
		"directory_revision": _directory_revision,
		"player": player,
		"retire_proof": String(envelope.get("retire_proof", "")),
	})
	if not _auto_return_target.is_empty() and not _auto_return_sent:
		_auto_return_due_ms = Time.get_ticks_msec() + AUTO_RETURN_DELAY_MS
	var ack := TransferContract.create(
		"%s/committed" % transfer_id, transfer_id, TransferContract.PHASE_COMMITTED,
		String(envelope.get("transfer_source_authority_id", "")), String(envelope.get("transfer_target_authority_id", "")),
		int(envelope.get("source_epoch", 0)), int(envelope.get("target_epoch", 0)), package,
		String(envelope.get("retire_proof", ""))
	)
	return _originate(ack)


func _handle_committed(envelope: Dictionary) -> Dictionary:
	var transfer_id := String(envelope.get("transfer_id", ""))
	if _source_transfer.is_empty() or transfer_id != String(_source_transfer.get("transfer_id", "")):
		return _success({"replay": true})
	if String(envelope.get("retire_proof", "")) != String(_source_transfer.get("retire_proof", "")):
		return _reject("SM0_P7_1_COMMITTED_RETIRE_PROOF_MISMATCH", envelope, "", 0)
	_event("SM0_P7_1_TRANSFER_COMPLETED", {
		"transfer_id": transfer_id,
		"owner_authority_id": _owner_authority_id,
		"authority_epoch": _authority_epoch,
		"directory_revision": _directory_revision,
		"player_entity_id": String(Dictionary(_source_transfer.get("package", {})).get("player_entity_id", "")),
	})
	_source_transfer.clear()
	_frozen_transfer_id = ""
	return _success({"completed": true})


func _join_local_owner(target_epoch: int, reason: String) -> Dictionary:
	var session_id := "transport-session/sm0/p7-1/a/%s/epoch/%d" % [_authority_id.get_slice("/", 2), target_epoch]
	var joined: Dictionary = _authority.join(
		"a", session_id,
		"operation/sm0/p7-1/%s/join/%s" % [_authority_id.get_slice("/", 2), reason.sha256_text().left(12)]
	)
	if not bool(joined.get("success", false)):
		return _failure("SM0_P7_1_TARGET_JOIN_FAILED", {"cause": joined})
	_active_session_id = session_id
	return _success({"player": Dictionary(joined.get("details", {}).get("player", {})).duplicate(true)})


func _package_from_player(player: Dictionary) -> Dictionary:
	return {
		"logical_player_id": String(player.get("logical_player_id", "")),
		"player_entity_id": String(player.get("player_entity_id", "")),
		"state_revision": int(player.get("state_revision", 0)),
		"last_input_sequence": int(player.get("last_input_sequence", 0)),
		"position": Dictionary(player.get("position", {})).duplicate(true),
		"velocity": Dictionary(player.get("velocity", {})).duplicate(true),
		"orientation_yaw": float(player.get("orientation_yaw", 0.0)),
	}


func _reject(error_code: String, envelope: Dictionary, remote_ip: String, remote_port: int) -> Dictionary:
	_rejected_count += 1
	_event("SM0_P7_1_REJECTED", {
		"error_code": error_code,
		"route_id": String(envelope.get("route_id", "")),
		"transfer_id": String(envelope.get("transfer_id", "")),
		"phase": String(envelope.get("phase", "")),
		"remote_ip": remote_ip,
		"remote_port": remote_port,
	})
	return _failure(error_code)


func status_for_tests() -> Dictionary:
	return {
		"authority_id": _authority_id,
		"zone_id": _zone_id,
		"owner_authority_id": _owner_authority_id,
		"authority_epoch": _authority_epoch,
		"directory_revision": _directory_revision,
		"writer_count": _writer_count(),
		"authority_present": _authority != null,
		"transit_only": _authority_id == Topology.AUTHORITY_B,
		"player": _authority.get_player("a") if _authority != null else {},
		"frozen_transfer_id": _frozen_transfer_id,
		"source_transfer": _source_transfer.duplicate(true),
		"prepared_transfer_count": _prepared_transfers.size(),
		"completed_transfer_count": _completed_transfers.size(),
		"forwarded_count": _forwarded_count,
		"delivered_count": _delivered_count,
		"replay_count": _replay_count,
		"rejected_count": _rejected_count,
	}


func _writer_count() -> int:
	if _authority_id == Topology.AUTHORITY_B or _authority == null or _owner_authority_id != _authority_id or not _frozen_transfer_id.is_empty():
		return 0
	var player: Dictionary = _authority.get_player("a")
	return 1 if not player.is_empty() and bool(player.get("connected", false)) else 0


func shutdown(exit_code: int, reason: String) -> void:
	_event("SM0_P7_1_EXIT", {"exit_code": exit_code, "reason": reason})
	if _socket != null:
		_socket.close()
	set_process(false)
	finished.emit(exit_code)


func _event(event_name: String, details: Dictionary = {}) -> void:
	var event := {
		"schema": "distributed_world_simulator.sm0_event.v1",
		"event": event_name,
		"severity": "INFO",
		"process_role": "p7-1-%s" % _authority_id.get_slice("/", 2),
		"process_id": OS.get_process_id(),
		"time_msec": Time.get_ticks_msec(),
		"authority_id": _authority_id,
		"zone_id": _zone_id,
		"owner_authority_id": _owner_authority_id,
		"authority_epoch": _authority_epoch,
		"writer_count": _writer_count(),
	}
	for key in details.keys():
		event[key] = details[key]
	print("[SM0_EVENT] %s" % JSON.stringify(event, "", false, true))


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}