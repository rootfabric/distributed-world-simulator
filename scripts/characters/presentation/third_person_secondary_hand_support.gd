class_name ThirdPersonSecondaryHandSupport
extends Node

const MODE_UNAVAILABLE := "UNAVAILABLE"
const MODE_NATIVE_TWO_BONE_IK := "NATIVE_TWO_BONE_IK"
const MODE_FALLBACK_PROCEDURAL_ARM := "FALLBACK_PROCEDURAL_ARM"
const DEFAULT_WORLD_LAYER_INDEX := 20
const FALLBACK_UPPER_ARM_LENGTH := 0.40
const FALLBACK_LOWER_ARM_LENGTH := 0.40

const LEFT_HAND_SUFFIXES: Array[String] = [
	"lefthand",
	"handl",
	"lhand",
	"leftwrist",
	"wristl",
]
const LEFT_FOREARM_SUFFIXES: Array[String] = [
	"leftforearm",
	"forearml",
	"leftlowerarm",
	"lowerarml",
]
const LEFT_UPPER_ARM_SUFFIXES: Array[String] = [
	"leftupperarm",
	"upperarml",
	"leftarm",
	"arml",
]

var world_presentation: Node
var source_skeleton: Skeleton3D
var world_layer_index: int = DEFAULT_WORLD_LAYER_INDEX
var mode := MODE_UNAVAILABLE
var active := false
var current_item_id := ""
var current_profile_id := ""
var matched_root_bone := ""
var matched_middle_bone := ""
var matched_end_bone := ""

var _ik: TwoBoneIK3D
var _pole: Node3D
var _active_target: Node3D
var _root_bone_index := -1
var _middle_bone_index := -1
var _end_bone_index := -1

var _fallback_parent: Node3D
var _fallback_original_arm: Node3D
var _fallback_original_arm_visible := true
var _fallback_upper: MeshInstance3D
var _fallback_lower: MeshInstance3D
var _fallback_hand: MeshInstance3D
var _fallback_target_error_m := 0.0
var _fallback_updates := 0
var _activations := 0
var _deactivations := 0
var _configured := false


func setup(
	p_world_presentation: Node,
	p_source_skeleton: Skeleton3D = null,
	p_world_layer_index: int = DEFAULT_WORLD_LAYER_INDEX
) -> Dictionary:
	if p_world_presentation == null:
		return _failure("FPE_S5_WORLD_PRESENTATION_REQUIRED")
	if p_world_layer_index < 1 or p_world_layer_index > 20:
		return _failure("FPE_S5_WORLD_LAYER_INVALID", {"world_layer_index": p_world_layer_index})
	world_presentation = p_world_presentation
	source_skeleton = p_source_skeleton
	world_layer_index = p_world_layer_index
	_cleanup_runtime()

	if source_skeleton != null and is_instance_valid(source_skeleton) and _resolve_left_arm_chain(source_skeleton):
		_install_native_ik()
	elif _install_fallback_support():
		mode = MODE_FALLBACK_PROCEDURAL_ARM
	else:
		mode = MODE_UNAVAILABLE
		return _failure("FPE_S5_LEFT_ARM_PRESENTATION_UNAVAILABLE", create_report())

	_configured = true
	set_process(false)
	return _success(create_report())


func activate(target: Node3D, item_id: String, grip_profile: Dictionary = {}) -> Dictionary:
	if not _configured:
		return _failure("FPE_S5_NOT_CONFIGURED")
	if target == null or not is_instance_valid(target):
		return _failure("FPE_S5_SECONDARY_TARGET_REQUIRED")
	if active:
		deactivate("TARGET_REPLACED")
	_active_target = target
	current_item_id = item_id.strip_edges()
	current_profile_id = String(grip_profile.get("profile_id", "")).strip_edges()

	if mode == MODE_NATIVE_TWO_BONE_IK:
		if _ik == null or not is_instance_valid(_ik):
			return _failure("FPE_S5_NATIVE_IK_MISSING")
		_ik.set_target_node(0, _ik.get_path_to(_active_target))
		_ik.reset()
		_ik.active = true
		active = true
		_activations += 1
		return _success({
			"active": true,
			"mode": mode,
			"item_id": current_item_id,
			"profile_id": current_profile_id,
		})

	if mode == MODE_FALLBACK_PROCEDURAL_ARM:
		if _fallback_original_arm != null and is_instance_valid(_fallback_original_arm):
			_fallback_original_arm_visible = _fallback_original_arm.visible
			_fallback_original_arm.visible = false
		_set_fallback_visible(true)
		active = true
		_activations += 1
		set_process(true)
		_update_fallback_arm()
		return _success({
			"active": true,
			"mode": mode,
			"item_id": current_item_id,
			"profile_id": current_profile_id,
		})

	return _failure("FPE_S5_SUPPORT_MODE_UNAVAILABLE")


func deactivate(reason: String = "CLEARED") -> Dictionary:
	var changed := active or _active_target != null
	if _ik != null and is_instance_valid(_ik):
		_ik.active = false
		_ik.set_target_node(0, NodePath())
	if _fallback_original_arm != null and is_instance_valid(_fallback_original_arm):
		_fallback_original_arm.visible = _fallback_original_arm_visible
	_set_fallback_visible(false)
	set_process(false)
	active = false
	_active_target = null
	current_item_id = ""
	current_profile_id = ""
	if changed:
		_deactivations += 1
	return _success({
		"changed": changed,
		"active": false,
		"reason": reason,
		"mode": mode,
	})


func _process(_delta: float) -> void:
	if active and mode == MODE_FALLBACK_PROCEDURAL_ARM:
		_update_fallback_arm()


func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.fpe_r2_s5_third_person_secondary_hand.v1",
		"configured": _configured,
		"active": active,
		"mode": mode,
		"item_id": current_item_id,
		"profile_id": current_profile_id,
		"source_skeleton_present": source_skeleton != null and is_instance_valid(source_skeleton),
		"matched_root_bone": matched_root_bone,
		"matched_middle_bone": matched_middle_bone,
		"matched_end_bone": matched_end_bone,
		"native_ik_present": _ik != null and is_instance_valid(_ik),
		"fallback_original_arm_present": _fallback_original_arm != null and is_instance_valid(_fallback_original_arm),
		"fallback_target_error_m": _fallback_target_error_m,
		"fallback_updates": _fallback_updates,
		"activations": _activations,
		"deactivations": _deactivations,
		"world_layer_index": world_layer_index,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
		"collision_body_created": false,
	}


func _resolve_left_arm_chain(skeleton: Skeleton3D) -> bool:
	_end_bone_index = _find_best_bone(skeleton, LEFT_HAND_SUFFIXES)
	if _end_bone_index < 0:
		return false
	_middle_bone_index = _find_named_ancestor(skeleton, _end_bone_index, LEFT_FOREARM_SUFFIXES)
	if _middle_bone_index < 0:
		_middle_bone_index = skeleton.get_bone_parent(_end_bone_index)
	if _middle_bone_index < 0:
		return false
	_root_bone_index = _find_named_ancestor(skeleton, _middle_bone_index, LEFT_UPPER_ARM_SUFFIXES)
	if _root_bone_index < 0:
		_root_bone_index = skeleton.get_bone_parent(_middle_bone_index)
	if _root_bone_index < 0:
		return false
	matched_root_bone = String(skeleton.get_bone_name(_root_bone_index))
	matched_middle_bone = String(skeleton.get_bone_name(_middle_bone_index))
	matched_end_bone = String(skeleton.get_bone_name(_end_bone_index))
	return true


func _install_native_ik() -> void:
	mode = MODE_NATIVE_TWO_BONE_IK
	_ik = TwoBoneIK3D.new()
	_ik.name = "FpeR2S5LeftArmTwoBoneIK"
	source_skeleton.add_child(_ik)
	_ik.set_setting_count(1)
	_ik.set_root_bone_name(0, matched_root_bone)
	_ik.set_middle_bone_name(0, matched_middle_bone)
	_ik.set_end_bone_name(0, matched_end_bone)
	_ik.set_use_virtual_end(0, false)
	_ik.mutable_bone_axes = false
	_ik.influence = 1.0
	_ik.active = false

	_pole = Node3D.new()
	_pole.name = "FpeR2S5LeftElbowPole"
	source_skeleton.add_child(_pole)
	var root_pose := source_skeleton.get_bone_global_pose(_root_bone_index)
	_pole.position = root_pose.origin + Vector3(-0.45, -0.12, 0.38)
	_ik.set_pole_node(0, _ik.get_path_to(_pole))


func _install_fallback_support() -> bool:
	var model_root := world_presentation.find_child("FallbackHumanoid", true, false)
	if not model_root is Node3D:
		return false
	_fallback_parent = model_root as Node3D
	var left_arm := _fallback_parent.find_child("LeftArm", true, false)
	if left_arm is Node3D:
		_fallback_original_arm = left_arm as Node3D

	_fallback_upper = _create_fallback_segment("FpeR2S5FallbackUpperArm")
	_fallback_lower = _create_fallback_segment("FpeR2S5FallbackLowerArm")
	_fallback_hand = _create_fallback_hand()
	_fallback_parent.add_child(_fallback_upper)
	_fallback_parent.add_child(_fallback_lower)
	_fallback_parent.add_child(_fallback_hand)
	_set_fallback_visible(false)
	return true


func _create_fallback_segment(node_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 0.12, 1.0)
	instance.mesh = mesh
	instance.material_override = _fallback_material(Color(0.25, 0.48, 0.82, 1.0))
	instance.layers = 0
	instance.set_layer_mask_value(world_layer_index, true)
	return instance


func _create_fallback_hand() -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = "FpeR2S5FallbackLeftHand"
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	instance.mesh = mesh
	instance.material_override = _fallback_material(Color(0.72, 0.52, 0.38, 1.0))
	instance.layers = 0
	instance.set_layer_mask_value(world_layer_index, true)
	return instance


func _fallback_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material


func _update_fallback_arm() -> void:
	if _fallback_parent == null or not is_instance_valid(_fallback_parent):
		return
	if _active_target == null or not is_instance_valid(_active_target):
		deactivate("TARGET_GONE")
		return
	if _fallback_upper == null or _fallback_lower == null or _fallback_hand == null:
		return

	var shoulder_local := Vector3(-0.33, 1.62, 0.0)
	var shoulder := _fallback_parent.global_transform * shoulder_local
	var target := _active_target.global_position
	var to_target := target - shoulder
	var raw_distance := to_target.length()
	if raw_distance <= 0.0001:
		return
	var direction := to_target / raw_distance
	var maximum_reach := FALLBACK_UPPER_ARM_LENGTH + FALLBACK_LOWER_ARM_LENGTH - 0.01
	var solved_distance := clampf(raw_distance, 0.08, maximum_reach)
	var solved_target := shoulder + direction * solved_distance

	var x := (
		FALLBACK_UPPER_ARM_LENGTH * FALLBACK_UPPER_ARM_LENGTH
		- FALLBACK_LOWER_ARM_LENGTH * FALLBACK_LOWER_ARM_LENGTH
		+ solved_distance * solved_distance
	) / (2.0 * solved_distance)
	var height_sq := maxf(FALLBACK_UPPER_ARM_LENGTH * FALLBACK_UPPER_ARM_LENGTH - x * x, 0.0)
	var height := sqrt(height_sq)
	var pole_vector := _fallback_parent.global_transform.basis * Vector3(-0.55, -0.15, 0.42)
	var pole_plane := pole_vector - direction * pole_vector.dot(direction)
	if pole_plane.length_squared() <= 0.000001:
		pole_plane = direction.cross(Vector3.UP)
	if pole_plane.length_squared() <= 0.000001:
		pole_plane = direction.cross(Vector3.RIGHT)
	pole_plane = pole_plane.normalized()
	var elbow := shoulder + direction * x + pole_plane * height

	_orient_fallback_segment(_fallback_upper, shoulder, elbow)
	_orient_fallback_segment(_fallback_lower, elbow, solved_target)
	_fallback_hand.global_position = solved_target
	_fallback_target_error_m = solved_target.distance_to(target)
	_fallback_updates += 1


func _orient_fallback_segment(segment: MeshInstance3D, start: Vector3, finish: Vector3) -> void:
	var delta := finish - start
	var length := delta.length()
	if length <= 0.0001:
		segment.visible = false
		return
	segment.visible = true
	segment.global_position = (start + finish) * 0.5
	var up := Vector3.UP
	if absf(delta.normalized().dot(up)) > 0.98:
		up = Vector3.FORWARD
	segment.look_at(finish, up)
	segment.scale = Vector3(1.0, 1.0, length)


func _set_fallback_visible(value: bool) -> void:
	for node in [_fallback_upper, _fallback_lower, _fallback_hand]:
		if node != null and is_instance_valid(node):
			node.visible = value


func _find_best_bone(skeleton: Skeleton3D, suffixes: Array[String]) -> int:
	var best_index := -1
	var best_score := -1
	for index in range(skeleton.get_bone_count()):
		var normalized := _normalize_bone_name(String(skeleton.get_bone_name(index)))
		var score := 0
		for suffix in suffixes:
			var candidate := _normalize_bone_name(suffix)
			if normalized == candidate:
				score = maxi(score, 100)
			elif normalized.ends_with(candidate):
				score = maxi(score, 80)
			elif normalized.contains(candidate):
				score = maxi(score, 60)
		if score > best_score:
			best_score = score
			best_index = index
	return best_index if best_score > 0 else -1


func _find_named_ancestor(skeleton: Skeleton3D, start_index: int, suffixes: Array[String]) -> int:
	var current := skeleton.get_bone_parent(start_index)
	while current >= 0:
		var normalized := _normalize_bone_name(String(skeleton.get_bone_name(current)))
		for suffix in suffixes:
			var candidate := _normalize_bone_name(suffix)
			if normalized == candidate or normalized.ends_with(candidate) or normalized.contains(candidate):
				return current
		current = skeleton.get_bone_parent(current)
	return -1


func _normalize_bone_name(value: String) -> String:
	var normalized := value.to_lower()
	for token in ["_", "-", ".", ":", " ", "/", "\\"]:
		normalized = normalized.replace(token, "")
	return normalized


func _cleanup_runtime() -> void:
	deactivate("RESET")
	if _ik != null and is_instance_valid(_ik):
		_ik.queue_free()
	if _pole != null and is_instance_valid(_pole):
		_pole.queue_free()
	for node in [_fallback_upper, _fallback_lower, _fallback_hand]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_ik = null
	_pole = null
	_fallback_upper = null
	_fallback_lower = null
	_fallback_hand = null
	_fallback_parent = null
	_fallback_original_arm = null
	matched_root_bone = ""
	matched_middle_bone = ""
	matched_end_bone = ""
	_root_bone_index = -1
	_middle_bone_index = -1
	_end_bone_index = -1
	mode = MODE_UNAVAILABLE
	_configured = false


func _exit_tree() -> void:
	_cleanup_runtime()


func _success(details: Dictionary = {}) -> Dictionary:
	return {
		"success": true,
		"error_code": "",
		"details": details.duplicate(true),
	}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
