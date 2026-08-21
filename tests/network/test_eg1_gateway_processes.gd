extends SceneTree

## EG1 L2: three REAL OS processes — sim server worker, gateway worker and a
## game client worker — connected over real ENET transports. Asserts distinct
## PIDs, readiness handshake via state files, strict identity namespace
## separation in the gateway report, the sim-side operation ledger continuity,
## DIRECT/GATEWAY canonical checksum equality, and clean exit codes.

const Support = preload("res://tools/network/eg1_process_support.gd")

const TIMEOUT_MS: int = 60000
const POLL_DELAY_MS: int = 25

var assertions := 0
var failures: Array[String] = []
var pids: Array[int] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg1-l2][FAIL] %s" % message)


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

	var root: String = ProjectSettings.globalize_path("res://artifacts/test-results/eg1-gateway-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(root)
	var sim_result: String = root.path_join("sim.json")
	var gateway_result: String = root.path_join("gateway.json")
	var client_result: String = root.path_join("client.json")
	for path in [sim_result, gateway_result, client_result]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

	var executable: String = OS.get_executable_path()
	var project_root: String = ProjectSettings.globalize_path("res://")

	# 1) sim server first (owns the backend endpoint)
	var sim_pid: int = _launch(executable, project_root, "eg1_sim_server_worker.gd", [
		"--host=127.0.0.1", "--port=%d" % sim_port,
		"--result-file=%s" % sim_result,
		"--timeout-ms=%d" % TIMEOUT_MS,
		"--mode=GATEWAY",
		"--user-data-dir=%s" % root.path_join("ud-sim"),
	])
	pids.append(sim_pid)
	_assert(sim_pid > 0, "failed to launch sim server worker")
	var sim_listening: Dictionary = _wait_for_state(sim_result, ["LISTENING"], 15000)
	_assert(bool(sim_listening.get("success", false)), "sim server never became LISTENING: %s" % str(sim_listening.get("value")))
	if not bool(sim_listening.get("success", false)):
		_finish()
		return

	# 2) gateway (client-facing listener + backend leg into the sim)
	var gateway_pid: int = _launch(executable, project_root, "eg1_gateway_worker.gd", [
		"--client-host=127.0.0.1", "--client-port=%d" % gateway_port,
		"--sim-host=127.0.0.1", "--sim-port=%d" % sim_port,
		"--result-file=%s" % gateway_result,
		"--timeout-ms=%d" % TIMEOUT_MS,
		"--user-data-dir=%s" % root.path_join("ud-gateway"),
	])
	pids.append(gateway_pid)
	_assert(gateway_pid > 0, "failed to launch gateway worker")
	var gateway_listening: Dictionary = _wait_for_state(gateway_result, ["LISTENING"], 15000)
	_assert(bool(gateway_listening.get("success", false)), "gateway never became LISTENING: %s" % str(gateway_listening.get("value")))

	# 3) game client into the gateway
	var client_pid: int = _launch(executable, project_root, "eg1_client_worker.gd", [
		"--host=127.0.0.1", "--port=%d" % gateway_port,
		"--result-file=%s" % client_result,
		"--timeout-ms=%d" % TIMEOUT_MS,
		"--user-data-dir=%s" % root.path_join("ud-client"),
	])
	pids.append(client_pid)
	_assert(client_pid > 0, "failed to launch client worker")

	var sim_wrap: Dictionary = _wait_for_terminal(sim_result, TIMEOUT_MS + 10000)
	var gateway_wrap: Dictionary = _wait_for_terminal(gateway_result, TIMEOUT_MS + 10000)
	var client_wrap: Dictionary = _wait_for_terminal(client_result, TIMEOUT_MS + 10000)
	var sim: Dictionary = sim_wrap.get("value", {})
	var gateway: Dictionary = gateway_wrap.get("value", {})
	var client: Dictionary = client_wrap.get("value", {})

	# --- process-level facts ---
	_assert(sim_pid != gateway_pid and gateway_pid != client_pid and sim_pid != client_pid,
			"child PIDs are not distinct")
	_assert(String(sim.get("state", "")) == "COMPLETE", "sim worker did not complete: %s" % str(sim))
	_assert(String(gateway.get("state", "")) == "COMPLETE", "gateway worker did not complete: %s" % str(gateway.get("failure_code", gateway)))
	_assert(String(client.get("state", "")) == "COMPLETE", "client worker did not complete: %s" % str(client.get("failure_code", client)))

	# --- sim-side equivalence + ledger continuity ---
	_assert(bool(sim.get("passed", false)), "sim report not passed")
	_assert(bool(sim.get("canonical_equal", false)), "DIRECT vs GATEWAY canonical state differs at the sim")
	var checksum_live := String(sim.get("checksum_live", ""))
	var checksum_direct := String(sim.get("checksum_direct", ""))
	_assert(not checksum_live.is_empty() and checksum_live == checksum_direct,
			"payload hash equality failed (%s vs %s)" % [checksum_live.left(12), checksum_direct.left(12)])
	var ledger: Array = sim.get("operation_ledger", [])
	_assert(ledger.size() == Support.EXPECTED_OPERATION_IDS.size(), "ledger size mismatch: %s" % str(ledger))
	var ledger_sorted: Array[String] = []
	for value in ledger:
		ledger_sorted.append(String(value))
	ledger_sorted.sort()
	var expected_sorted: Array[String] = []
	for value in Support.EXPECTED_OPERATION_IDS:
		expected_sorted.append(String(value))
	expected_sorted.sort()
	_assert(ledger_sorted == expected_sorted, "ledger content mismatch: %s" % str(ledger_sorted))

	# --- client observations ---
	_assert(bool(client.get("passed", false)), "client report not passed")
	_assert(int(client.get("results_received", 0)) == 4, "client received wrong result count")
	_assert(bool(client.get("detached_ack", false)), "client did not receive DETACHED ack")
	_assert(String(client.get("gateway_session_id", "")).begins_with("gateway-session/eg1/"),
			"client saw a gateway session id outside its namespace")

	# --- gateway report identity namespaces ---
	var identity: Dictionary = gateway.get("identity", {})
	var counters: Dictionary = gateway.get("counters", {})
	_assert(not identity.is_empty(), "gateway report missing identity")
	var peer_ids: Array = identity.get("transport_peer_ids", [])
	var session_ids: Array = identity.get("gateway_session_ids", [])
	var client_session_ids: Array = identity.get("client_session_ids", [])
	var slots: Array = identity.get("session_slots", [])
	_assert(peer_ids.size() >= 2, "gateway did not record both transport peers")
	var all_namespaces_ok := true
	for value in peer_ids:
		if not String(value).begins_with("peer/enet/"):
			all_namespaces_ok = false
	for value in session_ids:
		if not String(value).begins_with("gateway-session/") or String(value).begins_with("peer/enet/"):
			all_namespaces_ok = false
	for value in client_session_ids:
		if not String(value).begins_with("client-session/") or String(value).begins_with("gateway-session/"):
			all_namespaces_ok = false
	_assert(all_namespaces_ok, "identity namespaces collided: %s" % str(identity))
	# JSON round-trips may surface integers as floats; require exact integral values.
	var slots_integral := slots.size() > 0
	for value in slots:
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or int(value) != float(value):
			slots_integral = false
	_assert(slots_integral, "session_slot is not an integer")
	var slot_is_player_id := false
	for value in slots:
		if value is String and String(value).begins_with("player/"):
			slot_is_player_id = true
	_assert(not slot_is_player_id, "a session_slot leaked into the player namespace")
	# domain fields must be absent from the report entirely
	var report_text := JSON.stringify(gateway)
	for forbidden in ["logical_player_id", "player_entity_id", "canonical_item_graph", "\"items\"", "inventories"]:
		_assert(not report_text.contains(forbidden), "gateway report leaked domain field %s" % forbidden)

	# --- forwarding counters ---
	var forwarder_counters: Dictionary = counters.get("forwarder", {})
	_assert(int(forwarder_counters.get("forwarded_client_to_world", 0)) == 4,
			"gateway forwarded wrong upstream count: %s" % str(forwarder_counters))
	_assert(int(forwarder_counters.get("dropped_client_to_world", -1)) == 0
			and int(forwarder_counters.get("dropped_world_to_client", -1)) == 0,
			"gateway dropped frames across processes")
	_assert(int(counters.get("session_control_attached", 0)) == 1
			and int(counters.get("session_control_detached", 0)) == 1,
			"session control lifecycle incomplete at gateway: %s" % str(counters))
	var sessions: Array = gateway.get("sessions", [])
	if sessions.size() == 1:
		_assert(String(sessions[0]["binding_state"]) == "DETACHED", "session row was not detached before shutdown")

	_finish()


func _finish() -> void:
	_cleanup()
	var summary := {
		"test": "eg1_gateway_processes_l2",
		"verdict": "PASS" if failures.is_empty() else "FAIL",
		"assertions": assertions,
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if failures.is_empty():
		print("[eg1-l2] L2 PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg1-l2] L2 FAIL")
		quit(1)


func _cleanup() -> void:
	for pid in pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
