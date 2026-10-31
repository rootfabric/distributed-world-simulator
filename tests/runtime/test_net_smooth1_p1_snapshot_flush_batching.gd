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
var partial_fail_next := false
var pending_backpressure_next := false
var sent_types: Array[String] = []

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
		test_ref.sent_types.append(String(Dictionary(_frame.get("payload", {})).get("type", "")))
		return {"success": true, "details": {"queued": true}}
	func flush_outbound(_max_frames: int, _peer_id: String = "") -> Dictionary:
		test_ref.flush_calls += 1
		if test_ref.flush_fail_next:
			return {"success": false, "error_code": "TEST_FLUSH_FAILED"}
		if test_ref.partial_fail_next:
			return {"success": true, "details": {
				"attempted": 2, "dispatched": 1,
				"failed": [{"peer_id": "peer/test/b", "error_code": "ENET_SEND_FAILED"}],
				"blocked_stream_count": 1, "pending_messages": 1, "pending_bytes": 128}}
		if test_ref.pending_backpressure_next:
			return {"success": true, "details": {
				"attempted": 1, "dispatched": 1, "failed": [],
				"blocked_stream_count": 0, "pending_messages": 1, "pending_bytes": 128}}
		return {"success": true, "details": {
			"attempted": test_ref.sends, "dispatched": test_ref.sends,
			"failed": [], "blocked_stream_count": 0,
			"pending_messages": 0, "pending_bytes": 0}}
	func drain() -> Dictionary:
		return {"success": true, "details": {"replay": false}}
	func stop() -> Dictionary:
		return {"success": true, "details": {"replay": false}}


func _init() -> void:
	call_deferred("run")


func run() -> void:
	test_one_flush_per_publication()
	test_failed_batch_flush_stays_fail_closed()
	test_success_with_partial_dispatch_retains_dirty()
	test_backpressure_pending_count_retains_dirty()
	test_changed_and_unchanged_seam_use_one_batch()
	test_changed_seam_partial_does_not_cache_undelivered()
	check(assertions >= 26, "all expected assertions executed")
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
	flush_fail_next = false
	partial_fail_next = false
	pending_backpressure_next = false
	sent_types.clear()
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
	flush_fail_next = false
	partial_fail_next = false
	pending_backpressure_next = false
	sent_types.clear()
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



class SeamService extends RefCounted:
	var previous
	var state := {"region_id": "region/user1/b", "authority_epoch": 2,
		"ownership_epoch": 3}
	func create_snapshot() -> Dictionary:
		return previous.create_snapshot()
	func get_product_seam_state(_logical_player_id: String) -> Dictionary:
		return state.duplicate(true)


func test_success_with_partial_dispatch_retains_dirty() -> void:
	var runtime := _setup()
	if runtime == null:
		return
	_reset_stub()
	partial_fail_next = true
	_attach_boundary(runtime)
	_arm_snapshot(runtime)
	runtime.call("_maybe_publish_movement_snapshot")
	check(flush_calls == 1, "partial transport success needs one batch")
	check(bool(runtime.get("_movement_snapshot_dirty")), "success true with failed[] is dirty")
	check(String(runtime.get("_last_error_code")) == "R31P1_BATCH_DISPATCH_INCOMPLETE",
		"partial transport has explicit fail-closed code")
	runtime.call("stop")
	runtime.free()


func test_backpressure_pending_count_retains_dirty() -> void:
	var runtime := _setup()
	if runtime == null:
		return
	_reset_stub()
	pending_backpressure_next = true
	_attach_boundary(runtime)
	_arm_snapshot(runtime)
	runtime.call("_maybe_publish_movement_snapshot")
	check(flush_calls == 1, "bounded single backpressure batch")
	check(bool(runtime.get("_movement_snapshot_dirty")), "pending retained frames are dirty")
	runtime.call("stop")
	runtime.free()


func test_changed_and_unchanged_seam_use_one_batch() -> void:
	var runtime := _setup()
	if runtime == null:
		return
	_reset_stub()
	var real_service = runtime.get("_service")
	var seam := SeamService.new()
	seam.previous = real_service
	runtime.set("_service", seam)
	_attach_boundary(runtime)
	_arm_snapshot(runtime)
	runtime.call("_maybe_publish_movement_snapshot")
	check(flush_calls == 1, "changed seam authority one shared batch")
	check(sends == 4, "two COMPACT and two reliable seam messages queued")
	check(sent_types.count("COMPACT_GAMEPLAY_SNAPSHOT") == 2,
		"two compact snapshots queued")
	check(sent_types.count("PRODUCT_SEAM_STATE") == 2,
		"two reliable seam changes queued before flush")
	check(not bool(runtime.get("_movement_snapshot_dirty")),
		"changed authority shared batch completes")
	check(Dictionary(runtime.get("_seam_sent_state_by_peer")).size() == 2,
		"reliable seam cache commits only after complete dispatch")
	_arm_snapshot(runtime)
	runtime.call("_maybe_publish_movement_snapshot")
	check(flush_calls == 2, "unchanged seam one batch again")
	check(sends == 6, "unchanged seam must not resend reliable state")
	seam.state["authority_epoch"] = 3
	_arm_snapshot(runtime)
	runtime.call("_maybe_publish_movement_snapshot")
	check(flush_calls == 3, "new authority epoch one batch")
	check(sends == 10, "epoch change sends seam for both peers")
	runtime.set("_service", real_service)
	runtime.call("stop")
	runtime.free()


func test_changed_seam_partial_does_not_cache_undelivered() -> void:
	var runtime := _setup()
	if runtime == null:
		return
	_reset_stub()
	var live_service = runtime.get("_service")
	var seam := SeamService.new()
	seam.previous = live_service
	runtime.set("_service", seam)
	_attach_boundary(runtime)
	partial_fail_next = true
	_arm_snapshot(runtime)
	runtime.call("_maybe_publish_movement_snapshot")
	check(flush_calls == 1, "changed seam partial failure uses single shared flush")
	check(bool(runtime.get("_movement_snapshot_dirty")), "partial reliable seam keeps dirty")
	check(Dictionary(runtime.get("_seam_sent_state_by_peer")).is_empty(),
		"failed native dispatch must NOT poison reliable seam sent cache")
	check(sent_types.count("PRODUCT_SEAM_STATE") == 2,
		"both reliable seam frames were staged before partial failure")
	partial_fail_next = false
	_arm_snapshot(runtime)
	runtime.call("_maybe_publish_movement_snapshot")
	check(flush_calls == 2, "recovery retry still uses one shared flush")
	check(Dictionary(runtime.get("_seam_sent_state_by_peer")).size() == 2,
		"reliable seam cache advances only on subsequent COMPLETE batch")
	check(not bool(runtime.get("_movement_snapshot_dirty")),
		"successful retry publishes latest authoritative movement")
	runtime.set("_service", live_service)
	runtime.call("stop")
	runtime.free()


func _reset_stub() -> void:
	flush_calls = 0
	frame_creates = 0
	sends = 0
	flush_fail_next = false
	partial_fail_next = false
	pending_backpressure_next = false
	sent_types.clear()


func _attach_boundary(runtime: Object) -> void:
	runtime.set("_boundary", StubBoundary.new())
	(runtime.get("_boundary") as StubBoundary).test_ref = self
	runtime.set("_peer_to_player", {"peer/test/a": "a", "peer/test/b": "b"})
	runtime.set("_peer_to_session",
		{"peer/test/a": "session/test", "peer/test/b": "session/test"})


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
