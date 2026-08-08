extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_character_lab.tscn")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab = LabScene.instantiate()
	root.add_child(lab)
	await process_frame
	await physics_frame

	_assert(lab.player is CharacterBody3D, "CharacterBody3D missing")
	_assert(lab.avatar != null, "Avatar presenter missing")
	_assert(lab.first_person_adapter != null, "First-person adapter missing")
	_assert(lab.first_person_camera is Camera3D, "First-person camera missing")
	_assert(lab.third_person_camera is Camera3D, "Third-person camera missing")
	_assert(not lab.first_person_mode, "Lab must start in third person for A/B comparison")
	_assert(lab.third_person_camera.current, "Third-person camera is not current initially")
	_assert(lab.camera == lab.third_person_camera, "Current camera alias is not third-person initially")

	lab.set_first_person_mode(true)
	await process_frame
	var fp_report: Dictionary = lab.first_person_adapter.create_report()
	_assert(lab.first_person_mode, "First-person mode did not enable")
	_assert(lab.first_person_camera.current, "First-person camera did not become current")
	_assert(not lab.third_person_camera.current, "Third-person camera stayed current")
	_assert(lab.camera == lab.first_person_camera, "Current camera alias was not updated")
	_assert(lab.avatar.visible, "Full avatar was hidden instead of using a local head mask")
	_assert(bool(fp_report.get("mask_applied", false)), "First-person head mask was not applied")
	_assert(not _has_skeleton_ancestor(lab.first_person_camera), "Camera is parented to an animated Skeleton3D")
	_assert(is_equal_approx(lab.camera_yaw.position.y, 1.62), "First-person camera anchor is not at stable eye height")
	_assert(_count_nodes_of_type(lab.first_person_adapter, CharacterBody3D) == 0, "First-person adapter owns gameplay body")
	_assert(_count_nodes_of_type(lab.first_person_adapter, CollisionShape3D) == 0, "First-person adapter owns collision")

	var avatar_report: Dictionary = lab.avatar.create_report()
	_assert(not bool(avatar_report.get("root_motion_applied", true)), "First-person lab enables root motion")

	var require_external := OS.get_environment("PLANET_SIMULATOR_REQUIRE_QUATERNIUS_ASSETS") == "1"
	if require_external:
		_assert(String(avatar_report.get("asset_mode", "")) in ["QUATERNIUS_RETARGET", "QUATERNIUS_EMBEDDED"], "Strict CH5 lab fell back from Quaternius")
		_assert(String(fp_report.get("mask_mode", "")) == "BONE_SCALE", "Real Quaternius head did not resolve to bone-scale mask")
		_assert(bool(fp_report.get("head_bone_present", false)), "Real Quaternius head bone was not found")

	lab.set_first_person_mode(false)
	await process_frame
	fp_report = lab.first_person_adapter.create_report()
	_assert(not bool(fp_report.get("mask_applied", true)), "Head mask stayed active in third person")
	_assert(lab.third_person_camera.current, "Third-person camera did not restore")

	lab.queue_free()
	_finish()


func _has_skeleton_ancestor(node: Node) -> bool:
	var current := node.get_parent()
	while current != null:
		if current is Skeleton3D:
			return true
		current = current.get_parent()
	return false


func _count_nodes_of_type(node: Node, type_value: Variant) -> int:
	var count := 0
	for child in node.get_children():
		if is_instance_of(child, type_value):
			count += 1
		count += _count_nodes_of_type(child, type_value)
	return count


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH5 full-body first-person lab: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH5 full-body first-person lab: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
