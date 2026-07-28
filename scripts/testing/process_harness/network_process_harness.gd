extends RefCounted

const ManifestScript = preload("res://scripts/testing/process_harness/process_harness_manifest.gd")
const AtomicJsonScript = preload("res://scripts/testing/process_harness/atomic_json_file.gd")

var _manifest: Dictionary = {}
var _executable := ""
var _project_root := ""
var _output_root := ""
var _active_pids: Array[int] = []
var _used_ports := {}
var _killed_pids := {}
var _exit_codes := {}
var _finished_pids := {}

func configure(manifest: Dictionary, executable: String, project_root: String, output_root: String) -> Dictionary:
	_cleanup_all(); _used_ports.clear(); _killed_pids.clear(); _exit_codes.clear(); _finished_pids.clear()
	var validation := ManifestScript.validate(manifest)
	if not bool(validation.get("success", false)): return validation
	if executable.strip_edges().is_empty() or not FileAccess.file_exists(executable): return _failure("GODOT_EXECUTABLE_NOT_FOUND", "Godot executable is not available")
	if project_root.strip_edges().is_empty() or not FileAccess.file_exists(project_root.path_join("project.godot")): return _failure("PROJECT_ROOT_INVALID", "Project root does not contain project.godot")
	if output_root.strip_edges().is_empty(): return _failure("OUTPUT_ROOT_INVALID", "Output root cannot be empty")
	_manifest = manifest.duplicate(true); _executable = executable; _project_root = project_root; _output_root = output_root
	DirAccess.make_dir_recursive_absolute(_output_root)
	return {"success": true}

func run_all(requested_ids: Array[String] = []) -> Dictionary:
	if _manifest.is_empty(): return _failure("HARNESS_NOT_CONFIGURED", "Harness must be configured before run")
	_cleanup_all(); _used_ports.clear(); _killed_pids.clear(); _exit_codes.clear(); _finished_pids.clear()
	var selection := ManifestScript.select_scenarios(_manifest, requested_ids)
	if not bool(selection.get("success", false)): return selection
	var started_unix_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var results: Array = []
	for scenario in Array(selection["scenarios"]): results.append(_run_scenario(scenario))
	_cleanup_all()
	var passed_count := _count_passed(results)
	var finished_unix_ms := int(Time.get_unix_time_from_system() * 1000.0)
	return {
		"schema": "planet_simulator.network_process_harness_summary.v1",
		"checkpoint": String(_manifest.get("checkpoint", "")), "build_id": String(_manifest.get("build_id", "")),
		"passed": passed_count == results.size(), "started_unix_ms": started_unix_ms, "finished_unix_ms": finished_unix_ms,
		"duration_seconds": float(finished_unix_ms - started_unix_ms) / 1000.0,
		"scenario_count": results.size(), "passed_count": passed_count, "failed_count": results.size() - passed_count,
		"scenarios": results,
	}

func _run_scenario(scenario: Dictionary) -> Dictionary:
	var started := Time.get_ticks_msec(); var defaults: Dictionary = _manifest["defaults"]; var id := String(scenario["id"])
	var run_dir := _output_root.path_join("%s-%d" % [id, started]); DirAccess.make_dir_recursive_absolute(run_dir)
	var server_report_path := run_dir.path_join("server.json"); var client_report_path := run_dir.path_join("client.json")
	var server_log := run_dir.path_join("server.log"); var client_log := run_dir.path_join("client.log")
	var server_user := run_dir.path_join("user-server"); var client_user := run_dir.path_join("user-client")
	DirAccess.make_dir_recursive_absolute(server_user); DirAccess.make_dir_recursive_absolute(client_user)
	var port := _allocate_port(int(defaults["port_range_start"]), int(defaults["port_range_end"]), String(defaults["host"]))
	if port <= 0: return _scenario_failure(scenario, run_dir, server_log, client_log, "PORT_ALLOCATION_FAILED", "No free UDP port was found", started)
	var timeout_ms := int(scenario.get("timeout_ms", 0)); if timeout_ms <= 0: timeout_ms = int(defaults["scenario_timeout_ms"])
	var ready_timeout := int(scenario.get("readiness_timeout_ms", 0)); if ready_timeout <= 0: ready_timeout = int(defaults["readiness_timeout_ms"])
	var server_args := {"host": defaults["host"], "port": port, "result-file": server_report_path, "timeout-ms": timeout_ms, "node-id": scenario["server_node_id"]}
	var client_args := {"host": defaults["host"], "port": port, "result-file": client_report_path, "timeout-ms": timeout_ms, "node-id": scenario["client_node_id"]}
	_merge_args(server_args, scenario["server_args"]); _merge_args(client_args, scenario["client_args"])
	var server_pid := _spawn(String(scenario["server_script"]), server_args, server_log, server_user)
	if server_pid <= 0: return _scenario_failure(scenario, run_dir, server_log, client_log, "SERVER_START_FAILED", "Server process could not be created", started)
	var readiness := _wait_for_state(server_pid, server_report_path, String(scenario["server_ready_state"]), ready_timeout, int(defaults["poll_delay_ms"]))
	if not bool(readiness.get("success", false)):
		var code := String(readiness.get("error_code", "READINESS_FAILED")); _kill_and_wait(server_pid, int(defaults["shutdown_timeout_ms"]))
		return _evaluate_expected_failure(scenario, run_dir, server_log, client_log, code, String(readiness.get("message", code)), started, server_pid, -1, server_report_path, client_report_path, server_user, client_user, port)
	var client_pid := _spawn(String(scenario["client_script"]), client_args, client_log, client_user)
	if client_pid <= 0:
		_kill_and_wait(server_pid, int(defaults["shutdown_timeout_ms"]))
		return _evaluate_expected_failure(scenario, run_dir, server_log, client_log, "CLIENT_START_FAILED", "Client process could not be created", started, server_pid, client_pid, server_report_path, client_report_path, server_user, client_user, port)
	var terminal := _wait_for_terminal_pair(server_pid, client_pid, server_report_path, client_report_path, Array(scenario["server_terminal_states"]), Array(scenario["client_terminal_states"]), timeout_ms, int(defaults["poll_delay_ms"]))
	if not bool(terminal.get("success", false)):
		var code := String(terminal.get("error_code", "SCENARIO_TIMEOUT")); _kill_and_wait(client_pid, int(defaults["shutdown_timeout_ms"])); _kill_and_wait(server_pid, int(defaults["shutdown_timeout_ms"]))
		return _evaluate_expected_failure(scenario, run_dir, server_log, client_log, code, String(terminal.get("message", code)), started, server_pid, client_pid, server_report_path, client_report_path, server_user, client_user, port)
	_wait_for_exit(client_pid, int(defaults["shutdown_timeout_ms"]), int(defaults["poll_delay_ms"])); _wait_for_exit(server_pid, int(defaults["shutdown_timeout_ms"]), int(defaults["poll_delay_ms"]))
	if _is_running(client_pid) or _is_running(server_pid):
		_kill_and_wait(client_pid, int(defaults["shutdown_timeout_ms"])); _kill_and_wait(server_pid, int(defaults["shutdown_timeout_ms"]))
		return _evaluate_expected_failure(scenario, run_dir, server_log, client_log, "PROCESS_CLEANUP_TIMEOUT", "A child process did not terminate", started, server_pid, client_pid, server_report_path, client_report_path, server_user, client_user, port)
	_active_pids.erase(server_pid); _active_pids.erase(client_pid)
	var server_report := _read_json(server_report_path); var client_report := _read_json(client_report_path)
	var evaluation := _evaluate_success(scenario, server_report, client_report)
	var server_exit := _exit_code(server_pid); var client_exit := _exit_code(client_pid)
	if bool(evaluation.get("success", false)) and (server_exit != 0 or client_exit != 0): evaluation = _failure("PROCESS_EXIT_NONZERO", "Terminal reports succeeded, but exit codes were server=%d client=%d" % [server_exit, client_exit])
	var observed := String(evaluation.get("error_code", ""))
	if String(scenario["expected_outcome"]) == "EXPECTED_FAILURE":
		var expected := String(scenario["expected_failure_code"])
		if bool(evaluation.get("success", false)):
			evaluation = _failure("UNEXPECTED_SCENARIO_SUCCESS", "Scenario succeeded but failure was expected"); observed = "UNEXPECTED_SCENARIO_SUCCESS"
		elif observed == expected: evaluation = {"success": true, "error_code": "", "message": "Expected failure observed: %s" % expected}
	var result := _build_result(scenario, run_dir, server_log, client_log, server_report_path, client_report_path, server_user, client_user, port, started, bool(evaluation.get("success", false)), String(evaluation.get("error_code", "")), String(evaluation.get("message", "")), server_pid, client_pid, server_report, client_report)
	result["observed_failure_code"] = observed
	return result

func _wait_for_state(pid: int, path: String, expected: String, timeout_ms: int, delay_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		var report := _read_json(path); var state := String(report.get("state", ""))
		if state == expected: return {"success": true, "report": report}
		if state in ["FAILED", "REJECTED"]: return _failure("SERVER_FAILED_BEFORE_READY", "Server entered %s before readiness" % state)
		if not _is_running(pid): return _failure("SERVER_EXITED_BEFORE_READY", "Server exited before readiness")
		OS.delay_msec(delay_ms)
	return _failure("READINESS_TIMEOUT", "Server did not reach %s" % expected)

func _wait_for_terminal_pair(server_pid: int, client_pid: int, server_path: String, client_path: String, server_states: Array, client_states: Array, timeout_ms: int, delay_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		var server := _read_json(server_path); var client := _read_json(client_path)
		var ss := String(server.get("state", "")); var cs := String(client.get("state", ""))
		if cs in ["FAILED", "REJECTED"] and cs not in client_states: return _failure("CLIENT_FAILED", "Client entered %s" % cs)
		if ss in ["FAILED", "REJECTED"] and ss not in server_states: return _failure("SERVER_FAILED", "Server entered %s" % ss)
		if ss in server_states and cs in client_states: return {"success": true, "server": server, "client": client}
		if not _is_running(client_pid) and cs not in client_states: return _failure("CLIENT_EXITED_EARLY", "Client exited without a terminal report")
		if not _is_running(server_pid) and ss not in server_states: return _failure("SERVER_EXITED_EARLY", "Server exited without a terminal report")
		OS.delay_msec(delay_ms)
	return _failure("SCENARIO_TIMEOUT", "Scenario exceeded timeout")

func _evaluate_success(scenario: Dictionary, server: Dictionary, client: Dictionary) -> Dictionary:
	if server.is_empty() or client.is_empty(): return _failure("TERMINAL_REPORT_MISSING", "Server or client terminal report is missing")
	for pair in [["server", server, scenario["server_expect"]], ["client", client, scenario["client_expect"]]]:
		for field in Dictionary(pair[2]).keys():
			var actual = _get_path(pair[1], String(field)); var expected = pair[2][field]
			if actual != expected: return _failure("EXPECTATION_FAILED", "%s.%s expected %s, got %s" % [pair[0], field, expected, actual])
	for field in Array(scenario["shared_fields"]):
		if _get_path(server, String(field)) != _get_path(client, String(field)): return _failure("SHARED_FIELD_MISMATCH", "%s differs between server and client" % field)
	for assertion in Array(scenario["assertions"]):
		var source: Dictionary = server if String(assertion["source"]) == "server" else client
		var actual = _get_path(source, String(assertion["actual"]))
		if actual != assertion["equals"]: return _failure("ASSERTION_FAILED", "%s.%s expected %s, got %s" % [assertion["source"], assertion["actual"], assertion["equals"], actual])
	var su := String(server.get("resolved_user_data_dir", "")); var cu := String(client.get("resolved_user_data_dir", ""))
	if su.is_empty() or cu.is_empty() or su == cu: return _failure("USER_DATA_NOT_ISOLATED", "Server and client user data directories must be distinct")
	return {"success": true}

func _evaluate_expected_failure(scenario: Dictionary, run_dir: String, server_log: String, client_log: String, actual_code: String, message: String, started: int, server_pid: int, client_pid: int, server_report_path: String, client_report_path: String, server_user: String, client_user: String, port: int) -> Dictionary:
	var expected := String(scenario["expected_failure_code"]); var cleanup := not _is_running(server_pid) and not _is_running(client_pid)
	var passed := String(scenario["expected_outcome"]) == "EXPECTED_FAILURE" and actual_code == expected and cleanup
	var result_code := "" if passed else (actual_code if cleanup else "PROCESS_CLEANUP_TIMEOUT")
	var result_message := "Expected failure observed: %s" % actual_code if passed else (message if cleanup else "A child process remained alive after cleanup")
	var result := _build_result(scenario, run_dir, server_log, client_log, server_report_path, client_report_path, server_user, client_user, port, started, passed, result_code, result_message, server_pid, client_pid, _read_json(server_report_path), _read_json(client_report_path))
	result["observed_failure_code"] = actual_code if cleanup else "PROCESS_CLEANUP_TIMEOUT"
	return result

func _build_result(scenario: Dictionary, run_dir: String, server_log: String, client_log: String, server_report_path: String, client_report_path: String, server_user: String, client_user: String, port: int, started: int, passed: bool, failure_code: String, message: String, server_pid: int, client_pid: int, server_report: Dictionary, client_report: Dictionary) -> Dictionary:
	return {"id": scenario["id"], "passed": passed, "expected_outcome": scenario["expected_outcome"], "expected_failure_code": scenario["expected_failure_code"], "failure_code": failure_code, "observed_failure_code": failure_code, "message": message, "duration_seconds": float(Time.get_ticks_msec()-started)/1000.0, "port": port, "run_directory": run_dir, "server_report_path": server_report_path, "client_report_path": client_report_path, "server_log": server_log, "client_log": client_log, "server_user_root": server_user, "client_user_root": client_user, "server_pid": server_pid, "client_pid": client_pid, "server_exit_code": _exit_code(server_pid), "client_exit_code": _exit_code(client_pid), "server_running_after_cleanup": server_pid > 0 and _is_running(server_pid), "client_running_after_cleanup": client_pid > 0 and _is_running(client_pid), "server_report": server_report.duplicate(true), "client_report": client_report.duplicate(true)}

func _spawn(script: String, args: Dictionary, log_path: String, user_root: String) -> int:
	var argv: Array[String] = ["--headless", "--path", _project_root, "--log-file", log_path, "--script", script, "--"]
	var keys: Array[String] = []; for key in args.keys(): keys.append(String(key)); keys.sort()
	for key in keys: argv.append("--%s=%s" % [key, args[key]])
	var environment := _capture_environment(["HOME", "XDG_DATA_HOME", "APPDATA", "LOCALAPPDATA"])
	for name in ["HOME", "XDG_DATA_HOME", "APPDATA", "LOCALAPPDATA"]: OS.set_environment(name, user_root)
	var pid := OS.create_process(_executable, argv, false); _restore_environment(environment)
	if pid > 0: _active_pids.append(pid)
	return pid

func _allocate_port(start: int, end: int, host: String) -> int:
	var width := end-start+1; var initial := (OS.get_process_id()+Time.get_ticks_msec()) % width
	for offset in range(width):
		var port := start + ((initial+offset)%width)
		if _used_ports.has(port): continue
		var probe := PacketPeerUDP.new(); var error := probe.bind(port, host); probe.close()
		if error == OK: _used_ports[port] = true; return port
	return 0

func _wait_for_exit(pid: int, timeout_ms: int, delay_ms: int) -> void:
	if pid <= 0: return
	var started := Time.get_ticks_msec()
	while _is_running(pid) and Time.get_ticks_msec()-started <= timeout_ms: OS.delay_msec(delay_ms)

func _kill_and_wait(pid: int, timeout_ms: int) -> bool:
	if pid <= 0 or _finished_pids.has(pid):
		return true
	if not _is_running(pid):
		_active_pids.erase(pid)
		return true
	if OS.kill(pid) != OK:
		return false
	_killed_pids[pid] = true
	# OS.kill() is the cross-platform termination boundary exposed by Godot.
	# Querying OS.is_process_running() after a successful kill emits engine errors
	# on Unix once the child has already been reaped, so record the successful
	# termination atomically and avoid a racy second PID probe.
	OS.delay_msec(mini(maxi(timeout_ms, 0), 25))
	_finished_pids[pid] = true
	_exit_codes[pid] = -998
	_active_pids.erase(pid)
	return true

func _cleanup_all() -> bool:
	var all_stopped := true
	for pid in _active_pids.duplicate():
		if not _kill_and_wait(pid, 1000):
			all_stopped = false
	return all_stopped

func _read_json(path: String) -> Dictionary:
	return AtomicJsonScript.read_value(path)

func _get_path(value: Dictionary, path: String):
	var current = value
	for segment in path.split(".", true):
		if segment.is_empty() or not current is Dictionary or not current.has(segment): return null
		current = current[segment]
	return current

func _merge_args(target: Dictionary, extra: Dictionary) -> void:
	for key in extra.keys(): target[String(key)] = extra[key]

func _capture_environment(names: Array[String]) -> Dictionary:
	var result := {}; for name in names: result[name] = {"present": OS.has_environment(name), "value": OS.get_environment(name)}
	return result

func _restore_environment(captured: Dictionary) -> void:
	for name in captured.keys():
		if bool(captured[name]["present"]): OS.set_environment(String(name), String(captured[name]["value"]))
		else: OS.unset_environment(String(name))

func _exit_code(pid: int) -> int:
	if pid <= 0: return -999
	if _exit_codes.has(pid): return int(_exit_codes[pid])
	if _is_running(pid): return -999
	return int(_exit_codes.get(pid, -999))

func _is_running(pid: int) -> bool:
	if pid <= 0 or _finished_pids.has(pid): return false
	if OS.is_process_running(pid): return true
	_exit_codes[pid] = OS.get_process_exit_code(pid); _finished_pids[pid] = true; return false

func _count_passed(results: Array) -> int:
	var count := 0; for result in results: if bool(result.get("passed", false)): count += 1
	return count

func _scenario_failure(scenario: Dictionary, run_dir: String, server_log: String, client_log: String, code: String, message: String, started: int) -> Dictionary:
	return _build_result(scenario, run_dir, server_log, client_log, "", "", "", "", 0, started, false, code, message, -1, -1, {}, {})

func _failure(code: String, message: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": message}
