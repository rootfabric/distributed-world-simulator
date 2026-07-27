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
	instance_id: String = "scenario",
	angular_velocity: Vector3 = Vector3.ZERO
) -> Dictionary:
	return world_from_spatial_ref(SpatialRefScript.create(
		frame_id,
		transform.origin,
		transform.basis,
		linear_velocity,
		angular_velocity,
		sample_time_s,
		universe_id,
		space_id,
		instance_id
	))


static func world_from_spatial_ref(spatial_ref: Dictionary) -> Dictionary:
	var normalized: Dictionary = SpatialRefScript.normalize(spatial_ref)
	var transform := Transform3D(
		SpatialRefScript.get_basis(normalized),
		SpatialRefScript.get_position(normalized)
	)
	var linear_velocity: Vector3 = SpatialRefScript.get_linear_velocity(normalized)
	var angular_velocity: Vector3 = SpatialRefScript.get_angular_velocity(normalized)
	return canonicalize({
		"kind": WORLD,
		"spatial_ref": normalized,
		# Compatibility fields remain until all current item representations read
		# SPATIAL_REF_V1 directly.
		"transform": _transform_to_array(transform),
		"linear_velocity": _vector_to_array(linear_velocity),
		"angular_velocity": _vector_to_array(angular_velocity),
	})


static func world_entity(entity_id: String) -> Dictionary:
	return canonicalize({
		"kind": WORLD,
		"entity_id": entity_id,
	})


static func world_entity_id(relation: Dictionary) -> String:
	if kind_of(relation) != WORLD:
		return ""
	return String(relation.get("entity_id", ""))


static func is_entity_world_relation(relation: Dictionary) -> bool:
	return not world_entity_id(relation).is_empty()


static func is_legacy_world_relation(relation: Dictionary) -> bool:
	return kind_of(relation) == WORLD and world_entity_id(relation).is_empty()


static func update_world_state(
	relation: Dictionary,
	transform: Transform3D,
	linear_velocity: Vector3,
	angular_velocity: Vector3 = Vector3.ZERO,
	sample_time_s: float = -1.0
) -> Dictionary:
	var current: Dictionary = spatial_ref_from_relation(relation)
	var resolved_sample_time: float = sample_time_s
	if resolved_sample_time < 0.0:
		resolved_sample_time = float(current.get("sample_time_s", 0.0))
	return world_from_spatial_ref(SpatialRefScript.create(
		String(current.get("frame_id", SpatialRefScript.DEFAULT_FRAME_ID)),
		transform.origin,
		transform.basis,
		linear_velocity,
		angular_velocity,
		resolved_sample_time,
		String(current.get("universe_id", SpatialRefScript.DEFAULT_UNIVERSE_ID)),
		String(current.get("space_id", SpatialRefScript.DEFAULT_SPACE_ID)),
		String(current.get("instance_id", SpatialRefScript.DEFAULT_INSTANCE_ID))
	))


static func container(container_id: String, slot_index: int = -1) -> Dictionary:
	return canonicalize({
		"kind": CONTAINER,
		"container_id": container_id,
		"slot_index": slot_index,
	})


static func attachment(assembly_id: String, parent_item_id: String, socket_id: String) -> Dictionary:
	return canonicalize({
		"kind": ATTACHMENT,
		"assembly_id": assembly_id,
		"parent_item_id": parent_item_id,
		"socket_id": socket_id,
	})


static func destroyed() -> Dictionary:
	return canonicalize({"kind": DESTROYED})


# The item domain persists relation payloads as JSON. Canonicalizing at the
# boundary makes the in-memory representation identical to the representation
# returned by JSON.parse_string(): typed Arrays/PackedArrays and other Variant
# container metadata cannot survive JSON and must not leak into equality, hashes
# or revision decisions.
static func canonicalize(relation: Dictionary) -> Dictionary:
	var encoded: String = JSON.stringify(relation, "", true, true)
	var decoded = JSON.parse_string(encoded)
	if decoded is Dictionary:
		return Dictionary(decoded)
	return relation.duplicate(true)


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
	var legacy_transform: Transform3D = _legacy_transform_from_relation(relation)
	return SpatialRefScript.create(
		"scenario/local",
		legacy_transform.origin,
		legacy_transform.basis,
		_legacy_velocity_from_relation(relation),
		_legacy_angular_velocity_from_relation(relation),
		0.0,
		"main",
		"scenario",
		"scenario"
	)


static func transform_from_relation(relation: Dictionary) -> Transform3D:
	var value = relation.get("spatial_ref", {})
	if value is Dictionary and SpatialRefScript.is_valid(value):
		var normalized: Dictionary = SpatialRefScript.normalize(value)
		return Transform3D(
			SpatialRefScript.get_basis(normalized),
			SpatialRefScript.get_position(normalized)
		)
	return _legacy_transform_from_relation(relation)


static func velocity_from_relation(relation: Dictionary) -> Vector3:
	var value = relation.get("spatial_ref", {})
	if value is Dictionary and SpatialRefScript.is_valid(value):
		return SpatialRefScript.get_linear_velocity(value)
	return _legacy_velocity_from_relation(relation)


static func angular_velocity_from_relation(relation: Dictionary) -> Vector3:
	var value = relation.get("spatial_ref", {})
	if value is Dictionary and SpatialRefScript.is_valid(value):
		return SpatialRefScript.get_angular_velocity(value)
	return _legacy_angular_velocity_from_relation(relation)


static func _legacy_transform_from_relation(relation: Dictionary) -> Transform3D:
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


static func _legacy_velocity_from_relation(relation: Dictionary) -> Vector3:
	return _array_to_vector3(relation.get("linear_velocity", []))


static func _legacy_angular_velocity_from_relation(relation: Dictionary) -> Vector3:
	return _array_to_vector3(relation.get("angular_velocity", []))


static func _transform_to_array(transform: Transform3D) -> Array:
	return [
		transform.basis.x.x, transform.basis.x.y, transform.basis.x.z,
		transform.basis.y.x, transform.basis.y.y, transform.basis.y.z,
		transform.basis.z.x, transform.basis.z.y, transform.basis.z.z,
		transform.origin.x, transform.origin.y, transform.origin.z,
	]


static func _vector_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func _array_to_vector3(value) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
