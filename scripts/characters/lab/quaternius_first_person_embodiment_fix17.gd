class_name QuaterniusFirstPersonEmbodimentFix17
extends "res://scripts/characters/lab/quaternius_first_person_embodiment_fix16.gd"

const ProfiledTwoHandFirstPersonType = preload("res://scripts/characters/presentation/profiled_hand_asset_two_hand_first_person_embodiment.gd")
const HandAssetRegistryType = preload("res://scripts/characters/presentation/first_person_hand_asset_registry.gd")
const S10GrabBridgeType = preload("res://scripts/characters/interaction/first_person_grab_authority_bridge.gd")
const HAND_ASSET_PROFILE_ARG_PREFIX := "--fpe-hand-asset-profile="

var _requested_hand_asset_profile_ref := ""
var _active_hand_asset_profile_id := ""
var _active_hand_asset_profile_path := ""
var _hand_asset_profile_error := ""
var _hand_asset_profile_fallback_active := false
var _hand_asset_registry_report: Dictionary = {}


func _setup_first_person_embodiment() -> void:
	_requested_hand_asset_profile_ref = _find_requested_hand_asset_profile_ref()
	if _requested_hand_asset_profile_ref.is_empty():
		super._setup_first_person_embodiment()
		return
	if not _find_requested_hand_visual_scene_path().is_empty() or not _find_requested_skinned_hand_scene_path().is_empty():
		_hand_asset_profile_error = "FPE_HAND_PROFILE_MULTIPLE_PROVIDER_SELECTIONS"
		fpe_setup_result = _failure(_hand_asset_profile_error)
		return
	if (
		base_lab.player == null
		or base_lab.avatar == null
		or base_lab.first_person_adapter == null
		or base_lab.presentation_profile == null
		or base_lab.first_person_camera == null
	):
		fpe_setup_result = _failure("FPE_BASE_PRESENTATION_NOT_READY")
		return

	var registry = HandAssetRegistryType.new()
	var registry_load: Dictionary = registry.load_directory()
	if not bool(registry_load.get("success", false)):
		_hand_asset_profile_error = String(registry_load.get("error_code", "FPE_HAND_PROFILE_REGISTRY_LOAD_FAILED"))
		_hand_asset_profile_fallback_active = true
		super._setup_first_person_embodiment()
		return
	_hand_asset_registry_report = registry.create_report()
	var resolved: Dictionary = registry.resolve(_requested_hand_asset_profile_ref)
	if not bool(resolved.get("success", false)):
		_hand_asset_profile_error = String(resolved.get("error_code", "FPE_HAND_PROFILE_RESOLVE_FAILED"))
		_hand_asset_profile_fallback_active = true
		super._setup_first_person_embodiment()
		return
	var resolved_details := Dictionary(resolved.get("details", {}))
	var profile := Dictionary(resolved_details.get("profile", {})).duplicate(true)
	_active_hand_asset_profile_path = String(resolved_details.get("profile_path", ""))
	_active_hand_asset_profile_id = String(profile.get("profile_id", ""))

	var readiness_error := _profile_runtime_readiness_error(profile)
	if not readiness_error.is_empty():
		_hand_asset_profile_error = readiness_error
		_hand_asset_profile_fallback_active = true
		super._setup_first_person_embodiment()
		return

	var candidate = ProfiledTwoHandFirstPersonType.new()
	candidate.name = "ProfiledHandAssetTwoHandFirstPersonEmbodiment"
	for hand in ["left", "right"]:
		var configure_result: Dictionary = candidate.configure_hand_asset_profile(
			hand,
			profile,
			_active_hand_asset_profile_path
		)
		if not bool(configure_result.get("success", false)):
			_hand_asset_profile_error = String(configure_result.get("error_code", "FPE_HAND_PROFILE_CONFIGURE_FAILED"))
			_hand_asset_profile_fallback_active = true
			candidate.free()
			super._setup_first_person_embodiment()
			return

	grab_authority_bridge = S10GrabBridgeType.new()
	grab_authority_bridge.setup(Callable(), true)
	var source_skeleton: Skeleton3D = null
	if base_lab.layered_rig_adapter != null and base_lab.layered_rig_adapter.has_method("resolve_pose_skeleton"):
		var skeleton_value: Variant = base_lab.layered_rig_adapter.call("resolve_pose_skeleton", base_lab.avatar)
		if skeleton_value is Skeleton3D:
			source_skeleton = skeleton_value as Skeleton3D

	first_person_embodiment = candidate
	base_lab.player.add_child(first_person_embodiment)
	fpe_setup_result = first_person_embodiment.setup(
		base_lab.player,
		base_lab.avatar,
		base_lab.first_person_adapter,
		base_lab.presentation_profile,
		base_lab.first_person_camera,
		base_lab.third_person_camera,
		grab_authority_bridge,
		source_skeleton
	)
	if not bool(fpe_setup_result.get("success", false)):
		_hand_asset_profile_error = String(fpe_setup_result.get("error_code", "FPE_HAND_PROFILE_RUNTIME_SETUP_FAILED"))
		_hand_asset_profile_fallback_active = true
		if first_person_embodiment.get_parent() != null:
			first_person_embodiment.get_parent().remove_child(first_person_embodiment)
		first_person_embodiment.free()
		first_person_embodiment = null
		super._setup_first_person_embodiment()
		return
	if first_person_embodiment.interaction_raycast != null:
		first_person_embodiment.interaction_raycast.add_exception(base_lab.player)
	first_person_embodiment.interaction_result_changed.connect(_on_fpe_interaction_result_changed)
	first_person_embodiment.grab_state_changed.connect(_on_fpe_grab_state_changed)


func get_hand_asset_profile_composition_report() -> Dictionary:
	var profile_report: Dictionary = {}
	if first_person_embodiment != null and first_person_embodiment.has_method("get_hand_asset_profile_report"):
		var value: Variant = first_person_embodiment.call("get_hand_asset_profile_report")
		if value is Dictionary:
			profile_report = Dictionary(value).duplicate(true)
	var s6 := get_r2_s6_hand_visual_provider_report()
	return {
		"schema": "planet_simulator.fpe_hand_asset_profile_composition.v1",
		"requested": not _requested_hand_asset_profile_ref.is_empty(),
		"requested_ref": _requested_hand_asset_profile_ref,
		"profile_id": _active_hand_asset_profile_id,
		"profile_path": _active_hand_asset_profile_path,
		"error_code": _hand_asset_profile_error,
		"fallback_active": _hand_asset_profile_fallback_active,
		"registry": _hand_asset_registry_report.duplicate(true),
		"profile_config": profile_report,
		"left_mode": String(s6.get("left_mode", "UNAVAILABLE")),
		"right_mode": String(s6.get("right_mode", "UNAVAILABLE")),
		"portable_profiles_supported": true,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func get_first_person_embodiment_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_first_person_embodiment_debug_snapshot()
	snapshot["hand_asset_profile"] = get_hand_asset_profile_composition_report()
	return snapshot


func _refresh_status() -> void:
	super._refresh_status()
	if fpe_status_label == null:
		return
	var report := get_hand_asset_profile_composition_report()
	var error_code := String(report.get("error_code", ""))
	var fallback_suffix := " | fallback:DEFAULT" if bool(report.get("fallback_active", false)) else ""
	fpe_status_label.text += "\nhand profile: %s | L:%s R:%s%s%s" % [
		String(report.get("profile_id", "DEFAULT")) if bool(report.get("requested", false)) else "DEFAULT",
		String(report.get("left_mode", "UNAVAILABLE")),
		String(report.get("right_mode", "UNAVAILABLE")),
		fallback_suffix,
		" | error:%s" % error_code if not error_code.is_empty() else "",
	]


func _profile_runtime_readiness_error(profile: Dictionary) -> String:
	var asset := Dictionary(profile.get("asset", {}))
	var scene_path := String(asset.get("scene_path", "")).strip_edges()
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path, "PackedScene"):
		return "FPE_HAND_PROFILE_ASSET_SCENE_NOT_IMPORTED"
	var selection := Dictionary(profile.get("selection", {}))
	if bool(selection.get("inspection_required_before_runtime", false)):
		return "FPE_HAND_PROFILE_INSPECTION_PENDING"
	var retarget := Dictionary(profile.get("retarget", {}))
	var rest_policy := String(retarget.get("rest_space_policy", "")).strip_edges().to_upper()
	if rest_policy == "INSPECT_REQUIRED" or rest_policy.is_empty():
		return "FPE_HAND_PROFILE_REST_SPACE_NOT_CALIBRATED"
	var common_map := Dictionary(retarget.get("bone_map", {}))
	var by_hand_value: Variant = retarget.get("bone_map_by_hand", {})
	var by_hand := Dictionary(by_hand_value) if by_hand_value is Dictionary else {}
	if common_map.is_empty() and by_hand.is_empty():
		return "FPE_HAND_PROFILE_BONE_MAP_REQUIRED"
	if String(profile.get("hand_layout", "")).strip_edges().to_upper() == "PAIRED_SINGLE_MESH":
		var split := Dictionary(selection.get("paired_split", {}))
		if String(split.get("strategy", "")).strip_edges().is_empty():
			return "FPE_HAND_PROFILE_PAIRED_SPLIT_CONFIG_REQUIRED"
	return ""


func _find_requested_hand_asset_profile_ref() -> String:
	for raw_arg in OS.get_cmdline_user_args():
		var arg := String(raw_arg)
		if arg.begins_with(HAND_ASSET_PROFILE_ARG_PREFIX):
			return arg.substr(HAND_ASSET_PROFILE_ARG_PREFIX.length()).strip_edges()
	return ""
