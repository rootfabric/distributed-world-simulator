extends RefCounted

const EarthSurfaceRenderProjector = preload(
	"res://scripts/app/earth_surface_render_projector.gd"
)
const RESULT_SCHEMA := "planet_simulator.i2s_earth_item_spatial_projection.v1"

var _earth_world
var _anchor_direction: Vector3 = Vector3.ZERO


func setup(earth_world_reference, anchor_direction: Vector3 = Vector3.ZERO) -> Dictionary:
	if (
		earth_world_reference == null
		or not earth_world_reference.has_method("get_surface_point")
		or not earth_world_reference.has_method("get_render_origin")
	):
		return _failure("I2S_EARTH_WORLD_PROJECTION_REQUIRED")
	_earth_world = earth_world_reference
	if anchor_direction.length_squared() > 0.5:
		_anchor_direction = anchor_direction.normalized()
	elif _earth_world.has_method("get_canonical_spawn_direction"):
		var canonical_anchor = _earth_world.call("get_canonical_spawn_direction")
		if typeof(canonical_anchor) == TYPE_VECTOR3:
			_anchor_direction = canonical_anchor.normalized()
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
	# Match earth_mvp_app.gd exactly: north = up x east, and M3 -Z is north.
	var anchor_north := _anchor_direction.cross(anchor_east).normalized()
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

	var local_east := anchor_east - surface_direction * anchor_east.dot(surface_direction)
	if local_east.length_squared() <= 0.000001:
		local_east = _make_east(surface_direction)
	else:
		local_east = local_east.normalized()
	var local_north := surface_direction.cross(local_east).normalized()
	var surface_basis := Basis(local_east, surface_direction, -local_north).orthonormalized()
	var earth_fixed_transform := Transform3D(
		(surface_basis * canonical_transform.basis).orthonormalized(),
		world_position
	)
	var render_origin_value = _earth_world.call("get_render_origin")
	if typeof(render_origin_value) != TYPE_VECTOR3:
		return _failure("I2S_EARTH_PROJECTION_INVALID")
	var render_origin: Vector3 = render_origin_value
	var frame_basis := Basis.IDENTITY
	if _earth_world is Node3D:
		frame_basis = (_earth_world as Node3D).basis
	var render_transform := EarthSurfaceRenderProjector.project_anchor(
		earth_fixed_transform,
		render_origin,
		frame_basis
	)
	return _success({
		"transform": render_transform,
		"world_position": world_position,
		"surface_direction": surface_direction,
		"earth_fixed_transform": earth_fixed_transform,
	})


func _make_east(up_direction: Vector3) -> Vector3:
	var up := up_direction.normalized()
	var east := Vector3.UP.cross(up)
	if east.length_squared() <= 0.000001:
		east = Vector3.RIGHT.cross(up)
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
