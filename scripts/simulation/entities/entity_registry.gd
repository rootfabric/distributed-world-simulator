extends Node

signal entity_registered(event: Dictionary)
signal entity_unregistered(event: Dictionary)
signal entity_moved(event: Dictionary)
signal entity_entered_chunk(event: Dictionary)
signal entity_left_chunk(event: Dictionary)
signal entity_entered_zone(event: Dictionary)
signal entity_left_zone(event: Dictionary)
signal stale_authority_write_rejected(event: Dictionary)

const SpatialRefScript = preload(
	"res://scripts/simulation/spatial/spatial_ref.gd"
)

var zone_manager
var logger
var simulation_clock
var authority_owner_id: String = "local-process"
var authority_epoch: int = 1
var entities: Dictionary = {}
var recent_migrations: Array[Dictionary] = []
var max_recent_migrations: int = 50
var migration_count: int = 0
var chunk_transition_count: int = 0
var zone_transition_count: int = 0
var stale_write_rejection_count: int = 0


func setup(
	zone_manager_reference,
	logger_reference = null,
	context: Dictionary = {}
) -> void:
	var partition_callback := Callable(self, "_on_partition_window_changed")
	if (
		zone_manager != null
		and zone_manager.has_signal("partition_window_changed")
		and zone_manager.partition_window_changed.is_connected(partition_callback)
	):
		zone_manager.partition_window_changed.disconnect(partition_callback)
	entities.clear()
	recent_migrations.clear()
	migration_count = 0
	chunk_transition_count = 0
	zone_transition_count = 0
	stale_write_rejection_count = 0
	zone_manager = zone_manager_reference
	logger = logger_reference
	simulation_clock = context.get("simulation_clock")
	authority_owner_id = String(context.get("authority_owner_id", "local-process"))
	authority_epoch = maxi(1, int(context.get("authority_epoch", 1)))
	if zone_manager != null and zone_manager.has_signal("partition_window_changed"):
		zone_manager.partition_window_changed.connect(partition_callback)
	_log("INFO", "registry_started", {
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
	})


func register_entity(
	entity_record,
	emit_lifecycle_events: bool = true,
	registration_context: Dictionary = {}
) -> bool:
	if entity_record == null or entity_record.entity_id.is_empty():
		return false
	if entities.has(entity_record.entity_id):
		return false
	var partition: Dictionary = _resolve_partition_for_spatial_ref(
		entity_record.spatial_ref
	)
	if partition.is_empty():
		return false
	if bool(registration_context.get("adopt_authority", false)):
		entity_record.authority_owner_id = authority_owner_id
		entity_record.authority_epoch = authority_epoch
	entity_record.initialize_partition(partition.get("partition_address", partition))
	entity_record.zone_id = String(partition["zone_id"])
	entity_record.chunk_id = String(partition["chunk_id"])
	if entity_record.authority_owner_id.is_empty():
		entity_record.authority_owner_id = authority_owner_id
	if entity_record.authority_epoch <= 0:
		entity_record.authority_epoch = authority_epoch
	entities[entity_record.entity_id] = entity_record
	_sync_loaded_chunk_counts()
	if emit_lifecycle_events:
		var event: Dictionary = _make_event(
			"entity_registered",
			entity_record,
			"",
			entity_record.zone_id,
			"",
			entity_record.chunk_id
		)
		entity_registered.emit(event)
		_log("INFO", "entity_registered", event)
	return true


func unregister_entity(entity_id: String, emit_lifecycle_events: bool = true) -> bool:
	return delete_authoritative_entity(entity_id, emit_lifecycle_events)


func delete_authoritative_entity(
	entity_id: String,
	emit_lifecycle_events: bool = true,
	command_context: Dictionary = {}
) -> bool:
	if not entities.has(entity_id):
		return false
	var entity_record = entities[entity_id]
	if not _validate_authority(entity_record, command_context):
		return false
	return _remove_local_record(entity_id, entity_record, emit_lifecycle_events, "delete")


func evict_local_record(
	entity_id: String,
	reason: String = "partition_unload"
) -> bool:
	if not entities.has(entity_id):
		return false
	var entity_record = entities[entity_id]
	return _remove_local_record(entity_id, entity_record, false, reason)


func evict_replica(entity_id: String) -> bool:
	return evict_local_record(entity_id, "replica_evict")


func update_entity_position(
	entity_id: String,
	world_position: Vector3,
	command_context: Dictionary = {}
) -> bool:
	var entity_record = entities.get(entity_id)
	if entity_record == null:
		return false
	var next_ref: Dictionary = entity_record.spatial_ref.duplicate(true)
	next_ref["position_m"] = [world_position.x, world_position.y, world_position.z]
	return update_entity_spatial_ref(entity_id, next_ref, command_context)


func update_entity_spatial_ref(
	entity_id: String,
	spatial_ref: Dictionary,
	command_context: Dictionary = {}
) -> bool:
	var entity_record = entities.get(entity_id)
	if entity_record == null or not SpatialRefScript.is_valid(spatial_ref):
		return false
	if not _validate_authority(entity_record, command_context):
		return false
	var previous_position: Vector3 = entity_record.world_position
	var previous_zone: String = entity_record.zone_id
	var previous_chunk: String = entity_record.chunk_id
	var partition: Dictionary = _resolve_partition_for_spatial_ref(spatial_ref)
	if partition.is_empty():
		return false
	var next_zone: String = String(partition["zone_id"])
	var next_chunk: String = String(partition["chunk_id"])
	var partition_changed: bool = previous_zone != next_zone or previous_chunk != next_chunk
	var changed: bool = entity_record.apply_spatial_update(
		spatial_ref,
		partition.get("partition_address", partition),
		int(command_context.get("authority_epoch", entity_record.authority_epoch)),
		_get_simulation_tick()
	)
	entity_record.zone_id = next_zone
	entity_record.chunk_id = next_chunk
	if not changed:
		return false
	if partition_changed:
		migration_count += 1
		var migration_event: Dictionary = _make_event(
			"entity_partition_changed",
			entity_record,
			previous_zone,
			next_zone,
			previous_chunk,
			next_chunk
		)
		_append_migration(migration_event)
		if previous_chunk != next_chunk:
			chunk_transition_count += 1
			var left_chunk_event: Dictionary = migration_event.duplicate(true)
			left_chunk_event["event"] = "entity_left_chunk"
			entity_left_chunk.emit(left_chunk_event)
			_log("INFO", "entity_left_chunk", left_chunk_event)
			var entered_chunk_event: Dictionary = migration_event.duplicate(true)
			entered_chunk_event["event"] = "entity_entered_chunk"
			entity_entered_chunk.emit(entered_chunk_event)
			_log("INFO", "entity_entered_chunk", entered_chunk_event)
		if previous_zone != next_zone:
			zone_transition_count += 1
			var left_zone_event: Dictionary = migration_event.duplicate(true)
			left_zone_event["event"] = "entity_left_zone"
			entity_left_zone.emit(left_zone_event)
			_log("INFO", "entity_left_zone", left_zone_event)
			var entered_zone_event: Dictionary = migration_event.duplicate(true)
			entered_zone_event["event"] = "entity_entered_zone"
			entity_entered_zone.emit(entered_zone_event)
			_log("INFO", "entity_entered_zone", entered_zone_event)
		_sync_loaded_chunk_counts()
	var move_event: Dictionary = _make_event(
		"entity_moved",
		entity_record,
		previous_zone,
		next_zone,
		previous_chunk,
		next_chunk
	)
	move_event["previous_world_position"] = [
		previous_position.x,
		previous_position.y,
		previous_position.z,
	]
	entity_moved.emit(move_event)
	return true


func update_entity_components(
	entity_id: String,
	component_patch: Dictionary,
	command_context: Dictionary = {}
) -> bool:
	var entity_record = entities.get(entity_id)
	if entity_record == null or not _validate_authority(entity_record, command_context):
		return false
	return entity_record.apply_component_patch(
		component_patch,
		int(command_context.get("authority_epoch", authority_epoch)),
		_get_simulation_tick()
	)


func get_entity(entity_id: String):
	return entities.get(entity_id)


func has_entity(entity_id: String) -> bool:
	return entities.has(entity_id)


func get_entity_count() -> int:
	return entities.size()


func entities_in_chunk(chunk_id: String) -> Array:
	var result: Array = []
	for entity_value in entities.values():
		if entity_value.chunk_id == chunk_id:
			result.append(entity_value)
	return result


func get_entities_by_type(entity_type: String) -> Array:
	var result: Array = []
	for entity_value in entities.values():
		if entity_value.entity_type == entity_type:
			result.append(entity_value)
	return result


func get_persistent_entities_in_chunk(chunk_id: String) -> Array:
	var result: Array = []
	for entity_value in entities.values():
		if entity_value.chunk_id == chunk_id and entity_value.is_persistent():
			result.append(entity_value)
	return result


func create_snapshot() -> Dictionary:
	var records: Array[Dictionary] = []
	for entity_value in entities.values():
		records.append(entity_value.to_snapshot())
	return {
		"schema": "planet_simulator.entity_registry.v2",
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
		"entity_count": entities.size(),
		"migration_count": migration_count,
		"chunk_transition_count": chunk_transition_count,
		"zone_transition_count": zone_transition_count,
		"stale_write_rejection_count": stale_write_rejection_count,
		"entities": records,
	}


func get_recent_migrations() -> Array[Dictionary]:
	return recent_migrations.duplicate(true)


func clear_recent_migrations() -> void:
	recent_migrations.clear()


func get_runtime_summary() -> String:
	return "entities=%d migrations=%d chunks=%d zones=%d stale=%d" % [
		entities.size(),
		migration_count,
		chunk_transition_count,
		zone_transition_count,
		stale_write_rejection_count,
	]


func _remove_local_record(
	entity_id: String,
	entity_record,
	emit_lifecycle_events: bool,
	reason: String
) -> bool:
	var event: Dictionary = _make_event(
		"entity_unregistered",
		entity_record,
		entity_record.zone_id,
		"",
		entity_record.chunk_id,
		""
	)
	event["reason"] = reason
	entities.erase(entity_id)
	_sync_loaded_chunk_counts()
	if emit_lifecycle_events:
		entity_unregistered.emit(event)
		_log("INFO", "entity_unregistered", event)
	return true


func _validate_authority(entity_record, command_context: Dictionary) -> bool:
	var requested_owner: String = String(command_context.get(
		"authority_owner_id",
		authority_owner_id
	))
	var requested_epoch: int = int(command_context.get(
		"authority_epoch",
		authority_epoch
	))
	var valid: bool = (
		requested_owner == authority_owner_id
		and requested_epoch == authority_epoch
		and requested_owner == entity_record.authority_owner_id
		and requested_epoch == entity_record.authority_epoch
	)
	if valid:
		return true
	stale_write_rejection_count += 1
	var event: Dictionary = {
		"schema": "planet_simulator.authority_rejection.v1",
		"entity_id": entity_record.entity_id,
		"expected_owner_id": entity_record.authority_owner_id,
		"received_owner_id": requested_owner,
		"expected_authority_epoch": entity_record.authority_epoch,
		"received_authority_epoch": requested_epoch,
	}
	stale_authority_write_rejected.emit(event)
	_log("WARNING", "stale_authority_write_rejected", event)
	return false


func _resolve_partition_for_spatial_ref(spatial_ref: Dictionary) -> Dictionary:
	if zone_manager == null or not zone_manager.has_method("resolve_partition"):
		return {}
	var actual_universe_id: String = String(spatial_ref.get("universe_id", ""))
	if (
		zone_manager.has_method("get_universe_id")
		and actual_universe_id != String(zone_manager.get_universe_id())
	):
		_log("WARNING", "partition_universe_mismatch", {
			"required_universe_id": String(zone_manager.get_universe_id()),
			"actual_universe_id": actual_universe_id,
		})
		return {}
	var actual_instance_id: String = String(spatial_ref.get("instance_id", ""))
	if (
		zone_manager.has_method("get_instance_id")
		and actual_instance_id != String(zone_manager.get_partition_instance_id())
	):
		_log("WARNING", "partition_instance_mismatch", {
			"required_instance_id": String(zone_manager.get_partition_instance_id()),
			"actual_instance_id": actual_instance_id,
		})
		return {}
	var required_frame_id: String = ""
	if zone_manager.has_method("get_partition_frame_id"):
		required_frame_id = String(zone_manager.get_partition_frame_id())
	var actual_frame_id: String = String(spatial_ref.get("frame_id", ""))
	if not required_frame_id.is_empty() and actual_frame_id != required_frame_id:
		_log("WARNING", "partition_frame_mismatch", {
			"required_frame_id": required_frame_id,
			"actual_frame_id": actual_frame_id,
		})
		return {}
	return zone_manager.resolve_partition(SpatialRefScript.get_position(spatial_ref))


func _make_event(
	event_name: String,
	entity_record,
	from_zone: String,
	to_zone: String,
	from_chunk: String,
	to_chunk: String
) -> Dictionary:
	return {
		"schema": "planet_simulator.entity_event.v2",
		"event": event_name,
		"timestamp_utc": Time.get_datetime_string_from_system(true, true),
		"entity_id": entity_record.entity_id,
		"entity_type": entity_record.entity_type,
		"from_zone": from_zone,
		"to_zone": to_zone,
		"from_chunk": from_chunk,
		"to_chunk": to_chunk,
		"spatial_ref": entity_record.spatial_ref.duplicate(true),
		"partition_address": entity_record.partition_address.duplicate(true),
		"world_position": [
			entity_record.world_position.x,
			entity_record.world_position.y,
			entity_record.world_position.z,
		],
		"authority_owner_id": entity_record.authority_owner_id,
		"authority_epoch": entity_record.authority_epoch,
		"state_revision": entity_record.state_revision,
		"revision": entity_record.revision,
		"simulation_tick": entity_record.last_simulation_tick,
	}


func _append_migration(event: Dictionary) -> void:
	recent_migrations.append(event.duplicate(true))
	while recent_migrations.size() > max_recent_migrations:
		recent_migrations.pop_front()


func _on_partition_window_changed(_snapshot: Dictionary) -> void:
	_sync_loaded_chunk_counts()


func _sync_loaded_chunk_counts() -> void:
	if zone_manager == null or not zone_manager.has_method("reset_loaded_entity_counts"):
		return
	zone_manager.reset_loaded_entity_counts()
	for entity_value in entities.values():
		zone_manager.increment_loaded_chunk_entity_count(entity_value.chunk_id)


func _get_simulation_tick() -> int:
	if simulation_clock != null:
		return int(simulation_clock.tick_index)
	return 0


func _log(level: String, event_name: String, data: Dictionary) -> void:
	if logger == null:
		return
	match level:
		"ERROR":
			logger.error("entity_registry", event_name, data)
		"WARNING":
			logger.warning("entity_registry", event_name, data)
		_:
			logger.info("entity_registry", event_name, data)
