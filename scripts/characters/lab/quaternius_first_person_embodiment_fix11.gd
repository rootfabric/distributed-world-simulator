class_name QuaterniusFirstPersonEmbodimentFix11
extends "res://scripts/characters/lab/quaternius_first_person_embodiment_fix10.gd"

const PosedCataloguedFirstPersonType = preload("res://scripts/characters/presentation/posed_catalogued_first_person_embodiment.gd")
const S3GrabBridgeType = preload("res://scripts/characters/interaction/first_person_grab_authority_bridge.gd")


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

	grab_authority_bridge = S3GrabBridgeType.new()
	grab_authority_bridge.setup(Callable(), true)

	var source_skeleton: Skeleton3D = null
	if base_lab.layered_rig_adapter != null and base_lab.layered_rig_adapter.has_method("resolve_pose_skeleton"):
		var skeleton_value: Variant = base_lab.layered_rig_adapter.call("resolve_pose_skeleton", base_lab.avatar)
		if skeleton_value is Skeleton3D:
			source_skeleton = skeleton_value as Skeleton3D

	first_person_embodiment = PosedCataloguedFirstPersonType.new()
	first_person_embodiment.name = "PosedCataloguedFirstPersonEmbodiment"
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
		push_error("FPE R2 S3 articulated hand setup failed: %s" % JSON.stringify(fpe_setup_result))
		return
	if first_person_embodiment.interaction_raycast != null:
		first_person_embodiment.interaction_raycast.add_exception(base_lab.player)
	first_person_embodiment.interaction_result_changed.connect(_on_fpe_interaction_result_changed)
	first_person_embodiment.grab_state_changed.connect(_on_fpe_grab_state_changed)


func get_r2_s3_hand_pose_report() -> Dictionary:
	if first_person_embodiment != null and first_person_embodiment.has_method("get_hand_pose_report"):
		var value: Variant = first_person_embodiment.call("get_hand_pose_report")
		if value is Dictionary:
			return Dictionary(value).duplicate(true)
	return {
		"schema": "planet_simulator.fpe_r2_s3_hand_pose_composition.v1",
		"articulated_skeleton": false,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func get_first_person_embodiment_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_first_person_embodiment_debug_snapshot()
	snapshot["r2_s3"] = get_r2_s3_hand_pose_report()
	return snapshot


func _refresh_status() -> void:
	super._refresh_status()
	if fpe_status_label == null:
		return
	var pose_report: Dictionary = get_r2_s3_hand_pose_report()
	var rigs: Dictionary = Dictionary(pose_report.get("rigs", {}))
	var left_report: Dictionary = Dictionary(rigs.get("left", {}))
	var right_report: Dictionary = Dictionary(rigs.get("right", {}))
	var left_pose := String(left_report.get("current_pose_id", "UNAVAILABLE"))
	var right_pose := String(right_report.get("current_pose_id", "UNAVAILABLE"))
	var skeleton_state := "READY" if bool(pose_report.get("articulated_skeleton", false)) else "PENDING"
	fpe_status_label.text += "\nS3 hands: %s | L:%s | R:%s" % [skeleton_state, left_pose, right_pose]
