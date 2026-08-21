extends SceneTree

const Contract = preload("res://scripts/runtime/seamless/sm0/sm0_p10_view_contract.gd")

var _authority_id := ""
var _source_role := ""
var _listen_port := 0
var _source_epoch := 1
var _sequence := 1
var _fine_ready := false
var _socket: PacketPeerUDP
var _exit_code := 0

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	_authority_id = String(args.get("authority-id", "")).strip_edges()
	_source_role = String(args.get("source-role", "")).strip_edges()
	_listen_port = int(args.get("listen-port", 0))
	_source_epoch = int(args.get("source-epoch", 1))
	if _authority_id not in Contract.AUTHORITIES or _source_role not in Contract.SOURCE_ROLES or _listen_port < 1 or _source_epoch < 1:
		push_error("SM0_P10_SOURCE_CONFIGURATION_INVALID")
		quit(2)
		return
	_socket = PacketPeerUDP.new()
	var bind_result := _socket.bind(_listen_port, "127.0.0.1")
	if bind_result != OK:
		push_error("SM0_P10_SOURCE_BIND_FAILED:%d" % bind_result)
		quit(3)
		return
	print("[SM0_EVENT] %s" % JSON.stringify({
		"schema":"distributed_world_simulator.sm0_event.v1",
		"event":"SM0_P10_SOURCE_READY",
		"severity":"INFO",
		"process_role":"p10-projection-source",
		"process_id":OS.get_process_id(),
		"time_msec":Time.get_ticks_msec(),
		"authority_id":_authority_id,
		"writer_count":0,
		"authority_scope":"projection-source",
		"source_role":_source_role,
		"source_epoch":_source_epoch,
		"listen_port":_listen_port,
	}, "", false, true))

func _process(_delta: float) -> bool:
	if _socket == null:
		return false
	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		var remote_ip := _socket.get_packet_ip()
		var remote_port := _socket.get_packet_port()
		var decoded = JSON.parse_string(packet.get_string_from_utf8())
		var response: Dictionary
		if not decoded is Dictionary:
			response = {"request_id":"", "success":false, "error_code":"SM0_P10_SOURCE_JSON_INVALID", "details":{}}
		else:
			response = _dispatch(Dictionary(decoded))
		if _socket != null and _socket.set_dest_address(remote_ip, remote_port) == OK:
			_socket.put_packet(JSON.stringify(response, "", false, true).to_utf8_buffer())
	return false

func _dispatch(message: Dictionary) -> Dictionary:
	var request_id := String(message.get("request_id", ""))
	var command := String(message.get("command", ""))
	if request_id.is_empty() or command.is_empty():
		return _wire(request_id, false, "SM0_P10_SOURCE_COMMAND_INVALID", {})
	match command:
		"GET_PROJECTION":
			var snapshot := _build_snapshot()
			print("[SM0_EVENT] %s" % JSON.stringify({"schema":"distributed_world_simulator.sm0_event.v1","event":"SM0_P10_SOURCE_SNAPSHOT_SENT","severity":"INFO","process_role":"p10-projection-source","process_id":OS.get_process_id(),"time_msec":Time.get_ticks_msec(),"authority_id":_authority_id,"writer_count":0,"authority_scope":"projection-source","projection_sequence":_sequence,"fine_ready":_fine_ready}, "", false, true))
			return _wire(request_id, true, "", {"snapshot": snapshot})
		"ADVANCE_FINE":
			_fine_ready = true
			_sequence += 1
			return _wire(request_id, true, "", {"projection_sequence":_sequence, "fine_ready":true})
		"ADVANCE_ENTITY":
			_sequence += 1
			return _wire(request_id, true, "", {"projection_sequence":_sequence})
		"STATUS":
			return _wire(request_id, true, "", {"authority_id":_authority_id,"source_role":_source_role,"source_epoch":_source_epoch,"projection_sequence":_sequence,"fine_ready":_fine_ready})
		"SHUTDOWN":
			call_deferred("_shutdown")
			return _wire(request_id, true, "", {})
		_:
			return _wire(request_id, false, "SM0_P10_SOURCE_COMMAND_UNKNOWN", {})

func _build_snapshot() -> Dictionary:
	var entities: Array = []
	var reps: Array = []
	var tick := 100 + _sequence
	match _authority_id:
		"authority/sm0/a":
			entities.append(Contract.entity("player/a", "PLAYER", {"x":-12.0 + float(_sequence - 1),"y":0.0,"z":0.0}, 92, _sequence))
			reps.append(Contract.representation("rep/a/terrain/coarse", "region/a", "COARSE", {"x":-20.0,"y":0.0,"z":5.0}, 70, 220, "artifact-a-coarse-0001", true))
			reps.append(Contract.representation("rep/a/terrain/fine", "region/a", "FINE", {"x":-20.0,"y":0.0,"z":5.0}, 70, 900, "artifact-a-fine-0001", _fine_ready))
		"authority/sm0/b":
			entities.append(Contract.entity("ship/01", "VEHICLE", {"x":0.0,"y":0.0,"z":0.0}, 100, _sequence))
			reps.append(Contract.representation("rep/b/construction/coarse", "structure/b", "COARSE", {"x":8.0,"y":0.0,"z":0.0}, 95, 260, "artifact-b-coarse-0001", true))
			reps.append(Contract.representation("rep/b/construction/fine", "structure/b", "FINE", {"x":8.0,"y":0.0,"z":0.0}, 95, 1100, "artifact-b-fine-0001", true))
		"authority/sm0/c":
			entities.append(Contract.entity("player/c", "PLAYER", {"x":18.0,"y":0.0,"z":0.0}, 84, _sequence))
			reps.append(Contract.representation("rep/c/terrain/coarse", "region/c", "COARSE", {"x":35.0,"y":0.0,"z":0.0}, 60, 180, "artifact-c-coarse-0001", true))
			reps.append(Contract.representation("rep/c/terrain/fine", "region/c", "FINE", {"x":35.0,"y":0.0,"z":0.0}, 60, 780, "artifact-c-fine-0001", true))
	return Contract.create_snapshot(_authority_id, _source_epoch, _source_role, _sequence, tick, entities, reps)

func _wire(request_id: String, success: bool, error_code: String, details: Dictionary) -> Dictionary:
	return {"request_id":request_id,"success":success,"error_code":error_code,"details":details.duplicate(true)}

func _shutdown() -> void:
	if _socket != null:
		_socket.close()
	print("[SM0_EVENT] %s" % JSON.stringify({"schema":"distributed_world_simulator.sm0_event.v1","event":"SM0_P10_SOURCE_EXIT","severity":"INFO","process_role":"p10-projection-source","process_id":OS.get_process_id(),"time_msec":Time.get_ticks_msec(),"authority_id":_authority_id,"writer_count":0,"authority_scope":"projection-source","exit_code":_exit_code}, "", false, true))
	quit(_exit_code)

static func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = {}
	for raw in args:
		var text := String(raw)
		if not text.begins_with("--"):
			continue
		var body := text.substr(2)
		var separator := body.find("=")
		if separator < 0:
			parsed[body] = true
		else:
			parsed[body.substr(0, separator)] = body.substr(separator + 1)
	return parsed