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
const SpatialRefScript = preload(
	"res://scripts/simulation/spatial/spatial_ref.gd"
)
const PartitionAddressScript = preload(
	"res://scripts/simulation/partition/partition_address.gd"
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
	var revision_before_chunk_crossing: int = record.revision
	registry.update_entity_position("test/probe", target)
	_assert(
		record.revision == revision_before_chunk_crossing + 1,
		"One spatial command must increment entity revision exactly once."
	)
	_assert(entered_chunk_events >= 1, "Chunk enter event was not emitted.")
	_assert(left_chunk_events >= 1, "Chunk leave event was not emitted.")
	_assert(registry.chunk_transition_count >= 1, "Chunk transition counter did not change.")

	var far_target := Vector3(0.0, 1_737_400.0, 0.0)
	manager.update_observer(far_target, false)
	registry.update_entity_position("test/probe", far_target)
	_assert(entered_zone_events >= 1, "Zone enter event was not emitted.")
	_assert(registry.zone_transition_count >= 1, "Zone transition counter did not change.")


	var revision_before_orientation: int = record.revision
	var rotated_ref: Dictionary = record.spatial_ref.duplicate(true)
	var rotated_basis := Basis(Vector3.UP, 0.25)
	var rotated_quaternion: Quaternion = rotated_basis.get_rotation_quaternion()
	rotated_ref["rotation_xyzw"] = [
		rotated_quaternion.x,
		rotated_quaternion.y,
		rotated_quaternion.z,
		rotated_quaternion.w,
	]
	rotated_ref["linear_velocity_mps"] = [1.0, 2.0, 3.0]
	_assert(
		registry.update_entity_spatial_ref("test/probe", rotated_ref),
		"Orientation-only spatial update was ignored."
	)
	_assert(
		record.revision == revision_before_orientation + 1,
		"Orientation and velocity update must increment revision exactly once."
	)

	var revision_before_components: int = record.revision
	_assert(
		registry.update_entity_components("test/probe", {
			"controller": {"profile_id": "test"},
			"telemetry": {"enabled": true},
		}),
		"Atomic component patch was rejected."
	)
	_assert(
		record.revision == revision_before_components + 1,
		"One component patch must increment revision exactly once."
	)

	var wrong_frame_ref: Dictionary = SpatialRefScript.create(
		"sol.barycentric",
		record.world_position
	)
	_assert(
		not registry.update_entity_spatial_ref("test/probe", wrong_frame_ref),
		"Partition resolver accepted coordinates from the wrong frame."
	)
	var wrong_instance_ref: Dictionary = record.spatial_ref.duplicate(true)
	wrong_instance_ref["instance_id"] = "parallel-scenario"
	_assert(
		not registry.update_entity_spatial_ref("test/probe", wrong_instance_ref),
		"Partition resolver accepted coordinates from another universe instance."
	)

	var position_before_stale_write: Vector3 = record.world_position
	var stale_write_accepted: bool = registry.update_entity_position(
		"test/probe",
		manager.offset_surface_position(far_target, 100.0, 0.0),
		{
			"authority_owner_id": "local-process",
			"authority_epoch": record.authority_epoch - 1,
		}
	)
	_assert(not stale_write_accepted, "Stale authority epoch write was accepted.")
	_assert(
		record.world_position == position_before_stale_write,
		"Rejected stale write changed entity position."
	)
	_assert(
		registry.stale_write_rejection_count == 1,
		"Stale write rejection counter did not change."
	)
	registry.authority_epoch = record.authority_epoch + 1
	_assert(
		not registry.update_entity_position(
			"test/probe",
			manager.offset_surface_position(far_target, 200.0, 0.0)
		),
		"Registry accepted an entity from an obsolete authority epoch."
	)
	_assert(
		not registry.delete_authoritative_entity("test/probe", false),
		"Registry deleted an entity from an obsolete authority epoch."
	)
	_assert(
		registry.has_entity("test/probe"),
		"Rejected stale delete removed the entity."
	)
	registry.authority_epoch = record.authority_epoch

	var origin_record = EntityRecordScript.new()
	var origin_partition: Dictionary = PartitionAddressScript.create_cube_sphere(
		0, 0, 0, 0, 0
	)
	var origin_ref: Dictionary = SpatialRefScript.create(
		"body/moon/fixed",
		Vector3.ZERO
	)
	origin_record.setup_with_spatial_ref("test/origin", "generic", origin_ref)
	origin_record.initialize_partition(origin_partition)
	_assert(
		origin_record.setup_from_snapshot(origin_record.to_snapshot()),
		"Entity v2 rejected a valid origin coordinate."
	)

	var legacy_record = EntityRecordScript.new()
	_assert(
		legacy_record.setup_from_snapshot({
			"schema": "lunar.entity.v1",
			"entity_id": "legacy/probe",
			"entity_type": "diagnostic_probe",
			"zone_id": "zone/f0/00/00",
			"chunk_id": "zone/f0/00/00/chunk/00/00",
			"world_position": [1737400.0, 0.0, 0.0],
			"revision": 7,
			"components": {},
		}),
		"Legacy entity snapshot was not migrated."
	)
	_assert(
		String(legacy_record.spatial_ref.get("frame_id", "")) == "body/moon/fixed",
		"Legacy entity migrated to an unexpected reference frame."
	)
	_assert(legacy_record.state_revision == 7, "Legacy revision migration failed.")

	var snapshot: Dictionary = registry.create_snapshot()
	_assert(
		snapshot.get("schema", "") == "planet_simulator.entity_registry.v2",
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
