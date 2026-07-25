extends Node

signal chunk_loaded(chunk_id: String, entity_ids: Array)
signal chunk_unloaded(chunk_id: String)
signal world_saved(summary: Dictionary)
signal world_cleared()
signal persistence_error(message: String)

const EntityRecordScript = preload(
	"res://scripts/simulation/entities/entity_record.gd"
)

const DEFAULT_WORLD_ID: String = "moon-experiment-001"
const WORLD_SCHEMA: String = "lunar.world.v1"
const CHUNK_SCHEMA: String = "lunar.chunk.v1"
const JOURNAL_SCHEMA: String = "lunar.journal_event.v1"

var moon_world
var zone_manager
var entity_registry
var logger

var world_id: String = DEFAULT_WORLD_ID
var world_root: String = ""
var manifest_path: String = ""
var journal_path: String = ""
var entity_root: Node3D

var loaded_chunk_ids: Dictionary = {}
var runtime_nodes: Dictionary = {}
var persistent_entity_ids: Dictionary = {}
var dirty_chunks: Dictionary = {}
var journal_revision: int = 0
var last_save_summary: String = "Не сохранялся"
var loaded_entity_count: int = 0
var last_player_world_position: Vector3 = Vector3.ZERO
var chunk_load_count: int = 0
var chunk_unload_count: int = 0


func setup(
	moon_reference,
	zone_manager_reference,
	registry_reference,
	logger_reference = null,
	world_id_override: String = DEFAULT_WORLD_ID,
	root_override: String = ""
) -> void:
	moon_world = moon_reference
	zone_manager = zone_manager_reference
	entity_registry = registry_reference
	logger = logger_reference
	world_id = world_id_override
	world_root = (
		root_override
		if not root_override.is_empty()
		else "user://worlds/%s" % world_id
	)
	manifest_path = world_root.path_join("world.json")
	journal_path = world_root.path_join("journal/events.jsonl")

	entity_root = Node3D.new()
	entity_root.name = "PersistentEntities"
	add_child(entity_root)

	_ensure_world_layout()
	_ensure_world_manifest()
	_load_journal_revision()
	_connect_signals()
	_sync_partition_window(zone_manager.create_partition_snapshot())
	_log("INFO", "repository_started", create_snapshot())


func update_runtime_transforms() -> void:
	if moon_world == null:
		return
	for entity_id in runtime_nodes.keys():
		var entity_record = entity_registry.get_entity(String(entity_id))
		var node: Node3D = runtime_nodes.get(entity_id)
		if entity_record == null or node == null or not is_instance_valid(node):
			continue
		var up: Vector3 = entity_record.world_position.normalized()
		var transform_component: Dictionary = entity_record.get_component("transform")
		var forward: Vector3 = _array_to_vector3(
			transform_component.get("forward", [0.0, 0.0, -1.0])
		)
		forward = forward.slide(up)
		if forward.length_squared() < 0.000001:
			forward = Vector3.FORWARD.slide(up)
		if forward.length_squared() < 0.000001:
			forward = Vector3.RIGHT.slide(up)
		forward = forward.normalized()
		var right: Vector3 = forward.cross(up).normalized()
		var basis := Basis(right, up, -forward).orthonormalized()
		node.global_transform = Transform3D(
			basis,
			moon_world.world_to_render(entity_record.world_position)
		)


func create_survey_beacon(
	world_position: Vector3,
	forward_direction: Vector3,
	entity_id_override: String = "",
	extra_components: Dictionary = {}
) -> String:
	if world_position.length_squared() < 1.0:
		return ""
	var entity_id: String = entity_id_override
	if entity_id.is_empty():
		entity_id = "entity/survey_beacon/%d-%d" % [
			int(Time.get_unix_time_from_system()),
			Time.get_ticks_msec(),
		]
	var up: Vector3 = world_position.normalized()
	var forward: Vector3 = forward_direction.slide(up)
	if forward.length_squared() < 0.000001:
		forward = Vector3.FORWARD.slide(up)
	forward = forward.normalized()
	var components: Dictionary = {
		"persistence": {
			"persistent": true,
			"storage": "chunk",
		},
		"transform": {
			"forward": _vector_to_array(forward),
			"up": _vector_to_array(up),
		},
		"visual": {
			"archetype": "survey_beacon_v1",
			"label": "SURVEY",
		},
		"collision": {
			"shape": "cylinder",
			"radius": 0.32,
			"height": 2.8,
		},
		"ownership": {
			"owner": "local-player",
		},
	}
	for key in extra_components.keys():
		var extra_value = extra_components[key]
		if extra_value is Dictionary or extra_value is Array:
			components[key] = extra_value.duplicate(true)
		else:
			components[key] = extra_value

	var record = EntityRecordScript.new()
	record.setup(entity_id, "survey_beacon", world_position, components)
	if not entity_registry.register_entity(record):
		return ""
	return entity_id


func remove_entity(entity_id: String) -> bool:
	return entity_registry.unregister_entity(entity_id)


func remove_nearest_survey_beacon(
	world_position: Vector3,
	max_distance_m: float = 14.0
) -> String:
	var nearest_id: String = ""
	var nearest_distance: float = max_distance_m
	for entity_value in entity_registry.get_entities_by_type("survey_beacon"):
		var distance: float = entity_value.world_position.distance_to(world_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest_id = entity_value.entity_id
	if nearest_id.is_empty():
		return ""
	remove_entity(nearest_id)
	return nearest_id


func save_all_loaded_chunks() -> Dictionary:
	var saved_count: int = 0
	var removed_count: int = 0
	var chunks_to_save: Dictionary = loaded_chunk_ids.duplicate()
	for dirty_key in dirty_chunks.keys():
		chunks_to_save[dirty_key] = true
	for chunk_id in chunks_to_save.keys():
		var result: Dictionary = _save_chunk(String(chunk_id))
		if bool(result.get("saved", false)):
			saved_count += 1
		if bool(result.get("removed", false)):
			removed_count += 1
	dirty_chunks.clear()
	_update_manifest_open_time()
	last_save_summary = "saved=%d removed=%d" % [saved_count, removed_count]
	var summary: Dictionary = {
		"saved_chunks": saved_count,
		"removed_empty_chunks": removed_count,
		"loaded_chunks": loaded_chunk_ids.size(),
		"persistent_entities": get_persistent_entity_count(),
		"summary": last_save_summary,
	}
	world_saved.emit(summary)
	_log("INFO", "world_saved", summary)
	return summary


func run_roundtrip_test(
	origin_world_position: Vector3,
	forward_direction: Vector3
) -> Dictionary:
	var test_id: String = "test/persistence-roundtrip"
	if entity_registry.has_entity(test_id):
		remove_entity(test_id)
	var up: Vector3 = origin_world_position.normalized()
	var forward: Vector3 = forward_direction.slide(up).normalized()
	var test_position: Vector3 = origin_world_position + forward * 7.0
	test_position = moon_world.get_surface_point(test_position.normalized()) + up * 0.08
	var created_id: String = create_survey_beacon(
		test_position,
		forward,
		test_id,
		{"diagnostic": {"roundtrip_test": true}}
	)
	if created_id.is_empty():
		return _test_result(false, "Не удалось создать тестовый маяк", {})
	var record = entity_registry.get_entity(test_id)
	var chunk_id: String = record.chunk_id
	var save_result: Dictionary = _save_chunk(chunk_id)
	var chunk_path: String = get_chunk_file_path(chunk_id)
	var file_exists: bool = FileAccess.file_exists(chunk_path)

	_unload_chunk(chunk_id)
	_load_chunk(chunk_id)
	var restored: bool = entity_registry.has_entity(test_id)
	var restored_node: bool = runtime_nodes.has(test_id)
	var passed: bool = (
		bool(save_result.get("saved", false))
		and file_exists
		and restored
		and restored_node
	)
	var result: Dictionary = _test_result(
		passed,
		"PASS: запись → выгрузка → загрузка" if passed else "FAIL: roundtrip не завершён",
		{
			"entity_id": test_id,
			"chunk_id": chunk_id,
			"chunk_path": chunk_path,
			"file_exists": file_exists,
			"entity_restored": restored,
			"runtime_node_restored": restored_node,
		}
	)
	if entity_registry.has_entity(test_id):
		remove_entity(test_id)
	_save_chunk(chunk_id)
	_log("INFO" if passed else "ERROR", "persistence_roundtrip_test", result)
	return result


func clear_world_data() -> void:
	var persistent_ids: Array[String] = []
	for entity_value in entity_registry.entities.values():
		if entity_value.is_persistent():
			persistent_ids.append(entity_value.entity_id)
	for entity_id in persistent_ids:
		_free_runtime_node(entity_id)
		persistent_entity_ids.erase(entity_id)
		entity_registry.unregister_entity(entity_id, false)
	loaded_chunk_ids.clear()
	dirty_chunks.clear()
	journal_revision = 0
	_remove_tree(world_root)
	_ensure_world_layout()
	_ensure_world_manifest()
	_sync_partition_window(zone_manager.create_partition_snapshot())
	world_cleared.emit()
	_log("WARNING", "world_cleared", {"world_id": world_id})


func flush() -> void:
	save_all_loaded_chunks()


func set_last_player_world_position(world_position: Vector3) -> void:
	if world_position.length_squared() > 1.0:
		last_player_world_position = world_position


func get_last_player_world_position() -> Vector3:
	return last_player_world_position


func get_chunk_file_path(chunk_id: String) -> String:
	var parts: PackedStringArray = chunk_id.split("/")
	if parts.size() < 7:
		return ""
	var zone_folder: String = "%s_%s_%s" % [parts[1], parts[2], parts[3]]
	var chunk_file: String = "%s_%s.json" % [parts[5], parts[6]]
	return world_root.path_join("zones/%s/chunks/%s" % [zone_folder, chunk_file])


func get_manifest_path() -> String:
	return manifest_path


func get_journal_path() -> String:
	return journal_path


func get_world_root() -> String:
	return world_root


func get_persistent_entity_count() -> int:
	var result: int = 0
	for entity_value in entity_registry.entities.values():
		if entity_value.is_persistent():
			result += 1
	return result


func get_runtime_summary() -> String:
	return "world=%s loaded_chunks=%d entities=%d loads=%d unloads=%d save=%s" % [
		world_id,
		loaded_chunk_ids.size(),
		get_persistent_entity_count(),
		chunk_load_count,
		chunk_unload_count,
		last_save_summary,
	]


func create_snapshot() -> Dictionary:
	return {
		"schema": "lunar.persistence_runtime.v1",
		"world_id": world_id,
		"world_root": world_root,
		"manifest_path": manifest_path,
		"journal_path": journal_path,
		"loaded_chunk_count": loaded_chunk_ids.size(),
		"runtime_node_count": runtime_nodes.size(),
		"persistent_entity_count": get_persistent_entity_count(),
		"dirty_chunks": dirty_chunks.keys(),
		"chunk_load_count": chunk_load_count,
		"chunk_unload_count": chunk_unload_count,
		"last_save_summary": last_save_summary,
		"last_player_world_position": _vector_to_array(last_player_world_position),
	}


func _connect_signals() -> void:
	zone_manager.partition_window_changed.connect(_on_partition_window_changed)
	entity_registry.entity_registered.connect(_on_entity_registered)
	entity_registry.entity_unregistered.connect(_on_entity_unregistered)
	entity_registry.entity_moved.connect(_on_entity_moved)


func _on_partition_window_changed(snapshot: Dictionary) -> void:
	_sync_partition_window(snapshot)


func _sync_partition_window(snapshot: Dictionary) -> void:
	var desired_chunks: Dictionary = {}
	for zone_snapshot in snapshot.get("zones", []):
		for chunk_snapshot in zone_snapshot.get("chunks", []):
			desired_chunks[String(chunk_snapshot.get("chunk_id", ""))] = true
	for existing_chunk in loaded_chunk_ids.keys():
		if not desired_chunks.has(existing_chunk):
			_unload_chunk(String(existing_chunk))
	for desired_chunk in desired_chunks.keys():
		if not loaded_chunk_ids.has(desired_chunk):
			_load_chunk(String(desired_chunk))


func _on_entity_registered(event: Dictionary) -> void:
	var entity_id: String = String(event.get("entity_id", ""))
	var record = entity_registry.get_entity(entity_id)
	if record == null or not record.is_persistent():
		return
	persistent_entity_ids[entity_id] = true
	_instantiate_runtime_entity(record)
	dirty_chunks[record.chunk_id] = true
	_append_journal("entity_created", record.to_snapshot())
	_save_chunk(record.chunk_id)


func _on_entity_unregistered(event: Dictionary) -> void:
	var entity_id: String = String(event.get("entity_id", ""))
	if not persistent_entity_ids.has(entity_id):
		return
	var chunk_id: String = String(event.get("from_chunk", ""))
	_free_runtime_node(entity_id)
	persistent_entity_ids.erase(entity_id)
	if not chunk_id.is_empty():
		dirty_chunks[chunk_id] = true
		_append_journal("entity_removed", event)
		_save_chunk(chunk_id)


func _on_entity_moved(event: Dictionary) -> void:
	var entity_id: String = String(event.get("entity_id", ""))
	var record = entity_registry.get_entity(entity_id)
	if record == null or not record.is_persistent():
		return
	var previous_chunk: String = String(event.get("from_chunk", ""))
	if not previous_chunk.is_empty():
		dirty_chunks[previous_chunk] = true
		dirty_chunks[record.chunk_id] = true
	_append_journal("entity_moved", event)
	if not previous_chunk.is_empty() and previous_chunk != record.chunk_id:
		_save_chunk(previous_chunk)
	_save_chunk(record.chunk_id)


func _load_chunk(chunk_id: String) -> void:
	if chunk_id.is_empty() or loaded_chunk_ids.has(chunk_id):
		return
	var started_msec: int = Time.get_ticks_msec()
	loaded_chunk_ids[chunk_id] = true
	var restored_ids: Array = []
	var path: String = get_chunk_file_path(chunk_id)
	if not path.is_empty() and FileAccess.file_exists(path):
		var payload: Dictionary = _read_json(path)
		if String(payload.get("schema", "")) == CHUNK_SCHEMA:
			for snapshot in payload.get("entities", []):
				var record = EntityRecordScript.new()
				if not record.setup_from_snapshot(snapshot):
					continue
				if not record.is_persistent():
					continue
				if entity_registry.has_entity(record.entity_id):
					continue
				if entity_registry.register_entity(record, false):
					persistent_entity_ids[record.entity_id] = true
					_instantiate_runtime_entity(record)
					restored_ids.append(record.entity_id)
					loaded_entity_count += 1
	chunk_load_count += 1
	chunk_loaded.emit(chunk_id, restored_ids)
	_log("INFO", "chunk_loaded", {
		"chunk_id": chunk_id,
		"restored_entities": restored_ids,
		"path": path,
		"file_exists": FileAccess.file_exists(path),
		"duration_msec": Time.get_ticks_msec() - started_msec,
	})


func _unload_chunk(chunk_id: String) -> void:
	if not loaded_chunk_ids.has(chunk_id):
		return
	if dirty_chunks.has(chunk_id):
		_save_chunk(chunk_id)
	var entity_ids: Array[String] = []
	for entity_value in entity_registry.get_persistent_entities_in_chunk(chunk_id):
		entity_ids.append(entity_value.entity_id)
	for entity_id in entity_ids:
		_free_runtime_node(entity_id)
		persistent_entity_ids.erase(entity_id)
		entity_registry.unregister_entity(entity_id, false)
	loaded_chunk_ids.erase(chunk_id)
	dirty_chunks.erase(chunk_id)
	chunk_unload_count += 1
	chunk_unloaded.emit(chunk_id)
	_log("INFO", "chunk_unloaded", {
		"chunk_id": chunk_id,
		"unloaded_entities": entity_ids,
	})


func _save_chunk(chunk_id: String) -> Dictionary:
	var started_msec: int = Time.get_ticks_msec()
	if chunk_id.is_empty():
		return {"saved": false, "removed": false}
	var path: String = get_chunk_file_path(chunk_id)
	if path.is_empty():
		return {"saved": false, "removed": false}
	var snapshots: Array[Dictionary] = []
	for entity_value in entity_registry.get_persistent_entities_in_chunk(chunk_id):
		snapshots.append(entity_value.to_snapshot())
	if snapshots.is_empty():
		var existed: bool = FileAccess.file_exists(path)
		if existed:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		dirty_chunks.erase(chunk_id)
		if existed:
			_log("INFO", "empty_chunk_file_removed", {
				"chunk_id": chunk_id,
				"path": path,
				"duration_msec": Time.get_ticks_msec() - started_msec,
			})
		return {"saved": false, "removed": existed, "path": path}
	var partition: Dictionary = _partition_from_chunk_id(chunk_id)
	var payload: Dictionary = {
		"schema": CHUNK_SCHEMA,
		"world_id": world_id,
		"generator_version": moon_world.get_generator_version(),
		"chunk_id": chunk_id,
		"zone_id": partition.get("zone_id", ""),
		"revision": _max_entity_revision(snapshots),
		"updated_at_utc": Time.get_datetime_string_from_system(true, true),
		"entities": snapshots,
		"terrain_delta_revision": 0,
	}
	var success: bool = _write_json_atomic(path, payload)
	if success:
		dirty_chunks.erase(chunk_id)
		var absolute_path: String = ProjectSettings.globalize_path(path)
		var file_size: int = 0
		var saved_file := FileAccess.open(path, FileAccess.READ)
		if saved_file != null:
			file_size = saved_file.get_length()
		_log("INFO", "chunk_saved", {
			"chunk_id": chunk_id,
			"path": path,
			"absolute_path": absolute_path,
			"entity_count": snapshots.size(),
			"bytes": file_size,
			"duration_msec": Time.get_ticks_msec() - started_msec,
		})
	return {"saved": success, "removed": false, "path": path}


func _instantiate_runtime_entity(record) -> void:
	if runtime_nodes.has(record.entity_id):
		return
	if record.entity_type != "survey_beacon":
		return
	var beacon := StaticBody3D.new()
	beacon.name = "SurveyBeacon_%s" % record.entity_id.get_file()
	beacon.collision_layer = 1
	beacon.collision_mask = 1

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.34, 0.38, 0.43)
	metal.metallic = 0.7
	metal.roughness = 0.48
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.94, 0.24, 0.06)
	accent.emission_enabled = true
	accent.emission = Color(0.62, 0.04, 0.01)
	accent.emission_energy_multiplier = 1.8
	accent.roughness = 0.72
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.025, 0.03, 0.04)
	dark.roughness = 0.88

	_add_mesh(beacon, _cylinder_mesh(0.46, 0.18), metal, Vector3(0.0, 0.09, 0.0))
	_add_mesh(beacon, _cylinder_mesh(0.075, 2.4), metal, Vector3(0.0, 1.3, 0.0))
	_add_mesh(beacon, _sphere_mesh(0.22), accent, Vector3(0.0, 2.55, 0.0))
	var panel := BoxMesh.new()
	panel.size = Vector3(0.72, 0.46, 0.08)
	_add_mesh(beacon, panel, dark, Vector3(0.0, 1.65, -0.17))

	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.34
	shape.height = 2.75
	collision.shape = shape
	collision.position.y = 1.375
	beacon.add_child(collision)

	var label := Label3D.new()
	label.text = "SURVEY"
	label.font_size = 38
	label.modulate = Color(1.0, 0.42, 0.18)
	label.position = Vector3(0.0, 1.64, -0.23)
	label.double_sided = true
	label.no_depth_test = false
	beacon.add_child(label)

	entity_root.add_child(beacon)
	runtime_nodes[record.entity_id] = beacon
	update_runtime_transforms()


func _free_runtime_node(entity_id: String) -> void:
	var node = runtime_nodes.get(entity_id)
	if node != null and is_instance_valid(node):
		node.queue_free()
	runtime_nodes.erase(entity_id)


func _add_mesh(
	parent: Node3D,
	mesh: Mesh,
	material: Material,
	position_value: Vector3
) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position_value
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


func _cylinder_mesh(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 2
	return mesh


func _sphere_mesh(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 18
	mesh.rings = 9
	return mesh


func _ensure_world_layout() -> void:
	for path in [world_root, world_root.path_join("zones"), world_root.path_join("journal")]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _ensure_world_manifest() -> void:
	if FileAccess.file_exists(manifest_path):
		var manifest: Dictionary = _read_json(manifest_path)
		last_player_world_position = _array_to_vector3(
			manifest.get("last_player_world_position", [])
		)
		if int(manifest.get("world_seed", -1)) != moon_world.get_world_seed():
			_emit_error("World seed differs from the current terrain generator.")
		if int(manifest.get("generator_version", -1)) != moon_world.get_generator_version():
			_log("WARNING", "generator_version_changed", {
				"saved": manifest.get("generator_version", -1),
				"current": moon_world.get_generator_version(),
			})
		_update_manifest_open_time()
		return
	var now: String = Time.get_datetime_string_from_system(true, true)
	var manifest: Dictionary = {
		"schema": WORLD_SCHEMA,
		"world_id": world_id,
		"world_seed": moon_world.get_world_seed(),
		"generator_version": moon_world.get_generator_version(),
		"created_at_utc": now,
		"last_opened_at_utc": now,
		"last_player_world_position": [],
		"storage_policy": {
			"procedural_terrain_is_authoritative": true,
			"terrain_meshes_are_cached": false,
			"only_modified_chunks_exist_on_disk": true,
		},
	}
	_write_json_atomic(manifest_path, manifest)


func _update_manifest_open_time() -> void:
	var manifest: Dictionary = _read_json(manifest_path)
	if manifest.is_empty():
		return
	manifest["last_opened_at_utc"] = Time.get_datetime_string_from_system(true, true)
	manifest["generator_version"] = moon_world.get_generator_version()
	if last_player_world_position.length_squared() > 1.0:
		manifest["last_player_world_position"] = _vector_to_array(
			last_player_world_position
		)
	_write_json_atomic(manifest_path, manifest)


func _load_journal_revision() -> void:
	journal_revision = 0
	if not FileAccess.file_exists(journal_path):
		return
	var file := FileAccess.open(journal_path, FileAccess.READ)
	if file == null:
		return
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if parsed is Dictionary:
			journal_revision = maxi(
				journal_revision,
				int(parsed.get("revision", 0))
			)


func _append_journal(operation: String, data: Dictionary) -> void:
	journal_revision += 1
	var event: Dictionary = {
		"schema": JOURNAL_SCHEMA,
		"world_id": world_id,
		"revision": journal_revision,
		"timestamp_utc": Time.get_datetime_string_from_system(true, true),
		"operation": operation,
		"data": data.duplicate(true),
	}
	var file_mode: int = (
		FileAccess.READ_WRITE
		if FileAccess.file_exists(journal_path)
		else FileAccess.WRITE
	)
	var file := FileAccess.open(journal_path, file_mode)
	if file == null:
		_emit_error("Could not open world journal: %s" % journal_path)
		return
	if file_mode == FileAccess.READ_WRITE:
		file.seek_end()
	file.store_line(JSON.stringify(event))
	file.flush()


func _write_json_atomic(path: String, payload: Dictionary) -> bool:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var temp_path: String = "%s.tmp" % path
	var backup_path: String = "%s.bak" % path
	var absolute_temp: String = ProjectSettings.globalize_path(temp_path)
	var absolute_backup: String = ProjectSettings.globalize_path(backup_path)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		_emit_error("Could not write temporary file: %s" % temp_path)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	file = null
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	var had_original: bool = FileAccess.file_exists(path)
	if had_original:
		var backup_error: int = DirAccess.rename_absolute(
			absolute_path,
			absolute_backup
		)
		if backup_error != OK:
			_emit_error("Could not create backup for: %s" % path)
			return false
	var rename_error: int = DirAccess.rename_absolute(absolute_temp, absolute_path)
	if rename_error != OK:
		if had_original and FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(absolute_backup, absolute_path)
		_emit_error("Could not atomically replace file: %s" % path)
		return false
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	return true


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	_emit_error("Invalid JSON file: %s" % path)
	return {}


func _partition_from_chunk_id(chunk_id: String) -> Dictionary:
	var parts: PackedStringArray = chunk_id.split("/")
	if parts.size() < 7:
		return {}
	return {
		"zone_id": "zone/%s/%s/%s" % [parts[1], parts[2], parts[3]],
		"chunk_x": int(parts[5]),
		"chunk_y": int(parts[6]),
	}


func _max_entity_revision(snapshots: Array[Dictionary]) -> int:
	var result: int = 0
	for snapshot in snapshots:
		result = maxi(result, int(snapshot.get("revision", 0)))
	return result


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var name: String = directory.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var child_path: String = path.path_join(name)
			if directory.current_is_dir():
				_remove_tree(child_path)
			else:
				directory.remove(name)
		name = directory.get_next()
	directory.list_dir_end()
	directory = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_result(passed: bool, summary: String, details: Dictionary) -> Dictionary:
	return {
		"schema": "lunar.persistence_test.v1",
		"passed": passed,
		"summary": summary,
		"details": details,
	}


func _vector_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _array_to_vector3(value) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _emit_error(message: String) -> void:
	persistence_error.emit(message)
	push_error(message)
	_log("ERROR", "persistence_error", {"message": message})


func _log(level: String, event_name: String, data: Dictionary) -> void:
	if logger == null:
		return
	match level:
		"ERROR":
			logger.error("persistence", event_name, data)
		"WARNING":
			logger.warning("persistence", event_name, data)
		_:
			logger.info("persistence", event_name, data)
