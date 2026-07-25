extends Node

signal entity_registered(event: Dictionary)
signal entity_unregistered(event: Dictionary)
signal entity_moved(event: Dictionary)
signal entity_entered_chunk(event: Dictionary)
signal entity_left_chunk(event: Dictionary)
signal entity_entered_zone(event: Dictionary)
signal entity_left_zone(event: Dictionary)

var zone_manager
var logger
var entities: Dictionary = {}
var recent_migrations: Array[Dictionary] = []
var max_recent_migrations: int = 50
var migration_count: int = 0
var chunk_transition_count: int = 0
var zone_transition_count: int = 0


func setup(zone_manager_reference, logger_reference = null) -> void:
	zone_manager = zone_manager_reference
	logger = logger_reference
	if zone_manager != null and zone_manager.has_signal("partition_window_changed"):
		zone_manager.partition_window_changed.connect(_on_partition_window_changed)
	_log("INFO", "registry_started", {})


func register_entity(entity_record, emit_lifecycle_events: bool = true) -> bool:
	if entity_record == null or entity_record.entity_id.is_empty():
		return false
	if entities.has(entity_record.entity_id):
		return false

	var partition: Dictionary = _resolve_partition(entity_record.world_position)
	if partition.is_empty():
		return false
	entity_record.zone_id = String(partition["zone_id"])
	entity_record.chunk_id = String(partition["chunk_id"])
	entities[entity_record.entity_id] = entity_record
	_sync_loaded_chunk_counts()

	if emit_lifecycle_events:
		var event := _make_event(
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
	if not entities.has(entity_id):
		return false
	var entity_record = entities[entity_id]
	var event := _make_event(
		"entity_unregistered",
		entity_record,
		entity_record.zone_id,
		"",
		entity_record.chunk_id,
		""
	)
	entities.erase(entity_id)
	_sync_loaded_chunk_counts()
	if emit_lifecycle_events:
		entity_unregistered.emit(event)
		_log("INFO", "entity_unregistered", event)
	return true


func update_entity_position(entity_id: String, world_position: Vector3) -> bool:
	var entity_record = entities.get(entity_id)
	if entity_record == null:
		return false

	var previous_position: Vector3 = entity_record.world_position
	var previous_zone: String = entity_record.zone_id
	var previous_chunk: String = entity_record.chunk_id
	var partition: Dictionary = _resolve_partition(world_position)
	if partition.is_empty():
		return false

	var next_zone: String = String(partition["zone_id"])
	var next_chunk: String = String(partition["chunk_id"])
	var position_changed: bool = entity_record.update_position(world_position)
	var partition_changed: bool = (
		previous_zone != next_zone or previous_chunk != next_chunk
	)

	if partition_changed:
		entity_record.update_partition(next_zone, next_chunk)
		migration_count += 1
		var migration_event := _make_event(
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

	if position_changed:
		var move_event := _make_event(
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
	return position_changed or partition_changed


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
		"schema": "lunar.entity_registry.v1",
		"entity_count": entities.size(),
		"migration_count": migration_count,
		"chunk_transition_count": chunk_transition_count,
		"zone_transition_count": zone_transition_count,
		"entities": records,
	}


func get_recent_migrations() -> Array[Dictionary]:
	return recent_migrations.duplicate(true)


func clear_recent_migrations() -> void:
	recent_migrations.clear()


func get_runtime_summary() -> String:
	return "entities=%d migrations=%d chunks=%d zones=%d" % [
		entities.size(),
		migration_count,
		chunk_transition_count,
		zone_transition_count,
	]


func _resolve_partition(world_position: Vector3) -> Dictionary:
	if zone_manager == null or not zone_manager.has_method("resolve_partition"):
		return {}
	return zone_manager.resolve_partition(world_position)


func _make_event(
	event_name: String,
	entity_record,
	from_zone: String,
	to_zone: String,
	from_chunk: String,
	to_chunk: String
) -> Dictionary:
	return {
		"schema": "lunar.entity_event.v1",
		"event": event_name,
		"timestamp_utc": Time.get_datetime_string_from_system(true, true),
		"entity_id": entity_record.entity_id,
		"entity_type": entity_record.entity_type,
		"from_zone": from_zone,
		"to_zone": to_zone,
		"from_chunk": from_chunk,
		"to_chunk": to_chunk,
		"world_position": [
			entity_record.world_position.x,
			entity_record.world_position.y,
			entity_record.world_position.z,
		],
		"revision": entity_record.revision,
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


func _log(
	level: String,
	event_name: String,
	data: Dictionary
) -> void:
	if logger == null:
		return
	match level:
		"ERROR":
			logger.error("entity_registry", event_name, data)
		"WARNING":
			logger.warning("entity_registry", event_name, data)
		_:
			logger.info("entity_registry", event_name, data)
