class_name NativeSkeletonProfiledFirstPersonHandVisualProvider
extends "res://scripts/characters/presentation/profiled_skinned_first_person_hand_visual_provider.gd"

const MODE := "RESOURCE_NATIVE_SKELETON_RETARGETED"
const DRIVER := "NATIVE_SKELETON_POSE"
const SOURCE_NATIVE_BIND_SPACE := "SOURCE_NATIVE_BIND_SPACE"
const CANONICAL_FINGER_BONES: Array[String] = [
	"ThumbProximal", "ThumbMiddle", "ThumbDistal",
	"IndexProximal", "IndexMiddle", "IndexDistal",
	"MiddleProximal", "MiddleMiddle", "MiddleDistal",
	"RingProximal", "RingMiddle", "RingDistal",
	"PinkyProximal", "PinkyMiddle", "PinkyDistal",
]

var _native_root: Node3D
var _native_skeleton: Skeleton3D
var _canonical_skeleton: Skeleton3D
var _native_mesh: MeshInstance3D
var _normalized_hand := ""
var _pose_pairs: Array[Dictionary] = []
var _sync_count := 0
var _last_driven_bone_count := 0
var _last_report: Dictionary = {}


func setup_profiled(
	p_scene: PackedScene,
	p_profile: Dictionary,
	p_profile_path: String = "",
	p_resource_path: String = ""
) -> Dictionary:
	var validation: Dictionary = ProfileType.validate(p_profile)
	if not bool(validation.get("success", false)):
		return validation
	if p_scene == null:
		return _failure("FPE_HAND_NATIVE_PROFILE_SCENE_REQUIRED")
	var provider_kind := String(p_profile.get("provider", "")).strip_edges().to_upper()
	if provider_kind != ProfileType.PROVIDER_SKINNED_NAMED_BIND:
		return _failure("FPE_HAND_NATIVE_PROFILE_PROVIDER_UNSUPPORTED", {"provider": provider_kind})
	var retarget := Dictionary(p_profile.get("retarget", {}))
	var runtime_driver := String(retarget.get("runtime_driver", "")).strip_edges().to_upper()
	if runtime_driver != DRIVER:
		return _failure("FPE_HAND_NATIVE_PROFILE_DRIVER_REQUIRED", {
			"actual": runtime_driver,
			"required": DRIVER,
		})
	var rest_policy := String(retarget.get("rest_space_policy", "")).strip_edges().to_upper()
	if rest_policy != SOURCE_NATIVE_BIND_SPACE:
		return _failure("FPE_HAND_NATIVE_PROFILE_BIND_SPACE_REQUIRED", {
			"actual": rest_policy,
			"required": SOURCE_NATIVE_BIND_SPACE,
		})
	var by_hand_value: Variant = retarget.get("bone_map_by_hand", {})
	if not by_hand_value is Dictionary or Dictionary(by_hand_value).is_empty():
		return _failure("FPE_HAND_NATIVE_PROFILE_BONE_MAP_BY_HAND_REQUIRED")

	hand_asset_profile = p_profile.duplicate(true)
	hand_asset_profile_path = p_profile_path.strip_edges()
	_source_scene = p_scene
	_source_resource_path = p_resource_path.strip_edges()
	return _success({
		"profile_id": String(hand_asset_profile.get("profile_id", "")),
		"profile_path": hand_asset_profile_path,
		"resource_path": _source_resource_path,
		"portable_profile": true,
		"runtime_driver": DRIVER,
		"source_native_bind_space": true,
	})


func install_visuals(
	target_skeleton: Skeleton3D,
	hand_id: String,
	viewmodel_layer_index: int
) -> Dictionary:
	if _source_scene == null or hand_asset_profile.is_empty():
		return _failure("FPE_HAND_NATIVE_PROFILE_NOT_CONFIGURED")
	if target_skeleton == null:
		return _failure("FPE_HAND_NATIVE_CANONICAL_SKELETON_REQUIRED")
	var normalized_hand := hand_id.strip_edges().to_lower()
	if normalized_hand not in ["left", "right"]:
		return _failure("FPE_HAND_NATIVE_INVALID_HAND", {"hand_id": hand_id})
	if viewmodel_layer_index < 1 or viewmodel_layer_index > 20:
		return _failure("FPE_HAND_NATIVE_INVALID_LAYER", {"layer": viewmodel_layer_index})

	var source_instance: Node = _source_scene.instantiate()
	if not source_instance is Node3D:
		if source_instance != null:
			source_instance.free()
		return _failure("FPE_HAND_NATIVE_SOURCE_ROOT_NOT_NODE3D")
	var source_root := source_instance as Node3D
	var selection := Dictionary(hand_asset_profile.get("selection", {}))
	var selected := _select_skinned_meshes(source_root, selection, normalized_hand)
	if selected.size() != 1:
		source_root.free()
		return _failure("FPE_HAND_NATIVE_EXPECTS_ONE_SELECTED_SKINNED_MESH", {
			"selected_mesh_count": selected.size(),
			"hand_id": normalized_hand,
		})
	var source_mesh := selected[0]
	var source_skeleton := _resolve_source_skeleton(source_mesh)
	if source_skeleton == null:
		source_root.free()
		return _failure("FPE_HAND_NATIVE_SOURCE_SKELETON_REQUIRED")

	var layout := String(hand_asset_profile.get("hand_layout", "")).strip_edges().to_upper()
	var candidate: MeshInstance3D = source_mesh
	var kept_faces := 0
	var dropped_faces := 0
	var compact_bind_count := source_mesh.skin.get_bind_count() if source_mesh.skin != null else 0
	var source_mesh_transform := source_mesh.transform
	if layout == LAYOUT_PAIRED_SINGLE_MESH:
		var split_result := _split_paired_single_mesh(source_mesh, normalized_hand, selection)
		if not bool(split_result.get("success", false)):
			source_root.free()
			return split_result
		var split_details := Dictionary(split_result.get("details", {}))
		var candidate_value: Variant = split_details.get("mesh_instance")
		if not candidate_value is MeshInstance3D:
			source_root.free()
			return _failure("FPE_HAND_NATIVE_PAIRED_SPLIT_RESULT_INVALID")
		candidate = candidate_value as MeshInstance3D
		kept_faces = int(split_details.get("kept_faces", 0))
		dropped_faces = int(split_details.get("dropped_faces", 0))
		compact_bind_count = int(split_details.get("compact_bind_count", 0))
		var old_parent := source_mesh.get_parent()
		if old_parent != null:
			old_parent.remove_child(source_mesh)
		source_mesh.free()
		source_skeleton.add_child(candidate)
		candidate.transform = source_mesh_transform
		candidate.skeleton = NodePath("..")

	_configure_native_visual(candidate, viewmodel_layer_index)

	var retarget := Dictionary(hand_asset_profile.get("retarget", {}))
	var calibration_result := _auto_calibration_transform(
		candidate,
		source_root,
		target_skeleton,
		normalized_hand,
		retarget
	)
	if not bool(calibration_result.get("success", false)):
		source_root.free()
		return calibration_result
	var calibration_details := Dictionary(calibration_result.get("details", {}))
	var calibration := calibration_details.get("transform", Transform3D.IDENTITY) as Transform3D
	var presentation := _profile_transform(Dictionary(hand_asset_profile.get("presentation", {})))
	source_root.transform = presentation * calibration

	var pair_result := _build_pose_pairs(source_skeleton, target_skeleton, normalized_hand, retarget)
	if not bool(pair_result.get("success", false)):
		source_root.free()
		return pair_result

	target_skeleton.add_child(source_root)
	_native_root = source_root
	_native_skeleton = source_skeleton
	_canonical_skeleton = target_skeleton
	_native_mesh = candidate
	_normalized_hand = normalized_hand
	_sync_count = 0
	_last_driven_bone_count = 0
	_sync_pose_from_canonical_internal()

	_last_report = {
		"schema": "planet_simulator.fpe_native_skeleton_hand_visual_provider.v1",
		"provider_id": String(hand_asset_profile.get("profile_id", "native_profiled_hand")),
		"mode": MODE,
		"compatible_skeleton_schema": SKELETON_SCHEMA,
		"runtime_driver": DRIVER,
		"rest_space_policy": SOURCE_NATIVE_BIND_SPACE,
		"resource_path": _source_resource_path,
		"hand_id": normalized_hand,
		"installed_visual_count": 1,
		"skinned_mesh_count": 1,
		"paired_single_mesh_split": layout == LAYOUT_PAIRED_SINGLE_MESH,
		"kept_faces": kept_faces,
		"dropped_faces": dropped_faces,
		"compact_bind_count": compact_bind_count,
		"source_skin_preserved": true,
		"source_bind_poses_preserved": true,
		"source_skeleton_preserved": true,
		"canonical_skin_rebind": false,
		"native_pose_pair_count": _pose_pairs.size(),
		"native_pose_sync_count": _sync_count,
		"last_driven_bone_count": _last_driven_bone_count,
		"calibration_scale": float(calibration_details.get("uniform_scale", 1.0)),
		"portable_profile": true,
		"profile_id": String(hand_asset_profile.get("profile_id", "")),
		"profile_path": hand_asset_profile_path,
		"source_license": String(Dictionary(hand_asset_profile.get("license", {})).get("spdx", "")),
		"profiled_external_asset": bool(Dictionary(hand_asset_profile.get("asset", {})).get("external", false)),
		"bone_driven": true,
		"resource_backed": true,
		"retargeted": true,
		"substitutable": true,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}
	return _success({
		"visuals": [candidate],
		"report": _last_report.duplicate(true),
	})


func sync_pose_from_canonical(canonical_skeleton: Skeleton3D, hand_id: String) -> Dictionary:
	if _native_skeleton == null or not is_instance_valid(_native_skeleton):
		return _failure("FPE_HAND_NATIVE_SKELETON_NOT_INSTALLED")
	if canonical_skeleton == null or canonical_skeleton != _canonical_skeleton:
		return _failure("FPE_HAND_NATIVE_CANONICAL_SKELETON_MISMATCH")
	if hand_id.strip_edges().to_lower() != _normalized_hand:
		return _failure("FPE_HAND_NATIVE_HAND_MISMATCH", {"hand_id": hand_id})
	return _sync_pose_from_canonical_internal()


func create_report(installed_visual_count: int = 1) -> Dictionary:
	var report := _last_report.duplicate(true)
	if report.is_empty():
		report = {
			"schema": "planet_simulator.fpe_native_skeleton_hand_visual_provider.v1",
			"provider_id": String(hand_asset_profile.get("profile_id", "native_profiled_hand")),
			"mode": MODE,
			"runtime_driver": DRIVER,
			"rest_space_policy": SOURCE_NATIVE_BIND_SPACE,
			"installed_visual_count": installed_visual_count,
			"presentation_only": true,
			"owns_item_state": false,
			"owns_network_state": false,
			"owns_gameplay_transform": false,
		}
	report["native_pose_sync_count"] = _sync_count
	report["last_driven_bone_count"] = _last_driven_bone_count
	report["native_pose_pair_count"] = _pose_pairs.size()
	return report


func _build_pose_pairs(
	source_skeleton: Skeleton3D,
	target_skeleton: Skeleton3D,
	hand_id: String,
	retarget: Dictionary
) -> Dictionary:
	_pose_pairs.clear()
	var effective := _effective_bone_map(retarget, hand_id)
	for source_name_value in effective.keys():
		var source_name := String(source_name_value)
		var canonical_name := String(effective.get(source_name_value, ""))
		if canonical_name not in CANONICAL_FINGER_BONES:
			continue
		var source_index := source_skeleton.find_bone(source_name)
		var canonical_index := target_skeleton.find_bone(canonical_name)
		if source_index < 0 or canonical_index < 0:
			continue
		var source_rest_basis := source_skeleton.get_bone_rest(source_index).basis.orthonormalized()
		var canonical_rest_basis := target_skeleton.get_bone_rest(canonical_index).basis.orthonormalized()
		var source_to_canonical := canonical_rest_basis.inverse() * source_rest_basis
		_pose_pairs.append({
			"source_name": source_name,
			"canonical_name": canonical_name,
			"source_index": source_index,
			"canonical_index": canonical_index,
			"source_to_canonical": source_to_canonical,
		})
	if _pose_pairs.size() != 15:
		return _failure("FPE_HAND_NATIVE_FINGER_MAPPING_INCOMPLETE", {
			"hand_id": hand_id,
			"mapped_finger_bones": _pose_pairs.size(),
			"required": 15,
		})
	return _success({"pose_pair_count": _pose_pairs.size()})


func _sync_pose_from_canonical_internal() -> Dictionary:
	if _native_skeleton == null or _canonical_skeleton == null:
		return _failure("FPE_HAND_NATIVE_SYNC_NOT_READY")
	var driven := 0
	for pair in _pose_pairs:
		var source_index := int(pair.get("source_index", -1))
		var canonical_index := int(pair.get("canonical_index", -1))
		var alignment_value: Variant = pair.get("source_to_canonical", Basis.IDENTITY)
		if source_index < 0 or canonical_index < 0 or not alignment_value is Basis:
			continue
		var alignment := alignment_value as Basis
		var canonical_delta := Basis(_canonical_skeleton.get_bone_pose_rotation(canonical_index))
		var source_delta := alignment.inverse() * canonical_delta * alignment
		_native_skeleton.set_bone_pose_rotation(
			source_index,
			source_delta.orthonormalized().get_rotation_quaternion()
		)
		driven += 1
	_sync_count += 1
	_last_driven_bone_count = driven
	if not _last_report.is_empty():
		_last_report["native_pose_sync_count"] = _sync_count
		_last_report["last_driven_bone_count"] = _last_driven_bone_count
	return _success({
		"sync_count": _sync_count,
		"driven_bone_count": driven,
	})


func _configure_native_visual(visual: MeshInstance3D, viewmodel_layer_index: int) -> void:
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.layers = 0
	visual.set_layer_mask_value(viewmodel_layer_index, true)
