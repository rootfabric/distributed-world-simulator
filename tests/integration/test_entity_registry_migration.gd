extends SceneTree

const ZoneManagerScript = preload(
	"res://scripts/world/zones/lunar_zone_manager.gd"
)
const EntityRegistryScript = preload(
	"res://scripts/simulation/entities/entity_registry.gd"
)
const EntityRecordScript = preload(
	"res://scripts/simulation/entities/entity_record.gd"
)
const LoggerScript = preload(
	"res://scripts/diagnostics/lunar_logger.gd"
)
const MockMoonWorldScript = preload(
	"res://tests/support/mock_moon_world.gd"
)

var failures: Array[String] = []
var entered_chunk_events: int = 0
var left_chunk_events: int = 0
var entered_zone_events: int = 0


func _init() -> void:
	var mock_world = MockMoonWorldScript.new()
	var manager = ZoneManagerScript.new()
	manager.setup(mock_world)

	var logger = LoggerScript.new()
	logger.setup(true)

	var registry = EntityRegistryScript.new()
	registry.setup(manager, logger)
	registry.entity_entered_chunk.connect(_on_entered_chunk)
	registry.entity_left_chunk.connect(_on_left_chunk)
	registry.entity_entered_zone.connect(_on_entered_zone)

	var start := Vector3(1_737_400.0, 0.0, 0.0)
	manager.update_observer(start, false)
	var record = EntityRecordScript.new()
	record.setup("test/probe", "diagnostic_probe", start)
	_assert(registry.register_entity(record), "Entity registration failed.")
	_assert(not record.zone_id.is_empty(), "Registered entity zone is empty.")
	_assert(not record.chunk_id.is_empty(), "Registered entity chunk is empty.")

	var same_chunk_position := manager.offset_surface_position(start, 2.0, 2.0)
	registry.update_entity_position("test/probe", same_chunk_position)
	_assert(entered_chunk_events == 0, "Small move unexpectedly changed chunk.")

	var target := manager.offset_surface_position(
		start,
		manager.get_nominal_chunk_size_m() * 3.5,
		manager.get_nominal_chunk_size_m() * 0.4
	)
	registry.update_entity_position("test/probe", target)
	_assert(entered_chunk_events >= 1, "Chunk enter event was not emitted.")
	_assert(left_chunk_events >= 1, "Chunk leave event was not emitted.")
	_assert(registry.chunk_transition_count >= 1, "Chunk transition counter did not change.")

	var far_target := Vector3(0.0, 1_737_400.0, 0.0)
	manager.update_observer(far_target, false)
	registry.update_entity_position("test/probe", far_target)
	_assert(entered_zone_events >= 1, "Zone enter event was not emitted.")
	_assert(registry.zone_transition_count >= 1, "Zone transition counter did not change.")

	var snapshot: Dictionary = registry.create_snapshot()
	_assert(
		snapshot.get("schema", "") == "lunar.entity_registry.v1",
		"Unexpected entity registry snapshot schema."
	)
	_assert(int(snapshot.get("entity_count", 0)) == 1, "Unexpected entity count.")
	_assert(logger.get_recent_entries().size() > 0, "Logger did not capture events.")

	registry.free()
	manager.free()
	logger.free()
	mock_world.free()

	if failures.is_empty():
		print("Entity registry integration tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Entity registry integration tests: FAIL (%d)" % failures.size())
	quit(1)


func _on_entered_chunk(_event: Dictionary) -> void:
	entered_chunk_events += 1


func _on_left_chunk(_event: Dictionary) -> void:
	left_chunk_events += 1


func _on_entered_zone(_event: Dictionary) -> void:
	entered_zone_events += 1


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
