extends RefCounted

var entity_id: String = ""
var entity_type: String = "generic"
var zone_id: String = ""
var chunk_id: String = ""
var world_position: Vector3 = Vector3.ZERO
var components: Dictionary = {}
var revision: int = 0
var created_at_utc: String = ""
var updated_at_utc: String = ""


func setup(
	id_value: String,
	type_value: String,
	position_value: Vector3,
	components_value: Dictionary = {}
) -> void:
	entity_id = id_value
	entity_type = type_value
	world_position = position_value
	components = components_value.duplicate(true)
	created_at_utc = Time.get_datetime_string_from_system(true, true)
	updated_at_utc = created_at_utc


func setup_from_snapshot(snapshot: Dictionary) -> bool:
	if String(snapshot.get("schema", "")) != "lunar.entity.v1":
		return false
	entity_id = String(snapshot.get("entity_id", ""))
	entity_type = String(snapshot.get("entity_type", "generic"))
	zone_id = String(snapshot.get("zone_id", ""))
	chunk_id = String(snapshot.get("chunk_id", ""))
	world_position = _array_to_vector3(snapshot.get("world_position", []))
	var snapshot_components = snapshot.get("components", {})
	components = (
		snapshot_components.duplicate(true)
		if snapshot_components is Dictionary
		else {}
	)
	revision = int(snapshot.get("revision", 0))
	created_at_utc = String(snapshot.get("created_at_utc", ""))
	updated_at_utc = String(snapshot.get("updated_at_utc", ""))
	return not entity_id.is_empty() and world_position.length_squared() > 1.0


func update_position(position_value: Vector3) -> bool:
	if world_position.distance_squared_to(position_value) < 0.0001:
		return false
	world_position = position_value
	revision += 1
	updated_at_utc = Time.get_datetime_string_from_system(true, true)
	return true


func update_partition(zone_value: String, chunk_value: String) -> bool:
	if zone_id == zone_value and chunk_id == chunk_value:
		return false
	zone_id = zone_value
	chunk_id = chunk_value
	revision += 1
	updated_at_utc = Time.get_datetime_string_from_system(true, true)
	return true


func set_component(component_name: String, component_value: Dictionary) -> void:
	components[component_name] = component_value.duplicate(true)
	revision += 1
	updated_at_utc = Time.get_datetime_string_from_system(true, true)


func get_component(component_name: String) -> Dictionary:
	var value = components.get(component_name, {})
	return value.duplicate(true) if value is Dictionary else {}


func is_persistent() -> bool:
	var persistence_component: Dictionary = components.get("persistence", {})
	return bool(persistence_component.get("persistent", false))


func to_snapshot() -> Dictionary:
	return {
		"schema": "lunar.entity.v1",
		"entity_id": entity_id,
		"entity_type": entity_type,
		"zone_id": zone_id,
		"chunk_id": chunk_id,
		"world_position": [world_position.x, world_position.y, world_position.z],
		"components": components.duplicate(true),
		"revision": revision,
		"created_at_utc": created_at_utc,
		"updated_at_utc": updated_at_utc,
	}


func _array_to_vector3(value) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
