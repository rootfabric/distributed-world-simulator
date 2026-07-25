extends RefCounted

enum Activity {
    WARM,
    ACTIVE,
}

var chunk_id
var activity: int = Activity.WARM
var center_direction: Vector3 = Vector3.UP
var last_seen_frame: int = 0
var owner_token: String = "local-process"
var terrain_revision: int = 0
var entity_count: int = 0


func setup(id_value, center_direction_value: Vector3) -> void:
    chunk_id = id_value
    center_direction = center_direction_value.normalized()


func set_activity(activity_value: int, frame_value: int) -> void:
    activity = activity_value
    last_seen_frame = frame_value


func is_active() -> bool:
    return activity == Activity.ACTIVE
