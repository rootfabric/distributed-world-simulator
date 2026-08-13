extends RefCounted

const RegionState = preload("res://scripts/ecology/production/ecology_region_state_v1.gd")
const Persistence = preload("res://scripts/research/ecology/plant_ecosystem_persistence_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p4_2_deterministic_clock.v1"
const VERSION := "1.0.0"
const PARENT_P4_1_ACCEPTED_AGGREGATE := "1acb55e1e825872943eac438303f03b979f33778a87c227d9819f74bff44b717"
const MAX_EXACT_GENERATION := 9007199254740991
const RELATIVE_EPSILON := 0.000000000001
const TIME_EPSILON := 0.000000000001

const CLOCK_FIELDS := [
	"schema",
	"version",
	"parent_p4_1_accepted_aggregate",
	"origin_generation",
	"origin_world_time",
	"step_interval_world_time",
	"clock_hash",
]

static func create_clock(region_state: Dictionary, step_interval_value) -> Dictionary:
	if not bool(RegionState.validate_region_state(region_state).get("success", false)):
		return {}
	var interval := _normalized_positive_float(step_interval_value)
	if is_nan(interval):
		return {}
	var generation := int(region_state.get("ecology_generation", -1))
	var world_time := float(region_state.get("last_simulated_world_time", NAN))
	if generation < 0 or generation > MAX_EXACT_GENERATION or not is_finite(world_time) or world_time < 0.0:
		return {}
	var clock := {
		"schema": SCHEMA,
		"version": VERSION,
		"parent_p4_1_accepted_aggregate": PARENT_P4_1_ACCEPTED_AGGREGATE,
		"origin_generation": generation,
		"origin_world_time": world_time,
		"step_interval_world_time": interval,
	}
	clock["clock_hash"] = compute_clock_hash(clock)
	if not bool(validate_clock(clock).get("success", false)):
		return {}
	return clock

static func validate_clock(clock: Dictionary) -> Dictionary:
	if not _exact_fields(clock, CLOCK_FIELDS):
		return _failure("CLOCK_FIELDS_MISMATCH")
	if String(clock.get("schema", "")) != SCHEMA or String(clock.get("version", "")) != VERSION:
		return _failure("CLOCK_SCHEMA_OR_VERSION_MISMATCH")
	if String(clock.get("parent_p4_1_accepted_aggregate", "")) != PARENT_P4_1_ACCEPTED_AGGREGATE:
		return _failure("CLOCK_PARENT_P4_1_MISMATCH")
	if typeof(clock.get("origin_generation")) != TYPE_INT:
		return _failure("CLOCK_ORIGIN_GENERATION_TYPE_INVALID")
	var origin_generation := int(clock.get("origin_generation", -1))
	if origin_generation < 0 or origin_generation > MAX_EXACT_GENERATION:
		return _failure("CLOCK_ORIGIN_GENERATION_RANGE_INVALID")
	if typeof(clock.get("origin_world_time")) != TYPE_FLOAT:
		return _failure("CLOCK_ORIGIN_WORLD_TIME_TYPE_INVALID")
	var origin_world_time := float(clock.get("origin_world_time", NAN))
	if not is_finite(origin_world_time) or origin_world_time < 0.0:
		return _failure("CLOCK_ORIGIN_WORLD_TIME_RANGE_INVALID")
	if typeof(clock.get("step_interval_world_time")) != TYPE_FLOAT:
		return _failure("CLOCK_INTERVAL_TYPE_INVALID")
	var interval := float(clock.get("step_interval_world_time", NAN))
	if not is_finite(interval) or interval <= 0.0:
		return _failure("CLOCK_INTERVAL_RANGE_INVALID")
	var expected_hash := compute_clock_hash(clock)
	if not _is_hash(expected_hash) or String(clock.get("clock_hash", "")) != expected_hash:
		return _failure("CLOCK_HASH_MISMATCH")
	return {"success": true, "error": "", "clock_hash": expected_hash}

static func compute_clock_hash(clock: Dictionary) -> String:
	var canonical := [
		String(clock.get("schema", "")),
		String(clock.get("version", "")),
		String(clock.get("parent_p4_1_accepted_aggregate", "")),
		clock.get("origin_generation", -1),
		clock.get("origin_world_time", NAN),
		clock.get("step_interval_world_time", NAN),
	]
	return JSON.stringify(canonical).sha256_text()

static func boundary_time_for_generation(generation_value, clock: Dictionary) -> float:
	if not bool(validate_clock(clock).get("success", false)):
		return NAN
	if typeof(generation_value) != TYPE_INT:
		return NAN
	var generation := int(generation_value)
	var origin_generation := int(clock["origin_generation"])
	if generation < origin_generation or generation > MAX_EXACT_GENERATION:
		return NAN
	var offset := generation - origin_generation
	var boundary := float(clock["origin_world_time"]) + float(offset) * float(clock["step_interval_world_time"])
	if not is_finite(boundary) or boundary < 0.0:
		return NAN
	return boundary

static func validate_bound_region(region_state: Dictionary, clock: Dictionary) -> Dictionary:
	if not bool(RegionState.validate_region_state(region_state).get("success", false)):
		return _failure("REGION_STATE_INVALID")
	if not bool(validate_clock(clock).get("success", false)):
		return _failure("CLOCK_INVALID")
	var generation := int(region_state.get("ecology_generation", -1))
	var origin_generation := int(clock["origin_generation"])
	if generation < origin_generation:
		return _failure("REGION_GENERATION_BEFORE_CLOCK_ORIGIN")
	var expected_boundary := boundary_time_for_generation(generation, clock)
	if is_nan(expected_boundary):
		return _failure("REGION_BOUNDARY_UNREPRESENTABLE")
	var actual_boundary := float(region_state.get("last_simulated_world_time", NAN))
	if actual_boundary != expected_boundary:
		return _failure("REGION_WORLD_TIME_NOT_ON_EXACT_CLOCK_BOUNDARY")
	return {
		"success": true,
		"error": "",
		"ecology_generation": generation,
		"boundary_world_time": expected_boundary,
	}

static func due_plan(region_state: Dictionary, target_world_time_value, clock: Dictionary) -> Dictionary:
	var binding := validate_bound_region(region_state, clock)
	if not bool(binding.get("success", false)):
		return _failure(String(binding.get("error", "REGION_CLOCK_BINDING_INVALID")))
	var target_world_time := _normalized_nonnegative_float(target_world_time_value)
	if is_nan(target_world_time):
		return _failure("TARGET_WORLD_TIME_INVALID")
	var current_generation := int(region_state["ecology_generation"])
	var current_boundary := float(binding["boundary_world_time"])
	if target_world_time < current_boundary and not _times_equal(target_world_time, current_boundary):
		return _failure("TARGET_WORLD_TIME_REWIND")
	var target_generation := _generation_at_or_before(target_world_time, clock)
	if target_generation < 0:
		return _failure("TARGET_GENERATION_UNREPRESENTABLE")
	if target_generation < current_generation:
		target_generation = current_generation
	var due_steps := target_generation - current_generation
	if due_steps < 0:
		return _failure("DUE_STEPS_NEGATIVE")
	var processed_boundary := boundary_time_for_generation(target_generation, clock)
	if is_nan(processed_boundary):
		return _failure("TARGET_BOUNDARY_UNREPRESENTABLE")
	return {
		"success": true,
		"error": "",
		"due_steps": due_steps,
		"current_generation": current_generation,
		"target_generation": target_generation,
		"current_boundary_world_time": current_boundary,
		"processed_boundary_world_time": processed_boundary,
		"observed_target_world_time": target_world_time,
	}

static func advance_to(region_state: Dictionary, target_world_time_value, clock: Dictionary) -> Dictionary:
	var plan := due_plan(region_state, target_world_time_value, clock)
	if not bool(plan.get("success", false)):
		return {}
	var due_steps := int(plan["due_steps"])
	if due_steps == 0:
		return region_state.duplicate(true)
	if due_steps > Persistence.MAX_ADVANCE_STEPS:
		return {}
	var p3_state := RegionState.extract_p3_state(region_state)
	if p3_state.is_empty():
		return {}
	var advanced_p3 := Persistence.advance(p3_state, due_steps)
	if advanced_p3.is_empty() or not bool(Persistence.validate_state(advanced_p3).get("success", false)):
		return {}
	var advanced_region := RegionState.create_region_state(
		String(region_state["region_id"]),
		float(plan["processed_boundary_world_time"]),
		advanced_p3
	)
	if advanced_region.is_empty():
		return {}
	if not bool(validate_bound_region(advanced_region, clock).get("success", false)):
		return {}
	if int(advanced_region.get("ecology_generation", -1)) != int(plan["target_generation"]):
		return {}
	return advanced_region

static func _generation_at_or_before(target_world_time: float, clock: Dictionary) -> int:
	var origin_world_time := float(clock["origin_world_time"])
	var interval := float(clock["step_interval_world_time"])
	var relative := (target_world_time - origin_world_time) / interval
	if not is_finite(relative):
		return -1
	var relative_scale := maxf(1.0, absf(relative))
	var nearest := roundf(relative)
	if absf(relative - nearest) <= RELATIVE_EPSILON * relative_scale:
		relative = nearest
	if relative < 0.0:
		return int(clock["origin_generation"]) if absf(relative) <= RELATIVE_EPSILON else -1
	var offset_float: float = floorf(relative)
	if not is_finite(offset_float) or offset_float < 0.0 or offset_float > float(MAX_EXACT_GENERATION):
		return -1
	var offset := int(offset_float)
	var origin_generation := int(clock["origin_generation"])
	if origin_generation > MAX_EXACT_GENERATION - offset:
		return -1
	return origin_generation + offset

static func _normalized_positive_float(value) -> float:
	var result := _normalized_nonnegative_float(value)
	if is_nan(result) or result <= 0.0:
		return NAN
	return result

static func _normalized_nonnegative_float(value) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return NAN
	var result := float(value)
	if not is_finite(result) or result < 0.0:
		return NAN
	return result

static func _times_equal(a: float, b: float) -> bool:
	if not is_finite(a) or not is_finite(b):
		return false
	var scale := maxf(1.0, maxf(absf(a), absf(b)))
	return absf(a - b) <= TIME_EPSILON * scale

static func _is_hash(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true

static func _exact_fields(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true

static func _failure(error: String) -> Dictionary:
	return {"success": false, "error": error}
