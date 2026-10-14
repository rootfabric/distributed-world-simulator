extends SceneTree

# R3B: persistent M3 canonical DISCONNECT must enter the same M6 durable
# single-writer gate as ITEM, never block the server frame on the old sync path.
# No ACK is sent to a dead transport; reconnect/restart uses canonical replay.
const Runtime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
const Repository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")

const PEER := "peer/r3b/async-disconnect/a"
const SESSION := "transport-session/r3b/async-disconnect/a/1"
const PLAYER := "a"
var OP := "operation/m3/disconnect/%s" % SESSION.sha256_text().left(16)

var checks := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	OS.set_environment("DWS_NET_SMOOTH_TEST_HOOKS", "1")
	var root_path := ProjectSettings.globalize_path(
		"res://artifacts/net-smooth1/r3b-async-disconnect-%d" % Time.get_ticks_usec()
	)
	var runtime = Runtime.new()
	get_root().add_child(runtime)
	var configured: Dictionary = runtime.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true,
		"persistence_root": root_path,
		"async_durable_item_canary": true,
	})
	check(_ok(configured), "real persistent V0 M3 runtime")
	if not _ok(configured):
		runtime.free()
		_finish()
		return
	runtime.set_process(false)
	var writer = runtime.get("_movement_checkpoint_writer")
	check(_ok(writer.configure_test_command_delay_ms(800)),
		"writer delay restricted to worker thread")
	var service = runtime.get("_service")
	check(_ok(service.join(PLAYER, SESSION, "operation/r3b/async-disconnect/join/a")),
		"canonical player joins")
	runtime.set("_peer_to_player", {PEER: PLAYER})
	runtime.set("_peer_to_session", {PEER: SESSION})
	var initial_generation := int(runtime.get("_checkpoint_generation"))
	var started := Time.get_ticks_msec()
	runtime.call("_handle_disconnect", PEER, SESSION)
	check(Time.get_ticks_msec() - started < 800,
		"disconnect handler does not wait for deliberately slow writer")
	var pending: Dictionary = Dictionary(runtime.get("_p1b_item_pending"))
	check(not pending.is_empty() and String(pending.get("kind", "")) == "DISCONNECT",
		"async DISCONNECT owns pending durable generation")
	check(String(pending.get("operation_id", "")) == OP,
		"canonical disconnect op_id reserved exactly once")
	check(int(runtime.get("_checkpoint_generation")) == initial_generation,
		"pending writer cannot advance durable generation before commit")
	var proof = runtime.get("_p1b_item_async_owner")
	check(proof.peek_publication(PEER, SESSION, PLAYER, 1).is_empty(),
		"no successful ACK to stale transport while pending")
	check(int(runtime.get("_r3b_async_disconnect_commits")) == 0,
		"precommit disconnect not counted as durable")
	check(bool(service.has_durable_replay_operation(OP)),
		"canonical disconnect replay recorded in authoritative service")

	var disk = Repository.new()
	check(_ok(disk.configure(root_path)), "independent repository reader configured")
	var disk_before: Dictionary = disk.load_committed()
	check(_ok(disk_before), "pre-disconnect checkpoint readable")
	check(int(disk_before.get("details", {}).get("checkpoint", {}).get("generation", -1)) == initial_generation,
		"old generation remains durable until the writer finishes")
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		runtime.call("_p1b_poll_item_async_commit")
		if bool(runtime.get("_fatal_persistence_failure")) or Dictionary(runtime.get("_p1b_item_pending")).is_empty():
			break
		OS.delay_msec(1)  # standalone test only
	check(not bool(runtime.get("_fatal_persistence_failure")), "commit never enters fatal state")
	check(Dictionary(runtime.get("_p1b_item_pending")).is_empty(), "pending disconnect drained")
	check(int(runtime.get("_checkpoint_generation")) == initial_generation + 1,
		"exact M6 generation advanced once")
	check(int(runtime.get("_r3b_async_disconnect_commits")) == 1,
		"async disconnect receipt counted once")
	check(int(runtime.get("_p1b_item_commits")) == 0,
		"non-ITEM commit does not inflate ITEM commit telemetry")
	check(String(runtime.get("_peer_to_session").get(PEER, "")) == "",
		"old session mapping removed only after durable commit")
	check(proof.peek_publication(PEER, SESSION, PLAYER, 1).is_empty(),
		"old transport ACK remains quarantined after commit")
	check(String(proof.get_report().get("phase", "")) == "IDLE",
		"M6 durable ACK escrow reset after stale session quarantine")
	var durable: Dictionary = disk.load_committed()
	check(_ok(durable), "committed disconnect readable from disk")
	check(int(durable.get("details", {}).get("checkpoint", {}).get("generation", -1))
		== initial_generation + 1, "exact on-disk disconnect generation")
	check(_ok(runtime.stop()), "explicit final shutdown barrier")
	runtime.free()

	var restart = Runtime.new()
	get_root().add_child(restart)
	var restored: Dictionary = restart.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true,
		"persistence_root": root_path,
		"async_durable_item_canary": true,
	})
	check(_ok(restored), "fresh server recovers committed disconnect")
	if _ok(restored):
		restart.set_process(false)
		check(bool(restart.get("_service").has_durable_replay_operation(OP)),
			"canonical disconnect result survives restart")
		check(_ok(restart.stop()), "restart final barrier")
	restart.free()
	_finish()


func _port() -> int:
	var udp := PacketPeerUDP.new()
	if udp.bind(0, "127.0.0.1") != OK:
		return 0
	var port := udp.get_local_port()
	udp.close()
	return port


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func check(good: bool, label: String) -> void:
	checks += 1
	if not good:
		failures.append(label)


func _finish() -> void:
	for failure in failures:
		push_error(failure)
	print("NET_SMOOTH1_R42_R3B_ASYNC_DISCONNECT: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
