extends SceneTree

# R3C3 R1 real Godot double: deterministic legacy vs staged GPU-array parity,
# same default spawn, and the canceled intermediate local region never commits.
# This does NOT claim staged vegetation/ArrayMesh upload is frame-budget safe.
const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const MAX_VISUAL_WAIT_MS := 120000
const TEST_WATCHDOG_SECONDS := 150.0

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
	failures.append("R3C3_TEST_WATCHDOG_EXPIRED_OR_SCRIPT_ERROR")
	_finish()


func _run() -> void:
	var legacy = EarthWorld.new()
	legacy.name = "LegacyEarthWorld"
	root.add_child(legacy)
	check(bool(legacy.setup()), "legacy world initializes with original sync geometry and vegetation")
	if not legacy.initialized:
		legacy.free()
		_finish()
		return
	var original_global: Array = legacy.global_earth.mesh.surface_get_arrays(0)
	var original_local: Array = legacy.local_surface.mesh.surface_get_arrays(0)
	var original_global_stats: Dictionary = legacy.get_global_mesh_statistics()
	var original_local_stats: Dictionary = legacy.get_local_mesh_statistics()
	var original_placement: Dictionary = legacy.placement_system.get_summary()
	check(int(original_global_stats.get("sample_count", -1)) == 8385,
		"legacy global exact vertex count sourced from default Earth config")
	check(int(original_local_stats.get("sample_count", -1)) == 13825,
		"legacy local exact vertex count sourced from default Earth config")

	var staged = EarthWorld.new()
	staged.name = "StagedEarthWorld"
	root.add_child(staged)
	var initial_started_us := Time.get_ticks_usec()
	check(bool(staged.setup(null, true)), "opt-in staged world setup accepted")
	var setup_ms := float(Time.get_ticks_usec() - initial_started_us) / 1000.0
	var early: Dictionary = staged.get_r3c3_staged_geometry_report()
	check(bool(early.get("enabled", false)), "staged client world flag is explicit")
	check(not bool(early.get("global_ready", true)), "global geometry not eagerly built by setup")
	check(not bool(early.get("local_ready", true)), "local geometry not eagerly built by setup")
	check(not bool(early.get("visual_region_ready", true)), "world reports visual loading separately from game readiness")
	check(staged.global_earth.mesh == null, "global ArrayMesh is not uploaded in synchronous setup")
	check(staged.local_surface.mesh == null, "local ArrayMesh is not uploaded in synchronous setup")
	check(int(early.get("target_token", -1)) == 1, "one initial local request queued")
	# R2 now stages vegetation and GPU upload behind the same explicit flag.
	check(bool(early.get("vegetation_staged", false)), "R2 stages vegetation preparation")
	check(bool(early.get("gpu_upload_staged", false)), "R2 stages GPU transform upload")
	print("R3C3_R1_INIT_SETUP_MS=%0.3f" % setup_ms)

	# _ready spawn teleport requests exactly the same direction again. In
	# the old path it regenerates 13,825 terrain samples + vegetation twice.
	staged.prepare_surface_region(staged.get_canonical_spawn_direction(), false)
	var deduplicated: Dictionary = staged.get_r3c3_staged_geometry_report()
	check(int(deduplicated.get("target_token", -1)) == 1,
		"default EarthExplorer activation does not build a second local region")
	var ready: bool = await _await_staged_world(staged, MAX_VISUAL_WAIT_MS)
	check(ready, "staged global and local jobs complete within test watchdog")
	if not ready:
		legacy.queue_free()
		staged.queue_free()
		_finish()
		return
	var first: Dictionary = staged.get_r3c3_staged_geometry_report()
	check(bool(first.get("global_ready", false)) and bool(first.get("local_ready", false)),
		"both exact geometry jobs committed with one active visual token")
	check(int(first.get("committed_token", -1)) == 1, "committed initial geometry token exactly one")
	check(staged.global_earth.mesh != null and staged.local_surface.mesh != null,
		"main-thread ArrayMesh upload completed only after scratch was ready")

	_compare_mesh_arrays("global", original_global, staged.global_earth.mesh.surface_get_arrays(0))
	_compare_mesh_arrays("local", original_local, staged.local_surface.mesh.surface_get_arrays(0))
	check(staged.get_global_mesh_statistics() == original_global_stats,
		"global mesh geometric statistics bit/field identical")
	check(staged.get_local_mesh_statistics() == original_local_stats,
		"local mesh geometric statistics bit/field identical")
	var staged_placement: Dictionary = staged.placement_system.get_summary()
	for field in ["seed", "near_trees", "billboard_trees", "grass", "rocks", "pipeline_samples"]:
		check(staged_placement.get(field) == original_placement.get(field),
			"R1 retains original vegetation counts and deterministic seed: " + field)

	# New direction B is superseded by C before CPU scratch reaches READY.
	# Until C is fully prepared, the old completed mesh and its anchor
	# remain visible/unmodified. No stale B publication is permitted.
	var spawn: Vector3 = staged.get_canonical_spawn_direction()
	var prior_mesh = staged.local_surface.mesh
	var prior_anchor: Vector3 = staged.get_surface_anchor()
	var direction_b: Vector3 = (spawn + Vector3(0.07, 0.0, 0.02)).normalized()
	var direction_c: Vector3 = (spawn + Vector3(-0.05, 0.01, -0.03)).normalized()
	staged.prepare_surface_region(direction_b, false)
	var b_token := int(staged.get_r3c3_staged_geometry_report().get("target_token", -1))
	staged.prepare_surface_region(direction_c, false)
	var c: Dictionary = staged.get_r3c3_staged_geometry_report()
	check(int(c.get("target_token", -1)) == b_token + 1,
		"new region invalidates old scratch token monotonically")
	check(int(c.get("stale_cancellations", 0)) >= 1, "abandoned B build counted")
	check(not bool(c.get("visual_region_ready", true)), "target C is not falsely reported ready")
	check(bool(c.get("old_complete_region_remains_visible_during_recenter", false)),
		"old complete visual remains visible during new region request")
	check(staged.local_surface.mesh == prior_mesh, "old local mesh retained until complete C")
	check(staged.get_surface_anchor() == prior_anchor, "old visual anchor stays unchanged during C")
	ready = await _await_staged_world(staged, MAX_VISUAL_WAIT_MS)
	check(ready, "new C region completed after stale B cancellation")
	if ready:
		var latest: Dictionary = staged.get_r3c3_staged_geometry_report()
		check(int(latest.get("committed_token", -1)) == b_token + 1,
			"no canceled B token became visible instead of C")
		check(staged.surface_center_direction.is_equal_approx(direction_c),
			"last request C wins region identity")
		check(staged.local_surface.mesh != prior_mesh,
			"new C geometry replaced old complete region only at commit")
		# Legacy counterpart is still the accepted production generator.
		legacy.prepare_surface_region(direction_c, false)
		_compare_mesh_arrays(
			"recenter C",
			legacy.local_surface.mesh.surface_get_arrays(0),
			staged.local_surface.mesh.surface_get_arrays(0)
		)
		check(staged.get_local_mesh_statistics() == legacy.get_local_mesh_statistics(),
			"recenter C stats match exact canonical legacy sample order")

	check(staged.get_r3c3_staged_geometry_report().get("last_error", "") == "",
		"no async geometry build failure")
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
			failures.append("R3C3_JOB_FAILED:" + String(report.get("last_error", "")))
			return false
		await process_frame
	return false


func _compare_mesh_arrays(label: String, expected: Array, actual: Array) -> void:
	for kind in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_INDEX, Mesh.ARRAY_NORMAL,
			Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV]:
		var field_name := "%s geometry array slot %d" % [label, kind]
		if expected.size() <= kind or actual.size() <= kind:
			check(false, field_name + " missing")
			continue
		var left = expected[kind]
		var right = actual[kind]
		check(left.size() == right.size(), field_name + " count exact")
		check(left == right, field_name + " entire PackedArray byte/value parity")


func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures.append(message)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	for problem in failures:
		push_error("[R3C3] " + problem)
	print("NET_SMOOTH_R3C3_R1_STAGED_EARTH %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()
	])
	quit(0 if failures.is_empty() else 1)
