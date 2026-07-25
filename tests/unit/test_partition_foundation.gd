extends SceneTree

const AddressScript = preload(
	"res://scripts/world/coordinates/lunar_cube_address.gd"
)
const ZoneManagerScript = preload(
	"res://scripts/world/zones/lunar_zone_manager.gd"
)
const MockMoonWorldScript = preload(
	"res://tests/support/mock_moon_world.gd"
)

var failures: Array[String] = []


func _init() -> void:
	_test_cube_faces()
	_test_scale_invariance()
	_test_address_ranges()
	_test_partition_runtime()

	if failures.is_empty():
		print("Partition foundation tests: PASS")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	print("Partition foundation tests: FAIL (%d)" % failures.size())
	quit(1)


func _test_cube_faces() -> void:
	var directions: Array[Vector3] = [
		Vector3.RIGHT,
		Vector3.LEFT,
		Vector3.UP,
		Vector3.DOWN,
		Vector3.BACK,
		Vector3.FORWARD,
	]
	var faces: Dictionary = {}
	for direction in directions:
		var face_uv: Vector3 = AddressScript.direction_to_face_uv(direction)
		faces[int(face_uv.x)] = true
	_assert(faces.size() == 6, "Cardinal directions must resolve to six cube faces.")


func _test_scale_invariance() -> void:
	var address_a: Dictionary = AddressScript.direction_to_address(
		Vector3(1.0, 2.0, 3.0),
		48,
		32
	)
	var address_b: Dictionary = AddressScript.direction_to_address(
		Vector3(10.0, 20.0, 30.0),
		48,
		32
	)
	_assert(address_a == address_b, "Address must not depend on vector length.")


func _test_address_ranges() -> void:
	var samples: Array[Vector3] = [
		Vector3(1.0, 0.2, -0.4),
		Vector3(-0.3, 1.0, 0.8),
		Vector3(0.5, -0.7, 1.0),
		Vector3(-1.0, -1.0, -1.0),
	]
	for sample in samples:
		var address: Dictionary = AddressScript.direction_to_address(sample, 48, 32)
		_assert(int(address["face"]) >= 0 and int(address["face"]) < 6, "Face out of range.")
		_assert(int(address["zone_x"]) >= 0 and int(address["zone_x"]) < 48, "Zone X out of range.")
		_assert(int(address["zone_y"]) >= 0 and int(address["zone_y"]) < 48, "Zone Y out of range.")
		_assert(int(address["chunk_x"]) >= 0 and int(address["chunk_x"]) < 32, "Chunk X out of range.")
		_assert(int(address["chunk_y"]) >= 0 and int(address["chunk_y"]) < 32, "Chunk Y out of range.")


func _test_partition_runtime() -> void:
	var mock_world = MockMoonWorldScript.new()
	var manager = ZoneManagerScript.new()
	manager.setup(mock_world)
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
	_assert(snapshot.get("schema", "") == "lunar.partition.v1", "Unexpected partition schema.")
	_assert(not String(snapshot.get("active_zone", "")).is_empty(), "Active zone is missing.")
	_assert(not String(snapshot.get("active_chunk", "")).is_empty(), "Active chunk is missing.")


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
