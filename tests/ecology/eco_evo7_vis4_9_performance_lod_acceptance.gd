extends SceneTree

const Playground = preload("res://scripts/labs/ecology/eco_evo7_play0_live_planet_playground.gd")
const PerformanceLODEvidence = preload("res://scripts/labs/ecology/eco_evo7_vis4_9_performance_lod_evidence.gd")
const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")

var assertions := 0
var failures: Array[String] = []
var _finished := false


func _init() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _run() -> void:
	_controlled_lod_contract()

	var playground = Playground.new()
	playground.auto_initialize = false
	root.add_child(playground)
	await process_frame
	await process_frame

	_check(playground.initialize_runtime(), "VIS4.9 PLAY0 runtime initializes")
	if not playground.ready_success:
		_finish()
		return

	var presentation = playground.get_presentation()
	_check(presentation != null, "VIS4.9 presentation exists")
	_check(not playground.is_performance_lod_visible(), "VIS4.9 F8 starts hidden")
	_check(playground.get_performance_lod_state().is_empty(), "VIS4.9 generation-zero evidence unavailable")

	var panel: PanelContainer = playground.get_node_or_null("Play0HUD/VIS49PerformanceLODPanel") as PanelContainer
	var label: Label = playground.get_node_or_null("Play0HUD/VIS49PerformanceLODPanel/VIS49PerformanceLODText") as Label
	_check(panel != null and not panel.visible, "VIS4.9 panel starts hidden")
	_check(label != null, "VIS4.9 label exists")
	if panel != null:
		_check(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "VIS4.9 panel cannot intercept gameplay mouse")
	if label != null:
		_check(label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "VIS4.9 label cannot intercept gameplay mouse")

	var frame_before: Dictionary = playground.get_frame_performance()
	for _i in range(8):
		await process_frame
	var frame_after: Dictionary = playground.get_frame_performance()
	_check(int(frame_after.get("sample_count", 0)) > int(frame_before.get("sample_count", 0)), "VIS4.9 frame sampler advances")
	_check(float(frame_after.get("average_frame_ms", 0.0)) > 0.0, "VIS4.9 average frame time observed")
	_check(float(frame_after.get("estimated_fps", 0.0)) > 0.0, "VIS4.9 observational FPS derived")

	_check(playground.set_performance_lod_visible(true), "VIS4.9 F8 opens generation-zero panel")
	_check(playground.is_performance_lod_visible(), "VIS4.9 generation-zero panel visible")
	_check(playground.get_performance_lod_text().contains("Unavailable until completed PH5 generation"), "VIS4.9 generation-zero panel states evidence boundary")
	_check(not playground.toggle_performance_lod(), "VIS4.9 F8 closes generation-zero panel")

	_check(playground.request_generation(), "VIS4.9 generation request accepted")
	_check(await _wait_generation(playground, 60000), "VIS4.9 generation one completes")

	var published: Dictionary = playground.get_published_snapshot()
	var ecology_hash := String(published.get("ecology_state_hash", ""))
	_check(int(published.get("generation", -1)) == 1, "VIS4.9 source is generation one")
	_check(ecology_hash.length() == 64, "VIS4.9 ecology hash valid")

	var individuality_before: String = presentation.get_ph5_individuality_identity_hash()
	var appearance_before: String = presentation.get_ph5_grid_appearance_identity_hash()

	_check(playground.set_performance_lod_visible(true), "VIS4.9 opens live F8 panel")
	var evidence: Dictionary = playground.get_performance_lod_state()
	_check(not evidence.is_empty() and PerformanceLODEvidence.validate(evidence), "VIS4.9 live evidence validates")
	if evidence.is_empty():
		playground.queue_free()
		await process_frame
		_finish()
		return

	_check(int(evidence.get("record_count", 0)) > 0, "VIS4.9 observes live PH5 records")
	_check(int(evidence.get("snapshot_apply_count", 0)) >= 1, "VIS4.9 measures snapshot apply")
	_check(int(evidence.get("bridge_chain_build_count", 0)) > 0, "VIS4.9 counts exact PH5 chain builds")
	_check(int(evidence.get("materialization_build_count", 0)) > 0, "VIS4.9 counts materialization builds")
	_check(int(evidence.get("materialization_cache_miss_count", -1)) == int(evidence.get("materialization_build_count", -2)), "VIS4.9 misses equal actual builds")
	_check(bool(evidence.get("timings_diagnostic_only", false)), "VIS4.9 labels wall-clock timings diagnostic")
	_check(bool(evidence.get("draw_calls_are_proxy", false)), "VIS4.9 labels draw calls as proxy")
	_check(bool(evidence.get("fps_observational_only", false)), "VIS4.9 labels FPS observational")
	_check(bool(evidence.get("perf2_convergence_required", false)), "VIS4.9 cannot replace PERF2.CONV")
	_check(int(evidence.get("frame_sample_count", 0)) > 0, "VIS4.9 evidence carries frame samples")

	var text_value := playground.get_performance_lod_text()
	for required in [
		"VIS4.9 PERFORMANCE / LOD",
		"WORKLOAD",
		"CACHE / LOD",
		"PH5 BUILD TIMINGS",
		"FRAME OBSERVATION",
		"draw-call proxy",
		"GrowthGraph",
		"PERF2.CONV STILL REQUIRED",
	]:
		_check(text_value.contains(required), "VIS4.9 panel exposes %s" % required)

	var record_count := int(evidence.get("record_count", 0))
	var tiers: Dictionary = Dictionary(evidence.get("tier_counts", {}))
	var tier_sum := 0
	for tier in PerformanceLODEvidence.TIER_ORDER:
		tier_sum += int(tiers.get(tier, 0))
	_check(tier_sum == record_count, "VIS4.9 tier counts cover exact population")
	_check(
		int(evidence.get("visible_individual_count", -1))
		== record_count - int(tiers.get(Representation.TIER_4_POPULATION_ONLY, 0)),
		"VIS4.9 visible count matches non-T4 population"
	)

	var index := 0
	var canonical: Vector3 = presentation.get_stem_world_position(index)
	var height := maxf(0.1, presentation.get_ph5_record_height(index))
	var up := canonical.normalized()
	var focal_px := 1080.0 / (2.0 * tan(deg_to_rad(70.0) * 0.5))

	# TIER0: high projected height.
	_check(
		presentation.set_view_world_position(canonical + up * _distance_for_projected(height, focal_px, 360.0)),
		"VIS4.9 moves target record to T0 view"
	)
	_check(presentation.get_ph5_record_tier(index) == Representation.TIER_0_FULL, "VIS4.9 target reaches TIER0")
	var t0_perf: Dictionary = presentation.get_ph5_record_performance(index)
	var t0_identity: Dictionary = presentation.get_ph5_record_identity(index)
	_check(int(t0_perf.get("cost_units", 0)) == int(Representation.COST_UNITS[Representation.TIER_0_FULL]), "VIS4.9 T0 cost units exact")
	_check(int(t0_perf.get("branch_primitive_count", 0)) > 0, "VIS4.9 T0 has branch primitives")
	_check(int(t0_perf.get("foliage_instance_count", 0)) > 0, "VIS4.9 T0 has foliage instances")
	_check(int(t0_perf.get("draw_call_proxy", 0)) >= 1, "VIS4.9 T0 draw-call proxy nonzero")

	var stable_before: Dictionary = presentation.get_ph5_performance_counters()
	for _repeat in range(6):
		_check(
			presentation.set_view_world_position(canonical + up * _distance_for_projected(height, focal_px, 360.0)),
			"VIS4.9 repeated stable T0 view accepted"
		)
	var stable_after: Dictionary = presentation.get_ph5_performance_counters()
	_check(int(stable_after.get("lod_switch_count", -1)) == int(stable_before.get("lod_switch_count", -2)), "stable T0 view causes no LOD thrash")
	_check(int(stable_after.get("materialization_cache_hit_count", -1)) == int(stable_before.get("materialization_cache_hit_count", -2)), "stable T0 view performs no cache lookup")
	_check(int(stable_after.get("materialization_build_count", -1)) == int(stable_before.get("materialization_build_count", -2)), "stable T0 view performs no build")

	# TIER2: canopy approximation.
	_check(
		presentation.set_view_world_position(canonical + up * _distance_for_projected(height, focal_px, 50.0)),
		"VIS4.9 moves target record to T2 view"
	)
	_check(presentation.get_ph5_record_tier(index) == Representation.TIER_2_CANOPY, "VIS4.9 target reaches TIER2")
	var t2_perf: Dictionary = presentation.get_ph5_record_performance(index)
	_check(int(t2_perf.get("cost_units", 0)) == int(Representation.COST_UNITS[Representation.TIER_2_CANOPY]), "VIS4.9 T2 cost units exact")
	_check(int(t2_perf.get("branch_primitive_count", -1)) == 0, "VIS4.9 T2 removes branch primitives")
	_check(int(t2_perf.get("foliage_instance_count", -1)) == 0, "VIS4.9 T2 removes foliage instances")
	_check(int(t2_perf.get("far_primitive_count", 0)) == 1, "VIS4.9 T2 uses one canopy primitive")
	_check(int(t2_perf.get("cost_units", 0)) < int(t0_perf.get("cost_units", 0)), "VIS4.9 T2 reduces workload cost")

	# Return to T0; the exact prior materialization must come from cache.
	var cache_before_return: Dictionary = presentation.get_ph5_performance_counters()
	_check(
		presentation.set_view_world_position(canonical + up * _distance_for_projected(height, focal_px, 360.0)),
		"VIS4.9 returns target to T0"
	)
	_check(presentation.get_ph5_record_tier(index) == Representation.TIER_0_FULL, "VIS4.9 target returns TIER0")
	var cache_after_return: Dictionary = presentation.get_ph5_performance_counters()
	var t0_return_identity: Dictionary = presentation.get_ph5_record_identity(index)
	_check(
		int(cache_after_return.get("materialization_cache_hit_count", 0))
		> int(cache_before_return.get("materialization_cache_hit_count", 0)),
		"VIS4.9 T0 return produces cache hit"
	)
	_check(
		String(t0_return_identity.get("materialization_hash", ""))
		== String(t0_identity.get("materialization_hash", "")),
		"VIS4.9 cached T0 restores exact materialization hash"
	)

	# TIER4: no individual node and minimum representation cost.
	_check(
		presentation.set_view_world_position(canonical + up * _distance_for_projected(height, focal_px, 2.0)),
		"VIS4.9 moves target record to T4 view"
	)
	_check(presentation.get_ph5_record_tier(index) == Representation.TIER_4_POPULATION_ONLY, "VIS4.9 target reaches TIER4")
	var t4_perf: Dictionary = presentation.get_ph5_record_performance(index)
	_check(not presentation.is_ph5_record_individual_materialized(index), "VIS4.9 T4 has no individual node")
	_check(int(t4_perf.get("cost_units", 0)) == int(Representation.COST_UNITS[Representation.TIER_4_POPULATION_ONLY]), "VIS4.9 T4 cost units exact")
	_check(int(t4_perf.get("branch_primitive_count", -1)) == 0, "VIS4.9 T4 branch workload zero")
	_check(int(t4_perf.get("foliage_instance_count", -1)) == 0, "VIS4.9 T4 foliage workload zero")
	_check(int(t4_perf.get("far_primitive_count", -1)) == 0, "VIS4.9 T4 far workload zero")
	_check(int(t4_perf.get("draw_call_proxy", -1)) == 0, "VIS4.9 T4 draw-call proxy zero")
	_check(int(t4_perf.get("cost_units", 0)) < int(t2_perf.get("cost_units", 0)), "VIS4.9 T4 reduces cost below T2")

	# Restore T0 and ensure source identities remain non-causal.
	_check(
		presentation.set_view_world_position(canonical + up * _distance_for_projected(height, focal_px, 360.0)),
		"VIS4.9 restores target to T0 after T4"
	)
	_check(presentation.get_ph5_record_tier(index) == Representation.TIER_0_FULL, "VIS4.9 target final T0 restored")

	var final_perf: Dictionary = presentation.get_ph5_performance_counters()
	_check(int(final_perf.get("lod_update_count", 0)) > int(stable_before.get("lod_update_count", 0)), "VIS4.9 counts LOD update calls")
	_check(int(final_perf.get("lod_switch_count", 0)) > int(stable_before.get("lod_switch_count", 0)), "VIS4.9 counts actual LOD switches")
	_check(int(final_perf.get("materialization_cache_hit_count", 0)) > 0, "VIS4.9 records cache reuse")
	_check(float(final_perf.get("materialization_cache_hit_rate", 0.0)) > 0.0, "VIS4.9 reports nonzero cache hit rate")

	var final_evidence: Dictionary = playground.get_performance_lod_state()
	_check(not final_evidence.is_empty() and PerformanceLODEvidence.validate(final_evidence), "VIS4.9 final evidence validates after LOD campaign")
	_check(String(playground.get_published_snapshot().get("ecology_state_hash", "")) == ecology_hash, "VIS4.9 LOD campaign cannot mutate ecology")
	_check(presentation.get_ph5_individuality_identity_hash() == individuality_before, "VIS4.9 LOD campaign preserves VIS4.5 individuality")
	_check(presentation.get_ph5_grid_appearance_identity_hash() == appearance_before, "VIS4.9 LOD campaign preserves VIS4.6 appearance")

	# F6/F7/F8 share one diagnostic slot.
	_check(playground.set_morphology_inspector_visible(true), "VIS4.9 switches to F6")
	_check(not playground.is_performance_lod_visible(), "F6 hides F8")
	_check(playground.set_diversity_evidence_visible(true), "VIS4.9 switches to F7")
	_check(not playground.is_morphology_inspector_visible(), "F7 hides F6")
	_check(playground.set_performance_lod_visible(true), "VIS4.9 switches back to F8")
	_check(not playground.is_diversity_evidence_visible(), "F8 hides F7")

	var status: Dictionary = playground.get_play0_status()
	_check(bool(status.get("performance_lod_visible", false)), "PLAY0 status reports F8 visible")
	_check(String(status.get("performance_lod_structural_hash", "")).length() == 64, "PLAY0 status exposes VIS4.9 structural evidence hash")

	_source_guard()

	print("ECO.EVO7 VIS4.9 Performance / LOD evidence: PASS")
	print("VIS4.9 final cache hit rate: %.3f" % float(final_evidence.get("materialization_cache_hit_rate", 0.0)))
	print("VIS4.9 final cost units: %d" % int(final_evidence.get("cost_units", 0)))
	print("VIS4.9 observational frame ms: %.3f" % float(final_evidence.get("average_frame_ms", 0.0)))

	playground.queue_free()
	await process_frame
	_finish()


func _controlled_lod_contract() -> void:
	_check(Representation.select_tier(300.0) == Representation.TIER_0_FULL, "controlled LOD 300px -> T0")
	_check(Representation.select_tier(150.0) == Representation.TIER_1_REDUCED, "controlled LOD 150px -> T1")
	_check(Representation.select_tier(50.0) == Representation.TIER_2_CANOPY, "controlled LOD 50px -> T2")
	_check(Representation.select_tier(10.0) == Representation.TIER_3_IMPOSTOR, "controlled LOD 10px -> T3")
	_check(Representation.select_tier(2.0) == Representation.TIER_4_POPULATION_ONLY, "controlled LOD 2px -> T4")
	_check(
		Representation.select_tier_hysteretic(220.0, Representation.TIER_0_FULL, 0.12)
		== Representation.TIER_0_FULL,
		"controlled hysteresis keeps T0 inside lower margin"
	)
	_check(
		Representation.select_tier_hysteretic(100.0, Representation.TIER_1_REDUCED, 0.12)
		== Representation.TIER_1_REDUCED,
		"controlled hysteresis keeps T1 inside band"
	)
	_check(int(Representation.COST_UNITS[Representation.TIER_0_FULL]) > int(Representation.COST_UNITS[Representation.TIER_1_REDUCED]), "LOD cost T0 > T1")
	_check(int(Representation.COST_UNITS[Representation.TIER_1_REDUCED]) > int(Representation.COST_UNITS[Representation.TIER_2_CANOPY]), "LOD cost T1 > T2")
	_check(int(Representation.COST_UNITS[Representation.TIER_2_CANOPY]) > int(Representation.COST_UNITS[Representation.TIER_3_IMPOSTOR]), "LOD cost T2 > T3")
	_check(int(Representation.COST_UNITS[Representation.TIER_3_IMPOSTOR]) > int(Representation.COST_UNITS[Representation.TIER_4_POPULATION_ONLY]), "LOD cost T3 > T4")


func _distance_for_projected(height_m: float, focal_px: float, projected_px: float) -> float:
	return maxf(0.05, height_m * focal_px / maxf(projected_px, 0.001))


func _source_guard() -> void:
	var model_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis4_9_performance_lod_evidence.gd").to_lower()
	var renderer_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis4_4_play0_ph5_renderer.gd").to_lower()
	var bridge_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis4_3_exact_ph5_bridge.gd").to_lower()
	var playground_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_play0_live_planet_playground.gd").to_lower()

	_check(playground_source.contains("key_f8"), "VIS4.9 PLAY0 binds F8")
	_check(model_source.contains("perf2_convergence_required := true"), "VIS4.9 explicitly preserves PERF2.CONV requirement")
	_check(model_source.contains("timings_diagnostic_only"), "VIS4.9 labels timings diagnostic")
	_check(model_source.contains("draw_calls_are_proxy"), "VIS4.9 labels draw-call evidence proxy")
	_check(model_source.contains("fps_observational_only"), "VIS4.9 labels FPS observational")
	_check(renderer_source.contains("_materialization_cache_hit_count"), "VIS4.9 instruments accepted PH5 cache")
	_check(renderer_source.contains("_lod_switch_count"), "VIS4.9 instruments accepted PH5 LOD switches")
	_check(bridge_source.contains("_perf_growth_graph_usec"), "VIS4.9 measures accepted GrowthGraph phase")
	_check(not model_source.contains("growthgraph.build"), "VIS4.9 evidence model does not rebuild GrowthGraph")
	_check(not model_source.contains("functionalphenotype") and not model_source.contains("coupleddevelopment"), "VIS4.9 evidence model does not recompute biology")
	_check(not model_source.contains("fileaccess.open") and not model_source.contains("diraccess") and not model_source.contains("multiplayer"), "VIS4.9 evidence owns no persistence/network authority")


func _wait_generation(playground, timeout_msec: int) -> bool:
	var started := Time.get_ticks_msec()
	while playground.is_generation_running() and Time.get_ticks_msec() - started < timeout_msec:
		await process_frame
	return not playground.is_generation_running()


func _watchdog() -> void:
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline and not _finished:
		await process_frame
	if not _finished:
		push_error("ECO.EVO7 VIS4.9 watchdog timeout")
		print("ECO.EVO7 VIS4.9 Performance / LOD: FAIL (watchdog timeout)")
		quit(1)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("VIS4.9: " + label)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if failures.is_empty():
		print("ECO.EVO7 VIS4.9 Performance / LOD: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("FAIL: " + failure)
	print("ECO.EVO7 VIS4.9 Performance / LOD: FAIL (%d/%d)" % [failures.size(), assertions])
	quit(1)
