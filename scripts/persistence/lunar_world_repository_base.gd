extends Node

signal chunk_loaded(chunk_id: String, entity_ids: Array)
signal chunk_unloaded(chunk_id: String)
signal world_saved(summary: Dictionary)
signal world_cleared()
signal persistence_error(message: String)

const EntityRecordScript = preload(
	"res://scripts/simulation/entities/entity_record.gd"
)
const PartitionAddressScript = preload(
	"res://scripts/simulation/partition/partition_address.gd"
)
const SurveyBeaconInteractableScript = preload(
	"res://scripts/interaction/survey_beacon_interactable.gd"
)

const DEFAULT_WORLD_ID: String = "moon-experiment-001"
const WORLD_SCHEMA: String = "lunar.world.v1"
const CHUNK_SCHEMA: String = "planet_simulator.chunk.v2"
const LEGACY_CHUNK_SCHEMA: String = "lunar.chunk.v1"
const JOURNAL_SCHEMA: String = "lunar.journal_event.v1"
const LANDMARK_INDEX_SCHEMA: String = "lunar.landmark_index.v1"
const NAVIGATION_MARKER_CONFIG_PATH: String = "res://config/navigation_markers.json"

var moon_world
var zone_manager
var entity_registry
var logger

var world_id: String = DEFAULT_WORLD_ID
var universe_id: String = PartitionAddressScript.DEFAULT_UNIVERSE_ID
var instance_id: String = PartitionAddressScript.DEFAULT_INSTANCE_ID
var partition_space_id: String = PartitionAddressScript.DEFAULT_SPACE_ID
var partition_scheme: String = PartitionAddressScript.DEFAULT_SCHEME
var partition_scheme_revision: int = PartitionAddressScript.DEFAULT_SCHEME_REVISION
var partition_grid_descriptor: Dictionary = {}
var world_root: String = ""
var manifest_path: String = ""
var journal_path: String = ""
var landmark_index_path: String = ""
var entity_root: Node3D
var landmark_root: Node3D

var landmark_records: Dictionary = {}
var landmark_nodes: Dictionary = {}
var landmark_markers_enabled: bool = true
var landmark_marker_max_distance_m: float = 250_000.0
var landmark_marker_min_distance_m: float = 18.0
var landmark_marker_height_m: float = 7.0
var landmark_marker_font_size: int = 11
var landmark_marker_outline_size: int = 2
var landmark_text_update_interval_sec: float = 0.25
var landmark_text_accumulator: float = 0.0
var landmark_index_rebuilt: bool = false

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
var initialized: bool = false


func setup(
	moon_reference,
	zone_manager_reference,
	registry_reference,
	logger_reference = null,
	world_id_override: String = DEFAULT_WORLD_ID,
	root_override: String = ""
) -> bool:
	initialized = false
	universe_id = PartitionAddressScript.DEFAULT_UNIVERSE_ID
	instance_id = PartitionAddressScript.DEFAULT_INSTANCE_ID
	partition_space_id = PartitionAddressScript.DEFAULT_SPACE_ID
	partition_scheme = PartitionAddressScript.DEFAULT_SCHEME
	partition_scheme_revision = PartitionAddressScript.DEFAULT_SCHEME_REVISION
	partition_grid_descriptor = {}
	moon_world = moon_reference
	zone_manager = zone_manager_reference
	entity_registry = registry_reference
	logger = logger_reference
	world_id = world_id_override
	var partition_snapshot: Dictionary = (
		zone_manager.create_partition_snapshot()
		if zone_manager != null and zone_manager.has_method("create_partition_snapshot")
		else {}
	)
	universe_id = String(partition_snapshot.get("universe_id", universe_id))
	instance_id = String(partition_snapshot.get("instance_id", instance_id))
	partition_space_id = String(partition_snapshot.get("space_id", partition_space_id))
	partition_scheme = String(partition_snapshot.get("partition_scheme", partition_scheme))
	partition_scheme_revision = int(partition_snapshot.get(
		"partition_scheme_revision",
		partition_scheme_revision
	))
	var grid_descriptor_value = partition_snapshot.get("partition_grid", {})
	partition_grid_descriptor = (
		grid_descriptor_value.duplicate(true)
		if grid_descriptor_value is Dictionary
		else {}
	)
	world_root = (
		root_override
		if not root_override.is_empty()
		else _resolve_default_world_root()
	)
	manifest_path = world_root.path_join("world.json")
	journal_path = world_root.path_join("journal/events.jsonl")
	landmark_index_path = world_root.path_join("landmarks.json")

	entity_root = Node3D.new()
	entity_root.name = "PersistentEntities"
	add_child(entity_root)
	landmark_root = Node3D.new()
	landmark_root.name = "PersistentLandmarkMarkers"
	add_child(landmark_root)

	_load_navigation_marker_config()
	_ensure_world_layout()
	if not _ensure_world_manifest():
		_log("ERROR", "repository_start_aborted", {
			"world_root": world_root,
			"universe_id": universe_id,
			"instance_id": instance_id,
		})
		return false
	_load_journal_revision()
	_load_or_rebuild_landmark_index()
	_rebuild_landmark_marker_nodes()
	_connect_signals()
	_sync_partition_window(zone_manager.create_partition_snapshot())
	initialized = true
	_log("INFO", "repository_started", create_snapshot())
	return true


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


func update_landmark_markers(observer_world_position: Vector3, delta: float) -> void:
	if landmark_root == null or moon_world == null:
		return
	landmark_text_accumulator += delta
	var update_text: bool = landmark_text_accumulator >= landmark_text_update_interval_sec
	if update_text:
		landmark_text_accumulator = 0.0
	for entity_id in landmark_records.keys():
		var snapshot: Dictionary = landmark_records.get(entity_id, {})
		var node: Node3D = landmark_nodes.get(entity_id)
		if node == null or not is_instance_valid(node):
			_instantiate_landmark_marker(snapshot)
			node = landmark_nodes.get(entity_id)
		if node == null or not is_instance_valid(node):
			continue
		var world_position: Vector3 = _array_to_vector3(
			snapshot.get("world_position", [0.0, 0.0, 0.0])
		)
		if world_position.length_squared() < 1.0:
			node.visible = false
			continue
		var up: Vector3 = world_position.normalized()
		node.position = moon_world.world_to_render(
			world_position + up * landmark_marker_height_m
		)
		var distance_m: float = (
			observer_world_position.distance_to(world_position)
			if observer_world_position.length_squared() > 1.0
			else INF
		)
		var max_distance_m: float = float(
			snapshot.get("max_distance_m", landmark_marker_max_distance_m)
		)
		var marker_enabled: bool = bool(snapshot.get("enabled", true))
		node.visible = (
			landmark_markers_enabled
			and marker_enabled
			and distance_m >= landmark_marker_min_distance_m
			and distance_m <= max_distance_m
		)
		if update_text and node.visible:
			var label := node.get_node_or_null("Label") as Label3D
			if label != null:
				label.text = "%s\n%s" % [
					String(snapshot.get("label", "МАЯК")),
					_format_landmark_distance(distance_m),
				]


func set_landmark_markers_enabled(enabled: bool) -> void:
	landmark_markers_enabled = enabled
	for node_value in landmark_nodes.values():
		if node_value != null and is_instance_valid(node_value):
			node_value.visible = false
	_log("INFO", "landmark_markers_toggled", {
		"enabled": enabled,
		"landmark_count": landmark_records.size(),
	})


func toggle_landmark_markers() -> bool:
	set_landmark_markers_enabled(not landmark_markers_enabled)
	return landmark_markers_enabled


func are_landmark_markers_enabled() -> bool:
	return landmark_markers_enabled


func get_landmark_summary() -> String:
	return "%s, маяков=%d, дальность=%.0f км" % [
		"включены" if landmark_markers_enabled else "выключены",
		landmark_records.size(),
		landmark_marker_max_distance_m / 1000.0,
	]


func get_landmark_world_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for snapshot_value in landmark_records.values():
		if not (snapshot_value is Dictionary):
			continue
		var snapshot: Dictionary = snapshot_value
		var position: Vector3 = _array_to_vector3(
			snapshot.get("world_position", [0.0, 0.0, 0.0])
		)
		if bool(snapshot.get("enabled", true)) and position.length_squared() > 1.0:
			positions.append(position)
	return positions


func _load_navigation_marker_config() -> void:
	if not FileAccess.file_exists(NAVIGATION_MARKER_CONFIG_PATH):
		return
	var file := FileAccess.open(
		NAVIGATION_MARKER_CONFIG_PATH,
		FileAccess.READ
	)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return
	var config: Dictionary = parsed
	landmark_markers_enabled = bool(
		config.get("enabled", landmark_markers_enabled)
	)
	landmark_marker_max_distance_m = maxf(
		1000.0,
		float(config.get(
			"max_distance_m",
			landmark_marker_max_distance_m
		))
	)
	landmark_marker_min_distance_m = maxf(
		0.0,
		float(config.get(
			"min_distance_m",
			landmark_marker_min_distance_m
		))
	)
	landmark_marker_height_m = maxf(
		1.0,
		float(config.get(
			"height_above_surface_m",
			landmark_marker_height_m
		))
	)
	landmark_marker_font_size = maxi(
		6,
		int(config.get("font_size", landmark_marker_font_size))
	)
	landmark_marker_outline_size = maxi(
		0,
		int(config.get("outline_size", landmark_marker_outline_size))
	)
	landmark_text_update_interval_sec = maxf(
		0.05,
		float(config.get(
			"text_update_interval_sec",
			landmark_text_update_interval_sec
		))
	)


func _load_or_rebuild_landmark_index() -> void:
	landmark_records.clear()
	landmark_index_rebuilt = false
	if FileAccess.file_exists(landmark_index_path):
		var payload: Dictionary = _read_json(landmark_index_path)
		if String(payload.get("schema", "")) == LANDMARK_INDEX_SCHEMA:
			for snapshot_value in payload.get("landmarks", []):
				if not (snapshot_value is Dictionary):
					continue
				var snapshot: Dictionary = snapshot_value
				var entity_id: String = String(
					snapshot.get("entity_id", "")
				)
				if not entity_id.is_empty():
					landmark_records[entity_id] = snapshot.duplicate(true)
	if landmark_records.is_empty():
		_rebuild_landmark_index_from_chunk_files()
		landmark_index_rebuilt = true
		_save_landmark_index()
	_log("INFO", "landmark_index_loaded", {
		"path": landmark_index_path,
		"landmark_count": landmark_records.size(),
		"rebuilt": landmark_index_rebuilt,
	})


func _rebuild_landmark_index_from_chunk_files() -> void:
	var files: Array[String] = []
	_collect_json_files_recursive(world_root.path_join("zones"), files)
	_collect_json_files_recursive(world_root.path_join("partitions"), files)
	for path in files:
		var payload: Dictionary = _read_json(path)
		if not _is_supported_chunk_schema(String(payload.get("schema", ""))):
			continue
		for entity_snapshot_value in payload.get("entities", []):
			if not (entity_snapshot_value is Dictionary):
				continue
			var entity_snapshot: Dictionary = entity_snapshot_value
			if String(entity_snapshot.get("entity_type", "")) != "survey_beacon":
				continue
			var landmark_snapshot: Dictionary = (
				_landmark_snapshot_from_entity_snapshot(entity_snapshot)
			)
			var entity_id: String = String(
				landmark_snapshot.get("entity_id", "")
			)
			if not entity_id.is_empty():
				landmark_records[entity_id] = landmark_snapshot


func _collect_json_files_recursive(
	directory_path: String,
	output: Array[String]
) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	for file_name in directory.get_files():
		if file_name.ends_with(".json"):
			output.append(directory_path.path_join(file_name))
	for directory_name in directory.get_directories():
		_collect_json_files_recursive(
			directory_path.path_join(directory_name),
			output
		)


func _save_landmark_index() -> bool:
	var landmarks: Array[Dictionary] = []
	for entity_id in landmark_records.keys():
		var snapshot: Dictionary = landmark_records.get(entity_id, {})
		if not snapshot.is_empty():
			landmarks.append(snapshot.duplicate(true))
	var payload: Dictionary = {
		"schema": LANDMARK_INDEX_SCHEMA,
		"world_id": world_id,
		"updated_at_utc": Time.get_datetime_string_from_system(true, true),
		"landmarks": landmarks,
	}
	var success: bool = _write_json_atomic(landmark_index_path, payload)
	_log("INFO" if success else "ERROR", "landmark_index_saved", {
		"path": landmark_index_path,
		"landmark_count": landmarks.size(),
		"success": success,
	})
	return success


func _landmark_snapshot_from_record(record) -> Dictionary:
	var landmark_component: Dictionary = record.get_component("landmark")
	return {
		"schema": "lunar.landmark.v1",
		"entity_id": record.entity_id,
		"entity_type": record.entity_type,
		"world_position": _vector_to_array(record.world_position),
		"label": String(landmark_component.get("label", "МАЯК")),
		"enabled": bool(landmark_component.get("enabled", true)),
		"marker_type": String(
			landmark_component.get("marker_type", "survey_beacon")
		),
		"max_distance_m": float(
			landmark_component.get(
				"max_distance_m",
				landmark_marker_max_distance_m
			)
		),
	}


func _landmark_snapshot_from_entity_snapshot(
	entity_snapshot: Dictionary
) -> Dictionary:
	var components: Dictionary = entity_snapshot.get("components", {})
	var landmark_component: Dictionary = components.get("landmark", {})
	return {
		"schema": "lunar.landmark.v1",
		"entity_id": String(entity_snapshot.get("entity_id", "")),
		"entity_type": String(
			entity_snapshot.get("entity_type", "survey_beacon")
		),
		"world_position": entity_snapshot.get(
			"world_position",
			[0.0, 0.0, 0.0]
		),
		"label": String(landmark_component.get("label", "МАЯК")),
		"enabled": bool(landmark_component.get("enabled", true)),
		"marker_type": String(
			landmark_component.get("marker_type", "survey_beacon")
		),
		"max_distance_m": float(
			landmark_component.get(
				"max_distance_m",
				landmark_marker_max_distance_m
			)
		),
	}


func _upsert_landmark_from_record(record, save_now: bool = true) -> void:
	if record == null or record.entity_type != "survey_beacon":
		return
	var snapshot: Dictionary = _landmark_snapshot_from_record(record)
	landmark_records[record.entity_id] = snapshot
	_free_landmark_marker(record.entity_id)
	_instantiate_landmark_marker(snapshot)
	if save_now:
		_save_landmark_index()


func _remove_landmark(entity_id: String, save_now: bool = true) -> void:
	landmark_records.erase(entity_id)
	_free_landmark_marker(entity_id)
	if save_now:
		_save_landmark_index()


func _rebuild_landmark_marker_nodes() -> void:
	for entity_id in landmark_nodes.keys():
		_free_landmark_marker(String(entity_id))
	for snapshot_value in landmark_records.values():
		if snapshot_value is Dictionary:
			_instantiate_landmark_marker(snapshot_value)


func _instantiate_landmark_marker(snapshot: Dictionary) -> void:
	if landmark_root == null:
		return
	var entity_id: String = String(snapshot.get("entity_id", ""))
	if entity_id.is_empty() or landmark_nodes.has(entity_id):
		return
	var marker := Node3D.new()
	marker.name = "Landmark_%s" % entity_id.get_file()
	marker.visible = false
	var label := Label3D.new()
	label.name = "Label"
	label.text = String(snapshot.get("label", "МАЯК"))
	label.font_size = landmark_marker_font_size
	label.outline_size = landmark_marker_outline_size
	label.modulate = Color(1.0, 0.46, 0.10, 1.0)
	label.outline_modulate = Color(0.01, 0.01, 0.015, 0.95)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.no_depth_test = true
	label.double_sided = true
	label.pixel_size = 0.0025
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(label)
	landmark_root.add_child(marker)
	landmark_nodes[entity_id] = marker


func _free_landmark_marker(entity_id: String) -> void:
	var node = landmark_nodes.get(entity_id)
	if node != null and is_instance_valid(node):
		node.queue_free()
	landmark_nodes.erase(entity_id)


func _format_landmark_distance(distance_m: float) -> String:
	if distance_m >= 1000.0:
		return "%.1f км" % (distance_m / 1000.0)
	return "%.0f м" % distance_m


func create_survey_beacon(
	world_position: Vector3,
	forward_direction: Vector3,
	entity_id_override: String = "",
	extra_components: Dictionary = {}
) -> String:
	if not initialized or world_position.length_squared() < 1.0:
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
		"interaction": {
			"contract": "lunar.interactable.v1",
			"primary_action": "toggle_signal",
			"max_distance_m": 6.0,
		},
		"beacon_state": {
			"active": true,
			"last_toggled_utc": "",
		},
		"landmark": {
			"enabled": true,
			"marker_type": "survey_beacon",
			"label": "МАЯК",
			"max_distance_m": landmark_marker_max_distance_m,
		},
	}
	for key in extra_components.keys():
		var extra_value = extra_components[key]
		if extra_value is Dictionary or extra_value is Array:
			components[key] = extra_value.duplicate(true)
		else:
			components[key] = extra_value

	var record = EntityRecordScript.new()
	record.setup(
		entity_id,
		"survey_beacon",
		world_position,
		components,
		entity_registry.authority_owner_id,
		entity_registry.authority_epoch,
		{
			"universe_id": universe_id,
			"instance_id": instance_id,
			"space_id": "sol",
			"frame_id": "body/moon/fixed",
		}
	)
	if not entity_registry.register_entity(record):
		return ""
	return entity_id


func toggle_survey_beacon_signal(entity_id: String) -> Dictionary:
	if not initialized:
		return {
			"success": false,
			"message": "Persistence repository не инициализирован",
		}
	var record = entity_registry.get_entity(entity_id)
	if record == null or record.entity_type != "survey_beacon":
		return {
			"success": false,
			"message": "Маяк не найден или не загружен",
		}
	var state: Dictionary = record.get_component("beacon_state")
	var active: bool = not bool(state.get("active", true))
	state["active"] = active
	state["last_toggled_utc"] = Time.get_datetime_string_from_system(true, true)
	var landmark: Dictionary = record.get_component("landmark")
	landmark["enabled"] = active
	if not entity_registry.update_entity_components(entity_id, {
		"beacon_state": state,
		"landmark": landmark,
	}):
		return {
			"success": false,
			"message": "Изменение маяка отклонено authority-контрактом",
		}
	_upsert_landmark_from_record(record)

	var runtime_node = runtime_nodes.get(entity_id)
	if runtime_node != null and is_instance_valid(runtime_node):
		if runtime_node.has_method("set_beacon_active"):
			runtime_node.set_beacon_active(active)
	dirty_chunks[record.chunk_id] = true
	var journal_data: Dictionary = {
		"entity_id": entity_id,
		"entity_type": record.entity_type,
		"chunk_id": record.chunk_id,
		"component": "beacon_state",
		"active": active,
		"revision": record.revision,
	}
	_append_journal("entity_component_changed", journal_data)
	_save_chunk(record.chunk_id)
	_log("INFO", "survey_beacon_signal_toggled", journal_data)
	return {
		"success": true,
		"active": active,
		"entity_id": entity_id,
		"message": "Сигнал маяка %s" % ("включён" if active else "выключен"),
	}


func remove_entity(entity_id: String) -> bool:
	return initialized and entity_registry.unregister_entity(entity_id)


func remove_nearest_survey_beacon(
	world_position: Vector3,
	max_distance_m: float = 14.0
) -> String:
	if not initialized:
		return ""
	var nearest_id: String = ""
	var nearest_distance: float = max_distance_m
	for entity_value in entity_registry.get_entities_by_type("survey_beacon"):
		var distance: float = entity_value.world_position.distance_to(world_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest_id = entity_value.entity_id
	if nearest_id.is_empty():
		return ""
	return nearest_id if remove_entity(nearest_id) else ""


func save_all_loaded_chunks() -> Dictionary:
	if not initialized:
		return {
			"saved_chunks": 0,
			"removed_empty_chunks": 0,
			"loaded_chunks": 0,
			"persistent_entities": 0,
			"summary": "repository_not_initialized",
		}
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
	if not initialized:
		return _test_result(false, "Persistence repository не инициализирован", {
			"reason": "repository_not_initialized",
		})
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
	var interaction_result: Dictionary = toggle_survey_beacon_signal(test_id)
	var save_result: Dictionary = _save_chunk(chunk_id)
	var chunk_path: String = get_chunk_file_path(chunk_id)
	var file_exists: bool = FileAccess.file_exists(chunk_path)

	_unload_chunk(chunk_id)
	_load_chunk(chunk_id)
	var restored: bool = entity_registry.has_entity(test_id)
	var restored_node: bool = runtime_nodes.has(test_id)
	var restored_record = entity_registry.get_entity(test_id)
	var restored_state: Dictionary = (
		restored_record.get_component("beacon_state")
		if restored_record != null
		else {}
	)
	var restored_inactive: bool = not bool(restored_state.get("active", true))
	var restored_runtime_inactive: bool = false
	var restored_runtime = runtime_nodes.get(test_id)
	if restored_runtime != null and is_instance_valid(restored_runtime):
		restored_runtime_inactive = not bool(restored_runtime.get("beacon_active"))
	var passed: bool = (
		bool(interaction_result.get("success", false))
		and not bool(interaction_result.get("active", true))
		and bool(save_result.get("saved", false))
		and file_exists
		and restored
		and restored_node
		and restored_inactive
		and restored_runtime_inactive
	)
	var result: Dictionary = _test_result(
		passed,
		"PASS: запись → выгрузка → загрузка" if passed else "FAIL: roundtrip не завершён",
		{
			"entity_id": test_id,
			"chunk_id": chunk_id,
			"chunk_path": chunk_path,
			"file_exists": file_exists,
			"interaction_success": bool(
				interaction_result.get("success", false)
			),
			"entity_restored": restored,
			"runtime_node_restored": restored_node,
			"beacon_state_restored": restored_inactive,
			"runtime_state_restored": restored_runtime_inactive,
		}
	)
	if entity_registry.has_entity(test_id):
		remove_entity(test_id)
	_save_chunk(chunk_id)
	_log("INFO" if passed else "ERROR", "persistence_roundtrip_test", result)
	return result


func clear_world_data() -> void:
	if not initialized:
		_emit_error("Refusing to clear an uninitialized persistence repository.")
		return
	var persistent_ids: Array[String] = []
	for entity_value in entity_registry.entities.values():
		if entity_value.is_persistent():
			persistent_ids.append(entity_value.entity_id)
	for entity_id in persistent_ids:
		_free_runtime_node(entity_id)
		persistent_entity_ids.erase(entity_id)
		entity_registry.delete_authoritative_entity(entity_id, false)
	loaded_chunk_ids.clear()
	dirty_chunks.clear()
	journal_revision = 0
	landmark_records.clear()
	for landmark_id in landmark_nodes.keys():
		_free_landmark_marker(String(landmark_id))
	_remove_tree(world_root)
	_ensure_world_layout()
	initialized = _ensure_world_manifest()
	if not initialized:
		return
	_save_landmark_index()
	_sync_partition_window(zone_manager.create_partition_snapshot())
	world_cleared.emit()
	_log("WARNING", "world_cleared", {"world_id": world_id})


func flush() -> void:
	if initialized:
		save_all_loaded_chunks()


func set_last_player_world_position(world_position: Vector3) -> void:
	if world_position.length_squared() > 1.0:
		last_player_world_position = world_position


func get_last_player_world_position() -> Vector3:
	return last_player_world_position


func get_chunk_file_path(chunk_id: String) -> String:
	var address: Dictionary = PartitionAddressScript.parse(
		chunk_id,
		_partition_defaults()
	)
	if address.is_empty() or not PartitionAddressScript.has_chunk(address):
		return ""
	var components: PackedStringArray = PartitionAddressScript.file_components(address)
	var path: String = world_root.path_join("partitions")
	for component in components:
		path = path.path_join(component)
	return path


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
	return "world=%s loaded_chunks=%d entities=%d landmarks=%d loads=%d unloads=%d save=%s" % [
		world_id,
		loaded_chunk_ids.size(),
		get_persistent_entity_count(),
		landmark_records.size(),
		chunk_load_count,
		chunk_unload_count,
		last_save_summary,
	]


func create_snapshot() -> Dictionary:
	return {
		"schema": "lunar.persistence_runtime.v1",
		"initialized": initialized,
		"world_id": world_id,
		"universe_id": universe_id,
		"instance_id": instance_id,
		"partition_space_id": partition_space_id,
		"partition_scheme": partition_scheme,
		"partition_scheme_revision": partition_scheme_revision,
		"partition_grid": partition_grid_descriptor.duplicate(true),
		"world_root": world_root,
		"manifest_path": manifest_path,
		"journal_path": journal_path,
		"landmark_index_path": landmark_index_path,
		"landmark_count": landmark_records.size(),
		"landmark_marker_node_count": landmark_nodes.size(),
		"landmark_markers_enabled": landmark_markers_enabled,
		"landmark_marker_max_distance_m": landmark_marker_max_distance_m,
		"landmark_index_rebuilt": landmark_index_rebuilt,
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
	_upsert_landmark_from_record(record)
	dirty_chunks[record.chunk_id] = true
	_append_journal("entity_created", record.to_snapshot())
	_save_chunk(record.chunk_id)


func _on_entity_unregistered(event: Dictionary) -> void:
	var entity_id: String = String(event.get("entity_id", ""))
	if not persistent_entity_ids.has(entity_id):
		return
	var chunk_id: String = String(event.get("from_chunk", ""))
	_free_runtime_node(entity_id)
	_remove_landmark(entity_id)
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
	_upsert_landmark_from_record(record)
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
	var loaded_from_legacy_path: bool = false
	var loaded_from_previous_namespaced_path: bool = false
	var loaded_from_pre_instance_namespaced_path: bool = false
	if not FileAccess.file_exists(path):
		var previous_namespaced_path: String = (
			_get_previous_namespaced_chunk_file_path(chunk_id)
		)
		if FileAccess.file_exists(previous_namespaced_path):
			path = previous_namespaced_path
			loaded_from_previous_namespaced_path = true
		else:
			var pre_instance_path: String = (
				_get_pre_instance_namespaced_chunk_file_path(chunk_id)
			)
			if FileAccess.file_exists(pre_instance_path):
				path = pre_instance_path
				loaded_from_pre_instance_namespaced_path = true
			else:
				var legacy_path: String = _get_legacy_chunk_file_path(chunk_id)
				if FileAccess.file_exists(legacy_path):
					path = legacy_path
					loaded_from_legacy_path = true
	if not path.is_empty() and FileAccess.file_exists(path):
		var payload: Dictionary = _read_json(path)
		if _is_supported_chunk_schema(String(payload.get("schema", ""))):
			for snapshot in payload.get("entities", []):
				var record = EntityRecordScript.new()
				if not record.setup_from_snapshot(snapshot):
					continue
				if not record.is_persistent():
					continue
				if entity_registry.has_entity(record.entity_id):
					continue
				if entity_registry.register_entity(
					record,
					false,
					{"adopt_authority": true}
				):
					persistent_entity_ids[record.entity_id] = true
					_instantiate_runtime_entity(record)
					restored_ids.append(record.entity_id)
					loaded_entity_count += 1
	if (
		loaded_from_legacy_path
		or loaded_from_previous_namespaced_path
		or loaded_from_pre_instance_namespaced_path
	):
		dirty_chunks[chunk_id] = true
	chunk_load_count += 1
	chunk_loaded.emit(chunk_id, restored_ids)
	_log("INFO", "chunk_loaded", {
		"chunk_id": chunk_id,
		"restored_entities": restored_ids,
		"path": path,
		"file_exists": FileAccess.file_exists(path),
		"loaded_from_legacy_path": loaded_from_legacy_path,
		"loaded_from_previous_namespaced_path": loaded_from_previous_namespaced_path,
		"loaded_from_pre_instance_namespaced_path": loaded_from_pre_instance_namespaced_path,
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
		entity_registry.evict_local_record(entity_id, "partition_unload")
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
		var removed_any: bool = false
		if FileAccess.file_exists(path):
			removed_any = (
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK
				or removed_any
			)
		removed_any = _remove_obsolete_chunk_paths(chunk_id, path) or removed_any
		dirty_chunks.erase(chunk_id)
		if removed_any:
			_log("INFO", "empty_chunk_files_removed", {
				"chunk_id": chunk_id,
				"path": path,
				"duration_msec": Time.get_ticks_msec() - started_msec,
			})
		return {"saved": false, "removed": removed_any, "path": path}
	var partition: Dictionary = _partition_from_chunk_id(chunk_id)
	var payload: Dictionary = {
		"schema": CHUNK_SCHEMA,
		"world_id": world_id,
		"generator_version": moon_world.get_generator_version(),
		"chunk_id": chunk_id,
		"zone_id": partition.get("zone_id", ""),
		"partition_address": partition.duplicate(true),
		"revision": _max_entity_revision(snapshots),
		"updated_at_utc": Time.get_datetime_string_from_system(true, true),
		"entities": snapshots,
		"terrain_delta_revision": 0,
	}
	var success: bool = _write_json_atomic(path, payload)
	if success:
		_remove_obsolete_chunk_paths(chunk_id, path)
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
	var beacon = SurveyBeaconInteractableScript.new()
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

	_add_mesh(beacon, _cylinder_mesh(0.46, 0.18), metal, Vector3(0.0, 0.09, 0.0), "Base")
	_add_mesh(beacon, _cylinder_mesh(0.075, 2.4), metal, Vector3(0.0, 1.3, 0.0), "Mast")
	_add_mesh(beacon, _sphere_mesh(0.22), accent, Vector3(0.0, 2.55, 0.0), "Signal")
	var panel := BoxMesh.new()
	panel.size = Vector3(0.72, 0.46, 0.08)
	_add_mesh(beacon, panel, dark, Vector3(0.0, 1.65, -0.17), "Panel")

	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.34
	shape.height = 2.75
	collision.shape = shape
	collision.position.y = 1.375
	beacon.add_child(collision)

	var label := Label3D.new()
	label.name = "BeaconLabel"
	label.text = "SURVEY"
	label.font_size = 38
	label.modulate = Color(1.0, 0.42, 0.18)
	label.position = Vector3(0.0, 1.64, -0.23)
	label.double_sided = true
	label.no_depth_test = false
	beacon.add_child(label)

	entity_root.add_child(beacon)
	runtime_nodes[record.entity_id] = beacon
	var state: Dictionary = record.get_component("beacon_state")
	beacon.setup_interactable(
		self,
		record.entity_id,
		bool(state.get("active", true))
	)
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
	position_value: Vector3,
	name_value: String = "Mesh"
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position_value
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


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


func _resolve_default_world_root() -> String:
	if (
		universe_id == PartitionAddressScript.DEFAULT_UNIVERSE_ID
		and instance_id == PartitionAddressScript.DEFAULT_INSTANCE_ID
	):
		return "user://worlds/%s" % _sanitize_path_component(world_id)
	return "user://universes/%s/instances/%s/worlds/%s" % [
		_sanitize_path_component(universe_id),
		_sanitize_path_component(instance_id),
		_sanitize_path_component(world_id),
	]


func _validate_or_migrate_manifest_identity(manifest: Dictionary) -> bool:
	var migrated_fields := PackedStringArray()
	var legacy_scheme: String = "%s_v%d" % [
		partition_scheme,
		partition_scheme_revision,
	]
	if String(manifest.get("partition_scheme", "")) == legacy_scheme:
		manifest["partition_scheme"] = partition_scheme
		manifest["partition_scheme_revision"] = partition_scheme_revision
		migrated_fields.append("partition_scheme")
		migrated_fields.append("partition_scheme_revision")
	var identity_fields: Dictionary = {
		"universe_id": universe_id,
		"instance_id": instance_id,
		"partition_space_id": partition_space_id,
		"partition_scheme": partition_scheme,
		"partition_scheme_revision": partition_scheme_revision,
	}
	var mismatches := PackedStringArray()
	for field_value in identity_fields.keys():
		var field_name: String = String(field_value)
		var expected_value = identity_fields[field_name]
		if not manifest.has(field_name):
			manifest[field_name] = expected_value
			migrated_fields.append(field_name)
		elif str(manifest.get(field_name, "")) != str(expected_value):
			mismatches.append(field_name)
	if not partition_grid_descriptor.is_empty():
		if not manifest.has("partition_grid"):
			manifest["partition_grid"] = partition_grid_descriptor.duplicate(true)
			migrated_fields.append("partition_grid")
		elif not _partition_grid_identity_matches(
			manifest.get("partition_grid", {}),
			partition_grid_descriptor
		):
			mismatches.append("partition_grid")
	if not mismatches.is_empty():
		_emit_error(
			"World manifest identity mismatch (%s): %s" % [
				", ".join(mismatches),
				manifest_path,
			]
		)
		return false
	if not migrated_fields.is_empty():
		_write_json_atomic(manifest_path, manifest)
		_log("INFO", "world_manifest_identity_migrated", {
			"fields": Array(migrated_fields),
			"universe_id": universe_id,
			"instance_id": instance_id,
			"partition_space_id": partition_space_id,
		})
	return true


func _partition_grid_identity_matches(saved_value, expected: Dictionary) -> bool:
	if not saved_value is Dictionary:
		return false
	var saved: Dictionary = saved_value
	for field_name in [
		"schema",
		"scheme_id",
		"scheme_revision",
		"body_frame_id",
		"zones_per_face",
		"chunks_per_zone",
	]:
		if str(saved.get(field_name, "")) != str(expected.get(field_name, "")):
			return false
	return is_equal_approx(
		float(saved.get("body_radius_m", 0.0)),
		float(expected.get("body_radius_m", -1.0))
	)


func _sanitize_path_component(value: String) -> String:
	var result: String = value.strip_edges().to_lower()
	for character in ["/", "\\", ":", " ", ".."]:
		result = result.replace(character, "_")
	return result if not result.is_empty() else "unknown"


func _ensure_world_layout() -> void:
	for path in [
		world_root,
		world_root.path_join("zones"),
		world_root.path_join("partitions"),
		world_root.path_join("journal"),
	]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _ensure_world_manifest() -> bool:
	if FileAccess.file_exists(manifest_path):
		var manifest: Dictionary = _read_json(manifest_path)
		if not _validate_or_migrate_manifest_identity(manifest):
			last_player_world_position = Vector3.ZERO
			return false
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
		return true
	var now: String = Time.get_datetime_string_from_system(true, true)
	var manifest: Dictionary = {
		"schema": WORLD_SCHEMA,
		"world_id": world_id,
		"universe_id": universe_id,
		"instance_id": instance_id,
		"partition_space_id": partition_space_id,
		"partition_scheme": partition_scheme,
		"partition_scheme_revision": partition_scheme_revision,
		"partition_grid": partition_grid_descriptor.duplicate(true),
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
	return _write_json_atomic(manifest_path, manifest)


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
		"universe_id": universe_id,
		"instance_id": instance_id,
		"partition_space_id": partition_space_id,
		"partition_scheme": partition_scheme,
		"partition_scheme_revision": partition_scheme_revision,
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
	return PartitionAddressScript.parse(chunk_id, _partition_defaults())


func _partition_defaults() -> Dictionary:
	return {
		"universe_id": universe_id,
		"instance_id": instance_id,
		"space_id": partition_space_id,
		"partition_scheme": partition_scheme,
		"partition_scheme_revision": partition_scheme_revision,
	}


func _get_previous_namespaced_chunk_file_path(chunk_id: String) -> String:
	var address: Dictionary = _partition_from_chunk_id(chunk_id)
	if address.is_empty() or not PartitionAddressScript.has_chunk(address):
		return ""
	var legacy_scheme_folder: String = "%s_v%d" % [
		String(address.get("partition_scheme", partition_scheme)),
		int(address.get("partition_scheme_revision", partition_scheme_revision)),
	]
	var path: String = world_root.path_join("partitions")
	for component in [
		_sanitize_path_component(String(address.get("universe_id", universe_id))),
		_sanitize_path_component(String(address.get("instance_id", instance_id))),
		_sanitize_path_component(String(address.get("space_id", partition_space_id))),
		_sanitize_path_component(legacy_scheme_folder),
		"face_%d" % int(address.get("face", 0)),
		"zone_%02d_%02d" % [
			int(address.get("zone_x", 0)),
			int(address.get("zone_y", 0)),
		],
		"chunk_%02d_%02d.json" % [
			int(address.get("chunk_x", 0)),
			int(address.get("chunk_y", 0)),
		],
	]:
		path = path.path_join(String(component))
	return path


func _get_pre_instance_namespaced_chunk_file_path(chunk_id: String) -> String:
	var address: Dictionary = _partition_from_chunk_id(chunk_id)
	if address.is_empty() or not PartitionAddressScript.has_chunk(address):
		return ""
	var legacy_scheme_folder: String = "%s_v%d" % [
		String(address.get("partition_scheme", partition_scheme)),
		int(address.get("partition_scheme_revision", partition_scheme_revision)),
	]
	var path: String = world_root.path_join("partitions")
	for component in [
		_sanitize_path_component(String(address.get("universe_id", universe_id))),
		_sanitize_path_component(String(address.get("space_id", partition_space_id))),
		_sanitize_path_component(legacy_scheme_folder),
		"face_%d" % int(address.get("face", 0)),
		"zone_%02d_%02d" % [
			int(address.get("zone_x", 0)),
			int(address.get("zone_y", 0)),
		],
		"chunk_%02d_%02d.json" % [
			int(address.get("chunk_x", 0)),
			int(address.get("chunk_y", 0)),
		],
	]:
		path = path.path_join(String(component))
	return path


func _remove_obsolete_chunk_paths(chunk_id: String, current_path: String) -> bool:
	var removed_any: bool = false
	for obsolete_path in [
		_get_previous_namespaced_chunk_file_path(chunk_id),
		_get_pre_instance_namespaced_chunk_file_path(chunk_id),
		_get_legacy_chunk_file_path(chunk_id),
	]:
		var path: String = String(obsolete_path)
		if path.is_empty() or path == current_path or not FileAccess.file_exists(path):
			continue
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK:
			removed_any = true
	return removed_any


func _get_legacy_chunk_file_path(chunk_id: String) -> String:
	var address: Dictionary = _partition_from_chunk_id(chunk_id)
	if address.is_empty() or not PartitionAddressScript.has_chunk(address):
		return ""
	var zone_folder: String = "f%d_%02d_%02d" % [
		int(address.get("face", 0)),
		int(address.get("zone_x", 0)),
		int(address.get("zone_y", 0)),
	]
	var chunk_file: String = "%02d_%02d.json" % [
		int(address.get("chunk_x", 0)),
		int(address.get("chunk_y", 0)),
	]
	return world_root.path_join("zones/%s/chunks/%s" % [zone_folder, chunk_file])


func _is_supported_chunk_schema(schema: String) -> bool:
	return schema == CHUNK_SCHEMA or schema == LEGACY_CHUNK_SCHEMA


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
