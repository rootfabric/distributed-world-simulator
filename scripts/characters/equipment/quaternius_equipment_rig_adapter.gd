class_name QuaterniusEquipmentRigAdapter
extends CharacterRigAdapter

const RIG_PROFILE_ID := "quaternius.ual1.humanoid"
const SEMANTIC_BONE_CANDIDATES := {
	"body.root": ["root", "hips", "pelvis"],
	"body.head": ["head"],
	"gear.back": ["spine2", "spine1", "spine", "chest", "upperchest"],
	"hand.left": ["hand_l", "lefthand", "handleft"],
	"hand.right": ["hand_r", "righthand", "handright"],
}

var _presenter: Node
var _target_skeleton: Skeleton3D
var _resolved_bones: Dictionary = {}
var _fallback_anchors: Dictionary = {}
var _attachments: Dictionary = {}
var _mode := "UNBOUND"


func bind_presenter(presenter: Node) -> Dictionary:
	clear()
	_presenter = presenter
	rig_profile_id = RIG_PROFILE_ID
	if _presenter == null:
		return _result(false, "MISSING_PRESENTER")

	var model_root := _find_descendant_named(_presenter, "QuaterniusModel")
	if model_root != null:
		_target_skeleton = _find_first_skeleton(model_root)
	if _target_skeleton != null:
		_resolve_skeleton_bones()
		_mode = "SKELETON"
	elif _bind_fallback_anchors():
		_mode = "FALLBACK"
	else:
		return _result(false, "UNSUPPORTED_QUATERNIUS_RIG")

	if not supports_anchor("body.head") or not supports_anchor("gear.back"):
		clear()
		return _result(false, "MISSING_REQUIRED_EQUIPMENT_ANCHOR")
	return _result(true, CharacterEquipmentDomain.RESULT_OK, create_report())


func clear() -> void:
	for raw_attachment in _attachments.values():
		if raw_attachment is Node and is_instance_valid(raw_attachment):
			(raw_attachment as Node).queue_free()
	_attachments.clear()
	_resolved_bones.clear()
	_fallback_anchors.clear()
	_target_skeleton = null
	_presenter = null
	_mode = "UNBOUND"
	rig_profile_id = ""


func supports_anchor(anchor_id: String) -> bool:
	return _resolved_bones.has(anchor_id) or _fallback_anchors.has(anchor_id)


func resolve_anchor(_character_visual_root: Node, anchor_id: String) -> Node3D:
	if _fallback_anchors.has(anchor_id):
		var fallback = _fallback_anchors[anchor_id]
		return fallback as Node3D if fallback is Node3D and is_instance_valid(fallback) else null
	if _target_skeleton == null or not _resolved_bones.has(anchor_id):
		return null
	if _attachments.has(anchor_id):
		var cached = _attachments[anchor_id]
		if cached is Node3D and is_instance_valid(cached) and not cached.is_queued_for_deletion():
			return cached as Node3D

	var attachment := BoneAttachment3D.new()
	attachment.name = "EquipmentAnchor_%s" % _safe_node_token(anchor_id)
	attachment.bone_name = StringName(_resolved_bones[anchor_id])
	_target_skeleton.add_child(attachment)
	_attachments[anchor_id] = attachment
	return attachment


func create_report() -> Dictionary:
	var resolved: Dictionary = {}
	for anchor_id in SEMANTIC_BONE_CANDIDATES.keys():
		if _resolved_bones.has(anchor_id):
			resolved[anchor_id] = String(_resolved_bones[anchor_id])
		elif _fallback_anchors.has(anchor_id):
			var node = _fallback_anchors[anchor_id]
			resolved[anchor_id] = String(node.name) if node is Node else ""
	return {
		"schema": "planet_simulator.quaternius_equipment_rig_adapter.v1",
		"rig_profile_id": rig_profile_id,
		"mode": _mode,
		"resolved_anchors": resolved,
		"target_skeleton": _target_skeleton != null,
		"attachment_count": _attachments.size(),
		"moves_gameplay_body": false,
		"reads_input": false,
		"owns_network_state": false,
	}


func _resolve_skeleton_bones() -> void:
	var bone_by_normalized_name: Dictionary = {}
	for index in range(_target_skeleton.get_bone_count()):
		var bone_name := String(_target_skeleton.get_bone_name(index))
		bone_by_normalized_name[_normalized_bone_name(bone_name)] = bone_name
	for raw_anchor_id in SEMANTIC_BONE_CANDIDATES.keys():
		var anchor_id := String(raw_anchor_id)
		for raw_candidate in SEMANTIC_BONE_CANDIDATES[anchor_id]:
			var candidate := _normalized_bone_name(String(raw_candidate))
			if bone_by_normalized_name.has(candidate):
				_resolved_bones[anchor_id] = String(bone_by_normalized_name[candidate])
				break


func _bind_fallback_anchors() -> bool:
	var fallback_root := _find_descendant_named(_presenter, "FallbackHumanoid")
	if fallback_root == null:
		return false
	var head := _find_descendant_named(fallback_root, "Head")
	var torso := _find_descendant_named(fallback_root, "Torso")
	var left_arm := _find_descendant_named(fallback_root, "LeftArm")
	var right_arm := _find_descendant_named(fallback_root, "RightArm")
	if head is Node3D:
		_fallback_anchors["body.head"] = head
	if torso is Node3D:
		_fallback_anchors["body.root"] = torso
		_fallback_anchors["gear.back"] = torso
	if left_arm is Node3D:
		_fallback_anchors["hand.left"] = left_arm
	if right_arm is Node3D:
		_fallback_anchors["hand.right"] = right_arm
	return not _fallback_anchors.is_empty()


func _find_descendant_named(root: Node, target_name: String) -> Node:
	if root == null:
		return null
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


func _normalized_bone_name(value: String) -> String:
	var normalized := value.to_lower()
	for token in ["_", "-", " ", "/", ".", ":"]:
		normalized = normalized.replace(token, "")
	for prefix in ["mixamorig", "def", "org", "armature"]:
		if normalized.begins_with(prefix):
			normalized = normalized.trim_prefix(prefix)
	return normalized.replace("left", "l").replace("right", "r")


func _safe_node_token(value: String) -> String:
	return value.replace("/", "_").replace(":", "_").replace(".", "_").replace("-", "_")


func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": success,
		"code": code,
		"details": details.duplicate(true),
	}
