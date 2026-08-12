extends SceneTree

const HandRigType = preload("res://scripts/characters/presentation/articulated_first_person_hand_rig.gd")
const PoseCatalogType = preload("res://scripts/characters/presentation/first_person_hand_pose_catalog.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var rig = HandRigType.new()
	root.add_child(rig)
	var setup_result: Dictionary = rig.setup("right", 19)
	_assert(bool(setup_result.get("success", false)), "S3 articulated hand rig setup failed")
	var setup_report: Dictionary = rig.create_report()
	_assert(bool(setup_report.get("configured", false)), "S3 articulated hand rig not configured")
	_assert(bool(setup_report.get("skeleton_present", false)), "S3 articulated hand rig has no Skeleton3D")
	_assert(int(setup_report.get("bone_count", 0)) == 17, "S3 articulated hand bone count mismatch")
	_assert(int(setup_report.get("finger_chains", 0)) == 5, "S3 articulated hand does not expose five finger chains")
	_assert(int(setup_report.get("visual_segments", 0)) == 16, "S3 articulated hand visual segment count mismatch")
	_assert(int(setup_report.get("viewmodel_layer_index", -1)) == 19, "S3 articulated hand viewmodel layer mismatch")
	_assert(rig.skeleton is Skeleton3D, "S3 rig skeleton node type mismatch")
	_assert(rig.skeleton.find_bone("IndexProximal") >= 0, "S3 index proximal bone missing")
	_assert(rig.skeleton.find_bone("ThumbDistal") >= 0, "S3 thumb distal bone missing")

	var all_layered := true
	for visual in rig._visual_segments:
		if visual == null or not visual.get_layer_mask_value(19) or visual.get_layer_mask_value(1):
			all_layered = false
			break
	_assert(all_layered, "S3 articulated hand visual leaked outside viewmodel layer")

	var poses = PoseCatalogType.new()
	var open_result: Dictionary = rig.apply_pose(poses.get_open_pose())
	_assert(bool(open_result.get("success", false)), "S3 open pose apply failed")
	rig._process(0.2)
	_assert(String(rig.create_report().get("settled_pose_id", "")) == "open", "S3 open pose did not settle")

	var flashlight_pose: Dictionary = poses.resolve(
		{"profile_id": "flashlight_forward"},
		{"profile_id": "flashlight"}
	)
	var flashlight_result: Dictionary = rig.apply_pose(flashlight_pose)
	_assert(bool(flashlight_result.get("success", false)), "S3 flashlight hand pose apply failed")
	rig._process(0.2)
	var posed_report: Dictionary = rig.create_report()
	_assert(String(posed_report.get("current_pose_id", "")) == "flashlight_wrap", "S3 rig current pose id mismatch")
	_assert(String(posed_report.get("settled_pose_id", "")) == "flashlight_wrap", "S3 flashlight pose did not settle")
	_assert(not bool(posed_report.get("transitioning", true)), "S3 hand rig kept processing after transition completed")
	_assert(int(posed_report.get("pose_apply_count", 0)) >= 2, "S3 hand rig pose apply counter mismatch")

	var index_bone := rig.skeleton.find_bone("IndexProximal")
	if index_bone >= 0:
		var index_rotation: Quaternion = rig.skeleton.get_bone_pose_rotation(index_bone)
		_assert(absf(index_rotation.w) < 0.999, "S3 flashlight pose left index proximal bone effectively unrotated")

	_assert(bool(posed_report.get("presentation_only", false)), "S3 hand rig is not presentation-only")
	_assert(not bool(posed_report.get("owns_item_state", true)), "S3 hand rig claims item ownership")
	_assert(not bool(posed_report.get("owns_network_state", true)), "S3 hand rig claims network ownership")
	_assert(not bool(posed_report.get("owns_gameplay_transform", true)), "S3 hand rig claims gameplay transform ownership")

	root.queue_free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE R2 S3 articulated hand rig: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 S3 articulated hand rig: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
