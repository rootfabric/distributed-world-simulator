extends SceneTree

const MovementService = preload("res://scripts/runtime/networked_gameplay/services/player_movement_service.gd")
const ItemGraphBase = preload("res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_base.gd")

const SPAWN_A := Vector3(-5.0, 0.0, 0.0)
const TARGET_BEACON := Vector3(1.2, 0.4, -3.4)
const INTERACTION_ORIGIN_Y_OFFSET := 0.9
const LEGACY_STEPS := 12
const READY_HORIZONTAL_DISTANCE_M := 2.5
const MAX_STEPS := 64

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var per_tick_progress := MovementService.PLAYGROUND_WALK_SPEED_MPS * (1.0 / 60.0)
	_assert(is_equal_approx(per_tick_progress, 0.1), "fixed-tick minimum progress is 0.1m per acknowledged tick")
	var horizontal := (TARGET_BEACON - SPAWN_A).slide(Vector3.UP)
	var direction := horizontal.normalized()
	var legacy_position := SPAWN_A + direction * per_tick_progress * LEGACY_STEPS
	var legacy_origin := legacy_position + Vector3(0.0, INTERACTION_ORIGIN_Y_OFFSET, 0.0)
	var legacy_distance := legacy_origin.distance_to(TARGET_BEACON)
	_assert(legacy_distance > ItemGraphBase.SANDBOX_PICKUP_RANGE_M, "legacy 12-step minimum-progress budget does not guarantee canonical pickup range")
	_assert(READY_HORIZONTAL_DISTANCE_M < ItemGraphBase.SANDBOX_PICKUP_RANGE_M, "repair readiness threshold is conservative relative to canonical pickup range")

	var simulated_position := SPAWN_A
	var steps := 0
	while (TARGET_BEACON - simulated_position).slide(Vector3.UP).length() > READY_HORIZONTAL_DISTANCE_M and steps < MAX_STEPS:
		var to_target := (TARGET_BEACON - simulated_position).slide(Vector3.UP)
		simulated_position += to_target.normalized() * per_tick_progress
		steps += 1
	_assert(steps > LEGACY_STEPS, "minimum-progress schedule needs more than legacy fixed step count")
	_assert(steps <= MAX_STEPS, "bounded repair budget reaches conservative readiness even at one tick per command")
	var ready_origin := simulated_position + Vector3(0.0, INTERACTION_ORIGIN_Y_OFFSET, 0.0)
	_assert(ready_origin.distance_to(TARGET_BEACON) < ItemGraphBase.SANDBOX_PICKUP_RANGE_M, "conservative horizontal readiness proves canonical pickup distance")

	print("M7 recovery seed approach regression: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)
