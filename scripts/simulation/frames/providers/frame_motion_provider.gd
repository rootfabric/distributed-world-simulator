extends RefCounted

var origin_provider
var rotation_provider


func setup(origin_provider_reference = null, rotation_provider_reference = null) -> void:
	origin_provider = origin_provider_reference
	rotation_provider = rotation_provider_reference


func sample_state(time_s: float) -> Dictionary:
	var origin_state: Dictionary = (
		origin_provider.sample_state(time_s)
		if origin_provider != null
		else {
			"position_m": Vector3.ZERO,
			"velocity_mps": Vector3.ZERO,
		}
	)
	var rotation_state: Dictionary = (
		rotation_provider.sample_state(time_s)
		if rotation_provider != null
		else {
			"basis_parent_from_child": Basis.IDENTITY,
			"angular_velocity_parent_rps": Vector3.ZERO,
		}
	)
	return {
		"origin_parent_m": origin_state.get("position_m", Vector3.ZERO),
		"basis_parent_from_child": rotation_state.get(
			"basis_parent_from_child",
			Basis.IDENTITY
		),
		"linear_velocity_parent_mps": origin_state.get(
			"velocity_mps",
			Vector3.ZERO
		),
		"angular_velocity_parent_rps": rotation_state.get(
			"angular_velocity_parent_rps",
			Vector3.ZERO
		),
	}
