extends SceneTree

const SupportType = preload("res://scripts/characters/presentation/third_person_secondary_hand_support.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_native_two_bone_ik()
	_test_fallback_procedural_arm()
	_finish()


func _test_native_two_bone_ik() -> void:
	var root := Node3D.new()
	root.name = "NativeRoot"
	get_root().add_child(root)
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	root.add_child(skeleton)
	skeleton.add_bone("mixamorig_LeftUpperArm")
	skeleton.add_bone("mixamorig_LeftForeArm")
	skeleton.add_bone("mixamorig_LeftHand")
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_parent(2, 1)
	skeleton.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	skeleton.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.35, 0.0)))
	skeleton.set_bone_rest(2, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.35, 0.0)))

	var support = SupportType.new()
	root.add_child(support)
	var setup_result: Dictionary = support.setup(root, skeleton, 20)
	_assert(bool(setup_result.get("success", false)), "S5 native secondary-hand setup failed")
	var setup_report: Dictionary = support.create_report()
	_assert(String(setup_report.get("mode", "")) == "NATIVE_TWO_BONE_IK", "S5 native support did not select TwoBoneIK3D")
	_assert(String(setup_report.get("matched_root_bone", "")) == "mixamorig_LeftUpperArm", "S5 native root bone mismatch")
	_assert(String(setup_report.get("matched_middle_bone", "")) == "mixamorig_LeftForeArm", "S5 native middle bone mismatch")
	_assert(String(setup_report.get("matched_end_bone", "")) == "mixamorig_LeftHand", "S5 native end bone mismatch")
	_assert(bool(setup_report.get("native_ik_present", false)), "S5 native TwoBoneIK3D node missing")

	var target := Node3D.new()
	target.name = "SecondaryTarget"
	root.add_child(target)
	target.position = Vector3(-0.25, -0.45, -0.18)
	var active_result: Dictionary = support.activate(target, "item/test/two-hand", {"profile_id": "two_hand_test"})
	_assert(bool(active_result.get("success", false)), "S5 native support activation failed")
	var active_report: Dictionary = support.create_report()
	_assert(bool(active_report.get("active", false)), "S5 native support did not become active")
	_assert(String(active_report.get("item_id", "")) == "item/test/two-hand", "S5 native active item mismatch")
	_assert(support._ik != null and support._ik.active, "S5 native TwoBoneIK3D did not activate")
	_assert(support._ik.get_setting_count() == 1, "S5 native TwoBoneIK3D setting count mismatch")
	_assert(not bool(active_report.get("collision_body_created", true)), "S5 native support unexpectedly creates collision")

	var clear_result: Dictionary = support.deactivate("TEST_CLEAR")
	_assert(bool(clear_result.get("success", false)), "S5 native support deactivate failed")
	_assert(not bool(support.create_report().get("active", true)), "S5 native support remained active after clear")
	_assert(not support._ik.active, "S5 native TwoBoneIK3D remained active after clear")
	root.queue_free()


func _test_fallback_procedural_arm() -> void:
	var root := Node3D.new()
	root.name = "FallbackRoot"
	get_root().add_child(root)
	var yaw_root := Node3D.new()
	yaw_root.name = "AvatarYawRoot"
	root.add_child(yaw_root)
	var model := Node3D.new()
	model.name = "FallbackHumanoid"
	yaw_root.add_child(model)
	var left_arm := Node3D.new()
	left_arm.name = "LeftArm"
	model.add_child(left_arm)

	var support = SupportType.new()
	root.add_child(support)
	var setup_result: Dictionary = support.setup(root, null, 20)
	_assert(bool(setup_result.get("success", false)), "S5 fallback secondary-hand setup failed")
	var setup_report: Dictionary = support.create_report()
	_assert(String(setup_report.get("mode", "")) == "FALLBACK_PROCEDURAL_ARM", "S5 fallback support mode mismatch")
	_assert(bool(setup_report.get("fallback_original_arm_present", false)), "S5 fallback original arm was not detected")

	var target := Node3D.new()
	target.name = "FallbackTarget"
	model.add_child(target)
	target.position = Vector3(-0.05, 1.25, -0.35)
	var active_result: Dictionary = support.activate(target, "item/test/fallback", {"profile_id": "fallback_two_hand"})
	_assert(bool(active_result.get("success", false)), "S5 fallback support activation failed")
	support._process(0.016)
	var active_report: Dictionary = support.create_report()
	_assert(bool(active_report.get("active", false)), "S5 fallback support did not become active")
	_assert(not left_arm.visible, "S5 fallback support did not hide original swinging arm")
	_assert(int(active_report.get("fallback_updates", 0)) > 0, "S5 fallback arm was not solved")
	_assert(support._fallback_upper != null and support._fallback_upper.visible, "S5 fallback upper arm proxy missing")
	_assert(support._fallback_lower != null and support._fallback_lower.visible, "S5 fallback lower arm proxy missing")
	_assert(support._fallback_hand != null and support._fallback_hand.visible, "S5 fallback hand proxy missing")
	_assert(support._fallback_upper.get_layer_mask_value(20), "S5 fallback upper arm not on world render layer")
	_assert(not support._fallback_upper.get_layer_mask_value(1), "S5 fallback upper arm leaked onto default render layer")

	support.deactivate("TEST_CLEAR")
	_assert(left_arm.visible, "S5 fallback original arm visibility was not restored")
	_assert(not support._fallback_upper.visible and not support._fallback_lower.visible and not support._fallback_hand.visible, "S5 fallback support proxies remained visible after clear")
	var final_report: Dictionary = support.create_report()
	_assert(bool(final_report.get("presentation_only", false)), "S5 support is not presentation-only")
	_assert(not bool(final_report.get("owns_item_state", true)), "S5 support claims item ownership")
	_assert(not bool(final_report.get("owns_network_state", true)), "S5 support claims network ownership")
	_assert(not bool(final_report.get("owns_gameplay_transform", true)), "S5 support claims gameplay transform ownership")
	root.queue_free()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE R2 S5 secondary-hand support: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 S5 secondary-hand support: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
