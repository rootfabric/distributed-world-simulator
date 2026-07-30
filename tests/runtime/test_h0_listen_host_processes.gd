extends SceneTree

const AtomicJsonScript = preload("res://scripts/testing/process_harness/atomic_json_file.gd")

const TIMEOUT_MS: int = 20000
const POLL_DELAY_MS: int = 25

var failures: Array[String] = []
var assertions: int = 0
var process_ids: Array[int] = []


func _init() -> void:
	var result_dir: String = ProjectSettings.globalize_path(
		"res://artifacts/test-results/h0-listen-host-%d" % OS.get_process_id()
	)
	DirAccess.make_dir_recursive_absolute(result_dir)
	var host_path: String = result_dir.path_join("listen-host.json")
	var server_path: String = result_dir.path_join("enet-server.json")
	var client_path: String = result_dir.path_join("enet-client.json")
	for path in [host_path, server_path, client_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var executable: String = OS.get_executable_path()
	var project_root: String = ProjectSettings.globalize_path("res://")

	var host_pid: int = OS.create_process(executable, [
		"--headless", "--path", project_root,
		"--script", "res://tools/runtime/h0_listen_host_probe.gd", "--",
		"--result-file=%s" % host_path,
	], false)
	process_ids.append(host_pid)
	_assert(host_pid > 0, "Failed to create listen-host probe")
	var host_report: Dictionary = _wait_for_report(host_path, TIMEOUT_MS)
	_assert(not host_report.is_empty(), "Listen-host report was not produced")
	_assert(bool(host_report.get("passed", false)), "Listen-host process failed: %s" % host_report)
	_assert(String(host_report.get("checkpoint", "")) == "v16.10.0-runtime-m1-unified-networked-gameplay-core", "Listen-host checkpoint mismatch")
	_assert(String(host_report.get("build_id", "")) == "m1-unified-networked-gameplay-core", "Listen-host build id mismatch")
	_assert(String(host_report.get("transport_kind", "")) == "LOOPBACK", "Listen-host did not use loopback")
	_assert(not bool(host_report.get("direct_client_domain_access", true)), "Listen-host allowed direct domain access")

	var port: int = _find_available_port()
	_assert(port > 0, "Could not allocate ENet comparison port")
	if port <= 0:
		_cleanup()
		_finish()
		return
	var server_pid: int = OS.create_process(executable, [
		"--headless", "--path", project_root,
		"--script", "res://tools/network/n1_remote_item_server.gd", "--",
		"--host=127.0.0.1", "--port=%d" % port,
		"--result-file=%s" % server_path,
		"--timeout-ms=%d" % TIMEOUT_MS,
		"--node-id=sim-n1",
	], false)
	process_ids.append(server_pid)
	_assert(server_pid > 0, "Failed to create ENet server")
	var listening: Dictionary = _wait_for_state(server_path, "LISTENING", 5000)
	_assert(bool(listening.get("success", false)), "ENet server did not become LISTENING")
	if not bool(listening.get("success", false)):
		_cleanup()
		_finish()
		return
	var client_pid: int = OS.create_process(executable, [
		"--headless", "--path", project_root,
		"--script", "res://tools/network/n1_remote_item_client.gd", "--",
		"--host=127.0.0.1", "--port=%d" % port,
		"--result-file=%s" % client_path,
		"--timeout-ms=%d" % TIMEOUT_MS,
		"--node-id=bot-n1",
	], false)
	process_ids.append(client_pid)
	_assert(client_pid > 0, "Failed to create ENet client")
	var server_report: Dictionary = _wait_for_terminal(server_path, TIMEOUT_MS)
	var client_report: Dictionary = _wait_for_terminal(client_path, TIMEOUT_MS)
	_assert(bool(server_report.get("passed", false)), "ENet server comparison failed: %s" % server_report)
	_assert(bool(client_report.get("passed", false)), "ENet client comparison failed: %s" % client_report)
	_assert(String(server_report.get("final_snapshot_checksum", "")) == String(client_report.get("final_snapshot_checksum", "")), "ENet client/server checksums differ")
	_assert(String(host_report.get("authority_snapshot_checksum", "")) == String(server_report.get("final_snapshot_checksum", "")), "Loopback and ENet final checksums differ")
	_assert(int(host_report.get("authority_revision", -1)) == int(server_report.get("aggregate_revision", -2)), "Loopback and ENet revisions differ")
	_assert(int(host_report.get("server_tick", -1)) == int(server_report.get("server_tick", -2)), "Loopback and ENet ticks differ")
	_assert(int(host_report.get("authority_mutation_count", -1)) == int(server_report.get("mutation_count", -2)), "Loopback and ENet mutation counts differ")
	_assert(int(host_report.get("operation_ledger_count", -1)) == int(server_report.get("operation_ledger_count", -2)), "Loopback and ENet ledger counts differ")
	_assert(bool(host_report.get("replay_delta_fenced", false)), "Loopback replay fence missing")
	_assert(bool(client_report.get("duplicate_delta_replays", 0) == 1), "ENet replay fence missing")

	_wait_for_exit(host_pid, 4000)
	_wait_for_exit(server_pid, 4000)
	_wait_for_exit(client_pid, 4000)
	for pid in process_ids:
		_assert(pid <= 0 or not OS.is_process_running(pid), "H0 comparison process remained running: %d" % pid)
	_cleanup()
	_finish()


func _find_available_port() -> int:
	var start: int = 24000 + (OS.get_process_id() % 18000)
	for offset in range(200):
		var port: int = 20000 + ((start + offset - 20000) % 30000)
		var probe := PacketPeerUDP.new()
		var error: Error = probe.bind(port, "127.0.0.1")
		probe.close()
		if error == OK:
			return port
	return 0


func _wait_for_report(path: String, timeout_ms: int) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		var value: Dictionary = AtomicJsonScript.read_value(path)
		if not value.is_empty():
			return value
		OS.delay_msec(POLL_DELAY_MS)
	return {}


func _wait_for_state(path: String, state: String, timeout_ms: int) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		var value: Dictionary = AtomicJsonScript.read_value(path)
		if String(value.get("state", "")) == state:
			return {"success": true, "value": value}
		if String(value.get("state", "")) == "FAILED":
			return {"success": false, "value": value}
		OS.delay_msec(POLL_DELAY_MS)
	return {"success": false, "error_code": "TIMEOUT"}


func _wait_for_terminal(path: String, timeout_ms: int) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		var value: Dictionary = AtomicJsonScript.read_value(path)
		if String(value.get("state", "")) in ["COMPLETE", "REJECTED", "FAILED"]:
			return value
		OS.delay_msec(POLL_DELAY_MS)
	return {}


func _wait_for_exit(pid: int, timeout_ms: int) -> void:
	if pid <= 0:
		return
	var started: int = Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - started <= timeout_ms:
		OS.delay_msec(POLL_DELAY_MS)


func _cleanup() -> void:
	for pid in process_ids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	_cleanup()
	if failures.is_empty():
		print("H0 listen-host process equivalence: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("H0 listen-host process equivalence: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
