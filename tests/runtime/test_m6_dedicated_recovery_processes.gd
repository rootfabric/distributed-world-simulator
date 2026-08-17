extends SceneTree

const Support = preload("res://scripts/runtime/networked_gameplay/m6/m6_process_support.gd")

const READY_TIMEOUT_MS := 45000
const CLIENT_TIMEOUT_MS := 90000
const DISCONNECT_TIMEOUT_MS := 45000
const EXIT_TIMEOUT_MS := 15000
const POLL_MS := 40

var assertions := 0
var failures: Array[String] = []
var child_pids: Array[int] = []


func _init() -> void:
	var port := _find_available_port()
	_assert(port > 0, "M6 UDP port allocated")
	if port <= 0:
		_finish()
		return
	var root_path := ProjectSettings.globalize_path(
		"res://artifacts/test-results/m6-dedicated-recovery-%d" % OS.get_process_id()
	)
	_remove_tree(root_path)
	DirAccess.make_dir_recursive_absolute(root_path)
	var persistence_root := root_path.path_join("persistence")
	var server_result := root_path.path_join("server.json")
	var server_control := root_path.path_join("server-control.json")
	var client_control := root_path.path_join("client-control.json")
	var seed_a_result := root_path.path_join("seed-a.json")
	var seed_b_result := root_path.path_join("seed-b.json")
	var recover_a_result := root_path.path_join("recover-a.json")
	var recover_b_result := root_path.path_join("recover-b.json")
	Support.write(server_control, {"stop": false})
	Support.write(client_control, {"allow_replay": false, "allow_finish": false})

	var executable := OS.get_executable_path()
	var project_root := ProjectSettings.globalize_path("res://")
	var server1_pid := _spawn_server(
		executable, project_root, port, persistence_root, server_result,
		server_control, root_path.path_join("server-1.log"), root_path.path_join("user-server-1")
	)
	child_pids.append(server1_pid)
	_assert(server1_pid > 0, "First dedicated server process launched")
	var server_ready := _wait_state(server_result, ["READY", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(server_ready.get("state", "")) == "READY", "First dedicated server ready: %s" % server_ready)
	if String(server_ready.get("state", "")) != "READY":
		_finish()
		return
	_assert(not bool(server_ready.get("persistence", {}).get("recovered", true)), "First server starts from a new durable checkpoint")
	_assert(int(server_ready.get("persistence", {}).get("checkpoint_generation", 0)) == 1, "Seed checkpoint generation is one")

	var seed_a_pid := _spawn_client(
		executable, project_root, port, "a", "seed", seed_a_result, client_control,
		root_path.path_join("seed-a.log"), root_path.path_join("user-seed-a")
	)
	var seed_b_pid := _spawn_client(
		executable, project_root, port, "b", "seed", seed_b_result, client_control,
		root_path.path_join("seed-b.log"), root_path.path_join("user-seed-b")
	)
	child_pids.append(seed_a_pid)
	child_pids.append(seed_b_pid)
	_assert(seed_a_pid > 0 and seed_b_pid > 0, "Two seed clients launched")
	var seed_a := _wait_state(seed_a_result, ["SEEDED", "FAILED"], CLIENT_TIMEOUT_MS)
	var seed_b := _wait_state(seed_b_result, ["SEEDED", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(String(seed_a.get("state", "")) == "SEEDED", "A seeded durable state: %s" % seed_a)
	_assert(String(seed_b.get("state", "")) == "SEEDED", "B seeded durable state: %s" % seed_b)
	if String(seed_a.get("state", "")) != "SEEDED" or String(seed_b.get("state", "")) != "SEEDED":
		_finish()
		return
	_assert(int(seed_a.get("initial_ownership_epoch", seed_a.get("results", {}).get("initial_ownership_epoch", 0))) == 1, "A seed ownership epoch is one")
	_assert(int(seed_b.get("initial_ownership_epoch", seed_b.get("results", {}).get("initial_ownership_epoch", 0))) == 1, "B seed ownership epoch is one")

	var server_seeded := _wait_server(
		server_result,
		func(report: Dictionary) -> bool:
			return (
				int(report.get("connected_peer_count", 0)) == 2
				and int(report.get("persistence", {}).get("durable_commits", 0)) >= 7
				and int(report.get("persistence", {}).get("checkpoint_generation", 0)) >= 8
			),
		CLIENT_TIMEOUT_MS
	)
	_assert(int(server_seeded.get("connected_peer_count", 0)) == 2, "Both players are active before crash")
	var precrash_generation := int(server_seeded.get("persistence", {}).get("checkpoint_generation", 0))
	var precrash_durable_checksum := String(server_seeded.get("persistence", {}).get("service_recovery", {}).get("durable_state_checksum", ""))
	var precrash_player_snapshot: Dictionary = server_seeded.get("snapshot", {})
	var precrash_item_snapshot: Dictionary = server_seeded.get("item_graph_snapshot", {})
	var precrash_item_checksum := String(precrash_item_snapshot.get("checksum", ""))
	var precrash_item_revision := int(precrash_item_snapshot.get("revision", -1))
	var precrash_service_revision := int(server_seeded.get("service", {}).get("revision", -1))
	var precrash_server_tick := int(server_seeded.get("service", {}).get("server_tick", -1))
	var precrash_authority_epoch := int(server_seeded.get("service", {}).get("authority_epoch", -1))
	_assert(precrash_generation >= 8, "Every acknowledged seed mutation reached durable checkpoint")
	_assert(precrash_durable_checksum.length() == 64, "Pre-crash durable checksum captured")
	_assert(_all_item_ids_unique(precrash_item_snapshot), "Pre-crash Item Graph identities are unique")
	_assert(_item_count(precrash_item_snapshot, "item/shared/ore/1") == 1, "Pre-crash ore identity count is one")
	_assert(_item_count(precrash_item_snapshot, "item/shared/beacon/1") == 1, "Pre-crash beacon identity count is one")
	_assert(_inventory_contains(precrash_item_snapshot, "a", "item/shared/ore/1"), "Pre-crash A inventory owns ore")
	_assert(_inventory_contains(precrash_item_snapshot, "b", "item/shared/beacon/1"), "Pre-crash B inventory owns beacon")
	_assert(_hotbar_item(precrash_item_snapshot, "a", 2) == "item/shared/ore/1", "Pre-crash A hotbar assignment captured")
	_assert(not _player_position(precrash_player_snapshot, "a").is_empty(), "Pre-crash A position captured")
	_assert(not _player_position(precrash_player_snapshot, "b").is_empty(), "Pre-crash B position captured")

	var crash_kill_result := OS.kill(server1_pid)
	_assert(crash_kill_result == OK, "Dedicated server terminated without graceful shutdown")
	if crash_kill_result == OK:
		child_pids.erase(server1_pid)
		OS.delay_msec(100)
	_assert(crash_kill_result == OK, "Crashed server termination acknowledged by OS")
	var disconnected_a := _wait_state(seed_a_result, ["DISCONNECTED_AFTER_CRASH", "FAILED"], DISCONNECT_TIMEOUT_MS)
	var disconnected_b := _wait_state(seed_b_result, ["DISCONNECTED_AFTER_CRASH", "FAILED"], DISCONNECT_TIMEOUT_MS)
	_assert(String(disconnected_a.get("state", "")) == "DISCONNECTED_AFTER_CRASH", "A observed dedicated crash")
	_assert(String(disconnected_b.get("state", "")) == "DISCONNECTED_AFTER_CRASH", "B observed dedicated crash")
	_wait_exit(seed_a_pid, EXIT_TIMEOUT_MS)
	_wait_exit(seed_b_pid, EXIT_TIMEOUT_MS)
	child_pids.erase(seed_a_pid)
	child_pids.erase(seed_b_pid)
	OS.delay_msec(300)

	Support.write(server_control, {"stop": false})
	var server2_pid := _spawn_server(
		executable, project_root, port, persistence_root, server_result,
		server_control, root_path.path_join("server-2.log"), root_path.path_join("user-server-2")
	)
	child_pids.append(server2_pid)
	_assert(server2_pid > 0, "Replacement dedicated server launched")
	var recovered_server := _wait_server(
		server_result,
		func(report: Dictionary) -> bool:
			return String(report.get("state", "")) in ["READY", "FAILED"] and bool(report.get("persistence", {}).get("recovered", false)),
		READY_TIMEOUT_MS
	)
	_assert(String(recovered_server.get("state", "")) == "READY", "Replacement server recovered: %s" % recovered_server)
	if String(recovered_server.get("state", "")) != "READY":
		_finish()
		return
	_assert(bool(recovered_server.get("persistence", {}).get("recovered", false)), "Recovery flag is set")
	_assert(String(recovered_server.get("persistence", {}).get("recovery_source", "")) == "ACTIVE", "Active checkpoint selected after crash")
	_assert(int(recovered_server.get("persistence", {}).get("checkpoint_generation", 0)) == precrash_generation, "Crash did not invent checkpoint generation")
	_assert(String(recovered_server.get("persistence", {}).get("service_recovery", {}).get("durable_state_checksum", "")) == precrash_durable_checksum, "Durable checksum restored byte-stably")
	_assert(String(recovered_server.get("item_graph_snapshot", {}).get("checksum", "")) == precrash_item_checksum, "Canonical Item Graph restored byte-stably")
	_assert(int(recovered_server.get("item_graph_snapshot", {}).get("revision", -2)) == precrash_item_revision, "Canonical Item Graph revision restored")
	_assert(int(recovered_server.get("service", {}).get("revision", -2)) == precrash_service_revision, "Gameplay service revision restored")
	_assert(int(recovered_server.get("service", {}).get("server_tick", -2)) == precrash_server_tick, "Gameplay server tick restored")
	_assert(int(recovered_server.get("service", {}).get("authority_epoch", -2)) == precrash_authority_epoch, "Authority epoch restored")
	_assert(_player_position(recovered_server.get("snapshot", {}), "a") == _player_position(precrash_player_snapshot, "a"), "A position restored")
	_assert(_player_position(recovered_server.get("snapshot", {}), "b") == _player_position(precrash_player_snapshot, "b"), "B position restored")
	_assert(int(recovered_server.get("service", {}).get("player_count", 0)) == 2, "Both player records recovered")
	_assert(int(recovered_server.get("service", {}).get("connected_count", -1)) == 0, "Recovered transport sessions are disconnected")
	_assert(_all_item_ids_unique(recovered_server.get("item_graph_snapshot", {})), "Recovered Item Graph identities remain unique")
	_assert(_item_count(recovered_server.get("item_graph_snapshot", {}), "item/shared/ore/1") == 1, "Recovery did not duplicate ore")
	_assert(_item_count(recovered_server.get("item_graph_snapshot", {}), "item/shared/beacon/1") == 1, "Recovery did not duplicate beacon")
	_assert(_inventory_contains(recovered_server.get("item_graph_snapshot", {}), "a", "item/shared/ore/1"), "Recovered A inventory owns ore")
	_assert(_inventory_contains(recovered_server.get("item_graph_snapshot", {}), "b", "item/shared/beacon/1"), "Recovered B inventory owns beacon")
	_assert(_hotbar_item(recovered_server.get("item_graph_snapshot", {}), "a", 2) == "item/shared/ore/1", "Recovered A hotbar assignment is canonical")
	_assert(int(recovered_server.get("persistence", {}).get("outbox", {}).get("outbox_count", 0)) >= 1, "Committed outbox state recovered")
	_assert(int(recovered_server.get("persistence", {}).get("outbox", {}).get("pending_count", 0)) >= 1, "Pending committed outbox state recovered")

	Support.write(client_control, {"allow_replay": false, "allow_finish": false})
	var recover_a_pid := _spawn_client(
		executable, project_root, port, "a", "recover", recover_a_result, client_control,
		root_path.path_join("recover-a.log"), root_path.path_join("user-recover-a")
	)
	var recover_b_pid := _spawn_client(
		executable, project_root, port, "b", "recover", recover_b_result, client_control,
		root_path.path_join("recover-b.log"), root_path.path_join("user-recover-b")
	)
	child_pids.append(recover_a_pid)
	child_pids.append(recover_b_pid)
	var recover_a_ready := _wait_state(recover_a_result, ["RECOVER_READY", "FAILED"], CLIENT_TIMEOUT_MS)
	var recover_b_ready := _wait_state(recover_b_result, ["RECOVER_READY", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(String(recover_a_ready.get("state", "")) == "RECOVER_READY", "A reconnected to recovered server")
	_assert(String(recover_b_ready.get("state", "")) == "RECOVER_READY", "B reconnected to recovered server")
	_assert(int(recover_a_ready.get("results", {}).get("initial_ownership_epoch", 0)) == 2, "A ownership epoch advanced from one to two")
	_assert(int(recover_b_ready.get("results", {}).get("initial_ownership_epoch", 0)) == 2, "B ownership epoch advanced from one to two")
	_assert(String(recover_a_ready.get("results", {}).get("player_entity_id", "")) == "player/a", "A stable player entity recovered")
	_assert(String(recover_b_ready.get("results", {}).get("player_entity_id", "")) == "player/b", "B stable player entity recovered")
	var before_replay := _wait_server(
		server_result,
		func(report: Dictionary) -> bool:
			return int(report.get("connected_peer_count", 0)) == 2 and int(report.get("joins", 0)) == 2,
		CLIENT_TIMEOUT_MS
	)
	var replay_generation := int(before_replay.get("persistence", {}).get("checkpoint_generation", -1))
	var replay_commits := int(before_replay.get("persistence", {}).get("durable_commits", -1))
	var replay_outbox_count := int(before_replay.get("persistence", {}).get("outbox", {}).get("outbox_count", -1))
	var replay_item_checksum := String(before_replay.get("item_graph_snapshot", {}).get("checksum", ""))
	var replay_item_revision := int(before_replay.get("item_graph_snapshot", {}).get("revision", -1))
	var replay_service_operation_count := int(before_replay.get("service", {}).get("operation_count", -1))
	Support.write(client_control, {"allow_replay": true, "allow_finish": false})
	var replay_a := _wait_state(recover_a_result, ["REPLAY_COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	var replay_b := _wait_state(recover_b_result, ["REPLAY_BARRIER", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(String(replay_a.get("state", "")) == "REPLAY_COMPLETE", "A replayed pre-crash committed operation")
	_assert(bool(replay_a.get("results", {}).get("replay_marked", false)), "A received explicit committed replay marker")
	_assert(String(replay_b.get("state", "")) == "REPLAY_BARRIER", "B held deterministic replay barrier")
	var after_replay := _wait_server(
		server_result,
		func(report: Dictionary) -> bool:
			return int(report.get("messages_received", 0)) > int(before_replay.get("messages_received", 0)),
		10000
	)
	_assert(int(after_replay.get("persistence", {}).get("checkpoint_generation", -2)) == replay_generation, "Committed replay created no second checkpoint")
	_assert(int(after_replay.get("persistence", {}).get("durable_commits", -2)) == replay_commits, "Committed replay created no second durable commit")
	_assert(int(after_replay.get("persistence", {}).get("outbox", {}).get("outbox_count", -2)) == replay_outbox_count, "Committed replay created no duplicate outbox record")
	_assert(String(after_replay.get("item_graph_snapshot", {}).get("checksum", "")) == replay_item_checksum, "Committed replay did not mutate Item Graph checksum")
	_assert(int(after_replay.get("item_graph_snapshot", {}).get("revision", -2)) == replay_item_revision, "Committed replay did not advance Item Graph revision")
	_assert(int(after_replay.get("service", {}).get("operation_count", -2)) == replay_service_operation_count, "Committed replay created no second gameplay operation")
	_assert(String(replay_a.get("results", {}).get("replay_before_checksum", "")) == String(replay_a.get("results", {}).get("replay_after_checksum", "")), "Client observed no Item Graph mutation during replay")
	_assert(int(replay_a.get("results", {}).get("replay_before_revision", -1)) == int(replay_a.get("results", {}).get("replay_after_revision", -2)), "Client observed stable Item Graph revision during replay")

	Support.write(client_control, {"allow_replay": true, "allow_finish": true})
	var recover_a_done := _wait_state(recover_a_result, ["COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	var recover_b_done := _wait_state(recover_b_result, ["COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(bool(recover_a_done.get("passed", false)), "A continued gameplay after recovery: %s" % recover_a_done)
	_assert(bool(recover_b_done.get("passed", false)), "B continued gameplay after recovery: %s" % recover_b_done)
	_assert(String(recover_a_done.get("client_runtime", {}).get("last_error_code", "")) != "MULTIPLAYER_DELTA_BASE_MISMATCH", "A did not retain a transient delta-base mismatch")
	_assert(String(recover_b_done.get("client_runtime", {}).get("last_error_code", "")) != "MULTIPLAYER_DELTA_BASE_MISMATCH", "B did not retain a transient delta-base mismatch")
	_assert(not bool(recover_a_done.get("client_runtime", {}).get("pending_replica_resync", true)), "A completed any pending snapshot resync")
	_assert(not bool(recover_b_done.get("client_runtime", {}).get("pending_replica_resync", true)), "B completed any pending snapshot resync")
	_wait_exit(recover_a_pid, EXIT_TIMEOUT_MS)
	_wait_exit(recover_b_pid, EXIT_TIMEOUT_MS)
	child_pids.erase(recover_a_pid)
	child_pids.erase(recover_b_pid)
	var server_final := _wait_server(
		server_result,
		func(report: Dictionary) -> bool:
			return int(report.get("connected_peer_count", -1)) == 0 and int(report.get("leaves", 0)) >= 2,
		CLIENT_TIMEOUT_MS
	)
	_assert(String(server_final.get("item_graph_snapshot", {}).get("checksum", "")) == precrash_item_checksum, "Continuation movement did not alter recovered Item Graph")
	_assert(String(recover_a_done.get("results", {}).get("final_item_checksum", "")) == precrash_item_checksum, "A converged to recovered Item Graph checksum")
	_assert(String(recover_b_done.get("results", {}).get("final_item_checksum", "")) == precrash_item_checksum, "B converged to recovered Item Graph checksum")
	_assert(_all_item_ids_unique(server_final.get("item_graph_snapshot", {})), "Final Item Graph identities remain unique")
	_assert(int(server_final.get("leaves", -1)) == 2, "Exactly two graceful recovery leaves committed")
	_assert(int(server_final.get("persistence", {}).get("failures", 0)) == 0, "No persistence failure occurred")
	_assert(not bool(server_final.get("persistence", {}).get("fatal_failure", true)), "Dedicated server remained out of fail-stop state")

	Support.write(server_control, {"stop": true})
	var stopped_server := _wait_state(server_result, ["STOPPED", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(stopped_server.get("state", "")) == "STOPPED", "Recovered dedicated server stopped cleanly")
	_wait_exit(server2_pid, EXIT_TIMEOUT_MS)
	_assert(not OS.is_process_running(server2_pid), "Recovered dedicated process exited")
	child_pids.erase(server2_pid)
	for log_name in ["server-1.log", "server-2.log", "seed-a.log", "seed-b.log", "recover-a.log", "recover-b.log"]:
		_assert_clean_log(root_path.path_join(log_name), log_name)
	_finish()


func _spawn_server(executable: String, project_root: String, port: int, persistence_root: String, result_file: String, control_file: String, log_file: String, user_root: String) -> int:
	return _spawn(executable, [
		"--headless", "--quiet", "--path", project_root, "--log-file", log_file,
		"--script", "res://tools/network/m6_dedicated_server_worker.gd", "--",
		"--port=%d" % port,
		"--persistence-root=%s" % persistence_root,
		"--result-file=%s" % result_file,
		"--control-file=%s" % control_file,
	], user_root)


func _spawn_client(executable: String, project_root: String, port: int, client_id: String, phase: String, result_file: String, control_file: String, log_file: String, user_root: String) -> int:
	return _spawn(executable, [
		"--headless", "--quiet", "--path", project_root, "--log-file", log_file,
		"--script", "res://tools/network/m6_recovery_client_worker.gd", "--",
		"--port=%d" % port,
		"--client-id=%s" % client_id,
		"--phase=%s" % phase,
		"--result-file=%s" % result_file,
		"--control-file=%s" % control_file,
	], user_root)


func _spawn(executable: String, arguments: Array[String], user_root: String) -> int:
	var environment_names: Array[String] = [
		"HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"
	]
	var captured: Dictionary = {}
	for name in environment_names:
		captured[name] = OS.get_environment(name)
	var data_path := user_root.path_join("data")
	var config_path := user_root.path_join("config")
	var cache_path := user_root.path_join("cache")
	for path in [user_root, data_path, config_path, cache_path]:
		DirAccess.make_dir_recursive_absolute(path)
	OS.set_environment("HOME", user_root)
	OS.set_environment("XDG_DATA_HOME", data_path)
	OS.set_environment("XDG_CONFIG_HOME", config_path)
	OS.set_environment("XDG_CACHE_HOME", cache_path)
	OS.set_environment("APPDATA", data_path)
	OS.set_environment("LOCALAPPDATA", data_path)
	var pid := OS.create_process(executable, arguments, false)
	for name in environment_names:
		OS.set_environment(name, String(captured[name]))
	return pid


func _wait_state(path: String, states: Array[String], timeout_ms: int) -> Dictionary:
	return _wait_server(
		path,
		func(report: Dictionary) -> bool:
			return String(report.get("state", "")) in states,
		timeout_ms
	)


func _wait_server(path: String, predicate: Callable, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var last: Dictionary = {}
	while Time.get_ticks_msec() - started <= timeout_ms:
		last = Support.read(path)
		if predicate.call(last):
			return last
		OS.delay_msec(POLL_MS)
	return last


func _wait_exit(pid: int, timeout_ms: int) -> void:
	var started := Time.get_ticks_msec()
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() - started <= timeout_ms:
		OS.delay_msec(POLL_MS)


func _find_available_port() -> int:
	for port in range(47000 + (OS.get_process_id() % 400), 49000):
		var peer := PacketPeerUDP.new()
		if peer.bind(port, "127.0.0.1") == OK:
			peer.close()
			return port
	return 0


func _player_position(snapshot: Dictionary, logical_player_id: String) -> Dictionary:
	for player_value in snapshot.get("players", []):
		if player_value is Dictionary and String(player_value.get("logical_player_id", "")) == logical_player_id:
			return Dictionary(player_value.get("position", {})).duplicate(true)
	return {}


func _inventory_contains(snapshot: Dictionary, logical_player_id: String, item_id: String) -> bool:
	var inventory: Dictionary = Dictionary(snapshot.get("inventories", {})).get(logical_player_id, {})
	return item_id in Array(inventory.get("inventory", []))


func _hotbar_item(snapshot: Dictionary, logical_player_id: String, slot_index: int) -> String:
	var inventory: Dictionary = Dictionary(snapshot.get("inventories", {})).get(logical_player_id, {})
	var hotbar: Array = inventory.get("hotbar", [])
	return String(hotbar[slot_index]) if slot_index >= 0 and slot_index < hotbar.size() else ""


func _item_count(snapshot: Dictionary, item_id: String) -> int:
	var count := 0
	for item_value in snapshot.get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			count += 1
	return count


func _all_item_ids_unique(snapshot: Dictionary) -> bool:
	var seen: Dictionary = {}
	for item_value in snapshot.get("items", []):
		if not item_value is Dictionary:
			return false
		var item_id := String(item_value.get("item_id", ""))
		if item_id.is_empty() or seen.has(item_id):
			return false
		seen[item_id] = true
	return true


func _assert_clean_log(path: String, label: String) -> void:
	var text := FileAccess.get_file_as_string(path).to_lower() if FileAccess.file_exists(path) else ""
	_assert(not text.contains("objectdb instances leaked"), "%s has no ObjectDB leak" % label)
	_assert(not text.contains("resources still in use"), "%s has no resource leak" % label)
	_assert(not text.contains("failed to bind runtime bridge"), "%s has no MCP port collision" % label)
	_assert(not text.contains("parse error"), "%s has no parse error" % label)
	_assert(not text.contains("script error"), "%s has no script error" % label)
	_assert(not text.contains("compile error"), "%s has no compile error" % label)
	_assert(not text.contains("operation_replay_conflict"), "%s has no replay conflict" % label)
	_assert(not text.contains("join_rejected"), "%s has no reconnect rejection" % label)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file_name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in directory.get_directories():
		_remove_tree(path.path_join(directory_name))
	DirAccess.remove_absolute(path)


func _finish() -> void:
	for pid in child_pids.duplicate():
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	print("M6 dedicated recovery processes: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
