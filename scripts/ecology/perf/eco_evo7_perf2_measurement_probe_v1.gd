extends RefCounted

## PERF2.0 process-local observation helper.
##
## This helper samples only noncanonical process/clock state. It has no reference
## to ecology authorities and cannot mutate Workbench/LS3 state.

var _started_usec := 0
var _engine_static_before := 0
var _engine_peak_before := 0
var _active := false


func begin() -> Dictionary:
	if _active:
		return {"success": false, "error_code": "PERF2_PROBE_ALREADY_ACTIVE"}
	_started_usec = Time.get_ticks_usec()
	_engine_static_before = int(OS.get_static_memory_usage())
	_engine_peak_before = int(OS.get_static_memory_peak_usage())
	_active = true
	return {
		"success": true,
		"started_usec": _started_usec,
		"engine_static_before_bytes": _engine_static_before,
		"engine_static_peak_before_bytes": _engine_peak_before,
	}


func finish() -> Dictionary:
	if not _active:
		return {"success": false, "error_code": "PERF2_PROBE_NOT_ACTIVE"}
	var ended_usec := Time.get_ticks_usec()
	var engine_static_after := int(OS.get_static_memory_usage())
	var engine_peak_after := int(OS.get_static_memory_peak_usage())
	_active = false
	return {
		"success": true,
		"wall_ms": float(ended_usec - _started_usec) / 1000.0,
		"memory_bytes": {
			"engine_static_bytes": engine_static_after,
			"engine_static_peak_bytes": maxi(_engine_peak_before, engine_peak_after),
			"engine_static_before_bytes": _engine_static_before,
			"engine_static_delta_bytes": engine_static_after - _engine_static_before,
			"process_rss_bytes": null,
			"process_peak_rss_bytes": null,
		},
	}


func is_active() -> bool:
	return _active
