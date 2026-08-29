extends SceneTree

const Play0Scene = preload("res://scenes/labs/ecology/eco_evo7_play0_live_planet_playground.tscn")
const WorkbenchScript = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")

var assertions := 0
var failures: Array[String] = []
var _finished := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_start_watchdog(420.0)
	var playground = Play0Scene.instantiate()
	playground.auto_initialize = false
	root.add_child(playground)
	await process_frame
	await process_frame

	# (1) runtime initializes over the real planet.
	var ok: bool = playground.initialize_runtime()
	_check(ok, "PLAY0 runtime initializes")
	if not ok:
		_finish()
		return
	await process_frame

	var earth = playground.get_earth_world()
	var player = playground.get_player()
	var spectator = playground.get_spectator()
	var presentation = playground.get_presentation()

	# (2) real ProceduralEarthWorld exists and is the accepted implementation.
	_check(earth != null and earth.initialized, "real ProceduralEarthWorld exists and initialized")
	_check(
		String(earth.get_script().resource_path).ends_with("procedural_earth_world.gd"),
		"planet is the accepted procedural_earth_world.gd"
	)

	# (3) terrain collision exists (trimesh StaticBody3D from the local surface).
	_check(playground.has_terrain_collision(), "terrain trimesh collision exists")
	_check(
		earth.local_surface.get_node_or_null("EarthTerrainCollision") != null,
		"collision body hangs off the streamed local surface"
	)

	# (4) default mode is GROUND.
	_check(String(playground.get_mode()) == "GROUND", "default mode is GROUND")

	# (5) earth_humanoid controller is active on the existing lunar player.
	_check(playground.is_earth_humanoid_active(), "earth_humanoid is the active controller")
	_check(
		String(player.get_script().resource_path).ends_with("lunar_player.gd"),
		"player is the accepted lunar_player.gd CharacterBody3D"
	)

	# Ground stability: player stands on terrain, does not fall through.
	for _index in 45:
		await physics_frame
	_check(player.is_on_floor(), "player stands on terrain after physics settles")
	var spawn_altitude: float = earth.get_altitude(player.get_world_position())
	_check(absf(spawn_altitude) < 8.0, "spawn altitude near surface (no fall-through)")

	# (6) GROUND -> SPECTATOR works and is a real free camera over the planet.
	_check(String(playground.toggle_mode()) == "SPECTATOR", "GROUND -> SPECTATOR works")
	_check(bool(spectator.active), "spectator controller owns the active camera")
	_check(not playground.is_earth_humanoid_active(), "humanoid frozen while spectator")
	var radial_up: Vector3 = spectator.get_world_position().normalized()
	spectator.world_position += radial_up * 6000.0
	await process_frame
	var spectator_altitude: float = earth.get_altitude(spectator.get_world_position())
	_check(spectator_altitude > 4000.0, "spectator flies over the planet (alt %.0f m)" % spectator_altitude)

	# (7) SPECTATOR -> GROUND works at a remote location (recenter + land).
	var east: Vector3 = Vector3.UP.cross(radial_up).normalized()
	spectator.world_position += east * 25000.0 + radial_up * -4000.0
	var refreshes_before_landing: int = playground.get_collision_refresh_count()
	_check(String(playground.toggle_mode()) == "GROUND", "SPECTATOR -> GROUND works")
	_check(
		playground.get_collision_refresh_count() > refreshes_before_landing,
		"remote landing rebuilt the local region and refreshed collision"
	)
	for _index in 120:
		await physics_frame
	_check(player.is_on_floor(), "player lands on the remote surface")
	var remote_altitude: float = earth.get_altitude(player.get_world_position())
	_check(absf(remote_altitude) < 10.0, "remote landing altitude near surface (no fall-through)")
	_check(
		player.get_world_position().normalized().angle_to(
			spectator.get_world_position().normalized()
		) < 0.01,
		"player landed at the spectator direction, not the old spawn"
	)

	# (16) Earth region rebuild refreshes terrain collision.
	var refreshes_before_forced: int = playground.get_collision_refresh_count()
	var old_direction: Vector3 = player.get_world_position().normalized()
	var rotated := old_direction.rotated(Vector3.UP, 0.05).normalized()
	earth.prepare_surface_region(rotated, false)
	_check(
		playground.get_collision_refresh_count() > refreshes_before_forced,
		"Earth region rebuild refreshes terrain collision"
	)
	_check(playground.has_terrain_collision(), "collision stays valid after rebuild")

	# (8) accepted LS3.6 Workbench exists and is the ecology authority.
	var workbench = playground.get_workbench()
	_check(workbench != null and workbench.initialized, "accepted LS3.6 Workbench exists")
	_check(
		String(workbench.get_script().resource_path).ends_with("eco_evo7_ls36_rule_workbench_v1.gd"),
		"ecology source of truth is the accepted LS3.6 Workbench script"
	)

	# (9) ecology state hash initially valid.
	var initial: Dictionary = playground.get_published_snapshot()
	var initial_hash := String(initial.get("ecology_state_hash", ""))
	_check(initial_hash.length() == 64, "initial ecology state hash is valid")

	# (14) second simultaneous generation request is rejected fail-closed.
	_check(playground.request_generation(), "manual generation request accepted")
	_check(
		not playground.request_generation(),
		"second simultaneous generation request rejected fail-closed"
	)
	_check(playground.get_generation_rejections() >= 1, "rejection is observable")

	# (15) completed background generation publishes only completed snapshots.
	var in_flight_hash := String(playground.get_published_snapshot().get("ecology_state_hash", ""))
	_check(in_flight_hash == initial_hash, "in-flight generation does not expose partial state")
	var join_deadline := Time.get_ticks_msec() + 60000
	while playground.is_generation_running() and Time.get_ticks_msec() < join_deadline:
		_check(
			String(playground.get_published_snapshot().get("ecology_state_hash", "")) == initial_hash,
			"presentation source stays on the completed snapshot while a generation runs"
		)
		await process_frame
	_check(not playground.is_generation_running(), "background generation thread completed")
	var after_first: Dictionary = playground.get_published_snapshot()
	var first_hash := String(after_first.get("ecology_state_hash", ""))

	# (10) manual generation advances generation.
	_check(int(after_first.get("generation", -1)) == int(initial.get("generation", -1)) + 1,
		"manual generation advances the generation by exactly one")

	# (11) ecology hash changes after a valid generation.
	_check(first_hash != initial_hash, "ecology hash changes after a valid generation")
	_check(first_hash.length() == 64, "post-generation ecology hash stays valid")
	_check(
		String(workbench.get_workbench_snapshot().get("ecology_state_hash", "")) == first_hash,
		"published snapshot equals the completed Workbench snapshot"
	)

	# (12) phenotype presenter source hash matches the ecology hash.
	var contract: Dictionary = presentation.get_contract()
	_check(
		String(contract.get("source_ecology_hash", "")) == first_hash,
		"phenotype presenter source hash matches ecology hash"
	)
	_check(bool(contract.get("presentation_only", false)), "presentation contract is read-only")
	_check(int(contract.get("stem_instances", 0)) > 0, "presentation materialized 3D stems")
	_check(
		String(contract.get("placement_api", "")).contains("get_surface_point"),
		"plants placed through physical get_surface_point(direction)"
	)

	# (13) biome overlay toggle does not mutate the ecology hash.
	_check(playground.toggle_biome_overlay(), "biome overlay turns ON")
	_check(playground.is_biome_overlay_visible(), "biome overlay visibility observable")
	_check(
		String(playground.get_published_snapshot().get("ecology_state_hash", "")) == first_hash,
		"biome overlay toggle does not mutate ecology hash"
	)
	_check(not playground.toggle_biome_overlay(), "biome overlay turns OFF")

	# Second single-flight generation for stability + duration telemetry.
	_check(playground.request_generation(), "second manual generation accepted")
	var second_join := await _wait_generation_done(playground, 60000)
	_check(second_join, "second background generation completed")
	var after_second: Dictionary = playground.get_published_snapshot()
	_check(
		int(after_second.get("generation", -1)) == int(after_first.get("generation", -1)) + 1,
		"generations advance strictly one at a time"
	)
	_check(
		playground.get_completed_generations() == 2,
		"exactly one generation published per completed thread"
	)
	_check(
		playground.get_last_generation_duration_ms() >= 0.0,
		"last generation duration is measured"
	)
	_check(
		String(presentation.get_contract().get("source_ecology_hash", "")) ==
		String(after_second.get("ecology_state_hash", "")),
		"presentation republished after the completed generation"
	)

	# Presentation tracks render-origin shifts (streaming/recenter contract).
	if int(contract.get("stem_instances", 0)) > 0:
		var render_before: Vector3 = presentation.get_stem_render_position(0)
		var world_before: Vector3 = presentation.get_stem_world_position(0)
		var origin_before: Vector3 = earth.get_render_origin()
		earth.set_render_origin(origin_before + Vector3(1500.0, 0.0, 0.0))
		await process_frame
		await process_frame
		var render_after: Vector3 = presentation.get_stem_render_position(0)
		_check(
			absf((render_after - render_before).length() - 1500.0) < 1.0,
			"presentation tracks render-origin shifts"
		)
		_check(
			world_before.distance_to(earth.render_to_world(render_after)) < 0.01,
			"plant world position invariant under origin shift"
		)
		earth.set_render_origin(origin_before)
		await process_frame

	# HUD exposes the required minimum.
	var hud := playground.get_node_or_null("Play0HUD/Play0StatusHUD") as Label
	_check(hud != null, "PLAY0 HUD exists")
	if hud != null:
		var text := String(hud.text)
		for token in ["PLAY0.FINAL", "GROUND", "Altitude", "Biome", "FPS",
				"gen", "population", "IDLE", "hash", "BIOME"]:
			_check(text.contains(token), "HUD exposes %s" % token)
		playground.set_auto_evolution(true)
		_check(String(hud.text).contains("AUTO"), "HUD exposes AUTO state")
		playground.set_auto_evolution(false)
		_check(String(hud.text).contains("PAUSED"), "HUD exposes PAUSED state")

	# (17)(18)(19) authority contract.
	var authorities: Dictionary = playground.get_authorities()
	_check(bool(authorities.get("presentation_only", false)), "presentation_only == true")
	_check(not bool(authorities.get("network_authority", true)), "network_authority == false")
	_check(not bool(authorities.get("persistence_authority", true)), "persistence_authority == false")
	_check(
		not bool(authorities.get("renderer_write", true))
		and not bool(authorities.get("persistence_write", true))
		and not bool(authorities.get("network_replication_write", true)),
		"workbench fail-closed authorities inherited unchanged"
	)

	# LIVE status surface matches HUD reality.
	var status: Dictionary = playground.get_play0_status()
	_check(String(status.get("mode", "")) == "GROUND", "status mirrors live mode")
	_check(int(status.get("generation", -1)) == 2, "status mirrors live generation")

	_source_guard()
	playground.queue_free()
	await process_frame
	_finish()

func _wait_generation_done(playground, timeout_msec: int) -> bool:
	var started := Time.get_ticks_msec()
	while playground.is_generation_running() and Time.get_ticks_msec() - started < timeout_msec:
		await process_frame
	return not playground.is_generation_running()

func _source_guard() -> void:
	var playground_source := FileAccess.get_file_as_string(
		"res://scripts/labs/ecology/eco_evo7_play0_live_planet_playground.gd"
	).to_lower()
	var presentation_source := FileAccess.get_file_as_string(
		"res://scripts/labs/ecology/eco_evo7_play0_planet_presentation.gd"
	).to_lower()
	_check(
		playground_source.contains("eco_evo7_ls36_rule_workbench_v1.gd"),
		"PLAY0 consumes the accepted LS3.6 Workbench"
	)
	_check(
		playground_source.contains("eco_evo7_vis2_phenotype_render_adapter.gd"),
		"PLAY0 reuses the accepted VIS2 phenotype render adapter"
	)
	_check(
		playground_source.contains("spectator_controller.gd") and playground_source.contains("lunar_player.gd"),
		"PLAY0 reuses the accepted spectator and player actors"
	)
	_check(
		playground_source.contains("earth_humanoid")
		and not playground_source.contains("planetary_humanoid_controller.gd"),
		"PLAY0 activates earth_humanoid by profile, not by reimplementing a controller"
	)
	_check(
		playground_source.contains("create_trimesh_shape()"),
		"PLAY0 builds collision with create_trimesh_shape()"
	)
	_check(
		playground_source.contains("workbench.advance_generations(1)"),
		"evolution bridge advances the Workbench by exactly one generation"
	)
	for source_name in [playground_source, presentation_source]:
		_check(not source_name.contains("eco_evo7_ls33"), "no bypass into LS3.3 internals")
		_check(not source_name.contains("eco_evo7_ls34"), "no bypass into LS3.4 internals")
		_check(not source_name.contains("eco_evo7_ls35"), "no bypass into LS3.5 internals")
		_check(not source_name.contains("reproduce_bundle("), "no reproduction authority")
		_check(not source_name.contains("mutation_seed("), "no mutation authority")
		_check(not source_name.contains("dispersal_seed("), "no dispersal authority")
	_check(
		not presentation_source.contains("advance_generations"),
		"presentation owns no generation control path"
	)
	_check(
		not presentation_source.contains("fileaccess.open") and not presentation_source.contains("diraccess"),
		"presentation owns no persistence path"
	)
	_check(
		not presentation_source.contains("multiplayer"),
		"presentation owns no network path"
	)

func _start_watchdog(timeout_seconds: float) -> void:
	## Guarantees the engine quits even if the main coroutine aborts on a
	## runtime script error (an aborted coroutine never reaches quit()).
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline and not _finished:
		await process_frame
	if not _finished:
		push_error("ECO.EVO7 PLAY0 watchdog: acceptance did not finish in %ds" % int(timeout_seconds))
		print("ECO.EVO7 PLAY0 Live Planet Playground: FAIL (watchdog timeout)")
		quit(1)

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	_finished = true
	if failures.is_empty():
		print("ECO.EVO7 PLAY0 Live Planet Playground: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 PLAY0 FAIL: %s" % failure)
	print("ECO.EVO7 PLAY0 Live Planet Playground: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
