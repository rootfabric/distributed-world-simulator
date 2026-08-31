extends Node3D

## ECO.EVO7 PLAY0.FINAL — Live Planet Playground.
##
## Combines accepted building blocks into one interactive planetary experience:
##   PLAY0.1  real ProceduralEarthWorld + free spectator flight (existing
##            SpectatorController, render-origin mechanism, streaming/recenter).
##   PLAY0.2  walkable surface: the CURRENT streamed Earth local surface mesh is
##            converted with create_trimesh_shape() into a StaticBody3D that the
##            existing lunar_player + earth_humanoid planetary controller walks on.
##   PLAY0.3  live ecology in 3D: the accepted LS3.6 Rule Workbench is the only
##            ecology authority; VIS2 phenotype render adapter descriptors are
##            presented through MultiMeshes placed on the physical patch cells.
##
## Evolution bridge (PLAY0-local, NOT a PAR1 backend): at most ONE dedicated
## Thread runs workbench.advance_generations(1) at a time. The main/render
## thread keeps running; only immutable completed snapshots are ever published
## to presentation; partial generation state is never exposed; a second
## simultaneous generation request is rejected fail-closed.
##
## The whole runtime is presentation-only: no persistence writes, no network
## authority, no ecology-authority replacement.

const REVISION := "ECO.EVO7-PLAY0.FINAL.R3-VIS4.4"
const TITLE := "ECO EVO7 — PLAY0 Live Planet Playground"

const EarthWorldScript = preload(
	"res://scripts/world/earth/procedural_earth_world.gd"
)
const LunarPlayerScript = preload(
	"res://scripts/actors/player/lunar_player.gd"
)
const SpectatorScript = preload(
	"res://scripts/actors/spectator/spectator_controller.gd"
)
const WorkbenchScript = preload(
	"res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd"
)
const Vis2AdapterScript = preload(
	"res://scripts/labs/ecology/eco_evo7_vis2_phenotype_render_adapter.gd"
)
const Vis4AdapterScript = preload(
	"res://scripts/labs/ecology/eco_evo7_vis4_morphology_render_adapter.gd"
)
const PresentationScript = preload(
	"res://scripts/labs/ecology/eco_evo7_play0_planet_presentation.gd"
)
const MorphologyInspectorModel = preload(
	"res://scripts/labs/ecology/eco_evo7_vis4_7_morphology_inspector_model.gd"
)
const LoggerScript = preload(
	"res://scripts/diagnostics/lunar_logger.gd"
)

const MODE_GROUND := "GROUND"
const MODE_SPECTATOR := "SPECTATOR"
const HUD_UPDATE_INTERVAL := 0.25
const PRESENTATION_ONLY := true
const NETWORK_AUTHORITY := false
const PERSISTENCE_AUTHORITY := false

@export var auto_initialize: bool = true

var ready_success := false
var mode: String = MODE_GROUND
var auto_evolution := false
var mouse_captured := true
var help_visible := false

var logger
var earth_world = null
var player = null
var spectator = null
var workbench = null

# Mirrors the already-shipped Earth MVP spectator-body presentation:
# spectator detaches from the player, while a simple local body figure remains
# at the exact canonical player position. The figure is presentation-only.
var _spectator_body_visual: MeshInstance3D = null
var _spectator_body_world_position := Vector3.ZERO
var _spectator_body_basis := Basis.IDENTITY
var vis2_adapter = null
var vis4_adapter = null
var presentation = null

# PLAY0-local single-flight generation bridge state.
# The worker MUST be a non-Node RefCounted: thread entry points on Node
# methods hit thread-affinity checks in this engine build, and Thread.start
# invokes the callable with zero arguments.
class GenerationWorker:
	extends RefCounted
	var workbench = null

	func run_one() -> Dictionary:
		# Exactly one Workbench mutation per thread run, validated snapshot out.
		return workbench.advance_generations(1)

var _gen_worker: GenerationWorker = null
var _gen_thread: Thread = null
var _gen_in_flight := false
var _gen_started_msec := 0
var _generation_rejections := 0
var _completed_generations := 0
var _last_generation_ms := -1.0
var _published_snapshot: Dictionary = {}
var _published_ecology: Dictionary = {}
var _published_descriptors: Dictionary = {}
var _published_morphology_descriptors: Dictionary = {}
var _published_reconstruction: Dictionary = {}

# Terrain collision state.
var _terrain_body: StaticBody3D = null
var _terrain_shape: CollisionShape3D = null
var _collision_refresh_count := 0

# HUD state.
var hud_layer: CanvasLayer
var hud_label: Label
var help_panel: PanelContainer
var morphology_inspector_panel: PanelContainer
var morphology_inspector_label: Label
var morphology_inspector_visible := false
var _morphology_inspector_index := -1
var _morphology_inspector_record_id := ""
var _morphology_inspector_state: Dictionary = {}
var _hud_accumulator := 0.0


func _ready() -> void:
	name = "EcoEvo7Play0LivePlanetPlayground"
	_ensure_input_actions()
	if auto_initialize:
		initialize_runtime()
	if OS.get_environment("ECO_PLAY0_AUTOCAP") == "1":
		call_deferred("_autocap")
	if OS.get_environment("ECO_PLAY0_AUTOSOAK") == "1":
		call_deferred("_autosk")


func initialize_runtime() -> bool:
	if ready_success:
		return true
	logger = LoggerScript.new()
	logger.name = "Play0Logger"
	add_child(logger)
	logger.setup(false)

	# PLAY0.1/0.2 foundation: the real ProceduralEarthWorld (radius, terrain
	# pipeline and render-origin mechanism are the accepted ones).
	earth_world = EarthWorldScript.new()
	earth_world.name = "ProceduralEarthWorld"
	add_child(earth_world)
	if not earth_world.setup(logger):
		logger.error("play0", "earth_world_setup_failed", {})
		return false
	earth_world.set_primary_lighting_enabled(true)
	# Any subsequent local-region rebuild must refresh the trimesh collision.
	if not earth_world.earth_rebuilt.is_connected(_on_earth_rebuilt):
		earth_world.earth_rebuilt.connect(_on_earth_rebuilt)
	_build_terrain_collision()

	# PLAY0.3 authority: accepted LS3.6 Rule Workbench over the same world.
	workbench = WorkbenchScript.new()
	if not workbench.setup(earth_world):
		logger.error("play0", "workbench_setup_failed", {})
		return false
	vis2_adapter = Vis2AdapterScript.new()
	vis4_adapter = Vis4AdapterScript.new()
	# Generation zero is published synchronously (no thread needed yet).
	_publish_completed_snapshot(workbench.get_workbench_snapshot(), false)
	if _published_descriptors.is_empty():
		logger.error("play0", "initial_presentation_source_failed", {})
		return false

	# Presentation over the accepted founder fallback. Generation > 0 switches
	# atomically to exact VIS4.1 + VIS4.3 -> PH5.
	presentation = PresentationScript.new()
	presentation.name = "Play0PlanetPresentation"
	add_child(presentation)
	if not presentation.setup(earth_world, workbench.get_patch()):
		logger.error("play0", "presentation_setup_failed", {})
		return false
	if not presentation.apply_snapshot(_published_descriptors, workbench.get_classification()):
		logger.error("play0", "initial_presentation_apply_failed", {})
		return false

	# Spawn ground mode on the physical ecology patch so plants and terrain
	# coincide for the player.
	var patch_center: Vector3 = presentation.get_patch_center_direction()
	earth_world.prepare_surface_region(patch_center, true)
	earth_world.set_render_origin(earth_world.get_surface_anchor())
	_build_terrain_collision()
	_apply_local_daylight(patch_center)

	player = LunarPlayerScript.new()
	player.name = "Play0Player"
	add_child(player)
	player.setup(earth_world, logger, "earth_humanoid")
	player.teleport_to_surface(patch_center)
	player.activate_after_spawn()
	presentation.set_view_world_position(player.get_world_position())

	spectator = SpectatorScript.new()
	spectator.name = "Play0Spectator"
	add_child(spectator)
	spectator.setup(earth_world)

	ready_success = true
	_set_mouse_capture(true)
	_build_hud()
	_refresh_hud_text()
	DisplayServer.window_set_title("%s (%s)" % [TITLE, REVISION])
	logger.info("play0", "runtime_ready", {
		"revision": REVISION,
		"mode": mode,
		"patch_center": [patch_center.x, patch_center.y, patch_center.z],
		"generation": int(_published_snapshot.get("generation", -1)),
		"ecology_state_hash": String(_published_snapshot.get("ecology_state_hash", "")),
	})
	print("ECO.EVO7 PLAY0 READY revision=%s mode=%s" % [REVISION, mode])
	return true


func _process(delta: float) -> void:
	if not ready_success:
		return
	_poll_generation_thread()
	if auto_evolution and not _gen_in_flight:
		request_generation()
	_update_view(delta)
	if mode == MODE_SPECTATOR:
		_update_spectator_body_visual()
	if presentation != null:
		presentation.refresh_render_transform(false)
	_hud_accumulator += delta
	if _hud_accumulator >= HUD_UPDATE_INTERVAL:
		_hud_accumulator = 0.0
		_refresh_hud_text()


func _exit_tree() -> void:
	# Never abandon a running generation thread: join it before teardown.
	if _gen_thread != null and _gen_in_flight:
		if _gen_thread.is_alive():
			_gen_thread.wait_to_finish()
		_gen_in_flight = false
		_gen_thread = null


func _apply_local_daylight(patch_center: Vector3) -> void:
	## PLAY0-local presentation lighting: the accepted Earth sun is authored for
	## the canonical spawn hemisphere; the ecology patch sits elsewhere on the
	## globe, so aim the existing DirectionalLight3D at this patch (28 deg from
	## zenith) and add mild ambient plus a procedural sky. Pure presentation:
	## no ecology, terrain or physics identity is affected.
	if earth_world == null or earth_world.earth_light == null:
		return
	var up := patch_center.normalized()
	var tilt_axis: Vector3 = Vector3.UP.cross(up)
	if tilt_axis.length_squared() < 0.000001:
		tilt_axis = Vector3.RIGHT.cross(up)
	tilt_axis = tilt_axis.normalized()
	var sun_direction := up.rotated(tilt_axis, deg_to_rad(28.0)).normalized()
	earth_world.earth_light.look_at_from_position(
		sun_direction * 1000000.0,
		Vector3.ZERO,
		up
	)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.22, 0.42, 0.78)
	sky_material.sky_horizon_color = Color(0.62, 0.72, 0.84)
	sky_material.ground_bottom_color = Color(0.12, 0.13, 0.15)
	sky_material.ground_horizon_color = Color(0.58, 0.66, 0.76)
	sky.sky_material = sky_material
	environment.sky = sky
	# Align the sky sphere's zenith with the local planetary up so the
	# procedural horizon matches the patch horizon at this latitude.
	var pole_axis: Vector3 = Vector3.UP.cross(up)
	if pole_axis.length_squared() < 0.000001:
		pole_axis = Vector3.RIGHT.cross(up)
	environment.sky_rotation = Basis(
		pole_axis.normalized(),
		Vector3.UP.angle_to(up)
	).get_euler()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.58, 0.65, 0.75)
	environment.ambient_light_sky_contribution = 0.0
	environment.ambient_light_energy = 0.85
	var world_environment := WorldEnvironment.new()
	world_environment.name = "Play0WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)


func _update_view(delta: float) -> void:
	if earth_world == null:
		return
	var view_position := Vector3.ZERO
	if mode == MODE_SPECTATOR and spectator != null:
		view_position = spectator.get_world_position()
		earth_world.update_for_view(view_position, view_position, true, delta)
	elif player != null:
		view_position = player.get_world_position()
		earth_world.update_for_view(
			view_position,
			earth_world.get_render_origin(),
			false,
			delta
		)
	if presentation != null and view_position.length_squared() > 1.0:
		presentation.set_view_world_position(view_position)


# ------------------------------------------------------------------
# PLAY0.2 — terrain collision from the CURRENT streamed local surface
# ------------------------------------------------------------------

func _build_terrain_collision() -> void:
	if earth_world == null or earth_world.local_surface == null:
		return
	if _terrain_body == null:
		_terrain_body = StaticBody3D.new()
		_terrain_body.name = "EarthTerrainCollision"
		_terrain_shape = CollisionShape3D.new()
		_terrain_shape.name = "EarthTerrainTrimesh"
		_terrain_body.add_child(_terrain_shape)
		earth_world.local_surface.add_child(_terrain_body)
	var surface_mesh: Mesh = earth_world.local_surface.mesh
	_terrain_shape.shape = (
		surface_mesh.create_trimesh_shape() if surface_mesh != null else null
	)
	_collision_refresh_count += 1


func _on_earth_rebuilt(_summary: Dictionary) -> void:
	# Earth local-region rebuild happened: the streamed mesh changed, so the
	# physical collision must be rebuilt from the new mesh immediately.
	_build_terrain_collision()


func has_terrain_collision() -> bool:
	return (
		_terrain_body != null
		and _terrain_shape != null
		and _terrain_shape.shape != null
	)


func get_collision_refresh_count() -> int:
	return _collision_refresh_count


# ------------------------------------------------------------------
# Player / spectator handoff.
#
# This intentionally mirrors scripts/app/earth_mvp_app.gd semantics:
# - F3 detaches a spectator camera from the player body;
# - the body remains at its canonical world position and is represented by the
#   same simple CapsuleMesh-style spectator body figure used by the Earth MVP;
# - F2 returns control to THAT body, never to the spectator camera position.
# ------------------------------------------------------------------

func enter_spectator() -> bool:
	if not ready_success or mode != MODE_GROUND:
		return false
	_enter_spectator()
	_report_mode_change()
	return true


func return_to_player() -> bool:
	if not ready_success or mode != MODE_SPECTATOR:
		return false
	_enter_ground_from_spectator()
	_report_mode_change()
	return true


func toggle_mode() -> String:
	# Compatibility helper for automated soak drivers. Human hotkeys are
	# deliberately asymmetric: F3 enters spectator, F2 returns to the body.
	if mode == MODE_GROUND:
		enter_spectator()
	else:
		return_to_player()
	return mode


func toggle_player_camera() -> String:
	if not ready_success or player == null or mode != MODE_GROUND:
		return player.get_camera_mode() if player != null else ""
	var camera_mode: String = player.toggle_camera_mode()
	_refresh_hud_text()
	return camera_mode


func _report_mode_change() -> void:
	if logger != null:
		logger.info("play0", "mode_changed", {
			"mode": mode,
			"player_body_world_position": [
				_spectator_body_world_position.x,
				_spectator_body_world_position.y,
				_spectator_body_world_position.z,
			],
		})
	_refresh_hud_text()


func _enter_spectator() -> void:
	var camera_transform: Transform3D = player.get_active_camera_world_transform()
	_spectator_body_world_position = player.get_world_position()
	_spectator_body_basis = player.global_transform.basis.orthonormalized()

	# Reuse the accepted LunarPlayer freeze path for input/physics ownership.
	# It stores the canonical player world position and disables body simulation.
	player.freeze_for_spectator()

	# Earth MVP already uses a simple capsule as the detached local body visual.
	# Keep the same shape/name and the same semantic boundary here instead of
	# inventing another character-presentation contract.
	_ensure_spectator_body_visual()
	spectator.activate(camera_transform)
	# Mode must be SPECTATOR before the visual update: the updater derives
	# visibility from the current mode, and the detached figure must be
	# visible in the same frame the spectator detaches.
	mode = MODE_SPECTATOR
	_update_spectator_body_visual()


func _enter_ground_from_spectator() -> void:
	var body_position := _spectator_body_world_position
	if body_position.length_squared() <= 1.0:
		body_position = player.get_stored_world_position()
	var direction: Vector3 = (
		body_position.normalized()
		if body_position.length_squared() > 1.0
		else earth_world.surface_center_direction
	)

	spectator.deactivate()

	# Rebuild/recenter under the PLAYER BODY, not under the spectator. This is
	# the important portability contract shared with the existing Earth MVP:
	# spectator is presentation-only and cannot teleport authoritative gameplay.
	earth_world.prepare_surface_region(direction, true)
	earth_world.set_render_origin(earth_world.get_surface_anchor())
	_build_terrain_collision()

	player.restore_from_spectator()
	# Explicitly re-project the preserved canonical body position after the
	# render-origin change. No teleport_to_surface(spectator_direction) here.
	player.set_world_position(body_position)
	player.align_body_to_up(direction)
	player.reset_physics_interpolation()

	if _spectator_body_visual != null:
		_spectator_body_visual.visible = false
	mode = MODE_GROUND


func _ensure_spectator_body_visual() -> void:
	if _spectator_body_visual != null and is_instance_valid(_spectator_body_visual):
		return
	_spectator_body_visual = MeshInstance3D.new()
	_spectator_body_visual.name = "LocalPlayerBodySpectatorVisual"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	_spectator_body_visual.mesh = capsule
	_spectator_body_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spectator_body_visual.visible = false
	add_child(_spectator_body_visual)


func _update_spectator_body_visual() -> void:
	if (
		_spectator_body_visual == null
		or not is_instance_valid(_spectator_body_visual)
		or earth_world == null
	):
		return
	_spectator_body_visual.visible = mode == MODE_SPECTATOR
	if mode != MODE_SPECTATOR or _spectator_body_world_position.length_squared() <= 1.0:
		return
	var up := _spectator_body_world_position.normalized()
	var visual_center_world := _spectator_body_world_position + up * 0.90
	_spectator_body_visual.position = earth_world.world_to_render(visual_center_world)
	_spectator_body_visual.basis = _spectator_body_basis


func is_spectator_body_visible() -> bool:
	return (
		_spectator_body_visual != null
		and is_instance_valid(_spectator_body_visual)
		and _spectator_body_visual.visible
	)


func get_spectator_body_world_position() -> Vector3:
	return _spectator_body_world_position


func is_earth_humanoid_active() -> bool:
	return (
		ready_success
		and player != null
		and mode == MODE_GROUND
		and player.control_enabled
		and player.get_controller_id() == "earth_humanoid"
		and not spectator.active
	)


# ------------------------------------------------------------------
# PLAY0.3 — single-flight live evolution bridge (PLAY0-local only)
# ------------------------------------------------------------------

func request_generation() -> bool:
	## Starts exactly one background generation. A second simultaneous request
	## is rejected fail-closed while one is in flight.
	if not ready_success or workbench == null:
		return false
	if _gen_in_flight:
		_generation_rejections += 1
		return false
	_gen_in_flight = true
	_gen_started_msec = Time.get_ticks_msec()
	_gen_worker = GenerationWorker.new()
	_gen_worker.workbench = workbench
	_gen_thread = Thread.new()
	_gen_thread.start(_gen_worker.run_one)
	_refresh_hud_text()
	return true


func _poll_generation_thread() -> void:
	if not _gen_in_flight or _gen_thread == null:
		return
	if _gen_thread.is_alive():
		return
	var result: Dictionary = _gen_thread.wait_to_finish()
	_gen_thread = null
	_gen_in_flight = false
	if result.is_empty():
		# Fail closed: the last completed snapshot stays the presentation
		# source; no partial generation state is ever exposed.
		if logger != null:
			logger.error("play0", "generation_failed", {})
		_refresh_hud_text()
		return
	_publish_completed_snapshot(result, true)


func _publish_completed_snapshot(workbench_snapshot: Dictionary, measured: bool) -> void:
	## Atomically publishes only a complete presentation source. Generation zero
	## uses the legacy founder fallback; generation > 0 must carry exact VIS4.1
	## descriptors + VIS4.3 reconstruction evidence and materialize through PH5.
	if workbench_snapshot.is_empty() or workbench == null:
		return
	var ecology_snapshot: Dictionary = workbench.get_ecology_snapshot()
	var classification: Dictionary = workbench.get_classification()
	var descriptors: Dictionary = vis2_adapter.build(ecology_snapshot)
	if descriptors.is_empty():
		if logger != null:
			logger.error("play0", "presentation_descriptor_build_failed", {
				"generation": int(ecology_snapshot.get("generation", -1)),
			})
		return

	var generation := int(ecology_snapshot.get("generation", -1))
	var morphology_descriptors: Dictionary = {}
	var reconstruction: Dictionary = {}
	if generation > 0:
		var morphology: Dictionary = workbench.get_morphology_evidence()
		reconstruction = workbench.get_graph_reconstruction_evidence()
		if (
			morphology.is_empty()
			or not workbench.validate_morphology_evidence(morphology)
			or reconstruction.is_empty()
			or not workbench.validate_graph_reconstruction_evidence(reconstruction)
		):
			if logger != null:
				logger.error("play0", "vis4_source_evidence_incomplete", {
					"generation": generation,
				})
			return
		morphology_descriptors = vis4_adapter.build(ecology_snapshot, morphology)
		if morphology_descriptors.is_empty():
			if logger != null:
				logger.error("play0", "vis4_descriptor_build_failed", {
					"generation": generation,
				})
			return

	# Presentation is committed first. If PH5 rejects any source record, all
	# published state below stays on the previous completed generation.
	if presentation != null and presentation.initialized:
		if not presentation.apply_snapshot(
			descriptors,
			classification,
			morphology_descriptors,
			reconstruction
		):
			if logger != null:
				logger.error("play0", "presentation_atomic_publish_rejected", {
					"generation": generation,
				})
			return

	_published_snapshot = workbench_snapshot.duplicate(true)
	_published_ecology = ecology_snapshot.duplicate(true)
	_published_descriptors = descriptors.duplicate(true)
	_published_morphology_descriptors = morphology_descriptors.duplicate(true)
	_published_reconstruction = reconstruction.duplicate(true)
	if morphology_inspector_visible:
		_refresh_morphology_inspector(true)
	if measured:
		_completed_generations += 1
		_last_generation_ms = float(Time.get_ticks_msec() - _gen_started_msec)
	_refresh_hud_text()


func is_generation_running() -> bool:
	return _gen_in_flight


func get_generation_rejections() -> int:
	return _generation_rejections


func get_completed_generations() -> int:
	return _completed_generations


func get_last_generation_duration_ms() -> float:
	return _last_generation_ms


func set_auto_evolution(value: bool) -> bool:
	if not ready_success:
		return false
	auto_evolution = value
	_refresh_hud_text()
	return true


func is_auto_evolution() -> bool:
	return auto_evolution


func toggle_biome_overlay() -> bool:
	if not ready_success or presentation == null:
		return false
	var state: bool = presentation.toggle_biome_overlay()
	_refresh_hud_text()
	return state


func is_biome_overlay_visible() -> bool:
	return presentation != null and presentation.biome_overlay_visible


# ------------------------------------------------------------------
# Read-only observability surface (HUD + automated acceptance)
# ------------------------------------------------------------------

func get_play0_revision() -> String:
	return REVISION


func get_mode() -> String:
	return mode


func get_earth_world() -> Node3D:
	return earth_world


func get_player() -> CharacterBody3D:
	return player


func get_spectator() -> Node3D:
	return spectator


func get_workbench() -> RefCounted:
	return workbench


func get_presentation() -> Node3D:
	return presentation


func get_published_snapshot() -> Dictionary:
	## Immutable copy of the last COMPLETED generation snapshot (never partial).
	return _published_snapshot.duplicate(true)


func get_published_descriptors() -> Dictionary:
	return _published_descriptors.duplicate(true)


func get_published_morphology_descriptors() -> Dictionary:
	return _published_morphology_descriptors.duplicate(true)


func get_published_reconstruction_evidence() -> Dictionary:
	return _published_reconstruction.duplicate(true)


func is_morphology_inspector_visible() -> bool:
	return morphology_inspector_visible


func get_morphology_inspector_state() -> Dictionary:
	return _morphology_inspector_state.duplicate(true)


func get_morphology_inspector_text() -> String:
	return "" if morphology_inspector_label == null else morphology_inspector_label.text


func get_morphology_inspector_selected_index() -> int:
	return _morphology_inspector_index


func select_morphology_inspector_index(index: int) -> bool:
	if not _can_inspect_morphology():
		return false
	var descriptors: Array = Array(_published_morphology_descriptors.get("descriptors", []))
	if index < 0 or index >= descriptors.size() or not descriptors[index] is Dictionary:
		return false
	var state: Dictionary = _build_morphology_inspector_state(index)
	if state.is_empty():
		return false
	_morphology_inspector_index = index
	_morphology_inspector_record_id = String(state.get("record_id", ""))
	_morphology_inspector_state = state
	if morphology_inspector_label != null:
		morphology_inspector_label.text = MorphologyInspectorModel.format_text(state)
	return true


func set_morphology_inspector_visible(value: bool) -> bool:
	if value:
		if not _can_inspect_morphology():
			morphology_inspector_visible = true
			if morphology_inspector_panel != null:
				morphology_inspector_panel.visible = true
			if morphology_inspector_label != null:
				morphology_inspector_label.text = "VIS4.7 MORPHOLOGY INSPECTOR\nUnavailable until a completed generation > 0 has PH5 morphology evidence."
			_morphology_inspector_index = -1
			_morphology_inspector_record_id = ""
			_morphology_inspector_state = {}
			_refresh_hud_text()
			return true
		morphology_inspector_visible = true
		if morphology_inspector_panel != null:
			morphology_inspector_panel.visible = true
		if not _refresh_morphology_inspector(false):
			_select_nearest_morphology_inspector_record()
	else:
		morphology_inspector_visible = false
		if morphology_inspector_panel != null:
			morphology_inspector_panel.visible = false
	_refresh_hud_text()
	return morphology_inspector_visible


func toggle_morphology_inspector() -> bool:
	return set_morphology_inspector_visible(not morphology_inspector_visible)


func _can_inspect_morphology() -> bool:
	if presentation == null:
		return false
	var generation := int(_published_snapshot.get("generation", -1))
	var ecology_hash := String(_published_snapshot.get("ecology_state_hash", ""))
	var presentation_contract: Dictionary = presentation.get_contract()
	return (
		generation > 0
		and ecology_hash.length() == 64
		and not _published_morphology_descriptors.is_empty()
		and int(_published_morphology_descriptors.get("generation", -2)) == generation
		and String(_published_morphology_descriptors.get("source_ecology_state_hash", "")) == ecology_hash
		and bool(presentation_contract.get("ph5_active", false))
	)


func _build_morphology_inspector_state(index: int) -> Dictionary:
	if not _can_inspect_morphology():
		return {}
	var descriptors: Array = Array(_published_morphology_descriptors.get("descriptors", []))
	if index < 0 or index >= descriptors.size() or not descriptors[index] is Dictionary:
		return {}
	var descriptor: Dictionary = Dictionary(descriptors[index])
	var render_identity: Dictionary = presentation.get_ph5_record_identity(index)
	var grid_appearance: Dictionary = presentation.get_ph5_record_grid_appearance(index)
	return MorphologyInspectorModel.build(
		int(_published_snapshot.get("generation", -1)),
		String(_published_snapshot.get("ecology_state_hash", "")),
		descriptor,
		render_identity,
		grid_appearance
	)


func _refresh_morphology_inspector(preserve_record: bool) -> bool:
	if not morphology_inspector_visible or not _can_inspect_morphology():
		return false
	var descriptors: Array = Array(_published_morphology_descriptors.get("descriptors", []))
	if preserve_record and not _morphology_inspector_record_id.is_empty():
		for index in range(descriptors.size()):
			if (
				descriptors[index] is Dictionary
				and String(Dictionary(descriptors[index]).get("record_id", "")) == _morphology_inspector_record_id
			):
				return select_morphology_inspector_index(index)
		return _select_nearest_morphology_inspector_record()
	if _morphology_inspector_index >= 0 and _morphology_inspector_index < descriptors.size():
		return select_morphology_inspector_index(_morphology_inspector_index)
	return _select_nearest_morphology_inspector_record()


func _select_nearest_morphology_inspector_record() -> bool:
	if not _can_inspect_morphology():
		return false
	var descriptors: Array = Array(_published_morphology_descriptors.get("descriptors", []))
	var view_world: Vector3 = _active_view_world_position()
	var best_index := -1
	var best_distance := INF
	for index in range(descriptors.size()):
		if not descriptors[index] is Dictionary:
			continue
		if not presentation.is_ph5_record_individual_materialized(index):
			continue
		var visual_world: Vector3 = presentation.get_ph5_record_visual_world_position(index)
		var distance := visual_world.distance_squared_to(view_world)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	if best_index < 0 and not descriptors.is_empty():
		best_index = 0
	return select_morphology_inspector_index(best_index)


func _active_view_world_position() -> Vector3:
	if mode == MODE_SPECTATOR and spectator != null:
		return spectator.get_world_position()
	if player != null:
		return player.get_world_position()
	return Vector3.ZERO


func get_authorities() -> Dictionary:
	var snapshot_authorities: Dictionary = _published_snapshot.get("authorities", {})
	return {
		"presentation_only": PRESENTATION_ONLY,
		"network_authority": NETWORK_AUTHORITY,
		"persistence_authority": PERSISTENCE_AUTHORITY,
		"renderer_write": bool(snapshot_authorities.get("renderer_write", true)),
		"persistence_write": bool(snapshot_authorities.get("persistence_write", true)),
		"network_replication_write": bool(
			snapshot_authorities.get("network_replication_write", true)
		),
		"shadow_only": bool(_published_snapshot.get("shadow_only", false)),
	}


func get_play0_status() -> Dictionary:
	var view_position: Vector3 = (
		spectator.get_world_position()
		if mode == MODE_SPECTATOR and spectator != null
		else (player.get_world_position() if player != null else Vector3.ZERO)
	)
	var view_direction: Vector3 = (
		view_position.normalized() if view_position.length_squared() > 1.0 else Vector3.UP
	)
	var presentation_contract: Dictionary = presentation.get_contract() if presentation != null else {}
	return {
		"revision": REVISION,
		"mode": mode,
		"ready": ready_success,
		"altitude_m": earth_world.get_altitude(view_position) if earth_world != null else 0.0,
		"biome": earth_world.get_biome_name_at(view_direction) if earth_world != null else "unknown",
		"fps": Engine.get_frames_per_second(),
		"generation": int(_published_snapshot.get("generation", -1)),
		"population": int(_published_ecology.get("record_count", 0)),
		"ecology_state_hash": String(_published_snapshot.get("ecology_state_hash", "")),
		"auto": auto_evolution,
		"running": _gen_in_flight,
		"last_generation_ms": _last_generation_ms,
		"completed_generations": _completed_generations,
		"rejected_requests": _generation_rejections,
		"biome_overlay": is_biome_overlay_visible(),
		"collision_refresh_count": _collision_refresh_count,
		"mouse_captured": mouse_captured,
		"player_camera_mode": player.get_camera_mode() if player != null else "",
		"spectator_body_visible": is_spectator_body_visible(),
		"ph5_active": bool(presentation_contract.get("ph5_active", false)),
		"ph5": Dictionary(presentation_contract.get("ph5", {})).duplicate(true),
		"morphology_inspector_visible": morphology_inspector_visible,
		"morphology_inspector_selected_index": _morphology_inspector_index,
		"morphology_inspector_record_id": _morphology_inspector_record_id,
		"morphology_inspector_hash": String(_morphology_inspector_state.get("inspector_hash", "")),
	}


# ------------------------------------------------------------------
# Input
# ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F3:
				enter_spectator()
				get_viewport().set_input_as_handled()
			KEY_F2:
				return_to_player()
				get_viewport().set_input_as_handled()
			KEY_F5:
				toggle_player_camera()
				get_viewport().set_input_as_handled()
			KEY_F6:
				toggle_morphology_inspector()
				get_viewport().set_input_as_handled()
			KEY_P:
				set_auto_evolution(not auto_evolution)
				get_viewport().set_input_as_handled()
			KEY_N:
				request_generation()
				get_viewport().set_input_as_handled()
			KEY_B:
				toggle_biome_overlay()
				get_viewport().set_input_as_handled()
			KEY_F1:
				_set_help_visible(not help_visible)
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				_set_mouse_capture(not mouse_captured)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not mouse_captured:
			_set_mouse_capture(true)
			get_viewport().set_input_as_handled()


func _set_mouse_capture(captured: bool) -> void:
	mouse_captured = captured
	Input.mouse_mode = (
		Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	)


func _set_help_visible(value: bool) -> void:
	help_visible = value
	if help_panel != null:
		help_panel.visible = value


func _ensure_input_actions() -> void:
	for binding in [
		["move_forward", KEY_W], ["move_back", KEY_S],
		["move_left", KEY_A], ["move_right", KEY_D],
		["jump", KEY_SPACE], ["move_up", KEY_SPACE], ["move_down", KEY_CTRL],
		["boost", KEY_SHIFT], ["roll_left", KEY_E], ["roll_right", KEY_Q],
		["level_horizon", KEY_H],
	]:
		var action: StringName = StringName(binding[0])
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var has_key := false
		for existing in InputMap.action_get_events(action):
			if existing is InputEventKey and existing.physical_keycode == int(binding[1]):
				has_key = true
		if not has_key:
			var event := InputEventKey.new()
			event.physical_keycode = int(binding[1])
			InputMap.action_add_event(action, event)


# ------------------------------------------------------------------
# HUD
# ------------------------------------------------------------------

func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "Play0HUD"
	add_child(hud_layer)

	hud_label = Label.new()
	hud_label.name = "Play0StatusHUD"
	hud_label.position = Vector2(16, 14)
	hud_label.size = Vector2(860, 140)
	hud_label.add_theme_font_size_override("font_size", 16)
	hud_layer.add_child(hud_label)

	help_panel = PanelContainer.new()
	help_panel.name = "Play0HelpPanel"
	help_panel.position = Vector2(16, 170)
	help_panel.visible = false
	var help_label := Label.new()
	help_label.name = "Play0HelpText"
	help_label.text = "\n".join(PackedStringArray([
		"PLAY0.FINAL controls",
		"WASD        move / spectator flight",
		"Shift       run / spectator boost",
		"Space       jump / spectator up",
		"Ctrl        spectator down",
		"Mouse       look        Wheel   spectator speed",
		"Q / E       spectator roll      H   level horizon",
		"F3          enter SPECTATOR",
		"F2          return to PLAYER BODY at its preserved position",
		"F5          first-person / third-person character camera",
		"P           live ecology AUTO / PAUSE",
		"N           advance exactly one generation",
		"B           biome overlay ON / OFF",
		"F6          morphology inspector for nearest live PH5 plant",
		"F1          this help           Esc release/capture mouse",
	]))
	help_label.add_theme_font_size_override("font_size", 15)
	help_panel.add_child(help_label)
	hud_layer.add_child(help_panel)

	morphology_inspector_panel = PanelContainer.new()
	morphology_inspector_panel.name = "VIS47MorphologyInspectorPanel"
	morphology_inspector_panel.position = Vector2(16, 335)
	morphology_inspector_panel.size = Vector2(940, 610)
	morphology_inspector_panel.visible = false
	morphology_inspector_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	morphology_inspector_label = Label.new()
	morphology_inspector_label.name = "VIS47MorphologyInspectorText"
	morphology_inspector_label.custom_minimum_size = Vector2(920, 590)
	morphology_inspector_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	morphology_inspector_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	morphology_inspector_label.add_theme_font_size_override("font_size", 14)
	morphology_inspector_panel.add_child(morphology_inspector_label)
	hud_layer.add_child(morphology_inspector_panel)


func _refresh_hud_text() -> void:
	if hud_label == null:
		return
	var status := get_play0_status()
	var hash_value := String(status.get("ecology_state_hash", ""))
	var last_ms: float = float(status.get("last_generation_ms", -1.0))
	hud_label.text = "\n".join(PackedStringArray([
		"%s — %s" % [TITLE, REVISION],
		"Mode: %s    Altitude: %.1f m    Biome: %s    FPS: %d" % [
			String(status.get("mode", "?")),
			float(status.get("altitude_m", 0.0)),
			String(status.get("biome", "?")),
			int(status.get("fps", 0)),
		],
		"Ecology: gen %d    population %d    %s    %s    last gen %.1f ms    hash %s…" % [
			int(status.get("generation", -1)),
			int(status.get("population", 0)),
			"AUTO" if bool(status.get("auto", false)) else "PAUSED",
			"RUNNING" if bool(status.get("running", false)) else "IDLE",
			last_ms,
			hash_value.substr(0, 16),
		],
		"Overlay: BIOME %s    plants %d    completed %d    rejected %d    collision refreshes %d    %s" % [
			"ON" if bool(status.get("biome_overlay", false)) else "OFF",
			int(status.get("population", 0)),
			int(status.get("completed_generations", 0)),
			int(status.get("rejected_requests", 0)),
			int(status.get("collision_refresh_count", 0)),
			"mouse captured" if bool(status.get("mouse_captured", true)) else "mouse free (Esc)",
		],
		"Inspector: %s    selected: %s    F6 toggle" % [
			"ON" if morphology_inspector_visible else "OFF",
			_morphology_inspector_record_id if not _morphology_inspector_record_id.is_empty() else "<none>",
		],
	]))


# ------------------------------------------------------------------
# Automated graphical acceptance drivers (env-gated, PLAY0-local)
# ------------------------------------------------------------------

var _autocap_failures: Array[String] = []


func _autocap() -> void:
	## Scripted windowed pass over manual acceptance A–E with screenshots.
	if not ready_success:
		print("ECO.EVO7 PLAY0 AUTOCAP: FAIL init")
		get_tree().quit(1)
		return
	var shot_dir := _autocap_directory()
	await _settle_physics_frames(45)
	_check(_condition(player.is_on_floor()), "A: player stands on Earth surface at spawn")
	_check(
		_condition(absf(earth_world.get_altitude(player.get_world_position())) < 8.0),
		"A: spawn altitude near zero (no fall-through)"
	)
	await _capture("01_ground_spawn", shot_dir)

	Input.action_press("move_forward")
	await _settle_physics_frames(50)
	Input.action_release("move_forward")
	Input.action_press("jump")
	await _settle_physics_frames(6)
	Input.action_release("jump")
	await _settle_physics_frames(90)
	_check(_condition(player.is_on_floor()), "A: walk+jump keeps player grounded")
	await _capture("02_ground_walk", shot_dir)

	toggle_mode()
	await _settle_frames(8)
	_check(_condition(mode == MODE_SPECTATOR), "B: F3 enters spectator over the planet")
	await _capture("03_spectator_low", shot_dir)

	Input.action_press("boost")
	Input.action_press("move_up")
	await _settle_frames(110)
	Input.action_release("move_up")
	Input.action_press("move_forward")
	await _settle_frames(130)
	Input.action_release("move_forward")
	Input.action_release("boost")
	var spectator_altitude: float = earth_world.get_altitude(spectator.get_world_position())
	_check(_condition(spectator_altitude > 2000.0), "B: spectator climbed several km (%.0f m)" % spectator_altitude)
	await _capture("04_spectator_high", shot_dir)

	toggle_mode()
	await _settle_physics_frames(120)
	_check(_condition(mode == MODE_GROUND), "C: return restores control to preserved player body")
	_check(_condition(player.is_on_floor()), "C: player stands on rebuilt body region")
	_check(
		_condition(absf(earth_world.get_altitude(player.get_world_position())) < 10.0),
		"C: restored player altitude near zero (collision refreshed)"
	)
	await _capture("05_returned_player_body", shot_dir)

	var before_generation := int(get_published_snapshot().get("generation", -1))
	_check(_condition(request_generation()), "D: manual generation accepted")
	var join_ok := await _wait_generation_done(36000)
	_check(_condition(join_ok), "D: background generation completed")
	var after_snapshot := get_published_snapshot()
	_check(
		_condition(int(after_snapshot.get("generation", -1)) == before_generation + 1),
		"D: generation advanced by exactly one"
	)
	await _capture("06_ecology_generation_%d" % int(after_snapshot.get("generation", -1)), shot_dir)

	toggle_biome_overlay()
	await _settle_frames(4)
	_check(_condition(is_biome_overlay_visible()), "D: biome overlay turns ON")
	await _capture("07_biome_overlay", shot_dir)
	toggle_biome_overlay()
	_check(_condition(not is_biome_overlay_visible()), "D: biome overlay turns OFF")

	set_auto_evolution(true)
	await _settle_frames(600)
	set_auto_evolution(false)
	_check(_condition(get_completed_generations() >= 2), "E: AUTO evolved while interactive")
	_check(
		_condition(String(get_published_snapshot().get("ecology_state_hash", "")).length() == 64),
		"E: ecology state stays valid under AUTO"
	)
	await _capture("08_auto_evolution", shot_dir)

	var fps := Engine.get_frames_per_second()
	if _autocap_failures.is_empty():
		print("ECO.EVO7 PLAY0 AUTOCAP: PASS shots=%s gen=%d fps=%d last_gen_ms=%.1f" % [
			shot_dir, int(get_published_snapshot().get("generation", -1)), fps,
			get_last_generation_duration_ms(),
		])
		get_tree().quit(0)
		return
	for failure in _autocap_failures:
		push_error("ECO.EVO7 PLAY0 AUTOCAP FAIL: %s" % failure)
	print("ECO.EVO7 PLAY0 AUTOCAP: FAIL (%d failures)" % _autocap_failures.size())
	get_tree().quit(1)


func _autosk() -> void:
	## Env-gated soak: >= 10 minutes of mixed GROUND/SPECTATOR/evolution cycles
	## with invariant checks; never asserts from a partial generation.
	var soak_seconds := 600.0
	var env_seconds := float(OS.get_environment("ECO_PLAY0_AUTOSOAK_SECONDS"))
	if env_seconds > 60.0:
		soak_seconds = env_seconds
	var started_msec := Time.get_ticks_msec()
	var cycles := 0
	var next_report := 0.0
	var max_ground_altitude := -INF
	var min_ground_altitude := INF
	while float(Time.get_ticks_msec() - started_msec) / 1000.0 < soak_seconds:
		cycles += 1
		var elapsed := float(Time.get_ticks_msec() - started_msec) / 1000.0
		if elapsed >= next_report:
			next_report = elapsed + 30.0
			print("ECO.EVO7 PLAY0 SOAK t=%.0fs cycle=%d mode=%s gen=%d fps=%d alt=%.1fm" % [
				elapsed, cycles, mode,
				int(get_published_snapshot().get("generation", -1)),
				Engine.get_frames_per_second(),
				float(get_play0_status().get("altitude_m", 0.0)),
			])
		if mode == MODE_GROUND:
			Input.action_press("move_forward")
			Input.action_press("boost")
			await _settle_physics_frames(40)
			Input.action_release("move_forward")
			Input.action_release("boost")
			var altitude: float = earth_world.get_altitude(player.get_world_position())
			max_ground_altitude = maxf(max_ground_altitude, altitude)
			min_ground_altitude = minf(min_ground_altitude, altitude)
			if absf(altitude) > 60.0:
				print("ECO.EVO7 PLAY0 SOAK: FAIL ground altitude %.1f at cycle %d" % [altitude, cycles])
				get_tree().quit(1)
				return
			toggle_mode()
			await _settle_frames(5)
			Input.action_press("boost")
			Input.action_press("move_forward")
			await _settle_frames(90)
			Input.action_release("move_forward")
			Input.action_release("boost")
			toggle_mode()
			await _settle_physics_frames(100)
		else:
			toggle_mode()
			await _settle_frames(5)
		if cycles % 2 == 0:
			set_auto_evolution(true)
			await _settle_frames(240)
			set_auto_evolution(false)
		else:
			request_generation()
			var join_ok := await _wait_generation_done(36000)
			if not join_ok:
				print("ECO.EVO7 PLAY0 SOAK: FAIL generation did not complete at cycle %d" % cycles)
				get_tree().quit(1)
				return
		var hash_value := String(get_published_snapshot().get("ecology_state_hash", ""))
		if hash_value.length() != 64:
			print("ECO.EVO7 PLAY0 SOAK: FAIL ecology hash corrupted at cycle %d" % cycles)
			get_tree().quit(1)
			return
		var presentation_hash := String(
			presentation.get_contract().get("source_ecology_hash", "")
		)
		if presentation_hash != hash_value:
			print("ECO.EVO7 PLAY0 SOAK: FAIL presentation drifted from ecology at cycle %d" % cycles)
			get_tree().quit(1)
			return
	var total_seconds := float(Time.get_ticks_msec() - started_msec) / 1000.0
	print("ECO.EVO7 PLAY0 SOAK: PASS %.0fs cycles=%d gen=%d alt_range=[%.1f, %.1f] fps=%d" % [
		total_seconds, cycles, int(get_published_snapshot().get("generation", -1)),
		min_ground_altitude, max_ground_altitude, Engine.get_frames_per_second(),
	])
	get_tree().quit(0)


func _autocap_directory() -> String:
	var directory := "res://artifacts/play0_autocap_%d" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	return directory


func _capture(shot_name: String, directory: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [directory, shot_name]
	image.save_png(ProjectSettings.globalize_path(path))
	print("ECO.EVO7 PLAY0 AUTOCAP shot %s" % path)


func _settle_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _settle_physics_frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame


func _wait_generation_done(timeout_msec: int) -> bool:
	var started := Time.get_ticks_msec()
	while _gen_in_flight and Time.get_ticks_msec() - started < timeout_msec:
		await get_tree().process_frame
	return not _gen_in_flight


func _check(condition: bool, label: String) -> void:
	if not condition:
		_autocap_failures.append(label)


func _condition(value: bool) -> bool:
	return value
