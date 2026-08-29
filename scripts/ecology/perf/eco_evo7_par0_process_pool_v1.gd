extends RefCounted

class_name Par0ProcessPool

## ECO.EVO7 PERF1-PAR0 — deterministic persistent process pool coordinator.
##
## Owns N persistent Godot worker processes running the same executable as
## the coordinator. Deterministic partition and canonical merge live in the
## shadow runner; the pool only transports opaque job payloads and enforces
## the PAR0 failure policy:
##   worker timeout / crash / invalid response  -> named failure, FAIL-CLOSED
##   no retries, no stale generation crossing (single in-flight job/worker)

const Transport = preload("res://scripts/ecology/perf/eco_evo7_par0_transport_v1.gd")

const HANDSHAKE_TIMEOUT_MS := 60_000
const SHUTDOWN_TIMEOUT_MS := 10_000

var _godot_bin := ""
var _project_root := ""
var _session_dir := ""
var _worker_count := 0
var _workers: Array[Dictionary] = []
var _job_timeout_ms := 120_000
var _pending: Dictionary = {}
var _last_error := ""
var _seq := 0

func setup(
	godot_bin: String,
	project_root: String,
	session_dir: String,
	worker_count: int,
	context: Dictionary,
	job_timeout_ms: int = 120_000
) -> bool:
	if worker_count < 1:
		_fail("worker_count must be >= 1")
		return false
	_godot_bin = godot_bin
	_project_root = project_root
	_session_dir = session_dir
	_worker_count = worker_count
	_job_timeout_ms = job_timeout_ms
	DirAccess.make_dir_recursive_absolute(session_dir.path_join("inbox"))
	DirAccess.make_dir_recursive_absolute(session_dir.path_join("outbox"))
	DirAccess.make_dir_recursive_absolute(session_dir.path_join("workers"))

	var env_log_dir := OS.get_environment("PAR0_WORKER_LOG_DIR")
	for index in worker_count:
		var args := PackedStringArray([
			"--headless", "--path", project_root,
			"--script", "res://scripts/ecology/perf/eco_evo7_par0_worker_v1.gd",
		])
		if not env_log_dir.is_empty():
			args.append_array(PackedStringArray(["--log-file", env_log_dir.path_join("par0_worker_%d.log" % index)]))
		OS.set_environment("PAR0_WORKER_INDEX", str(index))
		OS.set_environment("PAR0_SESSION_DIR", _session_dir)
		OS.set_environment("BREAKPOINT_RUNTIME_DISABLED", "1")
		print("POOL diag before spawn index=%d envcheck=%s" % [index, OS.get_environment("PAR0_WORKER_INDEX")])
		var spawned = OS.execute_with_pipe(_godot_bin, args, false)
		if typeof(spawned) != TYPE_DICTIONARY or not spawned.has("pid") or not spawned.has("stdio"):
			_fail("worker %d spawn failed" % index)
			return false
		_workers.append({
			"index": index,
			"pid": int(spawned["pid"]),
			"stdio": spawned["stdio"],
			"stderr": spawned["stderr"],
			"parser": Transport.FrameParser.new(),
			"state": "SPAWNED",
			"jobs_done": 0,
		})

	if not _wait_state_all("HELLO"):
		return false
	if not _dispatch_setup(context):
		return false
	return true

func _dispatch_setup(context: Dictionary) -> bool:
	var setup_id := "setup_0"
	var setup_path := Transport.write_mailbox_message(_session_dir, "inbox", setup_id, {
		"protocol_version": Transport.PROTOCOL_VERSION,
		"setup_id": setup_id,
		"context": context,
	})
	if setup_path.is_empty():
		_fail("failed to write SETUP mailbox payload")
		return false
	for worker in _workers:
		if not _send_control(worker, "SETUP setup_0"):
			_fail("SETUP control write failed")
			return false
	if not _wait_state_all("SETUP_OK"):
		return false
	return true

func worker_count() -> int:
	return _worker_count

func last_error() -> String:
	return _last_error

## Deterministic partition: sorted candidate order, canonical contiguous
## ranges. Depends only on item order, N and worker_count — never on
## process scheduling.
static func partition(count: int, worker_count: int) -> Array[int]:
	var bounds: Array[int] = []
	for index in worker_count + 1:
		bounds.append(index * count / worker_count)
	return bounds

## Dispatch one generation batch. slices[index] is the canonical partition
## slice for worker `index` (already sorted by candidate_hash).
## Returns the base job_id or "" on failure.
func submit_generation(generation: int, slices: Array) -> String:
	if not _pending.is_empty():
		_fail("previous generation still pending")
		return ""
	if slices.size() != _worker_count:
		_fail("slice count must equal worker_count")
		return ""
	_seq += 1
	var base_id := "gen_%08d_%d" % [generation, _seq]
	for worker in _workers:
		var index := int(worker["index"])
		var job_id := "%s_w%d" % [base_id, index]
		var payload := {
			"protocol_version": Transport.PROTOCOL_VERSION,
			"job_id": job_id,
			"generation": generation,
			"worker_index": index,
			"items": slices[index],
		}
		if Transport.write_mailbox_message(_session_dir, "inbox", job_id, payload).is_empty():
			_fail("request mailbox write failed for %s" % job_id)
			return ""
	for worker in _workers:
		var index := int(worker["index"])
		var job_id := "%s_w%d" % [base_id, index]
		if not _send_control(worker, "JOB %s" % job_id):
			_fail("control write failed on worker %d" % index)
			return ""
		_pending[index] = {"job_id": job_id, "worker": worker}
	return base_id

## Collect every pending worker response. Returns {} on any failure
## (fail-closed), otherwise {"responses": [...]} in canonical worker order.
func collect_all() -> Dictionary:
	var deadline := Time.get_ticks_usec() + _job_timeout_ms * 1000
	var responses: Array[Dictionary] = []
	for worker in _workers:
		var index := int(worker["index"])
		var pending: Dictionary = _pending.get(index, {})
		if pending.is_empty():
			_fail("missing pending entry for worker %d" % index)
			return {}
		var response := _wait_response(worker, String(pending["job_id"]), deadline, true)
		if response.is_empty():
			return {}
		responses.append(response)
	_pending.clear()
	return {"responses": responses}

## ---------- transport-probe path (bulk-plane echo, no ecology) ----------

func submit_echo(job_id: String, worker_index: int, echo_payload: Dictionary) -> bool:
	var worker := _worker_by_index(worker_index)
	if worker.is_empty():
		_fail("unknown worker index %d" % worker_index)
		return false
	if Transport.write_mailbox_message(_session_dir, "inbox", job_id, {
		"protocol_version": Transport.PROTOCOL_VERSION,
		"job_id": job_id,
		"echo": echo_payload,
	}).is_empty():
		_fail("echo request write failed")
		return false
	if not _send_control(worker, "ECHO %s" % job_id):
		_fail("echo control write failed")
		return false
	_pending[worker_index] = {"job_id": job_id, "worker": worker}
	return true

func collect_echo(worker_index: int, timeout_ms: int) -> Dictionary:
	var worker := _worker_by_index(worker_index)
	var pending: Dictionary = _pending.get(worker_index, {})
	if worker.is_empty() or pending.is_empty():
		_fail("no pending echo for worker %d" % worker_index)
		return {}
	var deadline := Time.get_ticks_usec() + timeout_ms * 1000
	var response := _wait_response(worker, String(pending["job_id"]), deadline, false)
	_pending.erase(worker_index)
	return response

func ping_worker(worker_index: int, token: String, timeout_ms: int) -> bool:
	var worker := _worker_by_index(worker_index)
	if worker.is_empty():
		return false
	if not _send_control(worker, "PING %s" % token):
		return false
	var parser: Transport.FrameParser = worker["parser"]
	var deadline := Time.get_ticks_usec() + timeout_ms * 1000
	while Time.get_ticks_usec() < deadline:
		var raw: PackedByteArray = (worker["stdio"] as FileAccess).get_buffer(65536)
		if raw.size() > 0:
			parser.feed(raw)
			for message in Transport.parse_lines(parser):
				if message.begins_with("PONG "):
					return message.substr(5).strip_edges() == token
		else:
			OS.delay_usec(200)
			if not OS.is_process_running(int(worker["pid"])):
				return false
	return false

func worker_alive(worker_index: int) -> bool:
	var worker := _worker_by_index(worker_index)
	return not worker.is_empty() and OS.is_process_running(int(worker["pid"]))

func _worker_by_index(index: int) -> Dictionary:
	for worker in _workers:
		if int(worker["index"]) == index:
			return worker
	return {}

func shutdown() -> void:
	for worker in _workers:
		if OS.is_process_running(int(worker["pid"])):
			_send_control(worker, "QUIT")
	var deadline := Time.get_ticks_usec() + SHUTDOWN_TIMEOUT_MS * 1000
	for worker in _workers:
		var pid := int(worker["pid"])
		while OS.is_process_running(pid) and Time.get_ticks_usec() < deadline:
			OS.delay_usec(2000)
		if OS.is_process_running(pid):
			OS.kill(pid)
			worker["state"] = "KILLED"
		else:
			worker["state"] = "EXITED"

func session_dir() -> String:
	return _session_dir

## ---------- internals ----------

func _wait_state_all(target: String) -> bool:
	var deadline := Time.get_ticks_usec() + HANDSHAKE_TIMEOUT_MS * 1000
	var states: Array[String] = []
	for worker in _workers:
		states.append("")
	var all_ready := false
	while Time.get_ticks_usec() < deadline and not all_ready:
		all_ready = true
		for i in _workers.size():
			## Drain stdout to unblock child writes (Godot 4.7 pipe semantics
			## require the parent reader to consume chunks before the child
			## reaches _init). Without this drain the child hangs at engine
			## start-up waiting for the parent to acknowledge.
			var stdio: FileAccess = _workers[i]["stdio"]
			var chunk: PackedByteArray = stdio.get_buffer(65536)
			if chunk.size() > 0 and not chunk.is_empty():
				var parser: Transport.FrameParser = _workers[i]["parser"]
				parser.feed(chunk)
				for message in Transport.parse_lines(parser):
					print("POOL W%d start-up: %s" % [i, message.substr(0, 80)])
			if states[i] == target:
				continue
			var state := _read_worker_state(i)
			states[i] = state
			if state == target:
				_workers[i]["state"] = "READY"
			elif state == "FATAL" or state == "SETUP_INVALID" or state == "EXIT" or state == "IDLE_TIMEOUT" or state == "CORRUPT_CONTROL":
				_fail("worker %d failed during startup: %s" % [i, state])
				return false
			elif not OS.is_process_running(int(_workers[i]["pid"])):
				_fail("worker %d crashed during startup" % i)
				return false
			if state != target:
				all_ready = false
		if not all_ready:
			OS.delay_usec(4000)
	if not all_ready:
		_fail("handshake timeout waiting for %s" % target)
		return false
	return true
func _wait_response(worker: Dictionary, job_id: String, deadline_usec: int, strict: bool) -> Dictionary:
	var index := int(worker["index"])
	var response_path := ""
	while Time.get_ticks_usec() < deadline_usec:
		var raw: PackedByteArray = (worker["stdio"] as FileAccess).get_buffer(65536)
		if raw.size() > 0:
			var parser: Transport.FrameParser = worker["parser"]
			parser.feed(raw)
			for message in Transport.parse_lines(parser):
				if message == "@CORRUPT":
					_fail("worker %d sent corrupt control frame" % index)
					return {}
				if message.begins_with("DONE "):
					var done_id := message.substr(5).strip_edges()
					if done_id == job_id:
						response_path = Transport.mailbox_response_path(_session_dir, job_id)
						break
		else:
			OS.delay_usec(500)
		if response_path.is_empty() and not OS.is_process_running(int(worker["pid"])):
			_fail("worker %d crashed during job %s" % [index, job_id])
			return {}
		if not response_path.is_empty():
			break
		OS.delay_usec(500)
	if response_path.is_empty():
		_fail("job %s timeout on worker %d (fail-closed)" % [job_id, index])
		_kill_worker(worker)
		return {}
	var response := Transport.read_mailbox_message(response_path)
	Transport.remove_quiet(response_path)
	Transport.remove_quiet(Transport.mailbox_request_path(_session_dir, job_id))
	if response.is_empty():
		_fail("worker %d response corrupt for job %s" % [index, job_id])
		return {}
	if String(response.get("protocol_version", "")) != Transport.PROTOCOL_VERSION:
		_fail("worker %d protocol mismatch" % index)
		return {}
	if String(response.get("job_id", "")) != job_id:
		_fail("worker %d job_id mismatch: stale or foreign response" % index)
		return {}
	if int(response.get("worker_index", -1)) != index:
		_fail("worker %d response carries foreign worker_index" % index)
		return {}
	if strict:
		if response.has("error"):
			_fail("worker %d evaluation error %s for job %s" % [index, String(response["error"]), job_id])
			return {}
		if int(response.get("result_count", -1)) < 0 or not response.has("events"):
			_fail("worker %d response missing results" % index)
			return {}
	worker["jobs_done"] = int(worker["jobs_done"]) + 1
	worker["state"] = "JOB_DONE"
	return response

func _send_control(worker: Dictionary, text: String) -> bool:
	var frame := Transport.chunks_of(Transport.encode_frame(text.to_utf8_buffer()))
	var stdio: FileAccess = worker["stdio"]
	for piece in frame:
		stdio.store_buffer(piece)
	return true

func _read_worker_state(index: int) -> String:
	var path := _session_dir.path_join("workers").path_join("worker_%d.state" % index)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var state := file.get_line().strip_edges()
	file.close()
	return state

func _kill_worker(worker: Dictionary) -> void:
	var pid := int(worker["pid"])
	if OS.is_process_running(pid):
		OS.kill(pid)
		worker["state"] = "KILLED_TIMEOUT"

func _fail(message: String) -> void:
	_last_error = message
