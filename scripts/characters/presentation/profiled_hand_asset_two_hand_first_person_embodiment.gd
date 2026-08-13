class_name ProfiledHandAssetTwoHandFirstPersonEmbodiment
extends "res://scripts/characters/presentation/skinned_resource_configurable_two_hand_first_person_embodiment.gd"

const ProfileType = preload("res://scripts/characters/presentation/first_person_hand_asset_profile.gd")
const ProfiledProviderType = preload("res://scripts/characters/presentation/profiled_skinned_first_person_hand_visual_provider_fix2.gd")
const NativeProfiledProviderType = preload("res://scripts/characters/presentation/calibrated_native_skeleton_first_person_hand_visual_provider.gd")

var _hand_asset_profile_by_hand: Dictionary = {}


func configure_hand_asset_profile(
	hand_id: String,
	profile: Dictionary,
	profile_path: String = ""
) -> Dictionary:
	var hand := _normalize_hand(hand_id)
	if hand.is_empty():
		return _failure("FPE_HAND_PROFILE_INVALID_HAND", {"hand_id": hand_id})
	var validation: Dictionary = ProfileType.validate(profile)
	if not bool(validation.get("success", false)):
		return validation
	var provider_kind := String(profile.get("provider", "")).strip_edges().to_upper()
	if provider_kind != ProfileType.PROVIDER_SKINNED_NAMED_BIND:
		return _failure("FPE_HAND_PROFILE_PROVIDER_RUNTIME_UNSUPPORTED", {
			"profile_id": String(profile.get("profile_id", "")),
			"provider": provider_kind,
		})
	var asset := Dictionary(profile.get("asset", {}))
	var scene_path := String(asset.get("scene_path", "")).strip_edges()
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		return _failure("FPE_HAND_PROFILE_ASSET_SCENE_NOT_FOUND", {
			"profile_id": String(profile.get("profile_id", "")),
			"scene_path": scene_path,
			"status": String(profile.get("status", "")),
		})
	var resource: Resource = load(scene_path)
	if not resource is PackedScene:
		return _failure("FPE_HAND_PROFILE_ASSET_NOT_PACKED_SCENE", {
			"profile_id": String(profile.get("profile_id", "")),
			"scene_path": scene_path,
		})
	_hand_asset_profile_by_hand[hand] = {
		"profile": profile.duplicate(true),
		"profile_path": profile_path.strip_edges(),
		"scene_path": scene_path,
		"scene": resource as PackedScene,
	}
	return _success({
		"hand_id": hand,
		"profile_id": String(profile.get("profile_id", "")),
		"profile_path": profile_path,
		"scene_path": scene_path,
		"configured": true,
	})


func clear_hand_asset_profile(hand_id: String) -> Dictionary:
	var hand := _normalize_hand(hand_id)
	if hand.is_empty():
		return _failure("FPE_HAND_PROFILE_INVALID_HAND", {"hand_id": hand_id})
	_hand_asset_profile_by_hand.erase(hand)
	return _success({"hand_id": hand, "configured": false})


func get_hand_asset_profile_report() -> Dictionary:
	var configured: Dictionary = {}
	for hand in [HAND_LEFT, HAND_RIGHT]:
		var entry := Dictionary(_hand_asset_profile_by_hand.get(hand, {}))
		var profile := Dictionary(entry.get("profile", {}))
		var retarget := Dictionary(profile.get("retarget", {}))
		configured[hand] = {
			"configured": not entry.is_empty(),
			"profile_id": String(profile.get("profile_id", "")),
			"display_name": String(profile.get("display_name", "")),
			"profile_path": String(entry.get("profile_path", "")),
			"scene_path": String(entry.get("scene_path", "")),
			"license_spdx": String(Dictionary(profile.get("license", {})).get("spdx", "")),
			"status": String(profile.get("status", "")),
			"runtime_driver": String(retarget.get("runtime_driver", "")),
			"rest_space_policy": String(retarget.get("rest_space_policy", "")),
			"native_pose_calibration_mode": String(Dictionary(retarget.get("native_pose_calibration", {})).get("mode", "")),
		}
	return {
		"schema": "planet_simulator.fpe_profiled_hand_asset_config.v1",
		"configured": configured,
		"portable_profiles_supported": true,
		"drop_in_json_registration": true,
		"native_skeleton_pose_driver_supported": true,
		"native_axis_calibration_supported": true,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func _install_hand_rig(hand: String, hand_root: Node3D, viewmodel_layer: int) -> Dictionary:
	var config := Dictionary(_hand_asset_profile_by_hand.get(hand, {}))
	if config.is_empty():
		return super._install_hand_rig(hand, hand_root, viewmodel_layer)
	if hand_root == null:
		return _failure("FPE_S3_HAND_ROOT_REQUIRED", {"hand_id": hand})
	var scene_value: Variant = config.get("scene")
	var profile_value: Variant = config.get("profile")
	if not scene_value is PackedScene or not profile_value is Dictionary:
		return _failure("FPE_HAND_PROFILE_RUNTIME_CONFIG_INVALID", {"hand_id": hand})

	var profile := Dictionary(profile_value)
	var retarget := Dictionary(profile.get("retarget", {}))
	var runtime_driver := String(retarget.get("runtime_driver", "")).strip_edges().to_upper()
	var provider
	if runtime_driver == ProfileType.DRIVER_NATIVE_SKELETON_POSE:
		provider = NativeProfiledProviderType.new()
	else:
		provider = ProfiledProviderType.new()
	var provider_setup: Dictionary = provider.setup_profiled(
		scene_value as PackedScene,
		profile,
		String(config.get("profile_path", "")),
		String(config.get("scene_path", ""))
	)
	if not bool(provider_setup.get("success", false)):
		return provider_setup

	# SubstitutableRigType is inherited from ResourceConfigurableTwoHandFirstPersonEmbodiment.
	# Do not redeclare it here: GDScript treats duplicate inherited members as a parse error.
	var rig = SubstitutableRigType.new()
	rig.name = "%sArticulatedHandRig" % hand.capitalize()
	hand_root.add_child(rig)
	var setup_result: Dictionary = rig.setup(hand, viewmodel_layer, provider)
	if not bool(setup_result.get("success", false)):
		rig.queue_free()
		return setup_result
	var old_palm: Node = hand_root.get_node_or_null("%sPalm" % hand.capitalize())
	if old_palm is GeometryInstance3D:
		(old_palm as GeometryInstance3D).visible = false
	_hand_rig_by_hand[hand] = rig
	var open_result: Dictionary = rig.apply_pose(hand_pose_catalog.get_open_pose())
	if not bool(open_result.get("success", false)):
		return open_result
	_last_pose_by_hand[hand] = "open"
	return _success({
		"hand_id": hand,
		"rig": rig.create_report(),
		"profiled_hand_asset": true,
		"profile_id": String(profile.get("profile_id", "")),
		"runtime_driver": runtime_driver,
	})


func create_report() -> Dictionary:
	var report: Dictionary = super.create_report()
	report["hand_asset_profiles"] = get_hand_asset_profile_report()
	return report
