class_name CalibratedNativeSkeletonFirstPersonHandVisualProviderFix2
extends "res://scripts/characters/presentation/calibrated_native_skeleton_first_person_hand_visual_provider.gd"

const PoseCatalogType = preload("res://scripts/characters/presentation/first_person_hand_pose_catalog.gd")
const REFERENCE_POSE := "open"

var _pose_context_id := ""
var _open_pose_cache: Dictionary = {}


func set_canonical_pose_context(pose_id: String) -> void:
	_pose_context_id = pose_id.strip_edges().to_lower()


func _sync_pose_from_canonical_internal() -> Dictionary:
	if _native_skeleton == null or _canonical_skeleton == null:
		return _failure("FPE_HAND_NATIVE_SYNC_NOT_READY")
	var driven := 0
	var max_native_angle_deg := 0.0
	for pair in _pose_pairs:
		var source_index := int(pair.get("source_index", -1))
		var canonical_index := int(pair.get("canonical_index", -1))
		var canonical_name := String(pair.get("canonical_name", ""))
		if source_index < 0 or canonical_index < 0:
			continue
		var canonical_rotation := _canonical_skeleton.get_bone_pose_rotation(canonical_index)
		var open_rotation := _canonical_open_rotation(canonical_name)
		var relative_rotation := (open_rotation.inverse() * canonical_rotation).normalized()
		var canonical_euler := Basis(relative_rotation).get_euler()
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
		_native_report["canonical_reference_pose"] = REFERENCE_POSE
		_native_report["canonical_pose_context"] = _pose_context_id
	return _success({
		"sync_count": _sync_count,
		"driven_bone_count": driven,
		"max_native_pose_angle_deg": max_native_angle_deg,
		"canonical_reference_pose": REFERENCE_POSE,
		"canonical_pose_context": _pose_context_id,
	})


func create_live_report(installed_visual_count: int = 1) -> Dictionary:
	var report := super.create_live_report(installed_visual_count)
	report["canonical_reference_pose"] = REFERENCE_POSE
	report["canonical_pose_context"] = _pose_context_id
	report["open_pose_preserves_source_rest"] = true
	report["pose_delta_relative_to_open"] = true
	return report


func _canonical_open_rotation(canonical_name: String) -> Quaternion:
	if _open_pose_cache.has(canonical_name):
		var cached: Variant = _open_pose_cache.get(canonical_name)
		if cached is Quaternion:
			return cached as Quaternion
	var pose := PoseCatalogType.new().get_open_pose()
	var finger := _finger_from_canonical_name(canonical_name)
	var segment_index := _segment_index_from_canonical_name(canonical_name)
	var finger_curl := Dictionary(pose.get("finger_curl_deg", {}))
	var curls_value: Variant = finger_curl.get(finger, [])
	var curls: Array = curls_value if curls_value is Array else []
	var curl_deg := float(curls[segment_index]) if segment_index >= 0 and segment_index < curls.size() else 0.0
	var euler := Vector3(deg_to_rad(curl_deg), 0.0, 0.0)
	if finger == "thumb" and segment_index == 0:
		var side := -1.0 if _normalized_hand == "left" else 1.0
		euler.y = deg_to_rad(float(pose.get("thumb_opposition_deg", 0.0)) * side)
	var rotation := Basis.from_euler(euler).get_rotation_quaternion()
	_open_pose_cache[canonical_name] = rotation
	return rotation


func _segment_index_from_canonical_name(canonical_name: String) -> int:
	if canonical_name.ends_with("Proximal"):
		return 0
	if canonical_name.ends_with("Middle"):
		return 1
	if canonical_name.ends_with("Distal"):
		return 2
	return -1
