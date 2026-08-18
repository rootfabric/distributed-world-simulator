extends SceneTree

const Datagram = preload("res://scripts/runtime/seamless/mrpf/h1/mrpf_h1_projection_datagram.gd")
const Fixture = preload("res://scripts/runtime/seamless/mrpf/h1/mrpf_h1_space_earth_fixture.gd")

var _peer := PacketPeerUDP.new()
var _role := ""
var _route_id := ""
var _session_id := ""
var _target_port := 0
var _source_revision := 1
var _interval_ms := 100
var _sequence := 0
var _last_send_ms := 0
var _packet: PackedByteArray = PackedByteArray()

func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	_role = String(args.get("role", "")).strip_edges().to_lower()
	_target_port = int(args.get("target-port", "0"))
	_source_revision = int(args.get("revision", "1"))
	_interval_ms = max(20, int(args.get("interval-ms", "100")))
	if not ["space", "earth"].has(_role):
		_fail("MRPF_H1_PUBLISHER_ROLE_INVALID")
		return
	if _target_port < 1 or _target_port > 65535:
		_fail("MRPF_H1_PUBLISHER_PORT_INVALID")
		return
	if _source_revision < 1:
		_fail("MRPF_H1_PUBLISHER_REVISION_INVALID")
		return
	_route_id = Fixture.route_id_for_role(_role)
	_session_id = "%s/revision-%d/pid-%d" % [_route_id, _source_revision, OS.get_process_id()]
	var representation := Fixture.make_for_role(_role, _source_revision)
	var encoded := Datagram.encode(_route_id, _session_id, 1, representation)
	if not bool(encoded.get("success", false)):
		_fail("MRPF_H1_PUBLISHER_ENCODE_FAILED:%s" % String(encoded.get("error_code", "")))
		return
	_packet = PackedByteArray(encoded["details"]["packet"])
	var err := _peer.set_dest_address("127.0.0.1", _target_port)
	if err != OK:
		_fail("MRPF_H1_PUBLISHER_DESTINATION_FAILED:%d" % err)
		return
	print("MRPF_H1_PUBLISHER_READY role=%s route=%s revision=%d target_port=%d" % [
		_role, _route_id, _source_revision, _target_port
	])
	_send_packet()

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_msec()
	if now - _last_send_ms >= _interval_ms:
		_send_packet()
	return false

func _send_packet() -> void:
	_sequence += 1
	var representation := Fixture.make_for_role(_role, _source_revision)
	var encoded := Datagram.encode(_route_id, _session_id, _sequence, representation)
	if not bool(encoded.get("success", false)):
		_fail("MRPF_H1_PUBLISHER_ENCODE_FAILED:%s" % String(encoded.get("error_code", "")))
		return
	_packet = PackedByteArray(encoded["details"]["packet"])
	var err := _peer.put_packet(_packet)
	if err != OK:
		_fail("MRPF_H1_PUBLISHER_SEND_FAILED:%d" % err)
		return
	_last_send_ms = Time.get_ticks_msec()

func _fail(message: String) -> void:
	push_error(message)
	printerr(message)
	quit(2)

func _parse_args(raw_args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for raw in raw_args:
		var text := String(raw)
		if not text.begins_with("--"):
			continue
		var body := text.substr(2)
		var split := body.split("=", true, 1)
		if split.size() == 2:
			result[String(split[0])] = String(split[1])
	return result
