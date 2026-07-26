extends "res://scripts/app/lunar_app.gd"

const EarthWorldScript = preload(
	"res://scripts/world/earth/procedural_earth_world.gd"
)
const CelestialSystemScript = preload(
	"res://scripts/world/planetary/celestial_system.gd"
)
const EarthExplorerScript = preload(
	"res://scripts/actors/earth/earth_explorer.gd"
)
const PlanetaryOverlayScript = preload(
	"res://scripts/ui/planetary_overlay.gd"
)
const AtmosphereManagerScript = preload(
	"res://scripts/world/atmosphere/atmosphere_manager.gd"
)

var celestial_system
var earth_world
var earth_explorer
var planetary_overlay
var shared_space_mode: bool = false
var earth_initialized: bool = false
var earth_moon_distance_m: float = 384_400_000.0
var nearest_body_id: String = "moon"
var moon_sun: DirectionalLight3D
var atmosphere_manager
var atmosphere_initialized: bool = false


func _ready() -> void:
	super._ready()
	celestial_system = CelestialSystemScript.new()
	celestial_system.name = "CelestialSystem"
	add_child(celestial_system)
	if celestial_system.setup():
		earth_moon_distance_m = celestial_system.get_distance_between("earth", "moon")

	earth_world = EarthWorldScript.new()
	earth_world.name = "ProceduralEarthWorld"
	earth_world.visible = false
	earth_world.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(earth_world)

	earth_explorer = EarthExplorerScript.new()
	earth_explorer.name = "SharedSpaceSpectator"
	add_child(earth_explorer)
	earth_explorer.setup(earth_world, celestial_system, moon_world)

	atmosphere_manager = AtmosphereManagerScript.new()
	atmosphere_manager.name = "AtmosphereManager"
	add_child(atmosphere_manager)

	planetary_overlay = PlanetaryOverlayScript.new()
	planetary_overlay.name = "PlanetaryOverlay"
	add_child(planetary_overlay)
	planetary_overlay.setup()
	planetary_overlay.show_moon_mode(earth_moon_distance_m)
	moon_sun = moon_world.get_node_or_null("ProceduralSun") as DirectionalLight3D
	logger.info("application", "planetary_architecture_extension_ready", {
		"earth_moon_distance_m": earth_moon_distance_m,
		"moon_logic_modified": false,
		"shared_absolute_space": true,
		"earth_lazy_initialization": true,
	})


func _process(delta: float) -> void:
	if not shared_space_mode:
		super._process(delta)
		if planetary_overlay != null:
			planetary_overlay.show_moon_mode(earth_moon_distance_m)
		return
	if earth_world == null or earth_explorer == null:
		return

	var space_position: Vector3 = earth_explorer.get_world_position()
	var moon_local_position: Vector3 = celestial_system.to_body_local(
		space_position,
		"moon"
	)
	var earth_local_position: Vector3 = celestial_system.to_body_local(
		space_position,
		"earth"
	)

	# Both generators live in one absolute simulation frame. Each receives a
	# body-local position and rebases its render geometry around the same camera.
	moon_world.update_for_view(
		moon_local_position,
		moon_local_position,
		true,
		delta
	)
	earth_world.update_for_view(
		earth_local_position,
		earth_local_position,
		true,
		delta
	)
	if atmosphere_initialized:
		atmosphere_manager.update_for_observer(
			space_position,
			earth_explorer.get_camera(),
			delta
		)

	var new_nearest_body_id: String = celestial_system.get_nearest_body_id(space_position)
	if new_nearest_body_id != nearest_body_id:
		nearest_body_id = new_nearest_body_id
		logger.info("space", "nearest_body_changed", {
			"nearest_body_id": nearest_body_id,
			"space_position_m": [space_position.x, space_position.y, space_position.z],
		})
	_update_primary_body_lighting()

	if planetary_overlay != null:
		planetary_overlay.show_shared_space_mode(
			celestial_system,
			earth_world,
			moon_world,
			earth_explorer,
			nearest_body_id,
			earth_moon_distance_m,
			atmosphere_manager if atmosphere_initialized else null
		)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5 and shared_space_mode:
			get_viewport().set_input_as_handled()
			open_item_system_lab()
			return
		if event.physical_keycode == KEY_P:
			toggle_shared_space_mode()
			get_viewport().set_input_as_handled()
			return
		if shared_space_mode:
			if event.keycode == KEY_1:
				_teleport_to_earth_biome("forest")
			elif event.keycode == KEY_2:
				_teleport_to_earth_biome("grassland")
			elif event.keycode == KEY_3:
				_teleport_to_earth_biome("desert")
			elif event.keycode == KEY_4:
				_teleport_to_earth_biome("tundra")
			elif event.keycode == KEY_5:
				_teleport_to_earth_biome("alpine_snow")
			elif event.keycode == KEY_6:
				_teleport_to_body("moon")
			elif event.keycode == KEY_7:
				_teleport_to_body("earth")
			elif event.keycode == KEY_F4:
				earth_world.cycle_debug_view()
			elif event.keycode == KEY_F9:
				save_planetary_diagnostic_snapshot()
			elif event.physical_keycode == KEY_Y:
				earth_world.reload_rules()
			elif event.physical_keycode == KEY_G:
				_focus_other_body()
			else:
				return
			get_viewport().set_input_as_handled()
			return

	if shared_space_mode:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not mouse_captured:
				_set_mouse_capture(true)
				get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)


func toggle_shared_space_mode() -> void:
	if shared_space_mode:
		_leave_shared_space_mode()
	else:
		_enter_shared_space_mode()


func _enter_shared_space_mode() -> void:
	if not earth_initialized:
		earth_initialized = earth_world.setup(logger)
		if not earth_initialized:
			logger.error("earth", "shared_space_activation_failed", {})
			return
	if not atmosphere_initialized:
		var world_environment := moon_world.get_node_or_null("WorldEnvironment") as WorldEnvironment
		atmosphere_initialized = atmosphere_manager.setup(
			celestial_system,
			{"earth": earth_world, "moon": moon_world},
			world_environment,
			logger
		)
		if not atmosphere_initialized:
			logger.error("atmosphere", "atmosphere_manager_setup_failed", {})

	var initial_space_position: Vector3
	var initial_orientation := Basis.IDENTITY
	if spectator_enabled:
		initial_space_position = celestial_system.to_space(
			spectator.get_world_position(),
			"moon"
		)
		initial_orientation = spectator.global_transform.basis
		spectator.deactivate()
		spectator_enabled = false
	else:
		initial_space_position = celestial_system.to_space(
			player.get_world_position(),
			"moon"
		)
		initial_orientation = player.get_active_camera_world_transform().basis
		player.freeze_for_spectator()

	shared_space_mode = true
	moon_world.visible = true
	moon_world.process_mode = Node.PROCESS_MODE_INHERIT
	earth_world.visible = true
	earth_world.process_mode = Node.PROCESS_MODE_INHERIT
	celestial_system.set_proxy_visibility(false)
	earth_explorer.activate_at_space_position(
		initial_space_position,
		initial_orientation
	)
	nearest_body_id = celestial_system.get_nearest_body_id(initial_space_position)
	_update_primary_body_lighting()
	_set_menu_visible(false)
	_set_mouse_capture(true)
	logger.info("space", "shared_space_mode_entered", {
		"space_position_m": [
			initial_space_position.x,
			initial_space_position.y,
			initial_space_position.z,
		],
		"nearest_body_id": nearest_body_id,
		"earth_moon_distance_m": earth_moon_distance_m,
	})


func _leave_shared_space_mode() -> void:
	shared_space_mode = false
	if atmosphere_initialized:
		atmosphere_manager.deactivate()
	earth_explorer.deactivate()
	earth_world.set_primary_lighting_enabled(false)
	earth_world.visible = false
	earth_world.process_mode = Node.PROCESS_MODE_DISABLED
	moon_world.visible = true
	moon_world.process_mode = Node.PROCESS_MODE_INHERIT
	celestial_system.set_proxy_visibility(true)
	if moon_sun != null:
		moon_sun.visible = true

	var player_world_position: Vector3 = player.get_stored_world_position()
	if player_world_position.length_squared() > 1.0:
		moon_world.prepare_surface_region(player_world_position.normalized(), true)
		moon_world.set_render_origin(moon_world.get_surface_anchor())
	player.restore_from_spectator()
	_set_menu_visible(false)
	_set_mouse_capture(true)
	logger.info("space", "shared_space_mode_left", {})


func _teleport_to_earth_biome(biome_name: String) -> void:
	var direction: Vector3 = earth_world.find_biome_direction(biome_name)
	earth_explorer.teleport_to_body_surface("earth", direction, 450.0)
	nearest_body_id = "earth"
	_update_primary_body_lighting()
	logger.info("earth", "earth_biome_teleport", {
		"requested_biome": biome_name,
		"resolved_biome": earth_world.get_biome_name_at(direction),
	})


func _teleport_to_body(body_id: String) -> void:
	var direction: Vector3
	if body_id == "moon":
		direction = moon_world.get_random_spawn_direction()
	else:
		direction = earth_world.find_biome_direction("forest")
	earth_explorer.teleport_to_body_surface(body_id, direction, 1200.0)
	nearest_body_id = body_id
	_update_primary_body_lighting()
	logger.info("space", "body_surface_teleport", {
		"body_id": body_id,
		"altitude_m": 1200.0,
	})


func _focus_other_body() -> void:
	var target_body_id: String = "earth" if nearest_body_id == "moon" else "moon"
	earth_explorer.look_at_body(target_body_id)
	logger.info("space", "spectator_focus_body", {
		"target_body_id": target_body_id,
	})


func _update_primary_body_lighting() -> void:
	var earth_is_primary: bool = nearest_body_id == "earth"
	earth_world.set_primary_lighting_enabled(earth_is_primary)
	if moon_sun != null:
		moon_sun.visible = not earth_is_primary


func save_planetary_diagnostic_snapshot() -> String:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(DIAGNOSTIC_DIR)
	)
	var stamp: String = Time.get_datetime_string_from_system(false, false)
	stamp = stamp.replace(":", "-")
	var path: String = "%s/planetary_diagnostic_%s.json" % [DIAGNOSTIC_DIR, stamp]
	var space_position: Vector3 = earth_explorer.get_world_position()
	var payload: Dictionary = {
		"schema": "planet_simulator.diagnostic.v1",
		"created_at_utc": Time.get_datetime_string_from_system(true, true),
		"engine": Engine.get_version_info(),
		"shared_space_mode": shared_space_mode,
		"nearest_body_id": nearest_body_id,
		"space": celestial_system.get_space_snapshot(space_position),
		"celestial_system": celestial_system.create_snapshot(),
		"earth": earth_world.create_snapshot(),
		"atmosphere": (
			atmosphere_manager.create_snapshot()
			if atmosphere_initialized
			else {"initialized": false}
		),
		"moon_terrain_streaming": moon_world.get_terrain_streaming_snapshot(),
		"recent_logs": logger.get_recent_entries(),
		"log_path": logger.get_log_path(),
		"terrain_performance_log_path": logger.get_performance_log_path(),
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		last_diagnostic_path = "ERROR"
		logger.error("diagnostics", "planetary_snapshot_write_failed", {"path": path})
		return last_diagnostic_path
	file.store_string(JSON.stringify(payload, "	"))
	file.flush()
	last_diagnostic_path = path
	logger.info("diagnostics", "planetary_snapshot_saved", {"path": path})
	return path
