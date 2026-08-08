class_name FullBodyFirstPersonAdapter
extends "res://scripts/characters/presentation/controllable_view_adapter.gd"

const FIRST_PERSON_HEAD_SCALE := Vector3(0.001, 0.001, 0.001)

var avatar: Node
var mask_mode := "UNBOUND"
var head_bone_name := ""

var _target_skeleton: Skeleton3D
var _head_bone_index := -1
var _head_default_scale := Vector3.ONE
var _fallback_head: Node3D


func bind_avatar(presenter: Node, profile_override: Resource = null) -> Dictionary:
	_restore_mask_target()
	avatar = presenter
	var effective_profile := profile_override
	if effective_profile == null:
		effective_profile = _create_legacy_compatibility_profile()
	super.bind_presentation(presenter, effective_profile)
	_resolve_mask_target()
	_apply_mask()
	return _success(create_report())


func unbind_avatar() -> void:
	_restore_mask_target()
	avatar = null
	_target_skeleton = null
	_head_bone_index = -1
	_head_default_scale = Vector3.ONE
	_fallback_head = null
	mask_mode = "UNBOUND"
	head_bone_name = ""
	super.unbind_presentation()


func set_first_person_enabled(enabled: bool) -> Dictionary:
	super.set_first_person_enabled(enabled)
	_apply_mask()
	return _success(create_report())


func _process(_delta: float) -> void:
	# Legacy compatibility only. The CH5 fix1 path no longer edits a humanoid
	# skeleton every frame; it keeps the world model alive and removes its render
	# layer from the local first-person camera instead.
	if first_person_enabled and _uses_legacy_head_mask():
		_apply_mask()


func _create_legacy_compatibility_profile() -> Resource:
	var compatibility = PresentationProfile.new()
	compatibility.profile_id = &"legacy_full_body_first_person"
	compatibility.entity_kind = &"humanoid"
	compatibility.first_person_policy = PresentationProfile.FirstPersonPolicy.LEGACY_HEAD_MASK
	return compatibility


func _uses_legacy_head_mask() -> bool:
	return get_first_person_policy() == PresentationProfile.FirstPersonPolicy.LEGACY_HEAD_MASK


func _resolve_mask_target() -> void:
	_target_skeleton = null
	_head_bone_index = -1
	_head_default_scale = Vector3.ONE
	_fallback_head = null
	mask_mode = "UNAVAILABLE"
	head_bone_name = ""
	if avatar == null:
		mask_mode = "UNBOUND"
		return

	if not _uses_legacy_head_mask():
		match get_first_person_policy():
			PresentationProfile.FirstPersonPolicy.HIDE_WORLD_MODEL:
				mask_mode = "CAMERA_LAYER"
			PresentationProfile.FirstPersonPolicy.VIEWMODEL:
				mask_mode = "VIEWMODEL"
			PresentationProfile.FirstPersonPolicy.SHOW_WORLD_MODEL:
				mask_mode = "NONE"
			_:
				mask_mode = "UNAVAILABLE"
		return

	var model_root := _find_descendant_named(avatar, "QuaterniusModel")
	if model_root != null:
		_target_skeleton = _find_first_skeleton(model_root)
		if _target_skeleton != null:
			_head_bone_index = _find_head_bone(_target_skeleton)
			if _head_bone_index >= 0:
				head_bone_name = String(_target_skeleton.get_bone_name(_head_bone_index))
				_head_default_scale = _target_skeleton.get_bone_pose_scale(_head_bone_index)
				mask_mode = "BONE_SCALE"
				return

	var fallback_root := _find_descendant_named(avatar, "FallbackHumanoid")
	if fallback_root != null:
		var head := _find_descendant_named(fallback_root, "Head")
		if head is Node3D:
			_fallback_head = head as Node3D
			mask_mode = "FALLBACK_VISIBILITY"


func _apply_mask() -> void:
	if not _uses_legacy_head_mask():
		return
	if mask_mode == "BONE_SCALE" and _target_skeleton != null and _head_bone_index >= 0:
		_target_skeleton.set_bone_pose_scale(
			_head_bone_index,
			FIRST_PERSON_HEAD_SCALE if first_person_enabled else _head_default_scale
		)
	elif mask_mode == "FALLBACK_VISIBILITY" and _fallback_head != null:
		_fallback_head.visible = not first_person_enabled


func _restore_mask_target() -> void:
	if _target_skeleton != null and _head_bone_index >= 0:
		_target_skeleton.set_bone_pose_scale(_head_bone_index, _head_default_scale)
	if _fallback_head != null:
		_fallback_head.visible = true


func _find_head_bone(skeleton: Skeleton3D) -> int:
	var exact := -1
	var suffix := -1
	for index in range(skeleton.get_bone_count()):
		var normalized := _normalized_bone_name(skeleton.get_bone_name(index))
		if normalized == "head":
			exact = index
			break
		if suffix < 0 and normalized.ends_with("head"):
			suffix = index
	return exact if exact >= 0 else suffix


func _find_descendant_named(root: Node, target_name: String) -> Node:
	if String(root.name) == target_name:
		return root
	for child in root.get_children():
		var found := _find_descendant_named(child, target_name)
		if found != null:
			return found
	return null


func _find_first_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_first_skeleton(child)
		if found != null:
			return found
	return null


func _normalized_bone_name(value: StringName) -> String:
	var normalized := String(value).to_lower()
	for token in ["_", "-", " ", "/", ".", ":"]:
		normalized = normalized.replace(token, "")
	for prefix in ["mixamorig", "def", "org", "armature"]:
		if normalized.begins_with(prefix):
			normalized = normalized.trim_prefix(prefix)
	return normalized.replace("left", "l").replace("right", "r")


func create_report() -> Dictionary:
	var base_report := super.create_report()
	var legacy_ready := mask_mode in ["BONE_SCALE", "FALLBACK_VISIBILITY"]
	var camera_layer_ready := (
		mask_mode == "CAMERA_LAYER"
		and bool(base_report.get("first_person_camera_bound", false))
		and int(base_report.get("world_visual_count", 0)) > 0
	)
	var camera_layer_applied := (
		first_person_enabled
		and camera_layer_ready
		and bool(base_report.get("world_hidden_from_first_person", false))
	)
	return {
		"schema": "planet_simulator.full_body_first_person_adapter.v2",
		"first_person_enabled": first_person_enabled,
		"mask_mode": mask_mode,
		"mask_ready": legacy_ready or camera_layer_ready or mask_mode == "VIEWMODEL",
		"mask_applied": (
			(first_person_enabled and legacy_ready)
			or camera_layer_applied
			or (first_person_enabled and mask_mode == "VIEWMODEL")
		),
		"head_bone_name": head_bone_name,
		"head_bone_present": _head_bone_index >= 0,
		"fallback_head_present": _fallback_head != null,
		"first_person_policy": String(base_report.get("first_person_policy", "")),
		"profile_id": String(base_report.get("profile_id", "")),
		"entity_kind": String(base_report.get("entity_kind", "")),
		"world_visual_count": int(base_report.get("world_visual_count", 0)),
		"world_hidden_from_first_person": bool(base_report.get("world_hidden_from_first_person", false)),
		"world_visible_to_third_person": bool(base_report.get("world_visible_to_third_person", false)),
		"world_animation_preserved": bool(base_report.get("world_animation_preserved", true)),
		"shadow_caster_preserved": bool(base_report.get("shadow_caster_preserved", true)),
		"world_render_layer_mask": int(base_report.get("world_render_layer_mask", 0)),
		"viewmodel_render_layer_mask": int(base_report.get("viewmodel_render_layer_mask", 0)),
	}
