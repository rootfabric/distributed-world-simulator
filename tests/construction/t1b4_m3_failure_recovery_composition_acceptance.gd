extends SceneTree

const POLL_MS: int = 50
const SERVER_TIMEOUT_MS: int = 30000
const CLIENT_TIMEOUT_MS: int = 45000
const CONVERGENCE_TIMEOUT_MS: int = 20000
const CONSTRUCT_ID: String = "construct/t1/lunar-outpost/d0"
const GENERATOR_ID: String = "runtime/t1a5/d0/generator"
const CONSOLE_ID: String = "runtime/t1a5/d0/console"
const DOOR_ID: String = "runtime/t1a5/d0/door"
const LAMP_ID: String = "runtime/t1a5/d0/lamp"

var failures: Array[String] = []
var assertions: int = 0
var pids: Array[int] = []
var xvfb_pid: int = -1
var scenario_completed: bool = false


func _init() -> void:
	_test_live_m3_failure_recovery_composition()
	_finish()


func _test_live_m3_failure_recovery_composition() -> void:
	var port := _find_port()
	_assert(port > 0, "port allocation")
	if port <= 0:
		return
	var out := ProjectSettings.globalize_path("res://artifacts/test-results/t1b4-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	var server_file := out.path_join("server.json")
	var server_m3_file := out.path_join("server-m3.json")
	var control_file := out.path_join("server-control.json")
	var a_file := out.path_join("a.json")
	var a_action := out.path_join("a-action.json")
	var b_file := out.path_join("b.json")
	var b_action := out.path_join("b-action.json")
	var a2_file := out.path_join("a2.json")
	var a2_action := out.path_join("a2-action.json")
	var c_file := out.path_join("c.json")
	var c_action := out.path_join("c-action.json")
	var exe := OS.get_executable_path()
	var root_path := ProjectSettings.globalize_path("res://")
	var display := ""
	if OS.get_name() == "Linux":
		display = _start_xvfb()
		_assert(not display.is_empty(), "Xvfb graphical display")
		if display.is_empty():
			return

	var server_user := out.path_join("user-server")
	var server := _spawn_server(exe, root_path, port, server_file, server_m3_file, control_file, server_user)
	pids.append(server)
	_assert(server > 0, "initial dedicated server launch")
	var ready := _wait_state(server_file, ["READY", "FAILED", "TIMEOUT"], SERVER_TIMEOUT_MS)
	_assert(String(ready.get("state", "")) == "READY", "initial server ready: %s" % ready)
	if String(ready.get("state", "")) != "READY":
		return
	_assert(not bool(Dictionary(ready.get("t1b4", {})).get("recovered_from_m0", true)), "fresh server unexpectedly recovered from M0")

	var a := _spawn_client(exe, root_path, port, "client/t1b4/a", a_file, a_action, out.path_join("a.log"), out.path_join("user-a"), display)
	var b := _spawn_client(exe, root_path, port, "client/t1b4/b", b_file, b_action, out.path_join("b.log"), out.path_join("user-b"), display)
	pids.append(a)
	pids.append(b)
	_assert(a > 0 and b > 0, "initial graphical clients launch")
	_assert(String(_wait_state(a_file, ["READY", "FAILED", "TIMEOUT"], CLIENT_TIMEOUT_MS).get("state", "")) == "READY", "client A ready")
	_assert(String(_wait_state(b_file, ["READY", "FAILED", "TIMEOUT"], CLIENT_TIMEOUT_MS).get("state", "")) == "READY", "client B ready")

	_write_json(control_file, {"serial": 1, "operation": "INTEREST", "client_id": "client/t1b4/a", "interest_revision": 1, "selected_construct_ids": [CONSTRUCT_ID]})
	_assert_ok(_wait_control(server_file, 1, SERVER_TIMEOUT_MS), "A interest baseline control")
	_write_json(control_file, {"serial": 2, "operation": "INTEREST", "client_id": "client/t1b4/b", "interest_revision": 1, "selected_construct_ids": [CONSTRUCT_ID]})
	_assert_ok(_wait_control(server_file, 2, SERVER_TIMEOUT_MS), "B interest baseline control")
	var a_initial := _wait_snapshot(a_file, 0, CONVERGENCE_TIMEOUT_MS)
	var b_initial := _wait_snapshot(b_file, 0, CONVERGENCE_TIMEOUT_MS)
	_assert(not a_initial.is_empty() and not b_initial.is_empty(), "initial interest baselines received")
	_assert(String(a_initial.get("state_checksum", "")) == String(b_initial.get("state_checksum", "")), "initial client semantic convergence")

	var requirements := _requirements()
	var outage_availability := _availability(false)
	var edges := _edges()
	_write_json(control_file, {
		"serial": 3,
		"operation": "FAILURE_PLAN",
		"requirements_by_runtime_id": requirements,
		"base_availability_by_runtime_id": outage_availability,
		"edges": edges,
	})
	var outage_control := _wait_control(server_file, 3, SERVER_TIMEOUT_MS)
	_assert_ok(outage_control, "server outage failure plan")
	var outage_snapshot: Dictionary = Dictionary(Dictionary(outage_control.get("details", {})).get("snapshot", {}))
	var outage_revision := int(outage_snapshot.get("revision", -1))
	_assert(outage_revision >= 4, "outage advanced canonical runtime generation")
	var a_outage := _wait_snapshot(a_file, outage_revision, CONVERGENCE_TIMEOUT_MS)
	var b_outage := _wait_snapshot(b_file, outage_revision, CONVERGENCE_TIMEOUT_MS)
	_assert_operability(a_outage, GENERATOR_ID, "OFFLINE", ["POWER_UNAVAILABLE"], "A generator outage")
	_assert_operability(a_outage, CONSOLE_ID, "OFFLINE", ["DEPENDENCY_UNAVAILABLE"], "A console outage")
	_assert_operability(a_outage, DOOR_ID, "OFFLINE", ["DEPENDENCY_UNAVAILABLE"], "A door outage")
	_assert_operability(a_outage, LAMP_ID, "DEGRADED", ["DEPENDENCY_UNAVAILABLE"], "A lamp degradation")
	_assert(String(a_outage.get("state_checksum", "")) == String(b_outage.get("state_checksum", "")), "A/B outage semantic convergence")
	_assert(not bool(Dictionary(_read(a_file).get("presentation", {})).get("door_open", true)), "A outage presentation keeps closed door")

	var door_outage_subject := _subject(a_outage, DOOR_ID)
	var door_outage_revision := int(door_outage_subject.get("revision", -1))
	_write_json(a_action, {
		"serial": 1,
		"kind": "DOOR",
		"action_kind": "OPEN_DOOR",
		"operation_id": "operation/t1b4/door/offline",
		"expected_revision": door_outage_revision,
	})
	var rejected := _wait_action(a_file, 1, CLIENT_TIMEOUT_MS)
	_assert(not bool(rejected.get("success", true)) and String(rejected.get("error_code", "")) == "CONSTRUCTION_RUNTIME_SUBJECT_OFFLINE", "live M3 OFFLINE door command rejected")
	_assert(String(Dictionary(_subject(Dictionary(_read(a_file).get("runtime_snapshot", {})), DOOR_ID).get("state", {})).get("position", "")) == "CLOSED", "rejected network command did not mutate door")

	_write_json(control_file, {"serial": 4, "operation": "CHECKPOINT", "operation_id": "operation/t1b4/checkpoint/outage"})
	var checkpoint := _wait_control(server_file, 4, SERVER_TIMEOUT_MS)
	_assert_ok(checkpoint, "outage M0 checkpoint")
	_assert(int(checkpoint.get("runtime_checkpoint_revision", -1)) >= 0, "outage checkpoint revision recorded")

	_kill_if_running(a)
	_kill_if_running(b)
	_kill_if_running(server)
	OS.delay_msec(500)
	_remove_if_exists(control_file)
	_remove_if_exists(server_file)
	_remove_if_exists(a2_file)
	_remove_if_exists(c_file)

	var server2 := _spawn_server(exe, root_path, port, server_file, server_m3_file, control_file, server_user)
	pids.append(server2)
	_assert(server2 > 0, "restarted dedicated server launch")
	var ready2 := _wait_state(server_file, ["READY", "FAILED", "TIMEOUT"], SERVER_TIMEOUT_MS)
	_assert(String(ready2.get("state", "")) == "READY", "restarted server ready: %s" % ready2)
	if String(ready2.get("state", "")) != "READY":
		return
	_assert(bool(Dictionary(ready2.get("t1b4", {})).get("recovered_from_m0", false)), "server process restart did not recover T1B failure truth from M0")
	var recovered_server_snapshot: Dictionary = Dictionary(Dictionary(Dictionary(ready2.get("t1b4", {})).get("t1a7", {})).get("t1a6", {})).get("runtime_snapshot", {})
	_assert_operability(recovered_server_snapshot, DOOR_ID, "OFFLINE", ["DEPENDENCY_UNAVAILABLE"], "restarted server recovered door outage")

	var a2 := _spawn_client(exe, root_path, port, "client/t1b4/a", a2_file, a2_action, out.path_join("a2.log"), out.path_join("user-a2"), display)
	var c := _spawn_client(exe, root_path, port, "client/t1b4/c", c_file, c_action, out.path_join("c.log"), out.path_join("user-c"), display)
	pids.append(a2)
	pids.append(c)
	_assert(a2 > 0 and c > 0, "reconnect and late-join graphical clients launch")
	_assert(String(_wait_state(a2_file, ["READY", "FAILED", "TIMEOUT"], CLIENT_TIMEOUT_MS).get("state", "")) == "READY", "reconnected A ready")
	_assert(String(_wait_state(c_file, ["READY", "FAILED", "TIMEOUT"], CLIENT_TIMEOUT_MS).get("state", "")) == "READY", "late client C ready")
	_assert(Dictionary(_read(a2_file).get("runtime_snapshot", {})).is_empty(), "A reconnect received Construction truth before external interest projection")
	_assert(Dictionary(_read(c_file).get("runtime_snapshot", {})).is_empty(), "C late join received Construction truth before interest")

	_write_json(control_file, {"serial": 1, "operation": "INTEREST", "client_id": "client/t1b4/a", "interest_revision": 2, "selected_construct_ids": [CONSTRUCT_ID]})
	_assert_ok(_wait_control(server_file, 1, SERVER_TIMEOUT_MS), "reconnected A external interest restore")
	_write_json(control_file, {"serial": 2, "operation": "INTEREST", "client_id": "client/t1b4/c", "interest_revision": 1, "selected_construct_ids": [CONSTRUCT_ID]})
	_assert_ok(_wait_control(server_file, 2, SERVER_TIMEOUT_MS), "late C interest activation")
	var a_recovered := _wait_snapshot(a2_file, outage_revision, CONVERGENCE_TIMEOUT_MS)
	var c_recovered := _wait_snapshot(c_file, outage_revision, CONVERGENCE_TIMEOUT_MS)
	_assert_operability(a_recovered, DOOR_ID, "OFFLINE", ["DEPENDENCY_UNAVAILABLE"], "A reconnect recovered failure baseline")
	_assert_operability(c_recovered, DOOR_ID, "OFFLINE", ["DEPENDENCY_UNAVAILABLE"], "C late-interest recovered failure baseline")
	_assert(String(a_recovered.get("state_checksum", "")) == String(c_recovered.get("state_checksum", "")), "reconnect/late-interest failure baseline convergence")

	_write_json(a2_action, {
		"serial": 1,
		"kind": "DOOR",
		"action_kind": "OPEN_DOOR",
		"operation_id": "operation/t1b4/door/offline",
		"expected_revision": door_outage_revision,
	})
	var rejected_replay := _wait_action(a2_file, 1, CLIENT_TIMEOUT_MS)
	_assert(not bool(rejected_replay.get("success", true)) and String(rejected_replay.get("error_code", "")) == "CONSTRUCTION_RUNTIME_SUBJECT_OFFLINE", "rejected command terminal replay survived server process restart")

	_write_json(control_file, {
		"serial": 3,
		"operation": "FAILURE_PLAN",
		"requirements_by_runtime_id": requirements,
		"base_availability_by_runtime_id": _availability(true),
		"edges": edges,
	})
	var recovery_control := _wait_control(server_file, 3, SERVER_TIMEOUT_MS)
	_assert_ok(recovery_control, "server dependency recovery plan")
	var online_snapshot: Dictionary = Dictionary(Dictionary(recovery_control.get("details", {})).get("snapshot", {}))
	var online_revision := int(online_snapshot.get("revision", -1))
	var a_online := _wait_snapshot(a2_file, online_revision, CONVERGENCE_TIMEOUT_MS)
	var c_online := _wait_snapshot(c_file, online_revision, CONVERGENCE_TIMEOUT_MS)
	for runtime_id in [GENERATOR_ID, CONSOLE_ID, DOOR_ID, LAMP_ID]:
		_assert_operability(a_online, runtime_id, "ONLINE", [], "A recovered %s" % runtime_id)
		_assert_operability(c_online, runtime_id, "ONLINE", [], "C recovered %s" % runtime_id)
	_assert(String(a_online.get("state_checksum", "")) == String(c_online.get("state_checksum", "")), "A/C ONLINE semantic convergence")

	var door_online_subject := _subject(a_online, DOOR_ID)
	var door_online_revision := int(door_online_subject.get("revision", -1))
	_write_json(a2_action, {
		"serial": 2,
		"kind": "DOOR",
		"action_kind": "OPEN_DOOR",
		"operation_id": "operation/t1b4/door/open-after-recovery",
		"expected_revision": door_online_revision,
	})
	var opened := _wait_action(a2_file, 2, CLIENT_TIMEOUT_MS)
	_assert_ok(opened, "door command re-enabled over real M3 after recovery")
	var opened_snapshot := _wait_subject_state(a2_file, DOOR_ID, "position", "OPEN", CONVERGENCE_TIMEOUT_MS)
	var c_opened_snapshot := _wait_subject_state(c_file, DOOR_ID, "position", "OPEN", CONVERGENCE_TIMEOUT_MS)
	_assert(not opened_snapshot.is_empty() and not c_opened_snapshot.is_empty(), "OPEN mutation reached reconnect and late-interest replicas")
	_assert(String(opened_snapshot.get("state_checksum", "")) == String(c_opened_snapshot.get("state_checksum", "")), "OPEN mutation semantic convergence")
	_assert(bool(Dictionary(_read(a2_file).get("presentation", {})).get("door_open", false)), "A presenter derived OPEN from canonical runtime")
	_assert(bool(Dictionary(_read(c_file).get("presentation", {})).get("door_open", false)), "C presenter derived OPEN from canonical runtime")

	_write_json(control_file, {"serial": 4, "operation": "CHECKPOINT", "operation_id": "operation/t1b4/checkpoint/online-open"})
	_assert_ok(_wait_control(server_file, 4, SERVER_TIMEOUT_MS), "final ONLINE/OPEN runtime checkpoint")
	var final_server := _read(server_file)
	var t1b4_report: Dictionary = Dictionary(final_server.get("t1b4", {}))
	_assert(int(t1b4_report.get("failure_plan_rejections", -1)) == 0, "T1B.4 server has no failure-plan rejection")
	_assert(int(t1b4_report.get("runtime_checkpoint_failures", -1)) == 0, "T1B.4 server has no checkpoint failure")
	_assert(int(t1b4_report.get("failure_plan_updates", 0)) >= 1, "T1B.4 server recorded recovery failure-plan update")
	_assert(int(t1b4_report.get("runtime_checkpoints", 0)) >= 1, "T1B.4 server recorded final checkpoint")
	var t1a6_report: Dictionary = Dictionary(Dictionary(t1b4_report.get("t1a7", {})).get("t1a6", {}))
	_assert(int(t1a6_report.get("runtime_snapshot", {}).get("revision", -1)) >= int(opened_snapshot.get("revision", -1)), "server canonical revision covers final client state")
	_assert(int(t1a6_report.get("runtime_rejections", 0)) >= 1, "server recorded replayed OFFLINE command rejection")
	_assert_clean(out.path_join("a2.log"), "A reconnect")
	_assert_clean(out.path_join("c.log"), "C late join")
	_assert_clean(out.path_join("server.log"), "server")
	scenario_completed = true


func _requirements() -> Dictionary:
	return {
		GENERATOR_ID: {"power": "REQUIRED", "data": "NONE", "dependency": "NONE"},
		CONSOLE_ID: {"power": "NONE", "data": "NONE", "dependency": "REQUIRED"},
		DOOR_ID: {"power": "NONE", "data": "NONE", "dependency": "REQUIRED"},
		LAMP_ID: {"power": "NONE", "data": "NONE", "dependency": "OPTIONAL"},
	}


func _availability(generator_power: bool) -> Dictionary:
	return {
		GENERATOR_ID: {"power": generator_power, "data": true},
		CONSOLE_ID: {"power": true, "data": true},
		DOOR_ID: {"power": true, "data": true},
		LAMP_ID: {"power": true, "data": true},
	}


func _edges() -> Array:
	return [
		{"from_runtime_id": GENERATOR_ID, "to_runtime_id": CONSOLE_ID},
		{"from_runtime_id": CONSOLE_ID, "to_runtime_id": DOOR_ID},
		{"from_runtime_id": GENERATOR_ID, "to_runtime_id": LAMP_ID},
	]


func _spawn_server(exe: String, root_path: String, port: int, result: String, m3_result: String, control: String, user: String) -> int:
	return _spawn(exe, [
		"--headless", "--quiet", "--path", root_path,
		"--log-file", result.get_base_dir().path_join("server.log"),
		"--script", "res://tools/runtime/t1b4_runtime_server.gd", "--",
		"--host=127.0.0.1", "--port=%d" % port,
		"--result-file=%s" % result, "--m3-result-file=%s" % m3_result,
		"--control-file=%s" % control, "--m0-root=user://t1b4-m0",
		"--shutdown-after-ms=180000",
	], user, "")


func _spawn_client(exe: String, root_path: String, port: int, client_id: String, result: String, action: String, log: String, user: String, display: String) -> int:
	return _spawn(exe, [
		"--quiet", "--path", root_path,
		"--rendering-method", "gl_compatibility", "--audio-driver", "Dummy",
		"--log-file", log,
		"--script", "res://tools/runtime/t1b4_runtime_client.gd", "--",
		"--host=127.0.0.1", "--port=%d" % port,
		"--client-id=%s" % client_id, "--result-file=%s" % result,
		"--action-file=%s" % action, "--shutdown-after-ms=180000",
	], user, display)


func _spawn(exe: String, args: Array[String], user: String, display: String) -> int:
	var names := ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA", "DISPLAY", "LIBGL_ALWAYS_SOFTWARE"]
	var old: Dictionary = {}
	for name in names:
		old[name] = {"set": OS.has_environment(name), "value": OS.get_environment(name)}
	for path in [user, user.path_join("data"), user.path_join("config"), user.path_join("cache")]:
		DirAccess.make_dir_recursive_absolute(path)
	OS.set_environment("HOME", user)
	OS.set_environment("XDG_DATA_HOME", user.path_join("data"))
	OS.set_environment("XDG_CONFIG_HOME", user.path_join("config"))
	OS.set_environment("XDG_CACHE_HOME", user.path_join("cache"))
	OS.set_environment("APPDATA", user.path_join("data"))
	OS.set_environment("LOCALAPPDATA", user.path_join("data"))
	if not display.is_empty():
		OS.set_environment("DISPLAY", display)
		OS.set_environment("LIBGL_ALWAYS_SOFTWARE", "1")
	var pid := OS.create_process(exe, args, false)
	for name in names:
		if bool(old[name]["set"]):
			OS.set_environment(name, String(old[name]["value"]))
		else:
			OS.unset_environment(name)
	return pid


func _wait_state(path: String, states: Array[String], timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var value: Dictionary = {}
	while Time.get_ticks_msec() - started < timeout_ms:
		value = _read(path)
		if String(value.get("state", "")) in states:
			return value
		OS.delay_msec(POLL_MS)
	return value


func _wait_control(path: String, serial: int, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_ms:
		var value := _read(path)
		if int(value.get("control_serial", 0)) >= serial:
			return Dictionary(value.get("control_result", {}))
		OS.delay_msec(POLL_MS)
	return {}


func _wait_action(path: String, serial: int, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_ms:
		var value := _read(path)
		if int(value.get("action_serial", 0)) >= serial:
			return Dictionary(value.get("action_result", {}))
		OS.delay_msec(POLL_MS)
	return {}


func _wait_snapshot(path: String, minimum_revision: int, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_ms:
		var snapshot: Dictionary = Dictionary(_read(path).get("runtime_snapshot", {}))
		if not snapshot.is_empty() and int(snapshot.get("revision", -1)) >= minimum_revision:
			return snapshot
		OS.delay_msec(POLL_MS)
	return {}


func _wait_subject_state(path: String, runtime_id: String, field: String, expected, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_ms:
		var snapshot: Dictionary = Dictionary(_read(path).get("runtime_snapshot", {}))
		var subject := _subject(snapshot, runtime_id)
		if not subject.is_empty() and Dictionary(subject.get("state", {})).get(field) == expected:
			return snapshot
		OS.delay_msec(POLL_MS)
	return {}


func _subject(snapshot: Dictionary, runtime_id: String) -> Dictionary:
	var runtime_state: Dictionary = Dictionary(snapshot.get("runtime_state", {}))
	for value in runtime_state.get("subjects", []):
		if value is Dictionary and String(value.get("runtime_id", "")) == runtime_id:
			return Dictionary(value).duplicate(true)
	return {}


func _assert_operability(snapshot: Dictionary, runtime_id: String, expected: String, failure_codes: Array, label: String) -> void:
	var subject := _subject(snapshot, runtime_id)
	_assert(not subject.is_empty(), "%s subject exists" % label)
	var state: Dictionary = Dictionary(subject.get("state", {}))
	_assert(String(state.get("operability", "")) == expected, "%s operability" % label)
	_assert(Array(state.get("failure_codes", [])) == failure_codes, "%s failure codes" % label)


func _write_json(path: String, value: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value))
		file.close()


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return Dictionary(parsed) if parsed is Dictionary else {}


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _kill_if_running(pid: int) -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
		var started := Time.get_ticks_msec()
		while OS.is_process_running(pid) and Time.get_ticks_msec() - started < 5000:
			OS.delay_msec(POLL_MS)


func _start_xvfb() -> String:
	if not FileAccess.file_exists("/usr/bin/Xvfb"):
		return ""
	var display := ":%d" % (700 + OS.get_process_id() % 200)
	xvfb_pid = OS.create_process("/usr/bin/Xvfb", [display, "-screen", "0", "1280x720x24", "-nolisten", "tcp", "-noreset"], false)
	pids.append(xvfb_pid)
	OS.delay_msec(500)
	return display if OS.is_process_running(xvfb_pid) else ""


func _assert_clean(path: String, label: String) -> void:
	var text := FileAccess.get_file_as_string(path).to_lower() if FileAccess.file_exists(path) else ""
	_assert(not text.contains("objectdb instances leaked") and not text.contains("resources still in use"), "%s clean shutdown" % label)


func _find_port() -> int:
	for port in range(46000 + OS.get_process_id() % 500, 48000):
		var udp := PacketPeerUDP.new()
		if udp.bind(port, "127.0.0.1") == OK:
			udp.close()
			return port
	return 0


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert(ok: bool, message: String) -> void:
	assertions += 1
	if ok:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	if not scenario_completed:
		failures.append("T1B.4 scenario did not reach completion marker")
	for pid in pids:
		_kill_if_running(pid)
	print("T1B.4 M3 failure/recovery composition: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
