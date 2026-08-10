extends SceneTree

const POLL_MS: int = 50
const SERVER_TIMEOUT_MS: int = 30000
const CLIENT_TIMEOUT_MS: int = 45000
const D0: String = "construct/t1/lunar-outpost/d0"
const DOOR_RUNTIME_ID: String = "runtime/t1a5/d0/door"

var assertions: int = 0
var failures: Array[String] = []
var pids: Array[int] = []


func _init() -> void:
	_test_late_interest_and_reconnect()
	_finish()


func _test_late_interest_and_reconnect() -> void:
	var port := _find_port()
	_assert(port > 0, "T1A.7.2 port allocation")
	if port <= 0:
		return
	var out := ProjectSettings.globalize_path("res://artifacts/test-results/t1a7-2-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	var exe := OS.get_executable_path()
	var root_path := ProjectSettings.globalize_path("res://")
	var server_file := out.path_join("server.json")
	var server_control := out.path_join("server-control.json")
	var a_file := out.path_join("a.json")
	var a_action := out.path_join("a-action.json")
	var b_file := out.path_join("b.json")
	var b_action := out.path_join("b-action.json")
	var b2_file := out.path_join("b2.json")
	var b2_action := out.path_join("b2-action.json")

	var server := _spawn(
		exe,
		[
			"--headless", "--quiet", "--path", root_path,
			"--log-file", out.path_join("server.log"),
			"--script", "res://tools/runtime/t1a7_runtime_server.gd",
			"--",
			"--host=127.0.0.1",
			"--port=%d" % port,
			"--result-file=%s" % server_file,
			"--control-file=%s" % server_control,
			"--m0-root=user://t1a7-2-m0",
		],
		out.path_join("user-server")
	)
	pids.append(server)
	_assert(server > 0, "T1A.7.2 server launch")
	_assert(String(_wait_state(server_file, "READY", SERVER_TIMEOUT_MS).get("state", "")) == "READY", "T1A.7.2 server ready")
	if server <= 0:
		return

	var a := _spawn_client(exe, root_path, port, "a", a_file, a_action, out.path_join("a.log"), out.path_join("user-a"))
	pids.append(a)
	_assert(a > 0, "client A launch")
	var a_ready := _wait_state(a_file, "READY", CLIENT_TIMEOUT_MS)
	_assert(String(a_ready.get("state", "")) == "READY", "client A gameplay join")
	_assert(Dictionary(a_ready.get("runtime_snapshot", {})).is_empty(), "A received Construction runtime before interest")

	_write_json(server_control, {"serial": 1, "client_id": "a", "interest_revision": 1, "selected_construct_ids": [D0]})
	var control_a := _wait_control(server_file, 1, CLIENT_TIMEOUT_MS)
	_assert_ok(Dictionary(control_a.get("control_result", {})), "A interest activation")
	_assert(String(Dictionary(control_a.get("control_result", {})).get("details", {}).get("mode", "")) == "AUTHORITATIVE_BASELINE", "A interest did not choose authoritative baseline")
	var a_baseline := _wait_subject_revision(a_file, DOOR_RUNTIME_ID, 0, CLIENT_TIMEOUT_MS)
	_assert(not Dictionary(a_baseline.get("runtime_snapshot", {})).is_empty(), "A baseline runtime snapshot missing")
	_assert(String(_subject(Dictionary(a_baseline.get("runtime_snapshot", {})), DOOR_RUNTIME_ID).get("state", {}).get("position", "")) == "CLOSED", "A initial door baseline mismatch")

	_write_json(a_action, {
		"serial": 1,
		"kind": "DOOR",
		"action_kind": "OPEN_DOOR",
		"expected_revision": 0,
		"operation_id": "operation/t1a7-2/a/open-door"
	})
	var a_open := _wait_action(a_file, 1, CLIENT_TIMEOUT_MS)
	_assert_ok(Dictionary(a_open.get("action_result", {})), "A opens door")
	var a_open_replica := _wait_subject_revision(a_file, DOOR_RUNTIME_ID, 1, CLIENT_TIMEOUT_MS)
	_assert(String(_subject(Dictionary(a_open_replica.get("runtime_snapshot", {})), DOOR_RUNTIME_ID).get("state", {}).get("position", "")) == "OPEN", "A did not receive OPEN mutation")

	var b := _spawn_client(exe, root_path, port, "b", b_file, b_action, out.path_join("b.log"), out.path_join("user-b"))
	pids.append(b)
	_assert(b > 0, "client B late launch")
	var b_ready := _wait_state(b_file, "READY", CLIENT_TIMEOUT_MS)
	_assert(String(b_ready.get("state", "")) == "READY", "client B gameplay join")
	OS.delay_msec(400)
	b_ready = _read(b_file)
	_assert(Dictionary(b_ready.get("runtime_snapshot", {})).is_empty(), "late B received D0 before interest")
	_assert(_runtime_snapshot_count(b_ready) == 0, "late B runtime snapshot counter advanced before interest")

	_write_json(server_control, {"serial": 2, "client_id": "b", "interest_revision": 1, "selected_construct_ids": [D0]})
	var control_b := _wait_control(server_file, 2, CLIENT_TIMEOUT_MS)
	_assert_ok(Dictionary(control_b.get("control_result", {})), "B late-interest activation")
	var b_open := _wait_subject_revision(b_file, DOOR_RUNTIME_ID, 1, CLIENT_TIMEOUT_MS)
	_assert(String(_subject(Dictionary(b_open.get("runtime_snapshot", {})), DOOR_RUNTIME_ID).get("state", {}).get("position", "")) == "OPEN", "late B baseline did not contain current OPEN door")
	var b_count_before_leave := _runtime_snapshot_count(b_open)

	_write_json(server_control, {"serial": 3, "client_id": "b", "interest_revision": 2, "selected_construct_ids": []})
	var control_b_leave := _wait_control(server_file, 3, CLIENT_TIMEOUT_MS)
	_assert_ok(Dictionary(control_b_leave.get("control_result", {})), "B leaves D0 interest")
	_assert(String(Dictionary(control_b_leave.get("control_result", {})).get("details", {}).get("mode", "")) == "OUT_OF_INTEREST", "B leave did not become out-of-interest")

	_write_json(a_action, {
		"serial": 2,
		"kind": "DOOR",
		"action_kind": "CLOSE_DOOR",
		"expected_revision": 1,
		"operation_id": "operation/t1a7-2/a/close-door"
	})
	var a_close := _wait_action(a_file, 2, CLIENT_TIMEOUT_MS)
	_assert_ok(Dictionary(a_close.get("action_result", {})), "A closes door while B is out of interest")
	var a_closed_replica := _wait_subject_revision(a_file, DOOR_RUNTIME_ID, 2, CLIENT_TIMEOUT_MS)
	_assert(String(_subject(Dictionary(a_closed_replica.get("runtime_snapshot", {})), DOOR_RUNTIME_ID).get("state", {}).get("position", "")) == "CLOSED", "A did not receive CLOSED mutation")
	OS.delay_msec(500)
	var b_after_close := _read(b_file)
	_assert(_runtime_snapshot_count(b_after_close) == b_count_before_leave, "out-of-interest B received D0 mutation")
	_assert(String(_subject(Dictionary(b_after_close.get("runtime_snapshot", {})), DOOR_RUNTIME_ID).get("state", {}).get("position", "")) == "OPEN", "out-of-interest B replica changed without baseline")

	_write_json(server_control, {"serial": 4, "client_id": "b", "interest_revision": 3, "selected_construct_ids": [D0]})
	var control_b_reenter := _wait_control(server_file, 4, CLIENT_TIMEOUT_MS)
	_assert_ok(Dictionary(control_b_reenter.get("control_result", {})), "B re-enters D0 interest")
	var b_closed := _wait_subject_revision(b_file, DOOR_RUNTIME_ID, 2, CLIENT_TIMEOUT_MS)
	_assert(String(_subject(Dictionary(b_closed.get("runtime_snapshot", {})), DOOR_RUNTIME_ID).get("state", {}).get("position", "")) == "CLOSED", "B re-entry baseline did not catch up CLOSED door")
	_assert(_runtime_snapshot_count(b_closed) == b_count_before_leave + 1, "B re-entry baseline count mismatch")

	_write_json(b_action, {"serial": 1, "action_kind": "LEAVE"})
	_assert(_wait_exit(b, 10000), "B graceful leave")
	var one_peer := _wait_connected_peers(server_file, 1, CLIENT_TIMEOUT_MS)
	_assert(int(Dictionary(one_peer.get("m3", {})).get("connected_peer_count", -1)) == 1, "server did not observe B disconnect")

	var b2 := _spawn_client(exe, root_path, port, "b", b2_file, b2_action, out.path_join("b2.log"), out.path_join("user-b2"))
	pids.append(b2)
	_assert(b2 > 0, "client B reconnect launch")
	var b2_ready := _wait_state(b2_file, "READY", CLIENT_TIMEOUT_MS)
	_assert(String(b2_ready.get("state", "")) == "READY", "client B reconnect gameplay join")
	var b2_closed := _wait_subject_revision(b2_file, DOOR_RUNTIME_ID, 2, CLIENT_TIMEOUT_MS)
	_assert(String(_subject(Dictionary(b2_closed.get("runtime_snapshot", {})), DOOR_RUNTIME_ID).get("state", {}).get("position", "")) == "CLOSED", "reconnected B did not receive retained-interest baseline")
	var final_server := _read(server_file)
	var interest_report: Dictionary = Dictionary(final_server.get("t1a7", {})).get("interest", {})
	_assert(int(interest_report.get("reconnect_binds", 0)) >= 1, "server did not record reconnect bind")
	_assert(int(Dictionary(final_server.get("t1a7", {})).get("interest_baselines", 0)) >= 3, "server baseline telemetry too low")
	_assert(int(Dictionary(final_server.get("t1a7", {})).get("interest_suppressed_snapshots", 0)) >= 3, "server did not record filtered snapshots")

	_write_json(a_action, {"serial": 3, "action_kind": "LEAVE"})
	_write_json(b2_action, {"serial": 1, "action_kind": "LEAVE"})
	_wait_exit(a, 10000)
	_wait_exit(b2, 10000)


func _spawn_client(exe: String, root_path: String, port: int, client_id: String, result_file: String, action_file: String, log_file: String, user_dir: String) -> int:
	return _spawn(
		exe,
		[
			"--headless", "--quiet", "--path", root_path,
			"--log-file", log_file,
			"--script", "res://tools/runtime/t1a7_runtime_client.gd",
			"--",
			"--host=127.0.0.1",
			"--port=%d" % port,
			"--client-id=%s" % client_id,
			"--result-file=%s" % result_file,
			"--action-file=%s" % action_file,
		],
		user_dir
	)


func _spawn(exe: String, args: Array[String], user_dir: String) -> int:
	var names := ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"]
	var old: Dictionary = {}
	for name in names:
		old[name] = {"set": OS.has_environment(name), "value": OS.get_environment(name)}
	for path in [user_dir, user_dir.path_join("data"), user_dir.path_join("config"), user_dir.path_join("cache")]:
		DirAccess.make_dir_recursive_absolute(path)
	OS.set_environment("HOME", user_dir)
	OS.set_environment("XDG_DATA_HOME", user_dir.path_join("data"))
	OS.set_environment("XDG_CONFIG_HOME", user_dir.path_join("config"))
	OS.set_environment("XDG_CACHE_HOME", user_dir.path_join("cache"))
	OS.set_environment("APPDATA", user_dir.path_join("data"))
	OS.set_environment("LOCALAPPDATA", user_dir.path_join("data"))
	var pid := OS.create_process(exe, args, false)
	for name in names:
		if bool(old[name]["set"]):
			OS.set_environment(name, String(old[name]["value"]))
		else:
			OS.unset_environment(name)
	return pid


func _wait_state(path: String, expected: String, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var value: Dictionary = {}
	while Time.get_ticks_msec() - started < timeout_ms:
		value = _read(path)
		if String(value.get("state", "")) == expected:
			return value
		if String(value.get("state", "")) in ["FAILED", "TIMEOUT"]:
			return value
		OS.delay_msec(POLL_MS)
	return value


func _wait_control(path: String, serial: int, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var value: Dictionary = {}
	while Time.get_ticks_msec() - started < timeout_ms:
		value = _read(path)
		if int(value.get("control_serial", 0)) >= serial:
			return value
		OS.delay_msec(POLL_MS)
	return value


func _wait_action(path: String, serial: int, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var value: Dictionary = {}
	while Time.get_ticks_msec() - started < timeout_ms:
		value = _read(path)
		if int(value.get("action_serial", 0)) >= serial:
			return value
		OS.delay_msec(POLL_MS)
	return value


func _wait_subject_revision(path: String, runtime_id: String, revision: int, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var value: Dictionary = {}
	while Time.get_ticks_msec() - started < timeout_ms:
		value = _read(path)
		var subject := _subject(Dictionary(value.get("runtime_snapshot", {})), runtime_id)
		if not subject.is_empty() and int(subject.get("revision", -1)) >= revision:
			return value
		OS.delay_msec(POLL_MS)
	return value


func _wait_connected_peers(path: String, count: int, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var value: Dictionary = {}
	while Time.get_ticks_msec() - started < timeout_ms:
		value = _read(path)
		if int(Dictionary(value.get("m3", {})).get("connected_peer_count", -1)) == count:
			return value
		OS.delay_msec(POLL_MS)
	return value


func _subject(snapshot: Dictionary, runtime_id: String) -> Dictionary:
	for subject_value in Dictionary(snapshot.get("runtime_state", {})).get("subjects", []):
		if subject_value is Dictionary and String(subject_value.get("runtime_id", "")) == runtime_id:
			return Dictionary(subject_value)
	return {}


func _runtime_snapshot_count(report: Dictionary) -> int:
	return int(Dictionary(Dictionary(report.get("client", {})).get("t1a6", {})).get("runtime_snapshots_received", 0))


func _wait_exit(pid: int, timeout_ms: int) -> bool:
	var started := Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - started < timeout_ms:
		OS.delay_msec(POLL_MS)
	return not OS.is_process_running(pid)


func _write_json(path: String, value: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "  "))
		file.close()


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return Dictionary(parsed) if parsed is Dictionary else {}


func _find_port() -> int:
	for port in range(46000 + OS.get_process_id() % 500, 48000):
		var udp := PacketPeerUDP.new()
		if udp.bind(port, "127.0.0.1") == OK:
			udp.close()
			return port
	return 0


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _finish() -> void:
	for pid in pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	if failures.is_empty():
		print("T1A.7.2 late-interest + reconnect: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("T1A.7.2 late-interest + reconnect: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
