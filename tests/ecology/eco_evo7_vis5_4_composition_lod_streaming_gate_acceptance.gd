extends SceneTree

const LabScript = preload("res://scripts/labs/ecology/eco_evo7_vis5_3_mixed_strata_composition_lab.gd")
const Gate = preload("res://scripts/labs/ecology/eco_evo7_vis5_4_composition_lod_streaming_gate.gd")

var assertions := 0
var failures: Array[String] = []
var _finished := false


func _init() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _run() -> void:
	_m1_fail_closed_setup()
	await _m2_real_lod_streaming_lifecycle()
	_m3_source_boundary()
	_finish()


func _m1_fail_closed_setup() -> void:
	var gate := Gate.new()
	_check(not gate.setup(null), "null VIS5.3 lab rejected")
	_check(not gate.update_observer(Vector3.ZERO), "uninitialized observer update rejected")
	_check(gate.recenter_render_origin(Vector3.ZERO).is_empty(), "uninitialized recenter rejected")
	_check(gate.roundtrip_region_rebuild(Vector3.UP).is_empty(), "uninitialized region roundtrip rejected")
	_check(not Gate.validate_evidence({}), "empty evidence rejected")


func _m2_real_lod_streaming_lifecycle() -> void:
	var lab := LabScript.new()
	lab.auto_initialize = false
	root.add_child(lab)
	await process_frame
	_check(
		lab.initialize_runtime({
			"ground_cover_max_instances": 600,
			"max_rocks": 50,
			"rock_attempts_multiplier": 24,
		}),
		"closed VIS5.3 real mixed lab initializes"
	)
	if not lab.ready_success:
		lab.queue_free()
		await process_frame
		return

	var gate := Gate.new()
	_check(gate.setup(lab), "VIS5.4 gate accepts exact VIS5.3 mixed lab")
	var earth = lab.get_earth_world()
	var presentation = lab.get_presentation()
	var center_direction: Vector3 = presentation.get_patch_center_direction().normalized()
	var center_world: Vector3 = earth.get_surface_point(center_direction)
	var tangent := center_direction.cross(Vector3.UP)
	if tangent.length_squared() < 0.000001:
		tangent = center_direction.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var up := center_direction
	var source_hash := String(lab.get_summary().get("source_ecology_hash", ""))
	var bridge_hash := String(lab.get_summary().get("macro_bridge_hash", ""))
	var descriptor_hash := String(lab.get_published_morphology_descriptors().get("adapter_hash", ""))
	_check(source_hash.length() == 64, "baseline ecology hash valid")
	_check(bridge_hash.length() == 64, "baseline macro bridge hash valid")
	_check(descriptor_hash.length() == 64, "baseline Descriptor V2 adapter hash valid")

	var first_plant_world: Vector3 = presentation.get_stem_world_position(0)
	var first_plant_height: float = maxf(0.5, presentation.get_ph5_record_height(0))
	var near_view := first_plant_world + first_plant_world.normalized() * first_plant_height * 1.5
	_check(gate.update_observer(near_view, 1.0 / 60.0), "near observer update succeeds")
	var near := gate.get_evidence()
	_check(Gate.validate_evidence(near), "near evidence validates")
	_check(String(near.get("mode", "")) == Gate.MODE_NEAR, "near view selects NEAR composition mode")
	_check(int(near.get("ground_cover_visible_instances", 0)) == 600, "NEAR keeps full test ground-cover budget visible")
	_check(int(near.get("rock_visible_instances", 0)) == 50, "NEAR keeps full test rock budget visible")
	_check(int(near.get("ph5_visible_individual_count", 0)) > 0, "NEAR materializes PH5 individuals")
	_check(int(near.get("composition_draw_call_proxy", 0)) > 0, "NEAR exposes nonzero composition draw proxy")
	_check(bool(near.get("workload_is_proxy", false)), "workload explicitly labeled proxy")
	var near_cost := int(near.get("composition_cost_proxy", 0))
	var near_ph5_cost := int(near.get("ph5_cost_units", 0))
	var near_tiers: Dictionary = near.get("ph5_tier_counts", {})
	_check(int(near_tiers.get("TIER_0_FULL", 0)) > 0, "NEAR reaches full PH5 tier")

	_check(gate.update_observer(center_world + tangent * 700.0 + up * 20.0, 1.0 / 60.0), "mid observer update succeeds")
	var mid := gate.get_evidence()
	_check(String(mid.get("mode", "")) == Gate.MODE_MID, "700m view selects MID mode")
	_check(int(mid.get("ground_cover_visible_instances", -1)) == 0, "MID culls dense ground cover")
	_check(int(mid.get("rock_visible_instances", 0)) == 50, "MID retains terrain rock stratum")
	_check(int(mid.get("ph5_cost_units", 0)) < near_ph5_cost, "MID reduces PH5 representation cost")
	_check(int(mid.get("composition_cost_proxy", 0)) < near_cost, "MID reduces total composition cost proxy")

	_check(gate.update_observer(center_world + tangent * 3000.0 + up * 20.0, 1.0 / 60.0), "far observer update succeeds")
	var far := gate.get_evidence()
	_check(String(far.get("mode", "")) == Gate.MODE_FAR, "3km view selects FAR mode")
	_check(int(far.get("ground_cover_visible_instances", -1)) == 0, "FAR keeps ground cover culled")
	_check(int(far.get("rock_visible_instances", -1)) == 0, "FAR culls terrain rocks")
	_check(int(far.get("ph5_cost_units", 0)) <= int(mid.get("ph5_cost_units", 0)), "FAR does not increase PH5 cost")

	_check(gate.update_observer(center_world + tangent * 20000.0 + up * 20.0, 1.0 / 60.0), "culled observer update succeeds")
	var culled := gate.get_evidence()
	_check(String(culled.get("mode", "")) == Gate.MODE_CULLED, "20km view selects CULLED mode")
	var culled_tiers: Dictionary = culled.get("ph5_tier_counts", {})
	_check(int(culled_tiers.get("TIER_4_POPULATION_ONLY", 0)) == int(culled.get("ph5_record_count", -1)), "CULLED reduces every PH5 record to population-only")
	_check(int(culled.get("ph5_visible_individual_count", -1)) == 0, "CULLED has no individual PH5 nodes")
	_check(int(culled.get("ground_cover_visible_instances", -1)) == 0, "CULLED ground cover zero")
	_check(int(culled.get("rock_visible_instances", -1)) == 0, "CULLED rocks zero")

	_check(gate.update_observer(near_view, 1.0 / 60.0), "return-near observer update succeeds")
	var returned_near := gate.get_evidence()
	_check(String(returned_near.get("mode", "")) == Gate.MODE_NEAR, "return view restores NEAR mode")
	_check(int(returned_near.get("mode_switch_count", 0)) >= 5, "LOD walk records composition mode transitions")
	_check(int(returned_near.get("frame_sample_count", 0)) == 5, "five frame observations recorded")
	_check(float(returned_near.get("estimated_fps", 0.0)) > 0.0, "frame diagnostics expose estimated FPS")
	_check(bool(returned_near.get("frame_diagnostics_observational_only", false)), "frame diagnostics marked observational only")
	_check(String(returned_near.get("source_ecology_hash", "")) == source_hash, "LOD transitions preserve ecology hash")
	_check(String(returned_near.get("macro_bridge_hash", "")) == bridge_hash, "LOD transitions preserve macro source bridge")
	_check(String(returned_near.get("descriptor_adapter_hash", "")) == descriptor_hash, "LOD transitions preserve Descriptor V2 source")

	var original_origin: Vector3 = earth.get_render_origin()
	var record_world_before: Vector3 = presentation.get_stem_world_position(0)
	var record_render_before: Vector3 = presentation.get_stem_render_position(0)
	var composition_hash_before_recenter := String(lab.get_summary().get("composition_hash", ""))
	var shifted_origin := original_origin + tangent * 1500.0
	var recenter := gate.recenter_render_origin(shifted_origin)
	_check(not recenter.is_empty() and bool(recenter.get("changed", false)), "render-origin recenter executes")
	_check(bool(recenter.get("identity_stable", false)), "recenter preserves ecology / PH5 / Descriptor identity")
	_check(float(recenter.get("record_world_delta_m", 1.0)) < 0.001, "recenter leaves canonical plant world position invariant")
	var record_render_after: Vector3 = presentation.get_stem_render_position(0)
	_check(absf(record_render_after.distance_to(record_render_before) - 1500.0) < 0.1, "recenter reprojects PH5 render position by origin delta")
	_check(record_world_before.distance_to(presentation.get_stem_world_position(0)) < 0.001, "PH5 world point invariant after scenery rebuild")
	_check(String(lab.get_summary().get("source_ecology_hash", "")) == source_hash, "recenter scenery rebuild cannot mutate ecology hash")
	_check(String(lab.get_summary().get("macro_bridge_hash", "")) == bridge_hash, "recenter scenery rebuild cannot mutate macro bridge")
	_check(String(lab.get_summary().get("composition_hash", "")) != composition_hash_before_recenter, "render-space scenery hash responds to origin change")

	var restore := gate.recenter_render_origin(original_origin)
	_check(bool(restore.get("identity_stable", false)), "restoring render origin keeps source identity stable")
	_check(String(lab.get_summary().get("composition_hash", "")) == composition_hash_before_recenter, "same seed + same region + original origin restores exact composition hash")
	var after_restore := gate.get_evidence()
	_check(int(after_restore.get("render_origin_recenter_count", 0)) == 2, "two explicit render-origin recenter operations counted")
	_check(int(after_restore.get("scenery_rebuild_count", 0)) == 2, "recenter triggers deterministic scenery rebuild each time")
	_check(bool(after_restore.get("last_recenter_identity_stable", false)), "latest recenter identity invariant recorded")

	# Force a real ProceduralEarth local-region round trip beyond its accepted
	# 6.5km recenter threshold, then return to the canonical ecology patch.
	var angular_offset: float = earth.local_recenter_distance_m * 1.6 / earth.get_planet_radius()
	var target_direction := center_direction.rotated(tangent, angular_offset).normalized()
	var target_surface: Vector3 = earth.get_surface_point(target_direction)
	_check(target_surface.distance_to(earth.get_surface_anchor()) > earth.local_recenter_distance_m, "roundtrip target exceeds Earth local recenter threshold")
	var before_roundtrip_hash := String(lab.get_summary().get("composition_hash", ""))
	var roundtrip := gate.roundtrip_region_rebuild(target_direction)
	_check(not roundtrip.is_empty() and bool(roundtrip.get("success", false)), "real local-region rebuild roundtrip succeeds")
	_check(int(roundtrip.get("rebuild_events", 0)) >= 2, "roundtrip observes remote + return surface rebuilds")
	_check(bool(roundtrip.get("remote_placement_suppressed", false)), "remote terrain rebuild keeps procedural placement suppressed")
	_check(bool(roundtrip.get("return_placement_suppressed", false)), "return terrain rebuild keeps procedural placement suppressed")
	_check(bool(roundtrip.get("source_identity_stable", false)), "surface streaming roundtrip preserves source identity")
	_check(bool(roundtrip.get("composition_hash_restored", false)), "same seed / same canonical region restores exact scenery composition")
	_check(String(lab.get_summary().get("composition_hash", "")) == before_roundtrip_hash, "post-roundtrip composition hash exact")
	_check(String(lab.get_summary().get("source_ecology_hash", "")) == source_hash, "terrain rebuild roundtrip cannot mutate ecology")
	_check(String(lab.get_summary().get("macro_bridge_hash", "")) == bridge_hash, "terrain rebuild roundtrip cannot mutate PH5 source")

	var final_evidence := gate.get_evidence()
	_check(Gate.validate_evidence(final_evidence), "final VIS5.4 evidence validates")
	_check(int(final_evidence.get("local_surface_rebuild_count", 0)) >= 2, "local surface rebuild counter non-vacuous")
	_check(int(final_evidence.get("region_roundtrip_count", 0)) == 1, "one certified region roundtrip recorded")
	_check(bool(final_evidence.get("same_seed_roundtrip_verified", false)), "same-seed/region deterministic regeneration certified")
	_check(not bool(final_evidence.get("ecology_identity_drift", true)), "no ecology identity drift across lifecycle")
	_check(bool(final_evidence.get("procedural_tree_placement_suppressed", false)), "procedural Earth trees remain suppressed")
	_check(not bool(final_evidence.get("perf2_authority", true)), "VIS5.4 owns no PERF2 authority")
	_check(bool(final_evidence.get("perf2_convergence_required", false)), "PERF2.CONV remains required")
	_check(String(final_evidence.get("structural_evidence_hash", "")).length() == 64, "structural evidence hash present")

	var tampered := final_evidence.duplicate(true)
	tampered["ecology_authority"] = true
	_check(not Gate.validate_evidence(tampered), "ecology-authority claim rejected")
	tampered = final_evidence.duplicate(true)
	tampered["same_seed_roundtrip_verified"] = false
	_check(not Gate.validate_evidence(tampered), "failed deterministic roundtrip rejected after certification")
	tampered = final_evidence.duplicate(true)
	tampered["ground_cover_visible_instances"] = int(tampered.get("ground_cover_total_instances", 0))
	if String(tampered.get("mode", "")) != Gate.MODE_NEAR:
		_check(not Gate.validate_evidence(tampered), "ground cover outside NEAR rejected")
	else:
		tampered["mode"] = Gate.MODE_FAR
		_check(not Gate.validate_evidence(tampered), "ground cover in FAR mode rejected")

	lab.queue_free()
	await process_frame


func _m3_source_boundary() -> void:
	var source := FileAccess.get_file_as_string(
		"res://scripts/labs/ecology/eco_evo7_vis5_4_composition_lod_streaming_gate.gd"
	).to_lower()
	_check(source.contains("eco.evo7 vis5.4"), "source declares VIS5.4 boundary")
	_check(source.contains("set_view_world_position"), "VIS5.4 delegates PH5 LOD to accepted renderer")
	_check(source.contains("apply_lod_flags"), "VIS5.4 delegates ground-cover visibility to VIS5.2")
	_check(source.contains("prepare_surface_region"), "VIS5.4 exercises real ProceduralEarth local rebuild")
	_check(source.contains("refresh_render_transform"), "VIS5.4 reprojects accepted PH5 on origin change")
	_check(not source.contains("reproduce_bundle("), "VIS5.4 owns no reproduction")
	_check(not source.contains("mutation_seed("), "VIS5.4 owns no mutation")
	_check(not source.contains("advance_generations("), "VIS5.4 owns no generation mutation")
	_check(not source.contains("fileaccess.open") and not source.contains("diraccess"), "VIS5.4 owns no persistence path")
	_check(not source.contains("multiplayer"), "VIS5.4 owns no network implementation")
	_check(not source.contains("perf2.4"), "VIS5.4 does not touch PERF2.4 thresholds")
	_check(not source.contains("get_tree_mesh") and not source.contains("tree_density"), "VIS5.4 owns no procedural-tree path")


func _watchdog() -> void:
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline and not _finished:
		await process_frame
	if not _finished:
		push_error("ECO.EVO7 VIS5.4 watchdog timeout")
		print("ECO.EVO7 VIS5.4 Composition LOD / Streaming Local Gate: FAIL (watchdog timeout)")
		quit(1)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("VIS5.4: " + label)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if failures.is_empty():
		print("ECO.EVO7 VIS5.4 Composition LOD / Streaming Local Gate: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("FAIL: " + failure)
	print("ECO.EVO7 VIS5.4 Composition LOD / Streaming Local Gate: FAIL (%d/%d)" % [failures.size(), assertions])
	quit(1)
