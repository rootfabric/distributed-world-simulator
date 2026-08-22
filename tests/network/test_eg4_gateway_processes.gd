extends SceneTree

## EG4 L2: REAL OS processes over real ENET proving MULTI-SOURCE PROJECTION
## AGGREGATION through ONE client connection:
##   client -> gateway -> Sim A (ACTIVE authority)
##                     -> Sim B (PROJECTION source)
## Predicates under proof:
##   (a) the client keeps exactly ONE transport for the whole run while BOTH an
##       authoritative snapshot stream (Sim A) AND a read-only projection
##       stream (Sim B) reach it (frame counts per channel);
##   (b) a WRITE INJECTION from the projection source is rejected end to end:
##       the gateway fence counters increment and the client's operation-
##       receipt accounting shows NO extra receipt;
##   (c) KILLING Sim B mid-run does not disconnect gameplay: authoritative
##       snapshots continue arriving AFTER the kill timestamp;
##   (d) stale upstream subscriptions drain to ZERO within the deadline after
##       withdrawal (gateway telemetry);
##   (e) distinct PIDs; teardown kills survivors.

const Support = preload("res://tools/network/eg4_process_support.gd")

const TIMEOUT_MS: int = 60000
const POLL_DELAY_MS: int = 25

const FORBIDDEN_SUBSTRINGS: Array[String] = [
	"127.0.0.1", "localhost", "0.0.0.0", "::1",
]

var assertions := 0
var failures: Array[String] = []
var pids: Array[int] = []
var _started_ms: int = 0


func _process(_delta: float) -> bool:
	if _started_ms > 0 and Time.get_ticks_msec() - _started_ms > 240000:
		print("[eg4-l2] WATCHDOG TIMEOUT")
		_cleanup()
		quit(1)
		return true
	return false


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg4-l2][FAIL] %s" % message)


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
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _wait_for_state(path: String, states: Array, timeout_ms: int) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		var value: Dictionary = _read_json(path)
		if states.has(String(value.get("state", ""))):
			return {"success": true, "value": value}
		OS.delay_msec(POLL_DELAY_MS)
	return {"success": false, "value": _read_json(path)}


func _launch(executable: String, project_root: String, worker: String, args: Array) -> int:
	var full_args: Array = [
		"--headless", "--path", project_root,
		"--script", "res://tools/network/%s" % worker, "--",
	]
	full_args.append_array(args)
	return OS.create_process(executable, full_args, false)


func _wait_until(predicate: Callable, timeout_ms: int) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		if bool(predicate.call()):
			return {"success": true}
		OS.delay_msec(POLL_DELAY_MS)
	return {"success": false}


func _write_marker(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("GO")
		file.close()


func _init() -> void:
	_started_ms = Time.get_ticks_msec()
	var sim_a_port: int = _find_available_port()
	var sim_b_port: int = _find_available_port([sim_a_port])
	var gateway_port: int = _find_available_port([sim_a_port, sim_b_port])
	_assert(sim_a_port > 0 and sim_b_port > 0 and gateway_port > 0
			and sim_a_port != sim_b_port and gateway_port != sim_a_port,
			"port allocation failed")
	if sim_a_port <= 0 or sim_b_port <= 0 or gateway_port <= 0:
		_finish()
		return

	var root: String = ProjectSettings.globalize_path("res://artifacts/test-results/eg4-gateway-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(root)
	var sim_a_result: String = root.path_join("sim-a.json")
	var sim_b_result: String = root.path_join("sim-b.json")
	var gateway_result: String = root.path_join("gateway.json")
	var player_bindings: String = root.path_join("player-bindings.json")
	var client_result: String = root.path_join("client-alpha.json")

	var executable: String = OS.get_executable_path()
	var project_root: String = ProjectSettings.globalize_path("res://")

	# 1) Sim B first (PROJECTION source).
	var sim_b_pid: int = _launch(executable, project_root, "eg4_sim_server_worker.gd", [
		"--role=PROJECTION",
		"--host=127.0.0.1", "--port=%d" % sim_b_port,
		"--result-file=%s" % sim_b_result,
		"--stay-alive=1",
		"--timeout-ms=%d" % int(TIMEOUT_MS * 3),
		"--user-data-dir=%s" % root.path_join("ud-sim-b"),
	])
	pids.append(sim_b_pid)
	_assert(sim_b_pid > 0, "failed to launch Sim B worker")
	var sim_b_listening: Dictionary = _wait_for_state(sim_b_result, ["LISTENING"], 15000)
	_assert(bool(sim_b_listening.get("success", false)), "Sim B never became LISTENING")
	if not bool(sim_b_listening.get("success", false)):
		_finish()
		return

	# 2) Sim A (ACTIVE authority).
	var sim_a_pid: int = _launch(executable, project_root, "eg4_sim_server_worker.gd", [
		"--role=ACTIVE",
		"--host=127.0.0.1", "--port=%d" % sim_a_port,
		"--result-file=%s" % sim_a_result,
		"--player-binding-file=%s" % player_bindings,
		"--expected-operations=2",
		"--expected-movements=4",
		"--stay-alive=1",
		"--timeout-ms=%d" % int(TIMEOUT_MS * 3),
		"--user-data-dir=%s" % root.path_join("ud-sim-a"),
	])
	pids.append(sim_a_pid)
	_assert(sim_a_pid > 0, "failed to launch Sim A worker")
	var sim_a_listening: Dictionary = _wait_for_state(sim_a_result, ["LISTENING"], 15000)
	_assert(bool(sim_a_listening.get("success", false)), "Sim A never became LISTENING")
	if not bool(sim_a_listening.get("success", false)):
		_finish()
		return

	# 3) Gateway: one client leg + TWO bounded upstream legs.
	var demand_worlds: Array[String] = Support.demand_projection_worlds(4)
	var gateway_pid: int = _launch(executable, project_root, "eg4_gateway_worker.gd", [
		"--client-host=127.0.0.1", "--client-port=%d" % gateway_port,
		"--sim-a-host=127.0.0.1", "--sim-a-port=%d" % sim_a_port,
		"--sim-b-host=127.0.0.1", "--sim-b-port=%d" % sim_b_port,
		"--premint-client-sessions=client-session/eg4/alpha",
		"--expected-placements=1",
		"--expected-detachments=1",
		"--demand-projection-worlds=4",
		"--source-loss-timeout-ms=%d" % Support.SOURCE_LOSS_TIMEOUT_MS,
		"--result-file=%s" % gateway_result,
		"--player-binding-file=%s" % player_bindings,
		"--timeout-ms=%d" % int(TIMEOUT_MS * 3),
		"--user-data-dir=%s" % root.path_join("ud-gateway"),
	])
	pids.append(gateway_pid)
	_assert(gateway_pid > 0, "failed to launch gateway worker")
	var gateway_listening: Dictionary = _wait_for_state(gateway_result, ["LISTENING"], 15000)
	_assert(bool(gateway_listening.get("success", false)), "gateway never became LISTENING")
	if not bool(gateway_listening.get("success", false)):
		_finish()
		return
	var tickets: Dictionary = gateway_listening["value"].get("tickets", {})
	_assert(int(tickets.get("client-session/eg4/alpha", []).size()) >= 1,
			"gateway did not publish the preminted ticket table")

	# 4) THE client: single connection, subscribe, wave 1, park.
	var client_args: Array = [
		"--host=127.0.0.1", "--port=%d" % gateway_port,
		"--result-file=%s" % client_result,
		"--timeout-ms=%d" % int(TIMEOUT_MS * 2),
		"--user-data-dir=%s" % root.path_join("ud-client"),
		"--auth-ticket=%s" % str(tickets["client-session/eg4/alpha"][0]),
		"--client-session-id=client-session/eg4/alpha",
		"--peer-id=peer/enet/eg4-client-alpha",
		"--wire-session=transport-session/eg4/l2-client-alpha",
		"--ops-per-wave=2",
		"--movements-per-wave=2",
		"--movement-seq-base=100",
		"--demand-worlds=%s" % ",".join(demand_worlds),
		"--hold-release-marker-file=%s" % root.path_join("hold-release.marker"),
	]
	var client_pid: int = _launch(executable, project_root, "eg4_client_worker.gd", client_args)
	pids.append(client_pid)
	_assert(client_pid > 0, "failed to launch client worker")

	# Wait until the projection fan-in is visibly flowing to the ONE client.
	var flowing: Dictionary = _wait_until(func() -> bool:
		var heartbeat: Dictionary = _read_json(client_result + ".heartbeat.json")
		return int(Dictionary(heartbeat.get("channel_counts", {})).get("WORLD_PROJECTION", 0)) >= 5
	, 25000)
	_assert(bool(flowing.get("success", false)), "projection stream never reached the client")

	# Let the mutation-shaped injection attempts land mid-stream (the source
	# attempts one SOLO injection every inject-after-frames frames PER pair,
	# starting with each pair's very first frame: frames_sent % N == 0, so
	# attempt #1 rides the first beat), then KILL Sim B.
	OS.delay_msec(1500)
	var sim_b_killed_at_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	if OS.is_process_running(sim_b_pid):
		OS.kill(sim_b_pid)

	# 5) Release wave 2: gameplay MUST continue without the projection source;
	#    then the client withdraws its demand and detaches.
	_write_marker(root.path_join("hold-release.marker"))
	var client_wrap: Dictionary = _wait_for_state(client_result, ["COMPLETE", "FAILED"], int(TIMEOUT_MS * 2))
	var client_report: Dictionary = client_wrap.get("value", {})

	# 6) The gateway finishes once placement + detach + source-loss handling +
	#    zero stale subscriptions are ALL observable in its telemetry.
	var gateway_wrap: Dictionary = _wait_for_state(gateway_result, ["COMPLETE", "FAILED"], int(TIMEOUT_MS * 2))
	var gateway_report: Dictionary = gateway_wrap.get("value", {})
	var sim_a: Dictionary = _read_json(sim_a_result)
	var sim_b_heartbeat: Dictionary = _read_json(sim_b_result + ".heartbeat.json")

	# --- process-level facts ---------------------------------------------------
	_assert(sim_a_pid != sim_b_pid and gateway_pid != client_pid and sim_b_pid != gateway_pid,
			"child PIDs are not distinct")
	_assert(String(client_report.get("state", "")) == "COMPLETE",
			"client did not complete: %s" % str(client_report.get("failure_code", client_report)))
	_assert(String(gateway_report.get("state", "")) == "COMPLETE",
			"gateway did not complete: %s" % str(gateway_report.get("failure_code", gateway_report)))
	_assert(String(sim_a.get("state", "")) == "DRAINING",
			"Sim A never reached DRAINING: %s" % str(sim_a.get("failure_code", sim_a)))

	# --- (a) TWO sources, ONE client transport ----------------------------------
	var channel_counts: Dictionary = client_report.get("channel_counts", {})
	_assert(int(channel_counts.get("WORLD_PROJECTION", 0)) >= 5,
			"client received too few projection frames: %s" % str(channel_counts))
	_assert(int(channel_counts.get("AUTHORITATIVE_SNAPSHOT", 0)) >= 2,
			"client received too few authoritative snapshots: %s" % str(channel_counts))
	_assert(int(channel_counts.get("SESSION_CONTROL", 0)) >= 2,
			"client lost control-plane traffic: %s" % str(channel_counts))
	var node_report: Dictionary = gateway_report.get("gateway_node", {})
	var client_peers: Array[String] = []
	for row_value in node_report.get("sessions", []):
		var peer := String(Dictionary(row_value)["client_transport_peer_id"])
		if not client_peers.has(peer):
			client_peers.append(peer)
	_assert(client_peers.size() == 1,
			"client transport count must be exactly ONE: %s" % str(client_peers))
	var sim_a_peers: Array = sim_a.get("physical_peers_seen", [])
	_assert((sim_a_peers as Array).size() == 1, "Sim A saw more than one physical peer")

	# --- (b) write injection rejected end to end --------------------------------
	var aggregation: Dictionary = gateway_report.get("projection_aggregation", {})
	var fence_counters: Dictionary = aggregation.get("counters", {})
	_assert(int(fence_counters.get("rejected_mutation_shaped", 0)) >= 1,
			"gateway did not reject the mutation-shaped projection frame")
	_assert(fence_counters.has("rejected_not_read_only") and fence_counters.has("rejected_injection"),
			"fence counter surface unavailable: %s" % str(fence_counters.keys()))
	_assert(int(sim_b_heartbeat.get("injections_sent", 0)) >= 1,
			"Sim B never attempted the write injection")
	var injected_leaked := false
	for receipt_value in client_report.get("receipts", []):
		# Producer id (eg4_process_support.mutation_injection_envelope):
		# "operation/eg4/inj-%06d" — the needle must match it exactly.
		if String(Dictionary(receipt_value)["operation_id"]).contains("operation/eg4/inj-"):
			injected_leaked = true
	_assert(not injected_leaked, "the injected write REACHED the client as a receipt")
	_assert(int(client_report.get("receipt_count", -1)) == 6,
			"operation receipt accounting mismatch: %s" % str(client_report.get("receipt_count", -1)))

	# --- (c) projection source loss does not disconnect gameplay -----------------
	var lost_value: Variant = gateway_report.get("source_lost_reported", false)
	_assert(typeof(lost_value) == TYPE_BOOL and bool(lost_value),
			"gateway telemetry never reported the projection source lost")
	var last_snapshot_at_ms: int = int(client_report.get("last_snapshot_at_ms", -1))
	_assert(last_snapshot_at_ms > sim_b_killed_at_ms,
			"no authoritative snapshot arrived AFTER the projection source died (%d vs %d)" % [last_snapshot_at_ms, sim_b_killed_at_ms])
	var upstream_sources: Array = aggregation.get("upstream_set", {}).get("sources", [])
	_assert(not (upstream_sources as Array).has(Support.AUTHORITY_ID_EG4_B),
			"lost projection source still listed as active upstream")

	# --- (d) STALE_UPSTREAM_SUBSCRIPTIONS_EVENTUALLY_ZERO ------------------------
	_assert(aggregation.get("stale_subscription_count", -1) == 0,
			"gateway telemetry still reports stale subscriptions: %s" % str(aggregation.get("stale_subscriptions", [])))
	var interest: Dictionary = gateway_report.get("interest_aggregation", {})
	_assert(int(interest.get("stale_subscription_count", -1)) == 0,
			"interest aggregation still reports stale demand")

	# --- ENDPOINT DISCLOSURE FENCE over the client-leg corpus --------------------
	var corpus := ""
	for frame_entry_value in client_report.get("frames", []):
		corpus += str(frame_entry_value)
	for needle in FORBIDDEN_SUBSTRINGS:
		_assert(not corpus.contains(needle), "client leg leaked endpoint substring '%s'" % needle)

	# --- GATEWAY_OWNERSHIP_DECISIONS_ZERO ----------------------------------------
	# The gateway made NO canonical gameplay decision of its own: the authority
	# ledger contains EXACTLY what the client asked for (no extra operations,
	# no gateway-authored writes), and every forwarding failure counter is 0.
	var node_counters: Dictionary = node_report.get("counters", {})
	var failure_codes: Dictionary = node_counters.get("failure_codes", {})
	var failures_clean := true
	for channel_key in failure_codes.keys():
		if not (Dictionary(failure_codes[String(channel_key)]).is_empty() if typeof(failure_codes[String(channel_key)]) == TYPE_DICTIONARY else (failure_codes[String(channel_key)] as Array).is_empty()):
			failures_clean = false
	_assert(failures_clean, "gateway recorded forwarding failure codes: %s" % str(failure_codes))
	var expected_op_ids: Array[String] = []
	for receipt_value in client_report.get("receipts", []):
		var receipt: Dictionary = receipt_value
		var op_id := String(receipt.get("operation_id", ""))
		if op_id.begins_with("operation/eg4/l2/alpha-w1-") and not op_id.contains("move-ack"):
			expected_op_ids.append(op_id)
	var ledger_ops: Array[String] = []
	var ledger_sessions: Array[String] = []
	for session_key_value in Dictionary(sim_a.get("operation_ledger_by_session", {})).keys():
		ledger_sessions.append(String(session_key_value))
		for id_value in Dictionary(sim_a["operation_ledger_by_session"])[String(session_key_value)]:
			ledger_ops.append(String(id_value))
	ledger_ops.sort()
	expected_op_ids.sort()
	_assert(ledger_sessions.size() == 1,
			"Sim A served sessions other than THE single client session: %s" % str(ledger_sessions))
	_assert(ledger_ops == expected_op_ids,
			"authority ledger diverged from client demand (gateway ownership leak): %s vs %s" % [str(ledger_ops), str(expected_op_ids)])

	# --- BOUNDED_PER_SESSION_QUEUES ------------------------------------------------
	var mux_report: Dictionary = node_report.get("backend_multiplexer", {})
	var mux_options: Dictionary = mux_report.get("options", {})
	var max_messages := int(mux_options.get("max_session_messages", 0))
	var max_bytes := int(mux_options.get("max_session_bytes", 0))
	_assert(max_messages > 0 and max_bytes > 0, "multiplexer queue bounds not reported")
	var queues_bounded := true
	for session_row_value in mux_report.get("sessions", []):
		var session_row: Dictionary = session_row_value
		if int(session_row.get("depth_messages", -1)) > max_messages \
				or int(session_row.get("depth_bytes", -1)) > max_bytes:
			queues_bounded = false
	_assert(queues_bounded, "a per-session backend queue exceeded its bound")
	_assert(int(mux_report.get("link", {}).get("depth_messages", 0)) <= int(mux_options.get("link_max_messages", 0)),
			"backend link queue exceeded its bound")

	# --- NO_CROSS_SESSION_LEAKAGE ---------------------------------------------------
	# Every frame the ONE client received carries exactly ITS gateway session
	# identity; Sim A's ledgers hold exactly that one logical session. The
	# pre-attach acks legitimately echo the client's OWN declared provisional
	# id (the support-layer probe id used before the gateway mints the real
	# gateway-session/*), so it is part of THIS client's identity set.
	var client_gsid := String(client_report.get("gateway_session_id", ""))
	_assert(client_gsid != "", "client report lost its gateway session id")
	var own_identities := {
		client_gsid: true,
		"gateway-session/eg3/probe/l2": true,
	}
	var foreign_sessions := {}
	for frame_entry_value in client_report.get("frames", []):
		var entry_text := str(frame_entry_value)
		for candidate in _extract_gateway_session_ids(entry_text):
			if candidate != "" and not own_identities.has(candidate):
				foreign_sessions[candidate] = true
	_assert(foreign_sessions.is_empty(),
			"foreign session identities leaked onto the client connection: %s" % str(foreign_sessions.keys()))
	_assert((sim_a.get("joined_players", []) as Array).size() == 1,
			"Sim A joined players other than THE single client player")

	# --- children self-exited; teardown kills any survivor -----------------------
	for pid in pids:
		var exit_deadline: int = Time.get_ticks_msec() + 5000
		while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < exit_deadline:
			OS.delay_msec(POLL_DELAY_MS)
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
		_assert(pid <= 0 or not OS.is_process_running(pid), "worker process %d lingered" % pid)

	_finish()


func _finish() -> void:
	_cleanup()
	var ok := failures.is_empty()
	var summary := {
		"test": "eg4_gateway_processes_l2",
		"verdict": "PASS" if ok else "FAIL",
		"assertions": assertions,
		"predicates": [
			"MULTI_SOURCE_SINGLE_CLIENT_TRANSPORT_PASS",
			"GATEWAY_OWNERSHIP_DECISIONS_ZERO",
			"BOUNDED_PER_SESSION_QUEUES",
			"NO_CROSS_SESSION_LEAKAGE",
		] if ok else ["PREDICATE_NOT_DEMONSTRATED"],
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if ok:
		print("[eg4-l2] L2 PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg4-l2] L2 FAIL")
		quit(1)


func _cleanup() -> void:
	for pid in pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)


## Pull every gateway-session/* identity mentioned in a serialized frame entry.
func _extract_gateway_session_ids(text: String) -> Array[String]:
	var found: Array[String] = []
	var index := text.find("gateway-session/")
	while index >= 0:
		var end := index
		while end < text.length() and text[end] != '"' and text[end] != " " and text[end] != "\\":
			end += 1
		found.append(text.substr(index, end - index))
		index = text.find("gateway-session/", end)
	return found
