extends SceneTree

const CubeSphereGridScript = preload(
	"res://scripts/simulation/partition/cube_sphere_grid.gd"
)
const ZoneManagerScript = preload(
	"res://scripts/world/zones/lunar_zone_manager.gd"
)
const MockMoonWorldScript = preload(
	"res://tests/support/mock_moon_world.gd"
)
const PartitionAddressScript = preload(
	"res://scripts/simulation/partition/partition_address.gd"
)

var failures: Array[String] = []


func _init() -> void:
	_test_partition_runtime()
	_test_custom_grid_runtime()

	if failures.is_empty():
		print("Partition foundation tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Partition foundation tests: FAIL (%d)" % failures.size())
	quit(1)


func _test_partition_runtime() -> void:
	var mock_world = MockMoonWorldScript.new()
	var manager = ZoneManagerScript.new()
	_assert(
		manager.setup(mock_world, {
			"partition_grid_config_path": "res://config/partitions/moon_surface.json",
		}),
		"Moon partition runtime rejected its valid grid configuration."
	)
	manager.update_observer(Vector3(1_737_400.0, 0.0, 0.0), false)

	var initial_zone_count: int = manager.get_loaded_zone_count()
	var initial_chunk_count: int = manager.get_loaded_chunk_count()
	_assert(initial_zone_count > 1, "Runtime must keep multiple zones loaded.")
	_assert(initial_chunk_count > 1, "Runtime must keep multiple chunks loaded.")
	_assert(manager.get_active_chunk_count() > 0, "Runtime must have active chunks.")

	manager.update_observer(Vector3(1_737_401.0, 0.0, 0.0), false)
	_assert(
		manager.get_loaded_zone_count() == initial_zone_count,
		"Same chunk update must not grow the zone window."
	)
	_assert(
		manager.get_loaded_chunk_count() == initial_chunk_count,
		"Same chunk update must not grow the chunk window."
	)

	var snapshot: Dictionary = manager.create_partition_snapshot()
	_assert(
		snapshot.get("schema", "") == "planet_simulator.partition_window.v2",
		"Unexpected partition schema."
	)
	_assert(not String(snapshot.get("active_zone", "")).is_empty(), "Active zone is missing.")
	_assert(not String(snapshot.get("active_chunk", "")).is_empty(), "Active chunk is missing.")
	_assert(
		String(snapshot.get("active_chunk", "")).begins_with(
			"universe/main/instance/persistent/space/moon/"
		),
		"Active chunk is not namespaced."
	)
	_assert(
		String(snapshot.get("partition_frame_id", "")) == "body/moon/fixed",
		"Partition frame ID is missing or incorrect."
	)
	var descriptor: Dictionary = snapshot.get("partition_grid", {})
	_assert(
		String(descriptor.get("schema", "")) == CubeSphereGridScript.SCHEMA,
		"Partition grid descriptor is missing."
	)
	_assert(
		int(descriptor.get("zones_per_face", 0)) == 48
		and int(descriptor.get("chunks_per_zone", 0)) == 32,
		"Moon partition density is incorrect."
	)

	manager.update_interest_source(
		"robot/remote-probe",
		Vector3(0.0, 1_737_400.0, 0.0),
		false,
		false
	)
	_assert(manager.get_interest_source_count() == 2, "Multiple interest sources were not retained.")
	_assert(
		manager.get_loaded_chunk_count() > initial_chunk_count,
		"Second distant interest source did not expand the partition window."
	)
	manager.remove_interest_source("robot/remote-probe")
	_assert(
		manager.get_interest_source_count() == 1,
		"Removing one interest source removed the primary observer."
	)
	manager.remove_interest_source("primary_observer")
	_assert(manager.get_interest_source_count() == 0, "Final interest source was not removed.")
	_assert(
		manager.get_loaded_chunk_count() == 0,
		"Partition window remained loaded without interest sources."
	)
	manager.setup(mock_world, {"instance_id": "scenario-a"})
	_assert(
		manager.get_partition_instance_id() == "scenario-a",
		"Zone manager did not apply instance identity."
	)
	manager.setup(mock_world)
	_assert(
		manager.get_partition_instance_id() == PartitionAddressScript.DEFAULT_INSTANCE_ID,
		"Zone manager leaked instance identity across setup calls."
	)
	manager.free()
	mock_world.free()


func _test_custom_grid_runtime() -> void:
	var mock_world = MockMoonWorldScript.new()
	var manager = ZoneManagerScript.new()
	_assert(
		manager.setup(mock_world, {
			"space_id": "earth",
			"partition_grid_config_path": "res://config/partitions/earth_surface.json",
		}),
		"Earth partition runtime rejected its valid grid configuration."
	)
	_assert(manager.get_zones_per_face() == 96, "Earth grid config was not loaded.")
	_assert(manager.get_chunks_per_zone() == 32, "Earth chunk density was not loaded.")
	_assert(
		String(manager.get_partition_frame_id()) == "body/earth/fixed",
		"Earth grid body frame was not applied."
	)
	var partition: Dictionary = manager.resolve_partition(Vector3(6_371_000.0, 0.0, 0.0))
	_assert(
		String(partition.get("chunk_id", "")).contains("/space/earth/"),
		"Custom grid did not produce an Earth namespace."
	)
	_assert(
		int(partition.get("partition_scheme_revision", 0)) == 1,
		"Custom grid lost scheme revision."
	)
	_assert(
		not manager.setup(mock_world, {
			"instance_id": "invalid/path",
			"partition_grid_config_path": "res://config/partitions/earth_surface.json",
		}),
		"Partition runtime silently accepted an invalid namespace."
	)
	_assert(
		not manager.setup(mock_world, {
			"partition_grid": {"zones_per_face": 0},
		}),
		"Partition runtime silently replaced an invalid grid with defaults."
	)
	manager.free()
	mock_world.free()


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
