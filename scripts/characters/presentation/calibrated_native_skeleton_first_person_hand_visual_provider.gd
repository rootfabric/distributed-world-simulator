class_name CalibratedNativeSkeletonFirstPersonHandVisualProvider
extends "res://scripts/characters/presentation/native_skeleton_profiled_first_person_hand_visual_provider.gd"

const POSE_CALIBRATION_MODE := "AUTO_CHAIN_PALM_V1"
const ROOT_ORIENTATION_PRESERVE := "PRESERVE_SOURCE_BASIS"
const ROOT_ORIENTATION_ALIGN := "ALIGN_SOURCE_ANCHOR_TO_TARGET"

var _calibration_report: Dictionary = {}


func install_visuals(
	target_skeleton: Skeleton3D,
	hand_id: String,
	viewmodel_layer_index: int
) -> Dictionary:
	var inherited: Dictionary = super.install_visuals(target_skeleton, hand_id, viewmodel_layer_index)
	if not bool(inherited.get("success", false)):
		return inherited
	var root_result := _apply_calibrated_native_root_transform(target_skeleton, hand_id)
	if not bool(root_result.get("success", false)):
		_cleanup_native_root()
		return root_result
	_calibration_report = Dictionary(root_result.get("details", {})).duplicate(true)
	var sync_result := _sync_pose_from_canonical_internal()
	if not bool(sync_result.get("success", false)):
		_cleanup_native_root()
		return sync_result
	_update_native_report_calibration()
	return _success({
		"visuals": [_native_mesh],
		"report": create_live_report(1),
	})


func _build_pose_pairs(
	source_skeleton: Skeleton3D,
	target_skeleton: Skeleton3D,
	hand_id: String,
	retarget: Dictionary
) -> Dictionary:
	_pose_pairs.clear()
	var calibration := Dictionary(retarget.get("native_pose_calibration", {}))
	var mode := String(calibration.get("mode", "")).strip_edges().to_upper()
	if mode != POSE_CALIBRATION_MODE:
		return _failure("FPE_HAND_NATIVE_POSE_CALIBRATION_MODE_REQUIRED", {
			"actual": mode,
			"required": POSE_CALIBRATION_MODE,
		})
	var effective := _effective_bone_map(retarget, hand_id)
	var palm_result := _build_source_palm_frame(source_skeleton, hand_id, retarget, effective)
	if not bool(palm_result.get("success", false)):
		return palm_result
	var palm_details := Dictionary(palm_result.get("details", {}))
	var palm_normal := _vector3_from_report(palm_details.get("normal", []), Vector3.ZERO)
	if palm_normal.length_squared() <= 0.000001:
		return _failure("FPE_HAND_NATIVE_POSE_PALM_NORMAL_DEGENERATE")

	for source_name_value in effective.keys():
		var source_name := String(source_name_value)
		var canonical_name := String(effective.get(source_name_value, ""))
		if canonical_name not in CANONICAL_FINGER_BONES:
			continue
		var source_index := source_skeleton.find_bone(source_name)
		var canonical_index := target_skeleton.find_bone(canonical_name)
		if source_index < 0 or canonical_index < 0:
			continue
		var finger := _finger_from_canonical_name(canonical_name)
		var config := _pose_config_for_bone(calibration, hand_id, finger, source_name)
		var axis_result := _auto_pose_axes(
			source_skeleton,
			source_index,
			canonical_name,
			effective,
			palm_normal
		)
		if not bool(axis_result.get("success", false)):
			return axis_result
		var axis_details := Dictionary(axis_result.get("details", {}))
		var auto_curl_axis := _vector3_from_report(axis_details.get("curl_axis_local", []), Vector3.RIGHT)
		var auto_opposition_axis := _vector3_from_report(axis_details.get("opposition_axis_local", []), Vector3.UP)
		var curl_axis := _axis_from_config(config.get("curl_axis", []), auto_curl_axis)
		var opposition_axis := _axis_from_config(config.get("opposition_axis", []), auto_opposition_axis)
		var base_rotation_deg := _vector3_from_report(config.get("base_rotation_degrees", []), Vector3.ZERO)
		_pose_pairs.append({
			"source_name": source_name,
			"canonical_name": canonical_name,
			"source_index": source_index,
			"canonical_index": canonical_index,
			"finger": finger,
			"curl_axis": curl_axis,
			"opposition_axis": opposition_axis,
			"curl_sign": float(config.get("curl_sign", 1.0)),
			"curl_scale": float(config.get("curl_scale", 1.0)),
			"opposition_sign": float(config.get("opposition_sign", 1.0)),
			"opposition_scale": float(config.get("opposition_scale", 1.0)),
			"max_abs_curl_deg": maxf(float(config.get("max_abs_curl_deg", 105.0)), 0.0),
			"max_abs_opposition_deg": maxf(float(config.get("max_abs_opposition_deg", 70.0)), 0.0),
			"base_rotation": Basis.from_euler(Vector3(
				deg_to_rad(base_rotation_deg.x),
				deg_to_rad(base_rotation_deg.y),
				deg_to_rad(base_rotation_deg.z)
			)).get_rotation_quaternion(),
		})
	if _pose_pairs.size() != 15:
		return _failure("FPE_HAND_NATIVE_FINGER_MAPPING_INCOMPLETE", {
			"hand_id": hand_id,
			"mapped_finger_bones": _pose_pairs.size(),
			"required": 15,
		})
	return _success({
		"pose_pair_count": _pose_pairs.size(),
		"pose_calibration_mode": mode,
		"palm_frame": palm_details,
	})


func _sync_pose_from_canonical_internal() -> Dictionary:
	if _native_skeleton == null or _canonical_skeleton == null:
		return _failure("FPE_HAND_NATIVE_SYNC_NOT_READY")
	var driven := 0
	var max_native_angle_deg := 0.0
	for pair in _pose_pairs:
		var source_index := int(pair.get("source_index", -1))
		var canonical_index := int(pair.get("canonical_index", -1))
		if source_index < 0 or canonical_index < 0:
			continue
		var canonical_basis := Basis(_canonical_skeleton.get_bone_pose_rotation(canonical_index))
		var canonical_euler := canonical_basis.get_euler()
		var curl := clampf(
			canonical_euler.x * float(pair.get("curl_sign", 1.0)) * float(pair.get("curl_scale", 1.0)),
			-deg_to_rad(float(pair.get("max_abs_curl_deg", 105.0))),
			deg_to_rad(float(pair.get("max_abs_curl_deg", 105.0)))
		)
		var opposition := clampf(
			canonical_euler.y * float(pair.get("opposition_sign", 1.0)) * float(pair.get("opposition_scale", 1.0)),
			-deg_to_rad(float(pair.get("max_abs_opposition_deg", 70.0))),
			deg_to_rad(float(pair.get("max_abs_opposition_deg", 70.0)))
		)
		var curl_axis := pair.get("curl_axis", Vector3.RIGHT) as Vector3
		var opposition_axis := pair.get("opposition_axis", Vector3.UP) as Vector3
		var base_rotation := pair.get("base_rotation", Quaternion.IDENTITY) as Quaternion
		var curl_rotation := Quaternion(curl_axis.normalized(), curl) if curl_axis.length_squared() > 0.000001 else Quaternion.IDENTITY
		var opposition_rotation := Quaternion(opposition_axis.normalized(), opposition) if opposition_axis.length_squared() > 0.000001 else Quaternion.IDENTITY
		var source_rotation := (base_rotation * opposition_rotation * curl_rotation).normalized()
		_native_skeleton.set_bone_pose_rotation(source_index, source_rotation)
		max_native_angle_deg = maxf(max_native_angle_deg, rad_to_deg(Quaternion.IDENTITY.angle_to(source_rotation)))
		driven += 1
	_sync_count += 1
	_last_driven_bone_count = driven
	if not _native_report.is_empty():
		_native_report["native_pose_sync_count"] = _sync_count
		_native_report["last_driven_bone_count"] = _last_driven_bone_count
		_native_report["max_native_pose_angle_deg"] = max_native_angle_deg
	return _success({
		"sync_count": _sync_count,
		"driven_bone_count": driven,
		"max_native_pose_angle_deg": max_native_angle_deg,
	})


func create_live_report(installed_visual_count: int = 1) -> Dictionary:
	var report := super.create_live_report(installed_visual_count)
	for key in _calibration_report.keys():
		report[key] = _calibration_report.get(key)
	report["pose_calibration_mode"] = POSE_CALIBRATION_MODE
	report["axis_calibrated_native_pose"] = true
	report["open_pose_preserves_source_rest"] = true
	return report


func _apply_calibrated_native_root_transform(
	target_skeleton: Skeleton3D,
	hand_id: String
) -> Dictionary:
	if _native_root == null or _native_skeleton == null:
		return _failure("FPE_HAND_NATIVE_ROOT_CALIBRATION_NOT_READY")
	var retarget := Dictionary(hand_asset_profile.get("retarget", {}))
	var calibration := Dictionary(retarget.get("auto_calibration", {}))
	var source_anchor_by_hand := Dictionary(calibration.get("source_anchor_by_hand", {}))
	var source_reference_by_hand := Dictionary(calibration.get("source_scale_reference_by_hand", {}))
	var source_anchor_name := String(source_anchor_by_hand.get(hand_id, ""))
	var source_reference_name := String(source_reference_by_hand.get(hand_id, ""))
	var target_anchor_name := String(calibration.get("target_anchor", "Palm"))
	var target_reference_name := String(calibration.get("target_scale_reference", "MiddleProximal"))
	var source_anchor_index := _native_skeleton.find_bone(source_anchor_name)
	var source_reference_index := _native_skeleton.find_bone(source_reference_name)
	var target_anchor_index := target_skeleton.find_bone(target_anchor_name)
	var target_reference_index := target_skeleton.find_bone(target_reference_name)
	if source_anchor_index < 0 or source_reference_index < 0 or target_anchor_index < 0 or target_reference_index < 0:
		return _failure("FPE_HAND_NATIVE_ROOT_CALIBRATION_ANCHOR_MISSING", {
			"source_anchor": source_anchor_name,
			"source_reference": source_reference_name,
			"target_anchor": target_anchor_name,
			"target_reference": target_reference_name,
		})
	var source_skeleton_to_root := _relative_transform_to_root(_native_skeleton, _native_root)
	var source_anchor := source_skeleton_to_root * _native_skeleton.get_bone_global_rest(source_anchor_index)
	var source_reference := source_skeleton_to_root * _native_skeleton.get_bone_global_rest(source_reference_index)
	var target_anchor := target_skeleton.get_bone_global_rest(target_anchor_index)
	var target_reference := target_skeleton.get_bone_global_rest(target_reference_index)
	var source_span := source_anchor.origin.distance_to(source_reference.origin)
	var target_span := target_anchor.origin.distance_to(target_reference.origin)
	if source_span <= 0.000001 or target_span <= 0.000001:
		return _failure("FPE_HAND_NATIVE_ROOT_CALIBRATION_SCALE_DEGENERATE")
	var uniform_scale := target_span / source_span * float(calibration.get("uniform_scale_multiplier", 1.0))
	var orientation_mode := String(calibration.get("orientation_mode", ROOT_ORIENTATION_PRESERVE)).strip_edges().to_upper()
	var calibrated_basis := Basis.IDENTITY.scaled(Vector3.ONE * uniform_scale)
	if orientation_mode == ROOT_ORIENTATION_ALIGN:
		calibrated_basis = (
			target_anchor.basis.orthonormalized()
			* source_anchor.basis.orthonormalized().inverse()
		).scaled(Vector3.ONE * uniform_scale)
	elif orientation_mode != ROOT_ORIENTATION_PRESERVE:
		return _failure("FPE_HAND_NATIVE_ROOT_ORIENTATION_MODE_UNSUPPORTED", {"orientation_mode": orientation_mode})
	var calibrated_origin := target_anchor.origin - calibrated_basis * source_anchor.origin
	var calibration_transform := Transform3D(calibrated_basis, calibrated_origin)
	var presentation := _presentation_transform_for_hand(hand_id)
	_native_root.transform = presentation * calibration_transform
	return _success({
		"root_orientation_mode": orientation_mode,
		"root_calibration_scale": uniform_scale,
		"per_hand_presentation": true,
		"source_anchor": source_anchor_name,
		"source_reference": source_reference_name,
	})


func _presentation_transform_for_hand(hand_id: String) -> Transform3D:
	var presentation := Dictionary(hand_asset_profile.get("presentation", {}))
	var common := presentation.duplicate(true)
	common.erase("by_hand")
	var common_transform := _profile_transform(common)
	var by_hand_value: Variant = presentation.get("by_hand", {})
	if not by_hand_value is Dictionary:
		return common_transform
	var hand_value: Variant = Dictionary(by_hand_value).get(hand_id, {})
	if not hand_value is Dictionary:
		return common_transform
	return common_transform * _profile_transform(Dictionary(hand_value))


func _build_source_palm_frame(
	skeleton: Skeleton3D,
	hand_id: String,
	retarget: Dictionary,
	effective: Dictionary
) -> Dictionary:
	var calibration := Dictionary(retarget.get("auto_calibration", {}))
	var anchor_by_hand := Dictionary(calibration.get("source_anchor_by_hand", {}))
	var wrist_name := String(anchor_by_hand.get(hand_id, ""))
	var index_name := _source_name_for_canonical(effective, "IndexProximal")
	var middle_name := _source_name_for_canonical(effective, "MiddleProximal")
	var pinky_name := _source_name_for_canonical(effective, "PinkyProximal")
	var wrist_index := skeleton.find_bone(wrist_name)
	var index_index := skeleton.find_bone(index_name)
	var middle_index := skeleton.find_bone(middle_name)
	var pinky_index := skeleton.find_bone(pinky_name)
	if wrist_index < 0 or index_index < 0 or middle_index < 0 or pinky_index < 0:
		return _failure("FPE_HAND_NATIVE_POSE_PALM_FRAME_BONES_MISSING", {
			"wrist": wrist_name,
			"index": index_name,
			"middle": middle_name,
			"pinky": pinky_name,
		})
	var wrist := skeleton.get_bone_global_rest(wrist_index).origin
	var index_base := skeleton.get_bone_global_rest(index_index).origin
	var middle_base := skeleton.get_bone_global_rest(middle_index).origin
	var pinky_base := skeleton.get_bone_global_rest(pinky_index).origin
	var across := index_base - pinky_base
	var forward := middle_base - wrist
	if across.length_squared() <= 0.000001 or forward.length_squared() <= 0.000001:
		return _failure("FPE_HAND_NATIVE_POSE_PALM_FRAME_DEGENERATE")
	var normal := across.normalized().cross(forward.normalized()).normalized()
	if normal.length_squared() <= 0.000001:
		return _failure("FPE_HAND_NATIVE_POSE_PALM_NORMAL_DEGENERATE")
	return _success({
		"wrist": wrist_name,
		"index": index_name,
		"middle": middle_name,
		"pinky": pinky_name,
		"normal": [normal.x, normal.y, normal.z],
		"forward": [forward.normalized().x, forward.normalized().y, forward.normalized().z],
	})


func _auto_pose_axes(
	skeleton: Skeleton3D,
	source_index: int,
	canonical_name: String,
	effective: Dictionary,
	palm_normal: Vector3
) -> Dictionary:
	var source_global := skeleton.get_bone_global_rest(source_index)
	var direction := Vector3.ZERO
	var next_canonical := _next_canonical_bone(canonical_name)
	if not next_canonical.is_empty():
		var next_source := _source_name_for_canonical(effective, next_canonical)
		var next_index := skeleton.find_bone(next_source)
		if next_index >= 0:
			direction = skeleton.get_bone_global_rest(next_index).origin - source_global.origin
	if direction.length_squared() <= 0.000001:
		var parent_index := skeleton.get_bone_parent(source_index)
		if parent_index >= 0:
			direction = source_global.origin - skeleton.get_bone_global_rest(parent_index).origin
	if direction.length_squared() <= 0.000001:
		return _failure("FPE_HAND_NATIVE_POSE_FINGER_DIRECTION_DEGENERATE", {
			"bone": skeleton.get_bone_name(source_index),
		})
	var curl_axis_global := direction.normalized().cross(palm_normal.normalized()).normalized()
	if curl_axis_global.length_squared() <= 0.000001:
		return _failure("FPE_HAND_NATIVE_POSE_CURL_AXIS_DEGENERATE", {
			"bone": skeleton.get_bone_name(source_index),
		})
	var inverse_global_basis := source_global.basis.orthonormalized().inverse()
	var curl_axis_local := (inverse_global_basis * curl_axis_global).normalized()
	var opposition_axis_local := (inverse_global_basis * palm_normal.normalized()).normalized()
	return _success({
		"curl_axis_local": [curl_axis_local.x, curl_axis_local.y, curl_axis_local.z],
		"opposition_axis_local": [opposition_axis_local.x, opposition_axis_local.y, opposition_axis_local.z],
	})


func _pose_config_for_bone(
	calibration: Dictionary,
	hand_id: String,
	finger: String,
	source_name: String
) -> Dictionary:
	var result := Dictionary(calibration.get("default", {})).duplicate(true)
	var by_hand_value: Variant = calibration.get("by_hand", {})
	if by_hand_value is Dictionary:
		_merge_dictionary(result, Dictionary(Dictionary(by_hand_value).get(hand_id, {})))
	var by_finger_value: Variant = calibration.get("by_finger", {})
	if by_finger_value is Dictionary:
		_merge_dictionary(result, Dictionary(Dictionary(by_finger_value).get(finger, {})))
	var by_bone_value: Variant = calibration.get("by_bone", {})
	if by_bone_value is Dictionary:
		_merge_dictionary(result, Dictionary(Dictionary(by_bone_value).get(source_name, {})))
	return result


func _merge_dictionary(target: Dictionary, source: Dictionary) -> void:
	for key in source.keys():
		target[key] = source.get(key)


func _axis_from_config(value: Variant, fallback: Vector3) -> Vector3:
	var axis := _vector3_from_report(value, fallback)
	return axis.normalized() if axis.length_squared() > 0.000001 else fallback.normalized()


func _source_name_for_canonical(effective: Dictionary, canonical_name: String) -> String:
	for source_name in effective.keys():
		if String(effective.get(source_name, "")) == canonical_name:
			return String(source_name)
	return ""


func _next_canonical_bone(canonical_name: String) -> String:
	var index := CANONICAL_FINGER_BONES.find(canonical_name)
	if index < 0:
		return ""
	var segment := index % 3
	if segment >= 2:
		return ""
	return CANONICAL_FINGER_BONES[index + 1]


func _finger_from_canonical_name(canonical_name: String) -> String:
	var lower := canonical_name.to_lower()
	for finger in ["thumb", "index", "middle", "ring", "pinky"]:
		if lower.begins_with(finger):
			return finger
	return ""


func _vector3_from_report(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback


func _update_native_report_calibration() -> void:
	if _native_report.is_empty():
		return
	for key in _calibration_report.keys():
		_native_report[key] = _calibration_report.get(key)
	_native_report["pose_calibration_mode"] = POSE_CALIBRATION_MODE
	_native_report["axis_calibrated_native_pose"] = true
	_native_report["open_pose_preserves_source_rest"] = true


func _cleanup_native_root() -> void:
	if _native_root != null and is_instance_valid(_native_root):
		var parent := _native_root.get_parent()
		if parent != null:
			parent.remove_child(_native_root)
		_native_root.free()
	_native_root = null
	_native_skeleton = null
	_native_mesh = null
	_canonical_skeleton = null
