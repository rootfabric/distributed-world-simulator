extends RefCounted

const SpatialRefScript = preload(
	"res://scripts/simulation/spatial/spatial_ref.gd"
)
const PartitionAddressScript = preload(
	"res://scripts/simulation/partition/partition_address.gd"
)

const SCHEMA: String = "planet_simulator.entity.v2"
const LEGACY_SCHEMA: String = "lunar.entity.v1"

var entity_id: String = ""
var entity_type: String = "generic"
var zone_id: String = ""
var chunk_id: String = ""
var world_position: Vector3 = Vector3.ZERO
var spatial_ref: Dictionary = {}
var partition_address: Dictionary = {}
var components: Dictionary = {}
var revision: int = 0
var state_revision: int = 0
var authority_owner_id: String = "local-process"
var authority_epoch: int = 1
var last_simulation_tick: int = 0
var created_at_utc: String = ""
var updated_at_utc: String = ""


func setup(
	id_value: String,
	type_value: String,
	position_value: Vector3,
	components_value: Dictionary = {},
	authority_owner_id_value: String = "local-process",
	authority_epoch_value: int = 1,
	spatial_context: Dictionary = {}
) -> void:
	setup_with_spatial_ref(
		id_value,
		type_value,
		SpatialRefScript.create(
			String(spatial_context.get("frame_id", "body/moon/fixed")),
			position_value,
			Basis.IDENTITY,
			Vector3.ZERO,
			Vector3.ZERO,
			float(spatial_context.get("sample_time_s", 0.0)),
			String(spatial_context.get("universe_id", "main")),
			String(spatial_context.get("space_id", "sol")),
			String(spatial_context.get("instance_id", "persistent"))
		),
		components_value,
		authority_owner_id_value,
		authority_epoch_value
	)


func setup_with_spatial_ref(
	id_value: String,
	type_value: String,
	spatial_ref_value: Dictionary,
	components_value: Dictionary = {},
	authority_owner_id_value: String = "local-process",
	authority_epoch_value: int = 1
) -> void:
	zone_id = ""
	chunk_id = ""
	partition_address.clear()
	revision = 0
	state_revision = 0
	last_simulation_tick = 0
	entity_id = id_value
	entity_type = type_value
	spatial_ref = SpatialRefScript.normalize(spatial_ref_value)
	world_position = SpatialRefScript.get_position(spatial_ref)
	components = components_value.duplicate(true)
	authority_owner_id = authority_owner_id_value
	authority_epoch = maxi(1, authority_epoch_value)
	created_at_utc = Time.get_datetime_string_from_system(true, true)
	updated_at_utc = created_at_utc


func setup_from_snapshot(snapshot: Dictionary) -> bool:
	var schema: String = String(snapshot.get("schema", ""))
	if schema != SCHEMA and schema != LEGACY_SCHEMA:
		return false
	entity_id = String(snapshot.get("entity_id", ""))
	entity_type = String(snapshot.get("entity_type", "generic"))
	zone_id = String(snapshot.get("zone_id", ""))
	chunk_id = String(snapshot.get("chunk_id", ""))
	if schema == LEGACY_SCHEMA:
		world_position = _array_to_vector3(snapshot.get("world_position", []))
		spatial_ref = SpatialRefScript.create(
			"body/moon/fixed",
			world_position,
			Basis.IDENTITY,
			Vector3.ZERO,
			Vector3.ZERO,
			0.0,
			"main",
			"sol"
		)
		partition_address = PartitionAddressScript.parse(chunk_id, {
			"universe_id": "main",
			"instance_id": "persistent",
			"space_id": "moon",
			"partition_scheme": PartitionAddressScript.DEFAULT_SCHEME,
		})
		authority_owner_id = "local-process"
		authority_epoch = 1
		state_revision = int(snapshot.get("revision", 0))
		last_simulation_tick = 0
	else:
		var spatial_value = snapshot.get("spatial_ref", {})
		if not spatial_value is Dictionary or not SpatialRefScript.is_valid(spatial_value):
			return false
		spatial_ref = SpatialRefScript.normalize(spatial_value)
		world_position = SpatialRefScript.get_position(spatial_ref)
		var partition_value = snapshot.get("partition_address", {})
		partition_address = (
			PartitionAddressScript.normalize(partition_value)
			if partition_value is Dictionary
			else {}
		)
		if (
			not partition_address.is_empty()
			and not PartitionAddressScript.is_valid(partition_address)
		):
			return false
		if zone_id.is_empty():
			zone_id = String(partition_address.get("zone_id", ""))
		if chunk_id.is_empty():
			chunk_id = String(partition_address.get("chunk_id", ""))
		authority_owner_id = String(snapshot.get("authority_owner_id", "local-process"))
		authority_epoch = maxi(1, int(snapshot.get("authority_epoch", 1)))
		state_revision = int(snapshot.get("state_revision", snapshot.get("revision", 0)))
		last_simulation_tick = int(snapshot.get("last_simulation_tick", 0))
	var snapshot_components = snapshot.get("components", {})
	components = snapshot_components.duplicate(true) if snapshot_components is Dictionary else {}
	revision = state_revision
	created_at_utc = String(snapshot.get("created_at_utc", ""))
	updated_at_utc = String(snapshot.get("updated_at_utc", ""))
	return (
		not entity_id.is_empty()
		and SpatialRefScript.is_valid(spatial_ref)
		and not partition_address.is_empty()
		and PartitionAddressScript.is_valid(partition_address)
	)


func initialize_partition(partition_value: Dictionary) -> void:
	partition_address = PartitionAddressScript.normalize(partition_value)
	zone_id = String(partition_address.get("zone_id", zone_id))
	chunk_id = String(partition_address.get("chunk_id", chunk_id))


func apply_spatial_update(
	spatial_ref_value: Dictionary,
	partition_value: Dictionary,
	expected_authority_epoch: int = -1,
	simulation_tick: int = -1
) -> bool:
	if expected_authority_epoch >= 0 and expected_authority_epoch != authority_epoch:
		return false
	if (
		not SpatialRefScript.is_valid(spatial_ref_value)
		or not PartitionAddressScript.is_valid(partition_value)
		or String(spatial_ref_value.get("universe_id", ""))
		!= String(partition_value.get("universe_id", ""))
		or String(spatial_ref_value.get("instance_id", ""))
		!= String(partition_value.get("instance_id", ""))
	):
		return false
	var normalized_ref: Dictionary = SpatialRefScript.normalize(spatial_ref_value, spatial_ref)
	var normalized_partition: Dictionary = PartitionAddressScript.normalize(partition_value)
	if normalized_partition.is_empty():
		return false
	var next_position: Vector3 = SpatialRefScript.get_position(normalized_ref)
	var next_zone: String = String(normalized_partition.get("zone_id", zone_id))
	var next_chunk: String = String(normalized_partition.get("chunk_id", chunk_id))
	var changed: bool = (
		not _spatial_state_equal(spatial_ref, normalized_ref)
		or zone_id != next_zone
		or chunk_id != next_chunk
	)
	if not changed:
		return false
	spatial_ref = normalized_ref
	world_position = next_position
	partition_address = normalized_partition
	zone_id = next_zone
	chunk_id = next_chunk
	last_simulation_tick = simulation_tick if simulation_tick >= 0 else last_simulation_tick
	_touch_revision()
	return true


func update_position(position_value: Vector3) -> bool:
	var next_ref: Dictionary = spatial_ref.duplicate(true)
	next_ref["position_m"] = [position_value.x, position_value.y, position_value.z]
	return apply_spatial_update(next_ref, partition_address)


func update_partition(zone_value: String, chunk_value: String) -> bool:
	if zone_id == zone_value and chunk_id == chunk_value:
		return false
	zone_id = zone_value
	chunk_id = chunk_value
	partition_address["zone_id"] = zone_id
	partition_address["chunk_id"] = chunk_id
	_touch_revision()
	return true


func apply_component_patch(
	component_patch: Dictionary,
	expected_authority_epoch: int = -1,
	simulation_tick: int = -1
) -> bool:
	if expected_authority_epoch >= 0 and expected_authority_epoch != authority_epoch:
		return false
	if component_patch.is_empty():
		return false
	var changed: bool = false
	for component_name_value in component_patch.keys():
		var component_name: String = String(component_name_value)
		if component_name.is_empty():
			continue
		var component_value = component_patch[component_name_value]
		if component_value == null:
			if components.erase(component_name):
				changed = true
			continue
		var stored_value = (
			component_value.duplicate(true)
			if component_value is Dictionary or component_value is Array
			else component_value
		)
		if components.get(component_name) == stored_value:
			continue
		components[component_name] = stored_value
		changed = true
	if not changed:
		return false
	last_simulation_tick = simulation_tick if simulation_tick >= 0 else last_simulation_tick
	_touch_revision()
	return true


func set_component(component_name: String, component_value: Dictionary) -> void:
	components[component_name] = component_value.duplicate(true)
	_touch_revision()


func get_component(component_name: String) -> Dictionary:
	var value = components.get(component_name, {})
	return value.duplicate(true) if value is Dictionary else {}


func is_persistent() -> bool:
	var persistence_component: Dictionary = components.get("persistence", {})
	return bool(persistence_component.get("persistent", false))


func transfer_authority(next_owner_id: String, next_epoch: int) -> bool:
	if next_owner_id.is_empty() or next_epoch <= authority_epoch:
		return false
	authority_owner_id = next_owner_id
	authority_epoch = next_epoch
	state_revision = 0
	revision = 0
	updated_at_utc = Time.get_datetime_string_from_system(true, true)
	return true


func to_snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"entity_id": entity_id,
		"entity_type": entity_type,
		"spatial_ref": spatial_ref.duplicate(true),
		"partition_address": partition_address.duplicate(true),
		"zone_id": zone_id,
		"chunk_id": chunk_id,
		"world_position": [world_position.x, world_position.y, world_position.z],
		"components": components.duplicate(true),
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
		"state_revision": state_revision,
		"revision": revision,
		"last_simulation_tick": last_simulation_tick,
		"created_at_utc": created_at_utc,
		"updated_at_utc": updated_at_utc,
	}


func _spatial_state_equal(first: Dictionary, second: Dictionary) -> bool:
	if String(first.get("universe_id", "")) != String(second.get("universe_id", "")):
		return false
	if String(first.get("instance_id", "")) != String(second.get("instance_id", "")):
		return false
	if String(first.get("space_id", "")) != String(second.get("space_id", "")):
		return false
	if String(first.get("frame_id", "")) != String(second.get("frame_id", "")):
		return false
	if not SpatialRefScript.get_position(first).is_equal_approx(
		SpatialRefScript.get_position(second)
	):
		return false
	if not SpatialRefScript.get_linear_velocity(first).is_equal_approx(
		SpatialRefScript.get_linear_velocity(second)
	):
		return false
	if not SpatialRefScript.get_angular_velocity(first).is_equal_approx(
		SpatialRefScript.get_angular_velocity(second)
	):
		return false
	var first_rotation: Quaternion = SpatialRefScript.get_basis(
		first
	).get_rotation_quaternion().normalized()
	var second_rotation: Quaternion = SpatialRefScript.get_basis(
		second
	).get_rotation_quaternion().normalized()
	return absf(first_rotation.dot(second_rotation)) >= 0.999999999


func _touch_revision() -> void:
	state_revision += 1
	revision = state_revision
	updated_at_utc = Time.get_datetime_string_from_system(true, true)


func _array_to_vector3(value) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
