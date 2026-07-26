extends RefCounted

const MIN_ECCENTRICITY_DENOMINATOR: float = 0.0000001

var config: Dictionary = {}
var provider_type: String = "static"


func setup(config_value: Dictionary = {}) -> void:
	config = config_value.duplicate(true)
	provider_type = String(config.get("type", "static")).to_lower()


func sample_state(time_s: float) -> Dictionary:
	match provider_type:
		"circular":
			return _sample_circular(time_s)
		"kepler":
			return _sample_kepler(time_s)
		_:
			return _sample_static()


func create_snapshot() -> Dictionary:
	return {
		"type": provider_type,
		"config": config.duplicate(true),
	}


func _sample_static() -> Dictionary:
	return {
		"position_m": _array_to_vector3(config.get("position_m", [0.0, 0.0, 0.0])),
		"velocity_mps": _array_to_vector3(config.get("velocity_mps", [0.0, 0.0, 0.0])),
	}


func _sample_circular(time_s: float) -> Dictionary:
	var radius_m: float = float(config.get("radius_m", 0.0))
	var period_s: float = maxf(0.000001, absf(float(config.get("period_s", 1.0))))
	var epoch_s: float = float(config.get("epoch_s", 0.0))
	var phase_rad: float = deg_to_rad(float(config.get("phase_deg", 0.0)))
	var direction_sign: float = -1.0 if bool(config.get("retrograde", false)) else 1.0
	var angular_speed: float = direction_sign * TAU / period_s
	var angle: float = phase_rad + (time_s - epoch_s) * angular_speed
	var position := Vector3(cos(angle) * radius_m, 0.0, sin(angle) * radius_m)
	var velocity := Vector3(-sin(angle), 0.0, cos(angle)) * radius_m * angular_speed
	var orientation: Basis = _orbital_plane_basis()
	return {
		"position_m": orientation * position,
		"velocity_mps": orientation * velocity,
	}


func _sample_kepler(time_s: float) -> Dictionary:
	var semi_major_axis_m: float = maxf(0.0, float(config.get("semi_major_axis_m", 0.0)))
	var eccentricity: float = clampf(float(config.get("eccentricity", 0.0)), 0.0, 0.999999)
	var period_s: float = maxf(0.000001, absf(float(config.get("period_s", 1.0))))
	var epoch_s: float = float(config.get("epoch_s", 0.0))
	var mean_anomaly_at_epoch: float = deg_to_rad(float(
		config.get("mean_anomaly_at_epoch_deg", 0.0)
	))
	var direction_sign: float = -1.0 if bool(config.get("retrograde", false)) else 1.0
	var mean_motion: float = direction_sign * TAU / period_s
	var mean_anomaly: float = wrapf(
		mean_anomaly_at_epoch + (time_s - epoch_s) * mean_motion,
		-PI,
		PI
	)
	var eccentric_anomaly: float = _solve_eccentric_anomaly(mean_anomaly, eccentricity)
	var cos_e: float = cos(eccentric_anomaly)
	var sin_e: float = sin(eccentric_anomaly)
	var sqrt_one_minus_e2: float = sqrt(maxf(0.0, 1.0 - eccentricity * eccentricity))
	var position_plane := Vector3(
		semi_major_axis_m * (cos_e - eccentricity),
		0.0,
		semi_major_axis_m * sqrt_one_minus_e2 * sin_e
	)
	var eccentric_anomaly_rate: float = mean_motion / maxf(
		MIN_ECCENTRICITY_DENOMINATOR,
		1.0 - eccentricity * cos_e
	)
	var velocity_plane := Vector3(
		-semi_major_axis_m * sin_e * eccentric_anomaly_rate,
		0.0,
		semi_major_axis_m * sqrt_one_minus_e2 * cos_e * eccentric_anomaly_rate
	)
	var orientation: Basis = _orbital_plane_basis()
	return {
		"position_m": orientation * position_plane,
		"velocity_mps": orientation * velocity_plane,
	}


func _solve_eccentric_anomaly(mean_anomaly: float, eccentricity: float) -> float:
	var eccentric_anomaly: float = mean_anomaly if eccentricity < 0.8 else PI
	for _iteration in range(12):
		var function_value: float = (
			eccentric_anomaly
			- eccentricity * sin(eccentric_anomaly)
			- mean_anomaly
		)
		var derivative: float = 1.0 - eccentricity * cos(eccentric_anomaly)
		if absf(derivative) < MIN_ECCENTRICITY_DENOMINATOR:
			break
		var correction: float = function_value / derivative
		eccentric_anomaly -= correction
		if absf(correction) < 0.000000000001:
			break
	return eccentric_anomaly


func _orbital_plane_basis() -> Basis:
	var longitude_ascending_node: float = deg_to_rad(float(
		config.get("longitude_ascending_node_deg", 0.0)
	))
	var inclination: float = deg_to_rad(float(config.get("inclination_deg", 0.0)))
	var argument_periapsis: float = deg_to_rad(float(
		config.get("argument_periapsis_deg", 0.0)
	))
	return (
		Basis(Vector3.UP, longitude_ascending_node)
		* Basis(Vector3.RIGHT, inclination)
		* Basis(Vector3.UP, argument_periapsis)
	).orthonormalized()


func _array_to_vector3(value) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
