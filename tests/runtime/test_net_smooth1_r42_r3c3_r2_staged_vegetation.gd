extends SceneTree

# NET-SMOOTH1 R4.2 R3C.3 R2: exact legacy vs staged-vegetation parity and the
# negative falsifiers for staged CPU generation, bounded GPU upload and the
# atomic visual swap. Compares EVERY transform per bucket, not checksums.
const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const VegetationJob = preload("res://scripts/world/earth/earth_vegetation_build_job.gd")
const MAX_VISUAL_WAIT_MS := 180000
const TEST_WATCHDOG_SECONDS := 300.0

var assertions := 0
var failures: Array[String] = []
var _finished := false


func _init() -> void:
	call_deferred("_arm_watchdog")
	call_deferred("_run")


func _arm_watchdog() -> void:
	var timer := create_timer(TEST_WATCHDOG_SECONDS)
	timer.timeout.connect(_watchdog)


func _watchdog() -> void:
	if _finished:
		return
	failures.append("R3C3R2_TEST_WATCHDOG_EXPIRED_OR_SCRIPT_ERROR")
	_finish()


func _run() -> void:
	# --- Legacy synchronous reference -------------------------------------
	var legacy = EarthWorld.new()
	legacy.name = "LegacyEarthWorld"
	root.add_child(legacy)
	check(bool(legacy.setup()), "legacy world initializes with original sync path")
	if not legacy.initialized:
		legacy.free()
		_finish()
		return
	var legacy_global: Array = legacy.global_earth.mesh.surface_get_arrays(0)
	var legacy_local: Array = legacy.local_surface.mesh.surface_get_arrays(0)
	var legacy_placement_snapshot: Dictionary = _capture_placement(
		legacy.placement_system
	)
	var legacy_placement_summary: Dictionary = legacy.placement_system.get_summary()
	# The canonical spawn may legitimately reject ALL placement attempts; exact
	# parity is what matters. A forest anchor below guarantees non-empty buckets.
	check(int(legacy_placement_summary.get("pipeline_samples", -1)) == 76100,
		"legacy spawn exhausts the full 76100 attempt budget deterministically")

	# --- R2 staged world ---------------------------------------------------
	var staged = EarthWorld.new()
	staged.name = "StagedEarthWorld"
	root.add_child(staged)
	check(bool(staged.setup(null, true)), "staged R2 world setup accepted")
	var early: Dictionary = staged.get_r3c3_staged_geometry_report()
	check(bool(early.get("vegetation_staged", false)), "R2 staged vegetation advertised")
	check(bool(early.get("gpu_upload_staged", false)), "R2 staged GPU upload advertised")
	check(String(early.get("vegetation_phase", "")) == "IDLE",
		"no vegetation phase before geometry ready")
	var ready: bool = await _await_staged_world(staged, MAX_VISUAL_WAIT_MS)
	check(ready, "R2 staged global/local geometry plus vegetation complete")
	if not ready:
		legacy.queue_free()
		staged.queue_free()
		_finish()
		return
	var committed: Dictionary = staged.get_r3c3_staged_geometry_report()
	check(int(committed.get("committed_token", -1)) == 1, "initial R2 token committed")
	check(String(committed.get("vegetation_phase", "")) == "READY",
		"vegetation phases end in READY")
	check(String(committed.get("last_error", "")) == "", "no staged generation failure")

	# MESH PARITY
	_compare_mesh_arrays("global", legacy_global,
		staged.global_earth.mesh.surface_get_arrays(0))
	_compare_mesh_arrays("local", legacy_local,
		staged.local_surface.mesh.surface_get_arrays(0))
	check(staged.get_local_mesh_statistics() == legacy.get_local_mesh_statistics(),
		"local biome/slope statistics exact")
	check(staged.get_global_mesh_statistics() == legacy.get_global_mesh_statistics(),
		"global statistics exact")

	# VEGETATION PARITY: counts, order, every transform, materials, shadows.
	var staged_snapshot: Dictionary = _capture_placement(staged.placement_system)
	_compare_placement(legacy_placement_snapshot, staged_snapshot, "spawn")
	for field in ["seed", "near_trees", "billboard_trees", "grass", "rocks", "pipeline_samples"]:
		check(staged.placement_system.get_summary().get(field) ==
			legacy_placement_summary.get(field),
			"placement summary field exact: " + field)

	# LOD VISIBILITY parity under identical explicit flags.
	var lod_flags := {"near_trees": true, "billboard_trees": false, "grass": true, "rocks": false}
	legacy.placement_system.apply_lod_flags(lod_flags)
	staged.placement_system.apply_lod_flags(lod_flags)
	_compare_placement_visibility(legacy_placement_snapshot, staged_snapshot, "lod flags")

	# STAGE A job determinism runs below, at the forest anchor where vegetation
	# buckets are non-empty (the canonical spawn rejects every attempt).
	var spawn: Vector3 = staged.get_canonical_spawn_direction()

	# --- Recenter parity at two other directions/biomes --------------------
	# D2 is a searched forest biome so vegetation buckets are non-empty there
	# and the transform-by-transform comparison is meaningful.
	var direction_d1: Vector3 = (spawn + Vector3(0.11, -0.03, 0.05)).normalized()
	var direction_d2: Vector3 = legacy.find_biome_direction("forest")
	for pair in [[direction_d1, "D1"], [direction_d2, "D2"]]:
		staged.prepare_surface_region(pair[0], false)
		var pending: Dictionary = staged.get_r3c3_staged_geometry_report()
		check(bool(pending.get("old_complete_region_remains_visible_during_recenter", false)),
			"old region visible during " + String(pair[1]) + " recenter")
		ready = await _await_staged_world(staged, MAX_VISUAL_WAIT_MS)
		check(ready, String(pair[1]) + " staged recenter completes")
		if not ready:
			break
		legacy.prepare_surface_region(pair[0], false)
		_compare_mesh_arrays("local " + String(pair[1]),
			legacy.local_surface.mesh.surface_get_arrays(0),
			staged.local_surface.mesh.surface_get_arrays(0))
		_compare_placement(
			_capture_placement(legacy.placement_system),
			_capture_placement(staged.placement_system),
			String(pair[1])
		)
		check(legacy.get_local_mesh_statistics() == staged.get_local_mesh_statistics(),
			String(pair[1]) + " biome/slope statistics exact")

	# --- STAGE A job determinism at the non-empty forest anchor -------------
	var forest_snapshot: Dictionary = _capture_placement(staged.placement_system)
	var forest_summary: Dictionary = staged.placement_system.get_summary()
	check(int(forest_summary.get("near_trees", -1)) + int(forest_summary.get("grass", -1)) > 0,
		"forest anchor yields non-empty vegetation buckets")
	var whole_job = VegetationJob.new()
	check(bool(whole_job.configure(
		staged, staged.placement_system.config,
		staged.placement_system.tree_types, staged.placement_system.grass_types,
		staged.surface_center_direction, staged.surface_east, staged.surface_north,
		staged.surface_anchor_world, 901
	).get("success", false)), "reference job configures")
	while not whole_job.is_ready():
		whole_job.advance(100000, 2000000000)
	var draw_count_whole: int = whole_job.get_rng_draw_count()
	check(draw_count_whole > 1000, "RNG witness non-trivial")
	# One attempt per slice = the strongest frame-boundary splitting possible.
	var sliced_job = VegetationJob.new()
	check(bool(sliced_job.configure(
		staged, staged.placement_system.config,
		staged.placement_system.tree_types, staged.placement_system.grass_types,
		staged.surface_center_direction, staged.surface_east, staged.surface_north,
		staged.surface_anchor_world, 902
	).get("success", false)), "sliced job configures")
	var slices := 0
	while not sliced_job.is_ready() and slices < 400000:
		sliced_job.advance(1, 2000000000)
		slices += 1
	check(sliced_job.is_ready(), "one-attempt-per-slice job completes")
	check(sliced_job.get_rng_draw_count() == draw_count_whole,
		"RNG draw sequence identical across slice boundaries (no reset, no reorder)")
	_compare_buckets(whole_job, sliced_job, "slice-invariance")
	# And the committed visible MultiMeshes carry exactly these transforms.
	_compare_buckets_to_placement(whole_job, forest_snapshot, "committed-vs-job")
	# Deterministic seed derivation parity against the SAME anchor (forest).
	check(whole_job.get_placement_seed() == int(forest_summary.get("seed", -2)),
		"placement seed derivation exact vs legacy at the same anchor")
	check(whole_job.get_placement_seed() != int(legacy_placement_summary.get("seed", -3)),
		"different anchors derive different placement seeds")
	# RNG drift falsifier: a different seed MUST produce a different stream.
	var drifted_job = VegetationJob.new()
	var drifted_config: Dictionary = staged.placement_system.config.duplicate(true)
	drifted_config["seed"] = int(drifted_config.get("seed", 0)) + 1
	drifted_job.configure(
		staged, drifted_config,
		staged.placement_system.tree_types, staged.placement_system.grass_types,
		staged.surface_center_direction, staged.surface_east, staged.surface_north,
		staged.surface_anchor_world, 903
	)
	while not drifted_job.is_ready():
		drifted_job.advance(100000, 2000000000)
	var drift_detected := false
	for group in ["get_near_buckets", "get_billboard_buckets", "get_grass_buckets"]:
		var buckets_a: Dictionary = Callable(whole_job, group).call()
		var buckets_b: Dictionary = Callable(drifted_job, group).call()
		for type_id in buckets_a.keys():
			if buckets_a[type_id] != buckets_b.get(type_id, []):
				drift_detected = true
				break
		if drift_detected:
			break
	if not drift_detected:
		drift_detected = whole_job.get_rock_buckets() != drifted_job.get_rock_buckets()
	check(drift_detected, "comparator detects RNG drift (negative control is sensitive)")

	# --- Negative falsifiers on an isolated placement system ----------------
	var neg = legacy.placement_system
	var before_children: int = neg.get_child_count()
	check(not bool(neg.advance_staged_upload(16).get("success", true)),
		"NEG upload-before-allocate rejected")
	check(String(neg.get_staged_upload_report().get("phase", "")) != "UPLOAD_READY",
		"NEG upload state machine not bypassed")
	var empty_config := {}
	var bad_job = VegetationJob.new()
	check(not bool(bad_job.configure(
		staged, empty_config, [], [], spawn,
		staged.surface_east, staged.surface_north,
		staged.surface_anchor_world, 1
	).get("success", true)), "NEG vegetation job config validation (corrupt config)")

	var alloc = neg.begin_staged_generation(
		701, {"t": [Transform3D()]}, {"t": []}, {"g": [Transform3D()]}, [[], [], []]
	)
	check(bool(alloc.get("success", false)), "NEG candidate allocate ok")
	check(not bool(neg.commit_staged_generation(701).get("success", true)),
		"NEG commit-before-upload-ready rejected")
	# Partial upload: deliberately incomplete GPU upload must not commit.
	neg.advance_staged_upload(1)
	check(not bool(neg.commit_staged_generation(701).get("success", true)),
		"NEG incomplete GPU upload commit rejected")
	neg.advance_staged_upload(1000000)
	check(not bool(neg.commit_staged_generation(999).get("success", true)),
		"NEG stale generation token commit rejected")
	var commit_ok: Dictionary = neg.commit_staged_generation(701)
	check(bool(commit_ok.get("success", false)), "NEG complete correct-token commit ok")
	check(not bool(neg.commit_staged_generation(701).get("success", true)),
		"NEG double commit of one region rejected")
	# Baseline AFTER the committed NEG region: only scratch candidates must be
	# freed by cancellation, committed visible nodes stay.
	var neg_children_after_commit: int = neg.get_child_count()
	var corrupt = neg.begin_staged_generation(
		702, {"t": "not-an-array"}, {"t": []}, {"g": []}, [[], [], []]
	)
	check(not bool(corrupt.get("success", true)),
		"NEG corrupted bucket rejected before GPU allocation: "
		+ String(corrupt.get("error_code", "")))
	neg.cancel_staged_generation()
	check(neg.get_child_count() == neg_children_after_commit,
		"NEG scratch cancellation leaves visible children untouched")
	check(int(neg.get_staged_upload_report().get("instance_count_total", -1)) == 0,
		"NEG scratch instance counters reset after cancellation")

	# --- Teleport A -> B -> C: only C may publish ---------------------------
	var direction_a: Vector3 = (spawn + Vector3(0.02, 0.01, 0.0)).normalized()
	var direction_b: Vector3 = (spawn + Vector3(0.05, 0.02, 0.0)).normalized()
	var direction_c2: Vector3 = (spawn + Vector3(0.08, 0.02, 0.0)).normalized()
	var prior_mesh = staged.local_surface.mesh
	staged.prepare_surface_region(direction_a, false)
	staged.prepare_surface_region(direction_b, false)
	staged.prepare_surface_region(direction_c2, false)
	var fast: Dictionary = staged.get_r3c3_staged_geometry_report()
	check(int(fast.get("target_token", -1)) >= 4, "teleport A->B->C advanced tokens")
	check(staged.local_surface.mesh == prior_mesh, "old mesh held during A->B->C storm")
	ready = await _await_staged_world(staged, MAX_VISUAL_WAIT_MS)
	check(ready, "teleport storm settles on newest region")
	if ready:
		var final_report: Dictionary = staged.get_r3c3_staged_geometry_report()
		check(staged.surface_center_direction.is_equal_approx(direction_c2),
			"only newest C region published")
		check(int(final_report.get("staged_upload", {}).get("candidates", -1)) == 0,
			"no invisible MultiMesh accumulation after supersede")
		check(staged.local_surface.mesh != prior_mesh, "C mesh replaced old only at commit")
		legacy.prepare_surface_region(direction_c2, false)
		_compare_placement(
			_capture_placement(legacy.placement_system),
			_capture_placement(staged.placement_system),
			"teleport-C"
		)
	var timings: Dictionary = committed.get("r3c3r2_timings", {})
	print("R3C3R2_MESH_UPLOAD_MS=%0.3f" % float(timings.get("mesh_upload_ms", 0.0)))
	print("R3C3R2_CPU_SLICE_MAX_MS=%0.3f" % float(timings.get("cpu_slice_max_ms", 0.0)))
	print("R3C3R2_VERIFY_MS=%0.3f" % float(timings.get("verify_ms", 0.0)))
	print("R3C3R2_VISUAL_COMMIT_MS=%0.3f" % float(timings.get("visual_commit_ms", 0.0)))
	var upload_report: Dictionary = staged.placement_system.get_staged_upload_report()
	print("R3C3R2_GPU_ALLOC_MS=%0.3f" % float(upload_report.get("allocate_ms", 0.0)))
	print("R3C3R2_GPU_UPLOAD_MS_MAX=%0.3f" % float(upload_report.get("upload_ms_max", 0.0)))

	legacy.queue_free()
	staged.queue_free()
	_finish()


func _await_staged_world(world, deadline_ms: int) -> bool:
	var until: int = Time.get_ticks_msec() + deadline_ms
	while Time.get_ticks_msec() < until:
		var report: Dictionary = world.get_r3c3_staged_geometry_report()
		if bool(report.get("visual_region_ready", false)):
			return true
		if not String(report.get("last_error", "")).is_empty():
			failures.append("R3C3R2_JOB_FAILED:" + String(report.get("last_error", "")))
			return false
		await process_frame
	return false


func _capture_placement(placement_system) -> Dictionary:
	# Snapshot every live MultiMeshInstance3D: identity, flags and ALL
	# instance transforms. Transforms come from the authoritative CPU source
	# arrays: MultiMesh readback depends on the rendering backend (the
	# headless dummy server returns identity), while the source arrays are
	# the exact data uploaded on every backend.
	var result: Dictionary = {}
	for child in placement_system.get_children():
		if not child is MultiMeshInstance3D:
			continue
		var node_name: String = String(child.name)
		var transforms: Array = []
		if placement_system.committed_transform_sources.has(node_name):
			transforms = placement_system.committed_transform_sources[node_name].duplicate(true)
		else:
			var multi_mesh: MultiMesh = child.multimesh
			for index in range(multi_mesh.instance_count):
				transforms.append(multi_mesh.get_instance_transform(index))
		result[node_name] = {
			"transforms": transforms,
			"cast_shadow": child.cast_shadow,
			"material_override": child.material_override,
			"visible": child.visible,
		}
	return result


func _compare_placement(expected: Dictionary, actual: Dictionary, label: String) -> void:
	var names_expected := expected.keys()
	var names_actual := actual.keys()
	check(names_expected == names_actual,
		label + " MultiMesh bucket names and order exact")
	for node_name in names_expected:
		if not actual.has(node_name):
			continue
		var left: Dictionary = expected[node_name]
		var right: Dictionary = actual[node_name]
		var left_transforms: Array = left["transforms"]
		var right_transforms: Array = right["transforms"]
		check(left_transforms.size() == right_transforms.size(),
			"%s/%s instance count exact (%d vs %d)" % [
				label, node_name, left_transforms.size(), right_transforms.size()
			])
		var mismatch_index := -1
		var mismatch_field := ""
		for index in range(mini(left_transforms.size(), right_transforms.size())):
			var a: Transform3D = left_transforms[index]
			var b: Transform3D = right_transforms[index]
			if a.origin != b.origin:
				mismatch_index = index
				mismatch_field = "position"
				break
			if a.basis != b.basis:
				mismatch_index = index
				mismatch_field = "basis"
				break
			if a.basis.get_scale() != b.basis.get_scale():
				mismatch_index = index
				mismatch_field = "scale"
				break
		check(mismatch_index < 0,
			"%s/%s all transforms exact (first mismatch: index=%d field=%s)" % [
				label, node_name, mismatch_index, mismatch_field
			])
		check(left["cast_shadow"] == right["cast_shadow"],
			"%s/%s shadow flags exact" % [label, node_name])
		check(_material_fingerprint(left["material_override"]) ==
			_material_fingerprint(right["material_override"]),
			"%s/%s material assignment exact" % [label, node_name])


func _compare_placement_visibility(expected: Dictionary, actual: Dictionary, label: String) -> void:
	for node_name in expected.keys():
		if not actual.has(node_name):
			continue
		check(bool(expected[node_name]["visible"]) == bool(actual[node_name]["visible"]),
			"%s/%s LOD visibility exact" % [label, node_name])


func _compare_buckets(job_a, job_b, label: String) -> void:
	for group in ["get_near_buckets", "get_billboard_buckets", "get_grass_buckets"]:
		var buckets_a: Dictionary = Callable(job_a, group).call()
		var buckets_b: Dictionary = Callable(job_b, group).call()
		check(buckets_a.keys() == buckets_b.keys(), label + " " + group + " keys exact")
		for type_id in buckets_a.keys():
			check(buckets_a[type_id] == buckets_b[type_id],
				label + " " + group + "/" + String(type_id) + " transforms exact")
	var rocks_a: Array = job_a.get_rock_buckets()
	var rocks_b: Array = job_b.get_rock_buckets()
	check(rocks_a == rocks_b, label + " rock buckets transforms exact")


func _compare_buckets_to_placement(job, snapshot: Dictionary, label: String) -> void:
	var expected_by_name: Dictionary = {}
	for type_id in job.get_near_buckets().keys():
		if job.get_near_buckets()[type_id].is_empty():
			continue
		expected_by_name["NearTrees_%s" % type_id] = job.get_near_buckets()[type_id]
	for type_id in job.get_billboard_buckets().keys():
		if job.get_billboard_buckets()[type_id].is_empty():
			continue
		expected_by_name["BillboardTrees_%s" % type_id] = job.get_billboard_buckets()[type_id]
	for type_id in job.get_grass_buckets().keys():
		if job.get_grass_buckets()[type_id].is_empty():
			continue
		expected_by_name["Grass_%s" % type_id] = job.get_grass_buckets()[type_id]
	for variant in range(job.get_rock_buckets().size()):
		if job.get_rock_buckets()[variant].is_empty():
			continue
		expected_by_name["Rocks_%d" % variant] = job.get_rock_buckets()[variant]
	check(not expected_by_name.is_empty(),
		label + " job produced at least one non-empty bucket")
	for node_name in expected_by_name.keys():
		if not snapshot.has(node_name):
			check(false, label + " missing committed bucket " + node_name)
			continue
		check(snapshot[node_name]["transforms"] == expected_by_name[node_name],
			label + " " + node_name + " committed transforms exact vs CPU scratch")


func _compare_mesh_arrays(label: String, expected: Array, actual: Array) -> void:
	for kind in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_INDEX, Mesh.ARRAY_NORMAL,
			Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV]:
		var field_name := "%s geometry array slot %d" % [label, kind]
		if expected.size() <= kind or actual.size() <= kind:
			check(false, field_name + " missing")
			continue
		check(expected[kind].size() == actual[kind].size(), field_name + " count exact")
		check(expected[kind] == actual[kind], field_name + " entire PackedArray parity")


func _material_fingerprint(material) -> String:
	# Cross-world identity comparison is meaningless: each Earth world owns an
	# independent asset library instance. Compare the full semantic state.
	if material == null:
		return "null"
	var fields: Array = [
		material.get_class(), material.resource_name,
	]
	if material is StandardMaterial3D:
		fields.append_array([
			material.albedo_color, material.roughness, material.metallic,
			material.cull_mode, material.shading_mode, material.transparency,
			material.billboard_mode, material.vertex_color_use_as_albedo,
		])
	return var_to_str(fields)


func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures.append(message)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	for problem in failures:
		push_error("[R3C3R2] " + problem)
	print("NET_SMOOTH_R3C3_R2_STAGED_VEGETATION %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()
	])
	quit(0 if failures.is_empty() else 1)
