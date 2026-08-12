class_name QuaterniusFirstPersonEmbodimentFix14
extends "res://scripts/characters/lab/quaternius_first_person_embodiment_fix13.gd"


func get_r2_s6_hand_visual_provider_report() -> Dictionary:
	var left_provider: Dictionary = {}
	var right_provider: Dictionary = {}
	if first_person_embodiment != null and first_person_embodiment.has_method("get_hand_pose_report"):
		var pose_value: Variant = first_person_embodiment.call("get_hand_pose_report")
		if pose_value is Dictionary:
			var pose_report: Dictionary = Dictionary(pose_value)
			var rigs: Dictionary = Dictionary(pose_report.get("rigs", {}))
			var left_rig: Dictionary = Dictionary(rigs.get("left", {}))
			var right_rig: Dictionary = Dictionary(rigs.get("right", {}))
			left_provider = Dictionary(left_rig.get("visual_provider", {})).duplicate(true)
			right_provider = Dictionary(right_rig.get("visual_provider", {})).duplicate(true)

	var left_mode := String(left_provider.get("mode", "UNAVAILABLE"))
	var right_mode := String(right_provider.get("mode", "UNAVAILABLE"))
	return {
		"schema": "planet_simulator.fpe_r2_s6_hand_visual_provider_composition.v1",
		"left": left_provider,
		"right": right_provider,
		"left_mode": left_mode,
		"right_mode": right_mode,
		"provider_boundary_ready": not left_provider.is_empty() and not right_provider.is_empty(),
		"substitutable": bool(left_provider.get("substitutable", false)) and bool(right_provider.get("substitutable", false)),
		"pose_logic_independent": true,
		"production_asset_required_for_final_quality": true,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func get_first_person_embodiment_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_first_person_embodiment_debug_snapshot()
	snapshot["r2_s6"] = get_r2_s6_hand_visual_provider_report()
	return snapshot


func _refresh_status() -> void:
	super._refresh_status()
	if fpe_status_label == null:
		return
	var report := get_r2_s6_hand_visual_provider_report()
	fpe_status_label.text += "\nS6 hand visuals: L:%s | R:%s | substitutable:%s" % [
		String(report.get("left_mode", "UNAVAILABLE")),
		String(report.get("right_mode", "UNAVAILABLE")),
		"YES" if bool(report.get("substitutable", false)) else "NO",
	]
