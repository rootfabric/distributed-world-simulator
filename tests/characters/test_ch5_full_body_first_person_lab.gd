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
	_assert(lab.presentation_profile != null, "Controllable presentation profile missing")
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
	_assert(lab.avatar.visible, "World avatar was hidden globally instead of being culled only from the local FP camera")
	_assert(String(fp_report.get("schema", "")) == "planet_simulator.full_body_first_person_adapter.v2", "Unexpected CH5 fix1 adapter schema")
	_assert(String(fp_report.get("entity_kind", "")) == "humanoid", "Quaternius presentation profile lost its entity kind")
	_assert(String(fp_report.get("first_person_policy", "")) == "HIDE_WORLD_MODEL", "CH5 fix1 is not using camera-layer body suppression")
	_assert(String(fp_report.get("mask_mode", "")) == "CAMERA_LAYER", "CH5 fix1 fell back to destructive head masking")
	_assert(bool(fp_report.get("mask_applied", false)), "First-person world-body suppression was not applied")
	_assert(bool(fp_report.get("world_hidden_from_first_person", false)), "First-person camera can still render the world body")
	_assert(bool(fp_report.get("world_visible_to_third_person", false)), "Third-person camera lost the world body")
	_assert(bool(fp_report.get("world_animation_preserved", false)), "World avatar animation contract was disabled in first person")
	_assert(int(fp_report.get("world_visual_count", 0)) > 0, "No world visuals were assigned to the dedicated presentation layer")
	var world_mask := int(fp_report.get("world_render_layer_mask", 0))
	_assert(world_mask != 0, "World presentation render layer mask is invalid")
	_assert((lab.first_person_camera.cull_mask & world_mask) == 0, "First-person camera still contains the own-body render layer")
	_assert((lab.third_person_camera.cull_mask & world_mask) != 0, "Third-person camera excludes the avatar render layer")
	_assert(not _has_skeleton_ancestor(lab.first_person_camera), "Camera is parented to an animated Skeleton3D")
	_assert(is_equal_approx(lab.camera_yaw.position.y, 1.62), "First-person camera anchor is not at stable eye height")
	_assert(_count_nodes_of_type(lab.first_person_adapter, CharacterBody3D) == 0, "First-person adapter owns gameplay body")
	_assert(_count_nodes_of_type(lab.first_person_adapter, CollisionShape3D) == 0, "First-person adapter owns collision")

	var avatar_report: Dictionary = lab.avatar.create_report()
	_assert(not bool(avatar_report.get("root_motion_applied", true)), "First-person lab enables root motion")

	var require_external := OS.get_environment("PLANET_SIMULATOR_REQUIRE_QUATERNIUS_ASSETS") == "1"
	if require_external:
		_assert(String(avatar_report.get("asset_mode", "")) in ["QUATERNIUS_RETARGET", "QUATERNIUS_EMBEDDED"], "Strict CH5 lab fell back from Quaternius")
		_assert(int(fp_report.get("world_visual_count", 0)) > 0, "Real Quaternius world body was not captured for camera-layer suppression")

	lab.set_first_person_mode(false)
	await process_frame
	fp_report = lab.first_person_adapter.create_report()
	_assert(not bool(fp_report.get("mask_applied", true)), "First-person presentation state stayed active in third person")
	_assert(lab.third_person_camera.current, "Third-person camera did not restore")
	_assert(lab.avatar.visible, "World avatar did not remain globally visible after returning to third person")

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
		print("CH5 fix1 camera-layer first-person lab: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH5 fix1 camera-layer first-person lab: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
