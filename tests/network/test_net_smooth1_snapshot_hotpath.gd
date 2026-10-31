extends SceneTree

# NET-SMOOTH1 R2 copy-elision falsifier: canonical wire and independent
# caller/receiver ownership must survive optimized hot-path copies.
const Frame = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const Loopback = preload("res://scripts/network/transports/v2/loopback_multi_peer_transport_port.gd")
const Compact = preload("res://scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot.gd")
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")

const PEER := "peer/netsmooth/a"
const SESSION := "transport-session/netsmooth/a"
const ROUTE := "route/netsmooth/a"
const SCHEMA := "planet_simulator.netsmooth.hotpath.v1"

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_frame_payload_isolation()
	_test_real_compact_snapshot_copy_boundary()
	_test_poll_event_detachment()
	for f in failures:
		push_error(f)
	print("NET_SMOOTH1_HOTPATH: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_frame_payload_isolation() -> void:
	var caller: Dictionary = {"type":"COMPACT_GAMEPLAY_SNAPSHOT", "data": {"nested":[{"x":1,"v":[1,2,3]}]}}
	var original: Dictionary = caller.duplicate(true)
	var frame: Dictionary = Frame.create("frame/netsmooth/a/1", SESSION, 1,
		"SNAPSHOT", "UNRELIABLE_SEQUENCED", SCHEMA, caller)
	check(ok(Frame.validate(frame)), "created frame checksum valid")
	check(caller == original, "creating a frame never mutates caller")
	caller["data"]["nested"][0]["x"] = 99
	caller["data"]["nested"][0]["v"].append(4)
	check(int(frame["payload"]["data"]["nested"][0]["x"]) == 1 and frame["payload"]["data"]["nested"][0]["v"].size() == 3, "frame owns independent canonical payload")
	var encoded: Dictionary = Frame.encode(frame)
	check(ok(encoded), "frame remains wire serializable")
	var decoded: Dictionary = Frame.decode(encoded.get("details", {}).get("packet", PackedByteArray()))
	check(ok(decoded), "wire frame survives roundtrip")
	frame["payload"]["data"]["nested"][0]["x"] = -12
	var recv: Dictionary = decoded.get("details", {}).get("frame", {})
	check(int(recv["payload"]["data"]["nested"][0]["x"]) == 1 and recv["payload"]["data"]["nested"][0]["v"].size() == 3, "decode returns a detached payload")
	check(ok(Frame.validate(recv)), "receiver checksum stays valid after sender mutation")
	var corrupt: Dictionary = recv.duplicate(true)
	corrupt["payload"]["data"]["nested"][0]["x"] = 42
	check(not ok(Frame.validate(corrupt)), "payload tampering still rejected")

func _test_real_compact_snapshot_copy_boundary() -> void:
	var service = Service.new()
	var setup := service.setup("simulation/netsmooth/test", 1, 0, {
		"profile": Service.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET", "region_id": "region/netsmooth/test"})
	check(ok(setup), "real authority setup")
	if not ok(setup):
		return
	check(ok(service.join("a", "transport-session/netsmooth/a", "operation/netsmooth/join/a")), "player a joined")
	check(ok(service.join("b", "transport-session/netsmooth/b", "operation/netsmooth/join/b")), "player b joined")
	var snapshot: Dictionary = service.create_snapshot()
	var compact_result: Dictionary = Compact.encode(snapshot)
	check(ok(compact_result), "real compact snapshot built")
	if not ok(compact_result):
		service.shutdown()
		return
	var compact: Dictionary = compact_result.get("details", {}).get("snapshot", {})
	var envelope: Dictionary = {"reason":"MOVEMENT_NETWORK_TICK", "snapshot":compact}
	var before: Dictionary = envelope.duplicate(true)
	for idx in range(2):
		var payload: Dictionary = envelope.duplicate(false)
		payload["type"] = "COMPACT_GAMEPLAY_SNAPSHOT"
		payload["server_sent_at_ms"] = 10
		var wire: Dictionary = Frame.create("frame/netsmooth/movement/%d" % idx,
			SESSION, idx + 1, "SNAPSHOT", "UNRELIABLE_SEQUENCED", SCHEMA, payload)
		check(ok(Frame.validate(wire)), "real compact frame valid peer %d" % idx)
		var decoded: Dictionary = Frame.decode(Frame.encode(wire).get("details", {}).get("packet", PackedByteArray()))
		check(ok(decoded), "real compact frame decoded peer %d" % idx)
		var recv: Dictionary = decoded.get("details", {}).get("frame", {}).get("payload", {})
		check(ok(Compact.decode(recv.get("snapshot", {}))), "real compact snapshot accepted peer %d" % idx)
	check(envelope == before, "multi-peer shallow envelope did not modify shared compact source")
	service.shutdown()

func _test_poll_event_detachment() -> void:
	var port = Loopback.new()
	var boundary = Boundary.new()
	check(ok(boundary.configure(port, 65536, 16, 65536)), "boundary configured")
	check(ok(boundary.start_server({"transport":"LOOPBACK", "name":"netsmooth"})), "listener started")
	check(ok(port.attach_peer(PEER, SESSION, ROUTE, 1)), "peer connected")
	check(ok(boundary.poll_events(16)), "initial peer events accepted")
	for state_transition in ["mark_peer_handshaking", "mark_peer_synchronizing", "mark_peer_ready"]:
		check(ok(boundary.call(state_transition, PEER)), "peer transitioned %s" % state_transition)
	var inbound: Dictionary = Frame.create("frame/netsmooth/incoming/1", SESSION, 1,
		"SNAPSHOT", "UNRELIABLE_SEQUENCED", SCHEMA, {"v":{"x":1}})
	check(ok(port.inject_received_frame(PEER, inbound)), "input event queued")
	var observed: Dictionary = boundary.poll_events(8)
	check(ok(observed), "boundary returns validated frame")
	var events: Array = observed.get("details", {}).get("events", [])
	check(events.size() == 1, "one inbound message delivered")
	if events.size() == 1:
		var received: Dictionary = events[0].get("frame", {})
		check(ok(Frame.validate(received)), "returned public frame checksum valid")
		inbound["payload"]["v"]["x"] = 99
		check(ok(Frame.validate(received)), "returned event unaffected by caller mutation")
		check(int(received.get("payload", {}).get("v", {}).get("x", 0)) == 1, "snapshot content intact")
	boundary.stop()

func ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))

func check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
