extends RefCounted

const SpatialRefScript = preload(
	"res://scripts/simulation/spatial/spatial_ref.gd"
)

const WORLD := "WORLD"
const CONTAINER := "CONTAINER"
const ATTACHMENT := "ATTACHMENT"
const DESTROYED := "DESTROYED"


static func world(
	transform: Transform3D = Transform3D.IDENTITY,
	linear_velocity: Vector3 = Vector3.ZERO,
	frame_id: String = "scenario/local",
	sample_time_s: float = 0.0,
	universe_id: String = "main",
	space_id: String = "scenario",
	instance_id: String = "scenario"
) -> Dictionary:
	return {
		"kind": WORLD,
		"spatial_ref": SpatialRefScript.create(
			frame_id,
			transform.origin,
			transform.basis,
			linear_velocity,
			Vector3.ZERO,
			sample_time_s,
			universe_id,
			space_id,
			instance_id
		),
		# Compatibility fields remain until all current item representations read
		# SPATIAL_REF_V1 directly.
		"transform": _transform_to_array(transform),
		"linear_velocity": [linear_velocity.x, linear_velocity.y, linear_velocity.z],
	}


static func container(container_id: String, slot_index: int = -1) -> Dictionary:
	return {
		"kind": CONTAINER,
		"container_id": container_id,
		"slot_index": slot_index,
	}


static func attachment(assembly_id: String, parent_item_id: String, socket_id: String) -> Dictionary:
	return {
		"kind": ATTACHMENT,
		"assembly_id": assembly_id,
		"parent_item_id": parent_item_id,
		"socket_id": socket_id,
	}


static func destroyed() -> Dictionary:
	return {"kind": DESTROYED}


static func kind_of(relation: Dictionary) -> String:
	return String(relation.get("kind", ""))


static func relation_parent_item_id(relation: Dictionary, container_registry) -> String:
	match kind_of(relation):
		ATTACHMENT:
			return String(relation.get("parent_item_id", ""))
		CONTAINER:
			var container_id = String(relation.get("container_id", ""))
			var container = container_registry.get_container(container_id)
			if container != null and container.owner_kind == "ITEM_INSTANCE":
				return container.owner_id
	return ""


static func spatial_ref_from_relation(relation: Dictionary) -> Dictionary:
	var value = relation.get("spatial_ref", {})
	if value is Dictionary and SpatialRefScript.is_valid(value):
		return SpatialRefScript.normalize(value)
	var legacy_transform: Transform3D = transform_from_relation(relation)
	return SpatialRefScript.create(
		"scenario/local",
		legacy_transform.origin,
		legacy_transform.basis,
		velocity_from_relation(relation),
		Vector3.ZERO,
		0.0,
		"main",
		"scenario",
		"scenario"
	)


static func transform_from_relation(relation: Dictionary) -> Transform3D:
	var raw = relation.get("transform", [])
	if not raw is Array or raw.size() != 12:
		return Transform3D.IDENTITY
	var values: Array = raw
	return Transform3D(
		Vector3(float(values[0]), float(values[1]), float(values[2])),
		Vector3(float(values[3]), float(values[4]), float(values[5])),
		Vector3(float(values[6]), float(values[7]), float(values[8])),
		Vector3(float(values[9]), float(values[10]), float(values[11]))
	)


static func velocity_from_relation(relation: Dictionary) -> Vector3:
	var raw = relation.get("linear_velocity", [])
	if not raw is Array or raw.size() != 3:
		return Vector3.ZERO
	return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))


static func _transform_to_array(transform: Transform3D) -> Array:
	return [
		transform.basis.x.x, transform.basis.x.y, transform.basis.x.z,
		transform.basis.y.x, transform.basis.y.y, transform.basis.y.z,
		transform.basis.z.x, transform.basis.z.y, transform.basis.z.z,
		transform.origin.x, transform.origin.y, transform.origin.z,
	]
