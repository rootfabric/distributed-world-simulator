extends RefCounted

const DEFAULT_INTERIOR_MODEL: String = "uniform_sphere"
const MIN_DISTANCE_M: float = 0.000001


static func resolve_gravitational_parameter(source: Dictionary) -> float:
	var explicit_mu: float = float(
		source.get("gravitational_parameter_m3_s2", 0.0)
	)
	if explicit_mu > 0.0:
		return explicit_mu
	var radius_m: float = float(source.get("radius_m", 0.0))
	var surface_gravity_mps2: float = float(
		source.get("gravity_mps2", source.get("surface_gravity_mps2", 0.0))
	)
	if radius_m <= 0.0 or surface_gravity_mps2 <= 0.0:
		return 0.0
	return surface_gravity_mps2 * radius_m * radius_m


static func acceleration_from_source(
	position_m: Vector3,
	center_m: Vector3,
	radius_m: float,
	gravitational_parameter_m3_s2: float,
	interior_model: String = DEFAULT_INTERIOR_MODEL
) -> Vector3:
	if gravitational_parameter_m3_s2 <= 0.0:
		return Vector3.ZERO
	var toward_center: Vector3 = center_m - position_m
	var distance_m: float = toward_center.length()
	if distance_m <= MIN_DISTANCE_M:
		return Vector3.ZERO
	var magnitude_mps2: float = acceleration_magnitude(
		distance_m,
		radius_m,
		gravitational_parameter_m3_s2,
		interior_model
	)
	return toward_center / distance_m * magnitude_mps2


static func acceleration_magnitude(
	distance_from_center_m: float,
	radius_m: float,
	gravitational_parameter_m3_s2: float,
	interior_model: String = DEFAULT_INTERIOR_MODEL
) -> float:
	if gravitational_parameter_m3_s2 <= 0.0:
		return 0.0
	var distance_m: float = absf(distance_from_center_m)
	if distance_m <= MIN_DISTANCE_M:
		return 0.0
	if radius_m > MIN_DISTANCE_M and distance_m < radius_m:
		match interior_model:
			"none":
				return 0.0
			"surface_clamp":
				return gravitational_parameter_m3_s2 / (radius_m * radius_m)
			_:
				# Uniform-density sphere. This avoids a singularity and reaches
				# exactly zero acceleration at the body's centre.
				return (
					gravitational_parameter_m3_s2
					* distance_m
					/ (radius_m * radius_m * radius_m)
				)
	return gravitational_parameter_m3_s2 / (distance_m * distance_m)


static func circular_orbit_speed_mps(
	orbital_radius_m: float,
	gravitational_parameter_m3_s2: float
) -> float:
	if orbital_radius_m <= MIN_DISTANCE_M or gravitational_parameter_m3_s2 <= 0.0:
		return 0.0
	return sqrt(gravitational_parameter_m3_s2 / orbital_radius_m)


static func escape_speed_mps(
	distance_from_center_m: float,
	gravitational_parameter_m3_s2: float
) -> float:
	if distance_from_center_m <= MIN_DISTANCE_M or gravitational_parameter_m3_s2 <= 0.0:
		return 0.0
	return sqrt(2.0 * gravitational_parameter_m3_s2 / distance_from_center_m)
