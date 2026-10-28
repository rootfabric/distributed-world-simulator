extends Node

const Trace = preload("res://scripts/network/smoothness/net_smooth_trace.gd")
var _last_us := 0
var _last_control_ms := 0
var _measurement_ended := false
var _injected := false

func _ready() -> void:
	process_priority = 10000
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		Trace.emit("frame", {"interval_ms": float(now - _last_us) / 1000.0,
			"engine_process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0})
	_last_us = now
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_control_ms < 200:
		return
	_last_control_ms = now_ms
	var directory := OS.get_environment("DWS_NET_SMOOTH_TRACE_DIR")
	# Only enabled by an explicit per-process test environment; no remote port
	# or public gameplay command is added. Runner owns this unique directory.
	if not _measurement_ended and FileAccess.file_exists(directory.path_join("measure.end")):
		Trace.emit("measure_end")
		Trace.measuring = false
		_measurement_ended = true
		# Explicit local measurement-close ACK before planned reconnect,
		# final screenshots and teardown. The harness must wait for EVERY
		# process ACK; this does not retroactively filter any captured stalls.
		var ack: FileAccess = FileAccess.open(
			directory.path_join("measure.end.ack"), FileAccess.WRITE)
		if ack == null:
			push_error("NET_SMOOTH_MEASURE_END_ACK_WRITE_FAILED")
		else:
			ack.store_string(str(Time.get_ticks_usec()) + "\n")
			ack.flush()
			ack.close()
	elif not _measurement_ended and not Trace.measuring and FileAccess.file_exists(directory.path_join("measure.start")):
		Trace.measuring = true
		Trace.emit("measure_start")
	if FileAccess.file_exists(directory.path_join("stop.signal")):
		get_parent().request_graceful_shutdown("net_smooth1_runner", 0)
	if Trace.measuring and not _injected:
		var injection_ms := int(OS.get_environment("DWS_NET_SMOOTH_INJECT_STALL_MS"))
		if injection_ms > 0:
			_injected = true
			Trace.emit("injected_stall", {"duration_ms": mini(injection_ms, 1000)})
			OS.delay_msec(mini(injection_ms, 1000))
