extends SceneTree

const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

const POLL_MS := 50
const READY_TIMEOUT_MS := 30000
const COMPLETE_TIMEOUT_MS := 180000
const EXIT_TIMEOUT_MS := 15000
const CROSSINGS := 8
const CLIENT_PROFILE := "BAD_MOBILE"
const AUTHORITY_PROFILE := "LAG_SPIKE"

var assertions := 0
var failures: Array[String] = []
var child_pids: Array[int] = []
var xvfb_pid := -1


func _init() -> void:
	_run_process_case()
	_finish()


func _run_process_case() -> void:
	var ports := _allocate_ports(3)
	_assert(ports.size() == 3, "7.12 three isolated ENET ports allocated")
	if ports.size() != 3:
		return
	var root := ProjectSettings.globalize_path("res://artifacts/test-results/sm1-impaired-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(root)
	var display := ""
	if OS.get_name() == "Linux":
		display = _start_xvfb()
		_assert(not display.is_empty(), "7.12 Xvfb graphical display started")
		if display.is_empty():
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
		"--initial-active=true", "--initial-epoch=1", "--timeout-ms=180000", "--result-file=%s" % a_path,
	], root.path_join("user-authority-a"), "", root.path_join("authority-a.log"))
	var authority_b_pid := _spawn(exe, [
		"--headless", "--quiet", "--path", project_root, "--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_authority_worker.gd", "--",
		"--authority-id=%s" % Support.AUTHORITY_B, "--host=127.0.0.1", "--port=%d" % int(ports[2]),
		"--initial-active=false", "--initial-epoch=1", "--timeout-ms=180000", "--result-file=%s" % b_path,
	], root.path_join("user-authority-b"), "", root.path_join("authority-b.log"))
	child_pids.append(authority_a_pid)
	child_pids.append(authority_b_pid)
	_assert(authority_a_pid > 0 and authority_b_pid > 0, "7.12 two authority processes launched")
	var a_ready := _wait_state(a_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	var b_ready := _wait_state(b_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(a_ready.get("state", "")) == "LISTENING", "7.12 Authority A listening")
	_assert(String(b_ready.get("state", "")) == "LISTENING", "7.12 Authority B listening")
	if String(a_ready.get("state", "")) != "LISTENING" or String(b_ready.get("state", "")) != "LISTENING":
		return

	var gateway_pid := _spawn(exe, [
		"--headless", "--quiet", "--path", project_root, "--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_gateway_worker.gd", "--",
		"--client-host=127.0.0.1", "--client-port=%d" % int(ports[0]),
		"--authority-a-host=127.0.0.1", "--authority-a-port=%d" % int(ports[1]),
		"--authority-b-host=127.0.0.1", "--authority-b-port=%d" % int(ports[2]),
		"--client-network-profile=%s" % CLIENT_PROFILE,
		"--authority-network-profile=%s" % AUTHORITY_PROFILE,
		"--timeout-ms=180000", "--result-file=%s" % gateway_path,
	], root.path_join("user-gateway"), "", root.path_join("gateway.log"))
	child_pids.append(gateway_pid)
	_assert(gateway_pid > 0, "7.12 Gateway process launched with deterministic impairment")
	var gateway_ready := _wait_state(gateway_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(gateway_ready.get("state", "")) == "LISTENING", "7.12 impaired Gateway listening")
	if String(gateway_ready.get("state", "")) != "LISTENING":
		return

	var client_a_pid := _spawn(exe, [
		"--quiet", "--path", project_root, "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy",
		"--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_7_impaired_crossing_client.gd", "--",
		"--client-id=a", "--host=127.0.0.1", "--port=%d" % int(ports[0]), "--timeout-ms=180000", "--result-file=%s" % client_a_path,
	], root.path_join("user-client-a"), display, root.path_join("client-a.log"))
	var client_b_pid := _spawn(exe, [
		"--quiet", "--path", project_root, "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy",
		"--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_7_impaired_crossing_client.gd", "--",
		"--client-id=b", "--host=127.0.0.1", "--port=%d" % int(ports[0]), "--timeout-ms=180000", "--result-file=%s" % client_b_path,
	], root.path_join("user-client-b"), display, root.path_join("client-b.log"))
	child_pids.append(client_a_pid)
	child_pids.append(client_b_pid)
	_assert(client_a_pid > 0 and client_b_pid > 0, "7.12 two graphical clients launched")

	var client_a := _wait_state(client_a_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var client_b := _wait_state(client_b_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var gateway := _wait_state(gateway_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var authority_a := _wait_state(a_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var authority_b := _wait_state(b_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	_validate(client_a, client_b, gateway, authority_a, authority_b)
	for pid in [client_a_pid, client_b_pid, gateway_pid, authority_a_pid, authority_b_pid]:
		_wait_exit(int(pid), EXIT_TIMEOUT_MS)
		_assert(not OS.is_process_running(int(pid)), "7.12 child process %d exited cleanly" % int(pid))


func _validate(client_a: Dictionary, client_b: Dictionary, gateway: Dictionary, authority_a: Dictionary, authority_b: Dictionary) -> void:
	for pair in [["client A", client_a], ["client B", client_b], ["Gateway", gateway], ["Authority A", authority_a], ["Authority B", authority_b]]:
		_assert(bool(Dictionary(pair[1]).get("passed", false)), "7.12 %s process PASS: %s" % [String(pair[0]), Dictionary(pair[1])])
	var pids: Dictionary = {}
	for report in [client_a, client_b, gateway, authority_a, authority_b]:
		pids[int(report.get("process_id", 0))] = true
	_assert(pids.size() == 5 and not pids.has(0), "7.12 five distinct product OS process identities")

	var expected_epochs: Array[int] = []
	var expected_revisions: Array[int] = []
	var expected_routes: Array[String] = []
	for value in range(1, CROSSINGS + 2):
		expected_epochs.append(value)
		expected_revisions.append(value)
	for index in range(CROSSINGS + 1):
		expected_routes.append(Support.AUTHORITY_A if index % 2 == 0 else Support.AUTHORITY_B)
	for report in [client_a, client_b]:
		_assert(String(report.get("display_server", "")).to_lower() not in ["", "headless", "dummy"], "7.12 client remains graphical")
		_assert(String(report.get("rendering_method", "")) == "gl_compatibility", "7.12 client uses GL compatibility renderer")
		_assert(int(report.get("connect_count", 0)) == 1 and int(report.get("reconnect_count", -1)) == 0 and int(report.get("respawn_count", -1)) == 0, "7.12 impairment causes no reconnect/respawn")
		_assert(String(report.get("gateway_endpoint_id", "")) == Support.GATEWAY_ENDPOINT_ID, "7.12 logical Gateway endpoint remains stable")
		_assert(String(report.get("logical_player_id", "")) == Support.LOGICAL_PLAYER_ID and String(report.get("player_entity_id", "")) == Support.PLAYER_ENTITY_ID, "7.12 player identity remains stable")
		_assert(int(report.get("spawn_generation", 0)) == 1, "7.12 spawn generation remains one")
		_assert(_ints(report.get("epochs", [])) == expected_epochs, "7.12 client observes every monotonic authority epoch")
		_assert(_ints(report.get("revisions", [])) == expected_revisions, "7.12 client observes every world revision exactly once")
		_assert(_strings(report.get("route_history", [])) == expected_routes, "7.12 client observes every alternating route")
		_assert(int(report.get("state_updates", 0)) == CROSSINGS + 1, "7.12 client receives exactly one state update per logical operation")
	_assert(int(client_a.get("command_results", 0)) == CROSSINGS + 1, "7.12 writer receives exactly one result per logical operation")
	_assert(int(client_b.get("command_results", -1)) == 0, "7.12 observer remains read-only")

	var counters: Dictionary = Dictionary(gateway.get("counters", {}))
	_assert(int(gateway.get("handoff_count", -1)) == CROSSINGS, "7.12 Gateway records all repeated handoffs")
	_assert(String(gateway.get("active_authority_id", "")) == Support.AUTHORITY_A and int(gateway.get("authority_epoch", 0)) == CROSSINGS + 1, "7.12 final writer is A at monotonic epoch 9")
	_assert(int(gateway.get("last_world_revision", 0)) == CROSSINGS + 1, "7.12 Gateway converges to revision 9")
	_assert(int(counters.get("commands", -1)) == CROSSINGS + 1, "7.12 Gateway forwards exactly nine logical commands")
	_assert(int(counters.get("handoffs", -1)) == CROSSINGS and int(counters.get("route_changes", -1)) == CROSSINGS, "7.12 route changes exactly once per crossing")
	_assert(int(counters.get("state_broadcasts", -1)) == CROSSINGS + 1, "7.12 Gateway broadcasts one state per operation")
	_assert(int(counters.get("busy_rejections", -1)) == 0, "7.12 sequential impaired crossings need no busy retry")
	_assert(not bool(gateway.get("transfer_payload_retained", true)) and not bool(gateway.get("canonical_gameplay_owner", true)), "7.12 Gateway ends non-canonical with no retained transfer")
	_assert(not bool(gateway.get("client_endpoint_changed", true)), "7.12 client-facing endpoint never changes")

	var network: Dictionary = Dictionary(gateway.get("network_conditions", {}))
	var client_net: Dictionary = Dictionary(network.get("client", {}))
	var client_profile: Dictionary = Dictionary(client_net.get("profile", {}))
	var client_snapshot: Dictionary = Dictionary(client_net.get("snapshot", {}))
	var client_counters: Dictionary = Dictionary(client_snapshot.get("counters", {}))
	_assert(String(client_profile.get("profile_id", "")) == CLIENT_PROFILE, "7.12 client leg uses BAD_MOBILE profile")
	_assert(not bool(client_snapshot.get("passthrough", true)), "7.12 client leg is genuinely simulated")
	_assert(int(client_counters.get("network_simulator_outgoing_packets_queued", 0)) > 0 and int(client_counters.get("network_simulator_incoming_packets_queued", 0)) > 0, "7.12 client leg queues delayed traffic in both directions")
	_assert(int(client_counters.get("network_simulator_reliable_retransmissions_simulated", 0)) > 0, "7.12 BAD_MOBILE deterministically exercises reliable retransmission")
	var authority_network: Dictionary = Dictionary(network.get("authorities", {}))
	for authority_id in [Support.AUTHORITY_A, Support.AUTHORITY_B]:
		var leg: Dictionary = Dictionary(authority_network.get(authority_id, {}))
		var profile: Dictionary = Dictionary(leg.get("profile", {}))
		var snapshot: Dictionary = Dictionary(leg.get("snapshot", {}))
		var leg_counters: Dictionary = Dictionary(snapshot.get("counters", {}))
		_assert(String(profile.get("profile_id", "")) == AUTHORITY_PROFILE, "7.12 %s leg uses LAG_SPIKE profile" % authority_id)
		_assert(not bool(snapshot.get("passthrough", true)), "7.12 %s authority leg is simulated" % authority_id)
		_assert(int(leg_counters.get("network_simulator_periodic_lag_spikes", 0)) >= 2, "7.12 %s leg hits deterministic periodic lag spikes in both directions" % authority_id)

	var state_a: Dictionary = Dictionary(authority_a.get("shared_state", {}))
	var state_b: Dictionary = Dictionary(authority_b.get("shared_state", {}))
	var expected_ops: Array[String] = []
	for index in range(CROSSINGS):
		expected_ops.append("operation/sm1/impaired/%02d" % (index + 1))
	expected_ops.append("operation/sm1/graphical/5")
	_assert(String(authority_a.get("authority_id", "")) == Support.AUTHORITY_A and bool(authority_a.get("active", false)) and int(authority_a.get("authority_epoch", 0)) == CROSSINGS + 1, "7.12 Authority A is sole final active writer")
	_assert(String(authority_b.get("authority_id", "")) == Support.AUTHORITY_B and not bool(authority_b.get("active", true)) and int(authority_b.get("authority_epoch", 0)) == CROSSINGS, "7.12 Authority B is retired at epoch 8")
	_assert(int(state_a.get("world_revision", 0)) == CROSSINGS + 1 and int(state_a.get("last_input_sequence", 0)) == CROSSINGS + 1, "7.12 revision/input sequence remain monotonic through impairment")
	_assert(_strings(state_a.get("operation_ids", [])) == expected_ops, "7.12 final OperationId ledger contains every logical operation exactly once")
	_assert(float(state_a.get("position_x", 999.0)) == 0.0 and int(state_a.get("action_count", 0)) == 1, "7.12 repeated crossings return position to origin before final action")
	_assert(int(state_b.get("world_revision", 0)) == CROSSINGS and _strings(state_b.get("operation_ids", [])).size() == CROSSINGS, "7.12 retired B holds exact pre-final canonical state")
	var counters_a: Dictionary = Dictionary(authority_a.get("counters", {}))
	var counters_b: Dictionary = Dictionary(authority_b.get("counters", {}))
	_assert(int(counters_a.get("executed", -1)) == 5 and int(counters_b.get("executed", -1)) == 4, "7.12 execution partitions 5 on A + 4 on B")
	_assert(int(counters_a.get("replays", -1)) == 0 and int(counters_b.get("replays", -1)) == 0, "7.12 impairment causes zero OperationId replay")
	_assert(int(counters_a.get("write_rejections", -1)) == 0 and int(counters_b.get("write_rejections", -1)) == 0, "7.12 impairment causes zero stale/split-brain authority writes")
	_assert(not bool(authority_a.get("private_persistence_owner", true)) and not bool(authority_b.get("private_persistence_owner", true)), "7.12 authorities create no private persistence owner")


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
		failures.append("Xvfb is required for SM1.7.12 graphical acceptance")
		return ""
	var base := 1120 + (OS.get_process_id() % 100)
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
	var start := 39000 + (OS.get_process_id() % 10000)
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


func _ints(values) -> Array[int]:
	var result: Array[int] = []
	if values is Array:
		for value in values:
			result.append(int(value))
	return result


func _strings(values) -> Array[String]:
	var result: Array[String] = []
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
		print("[sm1.7.12] PASS: %s" % message)
	else:
		failures.append(message)
		print("[sm1.7.12][FAIL] %s" % message)


func _finish() -> void:
	for pid in child_pids.duplicate():
		if int(pid) > 0 and OS.is_process_running(int(pid)):
			OS.kill(int(pid))
	child_pids.clear()
	print("SM1.7.12 repeated crossings under impaired network: %d assertions, %d failures" % [assertions, failures.size()])
	if failures.is_empty():
		print("SM1_7_12_REPEATED_CROSSINGS_IMPAIRED_NETWORK_PASS")
	quit(0 if failures.is_empty() else 1)
