extends SceneTree
const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const Session = preload("res://scripts/network/transports/v2/network_peer_session.gd")
class Counters:
	extends RefCounted
	var values: Dictionary = {}
	func increment(key: String, amount: int = 1) -> void:
		values[key] = int(values.get(key, 0)) + amount
var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var boundary = Boundary.new()
	var counters = Counters.new()
	boundary.set("_telemetry", counters)
	var session = Session.new()
	check(bool(session.configure("peer/a", "transport-session/smooth/a", "route/a/1", 1, 128, 4096).get("success", false)), "session configured")
	boundary.set("_sessions", {"peer/a": session})
	for spec in [[1,"SNAPSHOT","UNRELIABLE_SEQUENCED"],[2,"CONTROL","RELIABLE_ORDERED"],[3,"SNAPSHOT","UNRELIABLE_SEQUENCED"],[4,"CONTROL","RELIABLE_ORDERED"]]:
		var result: Dictionary = boundary.call("_apply_event", {"event_type":"MESSAGE_RECEIVED", "peer_id":"peer/a", "session_id":"transport-session/smooth/a", "sequence":spec[0], "frame":{"sequence":spec[0], "channel":spec[1], "delivery_mode":spec[2]}})
		check(bool(result.get("success", false)), "all interleaved frames delivered")
	check(int(counters.values.get("transport_unreliable_sequence_id_skips", 0)) == 1, "one raw unreliable ID skip from another stream")
	check(int(counters.values.get("transport_reliable_sequence_id_skips", 0)) == 2, "reliable raw skips separate")
	check(int(counters.values.get("transport_unreliable_sequence_gaps", 0)) == 1, "compatibility alias excludes reliable frames")
	check(not bool(boundary.get_snapshot().get("sequence_gap_is_packet_loss", true)), "explicit NOT packet loss semantics")
	for f in failures: push_error(f)
	print("NET_SMOOTH1_GAPS: %s assertions=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures.append(label)
