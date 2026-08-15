extends RefCounted

func sample(_position: Vector3) -> Dictionary:
	return {}

func sample_context(position: Vector3, slope_degrees: float = 0.0) -> Dictionary:
	return {
		"environment": sample(position),
		"altitude_m": position.y,
		"slope_degrees": maxf(0.0, slope_degrees),
		"water_distance_m": INF,
		"water_availability": 0.0,
	}

func get_environment_revision() -> String:
	return ""

func get_seed() -> int:
	return 0
