extends SceneTree

const Vis55 = preload("res://scripts/labs/ecology/eco_evo7_vis5_5_visual_evidence_play1_handoff.gd")
const Report = preload("res://scripts/ecology/perf/eco_evo7_perf2_conv_play1_integrated_report_v1.gd")
const Perf2Report = preload("res://scripts/ecology/perf/eco_evo7_perf2_conv_integrated_report_v1.gd")

const ARTIFACT_PATH := "res://artifacts/perf2/perf2-conv-play1-integrated-r1.json"
const PERF2_ACCEPTANCE_PATH := "res://docs/checkpoints/2026-09-04_ECO_EVO7_PERF2_CONV_R3_ACCEPTED_RU.md"
const VIS55_CLOSURE_PATH := "res://docs/checkpoints/2026-09-04_ECO_EVO7_VIS5_5_VISUAL_EVIDENCE_INTEGRATED_PLAY1_HANDOFF_EXACT_VERIFIED_CLOSED_R1_RU.md"
const VIS55_HANDOFF_CONTRACT_PATH := "res://config/ecology/eco-evo7-vis5-5-play1-handoff.v1.json"

var assertions := 0
var failures: Array[String] = []
var _finished := false


func _init() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _run() -> void:
	_contract_checks()
	var immutable := _immutable_evidence()
	_check(not immutable.is_empty(), "PLAY1 immutable PERF2.CONV + VIS5.5 evidence is present")
	if immutable.is_empty():
		_finish()
		return

	var samples: Array = []
	for repetition in range(Report.REPETITIONS):
		var lab = Vis55.new()
		lab.auto_initialize = false
		lab.show_operator_hud = false
		root.add_child(lab)
		await process_frame

		var init_start := Time.get_ticks_usec()
		var initialized: bool = lab.initialize_runtime()
		var initialize_ms := float(Time.get_ticks_usec() - init_start) / 1000.0
		_check(initialized, "PLAY1 rep %d VIS5.5 initializes" % repetition)
		_check(initialize_ms <= Report.MAX_SINGLE_BOUNDED_OPERATION_MS, "PLAY1 rep %d initialization under inherited hard stall" % repetition)
		if not initialized:
			lab.queue_free()
			await process_frame
			_finish()
			return

		var initial_package: Dictionary = lab.get_handoff_package()
		_check(Vis55.validate_handoff_package(initial_package), "PLAY1 rep %d initial handoff validates" % repetition)
		_check(String(initial_package.get("visual_line_status", "")) == "READY_FOR_PLAY1_HANDOFF", "PLAY1 VIS5 visual line ready")
		_check(not bool(initial_package.get("play1_performance_accepted", true)), "PLAY1 VIS5 alone does not claim performance acceptance")
		_check(bool(initial_package.get("perf2_convergence_required", false)), "PLAY1 VIS5 requires PERF2.CONV join")

		var source_hash := String(initial_package.get("source_ecology_hash", ""))
		var composition_hash := String(initial_package.get("composition_hash", ""))
		var bridge_hash := String(initial_package.get("macro_bridge_hash", ""))
		var descriptor_hash := String(initial_package.get("descriptor_adapter_hash", ""))

		var view_sequence_start := Time.get_ticks_usec()
		var max_view_ms := 0.0
		for view_id in [
			Vis55.VIEW_NEAR_OVERVIEW,
			Vis55.VIEW_MID_CONTEXT,
			Vis55.VIEW_FAR_CONTEXT,
			Vis55.VIEW_CULLED_CONTEXT,
			Vis55.VIEW_NEAR_OVERVIEW,
		]:
			var view_start := Time.get_ticks_usec()
			var view_ok: bool = lab.set_evidence_view(view_id)
			var view_ms := float(Time.get_ticks_usec() - view_start) / 1000.0
			max_view_ms = maxf(max_view_ms, view_ms)
			_check(view_ok, "PLAY1 rep %d view %s applies" % [repetition, view_id])
			_check(view_ms <= Report.MAX_SINGLE_BOUNDED_OPERATION_MS, "PLAY1 rep %d view %s under inherited hard stall" % [repetition, view_id])
		var view_sequence_ms := float(Time.get_ticks_usec() - view_sequence_start) / 1000.0

		var after_views: Dictionary = lab.get_handoff_package()
		_check(String(after_views.get("source_ecology_hash", "")) == source_hash, "PLAY1 rep %d LOD views preserve ecology source" % repetition)
		_check(String(after_views.get("macro_bridge_hash", "")) == bridge_hash, "PLAY1 rep %d LOD views preserve PH5 bridge" % repetition)
		_check(String(after_views.get("descriptor_adapter_hash", "")) == descriptor_hash, "PLAY1 rep %d LOD views preserve Descriptor V2 adapter" % repetition)
		_check(String(after_views.get("composition_hash", "")) == composition_hash, "PLAY1 rep %d LOD views preserve composition identity" % repetition)

		var lifecycle_start := Time.get_ticks_usec()
		var lifecycle: Dictionary = lab.perform_handoff_lifecycle_evidence()
		var lifecycle_ms := float(Time.get_ticks_usec() - lifecycle_start) / 1000.0
		_check(not lifecycle.is_empty() and bool(lifecycle.get("success", false)), "PLAY1 rep %d recenter + real region roundtrip succeeds" % repetition)
		_check(lifecycle_ms <= Report.MAX_SINGLE_BOUNDED_OPERATION_MS, "PLAY1 rep %d lifecycle under inherited hard stall" % repetition)

		var final_package: Dictionary = lab.get_handoff_package()
		var handoff_valid := Vis55.validate_handoff_package(final_package)
		_check(handoff_valid, "PLAY1 rep %d final handoff validates" % repetition)
		_check(bool(final_package.get("lifecycle_evidence_complete", false)), "PLAY1 rep %d lifecycle evidence complete" % repetition)
		_check(not bool(final_package.get("ecology_identity_drift", true)), "PLAY1 rep %d ecology identity has no drift" % repetition)
		_check(bool(final_package.get("same_seed_roundtrip_verified", false)), "PLAY1 rep %d same-seed roundtrip restored" % repetition)
		_check(int(final_package.get("render_origin_recenter_count", 0)) >= 2, "PLAY1 rep %d render-origin recenter/restore observed" % repetition)
		_check(int(final_package.get("local_surface_rebuild_count", 0)) >= 2, "PLAY1 rep %d real Earth rebuilds observed" % repetition)
		_check(int(final_package.get("region_roundtrip_count", 0)) >= 1, "PLAY1 rep %d region roundtrip observed" % repetition)
		_check(String(final_package.get("source_ecology_hash", "")) == source_hash, "PLAY1 rep %d lifecycle preserves ecology source" % repetition)
		_check(String(final_package.get("macro_bridge_hash", "")) == bridge_hash, "PLAY1 rep %d lifecycle preserves PH5 bridge" % repetition)
		_check(String(final_package.get("descriptor_adapter_hash", "")) == descriptor_hash, "PLAY1 rep %d lifecycle preserves Descriptor V2 adapter" % repetition)
		_check(String(final_package.get("composition_hash", "")) == composition_hash, "PLAY1 rep %d lifecycle restores composition hash" % repetition)

		var truth_green := (
			String(final_package.get("terrain_source", "")) == "ProceduralEarthWorld"
			and String(final_package.get("macro_truth_status", "")) == "CANONICAL_ECO_VIS4_PH5"
			and String(final_package.get("ground_cover_truth_status", "")) == "NONCANONICAL_SCENERY"
			and String(final_package.get("rock_truth_status", "")) == "TERRAIN_SCENERY"
			and bool(final_package.get("procedural_tree_placement_suppressed", false))
			and bool(final_package.get("workload_is_proxy", false))
			and bool(final_package.get("frame_diagnostics_observational_only", false))
		)
		_check(truth_green, "PLAY1 rep %d truth/diagnostic boundary exact" % repetition)
		_check(int(final_package.get("macro_record_count", 0)) > 0, "PLAY1 rep %d macro plants materialized" % repetition)
		_check(int(final_package.get("ground_cover_instances", 0)) > 0, "PLAY1 rep %d ground cover materialized" % repetition)
		_check(int(final_package.get("rock_instances", 0)) > 0, "PLAY1 rep %d terrain rocks materialized" % repetition)

		var max_operation_ms := maxf(initialize_ms, maxf(max_view_ms, lifecycle_ms))
		samples.append({
			"repetition": repetition,
			"initialize_ms": initialize_ms,
			"view_sequence_ms": view_sequence_ms,
			"lifecycle_ms": lifecycle_ms,
			"max_bounded_operation_ms": max_operation_ms,
			"source_ecology_hash": source_hash,
			"composition_hash": composition_hash,
			"macro_bridge_hash": bridge_hash,
			"descriptor_adapter_hash": descriptor_hash,
			"lifecycle_green": bool(lifecycle.get("success", false)) and bool(final_package.get("lifecycle_evidence_complete", false)),
			"truth_green": truth_green,
			"ecology_identity_drift": bool(final_package.get("ecology_identity_drift", true)),
			"macro_records": int(final_package.get("macro_record_count", 0)),
			"ground_cover": int(final_package.get("ground_cover_instances", 0)),
			"rocks": int(final_package.get("rock_instances", 0)),
			"render_recenter_count": int(final_package.get("render_origin_recenter_count", 0)),
			"earth_rebuild_count": int(final_package.get("local_surface_rebuild_count", 0)),
			"region_roundtrip_count": int(final_package.get("region_roundtrip_count", 0)),
		})

		lab.queue_free()
		await process_frame
		await process_frame

	var target := {
		"head": OS.get_environment("ECO_PLAY1_TARGET_HEAD"),
		"tree": OS.get_environment("ECO_PLAY1_TARGET_TREE"),
	}
	_check(String(target["head"]).length() == 40, "PLAY1 target HEAD supplied by runner")
	_check(String(target["tree"]).length() == 40, "PLAY1 target TREE supplied by runner")

	var report: Dictionary = Report.build(samples, target, immutable)
	_check(not report.is_empty(), "PLAY1 integrated report builds")
	_check(Report.validate(report), "PLAY1 integrated report validates")
	if report.is_empty():
		_finish()
		return
	var summary: Dictionary = Dictionary(report.get("summary", {}))
	var claims: Dictionary = Dictionary(report.get("claims", {}))
	_check(bool(summary.get("lifecycle_green", false)), "PLAY1 lifecycle summary GREEN")
	_check(bool(summary.get("truth_green", false)), "PLAY1 truth summary GREEN")
	_check(bool(summary.get("deterministic_source_green", false)), "PLAY1 deterministic source summary GREEN")
	_check(bool(summary.get("hard_stall_green", false)), "PLAY1 inherited hard-stall summary GREEN")
	_check(bool(claims.get("perf2_conv_immutable_accepted", false)), "PLAY1 joins accepted PERF2.CONV")
	_check(bool(claims.get("vis5_5_immutable_closed", false)), "PLAY1 joins exact-closed VIS5.5")
	_check(bool(claims.get("play1_visual_composition_correctness", false)), "PLAY1 visual composition correctness claim GREEN")
	_check(bool(claims.get("play1_lifecycle_hard_stall_green", false)), "PLAY1 lifecycle hard-stall claim GREEN")
	_check(bool(claims.get("play1_integrated_acceptance", false)), "PLAY1 integrated acceptance claim GREEN")
	_check(_write_and_revalidate_artifact(report), "PLAY1 integrated JSON artifact round-trip validates")
	_tamper_guards(report)
	_source_guards()

	print("PLAY1 p50 initialize ms: %.3f" % float(summary.get("p50_initialize_ms", 0.0)))
	print("PLAY1 p95 view sequence ms: %.3f" % float(summary.get("p95_view_sequence_ms", 0.0)))
	print("PLAY1 p95 lifecycle ms: %.3f" % float(summary.get("p95_lifecycle_ms", 0.0)))
	print("PLAY1 max bounded operation ms: %.3f / %.1f" % [float(summary.get("max_bounded_operation_ms", 0.0)), Report.MAX_SINGLE_BOUNDED_OPERATION_MS])
	print("PLAY1 report hash: %s" % String(report.get("report_hash", "")))
	print("ECO.EVO7 PERF2.CONV / PLAY1 integrated acceptance: PASS")
	_finish()


func _contract_checks() -> void:
	_check(Report.REPETITIONS == 3, "PLAY1 repeats real VIS5.5 lifecycle three times")
	_check(Report.MAX_SINGLE_BOUNDED_OPERATION_MS == Perf2Report.MAX_SINGLE_COMBINED_GENERATION_MS, "PLAY1 hard stall exactly inherited from PERF2.CONV")
	_check(Perf2Report.MAX_P50_COMBINED_TO_SIM_RATIO == 2.50, "PLAY1 does not change PERF2 p50 ratio budget")
	_check(Perf2Report.MAX_P95_COMBINED_TO_SIM_RATIO == 4.00, "PLAY1 does not change PERF2 p95 ratio budget")
	_check(Perf2Report.MAX_CACHE_ENTRIES_PER_RECORD == 5, "PLAY1 does not change PERF2 PH5 cache bound")
	_check(Vis55.PRESENTATION_ONLY, "PLAY1 VIS5.5 remains presentation-only")
	_check(not Vis55.PERF2_AUTHORITY, "PLAY1 VIS5.5 owns no PERF2 authority")
	_check(not Vis55.PLAY1_PERFORMANCE_ACCEPTED, "PLAY1 starts from non-accepted VIS5.5 handoff state")


func _immutable_evidence() -> Dictionary:
	var perf_text := FileAccess.get_file_as_string(PERF2_ACCEPTANCE_PATH)
	var vis_text := FileAccess.get_file_as_string(VIS55_CLOSURE_PATH)
	var handoff_text := FileAccess.get_file_as_string(VIS55_HANDOFF_CONTRACT_PATH)
	if perf_text.is_empty() or vis_text.is_empty() or handoff_text.is_empty():
		return {}
	for token in [Report.PERF2_CONV_RUNTIME_HEAD, Report.PERF2_CONV_RUNTIME_TREE, Report.PERF2_CONV_ACCEPTED_CONTROL_HEAD, Report.PERF2_CONV_REPORT_HASH, "1.517", "1.590", "2501.0"]:
		if not perf_text.contains(token):
			return {}
	for token in [Report.VIS5_5_EXECUTABLE_HEAD, Report.VIS5_5_EXECUTABLE_TREE, Report.VIS5_5_SOURCE_SHA256, Report.VIS5_5_CAPTURE_BUNDLE_HASH, Report.VIS5_5_MANIFEST_SHA256, Report.VIS5_5_HANDOFF_HASH]:
		if not vis_text.contains(token):
			return {}
	if not handoff_text.contains("VIS5.5 GREEN + PERF2.CONV GREEN -> PLAY1 integrated acceptance"):
		return {}
	return {
		"perf2_conv_accepted": true,
		"perf2_conv_runtime_head": Report.PERF2_CONV_RUNTIME_HEAD,
		"perf2_conv_runtime_tree": Report.PERF2_CONV_RUNTIME_TREE,
		"perf2_conv_accepted_control_head": Report.PERF2_CONV_ACCEPTED_CONTROL_HEAD,
		"perf2_conv_report_hash": Report.PERF2_CONV_REPORT_HASH,
		"perf2_conv_p50_ratio": Report.PERF2_CONV_P50_RATIO,
		"perf2_conv_p95_ratio": Report.PERF2_CONV_P95_RATIO,
		"perf2_conv_max_combined_ms": Report.PERF2_CONV_MAX_COMBINED_MS,
		"vis5_5_closed": true,
		"vis5_5_executable_head": Report.VIS5_5_EXECUTABLE_HEAD,
		"vis5_5_executable_tree": Report.VIS5_5_EXECUTABLE_TREE,
		"vis5_5_closure_head": Report.VIS5_5_CLOSURE_HEAD,
		"vis5_5_source_sha256": Report.VIS5_5_SOURCE_SHA256,
		"vis5_5_capture_bundle_hash": Report.VIS5_5_CAPTURE_BUNDLE_HASH,
		"vis5_5_manifest_sha256": Report.VIS5_5_MANIFEST_SHA256,
		"vis5_5_handoff_hash": Report.VIS5_5_HANDOFF_HASH,
	}


func _write_and_revalidate_artifact(report: Dictionary) -> bool:
	var absolute := ProjectSettings.globalize_path(ARTIFACT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(absolute))
	return parsed is Dictionary and Report.validate(Dictionary(parsed))


func _tamper_guards(report: Dictionary) -> void:
	var bad_perf := report.duplicate(true)
	var immutable: Dictionary = Dictionary(bad_perf["immutable_evidence"]).duplicate(true)
	immutable["perf2_conv_report_hash"] = "f".repeat(64)
	bad_perf["immutable_evidence"] = immutable
	_check(not Report.validate(bad_perf), "PLAY1 rejects PERF2.CONV evidence tamper")

	var bad_vis := report.duplicate(true)
	var vis_immutable: Dictionary = Dictionary(bad_vis["immutable_evidence"]).duplicate(true)
	vis_immutable["vis5_5_handoff_hash"] = "0".repeat(64)
	bad_vis["immutable_evidence"] = vis_immutable
	_check(not Report.validate(bad_vis), "PLAY1 rejects VIS5.5 evidence tamper")

	var bad_claim := report.duplicate(true)
	var claims: Dictionary = Dictionary(bad_claim["claims"]).duplicate(true)
	claims["play1_integrated_acceptance"] = false
	bad_claim["claims"] = claims
	_check(not Report.validate(bad_claim), "PLAY1 rejects integrated-claim tamper")


func _source_guards() -> void:
	var report_source := FileAccess.get_file_as_string("res://scripts/ecology/perf/eco_evo7_perf2_conv_play1_integrated_report_v1.gd").to_lower()
	var vis_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis5_5_visual_evidence_play1_handoff.gd").to_lower()
	_check(report_source.contains("accepted_perf2_campaign_not_rerolled"), "PLAY1 records no-reroll policy for accepted PERF2 campaign")
	_check(report_source.contains("gpu_acceptance_not_inferred_from_llvmpipe"), "PLAY1 forbids llvmpipe GPU acceptance inference")
	_check(report_source.contains("timings_noncanonical"), "PLAY1 lifecycle timings remain noncanonical")
	_check(not report_source.contains("multiplayer") and not report_source.contains("persistence_write\": true"), "PLAY1 report has no network/persistence execution path")
	_check(vis_source.contains("play1_performance_accepted := false"), "PLAY1 joins a VIS5.5 source that cannot self-authorize performance")


func _watchdog() -> void:
	var deadline := Time.get_ticks_msec() + 240000
	while Time.get_ticks_msec() < deadline and not _finished:
		await process_frame
	if not _finished:
		failures.append("WATCHDOG: PLAY1 integrated acceptance exceeded 240s")
		_finish()


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % label)
	else:
		failures.append(label)
		push_error("FAIL: %s" % label)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if failures.is_empty():
		print("ECO.EVO7 PERF2.CONV / PLAY1: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("ECO.EVO7 PERF2.CONV / PLAY1: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
