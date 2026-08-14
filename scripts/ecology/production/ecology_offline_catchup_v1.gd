extends RefCounted

const EcologyClock = preload("res://scripts/ecology/production/ecology_clock_v1.gd")
const RegionState = preload("res://scripts/ecology/production/ecology_region_state_v1.gd")
const Persistence = preload("res://scripts/research/ecology/plant_ecosystem_persistence_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p4_3_offline_catchup.v1"
const VERSION := "1.0.0"
const PARENT_P4_2_ACCEPTED_AGGREGATE := "607884ed9ce2d398fb225928f03f423f4fd2ae4198c12d066aa74c6ce421a42e"
const MAX_EXACT_GENERATION := EcologyClock.MAX_EXACT_GENERATION
const STATE_FIELDS := [
	"schema",
	"version",
	"parent_p4_2_accepted_aggregate",
	"clock",
	"clock_hash",
	"observed_target_world_time",
	"region_state",
	"region_state_hash",
	"remaining_due_steps",
	"fully_caught_up",
	"catchup_hash",
]

static func create(region_state: Dictionary, observed_target_world_time_value, clock: Dictionary) -> Dictionary:
	if not bool(RegionState.validate_region_state(region_state).get("success", false)):
		return {}
	if not bool(EcologyClock.validate_clock(clock).get("success", false)):
		return {}
	if not bool(EcologyClock.validate_bound_region(region_state, clock).get("success", false)):
		return {}
	var target := _normalized_nonnegative_float(observed_target_world_time_value)
	if is_nan(target):
		return {}
	return _build(region_state, target, clock)

static func create_from_elapsed(region_state: Dictionary, offline_elapsed_world_time_value, clock: Dictionary) -> Dictionary:
	var elapsed := _normalized_nonnegative_float(offline_elapsed_world_time_value)
	if is_nan(elapsed):
		return {}
	if not bool(EcologyClock.validate_bound_region(region_state, clock).get("success", false)):
		return {}
	var boundary := float(region_state.get("last_simulated_world_time", NAN))
	var target := boundary + elapsed
	if not is_finite(target) or target < boundary:
		return {}
	return _build(region_state, target, clock)

static func extend_elapsed(state: Dictionary, additional_elapsed_world_time_value) -> Dictionary:
	if not bool(validate_state(state).get("success", false)):
		return {}
	var elapsed := _normalized_nonnegative_float(additional_elapsed_world_time_value)
	if is_nan(elapsed):
		return {}
	var target := float(state["observed_target_world_time"]) + elapsed
	if not is_finite(target) or target < float(state["observed_target_world_time"]):
		return {}
	return _build(Dictionary(state["region_state"]), target, Dictionary(state["clock"]))

static func observe_target(state: Dictionary, observed_target_world_time_value) -> Dictionary:
	if not bool(validate_state(state).get("success", false)):
		return {}
	var target := _normalized_nonnegative_float(observed_target_world_time_value)
	if is_nan(target):
		return {}
	var previous := float(state["observed_target_world_time"])
	if target < previous:
		return {}
	return _build(Dictionary(state["region_state"]), target, Dictionary(state["clock"]))

static func advance_batch(state: Dictionary, max_steps_value) -> Dictionary:
	if not bool(validate_state(state).get("success", false)):
		return {}
	if typeof(max_steps_value) != TYPE_INT:
		return {}
	var max_steps := int(max_steps_value)
	if max_steps <= 0 or max_steps > Persistence.MAX_ADVANCE_STEPS:
		return {}
	var remaining := int(state["remaining_due_steps"])
	if remaining == 0:
		return state.duplicate(true)
	var applied_steps := mini(remaining, max_steps)
	var region: Dictionary = state["region_state"]
	var current_generation := int(region["ecology_generation"])
	if current_generation > MAX_EXACT_GENERATION - applied_steps:
		return {}
	var target_generation := current_generation + applied_steps
	var clock: Dictionary = state["clock"]
	var batch_boundary := EcologyClock.boundary_time_for_generation(target_generation, clock)
	if is_nan(batch_boundary):
		return {}
	var advanced_region := EcologyClock.advance_to(region, batch_boundary, clock)
	if advanced_region.is_empty():
		return {}
	return _build(advanced_region, float(state["observed_target_world_time"]), clock)

static func validate_state(state: Dictionary) -> Dictionary:
	if not _exact_fields(state, STATE_FIELDS):
		return _failure("STATE_FIELDS_MISMATCH")
	if String(state.get("schema", "")) != SCHEMA or String(state.get("version", "")) != VERSION:
		return _failure("SCHEMA_OR_VERSION_MISMATCH")
	if String(state.get("parent_p4_2_accepted_aggregate", "")) != PARENT_P4_2_ACCEPTED_AGGREGATE:
		return _failure("PARENT_P4_2_MISMATCH")
	if typeof(state.get("clock")) != TYPE_DICTIONARY:
		return _failure("CLOCK_TYPE_INVALID")
	var clock: Dictionary = state["clock"]
	if not bool(EcologyClock.validate_clock(clock).get("success", false)):
		return _failure("CLOCK_INVALID")
	if String(state.get("clock_hash", "")) != String(clock.get("clock_hash", "")):
		return _failure("CLOCK_HASH_MISMATCH")
	if typeof(state.get("region_state")) != TYPE_DICTIONARY:
		return _failure("REGION_TYPE_INVALID")
	var region: Dictionary = state["region_state"]
	if not bool(RegionState.validate_region_state(region).get("success", false)):
		return _failure("REGION_INVALID")
	if String(state.get("region_state_hash", "")) != String(region.get("region_state_hash", "")):
		return _failure("REGION_HASH_MISMATCH")
	if not bool(EcologyClock.validate_bound_region(region, clock).get("success", false)):
		return _failure("REGION_CLOCK_BINDING_INVALID")
	if typeof(state.get("observed_target_world_time")) != TYPE_FLOAT:
		return _failure("TARGET_TYPE_INVALID")
	var target := float(state["observed_target_world_time"])
	if not is_finite(target) or target < 0.0:
		return _failure("TARGET_RANGE_INVALID")
	var plan := EcologyClock.due_plan(region, target, clock)
	if not bool(plan.get("success", false)):
		return _failure("TARGET_PLAN_INVALID")
	if typeof(state.get("remaining_due_steps")) != TYPE_INT:
		return _failure("REMAINING_TYPE_INVALID")
	var remaining := int(state["remaining_due_steps"])
	if remaining < 0 or remaining != int(plan.get("due_steps", -1)):
		return _failure("REMAINING_DERIVED_MISMATCH")
	if typeof(state.get("fully_caught_up")) != TYPE_BOOL:
		return _failure("CAUGHT_UP_TYPE_INVALID")
	if bool(state["fully_caught_up"]) != (remaining == 0):
		return _failure("CAUGHT_UP_DERIVED_MISMATCH")
	var expected_hash := compute_catchup_hash(state)
	if String(state.get("catchup_hash", "")) != expected_hash:
		return _failure("CATCHUP_HASH_MISMATCH")
	return {"success": true, "error": "", "remaining_due_steps": remaining, "fully_caught_up": remaining == 0, "catchup_hash": expected_hash}

static func compute_catchup_hash(state: Dictionary) -> String:
	var canonical := [
		String(state.get("schema", "")),
		String(state.get("version", "")),
		String(state.get("parent_p4_2_accepted_aggregate", "")),
		String(state.get("clock_hash", "")),
		state.get("observed_target_world_time", NAN),
		String(state.get("region_state_hash", "")),
		state.get("remaining_due_steps", -1),
		state.get("fully_caught_up", false),
	]
	return JSON.stringify(canonical).sha256_text()

static func _build(region_state: Dictionary, target: float, clock: Dictionary) -> Dictionary:
	var plan := EcologyClock.due_plan(region_state, target, clock)
	if not bool(plan.get("success", false)):
		return {}
	var remaining := int(plan.get("due_steps", -1))
	if remaining < 0:
		return {}
	var state := {
		"schema": SCHEMA,
		"version": VERSION,
		"parent_p4_2_accepted_aggregate": PARENT_P4_2_ACCEPTED_AGGREGATE,
		"clock": clock.duplicate(true),
		"clock_hash": String(clock.get("clock_hash", "")),
		"observed_target_world_time": target,
		"region_state": region_state.duplicate(true),
		"region_state_hash": String(region_state.get("region_state_hash", "")),
		"remaining_due_steps": remaining,
		"fully_caught_up": remaining == 0,
	}
	state["catchup_hash"] = compute_catchup_hash(state)
	if not bool(validate_state(state).get("success", false)):
		return {}
	return state

static func _normalized_nonnegative_float(value) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return NAN
	var result := float(value)
	if not is_finite(result) or result < 0.0:
		return NAN
	return result

static func _exact_fields(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true

static func _failure(error: String) -> Dictionary:
	return {"success": false, "error": "ECO_P4_3_" + error}
