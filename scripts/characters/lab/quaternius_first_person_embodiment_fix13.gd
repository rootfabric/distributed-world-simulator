class_name QuaterniusFirstPersonEmbodimentFix13
extends "res://scripts/characters/lab/quaternius_first_person_embodiment_fix12.gd"

const HeldStateS5Type = preload("res://scripts/characters/presentation/held_item_presentation_state.gd")
const ThirdPersonTwoHandType = preload("res://scripts/characters/presentation/two_hand_catalogued_third_person_held_item_presenter.gd")


func _setup_shared_held_item_presentation() -> void:
	if base_lab == null or base_lab.player == null or base_lab.avatar == null:
		_held_item_setup_result = _failure("FPE_R2_BASE_PRESENTATION_NOT_READY")
		return

	held_item_presentation_state = HeldStateS5Type.new()
	held_item_presentation_state.changed.connect(_on_held_item_presentation_changed)

	var source_skeleton: Skeleton3D = null
	if base_lab.layered_rig_adapter != null and base_lab.layered_rig_adapter.has_method("resolve_pose_skeleton"):
		var skeleton_value: Variant = base_lab.layered_rig_adapter.call("resolve_pose_skeleton", base_lab.avatar)
		if skeleton_value is Skeleton3D:
			source_skeleton = skeleton_value as Skeleton3D

	third_person_held_item_presenter = ThirdPersonTwoHandType.new()
	third_person_held_item_presenter.name = "FpeR2S5TwoHandThirdPersonHeldItemPresenter"
	base_lab.player.add_child(third_person_held_item_presenter)
	var world_layer_index := 20
	if base_lab.presentation_profile != null:
		world_layer_index = int(base_lab.presentation_profile.world_render_layer_index)
	_held_item_setup_result = third_person_held_item_presenter.setup(
		base_lab.avatar,
		source_skeleton,
		world_layer_index
	)
	if not bool(_held_item_setup_result.get("success", false)):
		_last_fpe_status_code = String(_held_item_setup_result.get("error_code", "FPE_R2_S5_THIRD_PERSON_SETUP_FAILED"))
		return

	if base_lab.character_gameplay_controller != null:
		_apply_hotbar_presentation_for_index(int(base_lab.character_gameplay_controller.selected_hotbar_index))


func get_r2_s5_secondary_world_hand_report() -> Dictionary:
	if third_person_held_item_presenter != null and third_person_held_item_presenter.has_method("get_secondary_hand_report"):
		var value: Variant = third_person_held_item_presenter.call("get_secondary_hand_report")
		if value is Dictionary:
			return Dictionary(value).duplicate(true)
	return {
		"schema": "planet_simulator.fpe_r2_s5_third_person_secondary_hand.v1",
		"configured": false,
		"active": false,
		"mode": "UNAVAILABLE",
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func get_first_person_embodiment_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_first_person_embodiment_debug_snapshot()
	snapshot["r2_s5"] = get_r2_s5_secondary_world_hand_report()
	return snapshot


func _refresh_status() -> void:
	super._refresh_status()
	if fpe_status_label == null:
		return
	var report := get_r2_s5_secondary_world_hand_report()
	var state := "ACTIVE" if bool(report.get("active", false)) else "FREE"
	fpe_status_label.text += "\nS5 world left: %s | mode: %s | item: %s" % [
		state,
		String(report.get("mode", "UNAVAILABLE")),
		String(report.get("item_id", "-")) if not String(report.get("item_id", "")).is_empty() else "-",
	]
