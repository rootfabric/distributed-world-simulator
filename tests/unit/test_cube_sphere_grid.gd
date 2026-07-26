extends SceneTree

const CubeSphereGridScript = preload(
	"res://scripts/simulation/partition/cube_sphere_grid.gd"
)
const PartitionAddressScript = preload(
	"res://scripts/simulation/partition/partition_address.gd"
)

var failures: Array[String] = []


func _init() -> void:
	_test_configuration_validation()
	_test_scale_invariance()
	_test_all_faces_and_cell_centers()
	_test_body_specific_grids()
	_test_surface_offsets_across_face_boundary()
	_test_topological_neighbors_across_all_seams()
	_test_partition_address_creation()

	if failures.is_empty():
		print("Cube-sphere grid tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Cube-sphere grid tests: FAIL (%d)" % failures.size())
	quit(1)


func _test_configuration_validation() -> void:
	var grid = CubeSphereGridScript.new()
	_assert(grid.setup(), "Default cube-sphere grid configuration is invalid.")
	_assert(grid.is_valid(), "Default cube-sphere grid did not remain valid.")
	_assert(
		not grid.setup({"body_radius_m": 0.0}),
		"Zero-radius cube-sphere grid was accepted."
	)
	_assert(
		not grid.setup({"zones_per_face": 0}),
		"Zero-zone cube-sphere grid was accepted."
	)
	_assert(
		not grid.setup({"chunks_per_zone": -1}),
		"Negative chunk count was accepted."
	)


func _test_scale_invariance() -> void:
	var grid = _make_grid("body/moon/fixed", 1_737_400.0, 48, 32)
	var address_a: Dictionary = grid.direction_to_cell(Vector3(1.0, 2.0, 3.0))
	var address_b: Dictionary = grid.direction_to_cell(Vector3(10.0, 20.0, 30.0))
	_assert(address_a == address_b, "Cell address depends on direction vector length.")


func _test_all_faces_and_cell_centers() -> void:
	var grid = _make_grid("body/moon/fixed", 1_737_400.0, 48, 32)
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
		var cell: Dictionary = grid.direction_to_cell(direction)
		faces[int(cell.get("face", -1))] = true
	_assert(faces.size() == 6, "Cardinal directions did not resolve to six faces.")

	for face in range(6):
		for zone_x in [0, 23, 47]:
			for zone_y in [0, 24, 47]:
				var zone_direction: Vector3 = grid.zone_center_direction(
					face,
					zone_x,
					zone_y
				)
				var zone_cell: Dictionary = grid.direction_to_cell(zone_direction)
				_assert(
					int(zone_cell.get("face", -1)) == face
					and int(zone_cell.get("zone_x", -1)) == zone_x
					and int(zone_cell.get("zone_y", -1)) == zone_y,
					"Zone center did not roundtrip for face %d zone %d,%d." % [
						face,
						zone_x,
						zone_y,
					]
				)
				var chunk_direction: Vector3 = grid.chunk_center_direction(
					face,
					zone_x,
					zone_y,
					15,
					16
				)
				var chunk_cell: Dictionary = grid.direction_to_cell(chunk_direction)
				_assert(
					int(chunk_cell.get("face", -1)) == face
					and int(chunk_cell.get("zone_x", -1)) == zone_x
					and int(chunk_cell.get("zone_y", -1)) == zone_y
					and int(chunk_cell.get("chunk_x", -1)) == 15
					and int(chunk_cell.get("chunk_y", -1)) == 16,
					"Chunk center did not roundtrip for face %d zone %d,%d." % [
						face,
						zone_x,
						zone_y,
					]
				)


func _test_body_specific_grids() -> void:
	var moon = _make_grid("body/moon/fixed", 1_737_400.0, 48, 32)
	var earth = _make_grid("body/earth/fixed", 6_371_000.0, 96, 32)
	_assert(
		moon.body_frame_id != earth.body_frame_id,
		"Earth and Moon grids share a body frame."
	)
	_assert(
		earth.get_nominal_zone_size_m() > moon.get_nominal_zone_size_m(),
		"Body radius/grid density did not affect nominal zone size."
	)
	var direction := Vector3(0.7, 0.2, -0.4)
	var moon_address: Dictionary = moon.create_partition_address(
		direction * moon.body_radius_m,
		"main",
		"persistent",
		"moon"
	)
	var earth_address: Dictionary = earth.create_partition_address(
		direction * earth.body_radius_m,
		"main",
		"persistent",
		"earth"
	)
	_assert(
		String(moon_address.get("chunk_id", "")) != String(earth_address.get("chunk_id", "")),
		"Earth and Moon grids generated the same canonical chunk ID."
	)
	_assert(
		moon.contains_cell(moon_address),
		"Moon grid rejected its own partition address."
	)
	_assert(
		not moon.contains_cell(earth_address),
		"Moon grid accepted an Earth grid address with incompatible density."
	)


func _test_surface_offsets_across_face_boundary() -> void:
	var grid = _make_grid("body/moon/fixed", 1_737_400.0, 48, 32)
	var near_edge := Vector3(1.0, 0.0, 0.999999).normalized()
	var before: Dictionary = grid.direction_to_cell(near_edge)
	var moved: Vector3 = grid.offset_direction(near_edge, -10_000.0, 0.0)
	var after: Dictionary = grid.direction_to_cell(moved)
	_assert(not before.is_empty() and not after.is_empty(), "Face-edge offset produced no cell.")
	_assert(
		int(after.get("face", -1)) >= 0 and int(after.get("face", -1)) < 6,
		"Face-edge offset produced an invalid face."
	)
	var measured: float = grid.angular_distance_m(near_edge, moved)
	_assert(
		absf(measured - 10_000.0) < 0.001,
		"Surface offset distance drifted excessively: %.3f m." % measured
	)


func _test_topological_neighbors_across_all_seams() -> void:
	var grid = _make_grid("body/moon/fixed", 1_737_400.0, 48, 32)
	var edge_chunks: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(0, grid.chunks_per_zone - 1),
		Vector2i(grid.chunks_per_zone - 1, 0),
		Vector2i(grid.chunks_per_zone - 1, grid.chunks_per_zone - 1),
	]
	var edge_zones: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(0, grid.zones_per_face - 1),
		Vector2i(grid.zones_per_face - 1, 0),
		Vector2i(grid.zones_per_face - 1, grid.zones_per_face - 1),
	]
	for face in range(6):
		for zone_coordinates in edge_zones:
			var zone_neighbors: Dictionary = {}
			for offset_y in range(-1, 2):
				for offset_x in range(-1, 2):
					var neighbor: Dictionary = grid.offset_zone_cell(
						face,
						zone_coordinates.x,
						zone_coordinates.y,
						offset_x,
						offset_y
					)
					_assert(not neighbor.is_empty(), "Zone seam neighbor is empty.")
					if neighbor.is_empty():
						continue
					var key: String = "%d/%d/%d" % [
						int(neighbor["face"]),
						int(neighbor["zone_x"]),
						int(neighbor["zone_y"]),
					]
					zone_neighbors[key] = true
			_assert(
				zone_neighbors.size() >= 8,
				"Zone seam neighborhood collapsed on face %d zone %d,%d." % [
					face,
					zone_coordinates.x,
					zone_coordinates.y,
				]
			)
			for chunk_coordinates in edge_chunks:
				var chunk_neighbors: Dictionary = {}
				for offset_y in range(-1, 2):
					for offset_x in range(-1, 2):
						var neighbor: Dictionary = grid.offset_chunk_cell(
							face,
							zone_coordinates.x,
							zone_coordinates.y,
							chunk_coordinates.x,
							chunk_coordinates.y,
							offset_x,
							offset_y
						)
						_assert(not neighbor.is_empty(), "Chunk seam neighbor is empty.")
						if neighbor.is_empty():
							continue
						var key: String = "%d/%d/%d/%d/%d" % [
							int(neighbor["face"]),
							int(neighbor["zone_x"]),
							int(neighbor["zone_y"]),
							int(neighbor["chunk_x"]),
							int(neighbor["chunk_y"]),
						]
						chunk_neighbors[key] = true
				_assert(
					chunk_neighbors.size() >= 8,
					"Chunk seam neighborhood collapsed on face %d zone %d,%d chunk %d,%d." % [
						face,
						zone_coordinates.x,
						zone_coordinates.y,
						chunk_coordinates.x,
						chunk_coordinates.y,
					]
				)


func _test_partition_address_creation() -> void:
	var grid = _make_grid("body/moon/fixed", 1_737_400.0, 48, 32)
	var address: Dictionary = grid.create_partition_address(
		Vector3(1_737_400.0, 0.0, 0.0),
		"main",
		"scenario-a",
		"moon"
	)
	_assert(PartitionAddressScript.is_valid(address), "Grid produced invalid PartitionAddress v2.")
	_assert(
		int(address.get("partition_scheme_revision", 0)) == grid.scheme_revision,
		"Grid scheme revision was not propagated into the partition address."
	)
	_assert(
		String(address.get("chunk_id", "")).begins_with(
			"universe/main/instance/scenario-a/space/moon/"
		),
		"Grid partition address lost universe/instance/space namespace."
	)


func _make_grid(
	frame_id: String,
	radius_m: float,
	zones_per_face: int,
	chunks_per_zone: int
):
	var grid = CubeSphereGridScript.new()
	var configured: bool = grid.setup({
		"scheme_id": "cube_sphere",
		"scheme_revision": 1,
		"body_frame_id": frame_id,
		"body_radius_m": radius_m,
		"zones_per_face": zones_per_face,
		"chunks_per_zone": chunks_per_zone,
	})
	_assert(configured, "Failed to configure cube-sphere grid for %s." % frame_id)
	return grid


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
