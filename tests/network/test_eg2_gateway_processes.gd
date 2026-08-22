extends SceneTree

## EG2 L2: REAL OS processes over real ENET — sim server worker, gateway
## worker (owning the auth service + identifier-only directory + placement
## flow), and TWO sequential game-client processes sharing one logical
## identity. Phase A CONNECTs -> AUTH -> PLACE -> WORLD_READY -> scenario ops
## -> DETACH. Phase B reconnects on a NEW connection, resumes via the rotated
## token, and must observe the SAME logical_player_id/player_entity_id while
## the sim proves world-state continuity (resume probe == phase-A checkpoint)
## and combined DIRECT/GATEWAY canonical equality. Every client-leg frame both
## processes received is scanned for server-endpoint disclosure.

const Support = preload("res://tools/network/eg2_process_support.gd")

const TIMEOUT_MS: int = 60000
const POLL_DELAY_MS: int = 25

const FORBIDDEN_SUBSTRINGS: Array[String] = [
	"127.0.0.1", "localhost", "0.0.0.0", "::1",
]
const FORBIDDEN_KEYS: Array[String] = [
	"host", "hostname", "port", "endpoint", "address", "ip", "url", "bind",
]

var assertions := 0
var failures: Array[String] = []
var pids: Array[int] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg2-l2][FAIL] %s" % message)


func _find_available_port(excluded: Array = []) -> int:
	var start: int = 24000 + (OS.get_process_id() % 20000)
	for offset in range(200):
		var port: int = 20000 + ((start + offset - 20000) % 40000)
		if excluded.has(port):
			continue
		var probe := PacketPeerUDP.new()
		var error: Error = probe.bind(port, "127.0.0.1")
		probe.close()
		if error == OK:
			return port
	return 0


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _wait_for_state(path: String, states: Array, timeout_ms: int) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		var value: Dictionary = _read_json(path)
		if states.has(String(value.get("state", ""))):
			return {"success": true, "value": value}
		OS.delay_msec(POLL_DELAY_MS)
	return {"success": false, "value": _read_json(path)}


func _wait_for_terminal(path: String, timeout_ms: int) -> Dictionary:
	return _wait_for_state(path, ["COMPLETE", "FAILED"], timeout_ms)


func _launch(executable: String, project_root: String, worker: String, args: Array) -> int:
	var full_args: Array = [
		"--headless", "--path", project_root,
		"--script", "res://tools/network/%s" % worker, "--",
	]
	full_args.append_array(args)
	return OS.create_process(executable, full_args, false)


func _init() -> void:
	var sim_port: int = _find_available_port()
	var gateway_port: int = _find_available_port([sim_port])
	_assert(sim_port > 0 and gateway_port > 0 and sim_port != gateway_port, "port allocation failed")
	if sim_port <= 0 or gateway_port <= 0:
		_finish()
		return

	var root: String = ProjectSettings.globalize_path("res://artifacts/test-results/eg2-gateway-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(root)
	var sim_result: String = root.path_join("sim.json")
	var gateway_result: String = root.path_join("gateway.json")
	var client_a_result: String = root.path_join("client-a.json")
	var client_b_result: String = root.path_join("client-b.json")

	var executable: String = OS.get_executable_path()
	var project_root: String = ProjectSettings.globalize_path("res://")

	# 1) sim server first (owns the backend endpoint)
	var sim_pid: int = _launch(executable, project_root, "eg2_sim_server_worker.gd", [
		"--host=127.0.0.1", "--port=%d" % sim_port,
		"--result-file=%s" % sim_result,
		"--timeout-ms=%d" % TIMEOUT_MS,
		"--user-data-dir=%s" % root.path_join("ud-sim"),
	])
	pids.append(sim_pid)
	_assert(sim_pid > 0, "failed to launch sim server worker")
	var sim_listening: Dictionary = _wait_for_state(sim_result, ["LISTENING"], 15000)
	_assert(bool(sim_listening.get("success", false)), "sim server never became LISTENING")
	if not bool(sim_listening.get("success", false)):
		_finish()
		return

	# 2) gateway (client-facing listener + backend leg into the sim)
	var gateway_pid: int = _launch(executable, project_root, "eg2_gateway_worker.gd", [
		"--client-host=127.0.0.1", "--client-port=%d" % gateway_port,
		"--sim-host=127.0.0.1", "--sim-port=%d" % sim_port,
		"--result-file=%s" % gateway_result,
		"--timeout-ms=%d" % int(TIMEOUT_MS * 2),
		"--user-data-dir=%s" % root.path_join("ud-gateway"),
	])
	pids.append(gateway_pid)
	_assert(gateway_pid > 0, "failed to launch gateway worker")
	var gateway_listening: Dictionary = _wait_for_state(gateway_result, ["LISTENING"], 15000)
	_assert(bool(gateway_listening.get("success", false)), "gateway never became LISTENING")
	if not bool(gateway_listening.get("success", false)):
		_finish()
		return
	var tickets_value = gateway_listening["value"].get("tickets", {}).get(Support.CLIENT_SESSION_ID, [])
	var tickets: Array = tickets_value if tickets_value is Array else []
	_assert(tickets.size() >= 2, "gateway did not publish preminted tickets")

	# 3) client A: fresh placement phase
	var ticket_a := str(tickets[0]) if tickets.size() > 0 else "auth-ticket/eg2/none"
	var ticket_b := str(tickets[1]) if tickets.size() > 1 else "auth-ticket/eg2/none"
	var client_a_pid: int = _launch(executable, project_root, "eg2_client_worker.gd", [
		"--host=127.0.0.1", "--port=%d" % gateway_port,
		"--auth-ticket=%s" % ticket_a,
		"--resume-token=",
		"--phase=A",
		"--peer-id=peer/enet/eg2-client-a",
		"--wire-session=transport-session/eg2/l2-client-a",
		"--result-file=%s" % client_a_result,
		"--timeout-ms=%d" % TIMEOUT_MS,
		"--user-data-dir=%s" % root.path_join("ud-client-a"),
	])
	pids.append(client_a_pid)
	_assert(client_a_pid > 0, "failed to launch client A worker")
	var client_a_wrap: Dictionary = _wait_for_terminal(client_a_result, TIMEOUT_MS + 10000)
	var client_a: Dictionary = client_a_wrap.get("value", {})
	_assert(String(client_a.get("state", "")) == "COMPLETE", "client A did not complete: %s" % str(client_a.get("failure_code", client_a)))
	if not bool(client_a.get("passed", false)) or String(client_a.get("resume_token_out", "")).is_empty():
		_assert(false, "client A produced no resume token to reconnect with")
		_finish()
		return

	# 4) client B: NEW connection, resumes via the rotated token
	var client_b_pid: int = _launch(executable, project_root, "eg2_client_worker.gd", [
		"--host=127.0.0.1", "--port=%d" % gateway_port,
		"--auth-ticket=%s" % ticket_b,
		"--resume-token=%s" % str(client_a["resume_token_out"]),
		"--phase=B",
		"--peer-id=peer/enet/eg2-client-b",
		"--wire-session=transport-session/eg2/l2-client-b",
		"--result-file=%s" % client_b_result,
		"--timeout-ms=%d" % TIMEOUT_MS,
		"--user-data-dir=%s" % root.path_join("ud-client-b"),
	])
	pids.append(client_b_pid)
	_assert(client_b_pid > 0, "failed to launch client B worker")

	var sim_wrap: Dictionary = _wait_for_terminal(sim_result, int(TIMEOUT_MS * 2) + 10000)
	var gateway_wrap: Dictionary = _wait_for_terminal(gateway_result, int(TIMEOUT_MS * 2) + 10000)
	var client_b_wrap: Dictionary = _wait_for_terminal(client_b_result, TIMEOUT_MS + 10000)
	var sim: Dictionary = sim_wrap.get("value", {})
	var gateway: Dictionary = gateway_wrap.get("value", {})
	var client_b: Dictionary = client_b_wrap.get("value", {})

	# --- process-level facts ---
	_assert(sim_pid != gateway_pid and gateway_pid != client_a_pid \
			and client_a_pid != client_b_pid and sim_pid != client_a_pid,
			"child PIDs are not distinct")
	_assert(String(sim.get("state", "")) == "COMPLETE", "sim worker did not complete")
	_assert(String(gateway.get("state", "")) == "COMPLETE", "gateway worker did not complete: %s" % str(gateway.get("failure_code", gateway)))
	_assert(String(client_b.get("state", "")) == "COMPLETE", "client B did not complete: %s" % str(client_b.get("failure_code", client_b)))

	# --- sim-side continuity + equivalence ---
	_assert(bool(sim.get("passed", false)), "sim report not passed")
	_assert(bool(sim.get("canonical_equal", false)), "DIRECT vs GATEWAY canonical state differs at the sim")
	var checkpoint := String(sim.get("checkpoint_checksum", ""))
	var resume_checksum := String(sim.get("resume_checksum", ""))
	_assert(not checkpoint.is_empty(), "sim never took the phase-A checkpoint")
	_assert(not resume_checksum.is_empty(), "sim never took the resume probe")
	_assert(resume_checksum == checkpoint, "world state changed between detach and resume")
	var live_checksum := String(sim.get("checksum_live", ""))
	var direct_checksum := String(sim.get("checksum_direct", ""))
	_assert(not live_checksum.is_empty() and live_checksum == direct_checksum,
			"payload hash equality failed (%s vs %s)" % [live_checksum.left(12), direct_checksum.left(12)])
	var ledger_sorted: Array[String] = []
	for value in sim.get("operation_ledger", []):
		ledger_sorted.append(String(value))
	ledger_sorted.sort()
	_assert(ledger_sorted == Support.expected_operation_ids_all(),
			"ledger content mismatch: %s" % str(ledger_sorted))
	var world_state: Dictionary = sim.get("world_state", {})
	_assert(String(world_state.get("state_checksum", "")) == live_checksum,
			"world-state projection lost the live checksum")

	# --- client observations: identity preserved across the reconnect ---
	_assert(bool(client_a.get("passed", false)), "client A report not passed")
	_assert(bool(client_b.get("passed", false)), "client B report not passed")
	var world_ready_a: Dictionary = client_a.get("world_ready", {})
	var world_ready_b: Dictionary = client_b.get("world_ready", {})
	_assert(String(world_ready_a.get("route_role", "")) == "ACTIVE", "phase A WORLD_READY missing ACTIVE role")
	_assert(bool(world_ready_b.get("resumed", false)) == true, "phase B WORLD_READY did not report resumed=true")
	_assert(bool(world_ready_a.get("resumed", false)) == false, "phase A WORLD_READY wrongly reported resumed=true")
	_assert(String(world_ready_a.get("authority_id", "")) == Support.AUTHORITY_ID
			and String(world_ready_b.get("authority_id", "")) == Support.AUTHORITY_ID,
			"WORLD_READY lost the directory authority identifier")
	_assert(String(world_ready_a.get("server_instance_id", "")) == Support.SERVER_INSTANCE_ID
			and String(world_ready_b.get("server_instance_id", "")) == Support.SERVER_INSTANCE_ID,
			"WORLD_READY lost the server instance identifier")
	_assert(String(world_ready_a.get("logical_player_id", "")).begins_with("player/")
			and String(world_ready_a.get("logical_player_id", "")) == String(world_ready_b.get("logical_player_id", "")),
			"resume did not preserve the logical player id")
	_assert(String(world_ready_a.get("player_entity_id", "")) == String(world_ready_b.get("player_entity_id", "")),
			"resume did not preserve the player entity id")
	_assert(String(world_ready_b.get("gateway_session_id", "")) != String(world_ready_a.get("gateway_session_id", "")),
			"resume reused the previous gateway session id")
	_assert(String(client_b.get("resume_token_out", "")) != String(client_a.get("resume_token_out", "")),
			"resume did not rotate the resume token")
	_assert(int(client_a.get("results_received", -1)) == 3, "client A wrong result count")
	_assert(int(client_b.get("results_received", -1)) == 3, "client B wrong result count")
	_assert(bool(client_a.get("detached_ack", false)) and bool(client_b.get("detached_ack", false)),
			"clients did not receive DETACHED acks")

	# --- ENDPOINT DISCLOSURE FENCE over every client-leg frame ---
	var corpus := ""
	for report in [client_a, client_b]:
		for frame_text_value in report.get("frames_received", []):
			var frame_text := str(frame_text_value)
			corpus += frame_text
			var parsed = JSON.parse_string(frame_text)
			if parsed is Dictionary:
				_scan_keys_recursive(Dictionary(parsed).get("payload", {}))
		for frame_text_value in report.get("frames_sent", []):
			corpus += str(frame_text_value)
	_assert(corpus.contains("server-instance/") and corpus.contains("authority/"),
			"fence corpus lacks the identifier projection it guards")
	for needle in FORBIDDEN_SUBSTRINGS:
		_assert(not corpus.contains(needle), "client leg leaked endpoint substring '%s'" % needle)
	for report_path in [gateway_result, sim_result]:
		var report_text := JSON.stringify(_read_json(report_path))
		for needle in FORBIDDEN_SUBSTRINGS:
			_assert(not report_text.contains(needle), "%s leaked '%s'" % [report_path.get_file(), needle])

	# --- gateway report: placement lifecycle + namespaces ---
	var counters: Dictionary = gateway.get("counters", {})
	_assert(int(counters.get("placement_handled", -1)) == 4, "placement handled counter mismatch: %s" % str(counters.get("placement_handled")))
	_assert(int(counters.get("placement_rejected", -1)) == 0, "gateway rejected placement frames")
	_assert(int(counters.get("session_control_detached", -1)) == 2, "detach lifecycle incomplete at gateway")
	_assert(int(counters.get("session_control_attached", -1)) == 0, "EG1 HELLO attach unexpectedly used")
	var forwarder_counters: Dictionary = counters.get("forwarder", {})
	_assert(int(forwarder_counters.get("forwarded_client_to_world", 0)) == 6,
			"gateway forwarded wrong upstream count: %s" % str(forwarder_counters))
	_assert(int(forwarder_counters.get("dropped_client_to_world", -1)) == 0
			and int(forwarder_counters.get("dropped_world_to_client", -1)) == 0,
			"gateway dropped frames across processes")
	var flow_report: Dictionary = gateway.get("placement_flow", {})
	var flow_counters: Dictionary = flow_report.get("counters", {})
	# Client B resumed the SAME client session, so its placement superseded
	# client A's row: exactly one live row remains, and it is B's.
	_assert(int(flow_counters.get("placements_created", -1)) == 1, "flow created counter mismatch")
	_assert(int(flow_counters.get("placements_resumed", -1)) == 1, "flow resumed counter mismatch")
	_assert(int(flow_counters.get("placements_degraded_warm", -1)) == 0, "unexpected WARM degradation")
	var identity: Dictionary = gateway.get("identity", {})
	for value in identity.get("gateway_session_ids", []):
		_assert(String(value).begins_with("gateway-session/"), "gateway session id outside its namespace")
	for value in identity.get("client_session_ids", []):
		_assert(String(value).begins_with("client-session/"), "client session id outside its namespace")
	var sessions: Array = gateway.get("sessions", [])
	_assert(sessions.size() == 1, "expected one surviving gateway session row: %d" % sessions.size())
	for row_value in sessions:
		var row: Dictionary = row_value
		_assert(String(row.get("gateway_session_id", "")) == String(world_ready_b.get("gateway_session_id", "")),
				"surviving row is not client B's resumed session")
		_assert(String(row.get("binding_state", "")) == "DETACHED", "session row was not detached before shutdown")
		var slot = row.get("session_slot", -1)
		_assert((typeof(slot) in [TYPE_INT, TYPE_FLOAT]) and int(slot) == float(slot),
				"session_slot is not an integer")

	# --- children self-exited; teardown kills any survivor ---
	for pid in pids:
		var exit_deadline: int = Time.get_ticks_msec() + 5000
		while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < exit_deadline:
			OS.delay_msec(POLL_DELAY_MS)
		_assert(pid <= 0 or not OS.is_process_running(pid), "worker process %d lingered" % pid)

	_finish()


func _scan_keys_recursive(value) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			for raw_key in value.keys():
				var key := String(raw_key)
				_assert(not FORBIDDEN_KEYS.has(key), "forbidden endpoint-ish key '%s' on the client leg" % key)
				_scan_keys_recursive(value[raw_key])
		TYPE_ARRAY:
			for index in range(value.size()):
				_scan_keys_recursive(value[index])


func _finish() -> void:
	_cleanup()
	var summary := {
		"test": "eg2_gateway_processes_l2",
		"verdict": "PASS" if failures.is_empty() else "FAIL",
		"assertions": assertions,
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if failures.is_empty():
		print("[eg2-l2] L2 PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg2-l2] L2 FAIL")
		quit(1)


func _cleanup() -> void:
	for pid in pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
