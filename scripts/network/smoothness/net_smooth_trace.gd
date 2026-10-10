extends RefCounted

# Opt-in per-process diagnostics. Producers are main-thread only; worker owns
# file IO/JSON. No live Nodes/Resources cross the queue. Missing END or loss is
# INCONCLUSIVE, never a smoothness PASS. Times are LOCAL monotonic microseconds.
const MAX_PENDING := 8192
const MAX_BYTES := 1073741824
static var _sink
static var measuring := false
var _thread := Thread.new()
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _pending: Array[Dictionary] = []
var _closing := false
var _dropped := 0
var _sequence := 0
var _path := ""

static func enabled() -> bool:
	return _sink != null

static func start() -> void:
	var directory := OS.get_environment("DWS_NET_SMOOTH_TRACE_DIR")
	if directory.is_empty() or _sink != null:
		return
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("NET_SMOOTH_TRACE_DIRECTORY_FAILED")
		return
	_sink = load("res://scripts/network/smoothness/net_smooth_trace.gd").new()
	_sink._path = directory.path_join("trace.jsonl")
	if _sink._thread.start(_sink._write_loop) != OK:
		push_error("NET_SMOOTH_TRACE_THREAD_FAILED")
		_sink = null
		return
	emit("header", {"schema": "dws.net_smooth.trace.v1",
		"run_id": OS.get_environment("DWS_NET_SMOOTH_RUN_ID"),
		"role": OS.get_environment("DWS_NET_SMOOTH_ROLE"),
		"pid": OS.get_process_id(), "version": Engine.get_version_info()["string"],
		"clock": "PROCESS_LOCAL_MONOTONIC_US", "max_pending": MAX_PENDING,
		"max_bytes": MAX_BYTES})

static func emit(kind: String, fields: Dictionary = {}) -> void:
	if _sink == null:
		return
	_sink._append(kind, fields)

static func finish() -> void:
	if _sink == null:
		return
	_sink._mutex.lock()
	_sink._closing = true
	_sink._mutex.unlock()
	_sink._wake.post()
	_sink._thread.wait_to_finish()
	_sink = null
	measuring = false

func _append(kind: String, fields: Dictionary) -> void:
	_sequence += 1
	var record := {"n": _sequence, "t_us": Time.get_ticks_usec(),
		"kind": kind, "measure": measuring, "data": fields.duplicate(true)}
	_mutex.lock()
	if _pending.size() >= MAX_PENDING:
		_dropped += 1
		_mutex.unlock()
		return
	var notify := _pending.is_empty()
	_pending.append(record)
	_mutex.unlock()
	if notify:
		_wake.post()

func _write_loop() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	var io_errors := 0
	var bytes := 0
	var written := 0
	while true:
		_wake.wait()
		_mutex.lock()
		var batch := _pending
		_pending = []
		var closing := _closing
		var lost := _dropped
		_mutex.unlock()
		for record in batch:
			var line := JSON.stringify(record) + "\n"
			var length := line.to_utf8_buffer().size()
			if file == null or bytes + length > MAX_BYTES:
				io_errors += 1
				continue
			file.store_string(line)
			bytes += length
			written += 1
			if file.get_error() != OK:
				io_errors += 1
		if closing:
			if file != null:
				file.store_string(JSON.stringify({"kind": "end", "t_us": Time.get_ticks_usec(),
					"data": {"dropped": lost, "io_errors": io_errors, "written": written,
					"produced": _sequence, "bytes": bytes}}) + "\n")
				file.flush()
				file.close()
			return
