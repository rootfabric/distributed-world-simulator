extends SceneTree

# NET-SMOOTH1 R3: a reliable PRODUCT_SEAM_STATE is mandatory on JOIN,
# actual authority/region changes and reconnect. Sending identical seam state
# on every 20Hz movement snapshot floods the RESYNC channel unnecessarily.
const Server = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")
const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const Loopback = preload("res://scripts/network/transports/v2/loopback_multi_peer_transport_port.gd")
const SeamState = preload("res://scripts/runtime/networked_gameplay/user1/user1_product_seam_state.gd")
const Frame = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")

const PEER_A := "peer/netsmooth/seam-a"
const PEER_B := "peer/netsmooth/seam-b"
const SESSION_A := "transport-session/netsmooth/seam-a"
const SESSION_B := "transport-session/netsmooth/seam-b"
const SESSION_A2 := "transport-session/netsmooth/seam-a2"
const ROUTE_A := "route/netsmooth/seam-a"
const ROUTE_B := "route/netsmooth/seam-b"
const PLAYER_A := "netsmooth-a"
const PLAYER_B := "netsmooth-b"

class FakeService:
	extends RefCounted
	var states: Dictionary = {}

	func get_product_seam_state(player_id: String) -> Dictionary:
		return Dictionary(states.get(player_id, {})).duplicate(true)

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var port = Loopback.new()
	var boundary = _create_ready_boundary(port, SESSION_A, SESSION_B)
	var service = FakeService.new()
	service.states[PLAYER_A] = _seam(PLAYER_A, false)
	service.states[PLAYER_B] = _seam(PLAYER_B, false)
	var runtime = Server.new()
	runtime._boundary = boundary
	runtime._service = service
	runtime._peer_to_player = {PEER_A: PLAYER_A, PEER_B: PLAYER_B}
	runtime._peer_to_session = {PEER_A: SESSION_A, PEER_B: SESSION_B}

	check(runtime._send_product_seam_state(PEER_A, PLAYER_A, "PLAYER_JOINED"), "join A sends reliable seam")
	check(runtime._send_product_seam_state(PEER_B, PLAYER_B, "PLAYER_JOINED"), "join B sends reliable seam")
	check(port.get_messages_for_peer(PEER_A).size() == 1, "one initial A seam")
	check(port.get_messages_for_peer(PEER_B).size() == 1, "one initial B seam")
	for i in range(20):
		check(runtime._send_product_seam_state(PEER_A, PLAYER_A, "MOVEMENT_NETWORK_TICK"), "A unchanged seam skip %d" % i)
		check(runtime._send_product_seam_state(PEER_B, PLAYER_B, "MOVEMENT_NETWORK_TICK"), "B unchanged seam skip %d" % i)
	check(port.get_messages_for_peer(PEER_A).size() == 1, "20Hz identical seam never resent A")
	check(port.get_messages_for_peer(PEER_B).size() == 1, "20Hz identical seam never resent B")
	check(_counter(runtime, "_seam_unchanged_skipped") == 40, "exact count of 40 suppressed seam frames")

	service.states[PLAYER_A] = _seam(PLAYER_A, true)
	check(runtime._send_product_seam_state(PEER_A, PLAYER_A, "MOVEMENT_NETWORK_TICK"), "authority crossing resends A")
	check(port.get_messages_for_peer(PEER_A).size() == 2, "crossing delivered a second A frame")
	check(port.get_messages_for_peer(PEER_B).size() == 1, "B did not receive A seam")
	var last_frame: Dictionary = port.get_messages_for_peer(PEER_A)[1]
	check(_valid_frame(last_frame), "changed seam frame checksum and state validate")
	check(String(last_frame.get("payload", {}).get("state", {}).get("region_id", "")) == "region/user1/b", "new authority B region reaches recipient")
	check(String(last_frame.get("channel", "")) == "RESYNC" and String(last_frame.get("delivery_mode", "")) == "RELIABLE_ORDERED", "seam remains ordered and reliable")
	check(runtime._send_product_seam_state(PEER_A, PLAYER_A, "MOVEMENT_NETWORK_TICK"), "same crossed state skipped")
	check(port.get_messages_for_peer(PEER_A).size() == 2, "no repeated crossing frame")

	# Before a failed send, do not advance the last-sent state. Once the
	# boundary comes back, the same authoritative state must be retried.
	service.states[PLAYER_A] = _seam(PLAYER_A, false)
	runtime._boundary = null
	check(not runtime._send_product_seam_state(PEER_A, PLAYER_A, "MOVEMENT_NETWORK_TICK"), "failed send is reported")
	runtime._boundary = boundary
	check(runtime._send_product_seam_state(PEER_A, PLAYER_A, "MOVEMENT_NETWORK_TICK"), "failed send is retried")
	check(port.get_messages_for_peer(PEER_A).size() == 3, "retried state arrives")

	# Repeated JOIN always sends the current authoritative seam, even when
	# the state is byte-for-byte equal. No stale cache suppresses a resync.
	check(runtime._send_product_seam_state(PEER_A, PLAYER_A, "PLAYER_JOINED"), "replayed join always resends")
	check(port.get_messages_for_peer(PEER_A).size() == 4, "repeat JOIN has fresh reliable frame")

	boundary.stop()
	var port_new = Loopback.new()
	var new_boundary = _create_ready_boundary(port_new, SESSION_A2, SESSION_B)
	runtime._boundary = new_boundary
	runtime._peer_to_session[PEER_A] = SESSION_A2
	check(runtime._send_product_seam_state(PEER_A, PLAYER_A, "MOVEMENT_NETWORK_TICK"), "new session receives unchanged state")
	check(port_new.get_messages_for_peer(PEER_A).size() == 1, "reconnect does not inherit old session cache")
	check(_valid_frame(port_new.get_messages_for_peer(PEER_A)[0]), "reconnect frame valid")
	check(_counter(runtime, "_seam_messages_sent") == 6, "six reliable initial/change/retry/rejoin/reconnect sends")
	new_boundary.stop()
	runtime.free()

	for reason in failures:
		push_error(reason)
	print("NET_SMOOTH1_SEAM_DELIVERY: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _create_ready_boundary(port, a_session: String, b_session: String):
	var boundary = Boundary.new()
	check(_ok(boundary.configure(port, 65536, 64, 1048576)), "boundary configured")
	check(_ok(boundary.start_server({"transport":"LOOPBACK", "name":"netsmooth-seam"})), "listener started")
	check(_ok(port.attach_peer(PEER_A, a_session, ROUTE_A, 1)), "A attached")
	check(_ok(port.attach_peer(PEER_B, b_session, ROUTE_B, 1)), "B attached")
	check(_ok(boundary.poll_events(16)), "peer events polled")
	for peer_id in [PEER_A, PEER_B]:
		for method in ["mark_peer_handshaking", "mark_peer_synchronizing", "mark_peer_ready"]:
			check(_ok(boundary.call(method, peer_id)), "ready transition %s %s" % [peer_id, method])
	return boundary

func _seam(player_id: String, crossed: bool) -> Dictionary:
	return SeamState.create({
		"logical_player_id": player_id,
		"active_authority_id": "authority/secondary" if crossed else "authority/primary",
		"authority_epoch": 2 if crossed else 1,
		"region_id": "region/user1/b" if crossed else "region/user1/a",
		"transfer_state": "ACTIVE",
		"crossings": 1 if crossed else 0,
		"secondary_entries": 1 if crossed else 0,
		"roundtrips": 0,
		"last_transfer_id": "transfer/test/1" if crossed else "",
	})

func _valid_frame(frame: Dictionary) -> bool:
	return _ok(Frame.validate(frame)) and _ok(SeamState.validate(frame.get("payload", {}).get("state", {})))

func _counter(runtime, key: String) -> int:
	var raw = runtime.get(key)
	return int(raw) if raw is int or raw is float else -1

func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))

func check(success: bool, title: String) -> void:
	assertions += 1
	if not success:
		failures.append(title)
