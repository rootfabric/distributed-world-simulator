extends RefCounted

const ChunkLifecycle = preload("res://scripts/simulation/lifecycle/chunk_lifecycle.gd")

enum Activity {
	WARM,
	ACTIVE,
}

var zone_id
var center_direction: Vector3 = Vector3.UP
var activity: int = Activity.WARM
var lifecycle_state: String = ChunkLifecycle.WARM
var lifecycle_revision: int = 0
var last_seen_frame: int = 0
var owner_token: String = "local-process"
var chunks: Dictionary = {}


func setup(id_value, center_direction_value: Vector3) -> void:
	zone_id = id_value
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
	return _transition_with_children(ChunkLifecycle.UNLOADING, "begin_unload", frame_value)


func mark_dormant(frame_value: int = -1) -> Dictionary:
	return _transition_with_children(ChunkLifecycle.DORMANT, "mark_dormant", frame_value)


func _transition_with_children(next_state: String, child_method: String, frame_value: int) -> Dictionary:
	var zone_preflight: Dictionary = ChunkLifecycle.transition(lifecycle_state, next_state)
	if not bool(zone_preflight.get("success", false)):
		return zone_preflight
	for chunk_id_value in chunks.keys():
		var chunk = chunks[chunk_id_value]
		if chunk == null or not chunk.has_method(child_method):
			return {
				"success": false,
				"error_code": "CHILD_CHUNK_LIFECYCLE_UNAVAILABLE",
				"chunk_id": str(chunk_id_value),
			}
		var child_state: String = String(chunk.get("lifecycle_state"))
		var child_preflight: Dictionary = ChunkLifecycle.transition(child_state, next_state)
		if not bool(child_preflight.get("success", false)):
			return {
				"success": false,
				"error_code": "CHILD_CHUNK_TRANSITION_FAILED",
				"chunk_id": str(chunk_id_value),
				"cause": child_preflight,
			}
	for chunk_id_value in chunks.keys():
		var child_result: Dictionary = chunks[chunk_id_value].call(child_method, frame_value)
		if not bool(child_result.get("success", false)):
			return {
				"success": false,
				"error_code": "CHILD_CHUNK_TRANSITION_FAILED",
				"chunk_id": str(chunk_id_value),
				"cause": child_result,
			}
	return transition_lifecycle(next_state, frame_value)


func warm(frame_value: int = -1) -> Dictionary:
	return transition_lifecycle(ChunkLifecycle.WARM, frame_value)


func activate(frame_value: int = -1) -> Dictionary:
	return transition_lifecycle(ChunkLifecycle.ACTIVE, frame_value)


func is_active() -> bool:
	return lifecycle_state == ChunkLifecycle.ACTIVE


func active_chunk_count() -> int:
	var result: int = 0
	for chunk_value in chunks.values():
		if chunk_value.is_active():
			result += 1
	return result


func create_snapshot() -> Dictionary:
	return {
		"schema": "planet_simulator.zone_runtime.v1",
		"zone_id": str(zone_id),
		"lifecycle_state": lifecycle_state,
		"lifecycle_revision": lifecycle_revision,
		"last_seen_frame": last_seen_frame,
		"owner_token": owner_token,
		"chunk_count": chunks.size(),
		"active_chunk_count": active_chunk_count(),
	}
