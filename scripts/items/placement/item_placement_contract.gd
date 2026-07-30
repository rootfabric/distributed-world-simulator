extends RefCounted

const SCHEMA: String = "planet_simulator.item_placement_profile.v1"
const KIND_MOUNT_SOCKET: String = "MOUNT_SOCKET"


static func get_profile(definition) -> Dictionary:
	if definition == null:
		return {}
	var value = definition.metadata.get("placement", {})
	if not value is Dictionary:
		return {}
	var profile := Dictionary(value).duplicate(true)
	if String(profile.get("schema", SCHEMA)) != SCHEMA:
		return {}
	var kind := String(profile.get("kind", "")).to_upper()
	if kind.is_empty():
		return {}
	profile["schema"] = SCHEMA
	profile["kind"] = kind
	profile["max_distance_m"] = maxf(0.5, float(profile.get("max_distance_m", 8.0)))
	profile["surface_offset_m"] = maxf(0.0, float(profile.get("surface_offset_m", 0.0)))
	return profile


static func is_placeable(definition) -> bool:
	return not get_profile(definition).is_empty()


static func build_surface_transform(
	hit_position: Vector3,
	hit_normal: Vector3,
	view_forward: Vector3,
	world_root: Node3D,
	surface_offset_m: float = 0.0
) -> Transform3D:
	var up := hit_normal.normalized()
	if up.length_squared() < 0.5:
		up = Vector3.UP
	var forward := view_forward.slide(up)
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD.slide(up)
	if forward.length_squared() < 0.0001:
		forward = Vector3.RIGHT.slide(up)
	forward = forward.normalized()
	var right := forward.cross(up).normalized()
	var basis := Basis(right, up, -forward).orthonormalized()
	# A fixture's origin is commonly its geometric centre.  Keep its collider
	# above the hit surface so the terrain cannot hide the interactable body.
	var global_transform := Transform3D(basis, hit_position + up * maxf(0.0, surface_offset_m))
	return (
		world_root.global_transform.affine_inverse() * global_transform
		if world_root != null and world_root.is_inside_tree()
		else global_transform
	)
