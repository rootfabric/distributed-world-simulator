extends SceneTree

const Vis55 = preload("res://scripts/labs/ecology/eco_evo7_vis5_5_visual_evidence_play1_handoff.gd")
const Report = preload("res://scripts/ecology/perf/eco_evo7_perf2_conv_play1_integrated_report_v1.gd")

var assertions := 0
var failures: Array[String] = []
var _finished := false


func _init() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _run() -> void:
	var repetition := int(OS.get_environment("ECO_PLAY1_REPETITION"))
	var sample_path := OS.get_environment("ECO_PLAY1_SAMPLE_PATH")
	_check(repetition >= 0 and repetition < Report.REPETITIONS, "PLAY1 worker repetition index valid")
	_check(not sample_path.is_empty(), "PLAY1 worker sample path supplied")
	if not failures.is_empty():
		_finish()
		return

	var lab = Vis55.new()
	lab.auto_initialize = false
	lab.show_operator_hud = false
	root.add_child(lab)
	await process_frame

	var init_start := Time.get_ticks_usec()
	var initialized: bool = lab.initialize_runtime()
	var initialize_ms := float(Time.get_ticks_usec() - init_start) / 1000.0
	_check(initialized, "PLAY1 worker VIS5.5 initializes")
	if not initialized:
		_finish()
		return

	var initial_package: Dictionary = lab.get_handoff_package()
	_check(Vis55.validate_handoff_package(initial_package), "PLAY1 worker initial handoff validates")
	_check(String(initial_package.get("visual_line_status", "")) == "READY_FOR_PLAY1_HANDOFF", "PLAY1 worker visual line ready")
	_check(not bool(initial_package.get("play1_performance_accepted", true)), "PLAY1 worker VIS5.5 cannot self-authorize performance")
	_check(bool(initial_package.get("perf2_convergence_required", false)), "PLAY1 worker VIS5.5 requires PERF2.CONV")

	var source_hash := String(initial_package.get("source_ecology_hash", ""))
	var composition_hash := String(initial_package.get("composition_hash", ""))
	var bridge_hash := String(initial_package.get("macro_bridge_hash", ""))
	var descriptor_hash := String(initial_package.get("descriptor_adapter_hash", ""))
	var earth = lab.lab.get_earth_world()
	var initial_surface_rebuild_ms := float(earth.last_rebuild_summary.get("elapsed_ms", 0.0))
	_check(initial_surface_rebuild_ms > 0.0, "PLAY1 worker observes initial atomic Earth surface rebuild")

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
		_check(view_ok, "PLAY1 worker view %s applies" % view_id)
		_check(view_ms <= Report.MAX_SINGLE_BOUNDED_OPERATION_MS, "PLAY1 worker view %s below inherited hard-stall ceiling" % view_id)
	var view_sequence_ms := float(Time.get_ticks_usec() - view_sequence_start) / 1000.0

	var after_views: Dictionary = lab.get_handoff_package()
	_check(String(after_views.get("source_ecology_hash", "")) == source_hash, "PLAY1 worker LOD views preserve ecology source")
	_check(String(after_views.get("macro_bridge_hash", "")) == bridge_hash, "PLAY1 worker LOD views preserve PH5 bridge")
	_check(String(after_views.get("descriptor_adapter_hash", "")) == descriptor_hash, "PLAY1 worker LOD views preserve Descriptor adapter")
	_check(String(after_views.get("composition_hash", "")) == composition_hash, "PLAY1 worker LOD views preserve composition hash")

	var lifecycle_start := Time.get_ticks_usec()
	var lifecycle: Dictionary = lab.perform_handoff_lifecycle_evidence()
	var lifecycle_ms := float(Time.get_ticks_usec() - lifecycle_start) / 1000.0
	_check(not lifecycle.is_empty() and bool(lifecycle.get("success", false)), "PLAY1 worker recenter + real region roundtrip succeeds")

	var final_package: Dictionary = lab.get_handoff_package()
	var return_surface_rebuild_ms := float(earth.last_rebuild_summary.get("elapsed_ms", 0.0))
	_check(return_surface_rebuild_ms > 0.0, "PLAY1 worker observes return atomic Earth surface rebuild")
	var max_bounded_operation_ms := maxf(max_view_ms, maxf(initial_surface_rebuild_ms, return_surface_rebuild_ms))
	_check(max_bounded_operation_ms <= Report.MAX_SINGLE_BOUNDED_OPERATION_MS, "PLAY1 worker atomic stages below inherited 5000ms hard-stall ceiling")

	_check(Vis55.validate_handoff_package(final_package), "PLAY1 worker final handoff validates")
	_check(bool(final_package.get("lifecycle_evidence_complete", false)), "PLAY1 worker lifecycle evidence complete")
	_check(not bool(final_package.get("ecology_identity_drift", true)), "PLAY1 worker ecology identity stable")
	_check(bool(final_package.get("same_seed_roundtrip_verified", false)), "PLAY1 worker same-seed roundtrip restored")
	_check(int(final_package.get("render_origin_recenter_count", 0)) >= 2, "PLAY1 worker recenter + restore observed")
	_check(int(final_package.get("local_surface_rebuild_count", 0)) >= 2, "PLAY1 worker two real surface rebuilds observed")
	_check(int(final_package.get("region_roundtrip_count", 0)) >= 1, "PLAY1 worker region roundtrip observed")
	_check(String(final_package.get("source_ecology_hash", "")) == source_hash, "PLAY1 worker lifecycle preserves ecology source")
	_check(String(final_package.get("macro_bridge_hash", "")) == bridge_hash, "PLAY1 worker lifecycle preserves PH5 bridge")
	_check(String(final_package.get("descriptor_adapter_hash", "")) == descriptor_hash, "PLAY1 worker lifecycle preserves Descriptor adapter")
	_check(String(final_package.get("composition_hash", "")) == composition_hash, "PLAY1 worker lifecycle restores composition hash")

	var truth_green := (
		String(final_package.get("terrain_source", "")) == "ProceduralEarthWorld"
		and String(final_package.get("macro_truth_status", "")) == "CANONICAL_ECO_VIS4_PH5"
		and String(final_package.get("ground_cover_truth_status", "")) == "NONCANONICAL_SCENERY"
		and String(final_package.get("rock_truth_status", "")) == "TERRAIN_SCENERY"
		and bool(final_package.get("procedural_tree_placement_suppressed", false))
		and bool(final_package.get("workload_is_proxy", false))
		and bool(final_package.get("frame_diagnostics_observational_only", false))
	)
	_check(truth_green, "PLAY1 worker truth and diagnostic boundary exact")
	_check(int(final_package.get("macro_record_count", 0)) > 0, "PLAY1 worker macro plants materialized")
	_check(int(final_package.get("ground_cover_instances", 0)) > 0, "PLAY1 worker ground cover materialized")
	_check(int(final_package.get("rock_instances", 0)) > 0, "PLAY1 worker terrain rocks materialized")

	var sample := {
		"repetition": repetition,
		"initialize_ms": initialize_ms,
		"view_sequence_ms": view_sequence_ms,
		"lifecycle_ms": lifecycle_ms,
		"initial_surface_rebuild_ms": initial_surface_rebuild_ms,
		"return_surface_rebuild_ms": return_surface_rebuild_ms,
		"max_view_ms": max_view_ms,
		"max_bounded_operation_ms": max_bounded_operation_ms,
		"source_ecology_hash": source_hash,
		"composition_hash": composition_hash,
		"macro_bridge_hash": bridge_hash,
		"descriptor_adapter_hash": descriptor_hash,
		"lifecycle_green": bool(lifecycle.get("success", false)) and bool(final_package.get("lifecycle_evidence_complete", false)),
		"truth_green": truth_green,
		"ecology_identity_drift": bool(final_package.get("ecology_identity_drift", true)),
		"macro_records": int(final_package.get("macro_record_count", 0)),
		"macro_visible": int(final_package.get("macro_visible_individual_count", 0)),
		"ground_cover": int(final_package.get("ground_cover_instances", 0)),
		"rocks": int(final_package.get("rock_instances", 0)),
		"render_recenter_count": int(final_package.get("render_origin_recenter_count", 0)),
		"earth_rebuild_count": int(final_package.get("local_surface_rebuild_count", 0)),
		"region_roundtrip_count": int(final_package.get("region_roundtrip_count", 0)),
		"composite_initialize_timing_observational_only": true,
		"composite_lifecycle_timing_observational_only": true,
	}

	var absolute_path := ProjectSettings.globalize_path(sample_path)
	if sample_path.begins_with("/"):
		absolute_path = sample_path
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	_check(file != null, "PLAY1 worker sample file opens")
	if file != null:
		file.store_string(JSON.stringify(sample, "\t"))
		file.close()
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(absolute_path))
		_check(parsed is Dictionary, "PLAY1 worker sample JSON round-trip")

	print("PLAY1_WORKER repetition=%d initialize_ms=%.3f lifecycle_ms=%.3f initial_surface_ms=%.3f return_surface_ms=%.3f max_atomic_ms=%.3f" % [repetition, initialize_ms, lifecycle_ms, initial_surface_rebuild_ms, return_surface_rebuild_ms, max_bounded_operation_ms])
	_finish()


func _watchdog() -> void:
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline and not _finished:
		await process_frame
	if not _finished:
		failures.append("WATCHDOG: PLAY1 fresh repetition exceeded 120s")
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
		print("ECO.EVO7 PLAY1 WORKER: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("ECO.EVO7 PLAY1 WORKER: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
