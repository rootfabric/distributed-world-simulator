extends SceneTree

const ZoneManagerScript = preload(
	"res://scripts/world/zones/lunar_zone_manager.gd"
)
const EntityRegistryScript = preload(
	"res://scripts/simulation/entities/entity_registry.gd"
)
const LoggerScript = preload(
	"res://scripts/diagnostics/lunar_logger.gd"
)
const RepositoryScript = preload(
	"res://scripts/persistence/lunar_world_repository.gd"
)
const MockMoonWorldScript = preload(
	"res://tests/support/mock_moon_world.gd"
)

var failures: Array[String] = []


func _init() -> void:
	_assert(
		FileAccess.file_exists("res://config/navigation_markers.json"),
		"Navigation marker config is missing."
	)
	var test_root: String = "user://tests/persistence_%d" % Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(test_root))
	var legacy_manifest := FileAccess.open(
		test_root.path_join("world.json"),
		FileAccess.WRITE
	)
	if legacy_manifest != null:
		legacy_manifest.store_string(JSON.stringify({
			"schema": "lunar.world.v1",
			"world_id": "persistence-test",
			"world_seed": 20260724,
			"generator_version": 9,
			"partition_scheme": "cube_sphere_v1",
			"last_player_world_position": [],
		}))
		legacy_manifest = null
	var container := Node.new()
	get_root().add_child(container)
	var mock_world = MockMoonWorldScript.new()
	container.add_child(mock_world)
	var manager = ZoneManagerScript.new()
	container.add_child(manager)
	manager.setup(mock_world)
	var start := Vector3(1_737_400.0, 0.0, 0.0)
	manager.update_observer(start, false)

	var logger = LoggerScript.new()
	container.add_child(logger)
	logger.setup(true)
	var registry = EntityRegistryScript.new()
	container.add_child(registry)
	registry.setup(manager, logger)
	var repository = RepositoryScript.new()
	container.add_child(repository)
	repository.setup(
		mock_world,
		manager,
		registry,
		logger,
		"persistence-test",
		test_root
	)

	_assert(FileAccess.file_exists(repository.get_manifest_path()), "World manifest was not created.")
	var migrated_manifest_file := FileAccess.open(
		repository.get_manifest_path(),
		FileAccess.READ
	)
	var migrated_manifest: Dictionary = (
		JSON.parse_string(migrated_manifest_file.get_as_text())
		if migrated_manifest_file != null
		else {}
	)
	migrated_manifest_file = null
	_assert(
		String(migrated_manifest.get("universe_id", "")) == "main"
		and String(migrated_manifest.get("instance_id", "")) == "persistent"
		and String(migrated_manifest.get("partition_space_id", "")) == "moon"
		and String(migrated_manifest.get("partition_scheme", "")) == "cube_sphere"
		and int(migrated_manifest.get("partition_scheme_revision", 0)) == 1,
		"Legacy world manifest identity was not migrated."
	)
	var migrated_grid: Dictionary = migrated_manifest.get("partition_grid", {})
	_assert(
		String(migrated_grid.get("body_frame_id", "")) == "body/moon/fixed"
		and int(migrated_grid.get("zones_per_face", 0)) == 48
		and int(migrated_grid.get("chunks_per_zone", 0)) == 32,
		"World manifest did not persist the exact partition-grid descriptor."
	)
	var forward := Vector3(0.0, 0.0, -1.0)
	var entity_id: String = repository.create_survey_beacon(
		start + Vector3(0.0, 0.0, -5.0),
		forward,
		"test/survey-beacon"
	)
	_assert(not entity_id.is_empty(), "Survey beacon was not created.")
	var record = registry.get_entity(entity_id)
	_assert(record != null, "Beacon record is missing from registry.")
	var chunk_path: String = repository.get_chunk_file_path(record.chunk_id)
	_assert(FileAccess.file_exists(chunk_path), "Changed chunk file was not created.")
	_assert(
		chunk_path.contains("/partitions/main/persistent/moon/cube_sphere_r1/"),
		"Chunk was not written to the namespaced partition path."
	)
	var chunk_file := FileAccess.open(chunk_path, FileAccess.READ)
	var chunk_payload: Dictionary = (
		JSON.parse_string(chunk_file.get_as_text())
		if chunk_file != null
		else {}
	)
	chunk_file = null
	_assert(
		String(chunk_payload.get("schema", "")) == "planet_simulator.chunk.v2",
		"Chunk was not saved with schema v2."
	)
	_assert(
		String(chunk_payload.get("chunk_id", "")).begins_with(
			"universe/main/instance/persistent/space/moon/"
		),
		"Saved chunk ID is not namespaced."
	)
	var previous_namespaced_path: String = chunk_path.replace(
		"/cube_sphere_r1/",
		"/cube_sphere_v1/"
	)
	var partition_address: Dictionary = chunk_payload.get("partition_address", {})
	var legacy_chunk_path: String = test_root.path_join(
		"zones/f%d_%02d_%02d/chunks/%02d_%02d.json" % [
			int(partition_address.get("face", 0)),
			int(partition_address.get("zone_x", 0)),
			int(partition_address.get("zone_y", 0)),
			int(partition_address.get("chunk_x", 0)),
			int(partition_address.get("chunk_y", 0)),
		]
	)
	manager.clear_interest_sources()
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(previous_namespaced_path.get_base_dir())
	)
	var current_chunk_file := FileAccess.open(chunk_path, FileAccess.READ)
	var previous_chunk_file := FileAccess.open(previous_namespaced_path, FileAccess.WRITE)
	if current_chunk_file != null and previous_chunk_file != null:
		previous_chunk_file.store_string(current_chunk_file.get_as_text())
	current_chunk_file = null
	previous_chunk_file = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(chunk_path))
	manager.update_observer(start, false)
	_assert(
		registry.has_entity(entity_id),
		"Previous namespaced chunk path was not loaded."
	)
	repository.save_all_loaded_chunks()
	_assert(
		FileAccess.file_exists(chunk_path),
		"Previous namespaced chunk was not migrated to the revisioned path."
	)
	_assert(
		not FileAccess.file_exists(previous_namespaced_path),
		"Obsolete namespaced chunk file remained after migration."
	)
	var pre_instance_namespaced_path: String = previous_namespaced_path.replace(
		"/partitions/main/persistent/moon/",
		"/partitions/main/moon/"
	)
	manager.clear_interest_sources()
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(pre_instance_namespaced_path.get_base_dir())
	)
	var revisioned_for_pre_instance := FileAccess.open(chunk_path, FileAccess.READ)
	var pre_instance_chunk_file := FileAccess.open(
		pre_instance_namespaced_path,
		FileAccess.WRITE
	)
	if revisioned_for_pre_instance != null and pre_instance_chunk_file != null:
		pre_instance_chunk_file.store_string(revisioned_for_pre_instance.get_as_text())
	revisioned_for_pre_instance = null
	pre_instance_chunk_file = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(chunk_path))
	manager.update_observer(start, false)
	_assert(
		registry.has_entity(entity_id),
		"Pre-instance namespaced chunk path was not loaded."
	)
	repository.save_all_loaded_chunks()
	_assert(
		FileAccess.file_exists(chunk_path),
		"Pre-instance namespaced chunk was not migrated to the revisioned path."
	)
	_assert(
		not FileAccess.file_exists(pre_instance_namespaced_path),
		"Pre-instance namespaced chunk file remained after migration."
	)
	manager.clear_interest_sources()
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(legacy_chunk_path.get_base_dir())
	)
	var revisioned_chunk_file := FileAccess.open(chunk_path, FileAccess.READ)
	var legacy_chunk_file := FileAccess.open(legacy_chunk_path, FileAccess.WRITE)
	if revisioned_chunk_file != null and legacy_chunk_file != null:
		legacy_chunk_file.store_string(revisioned_chunk_file.get_as_text())
	revisioned_chunk_file = null
	legacy_chunk_file = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(chunk_path))
	manager.update_observer(start, false)
	_assert(registry.has_entity(entity_id), "Legacy zones chunk path was not loaded.")
	repository.save_all_loaded_chunks()
	_assert(
		FileAccess.file_exists(chunk_path),
		"Legacy zones chunk was not migrated to the revisioned path."
	)
	_assert(
		not FileAccess.file_exists(legacy_chunk_path),
		"Legacy zones chunk file remained after migration."
	)
	_assert(
		FileAccess.file_exists(test_root.path_join("landmarks.json")),
		"Landmark index was not created."
	)
	_assert(
		repository.get_landmark_summary().contains("маяков=1"),
		"Survey beacon was not added to the landmark index."
	)

	_assert(repository.remove_entity(entity_id), "Migrated beacon could not be removed.")
	_assert(
		not FileAccess.file_exists(chunk_path)
		and not FileAccess.file_exists(previous_namespaced_path)
		and not FileAccess.file_exists(pre_instance_namespaced_path)
		and not FileAccess.file_exists(legacy_chunk_path),
		"Deleting the final entity left a current or legacy chunk file that could resurrect it."
	)

	var result: Dictionary = repository.run_roundtrip_test(start, forward)
	_assert(bool(result.get("passed", false)), "Persistence roundtrip mini-test failed.")
	_assert(FileAccess.file_exists(repository.get_journal_path()), "World journal was not created.")
	var journal_file := FileAccess.open(repository.get_journal_path(), FileAccess.READ)
	var journal_line: String = journal_file.get_line() if journal_file != null else ""
	var journal_event: Dictionary = JSON.parse_string(journal_line) if not journal_line.is_empty() else {}
	journal_file = null
	_assert(
		String(journal_event.get("universe_id", "")) == "main"
		and String(journal_event.get("instance_id", "")) == "persistent"
		and String(journal_event.get("partition_space_id", "")) == "moon"
		and String(journal_event.get("partition_scheme", "")) == "cube_sphere"
		and int(journal_event.get("partition_scheme_revision", 0)) == 1,
		"Journal event is missing universe, instance, or grid revision identity."
	)

	var foreign_manager = ZoneManagerScript.new()
	container.add_child(foreign_manager)
	foreign_manager.setup(mock_world, {"instance_id": "scenario-conflict"})
	foreign_manager.update_observer(start, false)
	var foreign_registry = EntityRegistryScript.new()
	container.add_child(foreign_registry)
	foreign_registry.setup(foreign_manager, logger)
	var foreign_repository = RepositoryScript.new()
	container.add_child(foreign_repository)
	_assert(
		not foreign_repository.setup(
			mock_world,
			foreign_manager,
			foreign_registry,
			logger,
			"persistence-test",
			test_root
		),
		"Repository accepted a manifest owned by another universe instance."
	)
	_assert(
		not bool(foreign_repository.create_snapshot().get("initialized", true)),
		"Rejected repository reported itself as initialized."
	)

	var incompatible_grid_manager = ZoneManagerScript.new()
	container.add_child(incompatible_grid_manager)
	incompatible_grid_manager.setup(mock_world, {
		"partition_grid": {
			"scheme_id": "cube_sphere",
			"scheme_revision": 1,
			"body_frame_id": "body/moon/fixed",
			"body_radius_m": 1_737_400.0,
			"zones_per_face": 49,
			"chunks_per_zone": 32,
		},
	})
	incompatible_grid_manager.update_observer(start, false)
	var incompatible_grid_registry = EntityRegistryScript.new()
	container.add_child(incompatible_grid_registry)
	incompatible_grid_registry.setup(incompatible_grid_manager, logger)
	var incompatible_grid_repository = RepositoryScript.new()
	container.add_child(incompatible_grid_repository)
	_assert(
		not incompatible_grid_repository.setup(
			mock_world,
			incompatible_grid_manager,
			incompatible_grid_registry,
			logger,
			"persistence-test",
			test_root
		),
		"Repository accepted a changed grid density without a scheme-revision bump."
	)

	repository.clear_world_data()
	_assert(FileAccess.file_exists(repository.get_manifest_path()), "Manifest was not recreated after clear.")
	_assert(repository.get_persistent_entity_count() == 0, "Persistent entities remained after clear.")

	if failures.is_empty():
		print("Persistent world integration tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Persistent world integration tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
