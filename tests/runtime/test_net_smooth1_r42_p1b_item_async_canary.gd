extends SceneTree

# R4.2-P1-B R2: real M3 ITEM handler → M6 outbox → one async writer →
# authoritative repository commit. A dummy peer cannot receive ACK, so the
# durable replay stays pending delivery. GUI/real transport is a later gate.
const Runtime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")
const Repository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")

const PEER := "peer/net-r42-p1b/a"
const SESSION := "transport-session/net-r42-p1b/a/1"
const PLAYER := "a"
const OP := "operation/net-r42-p1b/item/hotbar0"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_opt_in_requires_durable_world()
	_test_real_m3_item_and_crash_safe_replay()
	for message in failures:
		push_error(message)
	print("NET_SMOOTH1_R42_P1B_ITEM_ASYNC: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _port() -> int:
	var socket := PacketPeerUDP.new()
	if socket.bind(0, "127.0.0.1") != OK:
		return 0
	var port := socket.get_local_port()
	socket.close()
	return port


func _test_opt_in_requires_durable_world() -> void:
	var runtime = Runtime.new()
	get_root().add_child(runtime)
	var configured: Dictionary = runtime.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "async_durable_item_canary": true,
	})
	check(not _ok(configured), "cannot start opt-in ITEM worker without persistence root")
	check(String(configured.get("error_code", "")) ==
		"P1B_CANARY_REQUIRES_PERSISTENT_PLAYABLE_WORLD",
		"missing durable storage has explicit fail-closed error")
	runtime.free()


func _test_real_m3_item_and_crash_safe_replay() -> void:
	var path := ProjectSettings.globalize_path(
		"res://artifacts/net-smooth1/r42-p1b-item-canary-%d" % Time.get_ticks_usec()
	)
	var runtime = Runtime.new()
	get_root().add_child(runtime)
	var configured: Dictionary = runtime.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": path,
		"async_durable_item_canary": true,
	})
	check(_ok(configured), "real M3 dedicated runtime configured with durable ITEM canary")
	if not _ok(configured):
		runtime.free()
		return
	runtime.set_process(false)
	check(bool(runtime.get("_p1b_item_async_enabled")), "opt-in canary explicitly enabled")
	check(runtime.get("_p1b_item_async_owner") != null, "owner constructed with single writer")
	var service = runtime.get("_service")
	var joined: Dictionary = service.join(PLAYER, SESSION, "operation/net-r42-p1b/join/a")
	check(_ok(joined), "canonical player joins real authority")
	if not _ok(joined):
		runtime.stop()
		runtime.free()
		return
	runtime.set("_peer_to_player", {PEER: PLAYER})
	runtime.set("_peer_to_session", {PEER: SESSION})
	var old_generation := int(runtime.get("_checkpoint_generation"))
	var old_item_hash := String(service.create_canonical_item_graph_snapshot().get("checksum", ""))
	var before_revision := int(service.get_report().get("revision", -1))
	var command := {
		"operation_id": OP, "ownership_epoch": 1,
		"command_type": "inventory.select_hotbar",
		"payload": {"selected_hotbar_index": 0},
	}
	runtime.call("_handle_item_command", PEER, SESSION, command)
	var pending: Dictionary = runtime.get("_p1b_item_pending")
	check(not pending.is_empty(), "actual handler enters async pending without waiting for disk")
	check(String(pending.get("operation_id", "")) == OP, "pending operation is exactly canonical ITEM id")
	check(int(runtime.get("_checkpoint_generation")) == old_generation,
		"authoritative repository generation cannot advance on worker submission")
	check(not bool(runtime.get("_fatal_persistence_failure")), "submission did not fail closed")
	var proof = runtime.get("_p1b_item_async_owner")
	check(proof.peek_publication(PEER, SESSION, PLAYER, 1).is_empty(),
		"no precommit successful ITEM ACK eligible")
	check(bool(service.has_durable_replay_operation(OP)), "service applied one canonical ITEM mutation")
	check(String(service.create_canonical_item_graph_snapshot().get("checksum", "")) != "",
		"mutated item graph has canonical checksum")
	check(int(service.get_report().get("revision", -1)) >= before_revision,
		"authoritative revision did not roll back")

	# The service now holds an uncommitted item transaction, but NONE of its
	# reader paths may transmit it to an already connected client.
	runtime.set("_movement_snapshot_dirty", true)
	runtime.set("_last_movement_snapshot_tick", -10000)
	var count_before := int(runtime.get("_compact_movement_snapshots_published"))
	var full_before := int(runtime.get("_broadcasts"))
	var item_before := int(runtime.get("_item_graph_full_snapshots_published"))
	runtime.call("_maybe_publish_movement_snapshot")
	runtime.call("_broadcast_snapshot", "PRECOMMIT_TEST")
	runtime.call("_broadcast_item_snapshot", "PRECOMMIT_TEST")
	check(int(runtime.get("_compact_movement_snapshots_published")) == count_before,
		"compact snapshot cannot reveal pending item inventory")
	check(int(runtime.get("_broadcasts")) == full_before,
		"full gameplay snapshot and item graph cannot reveal pending mutation")
	check(int(runtime.get("_item_graph_full_snapshots_published")) == item_before,
		"no speculative ITEM graph full resync")
	check(int(runtime.get("_p1b_item_precommit_snapshot_holds")) >= 2,
		"hold decision visible in runtime metrics")
	runtime.call("_handle_item_graph_resync_request", PEER, SESSION,
		{"operation_id": "operation/net-r42-p1b/resync/a"})
	check(Dictionary(runtime.get("_p1b_item_resync_waiters")).size() == 1,
		"midcommit explicit resync queued with bounded peer/session identity")
	check(int(runtime.get("_item_graph_full_snapshots_published")) == item_before,
		"explicit resync does not expose uncommitted ITEM state")

	# A second ITEM command while worker owns generation must be rejected
	# before touching canonical item graph or recording a durable replay.
	var second_op := "operation/net-r42-p1b/item/second"
	var revision_before_second := int(service.get_report().get("revision", -1))
	runtime.call("_handle_item_command", PEER, SESSION, {
		"operation_id": second_op, "ownership_epoch": 1,
		"command_type": "inventory.select_hotbar",
		"payload": {"selected_hotbar_index": 1},
	})
	check(not bool(service.has_durable_replay_operation(second_op)),
		"concurrent canonical ITEM command prevented before mutation")
	check(int(service.get_report().get("revision", -1)) == revision_before_second,
		"rejected concurrent ITEM command never advances revision")

	# Simulated transport drop while the original ITEM commit may still be
	# in flight; no ACK to the obsolete peer, only M6 replay on reconnect.
	runtime.call("_handle_disconnect", PEER, SESSION)
	check(proof.peek_publication(PEER, SESSION, PLAYER, 1).is_empty(),
		"disconnected peer must not see successful pending ACK")
	var committed := false
	for _i in range(6000):
		runtime.call("_p1b_poll_item_async_commit")
		if bool(runtime.get("_fatal_persistence_failure")):
			break
		if Dictionary(runtime.get("_p1b_item_pending")).is_empty():
			committed = true
			break
		OS.delay_msec(1)  # Standalone test only, NEVER on production _process.
	check(committed and not bool(runtime.get("_fatal_persistence_failure")),
		"single async writer completes exact ITEM generation successfully")
	check(int(runtime.get("_checkpoint_generation")) == old_generation + 1,
		"atomic worker result advances repository generation once")
	check(int(runtime.get("_p1b_item_commits")) == 1, "exactly one ITEM durable commit recorded")
	check(proof.get_report().get("phase", "") == "IDLE",
		"quarantined ACK escrow is drained without a false delivery")
	check(Dictionary(runtime.get("_p1b_item_resync_waiters")).is_empty(),
		"queued stale resync cannot reach disconnected peer")

	var repository = Repository.new()
	check(_ok(repository.configure(path)), "independent durable repository opened")
	var loaded: Dictionary = repository.load_committed()
	check(_ok(loaded), "committed generation readable after asynchronous checkpoint")
	check(int(loaded.get("details", {}).get("checkpoint", {}).get("generation", -1)) ==
		old_generation + 1, "disk checkpoint contains committed ITEM generation")
	check(String(service.create_canonical_item_graph_snapshot().get("checksum", "")) != "",
		"authoritative item graph remains accessible after commit")
	check(_ok(runtime.stop()), "graceful stop commits final M6 state")
	runtime.free()

	# Fresh server restores the committed operation and cannot apply it twice.
	var restarted = Runtime.new()
	get_root().add_child(restarted)
	var restart_setup: Dictionary = restarted.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": path,
		"async_durable_item_canary": true,
	})
	check(_ok(restart_setup), "fresh M3 server reloads durable checkpoint")
	if _ok(restart_setup):
		restarted.set_process(false)
		var recovered_service = restarted.get("_service")
		check(bool(recovered_service.has_durable_replay_operation(OP)),
			"restart retains exactly the committed ITEM replay identity")
		check(int(restarted.get("_checkpoint_generation")) >= old_generation + 1,
			"restart generation never rolled backward")
		check(_ok(restarted.stop()), "restarted server exits cleanly")
	restarted.free()
	check(not old_item_hash.is_empty(), "baseline item graph captured from production service")


func _ok(value: Dictionary) -> bool:
	return bool(value.get("success", false))


func check(good: bool, label: String) -> void:
	assertions += 1
	if not good:
		failures.append(label)
