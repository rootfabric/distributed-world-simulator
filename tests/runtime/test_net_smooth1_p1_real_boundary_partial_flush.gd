extends SceneTree

# Real boundary, not mocked flush_result: success=true may carry failed[].
# Check failed peer queue persistence, exactly-once success and reliable
# ordered subsequent packets. No network socket or arbitrary OS pause.
const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const Session = preload("res://scripts/network/transports/v2/network_peer_session.gd")
const Stub = preload("res://tests/runtime/r31p1_partial_transport_stub.gd")

var checks := 0
var errors: Array[String] = []
const PEER_A := "peer/p1/a"
const PEER_B := "peer/p1/b"


func _init() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		errors.append(label)


func good(value: Dictionary) -> bool:
	return bool(value.get("success", false))


func queue(boundary, peer: String, channel: String, mode: String, marker: String) -> String:
	var created: Dictionary = boundary.create_frame_for_peer(peer, channel,
		"planet_simulator.p1.fixture.v1", {"marker": marker}, mode)
	check(good(created), "canonical frame create: "+peer+":"+marker)
	if not good(created):
		return ""
	var frame: Dictionary = Dictionary(created["details"])["frame"]
	var queued: Dictionary = boundary.send_to_peer(peer, frame)
	check(good(queued), "source-native frame queued: "+peer+":"+marker)
	return String(frame.get("frame_id", ""))


func _run() -> void:
	var port := Stub.new()
	var boundary := Boundary.new()
	check(good(boundary.configure(port)), "real boundary configured")
	check(good(boundary.start_server({})), "real boundary listening")
	for peer in [PEER_A, PEER_B]:
		check(good(boundary.call("_register_peer", peer,
			"transport-session/p1/" + peer.trim_prefix("peer/"),
			"route/p1/" + peer.trim_prefix("peer/"), 1,
			Session.STATE_TRANSPORT_CONNECTED)), "peer registered with current session")
		check(good(boundary.mark_peer_handshaking(peer)), "peer handshaking")
		check(good(boundary.mark_peer_synchronizing(peer)), "peer synchronizing")
		check(good(boundary.mark_peer_ready(peer)), "peer READY")

	var a_id := queue(boundary, PEER_A, "SNAPSHOT", "UNRELIABLE_SEQUENCED", "compact/a")
	var b_id := queue(boundary, PEER_B, "SNAPSHOT", "UNRELIABLE_SEQUENCED", "compact/b")
	check(not a_id.is_empty() and not b_id.is_empty(), "unique per-peer frames generated")
	port.fail_peer_once = PEER_B
	var partial: Dictionary = boundary.flush_outbound(32)
	var info: Dictionary = Dictionary(partial.get("details", {}))
	check(good(partial), "outer real boundary success remains true on partial send")
	check(Array(info.get("failed", [])).size() == 1, "real boundary details.failed nonempty")
	check(int(info.get("blocked_stream_count", 0)) == 1, "real boundary blocked peer stream")
	check(int(info.get("pending_messages", 0)) == 1, "failed peer frame remains queued")
	check(int(info.get("dispatched", -1)) == 1, "one peer dispatched, one blocked")
	check(port.accepted.size() == 1 and String(port.accepted[0]["peer"]) == PEER_A,
		"partial delivery sent only A")
	var completed: Dictionary = boundary.flush_outbound(32)
	var rest: Dictionary = Dictionary(completed.get("details", {}))
	check(good(completed) and Array(rest.get("failed", [])).is_empty(),
		"retry flush accepted failed peer without weakening checksum")
	check(int(rest.get("pending_messages", -1)) == 0, "queue drained after retry")
	check(port.accepted.size() == 2, "exactly two unique successful snapshots")
	check(String(port.accepted[1]["frame_id"]) == b_id,
		"queued B frame retained original id across failed attempt")
	check(String(port.accepted[0]["frame_id"]) == a_id,
		"A is not retransmitted after B retry")

	# Reliable RESYNC channel cannot silently coalesce or reorder its own
	# pending source/session/sequence following a delegate failure.
	var id1 := queue(boundary, PEER_B, "RESYNC", "RELIABLE_ORDERED", "seam/epoch2")
	port.fail_peer_once = PEER_B
	var first: Dictionary = boundary.flush_outbound(32)
	check(good(first) and int(first.get("details", {}).get("pending_messages", -1)) == 1,
		"failed reliable seam stays queued")
	var id2 := queue(boundary, PEER_B, "RESYNC", "RELIABLE_ORDERED", "seam/epoch3")
	var last: Dictionary = boundary.flush_outbound(32)
	check(good(last) and int(last.get("details", {}).get("pending_messages", -1)) == 0,
		"reliable seam queue drains after recovered delegate")
	check(port.accepted.size() == 4, "two COMPACT and two ordered seam frames accepted")
	if port.accepted.size() >= 4:
		check(String(port.accepted[2]["frame_id"]) == id1
			and String(port.accepted[3]["frame_id"]) == id2,
			"reliable RESYNC preserves per-stream FIFO without deduplication")
		check(int(port.accepted[2]["sequence"]) < int(port.accepted[3]["sequence"]),
			"session sequence remains monotone across retried RELIABLE frames")
	check(good(boundary.stop()), "real boundary cleanup")
	for e in errors:
		push_error("NET_SMOOTH1_P1_REAL_BOUNDARY_FAIL:"+e)
	print("NET_SMOOTH1_P1_REAL_BOUNDARY %s assertions=%d failures=%d" % [
		"PASS" if errors.is_empty() else "FAIL", checks, errors.size()])
	quit(0 if errors.is_empty() else 1)
