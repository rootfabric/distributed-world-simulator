class_name ResourceBackedFirstPersonHandVisualProvider
extends RefCounted

const ASSET_SCHEMA := "planet_simulator.fpe_hand_visual_asset.v1"
const SKELETON_SCHEMA := "planet_simulator.fpe_hand_skeleton.v1"
const MODE := "RESOURCE_BONE_ATTACHMENTS"
const REQUIRED_BONES: Array[String] = [
	"Palm",
	"ThumbProximal", "ThumbMiddle", "ThumbDistal",
	"IndexProximal", "IndexMiddle", "IndexDistal",
	"MiddleProximal", "MiddleMiddle", "MiddleDistal",
	"RingProximal", "RingMiddle", "RingDistal",
	"PinkyProximal", "PinkyMiddle", "PinkyDistal",
]

var packed_scene: PackedScene
var resource_path := ""
var provider_id := ""
var _last_report: Dictionary = {}


func setup(p_scene: PackedScene, p_resource_path: String = "") -> Dictionary:
	if p_scene == null:
		return _failure("FPE_S7_HAND_VISUAL_SCENE_REQUIRED")
	packed_scene = p_scene
	resource_path = p_resource_path.strip_edges()
	provider_id = resource_path if not resource_path.is_empty() else "packed_scene_hand_visual"
	return _success({
		"resource_path": resource_path,
		"provider_id": provider_id,
		"asset_schema": ASSET_SCHEMA,
	})


func install_visuals(
	skeleton: Skeleton3D,
	hand_id: String,
	viewmodel_layer_index: int
) -> Dictionary:
	if packed_scene == null:
		return _failure("FPE_S7_HAND_VISUAL_PROVIDER_NOT_CONFIGURED")
	if skeleton == null:
		return _failure("FPE_S7_HAND_VISUAL_SKELETON_REQUIRED")
	var normalized_hand := hand_id.strip_edges().to_lower()
	if normalized_hand not in ["left", "right"]:
		return _failure("FPE_S7_HAND_VISUAL_INVALID_HAND", {"hand_id": hand_id})
	if viewmodel_layer_index < 1 or viewmodel_layer_index > 20:
		return _failure("FPE_S7_HAND_VISUAL_INVALID_LAYER", {"layer": viewmodel_layer_index})

	for bone_name in REQUIRED_BONES:
		if skeleton.find_bone(bone_name) < 0:
			return _failure("FPE_S7_HAND_VISUAL_SKELETON_INCOMPATIBLE", {
				"missing_bone": bone_name,
				"required_schema": SKELETON_SCHEMA,
			})

	var instance: Node = packed_scene.instantiate()
	if not instance is Node3D:
		if instance != null:
			instance.free()
		return _failure("FPE_S7_HAND_VISUAL_ROOT_MUST_BE_NODE3D")
	var asset_root := instance as Node3D
	var asset_schema := String(asset_root.get_meta("fpe_hand_visual_schema", ""))
	var skeleton_schema := String(asset_root.get_meta("fpe_compatible_skeleton_schema", ""))
	var asset_hand := String(asset_root.get_meta("fpe_hand", "both")).strip_edges().to_lower()
	var asset_provider_id := String(asset_root.get_meta("fpe_provider_id", provider_id)).strip_edges()
	if asset_schema != ASSET_SCHEMA:
		asset_root.free()
		return _failure("FPE_S7_HAND_VISUAL_ASSET_SCHEMA_MISMATCH", {
			"actual": asset_schema,
			"required": ASSET_SCHEMA,
		})
	if skeleton_schema != SKELETON_SCHEMA:
		asset_root.free()
		return _failure("FPE_S7_HAND_VISUAL_SKELETON_SCHEMA_MISMATCH", {
			"actual": skeleton_schema,
			"required": SKELETON_SCHEMA,
		})
	if asset_hand not in ["both", normalized_hand]:
		asset_root.free()
		return _failure("FPE_S7_HAND_VISUAL_HAND_MISMATCH", {
			"asset_hand": asset_hand,
			"requested_hand": normalized_hand,
		})

	var attachments: Array[BoneAttachment3D] = []
	for child in asset_root.get_children():
		if child is BoneAttachment3D:
			attachments.append(child as BoneAttachment3D)
	if attachments.is_empty():
		asset_root.free()
		return _failure("FPE_S7_HAND_VISUAL_NO_BONE_ATTACHMENTS")

	var visuals: Array[MeshInstance3D] = []
	for attachment in attachments:
		var bone_name := String(attachment.bone_name).strip_edges()
		if bone_name.is_empty() or skeleton.find_bone(bone_name) < 0:
			asset_root.free()
			return _failure("FPE_S7_HAND_VISUAL_ATTACHMENT_BONE_INVALID", {
				"attachment": attachment.name,
				"bone_name": bone_name,
			})
		_collect_meshes(attachment, visuals)
	if visuals.is_empty():
		asset_root.free()
		return _failure("FPE_S7_HAND_VISUAL_NO_MESHES")

	for visual in visuals:
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.layers = 0
		visual.set_layer_mask_value(viewmodel_layer_index, true)

	# The authored contract is deliberately narrow in S7: direct
	# BoneAttachment3D children are moved onto the canonical pose skeleton.
	# Their local transforms and child mesh hierarchy are preserved.
	for attachment in attachments:
		asset_root.remove_child(attachment)
		skeleton.add_child(attachment)
	asset_root.free()

	provider_id = asset_provider_id if not asset_provider_id.is_empty() else provider_id
	_last_report = create_report(visuals.size(), attachments.size(), normalized_hand)
	return _success({
		"visuals": visuals,
		"report": _last_report.duplicate(true),
	})


func create_report(
	installed_visual_count: int = 0,
	attachment_count: int = 0,
	hand_id: String = ""
) -> Dictionary:
	return {
		"schema": "planet_simulator.fpe_resource_hand_visual_provider.v1",
		"provider_id": provider_id,
		"mode": MODE,
		"asset_schema": ASSET_SCHEMA,
		"compatible_skeleton_schema": SKELETON_SCHEMA,
		"resource_path": resource_path,
		"hand_id": hand_id,
		"installed_visual_count": installed_visual_count,
		"bone_attachment_count": attachment_count,
		"bone_driven": true,
		"resource_backed": true,
		"substitutable": true,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func _collect_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			output.append(child as MeshInstance3D)
		_collect_meshes(child, output)


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
