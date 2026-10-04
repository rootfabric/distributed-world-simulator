extends RefCounted

# Bounded observer only. It never authorizes/retries a command or changes its
# result. Record an allowlisted envelope, never request bodies or session tokens.
const MAX_RECORDS := 32
const MAX_REASON_BUCKETS := 32
const LOGS_PER_WINDOW := 8
const LOG_WINDOW_MS := 1000
const MAX_TEXT_LENGTH := 160

var _recent: Array[Dictionary] = []
var _counts: Dictionary = {}
var _total := 0
var _logged := 0
var _suppressed := 0
var _suppressed_since_log := 0
var _window_started_ms := -1
var _window_logs := 0
var _handler_calls := 0
var _slow_handlers := 0
var _max_handler_ms := 0.0
var _last_slow_handler := ""


func record_rejection(context: Dictionary, now_ms: int = -1) -> Dictionary:
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	var entry := {
		"at_ms": now_ms,
		"peer_id": _text(context.get("peer_id", "")),
		"player_id": _text(context.get("player_id", "")),
		"operation_id": _text(context.get("operation_id", "")),
		"command_type": _text(context.get("command_type", "")),
		"error_code": _text(context.get("error_code", "UNKNOWN")),
		"stage": _text(context.get("stage", "")),
		"server_tick": int(context.get("server_tick", 0)),
	}
	var queue_value = context.get("queue", {})
	if queue_value is Dictionary:
		var queue: Dictionary = queue_value
		for key in ["pending", "capacity", "oldest_queue_age_ticks", "pressure_coalesced"]:
			if queue.has(key) and typeof(queue[key]) in [TYPE_INT, TYPE_FLOAT]:
				entry[key] = int(queue[key])
	var bucket: String = String(entry["command_type"]) + ":" + String(entry["error_code"])
	if not _counts.has(bucket) and _counts.size() >= MAX_REASON_BUCKETS - 1:
		bucket = "OTHER"
	_counts[bucket] = int(_counts.get(bucket, 0)) + 1
	_total += 1
	_recent.append(entry.duplicate(true))
	if _recent.size() > MAX_RECORDS:
		_recent.pop_front()
	if _window_started_ms < 0 or now_ms < _window_started_ms or now_ms - _window_started_ms >= LOG_WINDOW_MS:
		_window_started_ms = now_ms
		_window_logs = 0
	var should_log := _window_logs < LOGS_PER_WINDOW
	if should_log:
		_window_logs += 1
		_logged += 1
		entry["suppressed_since_last_log"] = _suppressed_since_log
		_suppressed_since_log = 0
	else:
		_suppressed += 1
		_suppressed_since_log += 1
	return {"should_log": should_log, "entry": entry}


func observe_handler(command_type: String, elapsed_ms: float) -> void:
	if is_nan(elapsed_ms) or is_inf(elapsed_ms) or elapsed_ms < 0.0:
		return
	_handler_calls += 1
	_max_handler_ms = maxf(_max_handler_ms, elapsed_ms)
	if elapsed_ms > 50.0:
		_slow_handlers += 1
		_last_slow_handler = _text(command_type)


func get_report() -> Dictionary:
	return {
		"schema": "distributed_world_simulator.live2_r3_diagnostics.v1",
		"total_rejections_observed": _total,
		"log_records_admitted": _logged,
		"log_records_suppressed": _suppressed,
		"max_recent_records": MAX_RECORDS,
		"recent_rejections": _recent.duplicate(true),
		"reason_counts": _counts.duplicate(true),
		"handler_calls": _handler_calls,
		"handlers_over_50ms": _slow_handlers,
		"max_handler_ms": _max_handler_ms,
		"last_slow_handler": _last_slow_handler,
	}


func _text(value) -> String:
	return String(value).replace("\n", " ").replace("\r", " ").replace("\t", " ").left(MAX_TEXT_LENGTH)
