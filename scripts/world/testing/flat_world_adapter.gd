extends Node

var spawn_position: Vector3 = Vector3(0.0, 1.2, 6.0)


func setup(spawn_value: Vector3) -> void:
	spawn_position = spawn_value


func render_to_world(render_position: Vector3) -> Vector3:
	return render_position


func world_to_render(world_position: Vector3) -> Vector3:
	return world_position


func get_gravity_at_distance(_distance_from_center: float) -> float:
	return 9.81


func recenter_player(_actor) -> void:
	pass


func get_altitude(world_position: Vector3) -> float:
	return world_position.y


func recover_actor(actor) -> void:
	actor.global_position = spawn_position
	actor.velocity = Vector3.ZERO
	actor.reset_physics_interpolation()
