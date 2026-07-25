extends Node

const MOON_RADIUS: float = 1_737_400.0


func get_moon_radius() -> float:
	return MOON_RADIUS


func get_world_seed() -> int:
	return 20260724


func get_generator_version() -> int:
	return 9


func get_surface_point(direction_value: Vector3) -> Vector3:
	return direction_value.normalized() * MOON_RADIUS


func world_to_render(world_position: Vector3) -> Vector3:
	return world_position
