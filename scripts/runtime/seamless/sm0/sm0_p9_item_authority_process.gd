extends SceneTree

const AuthorityNode = preload("res://scripts/runtime/seamless/sm0/sm0_p9_item_authority_node.gd")

var _authority_id := ""
var _listen_port := 0
var _socket: PacketPeerUDP
var _authority
var _exit_code := 0

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	_authority_id = String(args.get("authority-id", "")).strip_edges()
	_listen_port = int(args.get("listen-port", 0))
	if _authority_id.is_empty() or _listen_port < 1:
		push_error("SM0_P9_PROCESS_CONFIGURATION_INVALID")
		quit(2)
		return
	_authority = AuthorityNode.new()
	root.add_child(_authority)
	var setup: Dictionary = _authority.setup(_authority_id)
	if not bool(setup.get("success", false)):
		push_error("P9 authority setup failed: %s" % String(setup.get("error_code", "")))
		quit(3)
		return
	_socket = PacketPeerUDP.new()
	var bind_result := _socket.bind(_listen_port, "127.0.0.1")
	if bind_result != OK:
		push_error("SM0_P9_PROCESS_BIND_FAILED:%d" % bind_result)
		quit(4)
		return
	print("[SM0_EVENT] %s" % JSON.stringify({"schema":"distributed_world_simulator.sm0_event.v1","event":"SM0_P9_PROCESS_READY","severity":"INFO","process_role":"p9-item-authority-process","process_id":OS.get_process_id(),"time_msec":Time.get_ticks_msec(),"authority_id":_authority_id,"writer_count":0,"authority_scope":"boundary-item-owner","listen_port":_listen_port}, "", false, true))

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
			response = {"request_id":"", "success":false, "error_code":"SM0_P9_PROCESS_JSON_INVALID", "details":{}}
		else:
			response = _dispatch(Dictionary(decoded))
		if _socket.set_dest_address(remote_ip, remote_port) == OK:
			_socket.put_packet(JSON.stringify(response, "", false, true).to_utf8_buffer())
	return false

func _dispatch(message: Dictionary) -> Dictionary:
	var request_id := String(message.get("request_id", ""))
	var command := String(message.get("command", ""))
	var payload := Dictionary(message.get("payload", {}))
	if request_id.is_empty() or command.is_empty():
		return _wire_result(request_id, {"success":false, "error_code":"SM0_P9_PROCESS_COMMAND_INVALID", "details":{}})
	var result: Dictionary
	match command:
		"SEED":
			result = _authority.seed_item_for_tests(Dictionary(payload.get("item", {})))
		"INTERACT":
			result = _authority.apply_interaction(Dictionary(payload.get("request", {})))
		"PREPARE_SEND":
			result = _authority.prepare_send(Dictionary(payload.get("request", {})))
		"PREPARE_RECEIVE":
			result = _authority.prepare_receive(Dictionary(payload.get("request", {})))
		"COMMIT_SEND":
			result = _authority.commit_send(Dictionary(payload.get("request", {})))
		"CANCEL_SEND":
			result = _authority.cancel_send(Dictionary(payload.get("request", {})))
		"COMMIT_RECEIVE":
			result = _authority.commit_receive(Dictionary(payload.get("request", {})), Dictionary(payload.get("retirement_proof", {})))
		"ROLLBACK_SEND":
			result = _authority.rollback_send(Dictionary(payload.get("request", {})))
		"ABORT_RECEIVE":
			result = _authority.abort_receive(Dictionary(payload.get("request", {})))
		"FAIL_NEXT_RECEIVE_COMMIT":
			_authority.fail_next_receive_commit_for_tests()
			result = {"success":true, "error_code":"", "details":{}}
		"STATUS":
			result = {"success":true, "error_code":"", "details":{"status":_authority.status_for_tests()}}
		"SHUTDOWN":
			result = {"success":true, "error_code":"", "details":{}}
			call_deferred("_shutdown")
		_:
			result = {"success":false, "error_code":"SM0_P9_PROCESS_COMMAND_UNKNOWN", "details":{}}
	return _wire_result(request_id, result)

func _wire_result(request_id: String, result: Dictionary) -> Dictionary:
	return {
		"request_id": request_id,
		"success": bool(result.get("success", false)),
		"error_code": String(result.get("error_code", "")),
		"details": Dictionary(result.get("details", {})).duplicate(true),
	}

func _shutdown() -> void:
	if _socket != null:
		_socket.close()
	print("[SM0_EVENT] %s" % JSON.stringify({"schema":"distributed_world_simulator.sm0_event.v1","event":"SM0_P9_PROCESS_EXIT","severity":"INFO","process_role":"p9-item-authority-process","process_id":OS.get_process_id(),"time_msec":Time.get_ticks_msec(),"authority_id":_authority_id,"writer_count":0,"authority_scope":"boundary-item-owner","exit_code":_exit_code}, "", false, true))
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