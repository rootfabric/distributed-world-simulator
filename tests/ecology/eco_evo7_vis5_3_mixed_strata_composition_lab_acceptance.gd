extends SceneTree

const LabScript = preload("res://scripts/labs/ecology/eco_evo7_vis5_3_mixed_strata_composition_lab.gd")
const GroundCoverBridge = preload("res://scripts/labs/ecology/eco_evo7_vis5_2_noncanonical_ground_cover_bridge.gd")

var assertions := 0
var failures: Array[String] = []
var _finished := false


func _init() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _run() -> void:
	_m1_fail_closed_profile()
	await _m2_real_mixed_runtime()
	_m3_source_boundary()
	_finish()


func _m1_fail_closed_profile() -> void:
	var bad := LabScript.new()
	bad.auto_initialize = false
	root.add_child(bad)
	_check(
		not bad.initialize_runtime({"unknown_profile_key": 1}),
		"unknown profile key rejected before runtime allocation"
	)
	bad.queue_free()

	bad = LabScript.new()
	bad.auto_initialize = false
	root.add_child(bad)
	_check(
		not bad.initialize_runtime({"ground_cover_max_instances": 0}),
		"zero ground-cover budget rejected"
	)
	bad.queue_free()


func _m2_real_mixed_runtime() -> void:
	var packed = load("res://scenes/labs/ecology/eco_evo7_vis5_3_mixed_strata_composition_lab.tscn")
	_check(packed is PackedScene, "VIS5.3 scene parses as PackedScene")

	var lab := LabScript.new()
	lab.auto_initialize = false
	root.add_child(lab)
	await process_frame
	var profile := {
		"ground_cover_max_instances": 700,
		"max_rocks": 60,
		"rock_attempts_multiplier": 24,
	}
	_check(lab.initialize_runtime(profile), "real VIS5.3 mixed runtime initializes")
	if not lab.ready_success:
		lab.queue_free()
		await process_frame
		return

	var summary := lab.get_summary()
	_check(LabScript.validate_summary(summary), "mixed composition summary validates")
	_check(lab.is_mixed_ready(), "lab reports mixed-ready")
	_check(String(summary.get("schema", "")) == LabScript.SCHEMA, "summary schema exact")
	_check(String(summary.get("revision", "")) == LabScript.REVISION, "summary revision exact")
	_check(bool(summary.get("presentation_only", false)), "composition remains presentation-only")
	_check(not bool(summary.get("network_authority", true)), "composition owns no network authority")
	_check(not bool(summary.get("persistence_authority", true)), "composition owns no persistence authority")
	_check(int(summary.get("world_seed", -1)) == 360055, "VIS5.3 uses deterministic grassland world seed")

	var earth = lab.get_earth_world()
	var workbench = lab.get_workbench()
	var presentation = lab.get_presentation()
	_check(earth != null and workbench != null and presentation != null, "real Earth + Workbench + presentation exist")
	_check(earth.local_surface != null and earth.local_surface.mesh != null, "real local Earth terrain mesh exists")
	_check(String(summary.get("terrain_source", "")) == "ProceduralEarthWorld", "terrain source explicitly ProceduralEarthWorld")
	_check(int(summary.get("terrain_sample_count", 0)) == 9, "terrain diagnostic samples nine local points")
	_check(float(summary.get("terrain_relief_range_m", 0.0)) > 10.0, "composition patch is materially uneven")
	_check(float(summary.get("terrain_maximum_geometric_slope_deg", 0.0)) > 1.0, "composition patch has non-zero geometric slope")

	var patch: Dictionary = workbench.get_patch()
	var patch_center := Vector3(patch.get("center_direction", Vector3.ZERO))
	var center_state: Dictionary = earth.get_surface_state(patch_center, 0)
	_check(int(center_state.get("water_kind", 1)) == 0, "mixed patch center is land")
	_check(float(center_state.get("grass_density", 0.0)) > 0.5, "mixed patch center has dense grass source")
	_check(float(center_state.get("rock_density", 0.0)) > 0.0, "mixed patch center has rock scenery source")

	var built_in: Dictionary = earth.placement_system.get_summary()
	_check(not earth.placement_system.visible, "built-in Earth placement subtree hidden")
	_check(int(built_in.get("near_trees", -1)) == 0, "built-in near procedural trees suppressed")
	_check(int(built_in.get("billboard_trees", -1)) == 0, "built-in billboard procedural trees suppressed")
	_check(int(built_in.get("grass", -1)) == 0, "built-in grass path suppressed")
	_check(int(built_in.get("rocks", -1)) == 0, "built-in rock path suppressed")
	_check(bool(summary.get("builtin_earth_placement_hidden", false)), "summary records built-in placement suppression")
	_check(not bool(summary.get("procedural_trees_visible", true)), "summary forbids visible procedural trees")

	var contract: Dictionary = presentation.get_contract()
	var ph5: Dictionary = contract.get("ph5", {})
	_check(bool(contract.get("ph5_active", false)), "canonical macro stratum uses live PH5")
	_check(bool(contract.get("uses_vis4_exact_ph5", false)), "composition reports exact VIS4 PH5 source")
	_check(String(summary.get("macro_truth_status", "")) == LabScript.MACRO_TRUTH_STATUS, "macro stratum truth marker exact")
	_check(String(summary.get("macro_source", "")) == "VIS4 PH5 only", "macro source excludes procedural trees")
	_check(int(summary.get("macro_record_count", 0)) == int(ph5.get("record_count", -1)), "summary macro count matches PH5 contract")
	_check(int(summary.get("macro_visible_individual_count", 0)) == int(ph5.get("visible_individual_count", -1)), "summary visible macro count matches PH5")
	_check(int(summary.get("macro_visible_individual_count", 0)) > 0, "PH5 macro layer visibly materialized")
	_check(String(summary.get("macro_bridge_hash", "")) == String(ph5.get("source_bridge_hash", "x")), "macro bridge identity exact")
	_check(String(summary.get("macro_bridge_hash", "")).length() == 64, "macro bridge hash valid")
	var source_hash := String(summary.get("source_ecology_hash", ""))
	_check(source_hash.length() == 64, "source ecology hash valid")
	_check(source_hash == String(lab.get_published_snapshot().get("ecology_state_hash", "")), "composition binds exact published ecology")
	var morphology := lab.get_published_morphology_descriptors()
	_check(not morphology.is_empty(), "Descriptor V2 morphology published")
	_check(int(morphology.get("descriptor_count", 0)) == int(summary.get("macro_record_count", -1)), "every Descriptor V2 record reaches macro PH5 stratum")
	_check(not lab.get_published_reconstruction_evidence().is_empty(), "exact GrowthGraph reconstruction evidence retained")

	var ground = lab.get_ground_cover_bridge()
	var ground_summary: Dictionary = ground.get_summary()
	_check(GroundCoverBridge.validate_summary(ground_summary), "VIS5.2 ground-cover summary remains valid inside VIS5.3")
	_check(String(summary.get("ground_cover_truth_status", "")) == LabScript.GROUND_COVER_TRUTH_STATUS, "ground cover remains explicit NONCANONICAL_SCENERY")
	_check(int(summary.get("ground_cover_instances", 0)) == 700, "test profile fills dense ground-cover budget")
	_check(float(summary.get("ground_cover_min_normal_alignment", 0.0)) > 0.999999, "ground cover follows geometric terrain normals")
	var grass_total := 0
	for child in ground.get_children():
		_check(child is MultiMeshInstance3D, "ground-cover child is MultiMeshInstance3D")
		_check(String(child.name).begins_with("GroundCover_"), "ground-cover namespace preserved")
		var instance := child as MultiMeshInstance3D
		_check(instance.multimesh != null and instance.multimesh.mesh != null, "ground-cover MultiMesh has real grass mesh")
		if instance.multimesh != null:
			grass_total += instance.multimesh.instance_count
	_check(grass_total == int(summary.get("ground_cover_instances", -1)), "ground-cover MultiMesh count matches composition summary")

	var rocks := lab.get_rock_instances()
	_check(String(summary.get("rock_truth_status", "")) == LabScript.ROCK_TRUTH_STATUS, "rocks remain TERRAIN_SCENERY")
	_check(int(summary.get("rock_instances", 0)) == 60, "test profile fills deterministic rock budget")
	_check(float(summary.get("rock_min_normal_alignment", 0.0)) > 0.999999, "rocks follow geometric terrain normals")
	_check(not rocks.is_empty(), "rock MultiMesh groups materialized")
	var rock_total := 0
	for rock in rocks:
		_check(String(rock.name).begins_with("Vis53TerrainRocks_"), "rock group namespace explicit")
		_check(rock.multimesh != null and rock.multimesh.mesh != null, "rock group has real Earth rock mesh")
		if rock.multimesh != null:
			rock_total += rock.multimesh.instance_count
	_check(rock_total == int(summary.get("rock_instances", -1)), "rock MultiMesh count matches composition summary")

	_check(not bool(summary.get("canonical_macro_source_replaced", true)), "scenery does not replace canonical macro source")
	_check(not bool(summary.get("ecology_individuals_created_by_scenery", true)), "scenery creates no ecology individuals")
	_check(not bool(summary.get("ecology_state_hash_changed_by_scenery", true)), "scenery reports no ecology hash mutation")
	_check(not bool(summary.get("descriptor_v2_changed_by_scenery", true)), "scenery reports no Descriptor V2 mutation")
	_check(not bool(summary.get("terrain_written_by_scenery", true)), "scenery reports no terrain write")

	var first_hash := String(summary.get("composition_hash", ""))
	var first_ground_hash := String(summary.get("ground_cover_hash", ""))
	var first_rock_hash := String(summary.get("rock_hash", ""))
	var first_macro_hash := String(summary.get("macro_bridge_hash", ""))
	_check(lab.rebuild_surface_scenery(int(summary.get("presentation_seed", -1))), "same-seed scenery rebuild succeeds")
	var repeated := lab.get_summary()
	_check(String(repeated.get("composition_hash", "")) == first_hash, "same seed reproduces exact composition hash")
	_check(String(repeated.get("ground_cover_hash", "")) == first_ground_hash, "same seed reproduces ground-cover hash")
	_check(String(repeated.get("rock_hash", "")) == first_rock_hash, "same seed reproduces rock hash")
	_check(String(repeated.get("source_ecology_hash", "")) == source_hash, "same-seed rebuild leaves ecology identity unchanged")

	_check(lab.rebuild_surface_scenery(int(summary.get("presentation_seed", -1)) + 1), "alternate presentation seed rebuild succeeds")
	var changed := lab.get_summary()
	_check(String(changed.get("composition_hash", "")) != first_hash, "alternate presentation seed changes composition identity")
	_check(
		String(changed.get("ground_cover_hash", "")) != first_ground_hash
		or String(changed.get("rock_hash", "")) != first_rock_hash,
		"alternate presentation seed changes at least one scenery layer"
	)
	_check(String(changed.get("source_ecology_hash", "")) == source_hash, "presentation reseed cannot mutate ecology hash")
	_check(String(changed.get("macro_bridge_hash", "")) == first_macro_hash, "presentation reseed cannot mutate PH5 macro identity")
	_check(LabScript.validate_summary(changed), "reseeded mixed summary still validates")

	var tampered := changed.duplicate(true)
	tampered["procedural_trees_visible"] = true
	_check(not LabScript.validate_summary(tampered), "visible procedural-tree claim rejected")
	tampered = changed.duplicate(true)
	tampered["ground_cover_truth_status"] = "CANONICAL"
	_check(not LabScript.validate_summary(tampered), "canonical ground-cover claim rejected")
	tampered = changed.duplicate(true)
	tampered["macro_ph5_active"] = false
	_check(not LabScript.validate_summary(tampered), "mixed summary without PH5 macro layer rejected")

	_check(lab.camera != null and lab.camera.current, "mixed lab owns an active composition camera")
	_check(lab.world_environment != null, "mixed lab owns local presentation environment")
	lab.queue_free()
	await process_frame


func _m3_source_boundary() -> void:
	var source := FileAccess.get_file_as_string(
		"res://scripts/labs/ecology/eco_evo7_vis5_3_mixed_strata_composition_lab.gd"
	)
	var lower := source.to_lower()
	_check(source.contains("eco_evo7_vis5_2_noncanonical_ground_cover_bridge.gd"), "VIS5.3 composes exact VIS5.2 bridge")
	_check(source.contains("eco_evo7_play0_planet_presentation.gd"), "VIS5.3 composes accepted PLAY0/VIS4 presentation")
	_check(source.contains("eco_evo7_vis4_morphology_render_adapter.gd"), "VIS5.3 consumes VIS4 Descriptor V2 adapter")
	_check(source.contains("eco_evo7_ls36_rule_workbench_v1.gd"), "VIS5.3 uses accepted Rule Workbench authority")
	_check(source.contains("procedural_earth_world.gd"), "VIS5.3 uses real ProceduralEarthWorld")
	_check(source.contains("earth_asset_library.gd"), "VIS5.3 reuses accepted Earth scenery assets")
	_check(not lower.contains("get_tree_mesh"), "VIS5.3 owns no procedural-tree mesh path")
	_check(not lower.contains("get_billboard_mesh"), "VIS5.3 owns no billboard-tree path")
	_check(not lower.contains("tree_density"), "VIS5.3 never samples procedural tree density")
	_check(not lower.contains("reproduce_bundle("), "VIS5.3 owns no reproduction implementation")
	_check(not lower.contains("mutation_seed("), "VIS5.3 owns no mutation implementation")
	_check(not lower.contains("fileaccess.write") and not lower.contains("fileaccess.write_read") and not lower.contains("store_") and not lower.contains("diraccess") and not lower.contains("multiplayer"), "VIS5.3 owns no persistence/network implementation")
	_check(not lower.contains("perf2.4"), "VIS5.3 cannot modify PERF2.4 thresholds")


func _watchdog() -> void:
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline and not _finished:
		await process_frame
	if not _finished:
		push_error("ECO.EVO7 VIS5.3 watchdog timeout")
		print("ECO.EVO7 VIS5.3 Mixed-Strata Composition Lab: FAIL (watchdog timeout)")
		quit(1)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("VIS5.3: " + label)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if failures.is_empty():
		print("ECO.EVO7 VIS5.3 Mixed-Strata Composition Lab: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("FAIL: " + failure)
	print("ECO.EVO7 VIS5.3 Mixed-Strata Composition Lab: FAIL (%d/%d)" % [failures.size(), assertions])
	quit(1)
