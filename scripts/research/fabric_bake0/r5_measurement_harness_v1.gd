extends RefCounted
## R5.0 generic measurement harness.
## Wall-clock/memory/object metrics are observational only and MUST NOT enter
## physical correctness or deterministic identity.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_r5_0_measurement_harness.v1"

var _label := ""
var _active := {}
var _stages := {}
var _snapshots := {}
var _counters := {}

func _init(label: String = "r5-0") -> void:
	_label = label

func begin_stage(name: String) -> Dictionary:
	if name.is_empty() or _active.has(name) or _stages.has(name):
		return U.failure("R5_MEASURE_STAGE_BEGIN_INVALID", {"stage": name})
	print("FABRIC_R5_0_STAGE_BEGIN=" + name)
	_active[name] = {
		"start_us": Time.get_ticks_usec(),
		"memory_static_bytes": _memory_static(),
		"object_count": _object_count(),
	}
	return U.success()

func end_stage(name: String) -> Dictionary:
	if not _active.has(name):
		return U.failure("R5_MEASURE_STAGE_END_INVALID", {"stage": name})
	var started: Dictionary = _active[name]
	var ended_us := Time.get_ticks_usec()
	var memory_after := _memory_static()
	var objects_after := _object_count()
	_stages[name] = {
		"duration_us": ended_us - int(started.start_us),
		"memory_before_bytes": int(started.memory_static_bytes),
		"memory_after_bytes": memory_after,
		"memory_delta_bytes": memory_after - int(started.memory_static_bytes),
		"objects_before": int(started.object_count),
		"objects_after": objects_after,
		"object_delta": objects_after - int(started.object_count),
	}
	_active.erase(name)
	print("FABRIC_R5_0_STAGE_END=%s DURATION_US=%d" % [name, int(_stages[name].duration_us)])
	return U.success(_stages[name].duplicate(true))

func sample(name: String) -> Dictionary:
	if name.is_empty():
		return U.failure("R5_MEASURE_SAMPLE_INVALID")
	_snapshots[name] = {
		"tick_us": Time.get_ticks_usec(),
		"memory_static_bytes": _memory_static(),
		"object_count": _object_count(),
	}
	return U.success(_snapshots[name].duplicate(true))

func set_counter(name: String, value) -> Dictionary:
	if name.is_empty() or not _json_scalar(value):
		return U.failure("R5_MEASURE_COUNTER_INVALID", {"counter": name})
	_counters[name] = value
	return U.success()

func finish(deterministic: Dictionary, applicability: Dictionary = {}) -> Dictionary:
	if not _active.is_empty():
		return U.failure("R5_MEASURE_STAGE_LEFT_OPEN", {"open_stages": _active.keys()})
	var memory_peak := _memory_static()
	for row in _snapshots.values():
		memory_peak = maxi(memory_peak, int(row.memory_static_bytes))
	for row in _stages.values():
		memory_peak = maxi(memory_peak, maxi(int(row.memory_before_bytes), int(row.memory_after_bytes)))
	var deterministic_payload := {
		"schema": SCHEMA,
		"label": _label,
		"counters": _counters.duplicate(true),
		"deterministic": deterministic.duplicate(true),
		"applicability": applicability.duplicate(true),
	}
	return U.success({
		"schema": SCHEMA,
		"label": _label,
		"stages": _stages.duplicate(true),
		"snapshots": _snapshots.duplicate(true),
		"counters": _counters.duplicate(true),
		"applicability": applicability.duplicate(true),
		"memory_static_peak_bytes": memory_peak,
		"deterministic": deterministic.duplicate(true),
		"deterministic_hash": U.canonical_hash(deterministic_payload),
	})

static func _memory_static() -> int:
	return int(Performance.get_monitor(Performance.MEMORY_STATIC))

static func _object_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))

static func _json_scalar(value) -> bool:
	var kind := typeof(value)
	return kind == TYPE_INT or kind == TYPE_FLOAT or kind == TYPE_BOOL or kind == TYPE_STRING
