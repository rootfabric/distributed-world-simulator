extends SceneTree

const AggregateScript = preload("res://scripts/construction/domain/construct_aggregate.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const EditorScript = preload("res://scripts/labs/fabric_construct0/construct0_editor.gd")

var _assertions := 0
var _failures: Array[String] = []

func _init() -> void:
	_test_generic_pose_mutation()
	_test_editor_workflow()
	_finish()

func _test_generic_pose_mutation() -> void:
	var aggregate = AggregateScript.new()
	_check(bool(aggregate.setup("construct/construct0/pose-test", "item/construct0/pose-test/root").get("success", false)), "pose aggregate setup")
	var part := PartScript.create(
		"part/construct0/pose-test/block",
		"item/construct0/pose-test/block",
		"BLOCK",
		"structure",
		10.0,
		[0.0, 0.5, 0.0],
		{
			"geometry": {"bounding_box_m": [0.7, 0.7, 0.7]},
			"local_rotation_quaternion": [0.0, 0.0, 0.0, 1.0],
		}
	)
	var added := aggregate.add_part("construct0/pose-test/add", 0, part)
	_check(bool(added.get("success", false)), "pose part add")
	var before := aggregate.export_snapshot()
	var q := Quaternion(Vector3.UP, deg_to_rad(30.0))
	var pose := aggregate.update_part_pose(
		"construct0/pose-test/pose",
		aggregate.state_revision,
		"part/construct0/pose-test/block",
		[1.25, 0.75, -0.5],
		[q.x, q.y, q.z, q.w]
	)
	_check(bool(pose.get("success", false)), "canonical pose mutation succeeds")
	var after := aggregate.export_snapshot()
	_check(int(after["state_revision"]) == int(before["state_revision"]) + 1, "pose mutation advances canonical revision")
	_check(String(after["checksum"]) != String(before["checksum"]), "pose mutation changes canonical checksum")
	var moved: Dictionary = after["parts"][0]
	_check(Array(moved["local_position_m"]) == [1.25, 0.75, -0.5], "canonical local position updated")
	_check(Array(moved["metadata"]["local_rotation_quaternion"]).size() == 4, "canonical rotation persisted in metadata")

	var replay := aggregate.update_part_pose(
		"construct0/pose-test/pose",
		1,
		"part/construct0/pose-test/block",
		[1.25, 0.75, -0.5],
		[q.x, q.y, q.z, q.w]
	)
	_check(bool(replay.get("success", false)) and bool(replay.get("replay", false)), "exact pose mutation replays")
	_check(int(aggregate.state_revision) == int(after["state_revision"]), "exact replay does not advance revision")

	var conflict := aggregate.update_part_pose(
		"construct0/pose-test/pose",
		aggregate.state_revision,
		"part/construct0/pose-test/block",
		[2.0, 0.75, -0.5],
		[q.x, q.y, q.z, q.w]
	)
	_check(not bool(conflict.get("success", false)) and String(conflict.get("error_code", "")) == "OPERATION_REPLAY_CONFLICT", "pose operation conflict rejected")

	var stale := aggregate.update_part_pose(
		"construct0/pose-test/stale",
		1,
		"part/construct0/pose-test/block",
		[1.5, 0.75, -0.5],
		[q.x, q.y, q.z, q.w]
	)
	_check(not bool(stale.get("success", false)) and String(stale.get("error_code", "")) == "STALE_CONSTRUCT_REVISION", "stale pose edit rejected")

func _test_editor_workflow() -> void:
	var editor = EditorScript.new()
	var ready := editor.setup()
	_check(bool(ready.get("success", false)), "editor setup")

	var block := editor.add_part("BLOCK", Vector3(0.0, 0.5, 0.0))
	var plate := editor.add_part("PLATE", Vector3(1.0, 0.5, 0.0))
	var beam := editor.add_part("BEAM", Vector3(2.0, 0.5, 0.0))
	_check(bool(block.get("success", false)), "editor adds BLOCK")
	_check(bool(plate.get("success", false)), "editor adds PLATE")
	_check(bool(beam.get("success", false)), "editor adds BEAM")

	var ids := editor.get_part_ids()
	_check(ids.size() == 3, "editor canonical part count")
	var snapshot_before_move := editor.get_snapshot()
	var beam_id := String(beam.get("part_id", ""))
	var moved := editor.move_part(beam_id, Vector3(0.25, 0.25, -0.5))
	_check(bool(moved.get("success", false)), "editor moves selected canonical part")
	var snapshot_after_move := editor.get_snapshot()
	_check(int(snapshot_after_move["state_revision"]) == int(snapshot_before_move["state_revision"]) + 1, "editor move advances revision")
	_check(String(snapshot_after_move["checksum"]) != String(snapshot_before_move["checksum"]), "editor move changes checksum")

	var rotated := editor.rotate_part_y(beam_id, deg_to_rad(15.0))
	_check(bool(rotated.get("success", false)), "editor rotates selected canonical part")
	var snapshot_after_rotate := editor.get_snapshot()
	_check(int(snapshot_after_rotate["state_revision"]) == int(snapshot_after_move["state_revision"]) + 1, "editor rotate advances revision")

	var bond := editor.add_rigid_bond(String(block["part_id"]), String(beam["part_id"]))
	_check(bool(bond.get("success", false)), "editor creates rigid canonical bond")
	_check(editor.get_bond_ids(false).size() == 1, "rigid bond visible as intact")

	var compiled := editor.compile_runtime_descriptor()
	_check(bool(compiled.get("success", false)), "edited construction compiles runtime projection")
	if bool(compiled.get("success", false)):
		_check(Array(compiled["descriptor"]["part_descriptors"]).size() == 3, "runtime projection includes edited parts")

	var broken := editor.break_bond(String(bond.get("bond_id", "")))
	_check(bool(broken.get("success", false)), "editor breaks canonical bond")
	var final_snapshot := editor.get_snapshot()
	_check(String(final_snapshot["build_state"]) == "DAMAGED", "bond break marks construct DAMAGED")
	_check(editor.get_bond_ids(false).is_empty(), "broken bond no longer intact")
	_check(editor.get_bond_ids(true).size() == 1, "broken bond remains in canonical history")

	var unsupported := editor.add_part("MOTOR", Vector3.ZERO)
	_check(not bool(unsupported.get("success", false)) and String(unsupported.get("error_code", "")) == "CONSTRUCT0_EDITOR_UNSUPPORTED_PART_KIND", "device-specific part shortcut rejected")

func _finish() -> void:
	if _failures.is_empty():
		print("FABRIC CONSTRUCT0 C0.3 Acceptance: PASS (%d assertions)" % _assertions)
		quit(0)
		return
	for failure in _failures:
		push_error("CONSTRUCT0 C0.3: %s" % failure)
	print("FABRIC CONSTRUCT0 C0.3 Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _assertions])
	quit(1)

func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(label)
