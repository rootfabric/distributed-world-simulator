extends "res://scripts/labs/ecology/eco_vis2_1_control_vs_treatment_lab.gd"

const VIS21V_RealtimeLODRenderer = preload("res://scripts/labs/ecology/eco_vis2_1v_realtime_lod_renderer.gd")

const VIS21V_STAGE := "ECO.VIS2.1-V"
const VIS21V_MODE := "TREATMENT_REALTIME_DISTANCE_LOD"


func _ready() -> void:
	_vis18r_renderer = VIS21V_RealtimeLODRenderer.new()
	super._ready()
	if is_instance_valid(_controls_label):
		_controls_label.text = _controls_label.text.replace("I VIS2.0 panel", "I source panel (pre-fork only)")
		_controls_label.text += "\nVIS2.1-V: Treatment uses camera-distance realtime LOD (near/mid/far); CONTROL remains data-only and no whole-field PH5 rebuild is introduced."
	_update_vis18r_title()
	_update_status()


func _exit_tree() -> void:
	# VIS2.1-V owns the replacement realtime renderer. Release its mesh/material
	# resources before the scene disappears so editor/headless shutdown does not depend
	# on RefCounted destruction order.
	if _vis18r_renderer != null and _vis18r_renderer.has_method("release_resources"):
		_vis18r_renderer.call("release_resources")
	_vis18r_renderer = null


func begin_paired_experiment() -> Dictionary:
	var result: Dictionary = super.begin_paired_experiment()
	if bool(result.get("success", false)):
		_hide_vis20_source_panel()
		_update_vis18r_title()
		_update_status()
	return result


func _unhandled_input(event: InputEvent) -> void:
	if _vis21_paired and event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_I:
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)


func get_vis21v_state() -> Dictionary:
	var state := get_vis21_state()
	var lod := {}
	if _vis18r_renderer != null:
		lod = Dictionary(_vis18r_renderer.call("lod_summary"))
	state["stage"] = VIS21V_STAGE
	state["mode"] = VIS21V_MODE
	state["realtime_lod"] = lod.duplicate(true)
	state["source_vis20_panel_hidden_after_fork"] = _vis21_paired and is_instance_valid(_vis20_experiment_panel) and not _vis20_experiment_panel.visible
	return state


func _hide_vis20_source_panel() -> void:
	_vis20_panel_visible = false
	if is_instance_valid(_vis20_experiment_panel):
		_vis20_experiment_panel.call("set_experiment_panel_visible", false)


func _update_vis18r_title() -> void:
	if not _vis21_paired:
		super._update_vis18r_title()
		var pre_fork_title := get_node_or_null("HUD/Margin/Panel/VBox/Title") as Label
		if pre_fork_title != null:
			pre_fork_title.text = pre_fork_title.text.replace("ECO.VIS2.0", VIS21V_STAGE).replace("ECO.VIS2.1", VIS21V_STAGE)
		return
	var title := get_node_or_null("HUD/Margin/Panel/VBox/Title") as Label
	if title == null:
		return
	title.text = "%s — %s fork=G%d paired=G%d — %s %d%% — reps=%d" % [
		VIS21V_STAGE,
		"PLAY" if _vis18r_playing else "PAUSE",
		_vis21_fork_generation,
		_vis18r_generation,
		_vis21_treatment_profile,
		int(round(_vis21_treatment_intensity * 100.0)),
		_vis18r_current_visual_count,
	]


func _update_status() -> void:
	super._update_status()
	var status := get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	if status == null:
		return
	var lod := {}
	if _vis18r_renderer != null:
		lod = Dictionary(_vis18r_renderer.call("lod_summary"))
	status.text += "\nVIS2.1-V realtime Treatment LOD=%s | near<=%.0fm mid=%.0f..%.0fm far>=%.0fm | tiers=%d/%d/%d" % [
		"ACTIVE" if bool(lod.get("enabled", false)) else "READY",
		float(lod.get("near_lod_end_m", 110.0)),
		float(lod.get("mid_lod_begin_m", 75.0)),
		float(lod.get("mid_lod_end_m", 240.0)),
		float(lod.get("far_lod_begin_m", 190.0)),
		int(lod.get("near_tier_count", 0)),
		int(lod.get("mid_tier_count", 0)),
		int(lod.get("far_tier_count", 0)),
	]
