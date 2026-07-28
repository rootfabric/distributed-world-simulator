extends SceneTree

const TIMEOUT_MS: int = 25000
const POLL_DELAY_MS: int = 25
const EXPECTED_INITIAL_REVISION: int = 12
const EXPECTED_FINAL_REVISION: int = 13
const EXPECTED_FINAL_TICK: int = 501

var failures: Array[String] = []
var assertions: int = 0
var server_pid: int = -1
var client_pid: int = -1


func _init() -> void:
	var port: int = _find_available_port()
	_assert(port > 0, "Could not allocate localhost UDP port")
	if port <= 0:
		_finish()
		return
	var result_dir: String = ProjectSettings.globalize_path("res://artifacts/test-results/n1-reconnect-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(result_dir)
	var server_path: String = result_dir.path_join("server.json")
	var client_path: String = result_dir.path_join("client.json")
	var summary_path: String = ProjectSettings.globalize_path("res://artifacts/test-results/n1-reconnect-replay-summary.json")
	for path in [server_path, client_path]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	var executable: String = OS.get_executable_path()
	var project_root: String = ProjectSettings.globalize_path("res://")
	server_pid = OS.create_process(executable, [
		"--headless", "--path", project_root,
		"--script", "res://tools/network/n1_reconnect_replay_server.gd", "--",
		"--host=127.0.0.1", "--port=%d" % port,
		"--result-file=%s" % server_path,
		"--timeout-ms=%d" % TIMEOUT_MS,
		"--node-id=sim-n1",
	], false)
	_assert(server_pid > 0, "Failed to create N1.3 server process")
	var listening: Dictionary = _wait_for_state(server_path, "LISTENING", 5000)
	_assert(bool(listening.get("success", false)), "N1.3 server did not become LISTENING: %s" % listening)
	if not bool(listening.get("success", false)):
		_cleanup_processes()
		_finish()
		return
	client_pid = OS.create_process(executable, [
		"--headless", "--path", project_root,
		"--script", "res://tools/network/n1_reconnect_replay_client.gd", "--",
		"--host=127.0.0.1", "--port=%d" % port,
		"--result-file=%s" % client_path,
		"--timeout-ms=%d" % TIMEOUT_MS,
		"--node-id=bot-n1",
	], false)
	_assert(client_pid > 0, "Failed to create N1.3 client process")
	var server_report: Dictionary = _wait_for_terminal_report(server_path, TIMEOUT_MS)
	var client_report: Dictionary = _wait_for_terminal_report(client_path, TIMEOUT_MS)
	_assert(not server_report.is_empty(), "Server terminal report missing")
	_assert(not client_report.is_empty(), "Client terminal report missing")
	_assert(bool(server_report.get("passed", false)), "Server reported failure: %s" % server_report)
	_assert(bool(client_report.get("passed", false)), "Client reported failure: %s" % client_report)
	_assert(String(server_report.get("state", "")) == "COMPLETE", "Server did not complete")
	_assert(String(client_report.get("state", "")) == "COMPLETE", "Client did not complete")
	_assert(String(server_report.get("logical_session_id", "")) == String(client_report.get("logical_session_id", "")), "Logical session IDs differ")
	_assert(String(server_report.get("entity_id", "")) == String(client_report.get("entity_id", "")), "Entity IDs differ")
	_assert(String(server_report.get("command_item_id", "")) == String(client_report.get("command_item_id", "")), "Item IDs differ")
	_assert(String(server_report.get("initial_snapshot_checksum", "")) == String(client_report.get("initial_snapshot_checksum", "")), "Initial checksums differ")
	_assert(String(server_report.get("final_snapshot_checksum", "")) == String(client_report.get("final_snapshot_checksum", "")), "Final checksums differ")
	_assert(String(server_report.get("initial_snapshot_checksum", "")) != String(server_report.get("final_snapshot_checksum", "")), "Mutation did not change checksum")
	_assert(int(server_report.get("aggregate_revision", -1)) == EXPECTED_FINAL_REVISION, "Server revision incorrect")
	_assert(int(client_report.get("snapshot_revision", -1)) == EXPECTED_FINAL_REVISION, "Client revision incorrect")
	_assert(int(client_report.get("snapshot_revision", -1)) == EXPECTED_INITIAL_REVISION + 1, "Client revision advanced more than once")
	_assert(int(server_report.get("server_tick", -1)) == EXPECTED_FINAL_TICK, "Server tick incorrect")
	_assert(int(client_report.get("server_tick", -1)) == EXPECTED_FINAL_TICK, "Client tick incorrect")
	_assert(int(server_report.get("mutation_count", -1)) == 1, "Server mutation count is not one")
	_assert(int(server_report.get("handler_invocation_count", -1)) == 1, "Domain handler was invoked during reconnect replay")
	_assert(int(server_report.get("operation_ledger_count", -1)) == 1, "Operation ledger count is not one")
	_assert(not bool(server_report.get("source_contains_item", true)), "Server source retained item")
	_assert(bool(server_report.get("destination_contains_item", false)), "Server destination missing item")
	_assert(int(client_report.get("source_item_count", -1)) == 0, "Client source projection retained item")
	_assert(int(client_report.get("destination_item_count", -1)) == 1, "Client destination projection missing item")
	_assert(int(client_report.get("item_revision", -1)) == 1, "Client item revision incorrect")
	_assert(int(client_report.get("mutations_applied", -1)) == 1, "Client applied mutation more than once")
	_assert(int(client_report.get("duplicate_delta_replays", -1)) == 1, "Client did not fence second replay delta")
	_assert(not bool(client_report.get("unexpected_result_before_disconnect", true)), "Initial command result was delivered before disconnect")
	_assert(int(server_report.get("disconnect_count", -1)) == 2, "Server did not force two disconnects")
	_assert(int(client_report.get("reconnect_count", -1)) == 2, "Client did not perform two reconnects")
	_assert(int(server_report.get("handshake_count", -1)) == 3, "Server handshake count incorrect")
	_assert(int(server_report.get("resume_count", -1)) == 2, "Server resume count incorrect")
	_assert(int(client_report.get("resume_accept_count", -1)) == 2, "Client resume acceptance count incorrect")
	_assert(int(server_report.get("replay_served_count", -1)) == 2, "Server replay serve count incorrect")
	_assert(int(server_report.get("final_ack_count", -1)) == 2, "Server final ACK count incorrect")
	_assert(int(client_report.get("final_ack_count", -1)) == 2, "Client final ACK count incorrect")
	_assert(int(server_report.get("command_count", -1)) == 3, "Server command count incorrect")
	_assert(int(client_report.get("commands_sent", -1)) == 3, "Client command count incorrect")
	_assert(int(client_report.get("results_received", -1)) == 2, "Client result count incorrect")
	_assert(int(client_report.get("deltas_received", -1)) == 2, "Client delta count incorrect")
	_assert(int(server_report.get("unique_transport_sessions", -1)) == 3, "Server transport sessions were not rotated")
	_assert(int(client_report.get("unique_transport_sessions", -1)) == 3, "Client transport sessions were not rotated")
	_assert(Array(server_report.get("transport_session_ids", [])).size() == 3, "Server transport session history incorrect")
	_assert(Array(client_report.get("transport_session_ids", [])).size() == 3, "Client transport session history incorrect")
	_assert(Array(server_report.get("transport_session_ids", [])) == Array(client_report.get("transport_session_ids", [])), "Transport session histories differ")
	var replay_cache: Dictionary = server_report.get("replay_cache", {})
	_assert(int(replay_cache.get("record_count", -1)) == 1, "Replay cache record count incorrect")
	_assert(int(replay_cache.get("ticket_count", -1)) == 1, "Replay cache ticket count incorrect")
	_assert(int(replay_cache.get("resume_accepts", -1)) == 2, "Replay cache resume accept count incorrect")
	_assert(int(replay_cache.get("resume_rejects", -1)) == 0, "Replay cache unexpectedly rejected resume")
	_assert(int(replay_cache.get("replay_serves", -1)) == 2, "Replay cache serve count incorrect")
	_assert(int(replay_cache.get("grant_count", -1)) == 0, "Replay grants leaked")
	_assert(int(replay_cache.get("max_records", -1)) == 8, "Replay cache bound changed")
	_assert(int(replay_cache.get("max_tickets", -1)) == 4, "Ticket cache bound changed")
	_assert(int(replay_cache.get("max_grants", -1)) == 12, "Replay grant cache bound changed")
	_assert(int(replay_cache.get("grant_evictions", -1)) == 0, "Replay grants were unexpectedly evicted")
	_assert(int(server_report.get("messages_sent", -1)) == 11, "Server message count incorrect")
	_assert(int(server_report.get("messages_received", -1)) == 11, "Server received message count incorrect")
	_assert(int(client_report.get("messages_sent", -1)) == 11, "Client sent message count incorrect")
	_assert(int(client_report.get("messages_received", -1)) == 11, "Client received message count incorrect")
	_assert(int(server_report.get("session_idle_timeout_ms", -1)) == 6000, "Server session idle timeout changed")
	_assert(int(client_report.get("session_idle_timeout_ms", -1)) == 6000, "Client session idle timeout changed")
	_wait_for_process_exit(server_pid, 4000)
	_wait_for_process_exit(client_pid, 4000)
	_assert(not OS.is_process_running(server_pid), "Server process remained running")
	_assert(not OS.is_process_running(client_pid), "Client process remained running")
	_write_summary(summary_path, port, server_report, client_report)
	_cleanup_processes()
	_finish()


func _find_available_port() -> int:
	var start: int = 20000 + (OS.get_process_id() % 20000)
	for offset in range(200):
		var port: int = 20000 + ((start + offset - 20000) % 30000)
		var probe := PacketPeerUDP.new()
		var error: Error = probe.bind(port, "127.0.0.1")
		probe.close()
		if error == OK: return port
	return 0


func _wait_for_state(path: String, expected: String, timeout_ms: int) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		var value: Dictionary = _read_json(path)
		if String(value.get("state", "")) == expected: return {"success": true, "value": value}
		if String(value.get("state", "")) == "FAILED": return {"success": false, "value": value}
		OS.delay_msec(POLL_DELAY_MS)
	return {"success": false, "error_code": "TIMEOUT"}


func _wait_for_terminal_report(path: String, timeout_ms: int) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		var value: Dictionary = _read_json(path)
		if String(value.get("state", "")) in ["COMPLETE", "REJECTED", "FAILED"]: return value
		OS.delay_msec(POLL_DELAY_MS)
	return {}


func _wait_for_process_exit(pid: int, timeout_ms: int) -> void:
	if pid <= 0: return
	var started: int = Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - started <= timeout_ms:
		OS.delay_msec(POLL_DELAY_MS)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _write_summary(path: String, port: int, server: Dictionary, client: Dictionary) -> void:
	var summary: Dictionary = {
		"schema": "planet_simulator.n1_reconnect_replay_summary.v1",
		"checkpoint": "v16.5.2-foundation-network-n1",
		"build_id": "n1-reconnect-replay-bounded-cache",
		"passed": failures.is_empty(),
		"port": port,
		"server": server.duplicate(true),
		"client": client.duplicate(true),
		"initial_checksum_equal": String(server.get("initial_snapshot_checksum", "")) == String(client.get("initial_snapshot_checksum", "")),
		"final_checksum_equal": String(server.get("final_snapshot_checksum", "")) == String(client.get("final_snapshot_checksum", "")),
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(summary, "  ", true, true) + "\n")
		file.close()


func _cleanup_processes() -> void:
	for pid in [client_pid, server_pid]:
		if pid > 0 and OS.is_process_running(pid): OS.kill(pid)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)


func _finish() -> void:
	_cleanup_processes()
	if failures.is_empty():
		print("N1 reconnect replay process test: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures: push_error(failure)
	print("N1 reconnect replay process test: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
