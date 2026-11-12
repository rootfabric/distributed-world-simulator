extends SceneTree

# Process-level seamless transfer metrics test.
# Spawns: Authority A (initial-active), Authority B (standby), Gateway, and ONE
# headless metrics client (tests/runtime/seamless_transfer_metrics_client.gd,
# --crossings=10). Validates >=10 crossings (20 handoffs), client-observed
# continuity (single connect, zero disconnects, continuous revisions,
# strictly-increasing epochs per pivot) and aggregates pause/latency timing into
# res://artifacts/test-results/seamless-transfer-process/metrics-<pid>.json.

const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

const POLL_MS := 50
const READY_TIMEOUT_MS := 30000
const COMPLETE_TIMEOUT_MS := 120000
const EXIT_TIMEOUT_MS := 15000
const CROSSINGS := 10
const EXPECTED_HANDOFFS := 2 * CROSSINGS
const EXPECTED_COMMANDS := 2 * CROSSINGS + 2
const EXPECTED_FINAL_EPOCH := 2 * CROSSINGS + 1
const EXPECTED_FINAL_REVISION := 2 * CROSSINGS + 2
const PAUSE_P95_LIMIT_US := 2000000

var assertions := 0
var failures: Array[String] = []
var child_pids: Array[int] = []


func _init() -> void:
	_run()
	_finish()


func _run() -> void:
	var ports := _allocate_ports(3)
	_assert(ports.size() == 3, "three isolated ENET ports allocated")
	if ports.size() != 3:
		return
	var root := ProjectSettings.globalize_path("res://artifacts/test-results/seamless-transfer-process/run-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(root)
	var project_root := ProjectSettings.globalize_path("res://")
	var exe := OS.get_executable_path()
	var a_path := root.path_join("authority-a.json")
	var b_path := root.path_join("authority-b.json")
	var gateway_path := root.path_join("gateway.json")
	var client_path := root.path_join("client-metrics.json")

	var authority_a_pid := _spawn(exe, [
		"--headless", "--quiet", "--path", project_root, "--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_authority_worker.gd", "--",
		"--authority-id=%s" % Support.AUTHORITY_A, "--host=127.0.0.1", "--port=%d" % int(ports[1]),
		"--initial-active=true", "--initial-epoch=1", "--result-file=%s" % a_path,
	], root.path_join("user-authority-a"), root.path_join("authority-a.log"))
	var authority_b_pid := _spawn(exe, [
		"--headless", "--quiet", "--path", project_root, "--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_authority_worker.gd", "--",
		"--authority-id=%s" % Support.AUTHORITY_B, "--host=127.0.0.1", "--port=%d" % int(ports[2]),
		"--initial-active=false", "--initial-epoch=1", "--result-file=%s" % b_path,
	], root.path_join("user-authority-b"), root.path_join("authority-b.log"))
	child_pids.append(authority_a_pid)
	child_pids.append(authority_b_pid)
	_assert(authority_a_pid > 0 and authority_b_pid > 0, "two authority processes launched")
	var a_ready := _wait_state(a_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	var b_ready := _wait_state(b_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(a_ready.get("state", "")) == "LISTENING", "Authority A listening")
	_assert(String(b_ready.get("state", "")) == "LISTENING", "Authority B listening")
	if String(a_ready.get("state", "")) != "LISTENING" or String(b_ready.get("state", "")) != "LISTENING":
		return

	var gateway_pid := _spawn(exe, [
		"--headless", "--quiet", "--path", project_root, "--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_gateway_worker.gd", "--",
		"--client-host=127.0.0.1", "--client-port=%d" % int(ports[0]),
		"--authority-a-host=127.0.0.1", "--authority-a-port=%d" % int(ports[1]),
		"--authority-b-host=127.0.0.1", "--authority-b-port=%d" % int(ports[2]),
		"--result-file=%s" % gateway_path,
	], root.path_join("user-gateway"), root.path_join("gateway.log"))
	child_pids.append(gateway_pid)
	_assert(gateway_pid > 0, "Gateway process launched")
	var gateway_ready := _wait_state(gateway_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(gateway_ready.get("state", "")) == "LISTENING", "Gateway listening")
	if String(gateway_ready.get("state", "")) != "LISTENING":
		return

	var client_pid := _spawn(exe, [
		"--headless", "--quiet", "--path", project_root, "--script", "res://tests/runtime/seamless_transfer_metrics_client.gd", "--",
		"--host=127.0.0.1", "--port=%d" % int(ports[0]), "--result-file=%s" % client_path,
		"--crossings=%d" % CROSSINGS,
	], root.path_join("user-client"), root.path_join("client.log"))
	child_pids.append(client_pid)
	_assert(client_pid > 0, "headless metrics client process launched")

	var client := _wait_state(client_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var gateway := _wait_state(gateway_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var authority_a := _wait_state(a_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var authority_b := _wait_state(b_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	_validate(client, gateway, authority_a, authority_b, {
		"root": root,
		"client_path": client_path,
		"gateway_path": gateway_path,
		"authority_a_path": a_path,
		"authority_b_path": b_path,
	})
	for pid in [client_pid, gateway_pid, authority_a_pid, authority_b_pid]:
		_wait_exit(int(pid), EXIT_TIMEOUT_MS)
		_assert(not OS.is_process_running(int(pid)), "child process %d exited cleanly" % int(pid))


func _validate(client: Dictionary, gateway: Dictionary, authority_a: Dictionary, authority_b: Dictionary, paths: Dictionary) -> void:
	for pair in [["metrics client", client], ["Gateway", gateway], ["Authority A", authority_a], ["Authority B", authority_b]]:
		_assert(bool(Dictionary(pair[1]).get("passed", false)), "%s process PASS: %s" % [String(pair[0]), Dictionary(pair[1])])
	var pids: Dictionary = {}
	for report in [client, gateway, authority_a, authority_b]:
		pids[int(report.get("process_id", 0))] = true
	_assert(pids.size() == 4 and not pids.has(0), "four distinct OS process identities (client, gateway, two authorities)")

	# --- client-observed continuity ---
	_assert(int(client.get("connect_count", 0)) == 1, "client connects to Gateway exactly once")
	_assert(int(client.get("disconnects", -1)) == 0, "client observes zero disconnects")
	_assert(int(client.get("respawn_count", -1)) == 0, "client observes zero respawns")
	_assert(int(client.get("spawn_generation", 0)) == 1, "spawn generation stays one")
	_assert(bool(client.get("gateway_endpoint_stable", false)), "Gateway endpoint remains stable")
	_assert(String(client.get("gateway_endpoint_id", "")) == Support.GATEWAY_ENDPOINT_ID, "client Gateway endpoint id matches")
	_assert(int(client.get("commands_sent", -1)) == EXPECTED_COMMANDS, "client sends exactly %d commands" % EXPECTED_COMMANDS)
	_assert(int(client.get("command_results", -1)) == EXPECTED_COMMANDS, "client receives all %d command results (zero losses)" % EXPECTED_COMMANDS)
	_assert(Array(client.get("command_failures", [])).is_empty(), "every command succeeded")
	var revisions := _ints(client.get("revisions", []))
	var expected_revisions: Array = []
	for i in range(EXPECTED_FINAL_REVISION):
		expected_revisions.append(i + 1)
	_assert(revisions == expected_revisions, "world revisions strictly continuous 1..%d" % EXPECTED_FINAL_REVISION)
	_assert(Array(client.get("revision_continuity_errors", [])).is_empty(), "no revision gaps or regressions observed")
	var epochs := _ints(client.get("epochs", []))
	var expected_epochs: Array = []
	for i in range(EXPECTED_FINAL_EPOCH):
		expected_epochs.append(i + 1)
	_assert(epochs == expected_epochs, "client observes epochs 1..%d" % EXPECTED_FINAL_EPOCH)
	var pivot_deltas := _ints(client.get("pivot_epoch_deltas", []))
	var deltas_ok := pivot_deltas.size() == EXPECTED_HANDOFFS
	if deltas_ok:
		for delta in pivot_deltas:
			if delta != 1:
				deltas_ok = false
				break
	_assert(deltas_ok, "authority epoch increases by exactly one at each of %d pivots" % EXPECTED_HANDOFFS)
	var route := _strings(client.get("route_history", []))
	var route_ok: bool = route.size() == EXPECTED_HANDOFFS + 1 and route[0] == Support.AUTHORITY_A and route[route.size() - 1] == Support.AUTHORITY_A
	if route_ok:
		for i in range(1, route.size()):
			if route[i] == route[i - 1]:
				route_ok = false
				break
	_assert(route_ok, "route history alternates A/B across %d pivots and returns to A" % EXPECTED_HANDOFFS)
	_assert(String(client.get("final_active_authority_id", "")) == Support.AUTHORITY_A, "client final active authority is A")
	_assert(int(client.get("final_authority_epoch", -1)) == EXPECTED_FINAL_EPOCH, "client final authority epoch is %d" % EXPECTED_FINAL_EPOCH)
	_assert(int(client.get("final_world_revision", -1)) == EXPECTED_FINAL_REVISION, "client final world revision is %d" % EXPECTED_FINAL_REVISION)

	# --- timing ---
	var pauses := _ints(client.get("pivot_pause_us", []))
	var latencies := _ints(client.get("command_latency_us", []))
	_assert(pauses.size() == EXPECTED_HANDOFFS, "client measures a pause for each of %d handoff pivots" % EXPECTED_HANDOFFS)
	_assert(latencies.size() == EXPECTED_COMMANDS, "client measures latency for each of %d commands" % EXPECTED_COMMANDS)
	var pause_stats := _stats(pauses)
	var latency_stats := _stats(latencies)
	_assert(int(pause_stats.get("count", 0)) == EXPECTED_HANDOFFS and int(latency_stats.get("count", 0)) == EXPECTED_COMMANDS, "timing sample counts complete")
	_assert(int(pause_stats.get("p95_us", 0)) < PAUSE_P95_LIMIT_US, "client pause p95 %d us < %d us" % [int(pause_stats.get("p95_us", 0)), PAUSE_P95_LIMIT_US])

	# --- gateway / authority reports ---
	_assert(int(gateway.get("handoff_count", -1)) == EXPECTED_HANDOFFS, "Gateway completes exactly %d handoffs (%d crossings)" % [EXPECTED_HANDOFFS, CROSSINGS])
	_assert(String(gateway.get("active_authority_id", "")) == Support.AUTHORITY_A and int(gateway.get("authority_epoch", -1)) == EXPECTED_FINAL_EPOCH, "Gateway final owner is Authority A at epoch %d" % EXPECTED_FINAL_EPOCH)
	_assert(int(gateway.get("last_world_revision", -1)) == EXPECTED_FINAL_REVISION, "Gateway observed final world revision %d" % EXPECTED_FINAL_REVISION)
	_assert(int(gateway.get("client_connection_count", -1)) == 2, "Gateway holds two client bindings (writer + observer peer)")
	_assert(not bool(gateway.get("transfer_payload_retained", true)), "Gateway retains no transfer payload after handoffs")
	_assert(not bool(gateway.get("canonical_gameplay_owner", true)), "Gateway never claims canonical gameplay ownership")
	_assert(not bool(gateway.get("client_endpoint_changed", true)), "client-facing Gateway endpoint never changes")
	var gateway_counters: Dictionary = Dictionary(gateway.get("counters", {}))
	_assert(int(gateway_counters.get("commands", -1)) == EXPECTED_COMMANDS, "Gateway forwards exactly %d commands" % EXPECTED_COMMANDS)
	_assert(int(gateway_counters.get("state_broadcasts", -1)) == EXPECTED_COMMANDS, "Gateway broadcasts one STATE per command")
	_assert(int(gateway_counters.get("busy_rejections", -1)) == 0, "Gateway issues zero busy rejections")
	_assert(int(gateway_counters.get("client_disconnects", -1)) == 0, "Gateway observes zero client disconnects mid-run")

	_assert(String(authority_a.get("authority_id", "")) == Support.AUTHORITY_A and bool(authority_a.get("active", false)) and int(authority_a.get("authority_epoch", -1)) == EXPECTED_FINAL_EPOCH, "Authority A is final active writer at epoch %d" % EXPECTED_FINAL_EPOCH)
	_assert(String(authority_b.get("authority_id", "")) == Support.AUTHORITY_B and not bool(authority_b.get("active", true)) and int(authority_b.get("authority_epoch", -1)) == EXPECTED_FINAL_EPOCH - 1, "Authority B is retired at epoch %d" % (EXPECTED_FINAL_EPOCH - 1))
	_assert(int(Dictionary(authority_a.get("shared_state", {})).get("world_revision", -1)) == EXPECTED_FINAL_REVISION, "Authority A owns final revision %d" % EXPECTED_FINAL_REVISION)
	_assert(int(Dictionary(authority_b.get("shared_state", {})).get("world_revision", -1)) == EXPECTED_FINAL_REVISION - 1, "Authority B retains retired revision %d" % (EXPECTED_FINAL_REVISION - 1))
	_assert(absf(float(Dictionary(authority_a.get("shared_state", {})).get("position_x", 999.0))) < 0.0001, "final position_x returns to 0.0 after %d crossings" % CROSSINGS)
	_assert(not bool(authority_a.get("private_persistence_owner", true)) and not bool(authority_b.get("private_persistence_owner", true)), "authorities do not create a private persistence owner")

	# --- aggregate metrics artifact ---
	var metrics := {
		"schema": "planet_simulator.seamless_transfer_process_metrics.v1",
		"parent_process_id": OS.get_process_id(),
		"crossings": CROSSINGS,
		"handoff_count": int(gateway.get("handoff_count", 0)),
		"command_count": EXPECTED_COMMANDS,
		"command_losses": EXPECTED_COMMANDS - int(client.get("command_results", 0)),
		"final_active_authority_id": String(gateway.get("active_authority_id", "")),
		"final_authority_epoch": int(gateway.get("authority_epoch", 0)),
		"final_world_revision": int(gateway.get("last_world_revision", 0)),
		"client_connect_count": int(client.get("connect_count", 0)),
		"client_disconnects": int(client.get("disconnects", 0)),
		"pivot_pause": pause_stats,
		"command_latency": latency_stats,
		"pivot_pause_us": pauses,
		"command_latency_us": latencies,
		"client_report_path": String(paths.get("client_path", "")),
		"gateway_report_path": String(paths.get("gateway_path", "")),
		"authority_a_report_path": String(paths.get("authority_a_path", "")),
		"authority_b_report_path": String(paths.get("authority_b_path", "")),
		"assertions": assertions + failures.size(),
		"failures": failures.duplicate(),
	}
	var metrics_path := ProjectSettings.globalize_path("res://artifacts/test-results/seamless-transfer-process/metrics-%d.json" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(metrics_path.get_base_dir())
	_assert(Support.write_json(metrics_path, metrics), "aggregate metrics artifact written")
	var metrics_read := _read_json(metrics_path)
	_assert(String(metrics_read.get("schema", "")) == "planet_simulator.seamless_transfer_process_metrics.v1", "metrics artifact readable with correct schema")
	print("[seamless-transfer] pause stats us: min=%d p50=%d p95=%d max=%d (n=%d)" % [int(pause_stats.get("min_us", 0)), int(pause_stats.get("p50_us", 0)), int(pause_stats.get("p95_us", 0)), int(pause_stats.get("max_us", 0)), int(pause_stats.get("count", 0))])
	print("[seamless-transfer] latency stats us: min=%d p50=%d p95=%d max=%d (n=%d)" % [int(latency_stats.get("min_us", 0)), int(latency_stats.get("p50_us", 0)), int(latency_stats.get("p95_us", 0)), int(latency_stats.get("max_us", 0)), int(latency_stats.get("count", 0))])
	print("[seamless-transfer] metrics artifact: %s" % metrics_path)


func _spawn(executable: String, args: Array, user_root: String, log_path: String) -> int:
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
	var full_args: Array = ["--log-file", log_path]
	full_args.append_array(args)
	var pid := OS.create_process(executable, full_args, false)
	_restore_environment(captured)
	return pid


func _allocate_ports(count: int) -> Array:
	var result: Array = []
	var start := 44000 + (OS.get_process_id() % 15000)
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


func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"count": 0, "min_us": 0, "p50_us": 0, "p95_us": 0, "max_us": 0}
	var sorted_values: Array = values.duplicate()
	sorted_values.sort()
	return {
		"count": sorted_values.size(),
		"min_us": int(sorted_values[0]),
		"p50_us": _percentile(sorted_values, 50.0),
		"p95_us": _percentile(sorted_values, 95.0),
		"max_us": int(sorted_values[sorted_values.size() - 1]),
	}


func _percentile(sorted_values: Array, p: float) -> int:
	if sorted_values.is_empty():
		return 0
	var index := int(floor(p / 100.0 * (sorted_values.size() - 1)))
	return int(sorted_values[clampi(index, 0, sorted_values.size() - 1)])


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
		print("[seamless-transfer] PASS: %s" % message)
	else:
		failures.append(message)
		print("[seamless-transfer][FAIL] %s" % message)


func _finish() -> void:
	for pid in child_pids.duplicate():
		if int(pid) > 0 and OS.is_process_running(int(pid)):
			OS.kill(int(pid))
	child_pids.clear()
	print("Seamless transfer process metrics: %d assertions, %d failures" % [assertions, failures.size()])
	if failures.is_empty():
		print("SEAMLESS_TRANSFER_PROCESS_METRICS_PASS")
	quit(0 if failures.is_empty() else 1)
