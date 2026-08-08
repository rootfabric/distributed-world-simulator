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
	_assert(lab.player_capsule is CapsuleShape3D, "Lab crouch capsule missing")
	_assert(lab.avatar != null, "Avatar presenter missing")
	_assert(lab.first_person_adapter != null, "First-person adapter missing")
	_assert(lab.presentation_profile != null, "Controllable presentation profile missing")
	_assert(lab.first_person_camera is Camera3D, "First-person camera missing")
	_assert(lab.third_person_camera is Camera3D, "Third-person camera missing")
	_assert(InputMap.has_action("ch4_crouch"), "Crouch input action missing")
	_assert(not lab.first_person_mode, "Lab must start in third person for A/B comparison")
	_assert(lab.third_person_camera.current, "Third-person camera is not current initially")
	_assert(lab.camera == lab.third_person_camera, "Current camera alias is not third-person initially")

	var lab_source := FileAccess.get_file_as_string("res://scripts/characters/lab/quaternius_character_lab.gd")
	_assert(not lab_source.contains("KEY_V"), "Technical model yaw toggle is still exposed in the lab")
	_assert(not lab_source.contains("развернуть модель"), "HUD still advertises the technical model yaw toggle")

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
	_assert(String(fp_report.get("first_person_shadow_policy", "")) == "WORLD_PROXY", "CH6 fix1 is not using WORLD_PROXY shadow preservation")
	_assert(String(fp_report.get("mask_mode", "")) == "CAMERA_LAYER", "CH5 fix1 fell back to destructive head masking")
	_assert(bool(fp_report.get("mask_applied", false)), "First-person world-body suppression was not applied")
	_assert(bool(fp_report.get("world_hidden_from_first_person", false)), "First-person camera can still render the world body")
	_assert(bool(fp_report.get("world_visible_to_third_person", false)), "Third-person camera lost the world body")
	_assert(bool(fp_report.get("world_animation_preserved", false)), "World avatar animation contract was disabled in first person")
	_assert(int(fp_report.get("world_visual_count", 0)) > 0, "No world visuals were assigned to the dedicated presentation layer")
	_assert(bool(fp_report.get("shadow_preservation_enabled", false)), "First-person shadow preservation is disabled")
	_assert(bool(fp_report.get("shadow_proxy_ready", false)), "First-person shadow proxy is not ready")
	_assert(bool(fp_report.get("shadow_proxy_active", false)), "First-person shadow proxy did not activate")
	_assert(bool(fp_report.get("shadow_caster_preserved", false)), "First-person hidden body has no preserved shadow caster")
	_assert(int(fp_report.get("shadow_proxy_count", 0)) > 0, "No shadow-only meshes were generated")
	_assert(int(fp_report.get("shadow_proxy_shared_mesh_count", 0)) == int(fp_report.get("shadow_proxy_count", 0)), "Shadow proxy duplicates mesh resources")
	_assert(bool(fp_report.get("render_layers_distinct", false)), "World/viewmodel/shadow layers overlap")
	var world_mask := int(fp_report.get("world_render_layer_mask", 0))
	var shadow_mask := int(fp_report.get("shadow_render_layer_mask", 0))
	_assert(world_mask != 0, "World presentation render layer mask is invalid")
	_assert(shadow_mask != 0, "Shadow presentation render layer mask is invalid")
	_assert(world_mask != shadow_mask, "World and shadow render layer masks overlap")
	_assert((lab.first_person_camera.cull_mask & world_mask) == 0, "First-person camera still contains the own-body render layer")
	_assert((lab.first_person_camera.cull_mask & shadow_mask) != 0, "First-person camera excludes the shadow-only render layer")
	_assert((lab.third_person_camera.cull_mask & world_mask) != 0, "Third-person camera excludes the avatar render layer")
	_assert(not _has_skeleton_ancestor(lab.first_person_camera), "Camera is parented to an animated Skeleton3D")
	_assert(is_equal_approx(lab.camera_yaw.position.y, 1.62), "First-person camera anchor is not at stable eye height")
	_assert(_count_nodes_of_type(lab.first_person_adapter, CharacterBody3D) == 0, "First-person adapter owns gameplay body")
	_assert(_count_nodes_of_type(lab.first_person_adapter, CollisionShape3D) == 0, "First-person adapter owns collision")

	var standing_height: float = float(lab.player_capsule.height)
	var standing_bottom: float = float(lab.player_collision.position.y - lab.player_capsule.height * 0.5)
	lab._apply_crouch_shape(true, 1.0)
	_assert(lab.player_capsule.height < standing_height, "Crouch does not reduce gameplay capsule height in the isolated lab")
	var crouching_bottom: float = float(lab.player_collision.position.y - lab.player_capsule.height * 0.5)
	_assert(is_equal_approx(crouching_bottom, standing_bottom), "Crouch changes the gameplay capsule foot plane and can make the body float")
	_assert(lab.camera_yaw.position.y < 1.62, "Crouch does not lower the local camera anchor")
	lab.avatar.apply_motion(Vector3.ZERO, Vector3.UP, Vector3.FORWARD, {"grounded": true, "crouching": true})
	await process_frame
	var avatar_report: Dictionary = lab.avatar.create_report()
	_assert(String(avatar_report.get("current_semantic", "")) == "crouch_idle", "Crouch lab state did not reach presenter")
	_assert(bool(lab.first_person_adapter.create_report().get("shadow_proxy_active", false)), "Crouch disabled first-person shadow preservation")

	lab.avatar.apply_motion(Vector3(0.0, 4.0, 0.0), Vector3.UP, Vector3.FORWARD, {"grounded": false, "crouching": false})
	await process_frame
	avatar_report = lab.avatar.create_report()
	_assert(String(avatar_report.get("current_semantic", "")) == "jump", "Airborne lab state did not reach presenter")
	_assert(bool(lab.first_person_adapter.create_report().get("shadow_proxy_active", false)), "Jump disabled first-person shadow preservation")
	lab._apply_crouch_shape(false, 1.0)
	lab.avatar.apply_motion(Vector3.ZERO, Vector3.UP, Vector3.FORWARD, {"grounded": true, "crouching": false})
	await process_frame
	_assert(is_equal_approx(lab.player_capsule.height, standing_height), "Standing capsule height did not restore")
	var restored_bottom: float = float(lab.player_collision.position.y - lab.player_capsule.height * 0.5)
	_assert(is_equal_approx(restored_bottom, standing_bottom), "Standing restore changes the gameplay capsule foot plane")

	avatar_report = lab.avatar.create_report()
	_assert(not bool(avatar_report.get("root_motion_applied", true)), "First-person lab enables root motion")

	var require_external := OS.get_environment("PLANET_SIMULATOR_REQUIRE_QUATERNIUS_ASSETS") == "1"
	if require_external:
		_assert(String(avatar_report.get("asset_mode", "")) in ["QUATERNIUS_RETARGET", "QUATERNIUS_EMBEDDED"], "Strict CH5 lab fell back from Quaternius")
		_assert(bool(avatar_report.get("supports_jump", false)), "Real UAL1 Jump clip unavailable in lab")
		_assert(bool(avatar_report.get("supports_crouch", false)), "Real UAL1 crouch clips unavailable in lab")
		_assert(int(fp_report.get("world_visual_count", 0)) > 0, "Real Quaternius world body was not captured for camera-layer suppression")
		_assert(int(fp_report.get("shadow_proxy_skinned_count", 0)) > 0, "Real Quaternius did not produce a skinned first-person shadow proxy")
		_assert(int(fp_report.get("shadow_proxy_skeleton_bound_count", 0)) > 0, "Real Quaternius shadow proxy is not bound to its animated Skeleton3D")

	lab.set_first_person_mode(false)
	await process_frame
	fp_report = lab.first_person_adapter.create_report()
	_assert(not bool(fp_report.get("mask_applied", true)), "First-person presentation state stayed active in third person")
	_assert(not bool(fp_report.get("shadow_proxy_active", true)), "Shadow proxy stayed active in third person")
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
		print("CH5/CH6 fix2 first-person jump/crouch lab: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH5/CH6 fix2 first-person jump/crouch lab: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)