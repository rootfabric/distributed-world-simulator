extends SceneTree

const PosedFirstPersonType = preload("res://scripts/characters/presentation/posed_catalogued_first_person_embodiment.gd")
const ViewmodelCatalogType = preload("res://scripts/characters/presentation/item_viewmodel_catalog.gd")
const GripCatalogType = preload("res://scripts/characters/presentation/held_item_grip_profile_catalog.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var posed = PosedFirstPersonType.new()
	root.add_child(posed)

	posed.left_hand_root = Node3D.new()
	posed.left_hand_root.name = "LeftHandViewmodel"
	posed.add_child(posed.left_hand_root)
	posed.left_held_root = Node3D.new()
	posed.left_held_root.name = "LeftGrip"
	posed.left_hand_root.add_child(posed.left_held_root)
	posed.right_hand_root = Node3D.new()
	posed.right_hand_root.name = "RightHandViewmodel"
	posed.add_child(posed.right_hand_root)
	posed.right_held_root = Node3D.new()
	posed.right_held_root.name = "RightGrip"
	posed.right_hand_root.add_child(posed.right_held_root)

	var left_setup: Dictionary = posed._install_hand_rig("left", posed.left_hand_root, 19)
	var right_setup: Dictionary = posed._install_hand_rig("right", posed.right_hand_root, 19)
	_assert(bool(left_setup.get("success", false)), "S3 posed viewmodel left rig setup failed")
	_assert(bool(right_setup.get("success", false)), "S3 posed viewmodel right rig setup failed")

	var visuals = ViewmodelCatalogType.new()
	var grips = GripCatalogType.new()
	var beacon_descriptor: Dictionary = visuals.resolve(
		"survey_beacon",
		["signal"],
		{},
		"",
		Color(1.0, 0.3, 0.05, 1.0)
	)
	var beacon_grip: Dictionary = grips.resolve("survey_beacon", beacon_descriptor, ["signal"], {})
	var apply_result: Dictionary = posed.set_catalogued_hand_item(
		"right",
		"item/beacon",
		"Survey Beacon",
		Color(1.0, 0.3, 0.05, 1.0),
		beacon_descriptor,
		beacon_grip
	)
	_assert(bool(apply_result.get("success", false)), "S3 posed viewmodel item apply failed")
	_assert(String(apply_result.get("details", {}).get("hand_pose_id", "")) == "beacon_pinch", "S3 beacon did not drive beacon_pinch hand pose")
	_assert(posed._authoritative_proxy_by_hand.get("right") is MeshInstance3D, "S3 posed viewmodel lost catalogued item proxy")

	var right_rig = posed._hand_rig_by_hand.get("right")
	_assert(right_rig != null, "S3 posed viewmodel right articulated rig missing")
	if right_rig != null:
		right_rig._process(0.2)
		var right_report: Dictionary = right_rig.create_report()
		_assert(String(right_report.get("current_pose_id", "")) == "beacon_pinch", "S3 right hand current pose mismatch")
		_assert(String(right_report.get("settled_pose_id", "")) == "beacon_pinch", "S3 right hand pose did not settle")

	var clear_result: Dictionary = posed.clear_authoritative_hand_item("right")
	_assert(bool(clear_result.get("success", false)), "S3 posed viewmodel clear failed")
	_assert(posed._authoritative_proxy_by_hand.get("right") == null, "S3 posed viewmodel retained item proxy after clear")
	if right_rig != null:
		right_rig._process(0.2)
		_assert(String(right_rig.create_report().get("current_pose_id", "")) == "open", "S3 empty hand did not return to open pose")

	var report: Dictionary = posed.get_hand_pose_report()
	_assert(bool(report.get("articulated_skeleton", false)), "S3 posed viewmodel report lost articulated skeleton flag")
	_assert(int(report.get("pose_apply_count", 0)) >= 2, "S3 posed viewmodel pose apply counter did not advance")
	_assert(bool(report.get("procedural_segment_visuals", false)), "S3 report does not disclose procedural segment visuals")
	_assert(not bool(report.get("owns_item_state", true)), "S3 posed viewmodel claims item ownership")
	_assert(not bool(report.get("owns_network_state", true)), "S3 posed viewmodel claims network ownership")
	_assert(not bool(report.get("owns_gameplay_transform", true)), "S3 posed viewmodel claims gameplay transform ownership")

	root.queue_free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE R2 S3 posed viewmodel: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 S3 posed viewmodel: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
