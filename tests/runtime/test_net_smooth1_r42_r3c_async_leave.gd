extends SceneTree

# R3C — real M3/M6 async LEAVE under a worker-only delay. No legacy fsync,
# no early LEAVE_ACK, and the exact replay survives a new server process.
const Runtime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
const Repository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")

const PEER := "peer/r3c/leave/a"
const SESSION := "transport-session/r3c/leave/a/1"
const PLAYER := "a"
const OP := "operation/r3c/leave/a/1"

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	OS.set_environment("DWS_NET_SMOOTH_TEST_HOOKS", "1")
	var root_path := ProjectSettings.globalize_path(
		"res://artifacts/net-smooth1/r3c-async-leave-%d" % Time.get_ticks_usec())
	var server = Runtime.new()
	get_root().add_child(server)
	var configured: Dictionary = server.setup({
		"host": "127.0.0.1", "port": _port(), "playable_sandbox": true,
		"persistence_root": root_path, "r3c_async_admission_canary": true,
	})
	check(_ok(configured), "real M3/R3C persistent runtime configured")
	if not _ok(configured):
		server.free()
		_finish()
		return
	server.set_process(false)
	check(bool(server.get("_r3c_async_admission_enabled")), "R3C explicitly enabled")
	check(bool(server.get("_p1b_item_async_enabled")), "one M6 writer shared with ITEM")
	var writer = server.get("_movement_checkpoint_writer")
	check(_ok(writer.configure_test_command_delay_ms(900)), "worker delay enabled, not main-loop sleep")
	var service = server.get("_service")
	check(_ok(service.join(PLAYER, SESSION, "operation/r3c/leave/join/a")),
		"canonical player joined")
	server.set("_peer_to_player", {PEER: PLAYER})
	server.set("_peer_to_session", {PEER: SESSION})
	server.set("_player_ownership_epochs", {PLAYER: 1})
	var generation := int(server.get("_checkpoint_generation"))
	var legacy_before := int(server.get("_legacy_sync_commit_count"))
	var started := Time.get_ticks_msec()
	server.call("_handle_leave", PEER, SESSION, {"operation_id": OP})
	var handler_ms := Time.get_ticks_msec() - started
	check(handler_ms < 900, "LEAVE handler never waits for delayed worker")
	check(int(server.get("_legacy_sync_commit_count")) == legacy_before,
		"LEAVE never entered legacy synchronous checkpoint")
	var pending: Dictionary = Dictionary(server.get("_p1b_item_pending"))
	check(String(pending.get("kind", "")) == "LEAVE" and
		String(pending.get("operation_id", "")) == OP, "LEAVE mutation enters proof escrow")
	check(int(server.get("_checkpoint_generation")) == generation,
		"commit generation not advanced by submit")
	check(int(server.get("_r3c_async_leave_commits")) == 0, "no early durable LEAVE")
	check(bool(service.has_durable_replay_operation(OP)), "canonical LEAVE recorded in service ledger")
	var proof = server.get("_p1b_item_async_owner")
	check(proof.peek_publication(PEER, SESSION, PLAYER, 1).is_empty(),
		"no LEAVE_ACK becomes visible before durable commit")
	var reader = Repository.new()
	check(_ok(reader.configure(root_path)), "independent repository reader")
	var old: Dictionary = reader.load_committed()
	check(int(old.get("details", {}).get("checkpoint", {}).get("generation", -1)) == generation,
		"disk remains old generation during worker delay")
	var limit := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < limit:
		server.call("_p1b_poll_item_async_commit")
		if Dictionary(server.get("_p1b_item_pending")).is_empty() or bool(server.get("_fatal_persistence_failure")):
			break
		OS.delay_msec(1)  # test only; no production waits
	check(not bool(server.get("_fatal_persistence_failure")), "no fatal M6 failure")
	check(Dictionary(server.get("_p1b_item_pending")).is_empty(), "M6 completion fully consumed")
	check(int(server.get("_checkpoint_generation")) == generation + 1,
		"single exact committed generation")
	check(int(server.get("_r3c_async_leave_commits")) == 1,
		"LEAVE async completion distinguished from ITEM/DISCONNECT")
	check(int(server.get("_p1b_item_commits")) == 0,
		"LEAVE cannot inflate ITEM counts")
	check(int(server.get("_legacy_sync_commit_count")) == legacy_before,
		"no LEGACY_COMMAND_SYNC after LEAVE completion")
	check(String(server.get("_peer_to_session").get(PEER, "")) == "",
		"obsolete peer mapping removed after durability")
	check(proof.peek_publication(PEER, SESSION, PLAYER, 1).is_empty(),
		"no ACK on the non-existent fake network peer")
	check(String(proof.get_report().get("phase", "")) == "IDLE",
		"escrow stale-session quarantine returned to IDLE")
	var saved: Dictionary = reader.load_committed()
	check(_ok(saved) and int(saved.get("details", {}).get("checkpoint", {}).get("generation", -1))
		== generation + 1, "real disk contains committed LEAVE state")
	check(_ok(server.stop()), "explicit final shutdown succeeds")
	server.free()
	var restarted = Runtime.new()
	get_root().add_child(restarted)
	var restored: Dictionary = restarted.setup({
		"host": "127.0.0.1", "port": _port(), "playable_sandbox": true,
		"persistence_root": root_path, "r3c_async_admission_canary": true,
	})
	check(_ok(restored), "fresh M3 runtime recovered from exact root")
	if _ok(restored):
		restarted.set_process(false)
		check(bool(restarted.get("_service").has_durable_replay_operation(OP)),
			"canonical LEAVE dedup survives restart")
		check(_ok(restarted.stop()), "restarted server stops cleanly")
	restarted.free()
	_finish()

func _port() -> int:
	var udp := PacketPeerUDP.new()
	if udp.bind(0, "127.0.0.1") != OK:
		return 0
	var number := udp.get_local_port()
	udp.close()
	return number

func _ok(v: Dictionary) -> bool:
	return bool(v.get("success", false))

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)

func _finish() -> void:
	for reason in failures:
		push_error(reason)
	print("NET_SMOOTH_R3C_ASYNC_LEAVE: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
