extends Node

signal focus_changed(snapshot: Dictionary)
signal interaction_completed(result: Dictionary)

const INTERACTABLE_GROUP: StringName = &"world_interactable"
const DISTANCE_SNAPSHOT_STEP_M: float = 0.1
const POSITION_SNAPSHOT_STEP_M: float = 0.05

var actor: Node3D
var logger
var interaction_distance_m: float = 6.0
var collision_mask: int = 1
var enabled: bool = false
var current_target: Node
var current_hit_position: Vector3 = Vector3.ZERO
var current_distance_m: float = 0.0
var current_snapshot: Dictionary = {}


func setup(actor_reference: Node3D, logger_reference = null) -> void:
	actor = actor_reference
	logger = logger_reference
	set_physics_process(true)


func set_enabled(enabled_value: bool) -> void:
	if enabled == enabled_value:
		return
	enabled = enabled_value
	if not enabled:
		_clear_focus()


func is_enabled() -> bool:
	return enabled


func get_current_snapshot() -> Dictionary:
	return current_snapshot.duplicate(true)


func perform_interaction() -> Dictionary:
	if not enabled or current_target == null or not is_instance_valid(current_target):
		return {
			"success": false,
			"message": "Нет объекта для взаимодействия",
		}
	if not current_target.has_method("interact"):
		return {
			"success": false,
			"message": "Объект не поддерживает действие",
		}
	var target := current_target
	var target_path: String = (
		str(target.get_path())
		if target.is_inside_tree()
		else str(target.name)
	)
	var action_distance_m: float = current_distance_m
	var context: Dictionary = {
		"distance_m": action_distance_m,
		"hit_position": current_hit_position,
	}
	var raw_result = target.call("interact", actor, context)
	var result: Dictionary = (
		raw_result.duplicate(true)
		if raw_result is Dictionary
		else {
			"success": bool(raw_result),
			"message": "Взаимодействие выполнено" if bool(raw_result) else "Действие не выполнено",
		}
	)
	if current_target != null and is_instance_valid(current_target):
		_refresh_snapshot()
	interaction_completed.emit(result)
	_log("interaction_performed", {
		"target": target_path,
		"distance_m": action_distance_m,
		"result": result,
	})
	return result


func _physics_process(_delta: float) -> void:
	if not enabled or actor == null or not is_instance_valid(actor):
		_clear_focus()
		return
	var camera: Camera3D = null
	if actor.has_method("get_active_camera"):
		camera = actor.call("get_active_camera") as Camera3D
	if camera == null or not is_instance_valid(camera):
		_clear_focus()
		return
	var world: World3D = actor.get_world_3d()
	if world == null:
		_clear_focus()
		return
	var from: Vector3 = camera.global_position
	var to: Vector3 = from + (-camera.global_transform.basis.z).normalized() * interaction_distance_m
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var collision_actor := actor as CollisionObject3D
	if collision_actor != null:
		query.exclude = [collision_actor.get_rid()]
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_clear_focus()
		return
	var target: Node = _resolve_interactable(hit.get("collider"))
	if target == null:
		_clear_focus()
		return
	var hit_position: Vector3 = hit.get("position", to)
	var distance_m: float = from.distance_to(hit_position)
	_set_focus(target, hit_position, distance_m)


func _resolve_interactable(collider) -> Node:
	var current: Node = collider as Node
	while current != null:
		if (
			current.is_in_group(INTERACTABLE_GROUP)
			and current.has_method("get_interaction_descriptor")
			and current.has_method("interact")
		):
			return current
		current = current.get_parent()
	return null


func _set_focus(target: Node, hit_position: Vector3, distance_m: float) -> void:
	var changed: bool = target != current_target
	if changed and current_target != null and is_instance_valid(current_target):
		if current_target.has_method("set_interaction_focus"):
			current_target.call("set_interaction_focus", false)
	current_target = target
	current_hit_position = hit_position
	current_distance_m = distance_m
	if changed and current_target.has_method("set_interaction_focus"):
		current_target.call("set_interaction_focus", true)
	_refresh_snapshot()


func _refresh_snapshot() -> void:
	if current_target == null or not is_instance_valid(current_target):
		_clear_focus()
		return
	var raw_snapshot = current_target.call("get_interaction_descriptor", actor)
	var next_snapshot: Dictionary = (
		raw_snapshot.duplicate(true) if raw_snapshot is Dictionary else {}
	)
	next_snapshot["distance_m"] = snappedf(
		current_distance_m,
		DISTANCE_SNAPSHOT_STEP_M
	)
	next_snapshot["hit_position"] = [
		snappedf(current_hit_position.x, POSITION_SNAPSHOT_STEP_M),
		snappedf(current_hit_position.y, POSITION_SNAPSHOT_STEP_M),
		snappedf(current_hit_position.z, POSITION_SNAPSHOT_STEP_M),
	]
	if next_snapshot != current_snapshot:
		current_snapshot = next_snapshot
		focus_changed.emit(current_snapshot.duplicate(true))


func _clear_focus() -> void:
	if current_target != null and is_instance_valid(current_target):
		if current_target.has_method("set_interaction_focus"):
			current_target.call("set_interaction_focus", false)
	current_target = null
	current_hit_position = Vector3.ZERO
	current_distance_m = 0.0
	if not current_snapshot.is_empty():
		current_snapshot = {}
		focus_changed.emit({})


func _log(event_name: String, data: Dictionary) -> void:
	if logger != null and logger.has_method("info"):
		logger.info("interaction", event_name, data)
