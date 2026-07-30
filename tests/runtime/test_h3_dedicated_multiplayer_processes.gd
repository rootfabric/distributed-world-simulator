extends SceneTree

const TIMEOUT_MS := 35000
const POLL_DELAY_MS := 25
const Authority = preload("res://scripts/runtime/host_client/multiplayer_gameplay_authority.gd")

var failures: Array[String] = []
var assertions := 0
var pids: Array[int] = []


func _init() -> void:
	var port := _find_available_port()
	_assert(port > 0, "UDP port allocation")
	if port <= 0:
		_finish()
		return
	var root := ProjectSettings.globalize_path("res://artifacts/test-results/h3-multiplayer-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(root)
	var server_path := root.path_join("server.json")
	var client_a_path := root.path_join("client-a.json")
	var client_b_path := root.path_join("client-b.json")
	for path in [server_path, client_a_path, client_b_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var executable := OS.get_executable_path()
	var project_root := ProjectSettings.globalize_path("res://")
	var server_pid := OS.create_process(executable, [
		"--headless", "--path", project_root,
		"--script", "res://tools/runtime/h3_multiplayer_server.gd", "--",
		"--host=127.0.0.1", "--port=%d" % port,
		"--result-file=%s" % server_path,
		"--timeout-ms=%d" % TIMEOUT_MS,
	], false)
	pids.append(server_pid)
	_assert(server_pid > 0, "dedicated server launch")
	var listening := _wait_for_state(server_path, ["LISTENING", "FAILED"], 6000)
	_assert(String(listening.get("state", "")) == "LISTENING", "dedicated server listening: %s" % listening)
	if String(listening.get("state", "")) != "LISTENING":
		_finish()
		return
	var client_a_pid := _launch_client(executable, project_root, port, "a", client_a_path)
	var client_b_pid := _launch_client(executable, project_root, port, "b", client_b_path)
	pids.append(client_a_pid)
	pids.append(client_b_pid)
	_assert(client_a_pid > 0, "client A launch")
	_assert(client_b_pid > 0, "client B launch")
	var server := _wait_for_state(server_path, ["COMPLETE", "FAILED"], TIMEOUT_MS)
	var client_a := _wait_for_state(client_a_path, ["COMPLETE", "FAILED"], TIMEOUT_MS)
	var client_b := _wait_for_state(client_b_path, ["COMPLETE", "FAILED"], TIMEOUT_MS)
	_assert(bool(server.get("passed", false)), "server scenario: %s" % server)
	_assert(bool(client_a.get("passed", false)), "client A scenario: %s" % client_a)
	_assert(bool(client_b.get("passed", false)), "client B scenario: %s" % client_b)
	var authority_report: Dictionary = server.get("authority", {})
	_assert(int(authority_report.get("player_count", 0)) == 2, "exactly two player entities")
	_assert(not bool(authority_report.get("shared_item_available", true)), "shared item removed from world")
	var pickup_results: Dictionary = server.get("pickup_results", {})
	var pickup_success_count := 0
	var pickup_rejection_count := 0
	for result in pickup_results.values():
		if bool(result.get("success", false)):
			pickup_success_count += 1
		elif String(result.get("error_code", "")) == "ITEM_ALREADY_CLAIMED":
			pickup_rejection_count += 1
	_assert(pickup_success_count == 1, "exactly one authoritative pickup success")
	_assert(pickup_rejection_count == 1, "exactly one deterministic pickup rejection")
	_assert(String(server.get("winner_player_entity_id", "")) in ["player/a", "player/b"], "valid contention winner")
	_assert(String(server.get("a_player_entity_id", "")) == String(client_a.get("player_entity_id", "")), "player A stable identity")
	_assert(int(client_a.get("first_ownership_epoch", 0)) == 1, "player A first ownership epoch")
	_assert(int(client_a.get("second_ownership_epoch", 0)) == 2, "player A reconnect ownership epoch")
	_assert(bool(server.get("a_rejoined", false)) and bool(client_a.get("rejoined", false)), "player A rejoined")
	_assert(bool(server.get("b_continued_after_a_left", false)), "player B continued after A left")
	_assert(int(client_b.get("move_successes", 0)) == 2, "player B completed movement before and after disconnect")
	_assert(bool(client_a.get("remote_movement_observed", false)), "client A observed player B movement")
	_assert(bool(client_b.get("remote_movement_observed", false)), "client B observed player A movement")
	_assert(bool(client_b.get("a_left_observed", false)), "client B observed player A leave")
	_assert(String(client_a.get("pickup_status", "")) != String(client_b.get("pickup_status", "")), "clients received distinct contention results")
	_assert(int(server.get("targeted_results", 0)) >= 5, "targeted command results emitted")
	_assert(int(server.get("broadcast_deltas", 0)) >= 6, "gameplay deltas broadcast")
	_assert(String(server.get("listener_state", "")) == "LISTENING", "listener survived peer disconnect/reconnect")
	var server_checksum := String(server.get("final_snapshot", {}).get("checksum", ""))
	_assert(not server_checksum.is_empty(), "server final checksum")
	_assert(String(client_a.get("final_snapshot_checksum", "")) == server_checksum, "client A final state matches server")
	_assert(String(client_b.get("final_snapshot_checksum", "")) == server_checksum, "client B final state matches server")
	var final_snapshot: Dictionary = server.get("final_snapshot", {})
	var inventory_count := 0
	for player in final_snapshot.get("players", []):
		inventory_count += Array(player.get("inventory", [])).count(Authority.SHARED_ITEM_ID)
	_assert(inventory_count == 1, "no duplicate item across player inventories")
	for pid in pids:
		_wait_for_exit(pid, 3000)
		_assert(pid <= 0 or not OS.is_process_running(pid), "child process remained running: %d" % pid)
	_write_summary(port, server, client_a, client_b)
	_finish()


func _launch_client(executable: String, project_root: String, port: int, client_id: String, result_path: String) -> int:
	return OS.create_process(executable, [
		"--headless", "--path", project_root,
		"--script", "res://tools/runtime/h3_multiplayer_client.gd", "--",
		"--host=127.0.0.1", "--port=%d" % port,
		"--result-file=%s" % result_path,
		"--timeout-ms=%d" % TIMEOUT_MS,
		"--client-id=%s" % client_id,
	], false)


func _find_available_port() -> int:
	var start := 26000 + (OS.get_process_id() % 20000)
	for offset in range(300):
		var port := 20000 + ((start + offset - 20000) % 30000)
		var probe := PacketPeerUDP.new()
		var error := probe.bind(port, "127.0.0.1")
		probe.close()
		if error == OK:
			return port
	return 0


func _wait_for_state(path: String, states: Array[String], timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		var value := _read_json(path)
		if String(value.get("state", "")) in states:
			return value
		OS.delay_msec(POLL_DELAY_MS)
	return {}


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _wait_for_exit(pid: int, timeout_ms: int) -> void:
	if pid <= 0:
		return
	var started := Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - started <= timeout_ms:
		OS.delay_msec(POLL_DELAY_MS)


func _write_summary(port: int, server: Dictionary, client_a: Dictionary, client_b: Dictionary) -> void:
	var path := ProjectSettings.globalize_path("res://artifacts/test-results/h3-dedicated-multiplayer-summary.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({
			"schema": "planet_simulator.h3_dedicated_multiplayer_summary.v1",
			"checkpoint": "v16.9.3-runtime-h3-dedicated-multiplayer",
			"build_id": "h3-dedicated-two-client-gameplay",
			"passed": failures.is_empty(),
			"port": port,
			"server": server,
			"client_a": client_a,
			"client_b": client_b,
		}, "  ", true, true) + "\n")
		file.close()


func _cleanup() -> void:
	for pid in pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	_cleanup()
	if failures.is_empty():
		print("H3 dedicated multiplayer processes: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("H3 dedicated multiplayer processes: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
