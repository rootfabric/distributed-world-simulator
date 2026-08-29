extends SceneTree

const Contract = preload("res://scripts/runtime/seamless/sm0/sm0_p11_fault_contract.gd")

var _authority_id := ""
var _listen_port := 0
var _instance_epoch := 1
var _available := true
var _socket: PacketPeerUDP
var _aggregates: Dictionary = {}
var _source_ops: Dictionary = {}
var _target_ops: Dictionary = {}
var _interaction_ops: Dictionary = {}

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	_authority_id = String(args.get("authority-id", "")).strip_edges()
	_listen_port = int(args.get("listen-port", 0))
	_instance_epoch = int(args.get("instance-epoch", 1))
	if not Contract.valid_authority(_authority_id) or _listen_port < 1 or _instance_epoch < 1:
		push_error("SM0_P11_PROCESS_CONFIGURATION_INVALID")
		quit(2)
		return
	_socket = PacketPeerUDP.new()
	var bind_result := _socket.bind(_listen_port, "127.0.0.1")
	if bind_result != OK:
		push_error("SM0_P11_PROCESS_BIND_FAILED:%d" % bind_result)
		quit(3)
		return
	_event("SM0_P11_AUTHORITY_READY", {"listen_port": _listen_port, "instance_epoch": _instance_epoch, "available": _available})

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
			response = _wire("", false, "SM0_P11_PROCESS_JSON_INVALID", {})
		else:
			response = _dispatch(Dictionary(decoded))
		if _socket != null and _socket.set_dest_address(remote_ip, remote_port) == OK:
			_socket.put_packet(JSON.stringify(response, "", false, true).to_utf8_buffer())
	return false

func _dispatch(message: Dictionary) -> Dictionary:
	var request_id := String(message.get("request_id", ""))
	var command := String(message.get("command", ""))
	var payload: Dictionary = Dictionary(message.get("payload", {})) if message.get("payload", {}) is Dictionary else {}
	if request_id.is_empty() or command.is_empty():
		return _wire(request_id, false, "SM0_P11_PROCESS_COMMAND_INVALID", {})
	if not _available and command not in ["SET_AVAILABLE", "STATUS", "SHUTDOWN"]:
		return _wire(request_id, false, "SM0_P11_PROCESS_AUTHORITY_UNAVAILABLE", {})
	match command:
		"SEED":
			return _seed(request_id, payload)
		"PREPARE_SOURCE":
			return _prepare_source(request_id, payload)
		"PREPARE_TARGET":
			return _prepare_target(request_id, payload)
		"RETIRE_SOURCE":
			return _retire_source(request_id, payload)
		"COMMIT_TARGET":
			return _commit_target(request_id, payload)
		"CANCEL_SOURCE":
			return _cancel_source(request_id, payload)
		"ROLLBACK_SOURCE":
			return _rollback_source(request_id, payload)
		"ABORT_TARGET":
			return _abort_target(request_id, payload)
		"INTERACT":
			return _interact(request_id, payload)
		"SET_AVAILABLE":
			_available = bool(payload.get("available", false))
			_event("SM0_P11_AUTHORITY_AVAILABILITY_CHANGED", {"available": _available})
			return _wire(request_id, true, "", {"available": _available})
		"STATUS":
			return _wire(request_id, true, "", {"authority_id": _authority_id, "instance_epoch": _instance_epoch, "available": _available, "aggregates": _aggregates.duplicate(true)})
		"SHUTDOWN":
			call_deferred("_shutdown")
			return _wire(request_id, true, "", {})
		_:
			return _wire(request_id, false, "SM0_P11_PROCESS_COMMAND_UNKNOWN", {})

func _seed(request_id: String, payload: Dictionary) -> Dictionary:
	var aggregate_id := String(payload.get("aggregate_id", "")).strip_edges()
	var identity_id := String(payload.get("identity_id", "")).strip_edges()
	var authority_epoch := int(payload.get("authority_epoch", 0))
	var active_writer := bool(payload.get("active_writer", false))
	if aggregate_id.is_empty() or identity_id.is_empty() or authority_epoch < 1:
		return _wire(request_id, false, "SM0_P11_PROCESS_SEED_INVALID", {})
	if _aggregates.has(aggregate_id):
		var existing: Dictionary = Dictionary(_aggregates[aggregate_id])
		if String(existing.get("identity_id", "")) == identity_id and int(existing.get("authority_epoch", 0)) == authority_epoch and bool(existing.get("active_writer", false)) == active_writer:
			return _wire(request_id, true, "", {"replay": true})
		return _wire(request_id, false, "SM0_P11_PROCESS_SEED_CONFLICT", {})
	_aggregates[aggregate_id] = {"aggregate_id": aggregate_id, "identity_id": identity_id, "authority_epoch": authority_epoch, "active_writer": active_writer, "frozen": false, "state_revision": 1}
	return _wire(request_id, true, "", {"replay": false})

func _prepare_source(request_id: String, payload: Dictionary) -> Dictionary:
	var operation_id := String(payload.get("operation_id", ""))
	var aggregate_id := String(payload.get("aggregate_id", ""))
	var target_authority_id := String(payload.get("target_authority_id", ""))
	var expected_epoch := int(payload.get("expected_epoch", 0))
	if _source_ops.has(operation_id):
		var op: Dictionary = Dictionary(_source_ops[operation_id])
		if String(op.get("aggregate_id", "")) != aggregate_id or String(op.get("target_authority_id", "")) != target_authority_id or int(op.get("source_epoch", 0)) != expected_epoch:
			return _wire(request_id, false, "SM0_P11_PROCESS_OPERATION_REUSE_CONFLICT", {})
		return _wire(request_id, true, "", {"replay": true, "phase": String(op.get("phase", ""))})
	if not _aggregates.has(aggregate_id):
		return _wire(request_id, false, "SM0_P11_PROCESS_AGGREGATE_UNKNOWN", {})
	var record: Dictionary = Dictionary(_aggregates[aggregate_id])
	if not bool(record.get("active_writer", false)):
		return _wire(request_id, false, "SM0_P11_PROCESS_SOURCE_NOT_WRITER", {})
	if bool(record.get("frozen", false)):
		return _wire(request_id, false, "SM0_P11_PROCESS_SOURCE_ALREADY_FROZEN", {})
	if int(record.get("authority_epoch", 0)) != expected_epoch:
		return _wire(request_id, false, "SM0_P11_PROCESS_SOURCE_EPOCH_MISMATCH", {})
	if not Contract.valid_authority(target_authority_id) or target_authority_id == _authority_id:
		return _wire(request_id, false, "SM0_P11_PROCESS_TARGET_INVALID", {})
	record["frozen"] = true
	_aggregates[aggregate_id] = record
	_source_ops[operation_id] = {"operation_id": operation_id, "aggregate_id": aggregate_id, "identity_id": String(record.get("identity_id", "")), "source_authority_id": _authority_id, "target_authority_id": target_authority_id, "source_epoch": expected_epoch, "target_epoch": expected_epoch + 1, "phase": "PREPARED"}
	return _wire(request_id, true, "", {"replay": false, "phase": "PREPARED"})

func _prepare_target(request_id: String, payload: Dictionary) -> Dictionary:
	var operation_id := String(payload.get("operation_id", ""))
	var aggregate_id := String(payload.get("aggregate_id", ""))
	var identity_id := String(payload.get("identity_id", ""))
	var source_authority_id := String(payload.get("source_authority_id", ""))
	var source_epoch := int(payload.get("source_epoch", 0))
	var target_epoch := int(payload.get("target_epoch", 0))
	if not Contract.valid_authority(source_authority_id) or source_authority_id == _authority_id or target_epoch != source_epoch + 1:
		return _wire(request_id, false, "SM0_P11_PROCESS_TARGET_PREPARE_INVALID", {})
	if _target_ops.has(operation_id):
		var op: Dictionary = Dictionary(_target_ops[operation_id])
		if String(op.get("aggregate_id", "")) != aggregate_id or String(op.get("identity_id", "")) != identity_id or String(op.get("source_authority_id", "")) != source_authority_id or int(op.get("target_epoch", 0)) != target_epoch:
			return _wire(request_id, false, "SM0_P11_PROCESS_OPERATION_REUSE_CONFLICT", {})
		return _wire(request_id, true, "", {"replay": true, "phase": String(op.get("phase", ""))})
	if _aggregates.has(aggregate_id) and bool(Dictionary(_aggregates[aggregate_id]).get("active_writer", false)):
		return _wire(request_id, false, "SM0_P11_PROCESS_TARGET_ALREADY_WRITER", {})
	_target_ops[operation_id] = {"operation_id": operation_id, "aggregate_id": aggregate_id, "identity_id": identity_id, "source_authority_id": source_authority_id, "target_authority_id": _authority_id, "source_epoch": source_epoch, "target_epoch": target_epoch, "phase": "SHADOW"}
	return _wire(request_id, true, "", {"replay": false, "phase": "SHADOW"})

func _retire_source(request_id: String, payload: Dictionary) -> Dictionary:
	var operation_id := String(payload.get("operation_id", ""))
	if not _source_ops.has(operation_id):
		return _wire(request_id, false, "SM0_P11_PROCESS_SOURCE_OPERATION_UNKNOWN", {})
	var op: Dictionary = Dictionary(_source_ops[operation_id])
	if String(op.get("phase", "")) == "RETIRED":
		return _wire(request_id, true, "", {"replay": true, "retirement_token": String(op.get("retirement_token", ""))})
	if String(op.get("phase", "")) != "PREPARED":
		return _wire(request_id, false, "SM0_P11_PROCESS_SOURCE_PHASE_INVALID", {})
	var aggregate_id := String(op.get("aggregate_id", ""))
	var record: Dictionary = Dictionary(_aggregates.get(aggregate_id, {}))
	if not bool(record.get("active_writer", false)) or not bool(record.get("frozen", false)):
		return _wire(request_id, false, "SM0_P11_PROCESS_SOURCE_RETIRE_INVARIANT", {})
	var token := Contract.retirement_token(operation_id, aggregate_id, String(op.get("identity_id", "")), _authority_id, String(op.get("target_authority_id", "")), int(op.get("source_epoch", 0)), int(op.get("target_epoch", 0)))
	record["active_writer"] = false
	record["frozen"] = true
	_aggregates[aggregate_id] = record
	op["phase"] = "RETIRED"
	op["retirement_token"] = token
	_source_ops[operation_id] = op
	return _wire(request_id, true, "", {"replay": false, "retirement_token": token})

func _commit_target(request_id: String, payload: Dictionary) -> Dictionary:
	var operation_id := String(payload.get("operation_id", ""))
	var token := String(payload.get("retirement_token", ""))
	if not _target_ops.has(operation_id):
		return _wire(request_id, false, "SM0_P11_PROCESS_TARGET_OPERATION_UNKNOWN", {})
	var op: Dictionary = Dictionary(_target_ops[operation_id])
	if String(op.get("phase", "")) == "COMMITTED":
		if token != String(op.get("retirement_token", "")):
			return _wire(request_id, false, "SM0_P11_PROCESS_RETIREMENT_PROOF_INVALID", {})
		return _wire(request_id, true, "", {"replay": true, "authority_epoch": int(op.get("target_epoch", 0))})
	var expected := Contract.retirement_token(operation_id, String(op.get("aggregate_id", "")), String(op.get("identity_id", "")), String(op.get("source_authority_id", "")), _authority_id, int(op.get("source_epoch", 0)), int(op.get("target_epoch", 0)))
	if token.is_empty() or token != expected:
		return _wire(request_id, false, "SM0_P11_PROCESS_RETIREMENT_PROOF_INVALID", {})
	var aggregate_id := String(op.get("aggregate_id", ""))
	var existing: Dictionary = Dictionary(_aggregates.get(aggregate_id, {}))
	if bool(existing.get("active_writer", false)):
		return _wire(request_id, false, "SM0_P11_PROCESS_TARGET_ALREADY_WRITER", {})
	_aggregates[aggregate_id] = {"aggregate_id": aggregate_id, "identity_id": String(op.get("identity_id", "")), "authority_epoch": int(op.get("target_epoch", 0)), "active_writer": true, "frozen": false, "state_revision": int(existing.get("state_revision", 0)) + 1}
	op["phase"] = "COMMITTED"
	op["retirement_token"] = token
	_target_ops[operation_id] = op
	return _wire(request_id, true, "", {"replay": false, "authority_epoch": int(op.get("target_epoch", 0))})

func _cancel_source(request_id: String, payload: Dictionary) -> Dictionary:
	var operation_id := String(payload.get("operation_id", ""))
	if not _source_ops.has(operation_id):
		return _wire(request_id, false, "SM0_P11_PROCESS_SOURCE_OPERATION_UNKNOWN", {})
	var op: Dictionary = Dictionary(_source_ops[operation_id])
	if String(op.get("phase", "")) != "PREPARED":
		return _wire(request_id, false, "SM0_P11_PROCESS_SOURCE_CANCEL_PHASE_INVALID", {})
	var aggregate_id := String(op.get("aggregate_id", ""))
	var record: Dictionary = Dictionary(_aggregates.get(aggregate_id, {}))
	record["frozen"] = false
	_aggregates[aggregate_id] = record
	_source_ops.erase(operation_id)
	return _wire(request_id, true, "", {})

func _rollback_source(request_id: String, payload: Dictionary) -> Dictionary:
	var operation_id := String(payload.get("operation_id", ""))
	if not _source_ops.has(operation_id):
		return _wire(request_id, false, "SM0_P11_PROCESS_SOURCE_OPERATION_UNKNOWN", {})
	var op: Dictionary = Dictionary(_source_ops[operation_id])
	if String(op.get("phase", "")) != "RETIRED":
		return _wire(request_id, false, "SM0_P11_PROCESS_SOURCE_ROLLBACK_PHASE_INVALID", {})
	var aggregate_id := String(op.get("aggregate_id", ""))
	var record: Dictionary = Dictionary(_aggregates.get(aggregate_id, {}))
	record["active_writer"] = true
	record["frozen"] = false
	_aggregates[aggregate_id] = record
	op["phase"] = "ROLLED_BACK"
	_source_ops[operation_id] = op
	return _wire(request_id, true, "", {})

func _abort_target(request_id: String, payload: Dictionary) -> Dictionary:
	var operation_id := String(payload.get("operation_id", ""))
	if not _target_ops.has(operation_id):
		return _wire(request_id, false, "SM0_P11_PROCESS_TARGET_OPERATION_UNKNOWN", {})
	var op: Dictionary = Dictionary(_target_ops[operation_id])
	if String(op.get("phase", "")) == "COMMITTED":
		return _wire(request_id, false, "SM0_P11_PROCESS_TARGET_ALREADY_COMMITTED", {})
	_target_ops.erase(operation_id)
	return _wire(request_id, true, "", {})

func _interact(request_id: String, payload: Dictionary) -> Dictionary:
	var operation_id := String(payload.get("operation_id", ""))
	var aggregate_id := String(payload.get("aggregate_id", ""))
	var expected_epoch := int(payload.get("expected_epoch", 0))
	if _interaction_ops.has(operation_id):
		var prior: Dictionary = Dictionary(_interaction_ops[operation_id])
		if String(prior.get("aggregate_id", "")) != aggregate_id or int(prior.get("expected_epoch", 0)) != expected_epoch:
			return _wire(request_id, false, "SM0_P11_PROCESS_INTERACTION_REPLAY_CONFLICT", {})
		var prior_response: Dictionary = Dictionary(prior.get("response", {})).duplicate(true)
		prior_response["details"] = Dictionary(prior_response.get("details", {})).duplicate(true)
		Dictionary(prior_response["details"])["replay"] = true
		return prior_response
	if not _aggregates.has(aggregate_id):
		return _wire(request_id, false, "SM0_P11_PROCESS_AGGREGATE_UNKNOWN", {})
	var record: Dictionary = Dictionary(_aggregates[aggregate_id])
	var response: Dictionary
	if not bool(record.get("active_writer", false)):
		response = _wire(request_id, false, "SM0_P11_PROCESS_INTERACTION_NOT_WRITER", {})
	elif bool(record.get("frozen", false)):
		response = _wire(request_id, false, "SM0_P11_PROCESS_INTERACTION_FROZEN", {})
	elif int(record.get("authority_epoch", 0)) != expected_epoch:
		response = _wire(request_id, false, "SM0_P11_PROCESS_INTERACTION_EPOCH_STALE", {})
	else:
		record["state_revision"] = int(record.get("state_revision", 0)) + 1
		_aggregates[aggregate_id] = record
		response = _wire(request_id, true, "", {"state_revision": int(record.get("state_revision", 0)), "replay": false})
	_interaction_ops[operation_id] = {"aggregate_id": aggregate_id, "expected_epoch": expected_epoch, "response": response.duplicate(true)}
	return response

func _wire(request_id: String, success: bool, error_code: String, details: Dictionary) -> Dictionary:
	return {"request_id": request_id, "success": success, "error_code": error_code, "details": details.duplicate(true)}

func _event(event_name: String, extra: Dictionary = {}) -> void:
	var payload := {"schema": "distributed_world_simulator.sm0_event.v1", "event": event_name, "severity": "INFO", "process_role": "p11-authority", "process_id": OS.get_process_id(), "time_msec": Time.get_ticks_msec(), "authority_id": _authority_id, "writer_count": _active_writer_total(), "authority_scope": "p11-fault-soak"}
	for key in extra.keys():
		payload[key] = extra[key]
	print("[SM0_EVENT] %s" % JSON.stringify(payload, "", false, true))

func _active_writer_total() -> int:
	var count := 0
	for raw in _aggregates.values():
		if raw is Dictionary and bool(Dictionary(raw).get("active_writer", false)):
			count += 1
	return count

func _shutdown() -> void:
	if _socket != null:
		_socket.close()
	_event("SM0_P11_AUTHORITY_EXIT", {"exit_code": 0})
	quit(0)

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
