extends SceneTree

const Fixture = preload("res://tests/representation/rl3_streaming_test_fixture.gd")
const WORKER_SCRIPT := "res://tools/representation/rl3_streaming_worker.gd"
const TIMEOUT_MS := 30000

var assertions: int = 0
var failures: Array[String] = []
var root_path: String = ""


func _init() -> void:
	root_path = ProjectSettings.globalize_path(
		"user://rl3-processes-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	_remove_tree(root_path)
	DirAccess.make_dir_recursive_absolute(root_path)
	_test_process_transfer_and_reconnect()
	_remove_tree(root_path)
	if failures.is_empty():
		print("RL3 representation streaming processes: PASS (%d assertions)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("RL3 representation streaming processes: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
		quit(1)


func _test_process_transfer_and_reconnect() -> void:
	var fixture: Dictionary = Fixture.build()
	var source: Dictionary = fixture["source"]
	var first_server_input: String = root_path.path_join("server-first-input.json")
	var first_server_output: String = root_path.path_join("server-first-output.json")
	_assert(_write_json(first_server_input, {
		"request": Fixture.request(source, 1),
		"manifests": fixture["manifests"],
		"artifacts": fixture["artifacts"],
	}), "First server input write failed")
	var server_pid: int = _spawn("server", first_server_input, first_server_output)
	_assert(server_pid > 0, "First server worker did not start")
	_assert(_wait(server_pid) == 0, "First server worker failed")
	var first_server: Dictionary = _read_json(first_server_output)
	_assert(bool(first_server.get("passed", false)), "First server report failed")
	_assert(String(first_server.get("server_status", "")) == "READY", "First server did not complete stream")
	_assert(int(first_server.get("store_bytes", 0)) == 736, "Process artifact store accounting changed")
	var first_plan: Dictionary = first_server.get("plan", {})
	_assert(Array(first_plan.get("stages", [])).size() == 2, "Process progressive plan stage count changed")
	_assert(int(first_plan["total_transfer_bytes"]) == 352, "Process first transfer bytes changed")
	_assert(Array(first_server.get("chunks", [])).size() == 6, "Process first chunk count changed")
	_assert(int(first_plan["stages"][0]["artifact_manifest"]["representation_key"]["lod_level"]) == 2, "Process coarse stage changed")
	_assert(int(first_plan["stages"][1]["artifact_manifest"]["representation_key"]["lod_level"]) == 1, "Process final stage changed")

	var first_client_input: String = root_path.path_join("client-first-input.json")
	var first_client_output: String = root_path.path_join("client-first-output.json")
	_assert(_write_json(first_client_input, {
		"plan": first_plan,
		"chunks": first_server["chunks"],
		"cache_entries": [],
		"source_checksum": source["checksum"],
	}), "First client input write failed")
	var client_pid: int = _spawn("client", first_client_input, first_client_output)
	_assert(client_pid > 0, "First client worker did not start")
	_assert(_wait(client_pid) == 0, "First client worker failed")
	var first_client: Dictionary = _read_json(first_client_output)
	_assert(bool(first_client.get("passed", false)), "First client report failed")
	_assert(String(first_client.get("client_status", "")) == "READY", "First client stream not ready")
	_assert(int(first_client.get("current_lod", -1)) == 1, "First client final LOD changed")
	_assert(Array(first_client.get("advertised_hashes", [])).size() == 2, "First client cache count changed")
	_assert(int(first_client.get("resident_bytes", 0)) == 352, "First client resident bytes changed")
	_assert(int(first_client.get("initial_ack_count", -1)) == 0, "First client unexpectedly used cache-hit ack")

	var cached_hashes: Array = first_client["advertised_hashes"]
	var reconnect_server_input: String = root_path.path_join("server-reconnect-input.json")
	var reconnect_server_output: String = root_path.path_join("server-reconnect-output.json")
	_assert(_write_json(reconnect_server_input, {
		"request": Fixture.request(source, 2, cached_hashes),
		"manifests": fixture["manifests"],
		"artifacts": fixture["artifacts"],
	}), "Reconnect server input write failed")
	var reconnect_server_pid: int = _spawn("server", reconnect_server_input, reconnect_server_output)
	_assert(reconnect_server_pid > 0, "Reconnect server worker did not start")
	_assert(_wait(reconnect_server_pid) == 0, "Reconnect server worker failed")
	var reconnect_server: Dictionary = _read_json(reconnect_server_output)
	_assert(bool(reconnect_server.get("passed", false)), "Reconnect server report failed")
	var reconnect_plan: Dictionary = reconnect_server.get("plan", {})
	_assert(int(reconnect_plan.get("total_transfer_bytes", -1)) == 0, "Reconnect transferred cached artifacts")
	_assert(Array(reconnect_server.get("chunks", [])).is_empty(), "Reconnect server emitted cached chunks")
	_assert(String(reconnect_plan["stages"][0]["delivery_mode"]) == "CACHE_HIT", "Reconnect coarse cache hit missing")
	_assert(String(reconnect_plan["stages"][1]["delivery_mode"]) == "CACHE_HIT", "Reconnect final cache hit missing")

	var reconnect_client_input: String = root_path.path_join("client-reconnect-input.json")
	var reconnect_client_output: String = root_path.path_join("client-reconnect-output.json")
	_assert(_write_json(reconnect_client_input, {
		"plan": reconnect_plan,
		"chunks": reconnect_server["chunks"],
		"cache_entries": first_client["cache_entries"],
		"source_checksum": source["checksum"],
	}), "Reconnect client input write failed")
	var reconnect_client_pid: int = _spawn("client", reconnect_client_input, reconnect_client_output)
	_assert(reconnect_client_pid > 0, "Reconnect client worker did not start")
	_assert(_wait(reconnect_client_pid) == 0, "Reconnect client worker failed")
	var reconnect_client: Dictionary = _read_json(reconnect_client_output)
	_assert(bool(reconnect_client.get("passed", false)), "Reconnect client report failed")
	_assert(String(reconnect_client.get("client_status", "")) == "READY", "Reconnect client stream not ready")
	_assert(int(reconnect_client.get("current_lod", -1)) == 1, "Reconnect client final LOD changed")
	_assert(int(reconnect_client.get("initial_ack_count", 0)) == 2, "Reconnect cache-hit ack count changed")
	_assert(reconnect_client.get("advertised_hashes", []) == cached_hashes, "Reconnect cache hashes changed")
	_assert(int(reconnect_client.get("resident_bytes", 0)) == 352, "Reconnect duplicated resident bytes")


func _spawn(mode: String, input_path: String, output_path: String) -> int:
	return OS.create_process(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", WORKER_SCRIPT, "--",
		"--mode=%s" % mode,
		"--input=%s" % input_path,
		"--output=%s" % output_path,
	], false)


func _wait(pid: int) -> int:
	var started: int = Time.get_ticks_msec()
	while OS.is_process_running(pid):
		if Time.get_ticks_msec() - started > TIMEOUT_MS:
			OS.kill(pid)
			return -998
		OS.delay_msec(10)
	var exit_code: int = OS.get_process_exit_code(pid)
	if exit_code == -1:
		OS.delay_msec(50)
		exit_code = OS.get_process_exit_code(pid)
	return exit_code


func _write_json(path: String, value: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t", false, true))
	file.flush()
	var error: int = file.get_error()
	file.close()
	return error == OK


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.include_hidden = true
	for file_name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in directory.get_directories():
		_remove_tree(path.path_join(directory_name))
	DirAccess.remove_absolute(path)
