class_name ThirdPersonHeldItemPresenter
extends Node

const DEFAULT_WORLD_LAYER_INDEX := 20
const RIGHT_HAND_SUFFIXES: Array[String] = [
	"righthand",
	"handr",
	"rhand",
	"rightwrist",
	"wristr",
]

var world_presentation: Node
var source_skeleton: Skeleton3D
var world_layer_index: int = DEFAULT_WORLD_LAYER_INDEX
var attachment_mode := "UNCONFIGURED"
var matched_bone_name := ""
var current_item_id := ""
var current_display_name := ""

var _anchor: Node3D
var _grip_root: Node3D
var _proxy: MeshInstance3D
var _owns_external_anchor := false
var _configured := false


func setup(
	p_world_presentation: Node,
	p_source_skeleton: Skeleton3D = null,
	p_world_layer_index: int = DEFAULT_WORLD_LAYER_INDEX
) -> Dictionary:
	if p_world_presentation == null:
		return _failure("THIRD_PERSON_HELD_WORLD_PRESENTATION_REQUIRED")
	if p_world_layer_index < 1 or p_world_layer_index > 20:
		return _failure("THIRD_PERSON_HELD_WORLD_LAYER_INVALID", {
			"world_layer_index": p_world_layer_index,
		})
	world_presentation = p_world_presentation
	source_skeleton = p_source_skeleton if p_source_skeleton != null else _find_first_skeleton(world_presentation)
	world_layer_index = p_world_layer_index
	_install_anchor()
	if _anchor == null or _grip_root == null:
		return _failure("THIRD_PERSON_HELD_ANCHOR_UNAVAILABLE")
	_configured = true
	return _success(create_report())


func present_item(
	item_id: String,
	display_name: String = "",
	item_color: Color = Color(0.65, 0.68, 0.72, 1.0)
) -> Dictionary:
	if not _configured:
		return _failure("THIRD_PERSON_HELD_NOT_CONFIGURED")
	var normalized_item_id := item_id.strip_edges()
	if normalized_item_id.is_empty():
		return clear_item()
	if current_item_id == normalized_item_id and _proxy != null and is_instance_valid(_proxy):
		_apply_proxy_metadata(normalized_item_id, display_name, item_color)
		return _success({
			"changed": false,
			"item_id": normalized_item_id,
			"attachment_mode": attachment_mode,
		})

	_clear_proxy()
	current_item_id = normalized_item_id
	current_display_name = display_name
	_proxy = MeshInstance3D.new()
	_proxy.name = "ThirdPersonHeldItemProxy"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.13, 0.17, 0.30)
	_proxy.mesh = mesh
	_proxy.position = Vector3(0.0, 0.0, -0.15)
	_proxy.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	_proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_proxy.layers = 0
	_proxy.set_layer_mask_value(world_layer_index, true)
	_grip_root.add_child(_proxy)
	_apply_proxy_metadata(normalized_item_id, display_name, item_color)
	return _success({
		"changed": true,
		"item_id": normalized_item_id,
		"display_name": display_name,
		"attachment_mode": attachment_mode,
		"matched_bone_name": matched_bone_name,
		"world_layer_index": world_layer_index,
		"presentation_only": true,
	})


func clear_item() -> Dictionary:
	var changed := not current_item_id.is_empty() or (_proxy != null and is_instance_valid(_proxy))
	_clear_proxy()
	current_item_id = ""
	current_display_name = ""
	return _success({
		"changed": changed,
		"item_id": "",
		"attachment_mode": attachment_mode,
	})


func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.third_person_held_item_presenter.v1",
		"configured": _configured,
		"attachment_mode": attachment_mode,
		"matched_bone_name": matched_bone_name,
		"source_skeleton_present": source_skeleton != null,
		"current_item_id": current_item_id,
		"current_display_name": current_display_name,
		"proxy_present": _proxy != null and is_instance_valid(_proxy),
		"world_layer_index": world_layer_index,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func _install_anchor() -> void:
	_cleanup_anchor()
	if source_skeleton != null:
		var right_hand_index := _find_right_hand_bone(source_skeleton)
		if right_hand_index >= 0:
			var attachment := BoneAttachment3D.new()
			attachment.name = "FpeR2RightHandAttachment"
			attachment.bone_name = source_skeleton.get_bone_name(right_hand_index)
			source_skeleton.add_child(attachment)
			_anchor = attachment
			matched_bone_name = String(attachment.bone_name)
			attachment_mode = "BONE_RIGHT_HAND"
			_owns_external_anchor = true

	if _anchor == null:
		var fallback_parent: Node = world_presentation.find_child("AvatarYawRoot", true, false)
		if fallback_parent == null:
			fallback_parent = world_presentation
		if fallback_parent is Node3D:
			var fallback := Node3D.new()
			fallback.name = "FpeR2FallbackRightHandAnchor"
			fallback.position = Vector3(0.48, 1.22, -0.10)
			fallback.rotation_degrees = Vector3(-12.0, -8.0, -18.0)
			(fallback_parent as Node3D).add_child(fallback)
			_anchor = fallback
			attachment_mode = "FALLBACK_AVATAR_ANCHOR"
			matched_bone_name = ""
			_owns_external_anchor = true

	if _anchor != null:
		_grip_root = Node3D.new()
		_grip_root.name = "FpeR2HeldItemGrip"
		if attachment_mode == "BONE_RIGHT_HAND":
			_grip_root.position = Vector3(0.0, -0.035, -0.075)
			_grip_root.rotation_degrees = Vector3(5.0, 0.0, 90.0)
		_anchor.add_child(_grip_root)


func _find_right_hand_bone(skeleton: Skeleton3D) -> int:
	var best_index := -1
	var best_score := -1
	for index in range(skeleton.get_bone_count()):
		var normalized := _normalize_bone_name(String(skeleton.get_bone_name(index)))
		var score := 0
		for suffix in RIGHT_HAND_SUFFIXES:
			if normalized == suffix:
				score = maxi(score, 100)
			elif normalized.ends_with(suffix):
				score = maxi(score, 80)
			elif normalized.contains(suffix):
				score = maxi(score, 60)
		if normalized.contains("forearm") or normalized.contains("lowerarm"):
			score -= 80
		if score > best_score:
			best_score = score
			best_index = index
	return best_index if best_score > 0 else -1


func _find_first_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_first_skeleton(child)
		if found != null:
			return found
	return null


func _normalize_bone_name(value: String) -> String:
	var normalized := value.to_lower()
	for token in ["_", "-", ".", ":", " ", "/", "\\"]:
		normalized = normalized.replace(token, "")
	return normalized


func _apply_proxy_metadata(item_id: String, display_name: String, item_color: Color) -> void:
	if _proxy == null or not is_instance_valid(_proxy):
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = item_color
	material.roughness = 0.72
	_proxy.material_override = material
	_proxy.set_meta("canonical_item_id", item_id)
	_proxy.set_meta("display_name", display_name)
	current_item_id = item_id
	current_display_name = display_name


func _clear_proxy() -> void:
	if _proxy != null and is_instance_valid(_proxy):
		_proxy.queue_free()
	_proxy = null


func _cleanup_anchor() -> void:
	_clear_proxy()
	_grip_root = null
	if _owns_external_anchor and _anchor != null and is_instance_valid(_anchor):
		_anchor.queue_free()
	_anchor = null
	_owns_external_anchor = false
	attachment_mode = "UNCONFIGURED"
	matched_bone_name = ""


func _exit_tree() -> void:
	_cleanup_anchor()


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
