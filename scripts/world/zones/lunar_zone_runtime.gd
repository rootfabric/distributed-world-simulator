extends RefCounted

enum Activity {
    WARM,
    ACTIVE,
}

var zone_id
var center_direction: Vector3 = Vector3.UP
var activity: int = Activity.WARM
var last_seen_frame: int = 0
var owner_token: String = "local-process"
var chunks: Dictionary = {}


func setup(id_value, center_direction_value: Vector3) -> void:
    zone_id = id_value
    center_direction = center_direction_value.normalized()


func set_activity(activity_value: int, frame_value: int) -> void:
    activity = activity_value
    last_seen_frame = frame_value


func is_active() -> bool:
    return activity == Activity.ACTIVE


func active_chunk_count() -> int:
    var result: int = 0
    for chunk_value in chunks.values():
        if chunk_value.is_active():
            result += 1
    return result
