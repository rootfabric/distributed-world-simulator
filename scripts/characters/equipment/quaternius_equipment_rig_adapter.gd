class_name QuaterniusEquipmentRigAdapter
extends CharacterRigAdapter

const HeadClipMaterial = preload("res://scripts/characters/equipment/quaternius_head_clip_material.gd")

const RIG_PROFILE_ID := "quaternius.ual1.humanoid"
const REQUIRED_ANCHORS := ["body.head", "gear.back"]
const COARSE_BODY_REGIONS := [
	"body.region.torso",
	"body.region.arms",
	"body.region.legs",
	"body.region.feet",
]
const HEAD_CLIP_BELOW_EYES_M := 0.20
const HEAD_CLIP_FALLBACK_BODY_FRACTION := 0.82
const SEMANTIC_BONE_CANDIDATES := {
	"body.root": ["root", "hips", "pelvis"],
	"body.head": ["head"],
	"gear.back": [
		"spine3", "spine03", "spine003",
		"spine2", "spine02", "spine002",
		"spine1", "spine01", "spine001",
		"spine", "upperchest", "chest", "torso"
	],
	"hand.left": ["hand_l", "lefthand", "handleft", "lhand"],
	"hand.right": ["hand_r", "righthand", "handright", "rhand"],
}
const BACK_BONE_TOKENS := ["spine", "upperchest", "chest", "torso"]

var _presenter: Node
var _target_skeleton: Skeleton3D
var _resolved_bones: Dictionary = {}
var _fallback_anchors: Dictionary = {}
var _attachments: Dictionary = {}
var _mode := "UNBOUND"
var _head_clip_mesh: MeshInstance3D
var _head_clip_material: ShaderMaterial
var _head_clip_y := 0.0
var _head_clip_error := ""


func bind_presenter(presenter: Node) -> Dictionary:
	clear()
	_presenter = presenter
	rig_profile_id = RIG_PROFILE_ID
	if _presenter == null:
		return _result(false, "MISSING_PRESENTER")

	var model_root: Node = _find_descendant_named(_presenter, "QuaterniusModel")
	if model_root != null:
		_target_skeleton = _find_first_skeleton(model_root)
	if _target_skeleton != null:
		_resolve_skeleton_bones()
		_mode = "SKELETON"
	elif _bind_fallback_anchors():
		_mode = "FALLBACK"
	else:
		return _result(false, "UNSUPPORTED_QUATERNIUS_RIG")

	var missing: Array[String] = _missing_required_anchors()
	if not missing.is_empty():
		var failure_details: Dictionary = create_report()
		failure_details["missing_required_anchors"] = missing
		failure_details["available_bones"] = _available_bone_names()
		clear()
		return _result(false, "MISSING_REQUIRED_EQUIPMENT_ANCHOR", failure_details)
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
	_head_clip_mesh = null
	_head_clip_material = null
	_head_clip_y = 0.0
	_head_clip_error = ""


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


func supports_body_region(region_id: String) -> bool:
	return region_id in COARSE_BODY_REGIONS


func resolve_body_region_visuals(
	_character_visual_root: Node,
	region_id: String
) -> Array[GeometryInstance3D]:
	var result: Array[GeometryInstance3D] = []
	if region_id not in COARSE_BODY_REGIONS:
		return result
	var body_mesh := _resolve_base_body_mesh()
	if body_mesh != null:
		result.append(body_mesh)
	return result


func resolve_body_region_suppression_targets(
	_character_visual_root: Node,
	region_id: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if region_id not in COARSE_BODY_REGIONS:
		return result
	var body_mesh := _resolve_base_body_mesh()
	if body_mesh == null:
		_head_clip_error = "HEAD_CLIP_BODY_MESH_NOT_FOUND"
		return result
	var clip_result := _ensure_head_clip_material(body_mesh)
	if not bool(clip_result.get("success", false)):
		_head_clip_error = String(clip_result.get("code", "HEAD_CLIP_SETUP_FAILED"))
		return result
	result.append({
		"key": "material_clip:%d" % body_mesh.get_instance_id(),
		"mode": BODY_SUPPRESSION_MATERIAL_OVERRIDE,
		"node": body_mesh,
		"material_override": _head_clip_material,
		"debug": {
			"kind": "QUATERNIUS_FUSED_BODY_HEAD_CLIP",
			"clip_local_y": _head_clip_y,
			"mesh_name": String(body_mesh.name),
		},
	})
	return result


func resolve_pose_skeleton(_character_visual_root: Node) -> Skeleton3D:
	return _target_skeleton if _target_skeleton != null and is_instance_valid(_target_skeleton) else null


func resolve_skinned_parent(_character_visual_root: Node) -> Node3D:
	if _presenter == null:
		return null
	var yaw_root := _find_descendant_named(_presenter, "AvatarYawRoot")
	if yaw_root is Node3D:
		return yaw_root as Node3D
	return _presenter as Node3D if _presenter is Node3D else null


func create_report() -> Dictionary:
	var resolved: Dictionary = {}
	for anchor_id in SEMANTIC_BONE_CANDIDATES.keys():
		if _resolved_bones.has(anchor_id):
			resolved[anchor_id] = String(_resolved_bones[anchor_id])
		elif _fallback_anchors.has(anchor_id):
			var node = _fallback_anchors[anchor_id]
			resolved[anchor_id] = String(node.name) if node is Node else ""
	return {
		# Keep the accepted CH7 report contract stable. CH7.8 adds optional
		# capability fields, but that is not a breaking schema change.
		"schema": "planet_simulator.quaternius_equipment_rig_adapter.v2",
		"rig_profile_id": rig_profile_id,
		"mode": _mode,
		"resolved_anchors": resolved,
		"target_skeleton": _target_skeleton != null,
		"bone_count": _target_skeleton.get_bone_count() if _target_skeleton != null else 0,
		"skinned_parent_ready": resolve_skinned_parent(_presenter) != null,
		"coarse_body_regions": COARSE_BODY_REGIONS.duplicate(),
		"body_suppression_mode": "MATERIAL_HEAD_CLIP",
		"head_clip_ready": _head_clip_material != null,
		"head_clip_mesh": String(_head_clip_mesh.name) if _head_clip_mesh != null else "",
		"head_clip_local_y": _head_clip_y,
		"head_clip_error": _head_clip_error,
		"attachment_count": _attachments.size(),
		"moves_gameplay_body": false,
		"reads_input": false,
		"owns_network_state": false,
	}


func _ensure_head_clip_material(body_mesh: MeshInstance3D) -> Dictionary:
	if _head_clip_material != null and _head_clip_mesh == body_mesh:
		return _result(true, CharacterEquipmentDomain.RESULT_OK, {
			"material": _head_clip_material,
			"clip_local_y": _head_clip_y,
		})
	_head_clip_y = _resolve_head_clip_y(body_mesh)
	var clip_result: Dictionary = HeadClipMaterial.create_from_mesh(body_mesh, _head_clip_y)
	if not bool(clip_result.get("success", false)):
		return clip_result
	var details: Dictionary = clip_result.get("details", {})
	var material = details.get("material")
	if not material is ShaderMaterial:
		return _result(false, "HEAD_CLIP_MATERIAL_NOT_SHADER")
	_head_clip_mesh = body_mesh
	_head_clip_material = material as ShaderMaterial
	_head_clip_error = ""
	return clip_result


func _resolve_head_clip_y(body_mesh: MeshInstance3D) -> float:
	var eyes := _resolve_base_eye_mesh()
	if eyes != null:
		return eyes.get_aabb().position.y - HEAD_CLIP_BELOW_EYES_M
	var body_aabb := body_mesh.get_aabb()
	return body_aabb.position.y + body_aabb.size.y * HEAD_CLIP_FALLBACK_BODY_FRACTION


func _resolve_base_body_mesh() -> MeshInstance3D:
	if _head_clip_mesh != null and is_instance_valid(_head_clip_mesh):
		return _head_clip_mesh
	if _presenter == null:
		return null
	var model_root := _find_descendant_named(_presenter, "QuaterniusModel")
	if model_root == null:
		return null
	var meshes: Array[MeshInstance3D] = []
	_collect_base_model_meshes(model_root, meshes)
	var best: MeshInstance3D
	var best_score := -100000.0
	for mesh in meshes:
		var lower := String(mesh.name).to_lower()
		var score := mesh.get_aabb().size.length()
		if lower.contains("superhero") or lower.contains("superhero"):
			score += 1000.0
		if lower.contains("male") and not lower.contains("female"):
			score += 200.0
		for unwanted in ["eye", "eyebrow", "hair", "beard"]:
			if lower.contains(String(unwanted)):
				score -= 2000.0
		if score > best_score:
			best_score = score
			best = mesh
	return best


func _resolve_base_eye_mesh() -> MeshInstance3D:
	if _presenter == null:
		return null
	var model_root := _find_descendant_named(_presenter, "QuaterniusModel")
	if model_root == null:
		return null
	var meshes: Array[MeshInstance3D] = []
	_collect_base_model_meshes(model_root, meshes)
	for mesh in meshes:
		if String(mesh.name).to_lower() == "eyes":
			return mesh
	for mesh in meshes:
		if String(mesh.name).to_lower().contains("eye") and not String(mesh.name).to_lower().contains("eyebrow"):
			return mesh
	return null


func _collect_base_model_meshes(root: Node, output: Array[MeshInstance3D]) -> void:
	if root is BoneAttachment3D:
		return
	if root is MeshInstance3D:
		output.append(root as MeshInstance3D)
	for child in root.get_children():
		_collect_base_model_meshes(child, output)


func _resolve_skeleton_bones() -> void:
	var normalized_to_index: Dictionary = {}
	for index in range(_target_skeleton.get_bone_count()):
		var bone_name := String(_target_skeleton.get_bone_name(index))
		var normalized := _normalized_bone_name(bone_name)
		if not normalized_to_index.has(normalized):
			normalized_to_index[normalized] = index

	for raw_anchor_id in SEMANTIC_BONE_CANDIDATES.keys():
		var anchor_id := String(raw_anchor_id)
		var resolved_index := _find_bone_by_candidates(normalized_to_index, SEMANTIC_BONE_CANDIDATES[anchor_id])
		if resolved_index >= 0:
			_resolved_bones[anchor_id] = String(_target_skeleton.get_bone_name(resolved_index))

	var head_index := _resolved_bone_index("body.head")
	if not _resolved_bones.has("gear.back") and head_index >= 0:
		var back_index := _find_back_bone_from_head(head_index)
		if back_index >= 0:
			_resolved_bones["gear.back"] = String(_target_skeleton.get_bone_name(back_index))

	if not _resolved_bones.has("body.root"):
		var root_index := _find_root_bone(head_index)
		if root_index >= 0:
			_resolved_bones["body.root"] = String(_target_skeleton.get_bone_name(root_index))


func _find_bone_by_candidates(normalized_to_index: Dictionary, candidates: Array) -> int:
	for raw_candidate in candidates:
		var candidate := _normalized_bone_name(String(raw_candidate))
		if normalized_to_index.has(candidate):
			return int(normalized_to_index[candidate])

	for raw_candidate in candidates:
		var candidate := _normalized_bone_name(String(raw_candidate))
		for raw_normalized in normalized_to_index.keys():
			var normalized := String(raw_normalized)
			if normalized.ends_with(candidate):
				return int(normalized_to_index[raw_normalized])
	return -1


func _find_back_bone_from_head(head_index: int) -> int:
	var current := _target_skeleton.get_bone_parent(head_index)
	while current >= 0:
		var normalized := _normalized_bone_name(String(_target_skeleton.get_bone_name(current)))
		for token in BACK_BONE_TOKENS:
			if normalized.contains(String(token)):
				return current
		current = _target_skeleton.get_bone_parent(current)
	return -1


func _find_root_bone(start_index: int) -> int:
	if _target_skeleton == null or _target_skeleton.get_bone_count() == 0:
		return -1
	if start_index >= 0:
		var current := start_index
		while _target_skeleton.get_bone_parent(current) >= 0:
			current = _target_skeleton.get_bone_parent(current)
		return current
	for index in range(_target_skeleton.get_bone_count()):
		if _target_skeleton.get_bone_parent(index) < 0:
			return index
	return 0


func _resolved_bone_index(anchor_id: String) -> int:
	if _target_skeleton == null or not _resolved_bones.has(anchor_id):
		return -1
	return _target_skeleton.find_bone(StringName(_resolved_bones[anchor_id]))


func _missing_required_anchors() -> Array[String]:
	var result: Array[String] = []
	for raw_anchor in REQUIRED_ANCHORS:
		var anchor_id := String(raw_anchor)
		if not supports_anchor(anchor_id):
			result.append(anchor_id)
	return result


func _available_bone_names() -> Array[String]:
	var result: Array[String] = []
	if _target_skeleton == null:
		return result
	for index in range(_target_skeleton.get_bone_count()):
		result.append(String(_target_skeleton.get_bone_name(index)))
	return result


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
	for token in ["_", "-", " ", "/", ".", ":", "|"]:
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
