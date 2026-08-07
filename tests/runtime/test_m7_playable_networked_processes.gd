extends SceneTree

const POLL_MS := 50
var failures: Array[String] = []
var assertions := 0
var pids: Array[int] = []
var xvfb_pid := -1
var client_network_profile := "LOCAL"


func _init() -> void:
	client_network_profile = OS.get_environment("NX4_TEST_CLIENT_NETWORK_PROFILE").strip_edges().to_upper()
	if client_network_profile.is_empty():
		client_network_profile = "LOCAL"
	var port := _find_port()
	_assert(port > 0, "M7 port allocated")
	if port <= 0:
		_finish()
		return
	var out := ProjectSettings.globalize_path("res://artifacts/test-results/m7-playable-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	var server_file := out.path_join("server.json")
	var a_file := out.path_join("a.json")
	var b_file := out.path_join("b.json")
	var display := ""
	if OS.get_name() == "Linux":
		display = _start_xvfb()
		_assert(not display.is_empty(), "M7 Xvfb graphical display")
	var exe := OS.get_executable_path()
	var root_path := ProjectSettings.globalize_path("res://")
	var server := _spawn(exe, [
		"--headless", "--quiet", "--path", root_path,
		"--log-file", out.path_join("server.log"), "--",
		"--role=dedicated-server", "--network-playground", "--world=playground",
		"--node-id=m7-playable-server", "--server-address=127.0.0.1",
		"--server-port=%d" % port, "--m7-result-file=%s" % server_file,
		"--shutdown-after-ms=180000",
	], out.path_join("user-server"), "")
	pids.append(server)
	_assert(server > 0, "M7 dedicated server launched")
	var ready := _wait_state(server_file, ["READY", "FAILED"], 30000)
	_assert(String(ready.get("state", "")) == "READY", "M7 dedicated server ready")
	if String(ready.get("state", "")) != "READY":
		_finish()
		return
	var a := _spawn_worker(exe, root_path, port, "a", 1, a_file, b_file, server_file, out.path_join("a.log"), out.path_join("user-a"), display)
	pids.append(a)
	_assert(a > 0, "M7 graphical client A launched")
	var a_done := _wait_state(a_file, ["A_DONE", "FAILED"], 90000)
	_assert(String(a_done.get("state", "")) == "A_DONE", "M7 client A completed 3D item flow")
	if String(a_done.get("state", "")) != "A_DONE":
		_finish()
		return
	var b := _spawn_worker(exe, root_path, port, "b", 2, b_file, a_file, server_file, out.path_join("b.log"), out.path_join("user-b"), display)
	pids.append(b)
	_assert(b > 0, "M7 graphical client B launched")
	var ar := _wait_state(a_file, ["COMPLETE", "FAILED"], 120000)
	var br := _wait_state(b_file, ["COMPLETE", "FAILED"], 120000)
	_assert(bool(ar.get("passed", false)), "M7 client A complete: %s" % ar)
	_assert(bool(br.get("passed", false)), "M7 client B complete: %s" % br)
	_wait_exit(a, 10000)
	_wait_exit(b, 10000)
	var final_server := _read(server_file)
	_assert(String(final_server.get("checkpoint", "")) == "v16.14.0-network-nx4-client-prediction-reconciliation", "M7 server reports NX4 runtime checkpoint")
	_assert(String(ar.get("runtime_report", {}).get("checkpoint", "")) == "v16.14.0-network-nx4-client-prediction-reconciliation", "M7 client A reports NX4 runtime checkpoint")
	_assert(String(br.get("runtime_report", {}).get("checkpoint", "")) == "v16.14.0-network-nx4-client-prediction-reconciliation", "M7 client B reports NX4 runtime checkpoint")
	_assert(String(final_server.get("gameplay_checkpoint", "")) == "v16.10.6.1-testing-m7-playable-networked-playground", "M7 server preserves gameplay checkpoint")
	_assert(String(ar.get("runtime_report", {}).get("gameplay_checkpoint", "")) == "v16.10.6.1-testing-m7-playable-networked-playground", "M7 client A preserves gameplay checkpoint")
	_assert(String(br.get("runtime_report", {}).get("gameplay_checkpoint", "")) == "v16.10.6.1-testing-m7-playable-networked-playground", "M7 client B preserves gameplay checkpoint")
	_assert(String(ar.get("display_server", "")).to_lower() not in ["", "headless", "dummy"], "M7 A is graphical")
	_assert(String(br.get("display_server", "")).to_lower() not in ["", "headless", "dummy"], "M7 B is graphical")
	_assert(bool(ar.get("world_report", {}).get("seven_days_inventory_active", false)), "M7 A uses Seven Days UI")
	_assert(bool(br.get("world_report", {}).get("seven_days_inventory_active", false)), "M7 B uses Seven Days UI")
	_assert(bool(ar.get("world_report", {}).get("network_prediction_mode", false)), "M7 A uses client-side prediction")
	_assert(bool(br.get("world_report", {}).get("network_prediction_mode", false)), "M7 B uses client-side prediction")
	_assert(String(ar.get("world_report", {}).get("m7_interpolation_mode", "")) == "CLIENT_PREDICTION_RECONCILIATION", "M7 A uses prediction/reconciliation presentation")
	_assert(String(br.get("world_report", {}).get("m7_interpolation_mode", "")) == "CLIENT_PREDICTION_RECONCILIATION", "M7 B uses prediction/reconciliation presentation")
	_assert(int(ar.get("runtime_report", {}).get("client_prediction", {}).get("runtime", {}).get("ticks_predicted", 0)) > 0, "M7 A predicts local movement ticks")
	_assert(int(br.get("runtime_report", {}).get("client_prediction", {}).get("runtime", {}).get("ticks_predicted", 0)) > 0, "M7 B predicts local movement ticks")
	_assert(int(ar.get("runtime_report", {}).get("client_prediction", {}).get("reconcile_failures", -1)) == 0, "M7 A has no prediction reconcile failures")
	_assert(int(br.get("runtime_report", {}).get("client_prediction", {}).get("reconcile_failures", -1)) == 0, "M7 B has no prediction reconcile failures")
	_assert(int(ar.get("runtime_report", {}).get("client_prediction", {}).get("runtime", {}).get("history_size", 999)) <= 256, "M7 A prediction history is bounded")
	_assert(int(br.get("runtime_report", {}).get("client_prediction", {}).get("runtime", {}).get("history_size", 999)) <= 256, "M7 B prediction history is bounded")
	_assert(String(ar.get("runtime_report", {}).get("network_conditions", {}).get("profile", {}).get("profile_id", "")) == client_network_profile, "M7 A uses requested network profile")
	_assert(String(br.get("runtime_report", {}).get("network_conditions", {}).get("profile", {}).get("profile_id", "")) == client_network_profile, "M7 B uses requested network profile")
	if client_network_profile != "LOCAL":
		_assert(String(ar.get("runtime_report", {}).get("last_error_code", "")) != "MULTIPLAYER_SAME_REVISION_MUTATION", "M7 A accepts clock-only conditioned snapshots")
		_assert(String(br.get("runtime_report", {}).get("last_error_code", "")) != "MULTIPLAYER_SAME_REVISION_MUTATION", "M7 B accepts clock-only conditioned snapshots")
	_assert(int(ar.get("runtime_report", {}).get("pending_blocking_command_count", -1)) == 0 and int(br.get("runtime_report", {}).get("pending_blocking_command_count", -1)) == 0, "M7 clients leave no pending blocking commands")
	_assert(int(ar.get("runtime_report", {}).get("buffered_command_result_count", -1)) == 0 and int(br.get("runtime_report", {}).get("buffered_command_result_count", -1)) == 0, "M7 clients do not accumulate movement command results")
	var realtime: Dictionary = Dictionary(final_server.get("realtime_traffic", {}))
	var applied_inputs: int = int(realtime.get("movement_inputs_applied", 0))
	_assert(int(realtime.get("movement_batches_received", 0)) > 0, "NX2 server receives movement input batches")
	_assert(applied_inputs > 0, "NX2 server applies batched movement inputs")
	_assert(int(realtime.get("movement_results_suppressed", -1)) == applied_inputs, "NX2 server suppresses every successful movement result")
	_assert(int(realtime.get("movement_deltas_suppressed", -1)) == applied_inputs, "NX2 server suppresses every per-input movement delta")
	_assert(int(realtime.get("movement_full_snapshots_suppressed", -1)) == applied_inputs, "NX2 server suppresses every per-input full snapshot")
	var fixed_tick: Dictionary = Dictionary(final_server.get("fixed_tick_simulation", {}))
	var fixed_ticks: int = int(fixed_tick.get("ticks_simulated", 0))
	var movement_snapshots: int = int(realtime.get("movement_snapshots_published", 0))
	_assert(movement_snapshots > 0 and movement_snapshots <= int(ceil(float(fixed_ticks) / 3.0)) + 2, "NX3 server publishes at most one movement snapshot per three fixed ticks")
	_assert(int(fixed_tick.get("tick_rate_hz", 0)) == 60 and int(fixed_tick.get("failures", -1)) == 0, "NX3 server uses healthy 60 Hz authoritative simulation")
	var channels: Dictionary = Dictionary(final_server.get("network_telemetry", {}).get("channels", {}))
	_assert(int(channels.get("input", {}).get("packets_received", 0)) > 0 and int(channels.get("snapshot", {}).get("packets_sent", 0)) > 0, "NX2 realtime input and snapshot channels carry traffic")
	_assert(int(channels.get("item", {}).get("packets_received", 0)) > 0 and int(channels.get("resync", {}).get("packets_sent", 0)) > 0, "NX2 item and resync channels remain independent under movement")
	_assert(int(ar.get("world_report", {}).get("m7_item_bridge", {}).get("accepted", 0)) >= 7, "M7 A network item actions accepted")
	_assert(int(br.get("world_report", {}).get("m7_item_bridge", {}).get("accepted", 0)) >= 2, "M7 B network item actions accepted")
	_assert(String(ar.get("item_graph_checksum", "")) == String(br.get("item_graph_checksum", "")), "M7 clients Item Graph converge")
	_assert(String(final_server.get("item_graph_snapshot", {}).get("checksum", "")) == String(ar.get("item_graph_checksum", "")), "M7 server and clients Item Graph converge")
	var a_player_convergence := String(ar.get("details", {}).get("convergence_player_checksum", ""))
	var b_player_convergence := String(br.get("details", {}).get("convergence_player_checksum", ""))
	var a_server_convergence := String(ar.get("details", {}).get("convergence_server_player_checksum", ""))
	var b_server_convergence := String(br.get("details", {}).get("convergence_server_player_checksum", ""))
	_assert(not a_player_convergence.is_empty(), "M7 player convergence checksum captured")
	_assert(a_player_convergence == b_player_convergence, "M7 player replicas converge while both clients are connected")
	_assert(a_player_convergence == a_server_convergence and a_server_convergence == b_server_convergence, "M7 server and clients player replicas converge before disconnect")
	_assert_clean(out.path_join("a.log"), "M7 A")
	_assert_clean(out.path_join("b.log"), "M7 B")
	_assert_clean(out.path_join("server.log"), "M7 server")
	_finish()


func _spawn_worker(exe: String, root_path: String, port: int, id: String, phase: int, result: String, peer: String, server_file: String, log: String, user: String, display: String) -> int:
	return _spawn(exe, [
		"--quiet", "--path", root_path, "--rendering-method", "gl_compatibility",
		"--audio-driver", "Dummy", "--log-file", log,
		"--script", "res://tools/runtime/m7_playable_network_client_camera_sync_fix.gd", "--",
		"--host=127.0.0.1", "--port=%d" % port, "--client-id=%s" % id,
		"--phase=%d" % phase, "--result-file=%s" % result, "--peer-file=%s" % peer,
		"--server-file=%s" % server_file, "--network-profile=%s" % client_network_profile,
	], user, display)


func _spawn(exe: String, args: Array[String], user: String, display: String) -> int:
	var names := ["HOME","XDG_DATA_HOME","XDG_CONFIG_HOME","XDG_CACHE_HOME","APPDATA","LOCALAPPDATA","DISPLAY","LIBGL_ALWAYS_SOFTWARE","BREAKPOINT_RUNTIME_DISABLED","GODOT_SILENCE_ROOT_WARNING"]
	var old: Dictionary = {}
	for name in names:
		old[name] = {"set":OS.has_environment(name),"value":OS.get_environment(name)}
	for path in [user,user.path_join("data"),user.path_join("config"),user.path_join("cache")]:
		DirAccess.make_dir_recursive_absolute(path)
	OS.set_environment("HOME",user)
	OS.set_environment("XDG_DATA_HOME",user.path_join("data"))
	OS.set_environment("XDG_CONFIG_HOME",user.path_join("config"))
	OS.set_environment("XDG_CACHE_HOME",user.path_join("cache"))
	OS.set_environment("APPDATA",user.path_join("data"))
	OS.set_environment("LOCALAPPDATA",user.path_join("data"))
	OS.set_environment("BREAKPOINT_RUNTIME_DISABLED", "1")
	OS.set_environment("GODOT_SILENCE_ROOT_WARNING", "1")
	if not display.is_empty():
		OS.set_environment("DISPLAY",display)
		OS.set_environment("LIBGL_ALWAYS_SOFTWARE","1")
	var pid := OS.create_process(exe,args,false)
	for name in names:
		if bool(old[name]["set"]): OS.set_environment(name,String(old[name]["value"]))
		else: OS.unset_environment(name)
	return pid


func _start_xvfb() -> String:
	if not FileAccess.file_exists("/usr/bin/Xvfb"):
		return ""
	var display := ":%d" % (700 + OS.get_process_id() % 200)
	xvfb_pid = OS.create_process("/usr/bin/Xvfb",[display,"-screen","0","1280x720x24","-nolisten","tcp","-noreset"],false)
	pids.append(xvfb_pid)
	OS.delay_msec(500)
	return display if OS.is_process_running(xvfb_pid) else ""


func _wait_state(path: String, states: Array[String], timeout: int) -> Dictionary:
	var start := Time.get_ticks_msec()
	var value: Dictionary = {}
	while Time.get_ticks_msec() - start < timeout:
		value = _read(path)
		if String(value.get("state", "")) in states:
			return value
		OS.delay_msec(POLL_MS)
	return value


func _wait_exit(pid: int, timeout: int) -> void:
	var start := Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - start < timeout:
		OS.delay_msec(POLL_MS)


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return Dictionary(parsed) if parsed is Dictionary else {}


func _assert_clean(path: String, label: String) -> void:
	var text := FileAccess.get_file_as_string(path).to_lower() if FileAccess.file_exists(path) else ""
	_assert(not text.contains("objectdb instances leaked") and not text.contains("resources still in use") and not text.contains("script error"), "%s clean shutdown" % label)


func _find_port() -> int:
	for candidate in range(44500 + OS.get_process_id() % 500, 46500):
		var udp := PacketPeerUDP.new()
		if udp.bind(candidate,"127.0.0.1") == OK:
			udp.close()
			return candidate
	return 0


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	for pid in pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	print("M7 playable network processes: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)