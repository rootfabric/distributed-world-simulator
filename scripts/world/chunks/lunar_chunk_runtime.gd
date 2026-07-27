extends RefCounted

const ChunkLifecycle = preload("res://scripts/simulation/lifecycle/chunk_lifecycle.gd")

enum Activity {
	WARM,
	ACTIVE,
}

var chunk_id
var activity: int = Activity.WARM
var lifecycle_state: String = ChunkLifecycle.WARM
var center_direction: Vector3 = Vector3.UP
var last_seen_frame: int = 0
var owner_token: String = "local-process"
var terrain_revision: int = 0
var entity_count: int = 0
var lifecycle_revision: int = 0


func setup(id_value, center_direction_value: Vector3) -> void:
	chunk_id = id_value
	center_direction = center_direction_value.normalized()
	lifecycle_state = ChunkLifecycle.WARM
	activity = Activity.WARM


func set_activity(activity_value: int, frame_value: int) -> void:
	var target_state: String = (
		ChunkLifecycle.ACTIVE
		if activity_value == Activity.ACTIVE
		else ChunkLifecycle.WARM
	)
	transition_lifecycle(target_state, frame_value)


func transition_lifecycle(next_state: String, frame_value: int = -1) -> Dictionary:
	var result: Dictionary = ChunkLifecycle.transition(lifecycle_state, next_state)
	if not bool(result.get("success", false)):
		return result
	if bool(result.get("changed", false)):
		lifecycle_state = next_state
		lifecycle_revision += 1
	if frame_value >= 0:
		last_seen_frame = frame_value
	activity = Activity.ACTIVE if lifecycle_state == ChunkLifecycle.ACTIVE else Activity.WARM
	result["lifecycle_revision"] = lifecycle_revision
	return result


func begin_unload(frame_value: int = -1) -> Dictionary:
	return transition_lifecycle(ChunkLifecycle.UNLOADING, frame_value)


func mark_dormant(frame_value: int = -1) -> Dictionary:
	return transition_lifecycle(ChunkLifecycle.DORMANT, frame_value)


func warm(frame_value: int = -1) -> Dictionary:
	return transition_lifecycle(ChunkLifecycle.WARM, frame_value)


func activate(frame_value: int = -1) -> Dictionary:
	return transition_lifecycle(ChunkLifecycle.ACTIVE, frame_value)


func is_active() -> bool:
	return lifecycle_state == ChunkLifecycle.ACTIVE


func create_snapshot() -> Dictionary:
	return {
		"schema": "planet_simulator.chunk_runtime.v1",
		"chunk_id": str(chunk_id),
		"lifecycle_state": lifecycle_state,
		"lifecycle_revision": lifecycle_revision,
		"last_seen_frame": last_seen_frame,
		"owner_token": owner_token,
		"terrain_revision": terrain_revision,
		"entity_count": entity_count,
	}
