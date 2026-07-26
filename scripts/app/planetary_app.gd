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
var runtime_startup_mode: String = "moon"
var visible_body_ids: Array[String] = ["earth", "moon"]
var default_earth_biome: String = "forest"
var earth_only_mode: bool = false


func _ready() -> void:
	super._ready()
	var runtime_options: Dictionary = runtime_world_definition.get("options", {})
	runtime_startup_mode = String(runtime_options.get("startup_mode", "moon"))
	default_earth_biome = String(runtime_options.get("default_biome", "forest"))
	visible_body_ids.clear()
	var configured_bodies = runtime_options.get("visible_bodies", ["earth", "moon"])
	if configured_bodies is Array:
		for body_id_value in configured_bodies:
			visible_body_ids.append(String(body_id_value))
	if visible_body_ids.is_empty():
		visible_body_ids = ["earth", "moon"]
	earth_only_mode = visible_body_ids.size() == 1 and visible_body_ids.has("earth")
	celestial_system = CelestialSystemScript.new()
	celestial_system.name = "CelestialSystem"
	add_child(celestial_system)
	var all_body_ids: Array[String] = []
	if celestial_system.setup(all_body_ids, simulation_clock, runtime_instance_id):
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
		"hierarchical_reference_frames": true,
		"earth_lazy_initialization": true,
		"runtime_startup_mode": runtime_startup_mode,
		"visible_body_ids": visible_body_ids,
	})
	call_deferred("_apply_runtime_startup_mode")


func _process(delta: float) -> void:
	if not shared_space_mode:
		super._process(delta)
		if planetary_overlay != null:
			planetary_overlay.show_moon_mode(earth_moon_distance_m)
		return
	if earth_world == null or earth_explorer == null:
		return

	var space_position: Vector3 = earth_explorer.get_world_position()
	var observer_frame_id: String = earth_explorer.get_reference_frame_id()
	earth_moon_distance_m = celestial_system.get_distance_between("earth", "moon")
	var moon_local_position: Vector3 = celestial_system.to_body_local(
		space_position,
		"moon"
	)
	var earth_local_position: Vector3 = celestial_system.to_body_local(
		space_position,
		"earth"
	)

	# Terrain is generated in stable body-fixed coordinates. Only the body root
	# is rotated into the observer frame; the generated coordinates are never
	# rewritten because the planet moved or rotated in the canonical system.
	moon_world.basis = celestial_system.get_relative_basis(
		celestial_system.get_body_fixed_frame_id("moon"),
		observer_frame_id
	)
	earth_world.basis = celestial_system.get_relative_basis(
		celestial_system.get_body_fixed_frame_id("earth"),
		observer_frame_id
	)
	if visible_body_ids.has("moon"):
		moon_world.update_for_view(
			moon_local_position,
			moon_local_position,
			true,
			delta
		)
	if visible_body_ids.has("earth"):
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
			delta,
			observer_frame_id
		)

	var new_nearest_body_id: String = _get_nearest_visible_body_id(space_position)
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
			atmosphere_manager if atmosphere_initialized else null,
			visible_body_ids
		)


func _unhandled_input(event: InputEvent) -> void:
	if simulator_app != null:
		return
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
	if earth_only_mode:
		if not shared_space_mode:
			_enter_shared_space_mode()
		return
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

	var initial_moon_local_position: Vector3
	var initial_orientation := Basis.IDENTITY
	if spectator_enabled:
		initial_moon_local_position = spectator.get_world_position()
		initial_orientation = spectator.global_transform.basis
		spectator.deactivate()
		spectator_enabled = false
	else:
		initial_moon_local_position = player.get_world_position()
		initial_orientation = player.get_active_camera_world_transform().basis
		player.freeze_for_spectator()
	var initial_spatial_ref: Dictionary = celestial_system.create_spatial_ref(
		celestial_system.get_body_fixed_frame_id("moon"),
		initial_moon_local_position,
		initial_orientation
	)
	var initial_space_position: Vector3 = celestial_system.to_space(
		initial_moon_local_position,
		"moon"
	)

	shared_space_mode = true
	moon_world.visible = true
	moon_world.process_mode = Node.PROCESS_MODE_INHERIT
	earth_world.visible = true
	earth_world.process_mode = Node.PROCESS_MODE_INHERIT
	celestial_system.set_proxy_visibility(false)
	earth_explorer.activate_at_spatial_ref(initial_spatial_ref)
	nearest_body_id = _get_nearest_visible_body_id(initial_space_position)
	_update_primary_body_lighting()
	_set_menu_visible(false)
	_set_mouse_capture(true)
	_apply_visible_body_policy()
	logger.info("space", "shared_space_mode_entered", {
		"space_position_m": [
			initial_space_position.x,
			initial_space_position.y,
			initial_space_position.z,
		],
		"nearest_body_id": nearest_body_id,
		"earth_moon_distance_m": earth_moon_distance_m,
		"visible_body_ids": visible_body_ids,
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
	moon_world.basis = Basis.IDENTITY
	earth_world.basis = Basis.IDENTITY
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


func teleport_player_to_spectator() -> void:
	if not shared_space_mode:
		super.teleport_player_to_spectator()
		return
	if earth_explorer == null or celestial_system == null:
		return
	var observer_space_position: Vector3 = earth_explorer.get_world_position()
	var observer_body_id: String = _get_nearest_visible_body_id(
		observer_space_position
	)
	# The current controllable player belongs to the lunar runtime. Until a
	# planet-independent player is introduced, F2 can safely land it only on
	# the Moon.
	if observer_body_id != "moon":
		last_action_result = (
			"Игрок пока может телепортироваться только к спектатору у Луны"
		)
		return
	var moon_local_position: Vector3 = celestial_system.to_body_local(
		observer_space_position,
		"moon"
	)
	if moon_local_position.length_squared() < 1.0:
		return
	var target_direction: Vector3 = moon_local_position.normalized()
	_leave_shared_space_mode()
	moon_world.prepare_surface_region(target_direction, true)
	moon_world.set_render_origin(moon_world.get_surface_anchor())
	player.teleport_to_surface(target_direction)
	player.activate_after_spawn()
	_set_mouse_capture(true)
	if hud != null:
		hud.set_menu_visible(false)
	_sync_player_entity()
	zone_manager.update_observer(player.get_world_position(), false)
	last_action_result = "Игрок перемещён к позиции спектатора"
	logger.info("gameplay", "player_teleported_from_shared_space_spectator", {
		"observer_space_position": [
			observer_space_position.x,
			observer_space_position.y,
			observer_space_position.z,
		],
		"player_world_position": _vector_to_array(player.get_world_position()),
	})


func _command_teleport_from_spectator(
	_arguments: Array[String]
) -> Dictionary:
	if not shared_space_mode:
		return super._command_teleport_from_spectator(_arguments)
	teleport_player_to_spectator()
	if shared_space_mode:
		return {
			"success": false,
			"output": last_action_result,
		}
	return {
		"success": true,
		"output": "Персонаж перемещён к позиции спектатора",
	}


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
	if not visible_body_ids.has(body_id):
		logger.warning("space", "hidden_body_teleport_rejected", {"body_id": body_id})
		return
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


func _get_nearest_visible_body_id(space_position: Vector3) -> String:
	var nearest_id: String = ""
	var nearest_distance: float = INF
	for body_id in visible_body_ids:
		var distance_to_surface: float = absf(
			celestial_system.get_surface_distance(body_id, space_position)
		)
		if distance_to_surface < nearest_distance:
			nearest_distance = distance_to_surface
			nearest_id = body_id
	return nearest_id


func _apply_runtime_startup_mode() -> void:
	match runtime_startup_mode:
		"earth":
			_enter_shared_space_mode()
			if shared_space_mode:
				_teleport_to_earth_biome(default_earth_biome)
				_apply_visible_body_policy()
		"shared_space":
			_enter_shared_space_mode()
			_apply_visible_body_policy()
		_:
			_apply_visible_body_policy()


func _apply_visible_body_policy() -> void:
	var show_moon: bool = visible_body_ids.has("moon")
	var show_earth: bool = visible_body_ids.has("earth")
	if shared_space_mode:
		moon_world.visible = show_moon
		moon_world.process_mode = (
			Node.PROCESS_MODE_INHERIT if show_moon else Node.PROCESS_MODE_DISABLED
		)
		earth_world.visible = show_earth
		earth_world.process_mode = (
			Node.PROCESS_MODE_INHERIT if show_earth else Node.PROCESS_MODE_DISABLED
		)
	else:
		moon_world.visible = show_moon
		moon_world.process_mode = (
			Node.PROCESS_MODE_INHERIT if show_moon else Node.PROCESS_MODE_DISABLED
		)
		earth_world.visible = false
		earth_world.process_mode = Node.PROCESS_MODE_DISABLED
	if celestial_system != null:
		celestial_system.set_proxy_visibility(
			not shared_space_mode and show_earth and show_moon
		)
	if moon_sun != null and not show_moon:
		moon_sun.visible = false


func register_runtime_commands(registry, owner_id: String) -> void:
	if not earth_only_mode:
		super.register_runtime_commands(registry, owner_id)
	else:
		_register_earth_only_common_commands(registry, owner_id)

	if not earth_only_mode:
		_register_runtime_command(registry, owner_id, {
			"id": "space.mode.toggle",
			"description": "Переключить поверхность Луны и общее пространство.",
			"usage": "space.mode.toggle",
			"category": "space",
		}, Callable(self, "_command_space_mode_toggle"))
	_register_runtime_command(registry, owner_id, {
		"id": "space.teleport.body",
		"description": "Перейти к поверхности видимого небесного тела.",
		"usage": "space.teleport.body <earth|moon>",
		"category": "space",
	}, Callable(self, "_command_space_teleport_body"))
	if not earth_only_mode:
		_register_runtime_command(registry, owner_id, {
			"id": "space.focus.other_body",
			"description": "Направить камеру на другое видимое тело.",
			"usage": "space.focus.other_body",
			"category": "space",
		}, Callable(self, "_command_space_focus_other"))
	_register_runtime_command(registry, owner_id, {
		"id": "space.frame.current",
		"description": "Показать систему отсчёта наблюдателя.",
		"usage": "space.frame.current",
		"category": "space",
	}, Callable(self, "_command_space_frame_current"))
	_register_runtime_command(registry, owner_id, {
		"id": "space.frame.set",
		"description": "Сменить систему отсчёта без изменения физического состояния.",
		"usage": "space.frame.set <system|earth.inertial|earth.fixed|moon.inertial|moon.fixed>",
		"category": "space",
	}, Callable(self, "_command_space_frame_set"))
	_register_runtime_command(registry, owner_id, {
		"id": "earth.teleport.biome",
		"description": "Перейти к одному из контрольных биомов Земли.",
		"usage": "earth.teleport.biome <forest|grassland|desert|tundra|alpine_snow>",
		"category": "earth",
	}, Callable(self, "_command_earth_teleport_biome"))
	_register_runtime_command(registry, owner_id, {
		"id": "earth.debug.cycle",
		"description": "Переключить final/biome/elevation/ecology отображение Земли.",
		"usage": "earth.debug.cycle",
		"category": "earth",
	}, Callable(self, "_command_earth_debug_cycle"))
	_register_runtime_command(registry, owner_id, {
		"id": "earth.rules.reload",
		"description": "Перечитать procedural rules Земли из JSON.",
		"usage": "earth.rules.reload",
		"category": "earth",
	}, Callable(self, "_command_earth_rules_reload"))


func _register_earth_only_common_commands(registry, owner_id: String) -> void:
	_register_runtime_command(registry, owner_id, {
		"id": "diagnostics.save",
		"description": "Сохранить диагностический JSON текущего мира.",
		"usage": "diagnostics.save",
		"category": "diagnostics",
	}, Callable(self, "_command_diagnostics_save"))
	if simulator_app == null:
		_register_runtime_command(registry, owner_id, {
			"id": "display.fullscreen.toggle",
			"description": "Переключить полноэкранный режим.",
			"usage": "display.fullscreen.toggle",
			"category": "display",
		}, Callable(self, "_command_fullscreen_toggle"))
		_register_runtime_command(registry, owner_id, {
			"id": "display.resolution.cycle",
			"description": "Переключить оконное разрешение.",
			"usage": "display.resolution.cycle",
			"category": "display",
		}, Callable(self, "_command_resolution_cycle"))


func register_runtime_tests(registry, owner_id: String) -> void:
	if not earth_only_mode:
		super.register_runtime_tests(registry, owner_id)
	registry.register_test({
		"id": "world.planetary.boot",
		"description": "Planetary runtime создал Землю, систему координат и атмосферный менеджер.",
		"category": "world",
	}, Callable(self, "_planetary_runtime_boot_test"), owner_id)
	registry.register_test({
		"id": "world.planetary.reference_frames",
		"description": "Earth/Moon runtime использует иерархический frame graph.",
		"category": "world",
	}, Callable(self, "_planetary_reference_frame_test"), owner_id)
	registry.register_test({
		"id": "world.planetary.visibility_policy",
		"description": "Видимость тел соответствует world definition.",
		"category": "world",
	}, Callable(self, "_planetary_visibility_test"), owner_id)


func prepare_for_unload() -> void:
	if atmosphere_manager != null:
		atmosphere_manager.deactivate()
	if earth_explorer != null:
		earth_explorer.deactivate()
	super.prepare_for_unload()


func create_runtime_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.create_runtime_snapshot()
	snapshot["schema"] = "planet_simulator.planetary_world_runtime.v2"
	snapshot["runtime_startup_mode"] = runtime_startup_mode
	snapshot["visible_body_ids"] = visible_body_ids.duplicate()
	snapshot["shared_space_mode"] = shared_space_mode
	snapshot["nearest_body_id"] = nearest_body_id
	snapshot["earth_initialized"] = earth_initialized
	snapshot["atmosphere_initialized"] = atmosphere_initialized
	snapshot["observer_spatial_ref"] = (
		earth_explorer.get_spatial_ref() if earth_explorer != null and shared_space_mode else {}
	)
	snapshot["celestial_system"] = (
		celestial_system.create_snapshot() if celestial_system != null else {}
	)
	snapshot["earth"] = earth_world.create_snapshot() if earth_initialized else {
		"initialized": false,
	}
	return snapshot


func save_runtime_diagnostic_snapshot() -> String:
	if shared_space_mode and earth_initialized:
		return save_planetary_diagnostic_snapshot()
	return save_diagnostic_snapshot()


func _command_space_mode_toggle(_arguments: Array[String]) -> Dictionary:
	if earth_only_mode:
		return {
			"success": false,
			"output": "В мире earth доступна только Земля. Используйте world.load earth_moon.",
		}
	toggle_shared_space_mode()
	return {
		"success": true,
		"output": "Режим: %s" % (
			"общее пространство" if shared_space_mode else "поверхность Луны"
		),
	}


func _command_space_teleport_body(arguments: Array[String]) -> Dictionary:
	if arguments.is_empty():
		return {"success": false, "output": "Использование: space.teleport.body <earth|moon>"}
	var body_id: String = arguments[0].to_lower()
	if not visible_body_ids.has(body_id):
		return {"success": false, "output": "Тело скрыто в текущем мире: %s" % body_id}
	if not shared_space_mode:
		_enter_shared_space_mode()
	if not shared_space_mode:
		return {"success": false, "output": "Не удалось включить общее пространство"}
	_teleport_to_body(body_id)
	return {"success": true, "output": "Переход к телу: %s" % body_id}


func _command_space_focus_other(_arguments: Array[String]) -> Dictionary:
	if visible_body_ids.size() < 2:
		return {"success": false, "output": "В текущем мире нет второго видимого тела"}
	if not shared_space_mode:
		return {"success": false, "output": "Сначала включите общее пространство"}
	_focus_other_body()
	return {"success": true, "output": "Камера направлена на другое тело"}


func _command_space_frame_current(_arguments: Array[String]) -> Dictionary:
	if earth_explorer == null or not shared_space_mode:
		return {"success": false, "output": "Сначала включите общее пространство"}
	return {
		"success": true,
		"output": "Frame: %s" % earth_explorer.get_reference_frame_id(),
		"spatial_ref": earth_explorer.get_spatial_ref(),
	}


func _command_space_frame_set(arguments: Array[String]) -> Dictionary:
	if arguments.is_empty():
		return {"success": false, "output": "Использование: space.frame.set <system|earth.inertial|earth.fixed|moon.inertial|moon.fixed>"}
	if not shared_space_mode:
		_enter_shared_space_mode()
	if not shared_space_mode:
		return {"success": false, "output": "Не удалось включить общее пространство"}
	var target_frame_id: String = _resolve_frame_alias(arguments[0])
	if target_frame_id.is_empty() or not earth_explorer.set_reference_frame(target_frame_id, true):
		return {"success": false, "output": "Неизвестная или недоступная система отсчёта: %s" % arguments[0]}
	return _command_space_frame_current([])


func _command_earth_teleport_biome(arguments: Array[String]) -> Dictionary:
	if not visible_body_ids.has("earth"):
		return {"success": false, "output": "Земля отсутствует в текущем мире"}
	if arguments.is_empty():
		return {
			"success": false,
			"output": "Использование: earth.teleport.biome <forest|grassland|desert|tundra|alpine_snow>",
		}
	if not shared_space_mode:
		_enter_shared_space_mode()
	if not shared_space_mode:
		return {"success": false, "output": "Не удалось инициализировать Землю"}
	var biome_name: String = arguments[0].to_lower()
	var direction: Vector3 = earth_world.find_biome_direction(biome_name)
	if direction.length_squared() < 0.5:
		return {"success": false, "output": "Биом не найден: %s" % biome_name}
	_teleport_to_earth_biome(biome_name)
	return {"success": true, "output": "Биом Земли: %s" % biome_name}


func _command_earth_debug_cycle(_arguments: Array[String]) -> Dictionary:
	if not earth_initialized:
		return {"success": false, "output": "Земля ещё не инициализирована"}
	earth_world.cycle_debug_view()
	return {"success": true, "output": "Debug-режим Земли переключён"}


func _command_earth_rules_reload(_arguments: Array[String]) -> Dictionary:
	if not earth_initialized:
		return {"success": false, "output": "Земля ещё не инициализирована"}
	var reloaded: bool = earth_world.reload_rules()
	return {
		"success": reloaded,
		"output": "Правила Земли перечитаны" if reloaded else "Не удалось перечитать правила Земли",
	}


func _planetary_runtime_boot_test() -> Dictionary:
	var body_ids: Array[String] = []
	if celestial_system != null:
		body_ids = celestial_system.get_body_ids()
	var body_contract_valid: bool = body_ids.has("earth")
	if not earth_only_mode:
		body_contract_valid = body_contract_valid and body_ids.has("moon")
	var passed: bool = (
		celestial_system != null
		and body_contract_valid
		and earth_world != null
		and earth_explorer != null
		and atmosphere_manager != null
	)
	return {
		"success": passed,
		"passed": passed,
		"output": "PASS: planetary runtime boot" if passed else "FAIL: planetary runtime boot",
	}


func _planetary_reference_frame_test() -> Dictionary:
	if celestial_system == null:
		return {"success": false, "passed": false, "output": "FAIL: celestial system missing"}
	var root_frame_id: String = celestial_system.get_root_frame_id()
	var earth_fixed: String = celestial_system.get_body_fixed_frame_id("earth")
	var moon_fixed: String = celestial_system.get_body_fixed_frame_id("moon")
	var sample: Vector3 = Vector3(1200.0, 6371000.0, -420.0)
	var root_point: Vector3 = celestial_system.transform_point(sample, earth_fixed, root_frame_id)
	var roundtrip: Vector3 = celestial_system.transform_point(root_point, root_frame_id, earth_fixed)
	var passed: bool = (
		celestial_system.has_frame(root_frame_id)
		and celestial_system.has_frame(earth_fixed)
		and celestial_system.has_frame(moon_fixed)
		and sample.distance_to(roundtrip) < 0.001
	)
	return {
		"success": passed,
		"passed": passed,
		"output": "PASS: hierarchical reference frames" if passed else "FAIL: frame graph roundtrip",
	}


func _resolve_frame_alias(value: String) -> String:
	match value.strip_edges().to_lower():
		"system", "root", "sol", "sol.barycentric":
			return celestial_system.get_root_frame_id()
		"earth.inertial", "body/earth/inertial":
			return celestial_system.get_body_inertial_frame_id("earth")
		"earth.fixed", "body/earth/fixed":
			return celestial_system.get_body_fixed_frame_id("earth")
		"moon.inertial", "body/moon/inertial":
			return celestial_system.get_body_inertial_frame_id("moon")
		"moon.fixed", "body/moon/fixed":
			return celestial_system.get_body_fixed_frame_id("moon")
		_:
			return ""


func _planetary_visibility_test() -> Dictionary:
	var moon_matches: bool = moon_world.visible == visible_body_ids.has("moon")
	var earth_matches: bool = (
		earth_world.visible == (shared_space_mode and visible_body_ids.has("earth"))
	)
	var passed: bool = moon_matches and earth_matches
	return {
		"success": passed,
		"passed": passed,
		"output": (
			"PASS: visibility policy"
			if passed
			else "FAIL: moon=%s earth=%s expected=%s" % [
				moon_world.visible,
				earth_world.visible,
				visible_body_ids,
			]
		),
	}
