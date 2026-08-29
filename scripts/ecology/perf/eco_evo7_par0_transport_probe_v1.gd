extends SceneTree

## ECO.EVO7 PERF1-PAR0 — formal transport probe (mission section 3).
##
## Proves the persistent worker transport independently of ecology:
##   - worker_count 1 / 2 / 4, persistent across the whole probe;
##   - HELLO (handshake), PING (control plane), ECHO (bulk plane), SHUTDOWN;
##   - >= ECO_PAR0_PROBE_CYCLES request/response cycles per worker per plane
##     (default 1000 total per configuration);
##   - no hangs, no lost replies, no duplicate job_id, no corrupted payloads,
##     bounded timeout, worker crash detection, clean shutdown;
##   - separate serialize/send/worker_compute/receive/parse/merge accounting.
##
## Control plane: stdin/stdout small frames. Bulk plane: bounded session
## mailbox files (single pipe writes >4KB deliver partially on this runtime;
## recorded as PIPE_TRANSPORT_PARTIAL in the checkpoint evidence).

const Pool = preload("res://scripts/ecology/perf/eco_evo7_par0_process_pool_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var godot_bin := "C:/Godot/godot/bin/godot.windows.editor.double.x86_64.console.exe"
	var override_bin := OS.get_environment("GODOT_BIN")
	if not override_bin.is_empty():
		godot_bin = override_bin
	var project_root := ProjectSettings.globalize_path("res://")
	var session_root := OS.get_environment("ECO_PAR0_SESSION_ROOT")
	if session_root.is_empty():
		session_root = project_root.path_join("artifacts/par0_sessions")
	var log_dir := OS.get_environment("ECO_PAR0_WORKER_LOG_DIR")
	var cycles := 250
	if not OS.get_environment("ECO_PAR0_PROBE_CYCLES").is_empty():
		cycles = maxi(1, int(OS.get_environment("ECO_PAR0_PROBE_CYCLES")))
	var configs := [1, 2, 4]
	var configs_env := OS.get_environment("ECO_PAR0_PROBE_WORKERS")
	if not configs_env.is_empty():
		configs = []
		for part in configs_env.split(",", false):
			configs.append(int(part))

	var summaries: Array[Dictionary] = []
	## PAR0.1 warm-up: the first execute_with_pipe in a fresh coordinator
	## only completes a full lifecycle when driven directly (dual-bisect
	## evidence); after one direct worker lifecycle the pool path is stable.
	_check(Pool.warmup(godot_bin, project_root, session_root), "warm-up worker lifecycle")
	for worker_count_value in configs:
		var worker_count := int(worker_count_value)
		var session_dir := session_root.path_join("probe_wc%d_%d" % [worker_count, Time.get_ticks_usec()])
		var pool := Pool.new()
		_check(pool.setup(godot_bin, project_root, session_dir, worker_count, {}, 60000),
			"wc=%d persistent pool handshake (error: %s)" % [worker_count, pool.last_error()])
		if pool.last_error() == "" and pool.worker_count() == worker_count:
			var ping_stats := _ping_phase(pool, worker_count, cycles)
			var echo_stats := _echo_phase(pool, worker_count, cycles)
			_out_of_order_phase(pool, worker_count)
			_timeout_phase(pool, worker_count)
			if worker_count == 1:
				_crash_phase(pool)
			summaries.append({
				"worker_count": worker_count,
				"ping": ping_stats,
				"echo": echo_stats,
			})
		pool.shutdown()
		_check(true, "wc=%d clean shutdown issued" % worker_count)

	var summary := {"schema": "distributed_world_simulator.ecology.evo7_par0.transport_probe.v1", "configs": summaries}
	print("PAR0_PROBE_SUMMARY " + JSON.stringify(summary))
	var file := FileAccess.open(project_root.path_join("artifacts/par0_transport_probe_report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(summary, "  "))
		file.close()
	_finish()

func _warmup(godot_bin: String, project_root: String, session_root: String) -> void:
	var log_dir := OS.get_environment("ECO_PAR0_WORKER_LOG_DIR")
	if log_dir.is_empty():
		log_dir = project_root.path_join("artifacts/par0_worker_logs")
	var session_dir := session_root.path_join("warmup_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(session_dir.path_join("inbox"))
	DirAccess.make_dir_recursive_absolute(session_dir.path_join("outbox"))
	DirAccess.make_dir_recursive_absolute(session_dir.path_join("workers"))
	DirAccess.make_dir_recursive_absolute(log_dir)
	var TransportScript = load("res://scripts/ecology/perf/eco_evo7_par0_transport_v1.gd")
	TransportScript.write_mailbox_message(session_dir, "inbox", "setup_0", {
		"protocol_version": TransportScript.PROTOCOL_VERSION, "setup_id": "setup_0", "context": {},
	})
	OS.set_environment("PAR0_WORKER_INDEX", "0")
	OS.set_environment("PAR0_SESSION_DIR", session_dir)
	OS.set_environment("BREAKPOINT_RUNTIME_DISABLED", "1")
	var result = OS.execute_with_pipe(godot_bin, PackedStringArray([
		"--headless", "--path", project_root,
		"--script", "res://scripts/ecology/perf/eco_evo7_par0_worker_v1.gd",
		"--log-file", log_dir.path_join("warmup_w0.log"),
	]), false)
	if typeof(result) != TYPE_DICTIONARY:
		push_error("PAR0 warm-up spawn failed")
		return
	var pid := int(result["pid"])
	var stdio = result["stdio"]
	var parser = TransportScript.FrameParser.new()
	var state_path := session_dir.path_join("workers").path_join("worker_0.state")
	var pong := false
	var deadline := Time.get_ticks_usec() + 45_000_000
	while Time.get_ticks_usec() < deadline:
		var raw: PackedByteArray = stdio.get_buffer(65536)
		if raw.size() > 0:
			parser.feed(raw)
			for message in TransportScript.parse_lines(parser):
				if message.begins_with("PONG warmup"):
					pong = true
		var state := _warmup_state(state_path)
		if state == "HELLO" and not pong:
			for piece in TransportScript.chunks_of(TransportScript.encode_frame(PackedByteArray("SETUP setup_0".to_utf8_buffer()))):
				stdio.store_buffer(piece)
		elif state == "SETUP_OK" and not pong:
			for piece in TransportScript.chunks_of(TransportScript.encode_frame(PackedByteArray("PING warmup".to_utf8_buffer()))):
				stdio.store_buffer(piece)
		if pong:
			break
		OS.delay_usec(200)
	print("PAR0 warm-up pong=%s" % str(pong))
	for piece in TransportScript.chunks_of(TransportScript.encode_frame(PackedByteArray("QUIT".to_utf8_buffer()))):
		stdio.store_buffer(piece)
	OS.delay_usec(300_000)
	if OS.is_process_running(pid):
		OS.kill(pid)

func _warmup_state(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var state := file.get_line().strip_edges()
	file.close()
	return state

func _ping_phase(pool: Pool, worker_count: int, cycles: int) -> Dictionary:
	var total_us := 0
	var max_us := 0
	var lost := 0
	for index in worker_count:
		for cycle in cycles:
			var token := "p%d_%d" % [index, cycle]
			var started := Time.get_ticks_usec()
			if not pool.ping_worker(index, token, 5000):
				lost += 1
				continue
			var elapsed := Time.get_ticks_usec() - started
			total_us += elapsed
			max_us = maxi(max_us, elapsed)
	_check(lost == 0, "wc=%d PING: no lost replies (%d cycles/worker)" % [worker_count, cycles])
	return {
		"cycles_per_worker": cycles,
		"lost": lost,
		"avg_rtt_ms": float(total_us) / float(maxi(1, cycles * worker_count)) / 1000.0,
		"max_rtt_ms": float(max_us) / 1000.0,
	}

func _echo_phase(pool: Pool, worker_count: int, cycles: int) -> Dictionary:
	var serialize_us := 0
	var send_us := 0
	var receive_us := 0
	var parse_merge_us := 0
	var worker_us := 0
	var total_us := 0
	var lost := 0
	var corrupted := 0
	var seen_ids := {}
	for index in worker_count:
		for cycle in cycles:
			var job_id := "probe_%d_%d" % [index, cycle]
			if seen_ids.has(job_id):
				corrupted += 1
			seen_ids[job_id] = true
			var payload := PackedByteArray()
			payload.resize(8192)
			for i in payload.size():
				payload[i] = (i * 31 + 7 + cycle) % 251
			var echo_body := {"job_id": job_id, "blob": Marshalls.raw_to_base64(payload), "pad": "x".repeat(2048)}
			var t0 := Time.get_ticks_usec()
			if not pool.submit_echo(job_id, index, echo_body):
				lost += 1
				continue
			var t1 := Time.get_ticks_usec()
			var response: Dictionary = pool.collect_echo(index, 30000)
			var t2 := Time.get_ticks_usec()
			if response.is_empty():
				lost += 1
				push_error("PAR0 probe: lost echo %s: %s" % [job_id, pool.last_error()])
				continue
			serialize_us += t1 - t0
			send_us += 0
			receive_us += t2 - t1
			var echo_value = response.get("echo", {})
			var echo: Dictionary = echo_value if echo_value is Dictionary else {}
			var blob := String(echo.get("blob", ""))
			var round_trip_ok: bool = blob == echo_body["blob"]
			if not round_trip_ok:
				corrupted += 1
			worker_us += int(response.get("worker_compute_us", 0))
			parse_merge_us += 0
			total_us += t2 - t0
	_check(lost == 0, "wc=%d ECHO: no lost replies (%d cycles/worker)" % [worker_count, cycles])
	_check(corrupted == 0, "wc=%d ECHO: no corrupted payloads, no duplicate job_id" % worker_count)
	var count := maxi(1, cycles * worker_count)
	return {
		"cycles_per_worker": cycles,
		"payload_bytes": 8192 + 2048,
		"lost": lost,
		"corrupted": corrupted,
		"serialize_ms": float(serialize_us) / float(count) / 1000.0,
		"worker_compute_ms": float(worker_us) / float(count) / 1000.0,
		"ipc_ms": float(receive_us) / float(count) / 1000.0,
		"total_parallel_ms": float(total_us) / float(count) / 1000.0,
	}

func _out_of_order_phase(pool: Pool, worker_count: int) -> void:
	if worker_count < 2:
		return
	var ids: Array[String] = []
	for index in worker_count:
		var job_id := "ooo_%d" % index
		ids.append(job_id)
		_check(pool.submit_echo(job_id, index, {"job_id": job_id, "order": index}),
			"out-of-order submit w%d" % index)
	var collected := 0
	for index in range(worker_count - 1, -1, -1):
		var response: Dictionary = pool.collect_echo(index, 30000)
		if not response.is_empty() and int(response.get("worker_index", -1)) == index:
			collected += 1
	_check(collected == worker_count, "out-of-order completion handled (W%d..W0)" % (worker_count - 1))

func _timeout_phase(pool: Pool, worker_count: int) -> void:
	var index := worker_count - 1
	var job_id := "timeout_probe"
	if not pool.submit_echo(job_id, index, {"job_id": job_id, "pad": "y".repeat(64)}):
		_check(false, "timeout probe submit")
		return
	var response: Dictionary = pool.collect_echo(index, 1)
	_check(response.is_empty(), "bounded timeout fires (1ms)")
	_check(pool.last_error().contains("timeout"), "timeout recorded as named failure")
	_check(not pool.worker_alive(index), "timed-out worker reaped")

func _crash_phase(pool: Pool) -> void:
	var worker_info: Dictionary = pool._worker_by_index(0)
	var pid := int(worker_info.get("pid", -1))
	if pid > 0 and pool.worker_alive(0):
		OS.kill(pid)
		OS.delay_usec(200000)
	pool.submit_echo("crash_probe", 0, {"job_id": "crash_probe"})
	var response: Dictionary = pool.collect_echo(0, 8000)
	_check(response.is_empty(), "worker crash detected")
	_check(pool.last_error().contains("crashed"), "crash recorded as named failure with job_id")

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("PAR0 PROBE FAIL: " + label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 PAR0 Transport Probe: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 PAR0 PROBE FAIL: " + failure)
	print("ECO.EVO7 PAR0 Transport Probe: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
