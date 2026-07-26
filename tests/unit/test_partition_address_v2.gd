extends SceneTree

const PartitionAddressScript = preload(
	"res://scripts/simulation/partition/partition_address.gd"
)

var failures: Array[String] = []


func _init() -> void:
	var moon: Dictionary = PartitionAddressScript.create_cube_sphere(
		4, 17, 9, 3, 28, "main", "moon"
	)
	var earth: Dictionary = PartitionAddressScript.create_cube_sphere(
		4, 17, 9, 3, 28, "main", "earth"
	)
	_assert(
		String(moon["chunk_id"]) != String(earth["chunk_id"]),
		"Earth and Moon partition IDs collided."
	)
	_assert(
		String(moon["chunk_id"]).begins_with("universe/main/instance/persistent/space/moon/"),
		"Moon partition ID is not namespaced."
	)
	var scenario_moon: Dictionary = PartitionAddressScript.create_cube_sphere(
		4, 17, 9, 3, 28, "main", "moon", "cube_sphere_v1", "scenario-a"
	)
	_assert(
		String(scenario_moon["chunk_id"]) != String(moon["chunk_id"]),
		"Persistent and scenario instance partition IDs collided."
	)
	var previous_v2: Dictionary = PartitionAddressScript.parse(
		"universe/main/space/moon/partition/cube_sphere_v1/zone/f4/17/09/chunk/03/28",
		{"instance_id": "persistent"}
	)
	_assert(
		String(previous_v2.get("chunk_id", "")) == String(moon["chunk_id"]),
		"Partition address without instance namespace was not migrated."
	)
	var parsed: Dictionary = PartitionAddressScript.parse(String(moon["chunk_id"]))
	_assert(parsed == moon, "Canonical partition address roundtrip failed.")
	_assert(
		int(parsed.get("partition_scheme_revision", 0)) == 1,
		"Partition scheme revision was not restored from the canonical scheme ID."
	)
	var legacy: Dictionary = PartitionAddressScript.parse(
		"zone/f4/17/09/chunk/03/28",
		{"universe_id": "main", "space_id": "moon"}
	)
	_assert(
		String(legacy.get("chunk_id", "")) == String(moon["chunk_id"]),
		"Legacy partition ID migration failed."
	)
	var file_components: PackedStringArray = PartitionAddressScript.file_components(moon)
	_assert(
		file_components.size() == 7
		and file_components[2] == "moon"
		and file_components[3] == "cube_sphere_r1",
		"Partition file components are incomplete or not revisioned."
	)
	var revision_two: Dictionary = PartitionAddressScript.create_cube_sphere(
		4, 17, 9, 3, 28, "main", "moon", "cube_sphere_v2", "persistent", 2
	)
	var parsed_revision_two: Dictionary = PartitionAddressScript.parse(
		String(revision_two["chunk_id"])
	)
	_assert(
		int(parsed_revision_two.get("partition_scheme_revision", 0)) == 2,
		"Partition scheme revision was not inferred from cube_sphere_v2."
	)
	_assert(
		PartitionAddressScript.parse(
			"universe/main/instance/persistent/space/moon/partition/cube_sphere_v1/zone/fx/17/09"
		).is_empty(),
		"Malformed partition face was silently accepted."
	)
	_assert(
		PartitionAddressScript.parse("zone/f4/-1/09").is_empty(),
		"Negative legacy partition coordinate was silently accepted."
	)

	_assert(
		PartitionAddressScript.create_cube_sphere(
			4, 17, 9, 3, 28, "main/other", "moon"
		).is_empty(),
		"Partition address accepted a namespace containing a path separator."
	)
	var normalized_case: Dictionary = PartitionAddressScript.create_cube_sphere(
		4, 17, 9, 3, 28, "MAIN", "MOON", "CUBE_SPHERE", "PERSISTENT"
	)
	_assert(
		String(normalized_case.get("chunk_id", "")) == String(moon["chunk_id"]),
		"Partition namespace case was not canonicalized."
	)

	if failures.is_empty():
		print("Partition address v2 tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Partition address v2 tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
