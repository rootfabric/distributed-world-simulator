extends SceneTree

const Support = preload("res://scripts/runtime/networked_gameplay/transports/m2_process_support.gd")

const SCHEMA := "planet_simulator.m2_dedicated_graphical_process_summary.v1"
const POLL_DELAY_MS := 50
const SERVER_READY_TIMEOUT_MS := 45000
const CLIENT_TIMEOUT_MS := 150000
const EXIT_TIMEOUT_MS := 20000
const SERVER_SHUTDOWN_AFTER_MS := 240000

var failures: Array[String] = []
var assertions := 0
var child_pids: Array[int] = []
var xvfb_pid := -1


func _init() -> void:
	var port := _find_available_port()
	_assert(port > 0, "UDP port allocation")
	if port <= 0:
		_finish()
		return
	var root := ProjectSettings.globalize_path(
		"res://artifacts/test-results/m2-graphical-%d" % OS.get_process_id()
	)
	DirAccess.make_dir_recursive_absolute(root)
	var server_report_path := root.path_join("server.json")
	var phase1_report_path := root.path_join("client-phase1.json")
	var phase2_report_path := root.path_join("client-phase2.json")
	var server_log_path := root.path_join("server.log")
	var phase1_log_path := root.path_join("client-phase1.log")
	var phase2_log_path := root.path_join("client-phase2.log")
	for path in [server_report_path, phase1_report_path, phase2_report_path, server_log_path, phase1_log_path, phase2_log_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var server_user := root.path_join("user-server")
	var phase1_user := root.path_join("user-client-phase1")
	var phase2_user := root.path_join("user-client-phase2")
	for path in [server_user, phase1_user, phase2_user]:
		DirAccess.make_dir_recursive_absolute(path)

	var display_name := ""
	if OS.get_name() == "Linux":
		display_name = _start_virtual_display(root)
		_assert(not display_name.is_empty(), "virtual graphical display started")
		if display_name.is_empty():
			_finish()
			return

	var executable := OS.get_executable_path()
	var project_root := ProjectSettings.globalize_path("res://")
	var server_pid := _spawn_process(executable, [
		"--headless", "--quiet", "--path", project_root,
		"--log-file", server_log_path,
		"--",
		"--role=dedicated-server",
		"--world=moon",
		"--node-id=local-dedicated-server",
		"--server-address=127.0.0.1",
		"--server-port=%d" % port,
		"--player-identity=local-astronaut",
		"--m2-result-file=%s" % server_report_path,
		"--shutdown-after-ms=%d" % SERVER_SHUTDOWN_AFTER_MS,
	], server_user, "")
	child_pids.append(server_pid)
	_assert(server_pid > 0, "dedicated server process launch")
	var server_ready := _wait_for_state(server_report_path, ["READY", "FAILED", "STOPPED"], SERVER_READY_TIMEOUT_MS)
	_assert(String(server_ready.get("state", "")) == "READY", "dedicated server world ready: %s" % server_ready)
	_assert(bool(server_ready.get("world_attached", false)), "dedicated server attached canonical world")
	if String(server_ready.get("state", "")) != "READY":
		_write_summary(root, port, server_ready, {}, {})
		_finish()
		return

	var phase1_pid := _spawn_graphical_client(
		executable, project_root, port, "moon", 1, phase1_report_path, "", phase1_log_path, phase1_user, display_name
	)
	child_pids.append(phase1_pid)
	_assert(phase1_pid > 0, "graphical client phase 1 launch")
	var phase1 := _wait_for_state(phase1_report_path, ["COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(bool(phase1.get("passed", false)), "graphical client phase 1: %s" % phase1)
	_wait_for_exit(phase1_pid, EXIT_TIMEOUT_MS)
	var phase1_stopped := phase1_pid > 0 and not OS.is_process_running(phase1_pid)
	_assert(phase1_stopped, "phase 1 graphical process exited")
	if phase1_stopped:
		child_pids.erase(phase1_pid)
	var server_after_phase1 := _wait_for_server_counts(server_report_path, 1, 1, 20000)
	_assert(int(server_after_phase1.get("joins", 0)) == 1, "server registered first join")
	_assert(int(server_after_phase1.get("leaves", 0)) == 1, "server registered first graceful leave")
	_assert(int(server_after_phase1.get("connected_peer_count", -1)) == 0, "first client detached cleanly")
	_assert(String(server_after_phase1.get("state", "")) == "READY", "dedicated listener survived first client")

	var phase2_pid := _spawn_graphical_client(
		executable, project_root, port, "moon", 2, phase2_report_path, phase1_report_path, phase2_log_path, phase2_user, display_name
	)
	child_pids.append(phase2_pid)
	_assert(phase2_pid > 0, "graphical client reconnect process launch")
	var phase2 := _wait_for_state(phase2_report_path, ["COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(bool(phase2.get("passed", false)), "graphical client phase 2: %s" % phase2)
	_wait_for_exit(phase2_pid, EXIT_TIMEOUT_MS)
	var phase2_stopped := phase2_pid > 0 and not OS.is_process_running(phase2_pid)
	_assert(phase2_stopped, "phase 2 graphical process exited")
	if phase2_stopped:
		child_pids.erase(phase2_pid)
	var server_final := _wait_for_server_counts(server_report_path, 2, 2, 20000)

	_validate_phase_reports(phase1, phase2)
	_validate_server_report(server_final, phase2)
	_validate_user_data_isolation(server_final, phase1, phase2)
	_write_summary(root, port, server_final, phase1, phase2)
	_run_playground_scenario(executable, project_root, root, display_name, port)
	_finish()


func _run_playground_scenario(
	executable: String,
	project_root: String,
	root: String,
	display_name: String,
	excluded_port: int
) -> void:
	var port := _find_available_port(excluded_port)
	_assert(port > 0, "playground UDP port allocation")
	if port <= 0:
		return
	var playground_root := root.path_join("playground")
	DirAccess.make_dir_recursive_absolute(playground_root)
	var server_report_path := playground_root.path_join("server.json")
	var client_report_path := playground_root.path_join("client.json")
	var server_log_path := playground_root.path_join("server.log")
	var client_log_path := playground_root.path_join("client.log")
	var server_user := playground_root.path_join("user-server")
	var client_user := playground_root.path_join("user-client")
	for path in [server_user, client_user]:
		DirAccess.make_dir_recursive_absolute(path)
	var server_pid := _spawn_process(executable, [
		"--headless", "--quiet", "--path", project_root,
		"--log-file", server_log_path,
		"--",
		"--role=dedicated-server",
		"--world=playground",
		"--node-id=m2-playground-server",
		"--server-address=127.0.0.1",
		"--server-port=%d" % port,
		"--player-identity=local-astronaut",
		"--m2-result-file=%s" % server_report_path,
		"--shutdown-after-ms=%d" % SERVER_SHUTDOWN_AFTER_MS,
	], server_user, "")
	child_pids.append(server_pid)
	_assert(server_pid > 0, "playground dedicated server launch")
	var server_ready := _wait_for_state(
		server_report_path,
		["READY", "FAILED", "STOPPED"],
		SERVER_READY_TIMEOUT_MS
	)
	_assert(
		String(server_ready.get("state", "")) == "READY",
		"playground dedicated world ready: %s" % server_ready
	)
	if String(server_ready.get("state", "")) != "READY":
		return
	var client_pid := _spawn_graphical_client(
		executable,
		project_root,
		port,
		"playground",
		1,
		client_report_path,
		"",
		client_log_path,
		client_user,
		display_name
	)
	child_pids.append(client_pid)
	_assert(client_pid > 0, "playground graphical client launch")
	var client := _wait_for_state(
		client_report_path,
		["COMPLETE", "FAILED"],
		CLIENT_TIMEOUT_MS
	)
	_assert(bool(client.get("passed", false)), "playground graphical client: %s" % client)
	_wait_for_exit(client_pid, EXIT_TIMEOUT_MS)
	var client_stopped := client_pid > 0 and not OS.is_process_running(client_pid)
	_assert(client_stopped, "playground graphical client exited")
	if client_stopped:
		child_pids.erase(client_pid)
	var server_final := _wait_for_server_counts(server_report_path, 1, 1, 20000)
	var initial_world: Dictionary = client.get("initial_world", {})
	var final_world: Dictionary = client.get("world", {})
	_assert(
		String(initial_world.get("world_id", "")) == "playground",
		"graphical client entered playground immediately"
	)
	_assert(
		_vector_distance(
			initial_world.get("player_position", []),
			[0.0, 1.2, 6.0]
		) <= 0.001,
		"playground authoritative spawn applied"
	)
	_assert(
		String(final_world.get("item_controller_mode", "")) == "replica",
		"playground inventory is replica-driven"
	)
	_assert(
		int(final_world.get("player_sync_count", 0)) >= 1,
		"playground authoritative movement synchronized"
	)
	_assert(
		int(final_world.get("player_rejection_count", -1)) == 0,
		"playground movement accepted"
	)
	_assert(
		int(server_final.get("command_rejections", -1)) == 0,
		"playground server rejected no commands"
	)


func _spawn_graphical_client(
	executable: String,
	project_root: String,
	port: int,
	world_id: String,
	phase: int,
	result_path: String,
	expected_path: String,
	log_path: String,
	user_root: String,
	display_name: String
) -> int:
	var args: Array[String] = [
		"--quiet", "--path", project_root,
		"--rendering-method", "gl_compatibility",
		"--audio-driver", "Dummy",
		"--log-file", log_path,
		"--",
		"--role=game-client",
		"--world=%s" % world_id,
		"--node-id=local-game-client",
		"--server-address=127.0.0.1",
		"--server-port=%d" % port,
		"--player-identity=local-astronaut",
		"--connect-timeout-ms=60000",
		"--command-timeout-ms=10000",
		"--m2-result-file=%s" % result_path,
		"--m2-phase=%d" % phase,
	]
	if not expected_path.is_empty():
		args.append("--m2-expected-state-file=%s" % expected_path)
	return _spawn_process(executable, args, user_root, display_name)


func _spawn_process(executable: String, args: Array[String], user_root: String, display_name: String) -> int:
	var names: Array[String] = ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA", "DISPLAY", "LIBGL_ALWAYS_SOFTWARE"]
	var captured := _capture_environment(names)
	var data_root := user_root.path_join("data")
	var config_root := user_root.path_join("config")
	var cache_root := user_root.path_join("cache")
	for path in [user_root, data_root, config_root, cache_root]:
		DirAccess.make_dir_recursive_absolute(path)
	OS.set_environment("HOME", user_root)
	OS.set_environment("XDG_DATA_HOME", data_root)
	OS.set_environment("XDG_CONFIG_HOME", config_root)
	OS.set_environment("XDG_CACHE_HOME", cache_root)
	OS.set_environment("APPDATA", data_root)
	OS.set_environment("LOCALAPPDATA", data_root)
	if not display_name.is_empty():
		OS.set_environment("DISPLAY", display_name)
		OS.set_environment("LIBGL_ALWAYS_SOFTWARE", "1")
	var pid := OS.create_process(executable, args, false)
	_restore_environment(captured)
	return pid


func _start_virtual_display(root: String) -> String:
	var executable := "/usr/bin/Xvfb"
	if not FileAccess.file_exists(executable):
		failures.append("Xvfb is required for the real graphical M2 process test")
		return ""
	var base := 120 + (OS.get_process_id() % 500)
	for offset in range(20):
		var number := base + offset
		var display_name := ":%d" % number
		var log_path := root.path_join("xvfb-%d.log" % number)
		xvfb_pid = OS.create_process(executable, [
			display_name, "-screen", "0", "1280x720x24", "-nolisten", "tcp", "-noreset"
		], false)
		if xvfb_pid <= 0:
			continue
		OS.delay_msec(500)
		if OS.is_process_running(xvfb_pid):
			child_pids.append(xvfb_pid)
			return display_name
		xvfb_pid = -1
	return ""


func _validate_phase_reports(phase1: Dictionary, phase2: Dictionary) -> void:
	_assert(String(phase1.get("checkpoint", "")) == Support.CHECKPOINT, "phase 1 checkpoint")
	_assert(String(phase2.get("checkpoint", "")) == Support.CHECKPOINT, "phase 2 checkpoint")
	_assert(String(phase1.get("display_server", "")).to_lower() not in ["", "headless", "dummy"], "phase 1 used graphical display")
	_assert(String(phase2.get("display_server", "")).to_lower() not in ["", "headless", "dummy"], "phase 2 used graphical display")
	_assert(String(phase1.get("rendering_method", "")) == "gl_compatibility", "phase 1 rendered through GL compatibility")
	_assert(String(phase2.get("rendering_method", "")) == "gl_compatibility", "phase 2 rendered through GL compatibility")
	var client1: Dictionary = phase1.get("client_runtime", {})
	var client2: Dictionary = phase2.get("client_runtime", {})
	_assert(String(client1.get("player_entity_id", "")) == "player/local-astronaut", "phase 1 stable player identity")
	_assert(String(client2.get("player_entity_id", "")) == "player/local-astronaut", "reconnect preserved player identity")
	_assert(int(client1.get("ownership_epoch", 0)) == 1, "first graphical ownership epoch")
	_assert(int(client2.get("ownership_epoch", 0)) == 2, "reconnect graphical ownership epoch")
	_assert(int(client1.get("direct_authority_references", 1)) == 0, "phase 1 has no authority reference")
	_assert(int(client2.get("direct_authority_references", 1)) == 0, "phase 2 has no authority reference")
	_assert(int(client1.get("direct_domain_references", 1)) == 0, "phase 1 has no domain reference")
	_assert(int(client2.get("direct_domain_references", 1)) == 0, "phase 2 has no domain reference")
	var world1: Dictionary = phase1.get("world", {})
	var world2: Dictionary = phase2.get("world", {})
	_assert(not String(world1.get("active_camera", "")).is_empty(), "phase 1 real LunarPlayer camera")
	_assert(not String(world2.get("active_camera", "")).is_empty(), "phase 2 real LunarPlayer camera")
	_assert(bool(world1.get("network_replica_mode", false)), "phase 1 player is replica-driven")
	_assert(bool(world2.get("network_replica_mode", false)), "phase 2 player is replica-driven")
	_assert(bool(world1.get("presentation_enabled", false)) and bool(world1.get("local_input_enabled", false)), "phase 1 graphical composition")
	_assert(bool(world2.get("presentation_enabled", false)) and bool(world2.get("local_input_enabled", false)), "phase 2 graphical composition")
	_assert(int(world1.get("player_sync_count", 0)) >= 1, "phase 1 authoritative movement synchronized")
	_assert(int(world2.get("player_sync_count", 0)) >= 1, "phase 2 authoritative movement synchronized")
	_assert(int(world1.get("player_rejection_count", -1)) == 0, "phase 1 movement accepted")
	_assert(int(world2.get("player_rejection_count", -1)) == 0, "phase 2 movement accepted")
	_assert(String(world1.get("item_controller_mode", "")) == "replica", "phase 1 inventory reads replica state")
	_assert(String(world2.get("item_controller_mode", "")) == "replica", "phase 2 inventory reads replica state")
	_assert(bool(phase1.get("inventory_result", {}).get("inventory_open", false)), "phase 1 replicated inventory opened")
	_assert(bool(phase2.get("inventory_result", {}).get("inventory_open", false)), "phase 2 replicated inventory opened")
	_assert(int(phase1.get("inventory_result", {}).get("selected_hotbar_index", -1)) == 1, "phase 1 hotbar replicated")
	_assert(int(phase2.get("inventory_result", {}).get("selected_hotbar_index", -1)) == 2, "phase 2 hotbar replicated")
	_assert(String(phase1.get("inventory_result", {}).get("runtime_mode", "")) == "replica", "phase 1 hotbar did not bypass replica")
	_assert(String(phase2.get("inventory_result", {}).get("runtime_mode", "")) == "replica", "phase 2 hotbar did not bypass replica")
	_assert(bool(phase1.get("leave_result", {}).get("success", false)), "phase 1 graceful leave")
	_assert(bool(phase2.get("leave_result", {}).get("success", false)), "phase 2 graceful leave")
	var previous_position = phase1.get("world", {}).get("player_snapshot", {}).get("domain_components", {}).get("player_state", {}).get("spatial_ref", {}).get("position_m", null)
	var restored_position = phase2.get("initial_world", {}).get("player_snapshot", {}).get("domain_components", {}).get("player_state", {}).get("spatial_ref", {}).get("position_m", null)
	_assert(previous_position != null and restored_position != null, "reconnect state positions present")
	if previous_position != null and restored_position != null:
		_assert(_vector_distance(previous_position, restored_position) <= 0.05, "reconnect restored authoritative position")


func _validate_server_report(server: Dictionary, phase2: Dictionary) -> void:
	_assert(String(server.get("state", "")) == "READY", "dedicated server remains ready after reconnect")
	_assert(bool(server.get("world_attached", false)), "dedicated world remains attached")
	_assert(int(server.get("joins", 0)) == 2, "server observed two graphical joins")
	_assert(int(server.get("leaves", 0)) == 2, "server observed two graphical leaves")
	_assert(int(server.get("connected_peer_count", -1)) == 0, "no stale graphical peer")
	_assert(int(server.get("command_rejections", -1)) == 0, "dedicated gameplay had no command rejection")
	_assert(int(server.get("direct_client_authority_references", 1)) == 0, "dedicated report confirms no client authority references")
	var boundary: Dictionary = server.get("boundary", {})
	_assert(String(boundary.get("state", "")) == "LISTENING", "ENet listener survived reconnect")
	_assert(int(boundary.get("outbound_pending_messages", -1)) == 0, "no pending outbound gameplay messages")
	_assert(int(boundary.get("outbound_pending_bytes", -1)) == 0, "no pending outbound gameplay bytes")
	var client_world: Dictionary = phase2.get("world", {})
	var server_player: Dictionary = server.get("player_snapshot", {})
	var server_item: Dictionary = server.get("item_graph_snapshot", {})
	var client_player: Dictionary = client_world.get("player_snapshot", {})
	var client_item: Dictionary = client_world.get("item_snapshot", {})
	_assert(not String(server_player.get("checksum", "")).is_empty(), "server player checksum available")
	_assert(not String(server_item.get("checksum", "")).is_empty(), "server Item Graph checksum available")
	_assert(String(server_player.get("checksum", "")) == String(client_player.get("checksum", "")), "graphical player replica converged to server")
	_assert(String(server_item.get("checksum", "")) == String(client_item.get("checksum", "")), "graphical Item Graph replica converged to server")
	var player: Dictionary = server.get("player", {})
	_assert(String(player.get("player_entity_id", "")) == "player/local-astronaut", "server retained stable player entity")
	_assert(int(player.get("ownership_epoch", 0)) == 2, "server retained reconnect ownership epoch")


func _validate_user_data_isolation(server: Dictionary, phase1: Dictionary, phase2: Dictionary) -> void:
	var server_dir := String(server.get("resolved_user_data_dir", ""))
	var phase1_dir := String(phase1.get("resolved_user_data_dir", ""))
	var phase2_dir := String(phase2.get("resolved_user_data_dir", ""))
	_assert(not server_dir.is_empty(), "server resolved user-data directory")
	_assert(not phase1_dir.is_empty(), "phase 1 resolved user-data directory")
	_assert(not phase2_dir.is_empty(), "phase 2 resolved user-data directory")
	_assert(server_dir != phase1_dir and server_dir != phase2_dir and phase1_dir != phase2_dir, "all M2 processes use isolated user-data directories")


func _wait_for_server_counts(path: String, joins: int, leaves: int, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var latest: Dictionary = {}
	while Time.get_ticks_msec() - started <= timeout_ms:
		latest = _read_json(path)
		if int(latest.get("joins", 0)) >= joins and int(latest.get("leaves", 0)) >= leaves and int(latest.get("connected_peer_count", -1)) == 0:
			return latest
		OS.delay_msec(POLL_DELAY_MS)
	return latest


func _wait_for_state(path: String, states: Array[String], timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var latest: Dictionary = {}
	while Time.get_ticks_msec() - started <= timeout_ms:
		latest = _read_json(path)
		if String(latest.get("state", "")) in states:
			return latest
		OS.delay_msec(POLL_DELAY_MS)
	return latest


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return Dictionary(parsed) if parsed is Dictionary else {}


func _find_available_port(excluded_port: int = -1) -> int:
	var start := 28000 + (OS.get_process_id() % 15000)
	for offset in range(500):
		var port := 20000 + ((start + offset - 20000) % 30000)
		if port == excluded_port:
			continue
		var probe := PacketPeerUDP.new()
		var error := probe.bind(port, "127.0.0.1")
		probe.close()
		if error == OK:
			return port
	return 0


func _vector_distance(left, right) -> float:
	if not left is Array or not right is Array or left.size() != 3 or right.size() != 3:
		return INF
	var a := Vector3(float(left[0]), float(left[1]), float(left[2]))
	var b := Vector3(float(right[0]), float(right[1]), float(right[2]))
	return a.distance_to(b)


func _capture_environment(names: Array[String]) -> Dictionary:
	var result := {}
	for name in names:
		result[name] = {"present": OS.has_environment(name), "value": OS.get_environment(name)}
	return result


func _restore_environment(captured: Dictionary) -> void:
	for name in captured.keys():
		if bool(captured[name].get("present", false)):
			OS.set_environment(String(name), String(captured[name].get("value", "")))
		else:
			OS.unset_environment(String(name))


func _wait_for_exit(pid: int, timeout_ms: int) -> void:
	if pid <= 0:
		return
	var started := Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - started <= timeout_ms:
		OS.delay_msec(POLL_DELAY_MS)


func _write_summary(root: String, port: int, server: Dictionary, phase1: Dictionary, phase2: Dictionary) -> void:
	var path := root.path_join("summary.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"schema": SCHEMA,
		"checkpoint": Support.CHECKPOINT,
		"build_id": Support.BUILD_ID,
		"passed": failures.is_empty(),
		"assertions": assertions,
		"port": port,
		"server": server,
		"phase1": phase1,
		"phase2": phase2,
	}, "  ", true, true) + "\n")
	file.close()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _cleanup() -> void:
	for pid in child_pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	child_pids.clear()


func _finish() -> void:
	_cleanup()
	if failures.is_empty():
		print("M2 dedicated graphical processes: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("M2 dedicated graphical processes: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
