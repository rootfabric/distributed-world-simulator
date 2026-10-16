extends SceneTree

# Real M3/M6 R3C.2: a single delayed ITEM writer commits on disk, then
# publication advances over bounded main-loop stages without opening a
# new canonical command or losing replay/ACK fences.
const Runtime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
const Repository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")

const PEER := "peer/r3c2/item/a"
const SESSION := "transport-session/r3c2/item/a/1"
const PLAYER := "a"
const OP := "operation/r3c2/item/hotbar0"
# A GDScript runtime error can abort _run() without calling quit(). Keep a
# SceneTree-timer guard independent of the test body; CI has an OS-level guard.
const R3C2_TEST_WATCHDOG_SECONDS := 90.0

var assertions := 0
var failures: Array[String] = []
var _finished := false


func _init() -> void:
	# Install the guard BEFORE running _run; a script error leaves the tree
	# alive but the SceneTreeTimer still fires and exits nonzero.
	call_deferred("_arm_watchdog")
	call_deferred("_run")


func _arm_watchdog() -> void:
	var timer := create_timer(R3C2_TEST_WATCHDOG_SECONDS)
	timer.timeout.connect(_watchdog_expired)


func _watchdog_expired() -> void:
	if _finished:
		return
	failures.append("R3C2_TEST_WATCHDOG_EXPIRED_OR_SCRIPT_ERROR")
	_finish()


func _run() -> void:
	OS.set_environment("DWS_NET_SMOOTH_TEST_HOOKS", "1")
	var root_path := ProjectSettings.globalize_path(
		"res://artifacts/net-smooth1/r3c2-phased-item-%d" % Time.get_ticks_usec()
	)
	var server = Runtime.new()
	get_root().add_child(server)
	var configured: Dictionary = server.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": root_path,
		"r3c_async_admission_canary": true,
		"r3c2_phased_publication_canary": true,
	})
	check(_ok(configured), "real M3/M6 runtime configured with explicit R3C2 opt-in")
	if not _ok(configured):
		server.free()
		_finish()
		return
	server.set_process(false)
	check(bool(server.get("_r3c2_phased_item_publication_enabled")), "R3C2 postcommit enabled")
	var writer = server.get("_movement_checkpoint_writer")
	check(_ok(writer.configure_test_command_delay_ms(500)), "worker-only 500ms command delay")
	var service = server.get("_service")
	check(_ok(service.join(PLAYER, SESSION, "operation/r3c2/join/a")), "canonical player joined")
	server.set("_peer_to_player", {PEER: PLAYER})
	server.set("_peer_to_session", {PEER: SESSION})
	server.set("_player_ownership_epochs", {PLAYER: 1})
	var generation := int(server.get("_checkpoint_generation"))
	var before_item_hash := String(service.create_canonical_item_graph_snapshot().get("checksum", ""))
	server.call("_handle_item_command", PEER, SESSION, {
		"operation_id": OP, "ownership_epoch": 1,
		"command_type": "inventory.select_hotbar",
		"payload": {"selected_hotbar_index": 0},
	})
	check(String(server.get("_p1b_item_pending").get("operation_id", "")) == OP,
		"canonical ITEM applied under one M6 pending fence")
	var pending_capture: Dictionary = Dictionary(server.get("_p1b_item_pending"))
	var frozen_item: Dictionary = Dictionary(pending_capture.get("after_item_frozen", {}))
	var frozen_checksum := String(frozen_item.get("checksum", ""))
	check(not frozen_item.is_empty() and not frozen_checksum.is_empty(),
		"exact canonical after-ITEM DTO is frozen before worker submit")
	check(frozen_checksum == String(pending_capture.get("after_item_checksum", "")),
		"frozen ITEM snapshot checksum is bound to durable outbox stage")
	check(server.get("_r3c2_postcommit_pending").is_empty(), "postcommit not opened before commit")
	check(int(server.get("_checkpoint_generation")) == generation,
		"no generation advance before worker completion")
	var proof = server.get("_p1b_item_async_owner")
	check(proof.peek_publication(PEER, SESSION, PLAYER, 1).is_empty(),
		"uncommitted ITEM never eligible for ACK")

	var until_ms := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < until_ms:
		server.call("_p1b_poll_item_async_commit")
		if bool(server.get("_fatal_persistence_failure")) or not server.get("_r3c2_postcommit_pending").is_empty():
			break
		OS.delay_msec(1)  # standalone fixture only, never server._process()
	check(not bool(server.get("_fatal_persistence_failure")), "worker did not fail closed")
	check(int(server.get("_checkpoint_generation")) == generation + 1,
		"atomic ITEM generation committed exactly once")
	check(int(server.get("_r3c2_postcommit_pending").get("stage", -1)) == 0,
		"durable completion only schedules first phase")
	check(String(server.get("_p1b_item_pending").get("operation_id", "")) == OP,
		"visibility fence retained after disk commit until staged publication")
	check(not server.call("_gate_can_accept"), "M6 admission stays closed between stages")
	var repository = Repository.new()
	check(_ok(repository.configure(root_path)), "independent repository reader")
	var disk: Dictionary = repository.load_committed()
	check(_ok(disk) and int(disk.get("details", {}).get("checkpoint", {}).get("generation", -1))
		== generation + 1, "real disk generation exists before any ACK")

	var speculative_op := "operation/r3c2/item/too-early"
	server.call("_handle_item_command", PEER, SESSION, {
		"operation_id": speculative_op, "ownership_epoch": 1,
		"command_type": "inventory.select_hotbar",
		"payload": {"selected_hotbar_index": 1},
	})
	check(not service.has_durable_replay_operation(speculative_op),
		"second canonical ITEM cannot overtake unpublished first ITEM")

	for phase in range(5):
		check(int(server.get("_r3c2_postcommit_pending").get("stage", -1)) == phase,
			"phase %d starts in exact FIFO order" % phase)
		server.call("_r3c2_drain_postcommit_stage")
		if phase == 0:
			var phased_after: Dictionary = Dictionary(
				server.get("_r3c2_postcommit_pending").get("after_item", {})
			)
			check(String(phased_after.get("checksum", "")) == frozen_checksum,
				"phase zero reuses original exact frozen ITEM checksum, not a new export")
		check(not bool(server.get("_fatal_persistence_failure")),
			"phase %d did not break M6 ACK/delta/snapshot fencing" % phase)
		if phase < 4:
			check(not server.call("_gate_can_accept"),
				"phase %d cannot admit new mutation before replication completion" % phase)
	check(server.get("_r3c2_postcommit_pending").is_empty(),
		"all postcommit phases drained")
	check(server.get("_p1b_item_pending").is_empty(), "visibility fence released after delivery stage")
	check(int(server.get("_r3c2_postcommit_phases_completed")) == 5,
		"exact five bounded publication steps")
	check(int(server.get("_p1b_item_commits")) == 1,
		"only one durable ITEM generation counted")
	check(proof.get_report().get("phase", "") == "IDLE",
		"nonexistent peer ACK quarantined and replay preserved")
	check(not bool(server.get("_fatal_persistence_failure")), "final M6 proof stable")
	check(String(service.create_canonical_item_graph_snapshot().get("checksum", "")) != ""
		and not before_item_hash.is_empty(), "canonical Item Graph checksum preserved")
	check(_ok(server.stop()), "graceful stop respects exact committed checkpoint")
	server.free()

	var restart = Runtime.new()
	get_root().add_child(restart)
	var recovered: Dictionary = restart.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": root_path,
		"r3c2_phased_publication_canary": true,
	})
	check(_ok(recovered), "fresh server recovered after staged ITEM publication")
	if _ok(recovered):
		restart.set_process(false)
		check(restart.get("_service").has_durable_replay_operation(OP),
			"canonical operation ID restored without re-commit")
		check(int(restart.get("_checkpoint_generation")) >= generation + 1,
			"recovered generation never regresses")
		check(_ok(restart.stop()), "recovered server stops cleanly")
	restart.free()
	_finish()


func _port() -> int:
	var socket := PacketPeerUDP.new()
	if socket.bind(0, "127.0.0.1") != OK:
		return 0
	var port := socket.get_local_port()
	socket.close()
	return port


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	for problem in failures:
		push_error("[R3C2] " + problem)
	print("NET_SMOOTH_R3C2_PHASED_ITEM %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
