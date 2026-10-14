extends SceneTree

# NET-SMOOTH1 R4.2 R3: actual V0 dedicated runtime + M6 single writer.
# A 1800ms worker-only ITEM delay is adversarial; two players move while the
# canonical mutation is uncommitted. No fake success ACK or production sleeps.
const Runtime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
const Repository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const Compact = preload("res://scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot.gd")
const Full = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")

const SESSION_A := "transport-session/r3/move/a/1"
const SESSION_B := "transport-session/r3/move/b/1"
const PEER_A := "peer/r3/move/a"
const OP := "operation/net-r42-r3/slow/item/a/1"
const DELAY_MS := 1800
var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	OS.set_environment("DWS_NET_SMOOTH_TEST_HOOKS", "1")
	var path := ProjectSettings.globalize_path(
		"res://artifacts/net-smooth1/r42-r3-slow-item-%d" % Time.get_ticks_usec()
	)
	var runtime = Runtime.new()
	get_root().add_child(runtime)
	var configured: Dictionary = runtime.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": path,
		"async_durable_item_canary": true,
	})
	check(_ok(configured), "real M3 R3 canary with durable root")
	if not _ok(configured):
		runtime.free()
		_finish()
		return
	runtime.set_process(false)
	var writer = runtime.get("_movement_checkpoint_writer")
	check(not _ok(writer.configure_test_command_delay_ms(2100)), "fault-inject delay bounded")
	check(_ok(writer.configure_test_command_delay_ms(DELAY_MS)), "slow ITEM writer enabled in worker only")
	var service = runtime.get("_service")
	check(_ok(service.join("a", SESSION_A, "operation/net-r3/join/a")), "player a joined canonical authority")
	check(_ok(service.join("b", SESSION_B, "operation/net-r3/join/b")), "player b joined canonical authority")
	var peers: Dictionary = {PEER_A: "a", "peer/r3/move/b": "b"}
	var sessions: Dictionary = {PEER_A: SESSION_A, "peer/r3/move/b": SESSION_B}
	runtime.set("_peer_to_player", peers)
	runtime.set("_peer_to_session", sessions)
	var before: Dictionary = service.create_snapshot()
	var pre_item_checksum := String(before.get("checksum", ""))
	var generation := int(runtime.get("_checkpoint_generation"))
	var before_item: Dictionary = service.create_canonical_item_graph_snapshot()
	var begin_ms := Time.get_ticks_msec()
	runtime.call("_handle_item_command", PEER_A, SESSION_A, {
		"operation_id": OP, "ownership_epoch": 1,
		"command_type": "inventory.select_hotbar",
		"payload": {"selected_hotbar_index": 0},
	})
	check(not Dictionary(runtime.get("_p1b_item_pending")).is_empty(), "ITEM mutation enters pending")
	check(int(runtime.get("_checkpoint_generation")) == generation, "writer cannot advance generation at submission")
	var proof = runtime.get("_p1b_item_async_owner")
	check(proof.peek_publication(PEER_A, SESSION_A, "a", 1).is_empty(), "precommit ACK not eligible")
	var observed_ticks := 0
	var previous_frame_tick := -1
	var last_position_x := -1.0
	for frame in range(10):
		var tick_start_ms := Time.get_ticks_msec()
		for phase in range(3):
			var tick := int(runtime.get("_server_tick")) + 1
			check(_ok(service.advance_fixed_server_tick(tick)), "fixed tick a/b advanced")
			runtime.set("_server_tick", tick)
			for who in ["a", "b"]:
				var session := SESSION_A if who == "a" else SESSION_B
				var moving: Dictionary = service.simulate_fixed_movement_tick(
					who, session, 1, frame * 3 + phase + 1,
					{"move_x": 0.0, "move_z": 1.0,
					"look_yaw": 0.25, "look_pitch": 0.0,
					"jump_pressed": false, "sprint": false,
					"delta_seconds": 1.0 / 60.0}, 1.0 / 60.0
				)
				check(_ok(moving), "simulated actual movement for "+who)
		runtime.set("_movement_snapshot_dirty", true)
		runtime.call("_maybe_publish_movement_snapshot")
		var projected: Dictionary = runtime.call("_build_p1b_committed_movement_snapshot")
		check(_ok(projected), "proof-safe movement built under slow writer")
		if _ok(projected):
			var full: Dictionary = projected["details"]["snapshot"]
			var compact: Dictionary = Compact.encode(full)
			check(_ok(Full.validate(full)) and _ok(compact), "frozen/full+compact checksum valid")
			if _ok(compact):
				check(_ok(Compact.decode(compact["details"]["snapshot"])), "compact nested checksum roundtrip")
			check(int(full.get("revision", -1)) == int(before.get("revision", -2)), "no precommit revision")
			check(full.get("shared_item", {}) == before.get("shared_item", {}), "no speculative shared item")
			for value in full.get("players", []):
				var player: Dictionary = Dictionary(value)
				var id := String(player.get("logical_player_id", ""))
				var frozen_player: Dictionary = _lookup(before, id)
				check(player.get("inventory") == frozen_player.get("inventory"), "no uncommitted inventory for "+id)
				check(player.get("state_revision") == frozen_player.get("state_revision"), "no speculative player revision for "+id)
			var a: Dictionary = _lookup(full, "a")
			var z := float(Dictionary(a.get("position", {})).get("z", 0.0))
			check(z >= last_position_x, "player a moves monotonically each frame")
			last_position_x = z
			check(int(full.get("server_tick", -1)) - previous_frame_tick == 3 or previous_frame_tick < 0,
				"exact 3 fixed ticks (50ms) per projected frame")
			previous_frame_tick = int(full.get("server_tick", -1))
		check(proof.peek_publication(PEER_A, SESSION_A, "a", 1).is_empty(), "no ACK on slow ITEM frame")
		check(int(runtime.get("_checkpoint_generation")) == generation, "durable generation held while unfenced ITEM")
		observed_ticks += 1
		var elapsed := Time.get_ticks_msec() - tick_start_ms
		if elapsed < 50:
			OS.delay_msec(50 - elapsed)  # standalone test only; never production loop
	check(observed_ticks == 10 and int(runtime.get("_p1b_committed_frames")) >= 10,
		"ten projected frames constructed while ITEM still pending")
	check(Time.get_ticks_msec() - begin_ms < DELAY_MS,
		"measurement window completed while worker injection still in flight")
	check(not Dictionary(runtime.get("_p1b_item_pending")).is_empty(), "ITEM pending during movement")
	check(String(service.create_snapshot().get("checksum", "")) != pre_item_checksum,
		"live authority moved while public committed view stayed durable")
	var finish_by := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < finish_by:
		runtime.call("_p1b_poll_item_async_commit")
		if Dictionary(runtime.get("_p1b_item_pending")).is_empty() or bool(runtime.get("_fatal_persistence_failure")):
			break
		OS.delay_msec(1)
	check(Dictionary(runtime.get("_p1b_item_pending")).is_empty() and not bool(runtime.get("_fatal_persistence_failure")),
		"slow ITEM worker completes exact M6 generation")
	check(int(runtime.get("_checkpoint_generation")) == generation + 1, "exactly one new durable generation")
	check(Dictionary(runtime.get("_p1b_committed_view")).is_empty(), "pre-item view evicted after durable commit")
	var disk = Repository.new()
	check(_ok(disk.configure(path)), "fresh repository configured")
	var loaded: Dictionary = disk.load_committed()
	check(_ok(loaded) and int(loaded.get("details", {}).get("checkpoint", {}).get("generation", -1)) == generation + 1,
		"disk contains committed ITEM generation before success ACK")
	check(String(before_item.get("checksum", "")).length() == 64, "baseline ITEM checksum canonical")
	check(_ok(runtime.stop()), "server final barrier succeeds")
	runtime.free()
	var restart = Runtime.new()
	get_root().add_child(restart)
	var restored: Dictionary = restart.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": path,
		"async_durable_item_canary": true,
	})
	check(_ok(restored), "new server restores durable ITEM")
	if _ok(restored):
		restart.set_process(false)
		check(bool(restart.get("_service").has_durable_replay_operation(OP)),
			"restart replay records committed ITEM operation once")
		check(_ok(restart.stop()), "recovered runtime shuts down")
	restart.free()
	_finish()


func _lookup(snapshot: Dictionary, logical_id: String) -> Dictionary:
	for value in snapshot.get("players", []):
		if value is Dictionary and String(value.get("logical_player_id", "")) == logical_id:
			return value
	return {}


func _port() -> int:
	var socket := PacketPeerUDP.new()
	if socket.bind(0, "127.0.0.1") != OK:
		return 0
	var port := socket.get_local_port()
	socket.close()
	return port


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)


func _finish() -> void:
	for msg in failures:
		push_error(msg)
	print("NET_SMOOTH1_R42_R3_SLOW_ITEM: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
