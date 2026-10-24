extends SceneTree

# NET-SMOOTH1 P1 tail-latency falsifier: one 20Hz COMPACT movement-snapshot
# publication to N peers must produce exactly ONE outbound transport flush.
# On the frozen R2.2 head every per-peer send performs its own
# flush_outbound(32, peer_id), so a 2-peer authority frame pays two full
# queue walks + telemetry passes every 50ms (measured p50 1.5ms, p99 3.8ms,
# max 20.3ms per call across the six r31p23r22 P0 runs). Batching the flush
# preserves per-peer ordering (per-peer queues) and keeps both frames in the
# same engine frame. Fail-closed: a failed batched flush must retain the
# dirty snapshot state so the next tick republishes.
const Runtime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")

var assertions := 0
var failures: Array[String] = []

var flush_calls := 0
var flush_fail_next := false

var frame_creates := 0
var sends := 0


class StubBoundary extends RefCounted:
	var test_ref: Object
	func get_peer_snapshot(_peer_id: String) -> Dictionary:
		return {"state": "READY"}
	func create_frame_for_peer(peer_id: String, _channel: String, _schema: String, payload: Dictionary, _mode: String) -> Dictionary:
		test_ref.frame_creates += 1
		return {"success": true, "details": {"frame": {
			"frame_id": "frame/test/%s/%d" % [peer_id, test_ref.frame_creates],
			"session_id": "session/test", "sequence": test_ref.frame_creates,
			"channel": _channel, "delivery_mode": _mode,
			"payload_schema": _schema, "payload": payload,
			"payload_checksum": "test"}}}
	func send_to_peer(_peer_id: String, _frame: Dictionary) -> Dictionary:
		test_ref.sends += 1
		return {"success": true, "details": {"queued": true}}
	func flush_outbound(_max_frames: int, _peer_id: String = "") -> Dictionary:
		test_ref.flush_calls += 1
		if test_ref.flush_fail_next:
			return {"success": false, "error_code": "TEST_FLUSH_FAILED"}
		return {"success": true, "details": {"dispatched": 1}}
	func drain() -> Dictionary:
		return {"success": true, "details": {"replay": false}}
	func stop() -> Dictionary:
		return {"success": true, "details": {"replay": false}}


func _init() -> void:
	call_deferred("run")


func run() -> void:
	test_one_flush_per_publication()
	test_failed_batch_flush_stays_fail_closed()
	check(assertions >= 6, "all expected assertions executed")
	for f in failures:
		push_error(f)
	print("NET_SMOOTH1_P1_FLUSH_BATCHING: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)


func test_one_flush_per_publication() -> void:
	var runtime := _setup()
	if runtime == null:
		return
	flush_calls = 0
	frame_creates = 0
	sends = 0
	runtime.set("_boundary", StubBoundary.new())
	(runtime.get("_boundary") as StubBoundary).test_ref = self
	runtime.set("_peer_to_player", {"peer/test/a": "a", "peer/test/b": "b"})
	runtime.set("_peer_to_session", {"peer/test/a": "session/test", "peer/test/b": "session/test"})
	_arm_snapshot(runtime)
	runtime.call("_maybe_publish_movement_snapshot")
	check(frame_creates == 2, "both peers still receive a compact frame (creates=%d)" % frame_creates)
	check(sends == 2, "both peers still receive a compact frame (sends=%d)" % sends)
	check(flush_calls == 1, "one batched transport flush per publication (flush_calls=%d)" % flush_calls)
	check(not bool(runtime.get("_movement_snapshot_dirty")), "successful publication clears dirty")
	check(int(runtime.get("_movement_snapshot_enqueue_failures")) == 0, "no enqueue failures on clean flush")
	runtime.call("stop")
	runtime.free()


func test_failed_batch_flush_stays_fail_closed() -> void:
	var runtime := _setup()
	if runtime == null:
		return
	flush_calls = 0
	frame_creates = 0
	sends = 0
	flush_fail_next = true
	runtime.set("_boundary", StubBoundary.new())
	(runtime.get("_boundary") as StubBoundary).test_ref = self
	runtime.set("_peer_to_player", {"peer/test/a": "a", "peer/test/b": "b"})
	runtime.set("_peer_to_session", {"peer/test/a": "session/test", "peer/test/b": "session/test"})
	_arm_snapshot(runtime)
	var failures_before := int(runtime.get("_movement_snapshot_enqueue_failures"))
	runtime.call("_maybe_publish_movement_snapshot")
	check(flush_calls == 1, "failed batch still attempts exactly one flush (flush_calls=%d)" % flush_calls)
	check(bool(runtime.get("_movement_snapshot_dirty")), "failed flush retains dirty snapshot for retry")
	check(int(runtime.get("_movement_snapshot_enqueue_failures")) == failures_before + 1,
		"failed flush is accounted as enqueue failure")
	runtime.call("stop")
	runtime.free()


func _arm_snapshot(runtime: Object) -> void:
	runtime.set("_movement_snapshot_dirty", true)
	runtime.set("_movement_snapshot_enqueue_failures", int(runtime.get("_movement_snapshot_enqueue_failures")))
	runtime.set("_last_movement_snapshot_tick", int(runtime.get("_server_tick")) - 64)


func _setup() -> Object:
	var runtime = Runtime.new()
	var path := ProjectSettings.globalize_path("res://artifacts/net-smooth1/p1-flush-batching-%d" % Time.get_ticks_usec())
	var config: Dictionary = {"host": "127.0.0.1", "port": _free_port(), "playable_sandbox": true, "persistence_root": path}
	var result: Dictionary = runtime.setup(config)
	if not ok(result):
		failures.append("runtime setup failed: %s" % String(result.get("error_code", "?")))
		runtime.free()
		return null
	get_root().add_child(runtime)
	runtime.set_process(false)
	return runtime


func _free_port() -> int:
	var socket := PacketPeerUDP.new()
	check(socket.bind(0, "127.0.0.1") == OK, "allocate unique port")
	var port := socket.get_local_port()
	socket.close()
	return port


func ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
