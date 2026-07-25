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
