class_name QuaterniusFirstPersonEmbodimentFix12
extends "res://scripts/characters/lab/quaternius_first_person_embodiment_fix11.gd"

const TwoHandFirstPersonType = preload("res://scripts/characters/presentation/owner_collision_isolated_two_hand_first_person_embodiment.gd")
const S4GrabBridgeType = preload("res://scripts/characters/interaction/first_person_grab_authority_bridge.gd")


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

	grab_authority_bridge = S4GrabBridgeType.new()
	grab_authority_bridge.setup(Callable(), true)

	var source_skeleton: Skeleton3D = null
	if base_lab.layered_rig_adapter != null and base_lab.layered_rig_adapter.has_method("resolve_pose_skeleton"):
		var skeleton_value: Variant = base_lab.layered_rig_adapter.call("resolve_pose_skeleton", base_lab.avatar)
		if skeleton_value is Skeleton3D:
			source_skeleton = skeleton_value as Skeleton3D

	first_person_embodiment = TwoHandFirstPersonType.new()
	first_person_embodiment.name = "OwnerCollisionIsolatedTwoHandFirstPersonEmbodiment"
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
		push_error("FPE R2 S4 two-hand viewmodel setup failed: %s" % JSON.stringify(fpe_setup_result))
		return
	if first_person_embodiment.interaction_raycast != null:
		first_person_embodiment.interaction_raycast.add_exception(base_lab.player)
	first_person_embodiment.interaction_result_changed.connect(_on_fpe_interaction_result_changed)
	first_person_embodiment.grab_state_changed.connect(_on_fpe_grab_state_changed)


func get_r2_s4_two_hand_report() -> Dictionary:
	if first_person_embodiment != null and first_person_embodiment.has_method("get_two_hand_report"):
		var value: Variant = first_person_embodiment.call("get_two_hand_report")
		if value is Dictionary:
			return Dictionary(value).duplicate(true)
	return {
		"schema": "planet_simulator.fpe_r2_s4_two_hand_composition.v1",
		"active": false,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func get_sandbox_collision_isolation_report() -> Dictionary:
	if first_person_embodiment != null and first_person_embodiment.has_method("get_owner_collision_isolation_report"):
		var value: Variant = first_person_embodiment.call("get_owner_collision_isolation_report")
		if value is Dictionary:
			return Dictionary(value).duplicate(true)
	return {
		"schema": "planet_simulator.fpe_owner_collision_isolation.v1",
		"active": 0,
		"owner_only_exception": false,
		"world_collisions_preserved": true,
		"presentation_sandbox_only": true,
	}


func get_first_person_embodiment_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_first_person_embodiment_debug_snapshot()
	snapshot["r2_s4"] = get_r2_s4_two_hand_report()
	snapshot["sandbox_collision_isolation"] = get_sandbox_collision_isolation_report()
	return snapshot


func _refresh_status() -> void:
	super._refresh_status()
	if fpe_status_label == null:
		return
	var report := get_r2_s4_two_hand_report()
	var state := "ACTIVE" if bool(report.get("active", false)) else "FREE"
	var profile := String(report.get("profile_id", ""))
	var pose := String(report.get("secondary_pose_id", ""))
	var isolation := get_sandbox_collision_isolation_report()
	fpe_status_label.text += "\nS4 two-hand: %s | profile: %s | left pose: %s" % [
		state,
		profile if not profile.is_empty() else "-",
		pose if not pose.is_empty() else "open",
	]
	fpe_status_label.text += "\nsandbox owner collision: %s | grace: %d ms" % [
		"ISOLATED" if int(isolation.get("active", 0)) > 0 else "FREE",
		int(isolation.get("release_grace_ms", 0)),
	]
