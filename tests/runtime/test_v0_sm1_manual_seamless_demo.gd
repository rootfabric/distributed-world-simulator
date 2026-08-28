extends SceneTree

const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

const TIMEOUT_MS := 120000
const POLL_MS := 50

var assertions := 0
var failures: Array[String] = []
var child_pids: Array[int] = []
var xvfb_pid := -1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var executable := OS.get_executable_path()
	var project_root := ProjectSettings.globalize_path("res://")
	var result_root := ProjectSettings.globalize_path("res://artifacts/test-results/sm1-manual-demo-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(result_root)
	var ports := _allocate_ports(3)
	_assert(ports.size() == 3, "three free ENET ports allocated")
	if ports.size() != 3:
		_finish()
		return
	var display := _start_xvfb() if OS.get_name() == "Linux" else ""
	if OS.get_name() == "Linux" and display.is_empty():
		_finish()
		return

	var authority_a_file := result_root.path_join("authority-a.json")
	var authority_b_file := result_root.path_join("authority-b.json")
	var gateway_file := result_root.path_join("gateway.json")
	var client_file := result_root.path_join("client.json")

	var a_pid := _spawn(executable, [
		"--headless", "--path", project_root,
		"--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_authority_worker.gd", "--",
		"--authority-id=%s" % Support.AUTHORITY_A,
		"--host=127.0.0.1", "--port=%d" % int(ports[0]),
		"--initial-active=true", "--initial-epoch=1",
		"--result-file=%s" % authority_a_file,
		"--timeout-ms=%d" % TIMEOUT_MS,
	], result_root.path_join("ud-a"), "", result_root.path_join("authority-a.log"))
	child_pids.append(a_pid)
	var b_pid := _spawn(executable, [
		"--headless", "--path", project_root,
		"--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_authority_worker.gd", "--",
		"--authority-id=%s" % Support.AUTHORITY_B,
		"--host=127.0.0.1", "--port=%d" % int(ports[1]),
		"--initial-active=false", "--initial-epoch=1",
		"--result-file=%s" % authority_b_file,
		"--timeout-ms=%d" % TIMEOUT_MS,
	], result_root.path_join("ud-b"), "", result_root.path_join("authority-b.log"))
	child_pids.append(b_pid)
	_assert(a_pid > 0 and b_pid > 0, "two Authority OS processes launched")
	var a_listen := _wait_state(authority_a_file, ["LISTENING", "FAILED"], 15000)
	var b_listen := _wait_state(authority_b_file, ["LISTENING", "FAILED"], 15000)
	_assert(String(a_listen.get("state", "")) == "LISTENING", "Authority A listening")
	_assert(String(b_listen.get("state", "")) == "LISTENING", "Authority B listening")
	if String(a_listen.get("state", "")) != "LISTENING" or String(b_listen.get("state", "")) != "LISTENING":
		_finish()
		return

	var gateway_pid := _spawn(executable, [
		"--headless", "--path", project_root,
		"--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_gateway_worker.gd", "--",
		"--client-host=127.0.0.1", "--client-port=%d" % int(ports[2]),
		"--authority-a-host=127.0.0.1", "--authority-a-port=%d" % int(ports[0]),
		"--authority-b-host=127.0.0.1", "--authority-b-port=%d" % int(ports[1]),
		"--demo-mode=true", "--required-client-count=1",
		"--result-file=%s" % gateway_file,
		"--timeout-ms=%d" % TIMEOUT_MS,
	], result_root.path_join("ud-gateway"), "", result_root.path_join("gateway.log"))
	child_pids.append(gateway_pid)
	_assert(gateway_pid > 0, "Gateway OS process launched")
	var gateway_listen := _wait_state(gateway_file, ["LISTENING", "FAILED"], 15000)
	_assert(String(gateway_listen.get("state", "")) == "LISTENING", "Gateway listening")
	if String(gateway_listen.get("state", "")) != "LISTENING":
		_finish()
		return

	var client_pid := _spawn(executable, [
		"--path", project_root, "--rendering-method", "gl_compatibility",
		"--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_manual_seamless_client.gd", "--",
		"--host=127.0.0.1", "--port=%d" % int(ports[2]),
		"--result-file=%s" % client_file,
		"--auto-demo=true", "--timeout-ms=%d" % TIMEOUT_MS,
	], result_root.path_join("ud-client"), display, result_root.path_join("client.log"))
	child_pids.append(client_pid)
	_assert(client_pid > 0, "graphical manual client OS process launched")

	var client := _wait_state(client_file, ["COMPLETE", "INCOMPLETE", "FAILED"], TIMEOUT_MS)
	var gateway := _wait_state(gateway_file, ["COMPLETE", "FAILED"], TIMEOUT_MS)
	var authority_a := _wait_state(authority_a_file, ["COMPLETE", "FAILED"], TIMEOUT_MS)
	var authority_b := _wait_state(authority_b_file, ["COMPLETE", "FAILED"], TIMEOUT_MS)

	_assert(String(client.get("state", "")) == "COMPLETE" and bool(client.get("passed", false)), "manual client completes A->B->A")
	_assert(String(gateway.get("state", "")) == "COMPLETE" and bool(gateway.get("passed", false)), "Gateway completes demo shutdown")
	_assert(String(authority_a.get("state", "")) == "COMPLETE" and bool(authority_a.get("passed", false)), "Authority A completes")
	_assert(String(authority_b.get("state", "")) == "COMPLETE" and bool(authority_b.get("passed", false)), "Authority B completes")
	_assert(String(client.get("display_server", "")).to_lower() not in ["", "headless", "dummy"], "manual client uses graphical DisplayServer")
	_assert(String(client.get("rendering_method", "")) == "gl_compatibility", "manual client uses GL compatibility renderer")
	_assert(int(client.get("connect_count", 0)) == 1, "manual client connects to Gateway exactly once")
	_assert(int(client.get("reconnect_count", -1)) == 0, "manual client performs zero reconnects")
	_assert(int(client.get("respawn_count", -1)) == 0, "manual client performs zero respawns")
	_assert(String(client.get("gateway_endpoint_id", "")) == Support.GATEWAY_ENDPOINT_ID, "Gateway endpoint identity remains stable")
	_assert(_strings(client.get("route_history", [])) == [Support.AUTHORITY_A, Support.AUTHORITY_B, Support.AUTHORITY_A], "manual client observes A->B->A route")
	_assert(_ints(client.get("epochs", [])) == [1, 2, 3], "manual client observes epochs 1->2->3")
	_assert(String(client.get("active_authority_id", "")) == Support.AUTHORITY_A and int(client.get("authority_epoch", 0)) == 3, "manual client finishes on Authority A epoch 3")
	_assert(String(client.get("logical_player_id", "")) == Support.LOGICAL_PLAYER_ID, "logical player identity remains stable")
	_assert(String(client.get("player_entity_id", "")) == Support.PLAYER_ENTITY_ID, "player entity identity remains stable")
	_assert(int(client.get("spawn_generation", 0)) == 1, "spawn generation remains one")
	_assert(bool(gateway.get("demo_mode", false)) and int(gateway.get("required_client_count", 0)) == 1, "Gateway uses bounded one-client demo mode")
	_assert(int(gateway.get("client_connection_count", 0)) == 1, "Gateway owns one stable client connection")
	_assert(int(gateway.get("handoff_count", 0)) == 2, "Gateway completes exactly two handoffs")
	_assert(String(gateway.get("active_authority_id", "")) == Support.AUTHORITY_A and int(gateway.get("authority_epoch", 0)) == 3, "Gateway final route returns to A epoch 3")
	_assert(not bool(gateway.get("client_endpoint_changed", true)), "client-facing Gateway endpoint never changes")
	_assert(not bool(gateway.get("canonical_gameplay_owner", true)), "Gateway remains non-canonical")
	_assert(not bool(gateway.get("transfer_payload_retained", true)), "Gateway retains no transfer payload after return handoff")
	_assert(int(Dictionary(gateway.get("counters", {})).get("client_reconnects", -1)) == 0, "Gateway records zero client reconnects")

	var pids: Dictionary = {}
	for report in [client, gateway, authority_a, authority_b]:
		pids[int(report.get("process_id", 0))] = true
	_assert(pids.size() == 4 and not pids.has(0), "four distinct product OS processes")
	_finish()


func _spawn(executable: String, args: Array, user_root: String, display: String, log_path: String) -> int:
	var names := ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA", "DISPLAY", "LIBGL_ALWAYS_SOFTWARE", "BREAKPOINT_RUNTIME_DISABLED", "GODOT_SILENCE_ROOT_WARNING"]
	var captured := _capture_environment(names)
	var data := user_root.path_join("data")
	var config := user_root.path_join("config")
	var cache := user_root.path_join("cache")
	for path in [user_root, data, config, cache]:
		DirAccess.make_dir_recursive_absolute(path)
	OS.set_environment("HOME", user_root)
	OS.set_environment("XDG_DATA_HOME", data)
	OS.set_environment("XDG_CONFIG_HOME", config)
	OS.set_environment("XDG_CACHE_HOME", cache)
	OS.set_environment("APPDATA", data)
	OS.set_environment("LOCALAPPDATA", data)
	OS.set_environment("BREAKPOINT_RUNTIME_DISABLED", "1")
	OS.set_environment("GODOT_SILENCE_ROOT_WARNING", "1")
	if not display.is_empty():
		OS.set_environment("DISPLAY", display)
		OS.set_environment("LIBGL_ALWAYS_SOFTWARE", "1")
	var full_args: Array = ["--log-file", log_path]
	full_args.append_array(args)
	var pid := OS.create_process(executable, full_args, false)
	_restore_environment(captured)
	return pid


func _start_xvfb() -> String:
	if not FileAccess.file_exists("/usr/bin/Xvfb"):
		failures.append("Xvfb is required for SM1 manual seamless graphical test")
		return ""
	var base := 820 + (OS.get_process_id() % 100)
	for offset in range(20):
		var display := ":%d" % (base + offset)
		xvfb_pid = OS.create_process("/usr/bin/Xvfb", [display, "-screen", "0", "1280x720x24", "-nolisten", "tcp", "-noreset"], false)
		if xvfb_pid <= 0:
			continue
		OS.delay_msec(400)
		if OS.is_process_running(xvfb_pid):
			child_pids.append(xvfb_pid)
			return display
	return ""


func _allocate_ports(count: int) -> Array:
	var result: Array = []
	var start := 32000 + (OS.get_process_id() % 20000)
	for offset in range(1000):
		var port := 20000 + ((start + offset - 20000) % 40000)
		if result.has(port):
			continue
		var probe := PacketPeerUDP.new()
		var error := probe.bind(port, "127.0.0.1")
		probe.close()
		if error == OK:
			result.append(port)
			if result.size() == count:
				break
	return result


func _wait_state(path: String, terminal_states: Array, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		var value := _read_json(path)
		if terminal_states.has(String(value.get("state", ""))):
			return value
		OS.delay_msec(POLL_MS)
	return _read_json(path)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return Dictionary(parsed) if parsed is Dictionary else {}


func _ints(values) -> Array:
	var result: Array = []
	if values is Array:
		for value in values:
			result.append(int(value))
	return result


func _strings(values) -> Array:
	var result: Array = []
	if values is Array:
		for value in values:
			result.append(String(value))
	return result


func _capture_environment(names: Array) -> Dictionary:
	var result: Dictionary = {}
	for name_value in names:
		var name := String(name_value)
		result[name] = {"set": OS.has_environment(name), "value": OS.get_environment(name)}
	return result


func _restore_environment(values: Dictionary) -> void:
	for name_value in values.keys():
		var name := String(name_value)
		if bool(Dictionary(values[name_value]).get("set", false)):
			OS.set_environment(name, String(Dictionary(values[name_value]).get("value", "")))
		else:
			OS.unset_environment(name)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("[sm1-manual] PASS: %s" % message)
	else:
		failures.append(message)
		print("[sm1-manual][FAIL] %s" % message)


func _finish() -> void:
	for pid in child_pids.duplicate():
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	child_pids.clear()
	print("SM1 manual seamless demo: %d assertions, %d failures" % [assertions, failures.size()])
	if failures.is_empty():
		print("SM1_MANUAL_SEAMLESS_DEMO_PASS")
	quit(0 if failures.is_empty() else 1)
