extends RefCounted

const SCHEMA: String = "planet_simulator.fixed_tick_scheduler.v1"
const DEFAULT_TICK_RATE_HZ: int = 60
const DEFAULT_MAX_CATCH_UP_TICKS: int = 8
const DEFAULT_MAX_FRAME_DELTA_SECONDS: float = 0.25
const BACKLOG_POLICY_DROP_EXCESS: String = "DROP_EXCESS_V1"
const BACKLOG_POLICY_RETAIN_EXCESS: String = "RETAIN_EXCESS_V1"

var _tick_rate_hz: int = DEFAULT_TICK_RATE_HZ
var _tick_delta_seconds: float = 1.0 / float(DEFAULT_TICK_RATE_HZ)
var _max_catch_up_ticks: int = DEFAULT_MAX_CATCH_UP_TICKS
var _max_frame_delta_seconds: float = DEFAULT_MAX_FRAME_DELTA_SECONDS
var _retain_excess_time: bool = false
var _accumulator_seconds: float = 0.0
var _server_tick: int = 0
var _ticks_emitted: int = 0
var _catch_up_limit_hits: int = 0
var _dropped_time_seconds: float = 0.0
var _retained_backlog_peak_ticks: int = 0

func configure(
	tick_rate_hz: int = DEFAULT_TICK_RATE_HZ,
	max_catch_up_ticks: int = DEFAULT_MAX_CATCH_UP_TICKS,
	initial_server_tick: int = 0,
	max_frame_delta_seconds: float = DEFAULT_MAX_FRAME_DELTA_SECONDS,
	retain_excess_time: bool = false
) -> Dictionary:
	if tick_rate_hz < 1 or tick_rate_hz > 1000:
		return _failure("INVALID_FIXED_TICK_RATE")
	if max_catch_up_ticks < 1 or max_catch_up_ticks > 256:
		return _failure("INVALID_FIXED_TICK_CATCH_UP_LIMIT")
	if initial_server_tick < 0:
		return _failure("INVALID_INITIAL_SERVER_TICK")
	if not _finite(max_frame_delta_seconds) or max_frame_delta_seconds <= 0.0 or max_frame_delta_seconds > 1.0:
		return _failure("INVALID_MAX_FRAME_DELTA")
	_tick_rate_hz = tick_rate_hz
	_tick_delta_seconds = 1.0 / float(tick_rate_hz)
	_max_catch_up_ticks = max_catch_up_ticks
	_max_frame_delta_seconds = max_frame_delta_seconds
	_retain_excess_time = retain_excess_time
	_accumulator_seconds = 0.0
	_server_tick = initial_server_tick
	_ticks_emitted = 0
	_catch_up_limit_hits = 0
	_dropped_time_seconds = 0.0
	_retained_backlog_peak_ticks = 0
	return _success(get_report())

func advance(frame_delta_seconds: float) -> Dictionary:
	if not _finite(frame_delta_seconds) or frame_delta_seconds < 0.0:
		return _failure("INVALID_FRAME_DELTA")
	var accepted_delta: float = minf(frame_delta_seconds, _max_frame_delta_seconds)
	if frame_delta_seconds > accepted_delta:
		# Even the lossless transient-stall mode keeps a hard one-frame safety cap.
		# M7 raises that cap to one second, so ordinary item/diagnostic stalls are
		# retained while pathological multi-second pauses still fail boundedly.
		_dropped_time_seconds += frame_delta_seconds - accepted_delta
	_accumulator_seconds += accepted_delta
	var requested_ticks: int = int(floor((_accumulator_seconds + 0.000000001) / _tick_delta_seconds))
	var emitted_ticks: int = mini(requested_ticks, _max_catch_up_ticks)
	if requested_ticks > _max_catch_up_ticks:
		_catch_up_limit_hits += 1
		if not _retain_excess_time:
			var skipped_ticks: int = requested_ticks - _max_catch_up_ticks
			_dropped_time_seconds += float(skipped_ticks) * _tick_delta_seconds
			_accumulator_seconds -= float(skipped_ticks) * _tick_delta_seconds
	_accumulator_seconds -= float(emitted_ticks) * _tick_delta_seconds
	_accumulator_seconds = maxf(_accumulator_seconds, 0.0)
	var pending_catch_up_ticks: int = _pending_catch_up_ticks()
	_retained_backlog_peak_ticks = maxi(_retained_backlog_peak_ticks, pending_catch_up_ticks)
	var first_tick: int = _server_tick + 1 if emitted_ticks > 0 else _server_tick
	_server_tick += emitted_ticks
	_ticks_emitted += emitted_ticks
	return _success({
		"tick_count": emitted_ticks,
		"first_tick": first_tick,
		"last_tick": _server_tick,
		"tick_delta_seconds": _tick_delta_seconds,
		"pending_catch_up_ticks": pending_catch_up_ticks,
	})

func get_server_tick() -> int:
	return _server_tick

func get_tick_delta_seconds() -> float:
	return _tick_delta_seconds

func get_pending_catch_up_ticks() -> int:
	return _pending_catch_up_ticks()

func has_catch_up_backlog() -> bool:
	return _pending_catch_up_ticks() > 0

func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"tick_rate_hz": _tick_rate_hz,
		"tick_delta_seconds": _tick_delta_seconds,
		"max_catch_up_ticks": _max_catch_up_ticks,
		"max_frame_delta_seconds": _max_frame_delta_seconds,
		"backlog_policy": BACKLOG_POLICY_RETAIN_EXCESS if _retain_excess_time else BACKLOG_POLICY_DROP_EXCESS,
		"retain_excess_time": _retain_excess_time,
		"server_tick": _server_tick,
		"accumulator_seconds": _accumulator_seconds,
		"pending_catch_up_ticks": _pending_catch_up_ticks(),
		"retained_backlog_peak_ticks": _retained_backlog_peak_ticks,
		"ticks_emitted": _ticks_emitted,
		"catch_up_limit_hits": _catch_up_limit_hits,
		"dropped_time_seconds": _dropped_time_seconds,
	}

func _pending_catch_up_ticks() -> int:
	return int(floor((_accumulator_seconds + 0.000000001) / _tick_delta_seconds))

func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)

func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

func _failure(error_code: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": {}}
