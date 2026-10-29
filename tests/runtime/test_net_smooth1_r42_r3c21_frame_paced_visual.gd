extends SceneTree

# Independent Godot R3C3 R2.1 falsifier. A visual-only opt-in must keep the
# original accepted CPU geometry, RNG and M6-free authority unchanged.
# Hidden renderer candidates are registered one per frame; old visible
# MultiMeshes stay untouched until the fully ready token is committed.
const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Preattach = preload("res://scripts/world/vegetation/earth_placement_system.gd")
const TEST_WATCHDOG_SECONDS := 280.0
const MAX_WAIT_MS := 220000

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
	failures.append("R3C21_WATCHDOG_OR_SCRIPT_ERROR")
	_finish()


func _run() -> void:
	var legacy = EarthWorld.new()
	legacy.name = "AcceptedLegacyEarth"
	root.add_child(legacy)
	check(bool(legacy.setup()), "accepted legacy Earth remains available")
	if not legacy.initialized:
		legacy.free()
		_finish()
		return
	var spawn := legacy.get_canonical_spawn_direction()
	var baseline_geom = legacy.local_surface.mesh.surface_get_arrays(0)
	var baseline_placement: Dictionary = legacy.placement_system.committed_transform_sources.duplicate(true)

	var candidate = EarthWorld.new()
	candidate.name = "R3C21ClientEarth"
	root.add_child(candidate)
	check(bool(candidate.setup(null, true, true)), "R2.1 opt-in enabled only explicitly")
	var early: Dictionary = candidate.get_r3c3_staged_geometry_report()
	check(bool(early.get("r3c21", {}).get("enabled", false)),
		"frame-paced vegetation is independently toggleable")
	check(candidate.local_surface.mesh == null, "R2.1 no eager local terrain")
	check(candidate.placement_system.get_staged_upload_report().get("r21_preattach_enabled", false),
		"placement opt-in inherited from owning Earth scene")
	# Default duplicate teleport must not restart the in-flight job.
	candidate.prepare_surface_region(spawn, false)
	check(int(candidate.get_r3c3_staged_geometry_report().get("target_token", 0)) == 1,
		"duplicate default spawn remains coalesced")
	var ready := await _await_visual_ready(candidate, MAX_WAIT_MS)
	check(ready, "first Earth presentation committed after paced CPU/GPU")
	if not ready:
		legacy.queue_free()
		candidate.queue_free()
		_finish()
		return
	var data: Dictionary = candidate.get_r3c3_staged_geometry_report()
	check(int(data.get("committed_token", -1)) == 1, "initial visual generation committed once")
	_compare_arrays(baseline_geom, candidate.local_surface.mesh.surface_get_arrays(0),
		"default local geometry exact")
	check(candidate.placement_system.committed_transform_sources == baseline_placement,
		"source-side exact vegetation transforms retained under paced mode")
	check(candidate.get_local_mesh_statistics() == legacy.get_local_mesh_statistics(),
		"CPU geometric statistics exact")
	check(candidate.get_r3c3_staged_geometry_report().get("last_error", "") == "",
		"no dropped CPU or preattach state")

	# Real Godot Node-name collision falsifier: old Grass_short remains visible
	# while a NEW Grass_short candidate is registered hidden in the same
	# SceneTree parent. Only the accepted name may appear after commit.
	var miniature = Preattach.new()
	miniature.name = "R3C21SameNameFalsifier"
	root.add_child(miniature)
	check(bool(miniature.setup(legacy, legacy.pipeline, legacy.assets)),
		"synthetic one-transform scene uses accepted Earth assets")
	miniature.configure_frame_paced_preattach(true)
	var occupied = MultiMeshInstance3D.new()
	occupied.name = "Grass_short"
	miniature.add_child(occupied)
	var started: Dictionary = miniature.begin_staged_generation(
		989, {}, {}, {"short": [Transform3D.IDENTITY]}, [[], [], []]
	)
	check(bool(started.get("success", false)),
		"same-name new grass candidate allocated detached")
	var uploaded: Dictionary = miniature.advance_staged_upload(8)
	check(bool(uploaded.get("success", false)) and
		bool(uploaded.get("details", {}).get("ready", false)),
		"one exact GPU transform uploaded")
	var attached: Dictionary = miniature.advance_staged_preattach(989, 1)
	check(bool(attached.get("success", false)) and
		bool(attached.get("details", {}).get("ready", false)),
		"new grass candidate registered while old name is occupied")
	check(occupied.name == "Grass_short" and occupied.visible,
		"old same-name visible group remains unchanged")
	check(miniature.get_child_count() == 2,
		"old and new hidden vegetation coexist in SceneTree")
	var hidden = miniature.get_child(1)
	check(not hidden.visible and String(hidden.name).begins_with("_R3C21_PENDING_"),
		"new candidate name collision prevented before commit")
	check(String(hidden.get_meta("r3c21_canonical_name", "")) == "Grass_short",
		"exact accepted grass bucket name preserved as private metadata")
	var committed_mini: Dictionary = miniature.commit_staged_generation(989)
	check(bool(committed_mini.get("success", false)),
		"same-name candidate canonical swap succeeds")
	check(miniature.get_child_count() == 1 and
		String(miniature.get_child(0).name) == "Grass_short" and
		miniature.get_child(0).visible,
		"canonical Grass_short restored, exactly one visible group remains")
	check(int(miniature.get_staged_upload_report().get("r21_retired_remaining", -1)) == 1,
		"old same-name group queued for bounded retirement")
	check(bool(miniature.drain_retired_visuals(1).get("success", false)),
		"detached old GPU object drained safely")
	miniature.queue_free()

	# Forest guarantees visible tree/grass candidates. The accepted R2 fixture
	# already demonstrated full transform-by-transform parity at this biome.
	var forest: Vector3 = legacy.find_biome_direction("forest")
	check(forest.length_squared() > 0.8, "independent forest anchor found")
	var committed_before = candidate.local_surface.mesh
	var anchor_before: Vector3 = candidate.surface_anchor_world
	var token_before := int(data.get("committed_token", 0))
	var old_live: Array = candidate.placement_system.get_children().duplicate()

	candidate.prepare_surface_region(forest, false)
	var target: int = int(candidate.get_r3c3_staged_geometry_report().get("target_token", -1))
	check(target == token_before + 1, "forest request creates a monotonic visual token")
	var until := Time.get_ticks_msec() + MAX_WAIT_MS
	var entered_preattach := false
	var attached_hidden := false
	while Time.get_ticks_msec() < until:
		var progress: Dictionary = candidate.placement_system.get_staged_upload_report()
		var phase := String(progress.get("phase", ""))
		if phase in [Preattach.R3C21_PHASE_PREATTACH, Preattach.R3C21_PHASE_PREATTACHED]:
			entered_preattach = true
			var attached_count := int(progress.get("r21_preattach_nodes", 0))
			if attached_count > 0:
				attached_hidden = true
				for child in candidate.placement_system.get_children():
					if child is MultiMeshInstance3D and not old_live.has(child):
						check(not child.visible, "new preattached candidate remains hidden")
				break
		if not String(candidate.get_r3c3_staged_geometry_report().get("last_error", "")).is_empty():
			break
		await process_frame
	check(entered_preattach, "forest GPU upload reached opt-in paced preattach phase")
	check(attached_hidden, "at least one real forest MultiMesh node preattached hidden")
	check(candidate.local_surface.mesh == committed_before,
		"old region mesh still visible during delayed preattach")
	check(candidate.surface_anchor_world == anchor_before,
		"old region anchor unchanged during delayed preattach")
	check(candidate.placement_system.committed_transform_sources == baseline_placement,
		"old committed vegetation transforms untouched before atomic swap")
	var wrong_token: Dictionary = candidate.placement_system.advance_staged_preattach(target - 1, 1)
	check(not bool(wrong_token.get("success", false)), "stale preattach token rejected")
	check(int(candidate.placement_system.get_staged_upload_report().get("r21_preattach_nodes", 0)) > 0,
		"wrong token cannot attach or erase valid candidates")

	# Cancel while at least one new candidate is already a hidden child.
	# The pending token MUST clean up those children (including resource RID)
	# and leave the current completed region intact until C finishes.
	var direction_c := (forest + Vector3(0.07, 0.0, 0.03)).normalized()
	candidate.prepare_surface_region(direction_c, false)
	check(int(candidate.get_r3c3_staged_geometry_report().get("target_token", -1)) == target + 1,
		"new C request supersedes partially preattached B")
	check(candidate.local_surface.mesh == committed_before,
		"supersede keeps old visible mesh")
	check(candidate.surface_anchor_world == anchor_before,
		"supersede keeps old visual anchor")
	await process_frame
	for child in candidate.placement_system.get_children():
		if child is MultiMeshInstance3D:
			check(old_live.has(child), "abandoned hidden B candidate removed from scene")
	ready = await _await_visual_ready(candidate, MAX_WAIT_MS)
	check(ready, "latest C eventually publishes intact region")
	if ready:
		var report: Dictionary = candidate.get_r3c3_staged_geometry_report()
		check(int(report.get("committed_token", -1)) == target + 1,
			"stale B never committed")
		check(candidate.surface_center_direction.is_equal_approx(direction_c),
			"new C center exact")
		check(candidate.local_surface.mesh != committed_before,
			"atomically swapped terrain to requested C")
		legacy.prepare_surface_region(direction_c, false)
		_compare_arrays(legacy.local_surface.mesh.surface_get_arrays(0),
			candidate.local_surface.mesh.surface_get_arrays(0), "C local geometry exact")
		check(legacy.placement_system.committed_transform_sources ==
			candidate.placement_system.committed_transform_sources,
			"all tree/grass/rock transforms identical after C paced publish")
		for _i in range(30):
			await process_frame
		check(int(candidate.placement_system.get_staged_upload_report().get(
			"r21_retired_remaining", -1)) == 0,
			"old disconnected GPU resource groups drained on bounded later frames")
	check(String(candidate.get_r3c3_staged_geometry_report().get("last_error", "")) == "",
		"no unsafe background state or failed visibility swap")
	legacy.queue_free()
	candidate.queue_free()
	_finish()


func _compare_arrays(left: Array, right: Array, label: String) -> void:
	for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR,
		Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX]:
		check(left[slot] == right[slot], label + " full packed array " + str(slot))


func _await_visual_ready(world, timeout_ms: int) -> bool:
	var until := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < until:
		var status: Dictionary = world.get_r3c3_staged_geometry_report()
		if bool(status.get("visual_region_ready", false)):
			return true
		if not String(status.get("last_error", "")).is_empty():
			failures.append("R3C21_VISUAL_FAILURE:" + String(status.get("last_error", "")))
			return false
		await process_frame
	return false


func check(ok: bool, name: String) -> void:
	assertions += 1
	if not ok:
		failures.append(name)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	for name in failures:
		push_error("R3C21_FAIL:" + name)
	print("NET_SMOOTH_R3C21_FRAME_PACED %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()
	])
	quit(0 if failures.is_empty() else 1)
