extends SceneTree

const ProfileType = preload("res://scripts/characters/presentation/first_person_hand_asset_profile.gd")
const ProviderType = preload("res://scripts/characters/presentation/calibrated_native_skeleton_first_person_hand_visual_provider.gd")
const RigType = preload("res://scripts/characters/presentation/substitutable_first_person_hand_rig.gd")
const PoseCatalogType = preload("res://scripts/characters/presentation/first_person_hand_pose_catalog.gd")
const PROFILE_ARG := "--fpe-hand-profile-path="
const POSES: Array[String] = ["open", "beacon_pinch", "bulky_carry", "support_cradle"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile_path := _profile_path_from_args()
	if profile_path.is_empty():
		_finish_failure("FPE_HAND_POSE_CALIBRATION_PROFILE_PATH_REQUIRED")
		return
	var loaded: Dictionary = ProfileType.load_from_path(profile_path)
	if not bool(loaded.get("success", false)):
		_finish_failure(String(loaded.get("error_code", "FPE_HAND_POSE_CALIBRATION_PROFILE_LOAD_FAILED")), loaded)
		return
	var details := Dictionary(loaded.get("details", {}))
	var profile := Dictionary(details.get("profile", {}))
	var asset := Dictionary(profile.get("asset", {}))
	var scene_path := String(asset.get("scene_path", ""))
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		_finish_failure("FPE_HAND_POSE_CALIBRATION_ASSET_NOT_IMPORTED", {"scene_path": scene_path})
		return
	var resource: Resource = load(scene_path)
	if not resource is PackedScene:
		_finish_failure("FPE_HAND_POSE_CALIBRATION_ASSET_NOT_PACKED_SCENE", {"scene_path": scene_path})
		return

	var output := {
		"schema": "planet_simulator.fpe_hand_pose_calibration_inspection.v1",
		"profile_path": profile_path,
		"profile_id": String(profile.get("profile_id", "")),
		"scene_path": scene_path,
		"hands": {},
	}
	var host := Node3D.new()
	get_root().add_child(host)
	for hand in ["right", "left"]:
		var provider = ProviderType.new()
		var provider_setup: Dictionary = provider.setup_profiled(resource as PackedScene, profile, profile_path, scene_path)
		if not bool(provider_setup.get("success", false)):
			host.queue_free()
			_finish_failure("FPE_HAND_POSE_CALIBRATION_PROVIDER_SETUP_FAILED", {"hand": hand, "result": provider_setup})
			return
		var rig = RigType.new()
		host.add_child(rig)
		var rig_setup: Dictionary = rig.setup(hand, 19, provider)
		if not bool(rig_setup.get("success", false)):
			host.queue_free()
			_finish_failure("FPE_HAND_POSE_CALIBRATION_RIG_SETUP_FAILED", {"hand": hand, "result": rig_setup})
			return
		var hand_report := {
			"provider": provider.create_live_report(1),
			"axes": _axis_report(provider),
			"poses": {},
		}
		for pose_id in POSES:
			var pose_result: Dictionary = rig.apply_pose(PoseCatalogType.new().get_pose(pose_id))
			if not bool(pose_result.get("success", false)):
				host.queue_free()
				_finish_failure("FPE_HAND_POSE_CALIBRATION_POSE_FAILED", {"hand": hand, "pose": pose_id, "result": pose_result})
				return
			rig._process(0.2)
			hand_report.poses[pose_id] = _pose_report(provider)
		output.hands[hand] = hand_report
		host.remove_child(rig)
		rig.free()
	host.queue_free()
	print("FPE hand pose calibration inspector: PASS")
	print("FPE_HAND_POSE_CALIBRATION_JSON:%s" % JSON.stringify(output))
	quit(0)


func _axis_report(provider) -> Array:
	var output: Array = []
	for pair in provider._pose_pairs:
		var source_index := int(pair.get("source_index", -1))
		var source_rest := provider._native_skeleton.get_bone_global_rest(source_index) if source_index >= 0 else Transform3D.IDENTITY
		var curl_axis := pair.get("curl_axis", Vector3.ZERO) as Vector3
		var opposition_axis := pair.get("opposition_axis", Vector3.ZERO) as Vector3
		output.append({
			"source_name": String(pair.get("source_name", "")),
			"canonical_name": String(pair.get("canonical_name", "")),
			"finger": String(pair.get("finger", "")),
			"curl_axis": [curl_axis.x, curl_axis.y, curl_axis.z],
			"opposition_axis": [opposition_axis.x, opposition_axis.y, opposition_axis.z],
			"curl_sign": float(pair.get("curl_sign", 1.0)),
			"curl_scale": float(pair.get("curl_scale", 1.0)),
			"opposition_sign": float(pair.get("opposition_sign", 1.0)),
			"opposition_scale": float(pair.get("opposition_scale", 1.0)),
			"source_global_rest_origin": [source_rest.origin.x, source_rest.origin.y, source_rest.origin.z],
			"source_global_rest_basis_x": [source_rest.basis.x.x, source_rest.basis.x.y, source_rest.basis.x.z],
			"source_global_rest_basis_y": [source_rest.basis.y.x, source_rest.basis.y.y, source_rest.basis.y.z],
			"source_global_rest_basis_z": [source_rest.basis.z.x, source_rest.basis.z.y, source_rest.basis.z.z],
		})
	return output


func _pose_report(provider) -> Dictionary:
	var bones: Dictionary = {}
	for pair in provider._pose_pairs:
		var source_name := String(pair.get("source_name", ""))
		var source_index := int(pair.get("source_index", -1))
		if source_index < 0:
			continue
		var rotation := provider._native_skeleton.get_bone_pose_rotation(source_index)
		var euler := Basis(rotation).get_euler()
		bones[source_name] = {
			"quaternion": [rotation.x, rotation.y, rotation.z, rotation.w],
			"euler_degrees": [rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z)],
			"angle_degrees": rad_to_deg(Quaternion.IDENTITY.angle_to(rotation)),
		}
	return {
		"bones": bones,
		"provider": provider.create_live_report(1),
	}


func _profile_path_from_args() -> String:
	for argument in OS.get_cmdline_user_args():
		var text := String(argument)
		if text.begins_with(PROFILE_ARG):
			return text.substr(PROFILE_ARG.length()).strip_edges()
	return ""


func _finish_failure(error_code: String, details: Dictionary = {}) -> void:
	push_error("%s:%s" % [error_code, JSON.stringify(details)])
	print("FPE hand pose calibration inspector: FAIL")
	quit(1)
