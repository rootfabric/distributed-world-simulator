extends SceneTree

const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

const POLL_MS := 50
const READY_TIMEOUT_MS := 30000
const COMPLETE_TIMEOUT_MS := 90000
const EXIT_TIMEOUT_MS := 10000

var assertions := 0
var failures: Array[String] = []
var child_pids: Array[int] = []
var xvfb_pid := -1


func _init() -> void:
	var ports := _allocate_ports(3)
	_assert(ports.size() == 3, "three isolated ENET ports allocated")
	if ports.size() != 3:
		_finish()
		return
	var root := ProjectSettings.globalize_path("res://artifacts/test-results/sm1-graphical-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(root)
	var display := ""
	if OS.get_name() == "Linux":
		display = _start_xvfb()
		_assert(not display.is_empty(), "Xvfb graphical display started")
		if display.is_empty():
			_finish()
			return
	var project_root := ProjectSettings.globalize_path("res://")
	var exe := OS.get_executable_path()
	var a_path := root.path_join("authority-a.json")
	var b_path := root.path_join("authority-b.json")
	var gateway_path := root.path_join("gateway.json")
	var client_a_path := root.path_join("client-a.json")
	var client_b_path := root.path_join("client-b.json")

	var authority_a_pid := _spawn(exe, [
		"--headless", "--quiet", "--path", project_root, "--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_authority_worker.gd", "--",
		"--authority-id=%s" % Support.AUTHORITY_A, "--host=127.0.0.1", "--port=%d" % int(ports[1]),
		"--initial-active=true", "--initial-epoch=1", "--result-file=%s" % a_path,
	], root.path_join("user-authority-a"), "", root.path_join("authority-a.log"))
	var authority_b_pid := _spawn(exe, [
		"--headless", "--quiet", "--path", project_root, "--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_authority_worker.gd", "--",
		"--authority-id=%s" % Support.AUTHORITY_B, "--host=127.0.0.1", "--port=%d" % int(ports[2]),
		"--initial-active=false", "--initial-epoch=1", "--result-file=%s" % b_path,
	], root.path_join("user-authority-b"), "", root.path_join("authority-b.log"))
	child_pids.append(authority_a_pid)
	child_pids.append(authority_b_pid)
	_assert(authority_a_pid > 0 and authority_b_pid > 0, "two authority processes launched")
	var a_ready := _wait_state(a_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	var b_ready := _wait_state(b_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(a_ready.get("state", "")) == "LISTENING", "Authority A listening")
	_assert(String(b_ready.get("state", "")) == "LISTENING", "Authority B listening")
	if String(a_ready.get("state", "")) != "LISTENING" or String(b_ready.get("state", "")) != "LISTENING":
		_finish()
		return

	var gateway_pid := _spawn(exe, [
		"--headless", "--quiet", "--path", project_root, "--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_gateway_worker.gd", "--",
		"--client-host=127.0.0.1", "--client-port=%d" % int(ports[0]),
		"--authority-a-host=127.0.0.1", "--authority-a-port=%d" % int(ports[1]),
		"--authority-b-host=127.0.0.1", "--authority-b-port=%d" % int(ports[2]),
		"--result-file=%s" % gateway_path,
	], root.path_join("user-gateway"), "", root.path_join("gateway.log"))
	child_pids.append(gateway_pid)
	_assert(gateway_pid > 0, "Gateway process launched")
	var gateway_ready := _wait_state(gateway_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(gateway_ready.get("state", "")) == "LISTENING", "Gateway listening")
	if String(gateway_ready.get("state", "")) != "LISTENING":
		_finish()
		return

	var client_a_pid := _spawn(exe, [
		"--quiet", "--path", project_root, "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy",
		"--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_graphical_client.gd", "--",
		"--client-id=a", "--host=127.0.0.1", "--port=%d" % int(ports[0]), "--result-file=%s" % client_a_path,
	], root.path_join("user-client-a"), display, root.path_join("client-a.log"))
	var client_b_pid := _spawn(exe, [
		"--quiet", "--path", project_root, "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy",
		"--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_graphical_client.gd", "--",
		"--client-id=b", "--host=127.0.0.1", "--port=%d" % int(ports[0]), "--result-file=%s" % client_b_path,
	], root.path_join("user-client-b"), display, root.path_join("client-b.log"))
	child_pids.append(client_a_pid)
	child_pids.append(client_b_pid)
	_assert(client_a_pid > 0 and client_b_pid > 0, "two graphical client processes launched")

	var client_a := _wait_state(client_a_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var client_b := _wait_state(client_b_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var gateway := _wait_state(gateway_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var authority_a := _wait_state(a_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var authority_b := _wait_state(b_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	_validate(client_a, client_b, gateway, authority_a, authority_b)
	for pid in [client_a_pid, client_b_pid, gateway_pid, authority_a_pid, authority_b_pid]:
		_wait_exit(int(pid), EXIT_TIMEOUT_MS)
		_assert(not OS.is_process_running(int(pid)), "child process %d exited cleanly" % int(pid))
	_finish()


func _validate(client_a: Dictionary, client_b: Dictionary, gateway: Dictionary, authority_a: Dictionary, authority_b: Dictionary) -> void:
	for pair in [["client A", client_a], ["client B", client_b], ["Gateway", gateway], ["Authority A", authority_a], ["Authority B", authority_b]]:
		_assert(bool(Dictionary(pair[1]).get("passed", false)), "%s process PASS: %s" % [String(pair[0]), Dictionary(pair[1])])
	var pids: Dictionary = {}
	for report in [client_a, client_b, gateway, authority_a, authority_b]:
		pids[int(report.get("process_id", 0))] = true
	_assert(pids.size() == 5 and not pids.has(0), "five distinct OS process identities")
	for report in [client_a, client_b]:
		_assert(String(report.get("display_server", "")).to_lower() not in ["", "headless", "dummy"], "client uses real graphical DisplayServer")
		_assert(String(report.get("rendering_method", "")) == "gl_compatibility", "client uses GL compatibility renderer")
		_assert(int(report.get("connect_count", 0)) == 1, "client connects to Gateway exactly once")
		_assert(int(report.get("reconnect_count", -1)) == 0, "client performs zero reconnects")
		_assert(int(report.get("respawn_count", -1)) == 0, "client performs zero respawns")
		_assert(String(report.get("gateway_endpoint_id", "")) == Support.GATEWAY_ENDPOINT_ID, "client Gateway endpoint remains stable")
		_assert(String(report.get("logical_player_id", "")) == Support.LOGICAL_PLAYER_ID, "logical player identity remains stable")
		_assert(String(report.get("player_entity_id", "")) == Support.PLAYER_ENTITY_ID, "player entity identity remains stable")
		_assert(int(report.get("spawn_generation", 0)) == 1, "spawn generation remains one")
		_assert(_ints(report.get("epochs", [])) == [1, 2, 3], "client observes authority epochs 1->2->3")
		_assert(_ints(report.get("revisions", [])) == [1, 2, 3, 4, 5], "client observes continuous revisions 1..5")
		_assert(_strings(report.get("route_history", [])) == [Support.AUTHORITY_A, Support.AUTHORITY_B, Support.AUTHORITY_A], "client observes A->B->A route pivot")
	_assert(int(client_a.get("commands_sent", 0)) == 5 and int(client_a.get("command_results", 0)) == 5, "client A completes five commands through one Gateway connection")
	_assert(int(client_b.get("commands_sent", -1)) == 0, "client B remains read-only observer")
	_assert(String(gateway.get("gateway_endpoint_id", "")) == Support.GATEWAY_ENDPOINT_ID, "Gateway exposes the same logical endpoint")
	_assert(int(gateway.get("client_connection_count", 0)) == 2, "Gateway holds two simultaneous clients")
	_assert(int(gateway.get("handoff_count", 0)) == 2, "Gateway completes exactly two handoffs")
	_assert(String(gateway.get("active_authority_id", "")) == Support.AUTHORITY_A and int(gateway.get("authority_epoch", 0)) == 3, "final owner returns to Authority A at epoch 3")
	_assert(int(gateway.get("last_world_revision", 0)) == 5, "Gateway observed final world revision 5")
	_assert(not bool(gateway.get("transfer_payload_retained", true)), "Gateway retains no transfer payload after handoff")
	_assert(not bool(gateway.get("canonical_gameplay_owner", true)), "Gateway never claims canonical gameplay ownership")
	_assert(not bool(gateway.get("client_endpoint_changed", true)), "client-facing Gateway endpoint never changes")
	_assert(String(authority_a.get("authority_id", "")) == Support.AUTHORITY_A and bool(authority_a.get("active", false)) and int(authority_a.get("authority_epoch", 0)) == 3, "Authority A is final active writer at epoch 3")
	_assert(String(authority_b.get("authority_id", "")) == Support.AUTHORITY_B and not bool(authority_b.get("active", true)) and int(authority_b.get("authority_epoch", 0)) == 2, "Authority B is retired after return handoff")
	_assert(int(Dictionary(authority_a.get("shared_state", {})).get("world_revision", 0)) == 5, "Authority A owns final revision 5")
	_assert(int(Dictionary(authority_b.get("shared_state", {})).get("world_revision", 0)) == 4, "Authority B retains only retired revision 4")
	_assert(not bool(authority_a.get("private_persistence_owner", true)) and not bool(authority_b.get("private_persistence_owner", true)), "authorities do not create a private persistence owner")


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
	var full_args: Array = args.duplicate()
	full_args.insert(4 if String(full_args[0]) == "--quiet" else 3, "--log-file")
	full_args.insert(5 if String(full_args[0]) == "--quiet" else 4, log_path)
	var pid := OS.create_process(executable, full_args, false)
	_restore_environment(captured)
	return pid


func _start_xvfb() -> String:
	if not FileAccess.file_exists("/usr/bin/Xvfb"):
		failures.append("Xvfb is required for SM1.6 graphical process acceptance")
		return ""
	var base := 500 + (OS.get_process_id() % 300)
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
	var start := 28000 + (OS.get_process_id() % 20000)
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


func _wait_exit(pid: int, timeout_ms: int) -> void:
	var started := Time.get_ticks_msec()
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() - started <= timeout_ms:
		OS.delay_msec(POLL_MS)


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
		print("[sm1-graphical] PASS: %s" % message)
	else:
		failures.append(message)
		print("[sm1-graphical][FAIL] %s" % message)


func _finish() -> void:
	for pid in child_pids.duplicate():
		if int(pid) > 0 and OS.is_process_running(int(pid)):
			OS.kill(int(pid))
	child_pids.clear()
	print("SM1.6 graphical A-B-A process acceptance: %d assertions, %d failures" % [assertions, failures.size()])
	if failures.is_empty():
		print("SM1_6_GRAPHICAL_PROCESS_PASS")
	quit(0 if failures.is_empty() else 1)
