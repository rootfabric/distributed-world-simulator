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
	var test_root: String = "user://tests/persistence_%d" % Time.get_ticks_msec()
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

	var result: Dictionary = repository.run_roundtrip_test(start, forward)
	_assert(bool(result.get("passed", false)), "Persistence roundtrip mini-test failed.")
	_assert(FileAccess.file_exists(repository.get_journal_path()), "World journal was not created.")

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
