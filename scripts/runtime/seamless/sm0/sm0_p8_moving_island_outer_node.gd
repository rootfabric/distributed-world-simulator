extends Node

signal finished(exit_code: int)

const Topology = preload("res://scripts/runtime/seamless/sm0/sm0_p7_three_authority_topology.gd")
const Contract = preload("res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_contract.gd")

const STOP_POLL_INTERVAL_MS := 100
const ANCHOR_PUBLISH_INTERVAL_MS := 40
const AUTO_RETURN_TICKS := 5
const DEFAULT_STEP_SECONDS := 1.0 / 60.0

var _authority_id := ""
var _zone_id := ""
var _listen_host := "127.0.0.1"
var _listen_port := 0
var _neighbor_endpoints: Dictionary = {}
var _anchor_host := "127.0.0.1"
var _anchor_port := 0
var _start_file := ""
var _stop_file := ""
var _auto_start_target := ""
var _auto_return_target := ""
var _auto_started := false
var _return_after_tick := -1
var _last_stop_poll_ms := 0
var _last_anchor_publish_ms := 0
var _socket: PacketPeerUDP
var _anchor_socket: PacketPeerUDP
var _writer := false
var _ship_anchor: Dictionary = {}
var _transfer: Dictionary = {}
var _reservations: Dictionary = {}
var _route_ledger: Dictionary = {}
var _transfer_counter := 0
var _forwarded_count := 0
var _rejected_count := 0
var _prepared_count := 0
var _committed_count := 0

func setup(config: Dictionary) -> Dictionary:
	_authority_id = String(config.get("authority_id", "")).strip_edges()
	_zone_id = Topology.zone_for_authority(_authority_id)
	_listen_host = String(config.get("listen_host", "127.0.0.1")).strip_edges()
	_listen_port = int(config.get("listen_port", 0))
	_neighbor_endpoints = Dictionary(config.get("neighbor_endpoints", {})).duplicate(true)
	_anchor_host = String(config.get("anchor_host", "127.0.0.1")).strip_edges()
	_anchor_port = int(config.get("anchor_port", 0))
	_start_file = String(config.get("start_file", "")).strip_edges()
	_stop_file = String(config.get("stop_file", "")).strip_edges()
	_auto_start_target = String(config.get("auto_start_target", "")).strip_edges()
	_auto_return_target = String(config.get("auto_return_target", "")).strip_edges()
	if _authority_id not in Topology.AUTHORITIES or _listen_host.is_empty() or _listen_port < 1:
		return _failure("SM0_P8_OUTER_CONFIGURATION_INVALID")
	for neighbor in Topology.neighbors(_authority_id):
		if not _neighbor_endpoints.has(neighbor): return _failure("SM0_P8_NEIGHBOR_ENDPOINT_REQUIRED", {"neighbor_authority_id": neighbor})
		var endpoint := Dictionary(_neighbor_endpoints[neighbor])
		if String(endpoint.get("host", "")).strip_edges().is_empty() or int(endpoint.get("port", 0)) < 1:
			return _failure("SM0_P8_NEIGHBOR_ENDPOINT_INVALID", {"neighbor_authority_id": neighbor})
	for configured in _neighbor_endpoints.keys():
		if String(configured) not in Topology.neighbors(_authority_id): return _failure("SM0_P8_NON_NEIGHBOR_ENDPOINT_FORBIDDEN")
	if _authority_id in [Topology.AUTHORITY_A, Topology.AUTHORITY_C] and _anchor_port < 1:
		return _failure("SM0_P8_ANCHOR_ENDPOINT_REQUIRED")
	if not _auto_start_target.is_empty() and _auto_start_target not in [Topology.AUTHORITY_A, Topology.AUTHORITY_C]: return _failure("SM0_P8_AUTO_TARGET_INVALID")
	if not _auto_return_target.is_empty() and _auto_return_target not in [Topology.AUTHORITY_A, Topology.AUTHORITY_C]: return _failure("SM0_P8_AUTO_TARGET_INVALID")
	_socket = PacketPeerUDP.new()
	var bind_result := _socket.bind(_listen_port, _listen_host)
	if bind_result != OK: return _failure("SM0_P8_OUTER_BIND_FAILED", {"error": bind_result})
	if _authority_id in [Topology.AUTHORITY_A, Topology.AUTHORITY_C]: _anchor_socket = PacketPeerUDP.new()
	if bool(config.get("initial_writer", _authority_id == Topology.AUTHORITY_A)):
		_writer = true
		var initial_position := Dictionary(config.get("initial_world_position", {"x": -1.0, "y": 0.0, "z": 0.0}))
		var initial_velocity := Dictionary(config.get("linear_velocity", {"x": 0.8, "y": 0.0, "z": 0.0}))
		_ship_anchor = Contract.create_anchor(
			_authority_id, int(config.get("initial_outer_epoch", 1)), int(config.get("initial_simulation_tick", 0)),
			initial_position, float(config.get("world_yaw", 0.0)), initial_velocity, float(config.get("angular_velocity_yaw", 0.2))
		)
		var check := Contract.validate_anchor(_ship_anchor)
		if not bool(check.get("success", false)): return check
	set_process(true)
	_event("SM0_P8_OUTER_READY", {
		"listen_port": _listen_port, "outer_writer": _writer, "authority_scope": "outer/island/ship/01",
		"island_id": Contract.ISLAND_ID, "island_entity_id": Contract.ISLAND_ENTITY_ID,
		"inner_authority_id": Contract.ISLAND_AUTHORITY_ID,
		"outer_authority_epoch": int(_ship_anchor.get("outer_authority_epoch", 0)) if _writer else 0,
	})
	if _writer: _publish_anchor(true)
	return _success()

func _process(delta: float) -> void:
	_poll_socket()
	if _writer:
		_integrate(maxf(delta, 0.000001))
		var now := Time.get_ticks_msec()
		if now - _last_anchor_publish_ms >= ANCHOR_PUBLISH_INTERVAL_MS: _publish_anchor(false)
		if not _auto_started and not _auto_start_target.is_empty() and ( _start_file.is_empty() or FileAccess.file_exists(_start_file)):
			_auto_started = true
			var begun := begin_transfer(_auto_start_target)
			if not bool(begun.get("success", false)): _reject(String(begun.get("error_code", "SM0_P8_AUTO_START_FAILED")), {})
		if _return_after_tick >= 0 and int(_ship_anchor.get("simulation_tick", 0)) >= _return_after_tick and not _auto_return_target.is_empty() and _transfer.is_empty():
			_return_after_tick = -1
			var returned := begin_transfer(_auto_return_target)
			if not bool(returned.get("success", false)): _reject(String(returned.get("error_code", "SM0_P8_AUTO_RETURN_FAILED")), {})
	var now2 := Time.get_ticks_msec()
	if not _stop_file.is_empty() and now2 - _last_stop_poll_ms >= STOP_POLL_INTERVAL_MS:
		_last_stop_poll_ms = now2
		if FileAccess.file_exists(_stop_file): shutdown(0, "stop-file")

func advance_for_tests(seconds: float = DEFAULT_STEP_SECONDS) -> Dictionary:
	if not _writer: return _failure("SM0_P8_NOT_OUTER_WRITER")
	_integrate(seconds); _publish_anchor(false); return _success({"anchor": _ship_anchor.duplicate(true)})

func begin_transfer(target_authority_id: String) -> Dictionary:
	if not _writer: return _failure("SM0_P8_SOURCE_NOT_WRITER")
	if not _transfer.is_empty(): return _failure("SM0_P8_TRANSFER_ALREADY_ACTIVE")
	if target_authority_id not in [Topology.AUTHORITY_A, Topology.AUTHORITY_C] or target_authority_id == _authority_id: return _failure("SM0_P8_TARGET_INVALID")
	_transfer_counter += 1
	var source_epoch := int(_ship_anchor.get("outer_authority_epoch", 0))
	var target_epoch := source_epoch + 1
	var transfer_id := "handoff/sm0/p8/%s-to-%s/%d/%d" % [_authority_id.get_slice("/",2), target_authority_id.get_slice("/",2), target_epoch, _transfer_counter]
	var reservation_tick := int(_ship_anchor.get("simulation_tick", 0))
	_transfer = {"transfer_id": transfer_id, "target": target_authority_id, "source_epoch": source_epoch, "target_epoch": target_epoch, "reservation_tick": reservation_tick, "stage": "PREPARE_SENT"}
	_event("SM0_P8_TRANSFER_BEGIN", {"transfer_id": transfer_id, "handoff_target_authority_id": target_authority_id, "reservation_tick": reservation_tick, "source_outer_epoch": source_epoch, "target_outer_epoch": target_epoch})
	var message := Contract.create_transfer(transfer_id, Contract.PHASE_PREPARE, _authority_id, target_authority_id, _authority_id, target_authority_id, source_epoch, target_epoch, reservation_tick)
	return _forward_or_deliver(message, false)

func accept_transfer_for_tests(message: Dictionary, previous_authority_id: String) -> Dictionary:
	return _accept_transfer(message, previous_authority_id, "127.0.0.1", 0, false)

func _integrate(seconds: float) -> void:
	if _ship_anchor.is_empty(): return
	var position := Dictionary(_ship_anchor.get("world_position", {})); var velocity := Dictionary(_ship_anchor.get("linear_velocity", {}))
	position["x"] = float(position.get("x",0.0)) + float(velocity.get("x",0.0)) * seconds
	position["y"] = float(position.get("y",0.0)) + float(velocity.get("y",0.0)) * seconds
	position["z"] = float(position.get("z",0.0)) + float(velocity.get("z",0.0)) * seconds
	var yaw := float(_ship_anchor.get("world_yaw",0.0)) + float(_ship_anchor.get("angular_velocity_yaw",0.0)) * seconds
	_ship_anchor = Contract.create_anchor(_authority_id, int(_ship_anchor.get("outer_authority_epoch",1)), int(_ship_anchor.get("simulation_tick",0))+1, position, yaw, velocity, float(_ship_anchor.get("angular_velocity_yaw",0.0)))

func _poll_socket() -> void:
	if _socket == null: return
	while _socket.get_available_packet_count() > 0:
		var bytes := _socket.get_packet(); var remote_ip := _socket.get_packet_ip(); var remote_port := _socket.get_packet_port()
		var decoded = JSON.parse_string(bytes.get_string_from_utf8())
		if not decoded is Dictionary:
			_reject("SM0_P8_ROUTE_JSON_INVALID", {}, remote_ip, remote_port); continue
		var message := Dictionary(decoded)
		_accept_transfer(message, Contract.previous_authority(message), remote_ip, remote_port, true)

func _accept_transfer(message: Dictionary, previous_authority_id: String, remote_ip: String, remote_port: int, verify_sender: bool) -> Dictionary:
	var validation := Contract.validate_transfer(message)
	if not bool(validation.get("success", false)): return _reject(String(validation.get("error_code", "SM0_P8_TRANSFER_INVALID")), message, remote_ip, remote_port)
	if Contract.current_authority(message) != _authority_id: return _reject("SM0_P8_ROUTE_CURRENT_HOP_MISMATCH", message, remote_ip, remote_port)
	var expected_previous := Contract.previous_authority(message)
	if expected_previous.is_empty() or expected_previous != previous_authority_id: return _reject("SM0_P8_ROUTE_PREVIOUS_HOP_MISMATCH", message, remote_ip, remote_port)
	if not Topology.are_adjacent(expected_previous, _authority_id): return _reject("SM0_P8_ROUTE_PREVIOUS_HOP_NOT_ADJACENT", message, remote_ip, remote_port)
	if verify_sender:
		if not _neighbor_endpoints.has(expected_previous): return _reject("SM0_P8_ROUTE_SENDER_NOT_NEIGHBOR", message, remote_ip, remote_port)
		if remote_port != int(Dictionary(_neighbor_endpoints[expected_previous]).get("port",0)): return _reject("SM0_P8_ROUTE_SENDER_PORT_MISMATCH", message, remote_ip, remote_port)
	var ledger_key := "%s|%s|%d" % [String(message.get("transfer_id","")), String(message.get("phase","")), int(message.get("hop_index",0))]
	var fingerprint := Contract.immutable_transfer_fingerprint(message)
	if _route_ledger.has(ledger_key) and String(_route_ledger[ledger_key]) != fingerprint: return _reject("SM0_P8_ROUTE_REPLAY_CONFLICT", message, remote_ip, remote_port)
	_route_ledger[ledger_key] = fingerprint
	return _forward_or_deliver(message, true)

func _forward_or_deliver(message: Dictionary, from_network: bool) -> Dictionary:
	if Contract.current_authority(message) != _authority_id and not from_network:
		# Originated messages start at hop 0, which is this authority.
		return _failure("SM0_P8_ROUTE_ORIGIN_MISMATCH")
	if String(message.get("destination_authority_id", "")) == _authority_id:
		return _deliver_phase(message)
	var next := Contract.next_authority(message)
	if next.is_empty() or not Topology.are_adjacent(_authority_id, next) or not _neighbor_endpoints.has(next): return _reject("SM0_P8_ROUTE_NEXT_HOP_INVALID", message)
	var advanced := Contract.advance(message); var check := Contract.validate_transfer(advanced)
	if not bool(check.get("success",false)): return _reject(String(check.get("error_code","SM0_P8_ROUTE_ADVANCE_INVALID")), advanced)
	var sent := _send_to_neighbor(next, advanced)
	if not bool(sent.get("success",false)): return sent
	_forwarded_count += 1
	_event("SM0_P8_ROUTE_FORWARDED", {"transfer_id": String(message.get("transfer_id","")), "phase": String(message.get("phase","")), "current_authority_id": _authority_id, "next_authority_id": next, "handoff_source_authority_id": String(message.get("handoff_source_authority_id","")), "handoff_target_authority_id": String(message.get("handoff_target_authority_id","")), "route_path": message.get("route_path",[])})
	return _success({"forwarded":true})

func _deliver_phase(message: Dictionary) -> Dictionary:
	match String(message.get("phase", "")):
		Contract.PHASE_PREPARE: return _on_prepare(message)
		Contract.PHASE_PREPARED: return _on_prepared(message)
		Contract.PHASE_COMMIT: return _on_commit(message)
		Contract.PHASE_COMMITTED: return _on_committed(message)
		_: return _reject("SM0_P8_TRANSFER_PHASE_INVALID", message)

func _on_prepare(message: Dictionary) -> Dictionary:
	if _authority_id != String(message.get("handoff_target_authority_id","")): return _reject("SM0_P8_PREPARE_WRONG_TARGET", message)
	if _writer: return _reject("SM0_P8_TARGET_ALREADY_WRITER", message)
	var transfer_id := String(message.get("transfer_id",""))
	var reservation := {"handoff_source_authority_id":String(message.get("handoff_source_authority_id","")), "source_outer_epoch":int(message.get("source_outer_epoch",0)), "target_outer_epoch":int(message.get("target_outer_epoch",0)), "reservation_tick":int(message.get("reservation_tick",0))}
	if _reservations.has(transfer_id) and Dictionary(_reservations[transfer_id]) != reservation: return _reject("SM0_P8_PREPARE_CONFLICT", message)
	_reservations[transfer_id] = reservation
	_prepared_count += 1
	_event("SM0_P8_TARGET_PREPARED", {"transfer_id":transfer_id,"shadow_only":true,"reservation_tick":int(message.get("reservation_tick",0)),"target_outer_epoch":int(message.get("target_outer_epoch",0))})
	var response := Contract.create_transfer(transfer_id, Contract.PHASE_PREPARED, _authority_id, String(message.get("handoff_source_authority_id","")), String(message.get("handoff_source_authority_id","")), _authority_id, int(message.get("source_outer_epoch",0)), int(message.get("target_outer_epoch",0)), int(message.get("reservation_tick",0)))
	return _forward_or_deliver(response, false)

func _on_prepared(message: Dictionary) -> Dictionary:
	if _transfer.is_empty() or String(message.get("transfer_id","")) != String(_transfer.get("transfer_id","")) or String(_transfer.get("stage","")) != "PREPARE_SENT": return _reject("SM0_P8_PREPARED_WITHOUT_SOURCE_TRANSFER", message)
	# Motion intentionally continued while PREPARE was in flight. Capture the freshest state now.
	var latest := _ship_anchor.duplicate(true)
	var commit_anchor := Contract.create_anchor(String(_transfer.get("target","")), int(_transfer.get("target_epoch",0)), int(latest.get("simulation_tick",0)), Dictionary(latest.get("world_position",{})), float(latest.get("world_yaw",0.0)), Dictionary(latest.get("linear_velocity",{})), float(latest.get("angular_velocity_yaw",0.0)))
	var shell := Contract.create_transfer(String(_transfer.get("transfer_id","")), Contract.PHASE_COMMIT, _authority_id, String(_transfer.get("target","")), _authority_id, String(_transfer.get("target","")), int(_transfer.get("source_epoch",0)), int(_transfer.get("target_epoch",0)), int(_transfer.get("reservation_tick",0)), commit_anchor, "placeholder")
	var proof := Contract.retirement_proof_for(shell, commit_anchor)
	var commit := Contract.create_transfer(String(_transfer.get("transfer_id","")), Contract.PHASE_COMMIT, _authority_id, String(_transfer.get("target","")), _authority_id, String(_transfer.get("target","")), int(_transfer.get("source_epoch",0)), int(_transfer.get("target_epoch",0)), int(_transfer.get("reservation_tick",0)), commit_anchor, proof)
	var commit_check := Contract.validate_transfer(commit)
	if not bool(commit_check.get("success",false)): return _reject(String(commit_check.get("error_code","SM0_P8_COMMIT_INVALID")), commit)
	_writer = false
	_transfer["stage"] = "COMMIT_SENT"
	_transfer["commit_tick"] = int(commit_anchor.get("simulation_tick",0))
	_event("SM0_P8_SOURCE_RETIRED", {"transfer_id":String(_transfer.get("transfer_id","")),"source_outer_epoch":int(_transfer.get("source_epoch",0)),"target_outer_epoch":int(_transfer.get("target_epoch",0)),"reservation_tick":int(_transfer.get("reservation_tick",0)),"commit_tick":int(commit_anchor.get("simulation_tick",0)),"linear_velocity":commit_anchor.get("linear_velocity",{}),"angular_velocity_yaw":float(commit_anchor.get("angular_velocity_yaw",0.0)),"inner_authority_unchanged":Contract.ISLAND_AUTHORITY_ID})
	return _forward_or_deliver(commit, false)

func _on_commit(message: Dictionary) -> Dictionary:
	var transfer_id := String(message.get("transfer_id",""))
	if not _reservations.has(transfer_id): return _reject("SM0_P8_COMMIT_WITHOUT_PREPARE", message)
	if _writer: return _reject("SM0_P8_COMMIT_TARGET_ALREADY_WRITER", message)
	var reservation := Dictionary(_reservations[transfer_id])
	if int(message.get("reservation_tick",-1)) != int(reservation.get("reservation_tick",-2)) or int(message.get("target_outer_epoch",0)) != int(reservation.get("target_outer_epoch",0)):
		return _reject("SM0_P8_COMMIT_RESERVATION_MISMATCH", message)
	var anchor := Dictionary(message.get("anchor",{})).duplicate(true)
	_ship_anchor = anchor
	_writer = true
	_committed_count += 1
	_reservations.erase(transfer_id)
	_event("SM0_P8_TARGET_COMMITTED", {"transfer_id":transfer_id,"outer_authority_epoch":int(anchor.get("outer_authority_epoch",0)),"simulation_tick":int(anchor.get("simulation_tick",0)),"world_position":anchor.get("world_position",{}),"linear_velocity":anchor.get("linear_velocity",{}),"angular_velocity_yaw":float(anchor.get("angular_velocity_yaw",0.0)),"island_id":Contract.ISLAND_ID,"island_entity_id":Contract.ISLAND_ENTITY_ID,"inner_authority_unchanged":Contract.ISLAND_AUTHORITY_ID})
	_publish_anchor(true)
	if not _auto_return_target.is_empty(): _return_after_tick = int(anchor.get("simulation_tick",0)) + AUTO_RETURN_TICKS
	var response := Contract.create_transfer(transfer_id, Contract.PHASE_COMMITTED, _authority_id, String(message.get("handoff_source_authority_id","")), String(message.get("handoff_source_authority_id","")), _authority_id, int(message.get("source_outer_epoch",0)), int(message.get("target_outer_epoch",0)), int(message.get("reservation_tick",0)))
	return _forward_or_deliver(response, false)

func _on_committed(message: Dictionary) -> Dictionary:
	if _transfer.is_empty() or String(message.get("transfer_id","")) != String(_transfer.get("transfer_id","")) or String(_transfer.get("stage","")) != "COMMIT_SENT": return _reject("SM0_P8_COMMITTED_WITHOUT_SOURCE_TRANSFER", message)
	_event("SM0_P8_TRANSFER_COMPLETED", {"transfer_id":String(_transfer.get("transfer_id","")),"handoff_target_authority_id":String(_transfer.get("target","")),"source_outer_epoch":int(_transfer.get("source_epoch",0)),"target_outer_epoch":int(_transfer.get("target_epoch",0)),"commit_tick":int(_transfer.get("commit_tick",0)),"inner_authority_unchanged":Contract.ISLAND_AUTHORITY_ID})
	_transfer.clear()
	return _success({"completed":true})

func _publish_anchor(force: bool) -> void:
	if not _writer or _anchor_socket == null or _anchor_port < 1 or _ship_anchor.is_empty(): return
	if not force and Time.get_ticks_msec() - _last_anchor_publish_ms < ANCHOR_PUBLISH_INTERVAL_MS: return
	_last_anchor_publish_ms = Time.get_ticks_msec()
	if _anchor_socket.set_dest_address(_anchor_host, _anchor_port) != OK: return
	_anchor_socket.put_packet(JSON.stringify(_ship_anchor,"",false,true).to_utf8_buffer())
	_event("SM0_P8_ANCHOR_PUBLISHED", {"outer_authority_epoch":int(_ship_anchor.get("outer_authority_epoch",0)),"simulation_tick":int(_ship_anchor.get("simulation_tick",0)),"world_position":_ship_anchor.get("world_position",{}),"linear_velocity":_ship_anchor.get("linear_velocity",{}),"angular_velocity_yaw":float(_ship_anchor.get("angular_velocity_yaw",0.0))})

func _send_to_neighbor(authority_id: String, message: Dictionary) -> Dictionary:
	if _socket == null or not _neighbor_endpoints.has(authority_id): return _failure("SM0_P8_ROUTE_ENDPOINT_MISSING")
	var endpoint := Dictionary(_neighbor_endpoints[authority_id]); var host := String(endpoint.get("host","")); var port := int(endpoint.get("port",0))
	if _socket.set_dest_address(host,port) != OK: return _failure("SM0_P8_ROUTE_DESTINATION_SET_FAILED")
	var error := _socket.put_packet(JSON.stringify(message,"",false,true).to_utf8_buffer())
	return _success() if error == OK else _failure("SM0_P8_ROUTE_SEND_FAILED", {"error":error})

func status_for_tests() -> Dictionary:
	return {"authority_id":_authority_id,"zone_id":_zone_id,"writer_count":1 if _writer else 0,"outer_writer":_writer,"authority_scope":"outer/island/ship/01","authority_present":_authority_id != Topology.AUTHORITY_B,"anchor":_ship_anchor.duplicate(true),"transfer":_transfer.duplicate(true),"reservation_count":_reservations.size(),"forwarded_count":_forwarded_count,"rejected_count":_rejected_count,"prepared_count":_prepared_count,"committed_count":_committed_count}

func shutdown(exit_code: int, reason: String) -> void:
	_event("SM0_P8_OUTER_EXIT", {"exit_code":exit_code,"reason":reason})
	if _socket != null: _socket.close()
	if _anchor_socket != null: _anchor_socket.close()
	set_process(false); finished.emit(exit_code)

func _reject(error_code: String, message: Dictionary, remote_ip: String = "", remote_port: int = 0) -> Dictionary:
	_rejected_count += 1
	_event("SM0_P8_ROUTE_REJECTED", {"error_code":error_code,"transfer_id":String(message.get("transfer_id","")),"phase":String(message.get("phase","")),"remote_ip":remote_ip,"remote_port":remote_port})
	return _failure(error_code)

func _event(event_name: String, details: Dictionary = {}) -> void:
	var event := {"schema":"distributed_world_simulator.sm0_event.v1","event":event_name,"severity":"INFO","process_role":"p8-outer-%s" % _authority_id.get_slice("/",2),"process_id":OS.get_process_id(),"time_msec":Time.get_ticks_msec(),"authority_id":_authority_id,"zone_id":_zone_id,"writer_count":1 if _writer else 0,"authority_scope":"outer/island/ship/01"}
	for key in details.keys(): event[key] = details[key]
	print("[SM0_EVENT] %s" % JSON.stringify(event,"",false,true))

static func _success(details: Dictionary = {}) -> Dictionary: return {"success":true,"error_code":"","details":details.duplicate(true)}
static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary: return {"success":false,"error_code":error_code,"details":details.duplicate(true)}