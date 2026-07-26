extends RefCounted

var config: Dictionary = {}
var provider_type: String = "static"
var orbit_provider


func setup(config_value: Dictionary = {}, orbit_provider_reference = null) -> void:
	config = config_value.duplicate(true)
	provider_type = String(config.get("type", "static")).to_lower()
	orbit_provider = orbit_provider_reference


func sample_state(time_s: float) -> Dictionary:
	match provider_type:
		"uniform", "axial_tilt_uniform":
			return _sample_uniform(time_s)
		"tidally_locked":
			return _sample_tidally_locked(time_s)
		_:
			return _sample_static()


func create_snapshot() -> Dictionary:
	return {
		"type": provider_type,
		"config": config.duplicate(true),
	}


func _sample_static() -> Dictionary:
	return {
		"basis_parent_from_child": _base_tilt_basis(),
		"angular_velocity_parent_rps": Vector3.ZERO,
	}


func _sample_uniform(time_s: float) -> Dictionary:
	var period_s: float = maxf(0.000001, absf(float(config.get("period_s", 1.0))))
	var epoch_s: float = float(config.get("epoch_s", 0.0))
	var phase_rad: float = deg_to_rad(float(config.get("phase_deg", 0.0)))
	var direction_sign: float = -1.0 if bool(config.get("retrograde", false)) else 1.0
	var angular_speed: float = direction_sign * TAU / period_s
	var angle: float = phase_rad + (time_s - epoch_s) * angular_speed
	var tilt_basis: Basis = _base_tilt_basis()
	var spin_basis := Basis(Vector3.UP, angle)
	return {
		"basis_parent_from_child": (tilt_basis * spin_basis).orthonormalized(),
		"angular_velocity_parent_rps": (tilt_basis * Vector3.UP) * angular_speed,
	}


func _sample_tidally_locked(time_s: float) -> Dictionary:
	if orbit_provider == null:
		return _sample_static()
	var orbit_state: Dictionary = orbit_provider.sample_state(time_s)
	var position: Vector3 = orbit_state.get("position_m", Vector3.ZERO)
	var velocity: Vector3 = orbit_state.get("velocity_mps", Vector3.ZERO)
	if position.length_squared() < 0.000001:
		return _sample_static()
	var x_axis: Vector3 = (-position).normalized()
	var y_axis: Vector3 = position.cross(velocity)
	if y_axis.length_squared() < 0.000001:
		y_axis = Vector3.UP
	y_axis = y_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis)
	if z_axis.length_squared() < 0.000001:
		z_axis = x_axis.cross(Vector3.UP)
	if z_axis.length_squared() < 0.000001:
		z_axis = x_axis.cross(Vector3.RIGHT)
	z_axis = z_axis.normalized()
	y_axis = z_axis.cross(x_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis).orthonormalized()
	var phase_offset: float = deg_to_rad(float(config.get("phase_offset_deg", 0.0)))
	if not is_zero_approx(phase_offset):
		basis = (basis * Basis(Vector3.UP, phase_offset)).orthonormalized()
	var angular_velocity: Vector3 = Vector3.ZERO
	var radius_squared: float = position.length_squared()
	if radius_squared > 0.000001:
		angular_velocity = position.cross(velocity) / radius_squared
	return {
		"basis_parent_from_child": basis,
		"angular_velocity_parent_rps": angular_velocity,
	}


func _base_tilt_basis() -> Basis:
	var axial_tilt_rad: float = deg_to_rad(float(config.get("axial_tilt_deg", 0.0)))
	var ascending_node_rad: float = deg_to_rad(float(
		config.get("axis_longitude_deg", 0.0)
	))
	return (
		Basis(Vector3.UP, ascending_node_rad)
		* Basis(Vector3.FORWARD, axial_tilt_rad)
	).orthonormalized()
