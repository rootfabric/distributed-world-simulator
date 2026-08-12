class_name QuaterniusFirstPersonEmbodimentFix15
extends "res://scripts/characters/lab/quaternius_first_person_embodiment_fix14.gd"

const ResourceTwoHandFirstPersonType = preload("res://scripts/characters/presentation/resource_configurable_two_hand_first_person_embodiment.gd")
const S7GrabBridgeType = preload("res://scripts/characters/interaction/first_person_grab_authority_bridge.gd")
const HAND_VISUAL_ARG_PREFIX := "--fpe-hand-visual-scene="

var _s7_requested_resource_path := ""
var _s7_resource_error := ""


func _setup_first_person_embodiment() -> void:
	if (
		base_lab.player == null
		or base_lab.avatar == null
		or base_lab.first_person_adapter == null
		or base_lab.presentation_profile == null
		or base_lab.first_person_camera == null
	):
		fpe_setup_result = _failure("FPE_BASE_PRESENTATION_NOT_READY")
		return

	grab_authority_bridge = S7GrabBridgeType.new()
	grab_authority_bridge.setup(Callable(), true)

	var source_skeleton: Skeleton3D = null
	if base_lab.layered_rig_adapter != null and base_lab.layered_rig_adapter.has_method("resolve_pose_skeleton"):
		var skeleton_value: Variant = base_lab.layered_rig_adapter.call("resolve_pose_skeleton", base_lab.avatar)
		if skeleton_value is Skeleton3D:
			source_skeleton = skeleton_value as Skeleton3D

	var candidate = ResourceTwoHandFirstPersonType.new()
	candidate.name = "ResourceConfigurableTwoHandFirstPersonEmbodiment"
	_s7_requested_resource_path = _find_requested_hand_visual_scene_path()
	_s7_resource_error = ""
	if not _s7_requested_resource_path.is_empty():
		if not ResourceLoader.exists(_s7_requested_resource_path, "PackedScene"):
			_s7_resource_error = "FPE_S7_HAND_VISUAL_RESOURCE_NOT_FOUND"
			fpe_setup_result = _failure(_s7_resource_error, {"resource_path": _s7_requested_resource_path})
			return
		var resource: Resource = load(_s7_requested_resource_path)
		if not resource is PackedScene:
			_s7_resource_error = "FPE_S7_HAND_VISUAL_RESOURCE_NOT_PACKED_SCENE"
			fpe_setup_result = _failure(_s7_resource_error, {"resource_path": _s7_requested_resource_path})
			return
		for hand in ["left", "right"]:
			var configure_result: Dictionary = candidate.configure_hand_visual_resource(
				hand,
				resource as PackedScene,
				_s7_requested_resource_path
			)
			if not bool(configure_result.get("success", false)):
				_s7_resource_error = String(configure_result.get("error_code", "FPE_S7_HAND_VISUAL_CONFIGURE_FAILED"))
				fpe_setup_result = configure_result
				return

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
		_s7_resource_error = String(fpe_setup_result.get("error_code", "FPE_R2_S7_SETUP_FAILED"))
		push_error("FPE R2 S7 resource-configurable viewmodel setup failed: %s" % JSON.stringify(fpe_setup_result))
		return
	if first_person_embodiment.interaction_raycast != null:
		first_person_embodiment.interaction_raycast.add_exception(base_lab.player)
	first_person_embodiment.interaction_result_changed.connect(_on_fpe_interaction_result_changed)
	first_person_embodiment.grab_state_changed.connect(_on_fpe_grab_state_changed)


func get_r2_s7_resource_hand_visual_report() -> Dictionary:
	var config: Dictionary = {}
	if first_person_embodiment != null and first_person_embodiment.has_method("get_resource_hand_visual_report"):
		var value: Variant = first_person_embodiment.call("get_resource_hand_visual_report")
		if value is Dictionary:
			config = Dictionary(value).duplicate(true)
	var s6: Dictionary = get_r2_s6_hand_visual_provider_report()
	return {
		"schema": "planet_simulator.fpe_r2_s7_resource_hand_visual_composition.v1",
		"requested": not _s7_requested_resource_path.is_empty(),
		"resource_path": _s7_requested_resource_path,
		"error_code": _s7_resource_error,
		"configured": config,
		"left_mode": String(s6.get("left_mode", "UNAVAILABLE")),
		"right_mode": String(s6.get("right_mode", "UNAVAILABLE")),
		"resource_adapter_ready": first_person_embodiment != null and first_person_embodiment.has_method("configure_hand_visual_resource"),
		"default_procedural_preserved": _s7_requested_resource_path.is_empty(),
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func get_first_person_embodiment_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_first_person_embodiment_debug_snapshot()
	snapshot["r2_s7"] = get_r2_s7_resource_hand_visual_report()
	return snapshot


func _refresh_status() -> void:
	super._refresh_status()
	if fpe_status_label == null:
		return
	var report := get_r2_s7_resource_hand_visual_report()
	var requested := bool(report.get("requested", false))
	var error_code := String(report.get("error_code", ""))
	fpe_status_label.text += "\nS7 resource hand: %s | L:%s R:%s%s" % [
		"REQUESTED" if requested else "DEFAULT",
		String(report.get("left_mode", "UNAVAILABLE")),
		String(report.get("right_mode", "UNAVAILABLE")),
		" | error:%s" % error_code if not error_code.is_empty() else "",
	]


func _find_requested_hand_visual_scene_path() -> String:
	for raw_arg in OS.get_cmdline_user_args():
		var arg := String(raw_arg)
		if arg.begins_with(HAND_VISUAL_ARG_PREFIX):
			return arg.substr(HAND_VISUAL_ARG_PREFIX.length()).strip_edges()
	return ""
