extends RefCounted

# Presentation-only transform helper for Earth-fixed objects. It never owns
# canonical spatial state: callers provide a stable Earth-fixed anchor and the
# current render origin/reference-frame basis, and receive a derived Node3D
# transform suitable for the floating-origin scene.
const EPSILON := 0.000001


static func create_surface_anchor(
	surface_point_world: Vector3,
	surface_clearance_m: float = 0.0
) -> Transform3D:
	if surface_point_world.length_squared() < EPSILON:
		return Transform3D.IDENTITY
	var up: Vector3 = surface_point_world.normalized()
	var anchor_basis: Basis = _surface_basis(up)
	var anchor_origin: Vector3 = surface_point_world + up * surface_clearance_m
	return Transform3D(anchor_basis, anchor_origin)


static func project_anchor(
	canonical_anchor: Transform3D,
	render_origin_world: Vector3,
	earth_fixed_to_render: Basis = Basis.IDENTITY
) -> Transform3D:
	var frame_basis: Basis = earth_fixed_to_render.orthonormalized()
	return Transform3D(
		(frame_basis * canonical_anchor.basis).orthonormalized(),
		frame_basis * (canonical_anchor.origin - render_origin_world)
	)


static func _surface_basis(up_value: Vector3) -> Basis:
	var up: Vector3 = up_value.normalized()
	var east: Vector3 = Vector3.UP.cross(up)
	if east.length_squared() < EPSILON:
		east = Vector3.RIGHT.cross(up)
	east = east.normalized()
	var north: Vector3 = up.cross(east).normalized()
	return Basis(east, up, -north).orthonormalized()
