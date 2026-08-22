extends SceneTree

## EG3 L2: REAL OS processes over real ENET proving the SHARED MULTIPLEXED
## BACKEND TUNNEL end to end. FIVE processes across the scenario: one sim
## server worker, one gateway worker composing the EG3 multiplexer, and four
## sequential/concurrent game-client processes (three concurrent sessions +
## one resume + one post-drop probe):
##   (a) ONE physical backend connection carries all sessions (sim sees a
##       single transport peer; the gateway multiplexer hosts N sessions);
##   (b) alpha floods INPUT_MOVEMENT while beta/gamma keep completing
##       control/operation/snapshot traffic within deadline;
##   (c) zero cross-session reliable-operation leakage (per-session sim
##       ledgers must equal each session's own operation table exactly);
##   (d) killing alpha WITHOUT a detach leaves the tunnel intact for the
##       survivors (their second wave completes afterwards);
##   (e) beta resumes through a NEW client process: NEW ephemeral gateway
##       slot, SAME granted PlayerId/PlayerEntityId, no stale-slot leakage;
##   (f) dropping the backend link fails subsequent traffic predictably:
##       the probe client times out cleanly and nothing resurrects stale
##       slots (the gateway purges scheduled frames on link loss).

const Support = preload("res://tools/network/eg3_process_support.gd")

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
		print("[eg3-l2][FAIL] %s" % message)


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
	return _wait_for_state(path, ["COMPLETE", "FAILED", "DRAINING"], timeout_ms)


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
	var sim_port: int = _find_available_port()
	var gateway_port: int = _find_available_port([sim_port])
	_assert(sim_port > 0 and gateway_port > 0 and sim_port != gateway_port, "port allocation failed")
	if sim_port <= 0 or gateway_port <= 0:
		_finish()
		return

	var root: String = ProjectSettings.globalize_path("res://artifacts/test-results/eg3-gateway-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(root)
	var sim_result: String = root.path_join("sim.json")
	var gateway_result: String = root.path_join("gateway.json")
	var player_bindings: String = root.path_join("player-bindings.json")
	var client_results: Dictionary = {
		"alpha": root.path_join("client-alpha.json"),
		"beta": root.path_join("client-beta.json"),
		"gamma": root.path_join("client-gamma.json"),
		"beta_resume": root.path_join("client-beta-resume.json"),
		"probe": root.path_join("client-probe.json"),
	}
	var trigger_beta: String = root.path_join("trigger-beta.marker")
	var trigger_gamma: String = root.path_join("trigger-gamma.marker")

	var executable: String = OS.get_executable_path()
	var project_root: String = ProjectSettings.globalize_path("res://")

	# 1) sim server first (owns the backend endpoint); stays alive so the
	#    orchestrator can drop the backend link as the final scenario step.
	var sim_pid: int = _launch(executable, project_root, "eg3_sim_server_worker.gd", [
		"--host=127.0.0.1", "--port=%d" % sim_port,
		"--result-file=%s" % sim_result,
		"--player-binding-file=%s" % player_bindings,
		"--expected-operations=%d" % Support.expected_operation_ids_applied().size(),
		"--expected-movements=%d" % Support.expected_movement_total(),
		"--stay-alive=1",
		"--link-drop-marker-file=%s" % root.path_join("drop-backend-link.marker"),
		"--timeout-ms=%d" % int(TIMEOUT_MS * 3),
		"--user-data-dir=%s" % root.path_join("ud-sim"),
	])
	pids.append(sim_pid)
	_assert(sim_pid > 0, "failed to launch sim server worker")
	var sim_listening: Dictionary = _wait_for_state(sim_result, ["LISTENING"], 15000)
	_assert(bool(sim_listening.get("success", false)), "sim server never became LISTENING")
	if not bool(sim_listening.get("success", false)):
		_finish()
		return

	# 2) gateway: THREE preminted sessions + a second beta ticket for the
	#    resume leg + a probe ticket for the post-drop leg.
	var premint: String = ",".join([
		Support.CLIENT_SESSION_A, Support.CLIENT_SESSION_B, Support.CLIENT_SESSION_C,
		Support.CLIENT_SESSION_B, "client-session/eg3/probe",
	])
	var gateway_pid: int = _launch(executable, project_root, "eg3_gateway_worker.gd", [
		"--client-host=127.0.0.1", "--client-port=%d" % gateway_port,
		"--sim-host=127.0.0.1", "--sim-port=%d" % sim_port,
		"--premint-client-sessions=%s" % premint,
		"--expected-placements=5",
		"--expected-detachments=3",
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
	_assert(int(tickets.get(Support.CLIENT_SESSION_A, []).size()) >= 1
			and int(tickets.get(Support.CLIENT_SESSION_B, []).size()) >= 2
			and int(tickets.get(Support.CLIENT_SESSION_C, []).size()) >= 1
			and int(tickets.get("client-session/eg3/probe", []).size()) >= 1,
			"gateway did not publish the preminted ticket table")

	var common_args := func(client_tag: String) -> Array:
		return [
			"--host=127.0.0.1", "--port=%d" % gateway_port,
			"--result-file=%s" % client_results[client_tag],
			"--timeout-ms=%d" % TIMEOUT_MS,
			"--user-data-dir=%s" % root.path_join("ud-client-%s" % client_tag),
		]

	# 3) THREE concurrent client sessions share the ONE backend link.
	var alpha_args: Array = common_args.call("alpha")
	alpha_args.append_array([
		"--auth-ticket=%s" % str(tickets[Support.CLIENT_SESSION_A][0]),
		"--client-session-id=%s" % Support.CLIENT_SESSION_A,
		"--peer-id=peer/enet/eg3-client-alpha",
		"--wire-session=transport-session/eg3/l2-client-alpha",
		"--flood-count=%d" % Support.FLOOD_INPUT_COUNT,
		"--flood-interval-ms=%d" % Support.FLOOD_INPUT_INTERVAL_MS,
		"--waves=1", "--no-detach=1", "--movement-seq-base=100",
	])
	var alpha_pid: int = _launch(executable, project_root, "eg3_client_worker.gd", alpha_args)
	pids.append(alpha_pid)
	_assert(alpha_pid > 0, "failed to launch alpha client worker")

	# Stagger: let alpha's flood get UNDERWAY before beta/gamma even connect,
	# so the survivors' whole first wave provably runs INSIDE the flood window
	# (tier-major scheduling must carry their P0-P1 traffic through it).
	var flooding: Dictionary = _wait_until(func() -> bool:
		var heartbeat: Dictionary = _read_json(String(client_results["alpha"]) + ".heartbeat.json")
		return int(heartbeat.get("flood_remaining", Support.FLOOD_INPUT_COUNT)) \
				<= Support.FLOOD_INPUT_COUNT - 5
	, 10000)
	_assert(bool(flooding.get("success", false)), "alpha flood never got underway")

	var beta_args: Array = common_args.call("beta")
	beta_args.append_array([
		"--auth-ticket=%s" % str(tickets[Support.CLIENT_SESSION_B][0]),
		"--client-session-id=%s" % Support.CLIENT_SESSION_B,
		"--peer-id=peer/enet/eg3-client-beta",
		"--wire-session=transport-session/eg3/l2-client-beta",
		"--waves=2", "--wave-trigger-file=%s" % trigger_beta,
		"--movement-seq-base=101",
	])
	var beta_pid: int = _launch(executable, project_root, "eg3_client_worker.gd", beta_args)
	pids.append(beta_pid)
	_assert(beta_pid > 0, "failed to launch beta client worker")

	var gamma_args: Array = common_args.call("gamma")
	gamma_args.append_array([
		"--auth-ticket=%s" % str(tickets[Support.CLIENT_SESSION_C][0]),
		"--client-session-id=%s" % Support.CLIENT_SESSION_C,
		"--peer-id=peer/enet/eg3-client-gamma",
		"--wire-session=transport-session/eg3/l2-client-gamma",
		"--waves=2", "--wave-trigger-file=%s" % trigger_gamma,
		"--movement-seq-base=102",
	])
	var gamma_pid: int = _launch(executable, project_root, "eg3_client_worker.gd", gamma_args)
	pids.append(gamma_pid)
	_assert(gamma_pid > 0, "failed to launch gamma client worker")

	# 4) alpha finishes its flood + operations without detaching; then the
	#    PROCESS disappears (abrupt transport-level disconnect).
	var alpha_wrap: Dictionary = _wait_for_terminal(client_results["alpha"], TIMEOUT_MS + 10000)
	var alpha: Dictionary = alpha_wrap.get("value", {})
	_assert(String(alpha.get("state", "")) == "COMPLETE", "alpha did not complete: %s" % str(alpha.get("failure_code", alpha)))
	var alpha_killed_at_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	if alpha_pid > 0 and OS.is_process_running(alpha_pid):
		OS.kill(alpha_pid)
	# Wait out the transport-level disconnect propagation.
	OS.delay_msec(300)

	# 5) release beta/gamma wave 2: the tunnel must carry them post-mortem.
	_write_marker(trigger_beta)
	_write_marker(trigger_gamma)
	var beta_wrap: Dictionary = _wait_for_terminal(client_results["beta"], TIMEOUT_MS + 10000)
	var gamma_wrap: Dictionary = _wait_for_terminal(client_results["gamma"], TIMEOUT_MS + 10000)
	var beta: Dictionary = beta_wrap.get("value", {})
	var gamma: Dictionary = gamma_wrap.get("value", {})

	# 6) beta resumes through a NEW client process: NEW ticket, rotated token,
	#    SAME client_session_id -> NEW ephemeral slot, SAME granted identity.
	var world_ready_beta: Dictionary = beta.get("world_ready", {})
	var beta_resume_args: Array = common_args.call("beta_resume")
	beta_resume_args.append_array([
		"--auth-ticket=%s" % str(tickets[Support.CLIENT_SESSION_B][1]),
		"--resume-token=%s" % str(beta.get("resume_token_out", "")),
		"--client-session-id=%s" % Support.CLIENT_SESSION_B,
		"--peer-id=peer/enet/eg3-client-beta-r2",
		"--wire-session=transport-session/eg3/l2-client-beta-r2",
		"--waves=1", "--movement-seq-base=301", "--op-wave-offset=2",
	])
	var beta_resume_pid: int = _launch(executable, project_root, "eg3_client_worker.gd", beta_resume_args)
	pids.append(beta_resume_pid)
	_assert(beta_resume_pid > 0, "failed to launch beta resume client worker")
	var beta_resume_wrap: Dictionary = _wait_for_terminal(client_results["beta_resume"], TIMEOUT_MS + 10000)
	var beta_resume: Dictionary = beta_resume_wrap.get("value", {})

	# 7) drop the BACKEND LINK gracefully (the sim closes its listener on the
	#    marker; a process kill on UDP/ENet is silent for ~30s); then a fresh
	#    probe client must fail predictably (placed, but no operation result
	#    ever arrives over the dead link).
	_write_marker(root.path_join("drop-backend-link.marker"))
	OS.delay_msec(500)
	var probe_args: Array = common_args.call("probe")
	probe_args.append_array([
		"--auth-ticket=%s" % str(tickets["client-session/eg3/probe"][0]),
		"--client-session-id=client-session/eg3/probe",
		"--peer-id=peer/enet/eg3-client-probe",
		"--wire-session=transport-session/eg3/l2-client-probe",
		"--waves=1", "--movement-seq-base=401", "--timeout-ms=4000",
	])
	var probe_pid: int = _launch(executable, project_root, "eg3_client_worker.gd", probe_args)
	pids.append(probe_pid)
	_assert(probe_pid > 0, "failed to launch probe client worker")
	var probe_wrap: Dictionary = _wait_for_terminal(client_results["probe"], 20000)
	var probe: Dictionary = probe_wrap.get("value", {})

	# The gateway completes only after the probe's PLACEMENT lands (5th).
	var gateway_wrap: Dictionary = _wait_for_terminal(gateway_result, int(TIMEOUT_MS * 2))
	var gateway: Dictionary = gateway_wrap.get("value", {})
	var sim: Dictionary = _read_json(sim_result)

	# --- process-level facts ---
	_assert(sim_pid != gateway_pid and gateway_pid != alpha_pid \
			and alpha_pid != beta_pid and beta_pid != gamma_pid,
			"child PIDs are not distinct")
	_assert(String(alpha.get("state", "")) == "COMPLETE", "alpha report missing")
	_assert(String(beta.get("state", "")) == "COMPLETE", "beta did not complete: %s" % str(beta.get("failure_code", beta)))
	_assert(String(gamma.get("state", "")) == "COMPLETE", "gamma did not complete: %s" % str(gamma.get("failure_code", gamma)))
	_assert(String(beta_resume.get("state", "")) == "COMPLETE", "beta resume did not complete: %s" % str(beta_resume.get("failure_code", beta_resume)))
	_assert(String(gateway.get("state", "")) == "COMPLETE", "gateway did not complete: %s" % str(gateway.get("failure_code", gateway)))
	_assert(String(sim.get("state", "")) == "DRAINING", "sim never reached DRAINING: %s" % str(sim.get("failure_code", sim)))
	_assert(FileAccess.file_exists(root.path_join("drop-backend-link.marker")), "backend link drop marker missing")

	# --- (a) single physical backend connection ---
	var physical_peers: Array = sim.get("physical_peers_seen", [])
	_assert(physical_peers.size() == 1, "sim saw more than one physical backend peer: %s" % str(physical_peers))
	var mux_report: Dictionary = gateway.get("backend_multiplexer", {})
	var mux_sessions: Array = mux_report.get("sessions", [])
	_assert(mux_sessions.size() >= 3 and mux_sessions.size() <= 5,
			"unexpected multiplexer session count: %d" % mux_sessions.size())
	var counters: Dictionary = gateway.get("counters", {})
	_assert(int(counters.get("frames_sent_client_to_world", 0)) > 0,
			"gateway sent no upstream frames")

	# --- (b) flood does not starve control/operations/snapshots ---
	var alpha_last_input: int = int(alpha.get("last_input_sent_at_ms", -1))
	var beta_wave_one: int = int(beta.get("wave_one_completed_at_ms", -1))
	var gamma_wave_one: int = int(gamma.get("wave_one_completed_at_ms", -1))
	_assert(alpha_last_input > 0 and beta_wave_one > 0 and gamma_wave_one > 0,
			"missing overlap timestamps")
	_assert(beta_wave_one < alpha_last_input,
			"beta wave 1 did not complete while alpha was still flooding (%d vs %d)" % [beta_wave_one, alpha_last_input])
	_assert(gamma_wave_one < alpha_last_input,
			"gamma wave 1 did not complete while alpha was still flooding (%d vs %d)" % [gamma_wave_one, alpha_last_input])
	_assert(int(alpha.get("flood_inputs_sent", 0)) == Support.FLOOD_INPUT_COUNT,
			"alpha did not send its whole flood")
	var snapshot_frames := 0
	for report_value in [beta, gamma, beta_resume]:
		var report: Dictionary = report_value
		for frame_text_value in report.get("frames_received", []):
			var parsed = JSON.parse_string(str(frame_text_value))
			if parsed is Dictionary \
					and String(Dictionary(parsed).get("payload", {}).get("channel", "")) == "AUTHORITATIVE_SNAPSHOT":
				snapshot_frames += 1
	_assert(snapshot_frames >= 1, "survivor legs received no AUTHORITATIVE_SNAPSHOT egress")

	# --- (c) zero cross-session reliable-operation leakage ---
	var world_ready_alpha: Dictionary = alpha.get("world_ready", {})
	var world_ready_gamma: Dictionary = gamma.get("world_ready", {})
	var world_ready_beta_resume: Dictionary = beta_resume.get("world_ready", {})
	var gsid_alpha := String(world_ready_alpha.get("gateway_session_id", ""))
	var gsid_beta := String(world_ready_beta.get("gateway_session_id", ""))
	var gsid_gamma := String(world_ready_gamma.get("gateway_session_id", ""))
	var gsid_beta_resume := String(world_ready_beta_resume.get("gateway_session_id", ""))
	var ledgers: Dictionary = sim.get("operation_ledger_by_session", {})
	var expected_ledger_keys: Array[String] = [gsid_alpha, gsid_beta, gsid_gamma, gsid_beta_resume]
	expected_ledger_keys.sort()
	var actual_ledger_keys: Array[String] = []
	for key_value in ledgers.keys():
		actual_ledger_keys.append(String(key_value))
	actual_ledger_keys.sort()
	_assert(actual_ledger_keys == expected_ledger_keys,
			"sim ledgers cover unexpected sessions:\n  got      %s\n  expected %s" % [str(actual_ledger_keys), str(expected_ledger_keys)])
	var expected_by_gsid: Dictionary = {
		gsid_alpha: Support.tag_operations("alpha", 1),
		gsid_beta: _sorted_concat(Support.tag_operations("beta", 1), Support.tag_operations("beta", 2)),
		gsid_gamma: _sorted_concat(Support.tag_operations("gamma", 1), Support.tag_operations("gamma", 2)),
		gsid_beta_resume: Support.tag_operations("beta", 3),
	}
	for gsid_value in expected_by_gsid.keys():
		var gsid_key := String(gsid_value)
		var actual: Array[String] = []
		for id_value in ledgers.get(gsid_key, []):
			actual.append(String(id_value))
		var expected: Array[String] = expected_by_gsid[gsid_key]
		_assert(actual == expected, "ledger mismatch for %s:\n  got      %s\n  expected %s" % [gsid_key, str(actual), str(expected)])
	var seen_ops: Dictionary = {}
	for gsid_key in expected_by_gsid.keys():
		for id_value in ledgers.get(String(gsid_key), []):
			var op_id := String(id_value)
			_assert(not seen_ops.has(op_id), "operation %s appears in TWO session ledgers" % op_id)
			seen_ops[op_id] = true

	# --- (d) abrupt disconnect of alpha left the tunnel intact ---
	_assert(int(beta.get("completed_at_ms", 0)) > alpha_killed_at_ms,
			"beta finished before alpha died; tunnel survival unproven")
	_assert(int(gamma.get("completed_at_ms", 0)) > alpha_killed_at_ms,
			"gamma finished before alpha died; tunnel survival unproven")

	# --- (e) resume: new ephemeral slot, same granted identity ---
	_assert(bool(world_ready_beta_resume.get("resumed", false)) == true,
			"resume WORLD_READY did not report resumed=true")
	_assert(String(world_ready_beta_resume.get("logical_player_id", "")) == String(world_ready_beta.get("logical_player_id", "")),
			"resume changed the granted logical player id")
	_assert(String(world_ready_beta_resume.get("player_entity_id", "")) == String(world_ready_beta.get("player_entity_id", "")),
			"resume changed the granted player entity id")
	_assert(gsid_beta_resume != "" and gsid_beta_resume != gsid_beta,
			"resume reused the previous gateway session slot identity")
	var bindings: Dictionary = sim.get("session_bindings", {})
	_assert(String(bindings.get(gsid_beta, "")) == String(world_ready_beta.get("logical_player_id", ""))
			and String(bindings.get(gsid_beta_resume, "")) == String(world_ready_beta_resume.get("logical_player_id", "")),
			"sim did not bind BOTH beta slots to the same granted identity")
	var joined_players: Array = sim.get("joined_players", [])
	_assert(joined_players.size() == 3, "expected three distinct joined players: %s" % str(joined_players))

	# --- (f) backend link drop fails predictably, no resurrection ---
	_assert(String(probe.get("state", "")) == "FAILED", "probe should have failed after the link drop")
	_assert(String(probe.get("failure_code", "")) == "CLIENT_TIMEOUT",
			"probe failed with unexpected code: %s" % String(probe.get("failure_code", "")))
	_assert(int(probe.get("results_received", -1)) == 0, "probe received results over a dead link")
	var probe_details: Dictionary = probe.get("details", {})
	_assert(bool(probe_details.get("placed", false)) == true,
			"probe should still have been placed by the live gateway")
	_assert(int(counters.get("backend_link_drops", 0)) >= 1,
			"gateway did not account the backend link drop")
	_assert(int(counters.get("placement_rejected", 0)) == 0, "gateway rejected placement frames")
	var forwarder_counters: Dictionary = counters.get("forwarder", {})
	_assert(int(forwarder_counters.get("dropped_client_to_world", -1)) == 0,
			"gateway dropped reliable upstream frames")
	_assert(int(counters.get("backend_mux_rejected", 0)) == 0,
			"multiplexer rejected healthy frames")
	_assert(int(mux_report.get("counters", {}).get("sent", 0)) >= 12,
			"multiplexer carried too few frames: %s" % str(mux_report.get("counters", {})))
	var flow_counters: Dictionary = gateway.get("placement_flow", {}).get("counters", {})
	_assert(int(flow_counters.get("placements_created", -1)) == 4, "flow created counter mismatch: %s" % str(flow_counters.get("placements_created")))
	_assert(int(flow_counters.get("placements_resumed", -1)) == 1, "flow resumed counter mismatch")

	# --- flood pressure actually arrived (lossy-unreliable is legal) ---
	var flood_by_session: Dictionary = sim.get("flood_inputs_by_session", {})
	var alpha_flood := int(flood_by_session.get(gsid_alpha, 0))
	_assert(alpha_flood >= Support.FLOOD_INPUT_COUNT / 2,
			"too few flood inputs survived to pressure the tunnel: %d" % alpha_flood)
	var receipts_by_session: Dictionary = sim.get("movement_receipts_by_session", {})
	_assert(int(receipts_by_session.get(gsid_alpha, 0)) >= 1
			and int(receipts_by_session.get(gsid_beta, 0)) >= 2
			and int(receipts_by_session.get(gsid_gamma, 0)) >= 2
			and int(receipts_by_session.get(gsid_beta_resume, 0)) >= 1,
			"movement receipt accounting mismatch: %s" % str(receipts_by_session))

	# --- ENDPOINT DISCLOSURE FENCE over every client-leg frame ---
	var corpus := ""
	for report_value in [alpha, beta, gamma, beta_resume, probe]:
		for frame_text_value in report_value.get("frames_received", []):
			var frame_text := str(frame_text_value)
			corpus += frame_text
			var parsed = JSON.parse_string(frame_text)
			if parsed is Dictionary:
				_scan_keys_recursive(Dictionary(parsed).get("payload", {}))
	for needle in FORBIDDEN_SUBSTRINGS:
		_assert(not corpus.contains(needle), "client leg leaked endpoint substring '%s'" % needle)
	for report_path in [gateway_result, sim_result]:
		var report_text := JSON.stringify(_read_json(report_path))
		for needle in FORBIDDEN_SUBSTRINGS:
			_assert(not report_text.contains(needle), "%s leaked '%s'" % [report_path.get_file(), needle])

	# --- children self-exited; teardown kills any survivor ---
	for pid in pids:
		var exit_deadline: int = Time.get_ticks_msec() + 5000
		while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < exit_deadline:
			OS.delay_msec(POLL_DELAY_MS)
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
		_assert(pid <= 0 or not OS.is_process_running(pid), "worker process %d lingered" % pid)

	_finish()


func _sorted_concat(a: Array[String], b: Array[String]) -> Array[String]:
	var merged: Array[String] = []
	for value in a:
		merged.append(value)
	for value in b:
		merged.append(value)
	merged.sort()
	return merged


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
		"test": "eg3_gateway_processes_l2",
		"verdict": "PASS" if failures.is_empty() else "FAIL",
		"assertions": assertions,
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if failures.is_empty():
		print("[eg3-l2] L2 PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg3-l2] L2 FAIL")
		quit(1)


func _cleanup() -> void:
	for pid in pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
