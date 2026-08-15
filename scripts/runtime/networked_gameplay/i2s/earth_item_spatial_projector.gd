extends RefCounted

const RESULT_SCHEMA := "planet_simulator.i2s_earth_item_spatial_projection.v1"

var _earth_world
var _anchor_direction: Vector3 = Vector3.ZERO


func setup(earth_world_reference, anchor_direction: Vector3 = Vector3.ZERO) -> Dictionary:
	if (
		earth_world_reference == null
		or not earth_world_reference.has_method("get_surface_point")
		or not earth_world_reference.has_method("world_to_render")
	):
		return _failure("I2S_EARTH_WORLD_PROJECTION_REQUIRED")
	_earth_world = earth_world_reference
	if anchor_direction.length_squared() > 0.5:
		_anchor_direction = anchor_direction.normalized()
	elif _earth_world.has_method("get_canonical_spawn_direction"):
		var canonical_anchor = _earth_world.call("get_canonical_spawn_direction")
		if typeof(canonical_anchor) == TYPE_VECTOR3:
			_anchor_direction = Vector3(canonical_anchor).normalized()
	if _anchor_direction.length_squared() <= 0.5:
		return _failure("I2S_EARTH_ANCHOR_REQUIRED")
	return _success()


func set_anchor_direction(anchor_direction: Vector3) -> Dictionary:
	if anchor_direction.length_squared() <= 0.5:
		return _failure("I2S_EARTH_ANCHOR_REQUIRED")
	_anchor_direction = anchor_direction.normalized()
	return _success()


func project_transform(canonical_transform: Transform3D) -> Dictionary:
	if _earth_world == null or _anchor_direction.length_squared() <= 0.5:
		return _failure("I2S_EARTH_PROJECTOR_NOT_CONFIGURED")
	var anchor_surface_value = _earth_world.call("get_surface_point", _anchor_direction)
	if typeof(anchor_surface_value) != TYPE_VECTOR3:
		return _failure("I2S_EARTH_PROJECTION_INVALID")
	var anchor_surface: Vector3 = anchor_surface_value
	var anchor_east := _make_east(_anchor_direction)
	var anchor_north := anchor_east.cross(_anchor_direction).normalized()
	var local_position := canonical_transform.origin
	var tangent_surface := (
		anchor_surface
		+ anchor_east * local_position.x
		- anchor_north * local_position.z
	)
	if tangent_surface.length_squared() <= 1.0:
		return _failure("I2S_EARTH_PROJECTION_INVALID")
	var surface_direction := tangent_surface.normalized()
	var surface_world_value = _earth_world.call("get_surface_point", surface_direction)
	if typeof(surface_world_value) != TYPE_VECTOR3:
		return _failure("I2S_EARTH_PROJECTION_INVALID")
	var surface_world: Vector3 = surface_world_value
	var world_position := surface_world + surface_direction * local_position.y
	var render_position_value = _earth_world.call("world_to_render", world_position)
	if typeof(render_position_value) != TYPE_VECTOR3:
		return _failure("I2S_EARTH_PROJECTION_INVALID")
	var render_position: Vector3 = render_position_value

	var local_east := anchor_east - surface_direction * anchor_east.dot(surface_direction)
	if local_east.length_squared() <= 0.000001:
		local_east = _make_east(surface_direction)
	else:
		local_east = local_east.normalized()
	var local_north := local_east.cross(surface_direction).normalized()
	var tangent_basis := Basis(local_east, surface_direction, -local_north)
	var render_basis := (tangent_basis * canonical_transform.basis).orthonormalized()
	return _success({
		"transform": Transform3D(render_basis, render_position),
		"world_position": world_position,
		"surface_direction": surface_direction,
	})


func _make_east(up_direction: Vector3) -> Vector3:
	var reference := Vector3.UP
	if absf(up_direction.normalized().dot(reference)) > 0.98:
		reference = Vector3.FORWARD
	var east := reference.cross(up_direction.normalized())
	if east.length_squared() <= 0.000001:
		east = Vector3.RIGHT
	return east.normalized()


func _success(details: Dictionary = {}) -> Dictionary:
	return {
		"schema": RESULT_SCHEMA,
		"success": true,
		"error_code": "",
		"details": details.duplicate(true),
	}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"schema": RESULT_SCHEMA,
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
