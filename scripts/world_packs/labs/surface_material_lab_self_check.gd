extends SceneTree

## WP-VIS1 headless self-check (scaffold + enabled surface milestones).
##
## Validates the fixture registry (structure, uniqueness, required ids,
## orientation coverage incl. down-facing fixtures), instantiates the lab
## scene once, and verifies that every fixture whose milestone is enabled in
## the lab script became a real oriented surface while the rest stayed
## markers. Exit code 0 on success, 1 on any problem.

const LabScene := preload("res://scenes/labs/world_packs/surface_material_lab.tscn")
const Fixtures := preload("res://scripts/world_packs/labs/surface_material_lab_fixtures.gd")

## Expected orientation class per fixture id, derived from the registry
## rotation. Kept in sync with surface_material_lab_fixtures.gd; the check
## compares the computed world normal against these classes so a silently
## broken rotation fails the self-check.
const EXPECTED_ORIENTATION := {
	"horizontal_plane": "up",
	"slope_45": "up",
	"vertical_wall": "side",
	"overhang": "down",
	"inverted_ceiling": "down",
	"sphere_fixture": "side",
}

## Fixtures that must exist as real surfaces (Fixture_*) at this milestone.
const EXPECTED_SURFACES := [
	"horizontal_plane",
	"slope_45",
	"vertical_wall",
]


func orientation_class(world_normal: Vector3) -> String:
	if world_normal.y > 0.7:
		return "up"
	if world_normal.y < -0.7:
		return "down"
	return "side"


var _lab: Node
var _problems := PackedStringArray()


func _initialize() -> void:
	for fixture in Fixtures.FIXTURES:
		var fixture_id := String(fixture["id"])
		var world_normal := Fixtures.world_surface_normal(fixture)
		print(
			"SURFACE_MATERIAL_LAB_FIXTURE=%s world_normal=(%.3f, %.3f, %.3f)"
			% [fixture_id, world_normal.x, world_normal.y, world_normal.z]
		)
		if world_normal == Vector3.ZERO:
			_problems.append("fixture %s world normal is zero" % fixture_id)
		var expected := String(EXPECTED_ORIENTATION.get(fixture_id, ""))
		if not expected.is_empty() and orientation_class(world_normal) != expected:
			_problems.append(
				"fixture %s orientation class %s != expected %s"
				% [fixture_id, orientation_class(world_normal), expected]
			)

	_lab = LabScene.instantiate()
	root.add_child(_lab)


# Node _ready is deferred until the first frame inside a SceneTree script, so
# the scene build is inspected on the first _process tick.
func _process(_delta: float) -> bool:
	var problems := PackedStringArray(_problems)
	problems.append_array(Fixtures.validate_registry())

	var surfaces := 0
	var markers := 0
	var surface_ids := PackedStringArray()
	for child in _lab.get_children():
		if child is Node3D:
			if String(child.name).begins_with("Marker_"):
				markers += 1
			elif String(child.name).begins_with("Fixture_"):
				surfaces += 1
				surface_ids.append(String(child.name).trim_prefix("Fixture_"))

	if surfaces != EXPECTED_SURFACES.size():
		problems.append(
			"expected %d real surfaces, scene built %d"
			% [EXPECTED_SURFACES.size(), surfaces]
		)
	for expected_id in EXPECTED_SURFACES:
		if not surface_ids.has(expected_id):
			problems.append("missing real surface for fixture %s" % expected_id)
	if surfaces + markers != Fixtures.FIXTURES.size():
		problems.append(
			"expected %d total lab nodes, scene built %d"
			% [Fixtures.FIXTURES.size(), surfaces + markers]
		)

	# Every real surface must carry the fixture-local normal indicator and
	# report the descriptor world normal through the lab API.
	var lab := _lab as Node
	for expected_id in EXPECTED_SURFACES:
		var fixture_root := lab.get_node_or_null("Fixture_%s" % expected_id) as Node3D
		if fixture_root == null:
			continue
		if fixture_root.get_node_or_null("LocalNormal") == null:
			problems.append("surface %s lacks local normal indicator" % expected_id)
		var reported: Vector3 = lab.report_world_normal(expected_id)
		var declared: Vector3 = Fixtures.world_surface_normal(
			Fixtures.descriptor(expected_id)
		)
		if not reported.is_equal_approx(declared):
			problems.append(
				"surface %s API normal (%s) != registry normal (%s)"
				% [expected_id, reported, declared]
			)

	if problems.is_empty():
		print(
			"SURFACE_MATERIAL_LAB_SELF_CHECK=PASS surfaces=%d markers=%d"
			% [surfaces, markers]
		)
		quit(0)
	else:
		for problem in problems:
			print("SURFACE_MATERIAL_LAB_PROBLEM=%s" % problem)
		print("SURFACE_MATERIAL_LAB_SELF_CHECK=FAIL")
		quit(1)
	return true
