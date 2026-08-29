extends SceneTree

## ECO.EVO7 PERF1-PAR0 — persistent recruitment evaluation worker process.
##
## One persistent worker evaluates canonical LS3.3 recruitment candidates in
## bulk. Control messages arrive on stdin (small frames only); JOB payloads
## and responses travel through the bounded session mailbox (files with
## SHA-256 guards). The worker:
##   - never touches renderer/UI/SceneTree state for results;
##   - evaluates every candidate through the SAME pure kernel as the serial
##     coordinator (single implementation guarantee);
##   - is identity-blind: worker_index/PID/time never enter event payloads;
##   - exits on QUIT, on session-directory removal, or after a bounded idle
##     lifetime so no orphan worker outlives its coordinator session.

const Kernel = preload("res://scripts/ecology/perf/eco_evo7_par0_recruitment_kernel_v1.gd")
const Transport = preload("res://scripts/ecology/perf/eco_evo7_par0_transport_v1.gd")

const IDLE_LIFETIME_MS := 1_800_000
const INBOX_POLL_DELAY_USEC := 2000

var _worker_index := -1
var _session_dir := ""
var _context := {}
var _parser = null
var _jobs_done := 0

func _init() -> void:
	_worker_index = int(OS.get_environment("PAR0_WORKER_INDEX"))
	_session_dir = OS.get_environment("PAR0_SESSION_DIR")
	if _worker_index < 0 or _session_dir.is_empty():
		_print_frame("FATAL missing worker_index or session_dir")
		quit(1)
		return
	_parser = Transport.FrameParser.new()
	_write_worker_file("HELLO")
	var idle_started := Time.get_ticks_usec()
	while true:
		var chunk: PackedByteArray = OS.read_buffer_from_stdin()
		if chunk.size() > 0:
			idle_started = Time.get_ticks_usec()
			_parser.feed(chunk)
			for message in Transport.parse_lines(_parser):
				var done := _handle_message(message)
				if done:
					_shutdown_clean()
					return
		else:
			OS.delay_usec(INBOX_POLL_DELAY_USEC)
		if Time.get_ticks_usec() - idle_started > IDLE_LIFETIME_MS * 1000:
			_write_worker_file("IDLE_TIMEOUT")
			break
		if not DirAccess.dir_exists_absolute(_session_dir):
			break
	_write_worker_file("EXIT")
	quit(0)

func _handle_message(message: String) -> bool:
	if message == "@CORRUPT":
		_write_worker_file("CORRUPT_CONTROL")
		return false
	if message.begins_with("PING"):
		_print_frame("PONG %s" % message.substr(5))
		return false
	if message.begins_with("SETUP"):
		var setup_id := message.substr(6).strip_edges()
		var payload := Transport.read_mailbox_message(Transport.mailbox_request_path(_session_dir, setup_id))
		if payload.is_empty() or String(payload.get("protocol_version", "")) != Transport.PROTOCOL_VERSION:
			_write_worker_file("SETUP_INVALID")
			return false
		_context = payload.get("context", {})
		_write_worker_file("SETUP_OK")
		return false
	if message.begins_with("JOB"):
		var job_id := message.substr(4).strip_edges()
		var started := Time.get_ticks_usec()
		var response := _evaluate_job(job_id, started)
		var write_path := Transport.write_mailbox_message(_session_dir, "outbox", job_id, response)
		if write_path.is_empty():
			_write_worker_file("RESPONSE_WRITE_FAIL")
			return false
		_print_frame("DONE %s" % job_id)
		return false
	if message.begins_with("ECHO"):
		## Transport-probe verb: full bulk-plane round-trip with an opaque
		## echo payload; never used by the simulation path.
		var echo_id := message.substr(5).strip_edges()
		var echo_started := Time.get_ticks_usec()
		var echo_payload := Transport.read_mailbox_message(Transport.mailbox_request_path(_session_dir, echo_id))
		if echo_payload.is_empty():
			_write_worker_file("ECHO_REQUEST_INVALID")
			return false
		var echo_response := {
			"protocol_version": Transport.PROTOCOL_VERSION,
			"job_id": echo_id,
			"worker_index": _worker_index,
			"worker_compute_us": Time.get_ticks_usec() - echo_started,
			"echo": echo_payload.get("echo", {}),
		}
		if Transport.write_mailbox_message(_session_dir, "outbox", echo_id, echo_response).is_empty():
			_write_worker_file("ECHO_RESPONSE_WRITE_FAIL")
			return false
		_print_frame("DONE %s" % echo_id)
		return false
	if message == "QUIT":
		return true
	_write_worker_file("UNKNOWN_CONTROL")
	return false

func _evaluate_job(job_id: String, started: int) -> Dictionary:
	var payload := Transport.read_mailbox_message(Transport.mailbox_request_path(_session_dir, job_id))
	if payload.is_empty():
		return _error_response(job_id, "REQUEST_INVALID")
	if String(payload.get("protocol_version", "")) != Transport.PROTOCOL_VERSION:
		return _error_response(job_id, "PROTOCOL_MISMATCH")
	if String(payload.get("job_id", "")) != job_id:
		return _error_response(job_id, "JOB_ID_MISMATCH")
	if _context.is_empty():
		return _error_response(job_id, "NO_SETUP")
	var items_value = payload.get("items")
	if not items_value is Array:
		return _error_response(job_id, "ITEMS_INVALID")
	var items: Array = items_value
	var input_keys := PackedStringArray()
	var events: Array[Dictionary] = []
	for item_value in items:
		if not item_value is Dictionary:
			return _error_response(job_id, "ITEM_INVALID")
		var item: Dictionary = item_value
		var candidate_value = item.get("candidate")
		var route_value = item.get("route")
		if not candidate_value is Dictionary or not route_value is Dictionary:
			return _error_response(job_id, "ITEM_FIELD_INVALID")
		var candidate: Dictionary = candidate_value
		var route: Dictionary = route_value
		input_keys.append(String(candidate.get("candidate_hash", "")))
		input_keys.append(String(route.get("route_hash", "")))
		var event := Kernel.evaluate_recruitment_event(candidate, route, _context)
		if event.is_empty():
			return _error_response(job_id, "EVALUATION_FAILED")
		event["recruitment_event_hash"] = Kernel.recruitment_event_hash(
			event, String(_context["schema"]), String(_context["version"]))
		events.append(event)
	var response := {
		"protocol_version": Transport.PROTOCOL_VERSION,
		"job_id": job_id,
		"generation": int(payload.get("generation", -1)),
		"worker_index": _worker_index,
		"input_hash": "|".join(input_keys).sha256_text(),
		"result_count": events.size(),
		"events": events,
		"result_hash": _result_hash(events),
		"worker_compute_us": Time.get_ticks_usec() - started,
	}
	_jobs_done += 1
	return response

func _error_response(job_id: String, code: String) -> Dictionary:
	return {
		"protocol_version": Transport.PROTOCOL_VERSION,
		"job_id": job_id,
		"worker_index": _worker_index,
		"error": code,
		"result_count": 0,
		"events": [],
		"result_hash": "",
		"input_hash": "",
		"worker_compute_us": 0,
	}

func _result_hash(events: Array[Dictionary]) -> String:
	var hashes := PackedStringArray()
	for event in events:
		hashes.append(String(event.get("recruitment_event_hash", "")))
	return "|".join(hashes).sha256_text()

func _print_frame(text: String) -> void:
	for piece in Transport.chunks_of(Transport.encode_frame(text.to_utf8_buffer())):
		print(piece.get_string_from_utf8())

func _write_worker_file(state: String) -> void:
	var dir := _session_dir.path_join("workers")
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(dir.path_join("worker_%d.state" % _worker_index), FileAccess.WRITE)
	if file != null:
		file.store_line(state)
		file.store_line(str(OS.get_process_id()))
		file.store_line(Transport.PROTOCOL_VERSION)
		file.close()

func _shutdown_clean() -> void:
	_write_worker_file("BYE")
	quit(0)
