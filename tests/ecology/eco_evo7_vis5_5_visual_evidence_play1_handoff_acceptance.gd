extends SceneTree

const Vis55 = preload("res://scripts/labs/ecology/eco_evo7_vis5_5_visual_evidence_play1_handoff.gd")
const Vis54 = preload("res://scripts/labs/ecology/eco_evo7_vis5_4_composition_lod_streaming_gate.gd")

var assertions := 0
var failures: Array[String] = []
var _finished := false


func _initialize() -> void:
	call_deferred("_run")
	_watchdog()


func _run() -> void:
	var packed := load("res://scenes/labs/ecology/eco_evo7_vis5_5_visual_evidence_play1_handoff.tscn") as PackedScene
	_check(packed != null, "VIS5.5 scene parses")
	if packed == null:
		_finish()
		return
	var host = packed.instantiate()
	host.auto_initialize = false
	root.add_child(host)
	var profile := {
		"ground_cover_max_instances": 650,
		"max_rocks": 55,
		"rock_attempts_multiplier": 24,
	}
	_check(host.initialize_runtime(profile), "VIS5.5 runtime initializes over real VIS5.3/5.4")
	if not host.initialized:
		host.queue_free()
		_finish()
		return

	var contract_text := FileAccess.get_file_as_string("res://config/ecology/eco-evo7-vis5-5-play1-handoff.v1.json")
	var contract_value = JSON.parse_string(contract_text)
	_check(contract_value is Dictionary, "PLAY1 handoff contract parses")
	if contract_value is Dictionary:
		var contract: Dictionary = contract_value
		_check(String(contract.get("contract_state", "")) == "FROZEN", "PLAY1 handoff contract frozen")
		_check(String(contract.get("visual_line_status_on_green", "")) == Vis55.VISUAL_LINE_STATUS, "contract maps green to visual handoff readiness")
		var final_join: Dictionary = contract.get("final_join", {})
		_check(bool(final_join.get("perf2_convergence_required", false)), "static contract requires PERF2.CONV")
		_check(not bool(final_join.get("play1_performance_accepted_by_vis5_5", true)), "static contract forbids VIS5.5 performance acceptance")
		var contract_views: Array = contract.get("capture_views", [])
		_check(contract_views.size() == 6, "static contract freezes six visual evidence views")

	var handoff: Dictionary = host.get_handoff_package()
	_check(Vis55.validate_handoff_package(handoff), "initial PLAY1 handoff validates")
	_check(String(handoff.get("visual_line_status", "")) == Vis55.VISUAL_LINE_STATUS, "visual line declares READY_FOR_PLAY1_HANDOFF")
	_check(bool(handoff.get("visual_composition_ready", false)), "visual composition ready")
	_check(bool(handoff.get("play1_handoff_ready", false)), "PLAY1 handoff ready")
	_check(bool(handoff.get("perf2_convergence_required", false)), "PERF2.CONV remains required")
	_check(not bool(handoff.get("play1_performance_accepted", true)), "VIS5.5 does not claim PLAY1 performance acceptance")
	_check(not bool(handoff.get("perf2_authority", true)), "VIS5.5 owns no PERF2 authority")
	_check(not bool(handoff.get("ecology_authority", true)), "VIS5.5 owns no ecology authority")
	_check(not bool(handoff.get("terrain_authority", true)), "VIS5.5 owns no terrain authority")
	_check(not bool(handoff.get("network_authority", true)), "VIS5.5 owns no network authority")
	_check(not bool(handoff.get("persistence_authority", true)), "VIS5.5 owns no persistence authority")
	_check(String(handoff.get("terrain_source", "")) == "ProceduralEarthWorld", "real ProceduralEarth remains terrain source")
	_check(String(handoff.get("macro_truth_status", "")) == "CANONICAL_ECO_VIS4_PH5", "macro plants truth label canonical")
	_check(String(handoff.get("ground_cover_truth_status", "")) == "NONCANONICAL_SCENERY", "ground cover truth label explicit")
	_check(String(handoff.get("rock_truth_status", "")) == "TERRAIN_SCENERY", "rock truth label explicit")
	_check(int(handoff.get("macro_record_count", 0)) > 0, "canonical macro records present")
	_check(int(handoff.get("ground_cover_instances", 0)) == 650, "test ground-cover stratum present")
	_check(int(handoff.get("rock_instances", 0)) == 55, "test rock stratum present")
	_check(float(handoff.get("terrain_relief_range_m", 0.0)) > 10.0, "uneven real terrain evidenced")
	_check(float(handoff.get("terrain_maximum_geometric_slope_deg", 0.0)) > 1.0, "nonzero geometric terrain slope evidenced")
	_check(bool(handoff.get("procedural_tree_placement_suppressed", false)), "legacy ProceduralEarth trees remain suppressed")
	_check(bool(handoff.get("workload_is_proxy", false)), "workload counters explicitly proxies")
	_check(bool(handoff.get("frame_diagnostics_observational_only", false)), "frame diagnostics observational only")
	_check(String(handoff.get("source_ecology_hash", "")).length() == 64, "source ecology identity present")
	_check(String(handoff.get("macro_bridge_hash", "")).length() == 64, "PH5 bridge identity present")
	_check(String(handoff.get("descriptor_adapter_hash", "")).length() == 64, "Descriptor V2 identity present")
	_check(String(handoff.get("composition_hash", "")).length() == 64, "mixed composition hash present")
	_check(String(handoff.get("handoff_hash", "")).length() == 64, "handoff structural hash present")

	var capture_plan: Array[Dictionary] = host.get_capture_plan()
	_check(capture_plan.size() == 6, "durable capture plan has six evidence views")
	var seen_modes := {}
	for item in capture_plan:
		seen_modes[String(item.get("expected_mode", ""))] = true
		_check(String(item.get("filename", "")).ends_with(".png"), "capture plan item has PNG filename")
		_check(bool(item.get("truth_overlay_required", false)), "capture plan requires truth overlay")
	for mode in [Vis54.MODE_NEAR, Vis54.MODE_MID, Vis54.MODE_FAR, Vis54.MODE_CULLED]:
		_check(seen_modes.has(mode), "capture plan covers mode " + mode)

	var expected_views := [
		[Vis55.VIEW_NEAR_OVERVIEW, Vis54.MODE_NEAR],
		[Vis55.VIEW_NEAR_DETAIL, Vis54.MODE_NEAR],
		[Vis55.VIEW_MID_CONTEXT, Vis54.MODE_MID],
		[Vis55.VIEW_FAR_CONTEXT, Vis54.MODE_FAR],
		[Vis55.VIEW_CULLED_CONTEXT, Vis54.MODE_CULLED],
	]
	var source_hash := String(handoff.get("source_ecology_hash", ""))
	var bridge_hash := String(handoff.get("macro_bridge_hash", ""))
	var descriptor_hash := String(handoff.get("descriptor_adapter_hash", ""))
	for pair in expected_views:
		_check(host.set_evidence_view(String(pair[0])), "view switch succeeds: " + String(pair[0]))
		var state: Dictionary = host.get_handoff_package()
		_check(String(state.get("current_mode", "")) == String(pair[1]), "view selects expected composition mode: " + String(pair[0]))
		_check(String(state.get("source_ecology_hash", "")) == source_hash, "view switch preserves ecology source")
		_check(String(state.get("macro_bridge_hash", "")) == bridge_hash, "view switch preserves PH5 bridge")
		_check(String(state.get("descriptor_adapter_hash", "")) == descriptor_hash, "view switch preserves Descriptor V2 identity")

	_check(host.hud_layer != null and host.hud_panel != null, "operator HUD exists")
	_check(host.hud_truth != null and host.hud_truth.text.contains("CANONICAL ECO/VIS4 PH5"), "HUD identifies canonical ecology")
	_check(host.hud_truth.text.contains("NONCANONICAL_SCENERY"), "HUD identifies noncanonical ground cover")
	_check(host.hud_truth.text.contains("TERRAIN_SCENERY"), "HUD identifies terrain scenery")
	_check(host.hud_truth.text.contains("PROXIES ONLY"), "HUD marks workload as proxy")
	_check(host.hud_truth.text.contains("PERF2.CONV REQUIRED"), "HUD states final join dependency")

	var lifecycle: Dictionary = host.perform_handoff_lifecycle_evidence()
	_check(not lifecycle.is_empty() and bool(lifecycle.get("success", false)), "handoff lifecycle evidence succeeds")
	_check(bool(lifecycle.get("source_identity_stable", false)), "lifecycle keeps source identity stable")
	_check(bool(lifecycle.get("composition_hash_restored", false)), "lifecycle restores exact composition hash")
	var roundtrip: Dictionary = lifecycle.get("roundtrip", {})
	_check(int(roundtrip.get("rebuild_events", 0)) >= 2, "lifecycle observes real remote + return Earth rebuilds")
	_check(bool(roundtrip.get("remote_placement_suppressed", false)), "remote Earth rebuild suppresses legacy placement")
	_check(bool(roundtrip.get("return_placement_suppressed", false)), "return Earth rebuild suppresses legacy placement")
	var final_handoff: Dictionary = host.get_handoff_package()
	_check(Vis55.validate_handoff_package(final_handoff), "final handoff validates after lifecycle")
	_check(bool(final_handoff.get("lifecycle_evidence_complete", false)), "handoff records completed recenter/streaming evidence")
	_check(int(final_handoff.get("render_origin_recenter_count", 0)) >= 2, "handoff exposes recenter evidence")
	_check(int(final_handoff.get("local_surface_rebuild_count", 0)) >= 2, "handoff exposes Earth rebuild evidence")
	_check(int(final_handoff.get("region_roundtrip_count", 0)) >= 1, "handoff exposes region roundtrip evidence")
	_check(bool(final_handoff.get("same_seed_roundtrip_verified", false)), "handoff preserves same-seed/region deterministic restoration")
	_check(not bool(final_handoff.get("ecology_identity_drift", true)), "handoff reports no ecology identity drift")
	_check(String(final_handoff.get("current_view_id", "")) == Vis55.VIEW_RETURN_AFTER_STREAMING, "lifecycle ends on operator-readable return view")
	_check(String(final_handoff.get("current_mode", "")) == Vis54.MODE_NEAR, "return view restores NEAR composition mode")

	var tampered: Dictionary = final_handoff.duplicate(true)
	tampered["play1_performance_accepted"] = true
	_check(not Vis55.validate_handoff_package(tampered), "premature PLAY1 performance acceptance rejected")
	tampered = final_handoff.duplicate(true)
	tampered["perf2_convergence_required"] = false
	_check(not Vis55.validate_handoff_package(tampered), "handoff without PERF2.CONV dependency rejected")
	tampered = final_handoff.duplicate(true)
	tampered["ground_cover_truth_status"] = "CANONICAL_ECOLOGY"
	_check(not Vis55.validate_handoff_package(tampered), "ground cover authority inflation rejected")
	tampered = final_handoff.duplicate(true)
	tampered["workload_is_proxy"] = false
	_check(not Vis55.validate_handoff_package(tampered), "unlabeled workload counters rejected")

	_source_boundary_checks()
	host.queue_free()
	await process_frame
	_finish()


func _source_boundary_checks() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis5_5_visual_evidence_play1_handoff.gd").to_lower()
	_check(source.contains("vis5.3") and source.contains("vis5.4"), "VIS5.5 composes accepted VIS5.3 and VIS5.4")
	_check(source.contains("capture_evidence_bundle"), "VIS5.5 exposes repeatable capture path")
	_check(source.contains("truthandhandoffpanel"), "VIS5.5 exposes operator truth overlay")
	_check(source.contains("perf2_convergence_required"), "source preserves PERF2.CONV join boundary")
	_check(source.contains("play1_performance_accepted"), "source explicitly carries PLAY1 acceptance state")
	_check(not source.contains("reproduce_bundle("), "VIS5.5 owns no reproduction")
	_check(not source.contains("mutation_seed("), "VIS5.5 owns no mutation")
	_check(not source.contains("advance_generations("), "VIS5.5 owns no generation mutation")
	_check(not source.contains("rpc(") and not source.contains("multiplayer"), "VIS5.5 owns no network implementation")
	_check(not source.contains("perf2.4"), "VIS5.5 does not touch PERF2.4")
	_check(not source.contains("get_tree_mesh") and not source.contains("tree_density"), "VIS5.5 owns no procedural-tree source")


func _watchdog() -> void:
	var deadline := Time.get_ticks_msec() + 210000
	while Time.get_ticks_msec() < deadline and not _finished:
		await process_frame
	if not _finished:
		push_error("ECO.EVO7 VIS5.5 watchdog timeout")
		print("ECO.EVO7 VIS5.5 Visual Evidence / Integrated PLAY1 Handoff: FAIL (watchdog timeout)")
		quit(1)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("VIS5.5: " + label)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if failures.is_empty():
		print("ECO.EVO7 VIS5.5 Visual Evidence / Integrated PLAY1 Handoff: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("FAIL: " + failure)
	print("ECO.EVO7 VIS5.5 Visual Evidence / Integrated PLAY1 Handoff: FAIL (%d/%d)" % [failures.size(), assertions])
	quit(1)
