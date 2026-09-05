extends SceneTree

## WP-VIS1 GENERIC_LAB_SCAFFOLD headless self-check.
##
## Validates the fixture registry (structure, uniqueness, required ids,
## orientation coverage incl. down-facing fixtures) and instantiates the lab
## scene once to prove the scaffold builds without assets. Exit code 0 on
## success, 1 on any problem.

const LabScene := preload("res://scenes/labs/world_packs/surface_material_lab.tscn")
const Fixtures := preload("res://scripts/world_packs/labs/surface_material_lab_fixtures.gd")


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

	_lab = LabScene.instantiate()
	root.add_child(_lab)


# Node _ready is deferred until the first frame inside a SceneTree script, so
# the scene build is inspected on the first _process tick.
func _process(_delta: float) -> bool:
	var problems := PackedStringArray(_problems)
	problems.append_array(Fixtures.validate_registry())
	var markers := 0
	for child in _lab.get_children():
		if child is Node3D and String(child.name).begins_with("Marker_"):
			markers += 1
	if markers != Fixtures.FIXTURES.size():
		problems.append(
			"expected %d scaffold markers, scene built %d"
			% [Fixtures.FIXTURES.size(), markers]
		)

	if problems.is_empty():
		print("SURFACE_MATERIAL_LAB_SELF_CHECK=PASS markers=%d" % markers)
		quit(0)
	else:
		for problem in problems:
			print("SURFACE_MATERIAL_LAB_PROBLEM=%s" % problem)
		print("SURFACE_MATERIAL_LAB_SELF_CHECK=FAIL")
		quit(1)
	return true
