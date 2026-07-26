extends Node3D

const MoonWorldScript = preload("res://scripts/world/moon_world.gd")
const LunarPlayerScript = preload("res://scripts/actors/player/lunar_player.gd")
const SpectatorScript = preload("res://scripts/actors/spectator/spectator_controller.gd")
const HudScript = preload("res://scripts/ui/lunar_hud.gd")
const LunarZoneManagerScript = preload(
	"res://scripts/world/zones/lunar_zone_manager.gd"
)
const EntityRegistryScript = preload(
	"res://scripts/simulation/entities/entity_registry.gd"
)
const EntityRecordScript = preload(
	"res://scripts/simulation/entities/entity_record.gd"
)
const LunarLoggerScript = preload(
	"res://scripts/diagnostics/lunar_logger.gd"
)
const WorldRepositoryScript = preload(
	"res://scripts/persistence/lunar_world_repository.gd"
)
const WorldInteractorScript = preload(
	"res://scripts/interaction/world_interactor.gd"
)

const PROJECT_VERSION: String = "15.4.1"
const BUILD_ID: String = "planetary-items-and-interaction"
const PLAYER_ENTITY_ID: String = "player/local-astronaut"
const MINI_TEST_ENTITY_ID: String = "test/chunk-migration-probe"
const DISPLAY_SETTINGS_PATH: String = "user://display_settings.cfg"
const DIAGNOSTIC_DIR: String = "user://diagnostics"
const ITEM_SYSTEM_LAB_SCENE: String = "res://scenes/items/item_system_lab.tscn"
const WINDOWED_RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3440, 1440),
]

var moon_world
var player
var spectator
var hud
var zone_manager
var entity_registry
var logger
var persistence
var world_interactor

var spectator_enabled: bool = false
var mouse_captured: bool = true
var fullscreen_enabled: bool = false
var resolution_index: int = 2
var last_mini_test_result: String = "Не запускался"
var last_persistence_test_result: String = "Не запускался"
var last_controller_test_result: String = "Не запускался"
var last_terrain_streaming_test_result: String = "Не запускался"
var last_diagnostic_path: String = "-"
var last_action_result: String = "-"
var clear_confirmation_deadline_msec: int = 0


func _ready() -> void:
	get_tree().auto_accept_quit = false
	_ensure_input_actions()
	_load_display_settings()
	_apply_display_settings()

	logger = LunarLoggerScript.new()
	logger.name = "LunarLogger"
	add_child(logger)
	logger.setup(false)
	logger.info("application", "startup", {
		"project_version": PROJECT_VERSION,
		"build_id": BUILD_ID,
		"engine": Engine.get_version_info(),
		"display_mode": get_display_mode_name(),
		"resolution": get_display_resolution_name(),
	})

	moon_world = MoonWorldScript.new()
	moon_world.name = "MoonWorld"
	add_child(moon_world)
	moon_world.setup(logger)
	moon_world.terrain_streaming_test_completed.connect(
		_on_terrain_streaming_test_completed
	)

	zone_manager = LunarZoneManagerScript.new()
	zone_manager.name = "LunarZoneManager"
	add_child(zone_manager)
	zone_manager.setup(moon_world)
	zone_manager.partition_window_changed.connect(_on_partition_window_changed)

	entity_registry = EntityRegistryScript.new()
	entity_registry.name = "EntityRegistry"
	add_child(entity_registry)
	entity_registry.setup(zone_manager, logger)

	player = LunarPlayerScript.new()
	player.name = "LunarPlayer"
	add_child(player)
	player.setup(moon_world, logger)
	moon_world.register_streaming_actor(player)
	player.controller_changed.connect(_on_player_controller_changed)
	player.camera_mode_changed.connect(_on_player_camera_mode_changed)

	spectator = SpectatorScript.new()
	spectator.name = "SpectatorController"
	add_child(spectator)
	spectator.setup(moon_world)

	persistence = WorldRepositoryScript.new()
	persistence.name = "LunarWorldRepository"
	add_child(persistence)
	persistence.setup(
		moon_world,
		zone_manager,
		entity_registry,
		logger
	)
	_sync_streaming_landmark_pins()

	world_interactor = WorldInteractorScript.new()
	world_interactor.name = "WorldInteractor"
	add_child(world_interactor)
	world_interactor.setup(player, logger)
	world_interactor.focus_changed.connect(_on_interaction_focus_changed)
	world_interactor.interaction_completed.connect(_on_interaction_completed)

	hud = HudScript.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(
		self,
		moon_world,
		player,
		spectator,
		zone_manager,
		entity_registry,
		persistence,
		logger
	)

	_restore_saved_location_or_random_spawn()
	_ensure_player_entity_registered()
	zone_manager.update_observer(player.get_world_position(), false)
	_set_menu_visible(true)


func _process(delta: float) -> void:
	if moon_world == null or player == null:
		return

	var active_world_position: Vector3
	if spectator_enabled:
		active_world_position = spectator.get_world_position()
		moon_world.update_for_view(
			active_world_position,
			active_world_position,
			true,
			delta
		)
	else:
		active_world_position = player.get_world_position()
		moon_world.update_for_view(
			active_world_position,
			moon_world.get_render_origin(),
			false,
			delta
		)

	if zone_manager != null:
		zone_manager.update_observer(active_world_position, spectator_enabled)
	_sync_player_entity()
	if persistence != null:
		persistence.set_last_player_world_position(
			player.get_stored_world_position()
			if spectator_enabled
			else player.get_world_position()
		)
		persistence.update_runtime_transforms()
		persistence.update_landmark_markers(active_world_position, delta)

	_update_interaction_enabled()

	if hud != null:
		hud.update_values(
			spectator_enabled,
			mouse_captured,
			player.get_world_position() if not spectator_enabled else player.get_stored_world_position(),
			active_world_position
		)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1 or event.keycode == KEY_ESCAPE:
			toggle_menu()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F3:
			toggle_spectator()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F2:
			toggle_spectator_lod_tracking()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F4:
			toggle_lod_debug_colors()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F7:
			run_entity_migration_mini_test()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F9:
			save_diagnostic_snapshot()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F10:
			run_persistence_mini_test()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_V:
			moon_world.cycle_surface_style()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F6 or event.physical_keycode == KEY_R:
			random_spawn()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_T and spectator_enabled:
			teleport_player_to_spectator()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_C and not spectator_enabled and not _is_menu_open():
			toggle_player_camera()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_J and not spectator_enabled and not _is_menu_open():
			toggle_player_controller()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_K:
			run_terrain_streaming_mini_test()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F12:
			run_controller_mini_test()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F11:
			toggle_fullscreen()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F5:
			get_viewport().set_input_as_handled()
			open_item_system_lab()
			return
		if event.keycode == KEY_F8:
			cycle_resolution()
			get_viewport().set_input_as_handled()
			return
		if event.ctrl_pressed and event.physical_keycode == KEY_S:
			save_world_now()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_M:
			toggle_beacon_markers()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_E and not spectator_enabled and not _is_menu_open():
			interact_with_world()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_B and not _is_menu_open():
			place_survey_beacon()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_DELETE and not _is_menu_open():
			remove_nearest_survey_beacon()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_TAB:
			_set_mouse_capture(not mouse_captured)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not mouse_captured:
			if not _is_menu_open():
				_set_mouse_capture(true)
				get_viewport().set_input_as_handled()


func open_item_system_lab() -> void:
	if persistence != null:
		persistence.save_all_loaded_chunks()
	get_tree().change_scene_to_file(ITEM_SYSTEM_LAB_SCENE)


func toggle_menu() -> void:
	if hud == null:
		return
	_set_menu_visible(not hud.is_menu_visible())


func _set_menu_visible(visible_value: bool) -> void:
	if hud != null:
		hud.set_menu_visible(visible_value)
	_set_mouse_capture(not visible_value)
	if logger != null:
		logger.info("ui", "menu_visibility_changed", {
			"visible": visible_value,
		})


func _is_menu_open() -> bool:
	return hud != null and hud.is_menu_visible()


func toggle_spectator() -> void:
	spectator_enabled = not spectator_enabled
	if spectator_enabled:
		var camera_world_transform: Transform3D = player.get_active_camera_world_transform()
		player.freeze_for_spectator()
		spectator.activate(camera_world_transform)
	else:
		var player_world_position: Vector3 = player.get_stored_world_position()
		spectator.deactivate()
		moon_world.prepare_surface_region(player_world_position.normalized(), true)
		moon_world.set_render_origin(moon_world.get_surface_anchor())
		player.restore_from_spectator()
	_set_mouse_capture(true)
	if hud != null:
		hud.set_menu_visible(false)
	logger.info("gameplay", "spectator_mode_changed", {
		"enabled": spectator_enabled,
	})


func toggle_spectator_lod_tracking() -> void:
	moon_world.set_spectator_tracking_enabled(
		not moon_world.is_spectator_tracking_enabled()
	)
	logger.info("lod", "spectator_tracking_changed", {
		"enabled": moon_world.is_spectator_tracking_enabled(),
	})


func toggle_lod_debug_colors() -> void:
	moon_world.set_lod_debug_enabled(not moon_world.is_lod_debug_enabled())
	logger.info("lod", "debug_colors_changed", {
		"enabled": moon_world.is_lod_debug_enabled(),
	})


func _restore_saved_location_or_random_spawn() -> void:
	var saved_position: Vector3 = persistence.get_last_player_world_position()
	if saved_position.length_squared() <= 1.0:
		random_spawn()
		return
	var direction: Vector3 = saved_position.normalized()
	moon_world.prepare_surface_region(direction, true)
	moon_world.set_render_origin(moon_world.get_surface_anchor())
	player.teleport_to_surface(direction)
	player.activate_after_spawn()
	_sync_player_entity()
	last_action_result = "Восстановлена последняя точка мира"
	logger.info("persistence", "player_location_restored", {
		"world_position": _vector_to_array(player.get_world_position()),
	})


func random_spawn() -> void:
	if spectator_enabled:
		spectator_enabled = false
		spectator.deactivate()

	var spawn_direction: Vector3 = moon_world.get_random_spawn_direction()
	moon_world.prepare_surface_region(spawn_direction, true)
	spawn_direction = moon_world.get_safe_spawn_direction_near(spawn_direction)
	moon_world.set_render_origin(moon_world.get_surface_anchor())
	player.teleport_to_surface(spawn_direction)
	player.activate_after_spawn()
	_set_mouse_capture(true)
	if hud != null:
		hud.set_menu_visible(false)
	_sync_player_entity()
	if zone_manager != null:
		zone_manager.update_observer(player.get_world_position(), false)
	if logger != null:
		logger.info("gameplay", "random_spawn", {
			"world_position": _vector_to_array(player.get_world_position()),
		})


func teleport_player_to_spectator() -> void:
	if not spectator_enabled or spectator == null:
		return
	var spectator_world_position: Vector3 = spectator.get_world_position()
	if spectator_world_position.length_squared() < 1.0:
		return
	var target_direction: Vector3 = spectator_world_position.normalized()
	spectator_enabled = false
	spectator.deactivate()
	moon_world.prepare_surface_region(target_direction, true)
	moon_world.set_render_origin(moon_world.get_surface_anchor())
	player.teleport_to_surface(target_direction)
	player.activate_after_spawn()
	_set_mouse_capture(true)
	if hud != null:
		hud.set_menu_visible(false)
	_sync_player_entity()
	zone_manager.update_observer(player.get_world_position(), false)
	logger.info("gameplay", "player_teleported_from_spectator", {
		"world_position": _vector_to_array(player.get_world_position()),
	})


func toggle_player_camera() -> String:
	if player == null or spectator_enabled:
		return ""
	var mode: String = player.toggle_camera_mode()
	last_action_result = "Камера: %s" % player.get_camera_mode_display_name()
	return mode


func toggle_player_controller() -> String:
	if player == null or spectator_enabled:
		return ""
	var current_id: String = player.get_controller_id()
	var target_id: String = (
		"lunar_jetpack" if current_id != "lunar_jetpack" else "lunar_humanoid"
	)
	if not player.activate_controller(target_id):
		last_action_result = "Не удалось подключить контроллер %s" % target_id
		return current_id
	last_action_result = "Контроллер: %s" % player.get_controller_display_name()
	return player.get_controller_id()


func activate_player_controller(profile_id: String) -> bool:
	if player == null or spectator_enabled:
		return false
	var activated: bool = player.activate_controller(profile_id)
	last_action_result = (
		"Контроллер: %s" % player.get_controller_display_name()
		if activated
		else "Не удалось подключить контроллер %s" % profile_id
	)
	return activated


func run_controller_mini_test() -> Dictionary:
	if player == null or spectator_enabled:
		last_controller_test_result = "FAIL: нужен режим персонажа"
		return {"passed": false, "summary": last_controller_test_result}
	var original_controller: String = player.get_controller_id()
	var original_camera: String = player.get_camera_mode()
	var target_controller: String = (
		"lunar_jetpack"
		if original_controller != "lunar_jetpack"
		else "lunar_humanoid"
	)
	var controller_switched: bool = player.activate_controller(target_controller)
	var controller_verified: bool = player.get_controller_id() == target_controller
	var toggled_camera: String = player.toggle_camera_mode()
	var camera_verified: bool = toggled_camera != original_camera
	var active_camera_valid: bool = (
		player.get_active_camera() != null
		and player.get_active_camera().current
	)
	var restored_controller: bool = player.activate_controller(original_controller)
	player.set_camera_mode(original_camera)
	var restored: bool = (
		restored_controller
		and player.get_controller_id() == original_controller
		and player.get_camera_mode() == original_camera
	)
	var passed: bool = (
		controller_switched
		and controller_verified
		and camera_verified
		and active_camera_valid
		and restored
	)
	last_controller_test_result = (
		"PASS: %s ↔ %s, %s ↔ %s" % [
			original_controller,
			target_controller,
			original_camera,
			toggled_camera,
		]
		if passed
		else "FAIL: controller/camera contract"
	)
	var result: Dictionary = {
		"passed": passed,
		"original_controller": original_controller,
		"target_controller": target_controller,
		"original_camera": original_camera,
		"target_camera": toggled_camera,
		"active_camera_valid": active_camera_valid,
		"restored": restored,
		"summary": last_controller_test_result,
	}
	logger.info("integration_test", "controller_mini_test", result)
	last_action_result = last_controller_test_result
	return result


func _sync_streaming_landmark_pins() -> void:
	if (
		moon_world == null
		or persistence == null
		or not moon_world.has_method("set_streaming_landmark_positions")
	):
		return
	moon_world.set_streaming_landmark_positions(
		persistence.get_landmark_world_positions()
	)


func interact_with_world() -> Dictionary:
	if (
		world_interactor == null
		or spectator_enabled
		or _is_menu_open()
		or not mouse_captured
	):
		var unavailable: Dictionary = {
			"success": false,
			"message": "Взаимодействие сейчас недоступно",
		}
		last_action_result = String(unavailable["message"])
		return unavailable
	if player.get_camera_mode() != "first_person":
		var camera_required: Dictionary = {
			"success": false,
			"message": "Для взаимодействия переключитесь в первое лицо (C)",
		}
		last_action_result = String(camera_required["message"])
		return camera_required
	var result: Dictionary = world_interactor.perform_interaction()
	last_action_result = String(result.get("message", "Действие завершено"))
	return result


func get_interaction_snapshot() -> Dictionary:
	return (
		world_interactor.get_current_snapshot()
		if world_interactor != null
		else {}
	)


func _update_interaction_enabled() -> void:
	if world_interactor == null:
		return
	world_interactor.set_enabled(
		not spectator_enabled
		and not _is_menu_open()
		and mouse_captured
		and player != null
		and player.get_camera_mode() == "first_person"
	)


func _on_interaction_focus_changed(snapshot: Dictionary) -> void:
	if hud != null:
		hud.set_interaction_state(snapshot)


func _on_interaction_completed(result: Dictionary) -> void:
	last_action_result = String(result.get("message", "Действие завершено"))
	_sync_streaming_landmark_pins()
	if hud != null:
		hud.set_interaction_state(get_interaction_snapshot())


func toggle_beacon_markers() -> bool:
	if persistence == null:
		return false
	var enabled: bool = persistence.toggle_landmark_markers()
	last_action_result = (
		"Дальние метки маяков включены"
		if enabled
		else "Дальние метки маяков выключены"
	)
	return enabled


func get_beacon_marker_summary() -> String:
	if persistence == null:
		return "не инициализированы"
	return persistence.get_landmark_summary()


func place_survey_beacon() -> String:
	if spectator_enabled:
		last_action_result = "Маяк можно ставить только в режиме персонажа"
		return ""
	var player_position: Vector3 = player.get_world_position()
	var up: Vector3 = player_position.normalized()
	var camera_transform: Transform3D = player.get_active_camera_world_transform()
	var forward: Vector3 = (-camera_transform.basis.z).slide(up)
	if forward.length_squared() < 0.000001:
		forward = (-player.global_transform.basis.z).slide(up)
	forward = forward.normalized()
	var approximate: Vector3 = player_position + forward * 5.0
	var direction: Vector3 = approximate.normalized()
	var beacon_position: Vector3 = moon_world.get_surface_point(direction) + direction * 0.06
	var entity_id: String = persistence.create_survey_beacon(
		beacon_position,
		forward
	)
	_sync_streaming_landmark_pins()
	last_action_result = (
		"Маяк установлен: %s" % entity_id
		if not entity_id.is_empty()
		else "Ошибка установки маяка"
	)
	logger.info("construction", "survey_beacon_placed", {
		"entity_id": entity_id,
		"world_position": _vector_to_array(beacon_position),
	})
	return entity_id


func remove_nearest_survey_beacon() -> String:
	var position: Vector3 = (
		player.get_stored_world_position()
		if spectator_enabled
		else player.get_world_position()
	)
	var entity_id: String = persistence.remove_nearest_survey_beacon(position, 18.0)
	_sync_streaming_landmark_pins()
	last_action_result = (
		"Маяк удалён: %s" % entity_id
		if not entity_id.is_empty()
		else "Рядом нет маяка (радиус 18 м)"
	)
	return entity_id


func save_world_now() -> Dictionary:
	var result: Dictionary = persistence.save_all_loaded_chunks()
	last_action_result = "Мир сохранён: %s" % String(result.get("summary", "-"))
	return result


func clear_persistent_world() -> void:
	var now: int = Time.get_ticks_msec()
	if now > clear_confirmation_deadline_msec:
		clear_confirmation_deadline_msec = now + 5000
		last_action_result = "Нажмите «Очистить» ещё раз в течение 5 секунд"
		return
	persistence.clear_world_data()
	_sync_streaming_landmark_pins()
	clear_confirmation_deadline_msec = 0
	last_action_result = "Постоянный слой тестового мира очищен"
	last_persistence_test_result = "Не запускался"


func run_persistence_mini_test() -> Dictionary:
	var position: Vector3 = (
		player.get_stored_world_position()
		if spectator_enabled
		else player.get_world_position()
	)
	var up: Vector3 = position.normalized()
	var forward: Vector3
	if spectator_enabled:
		forward = (-spectator.orientation.z).slide(up)
	else:
		forward = (-player.get_active_camera_world_transform().basis.z).slide(up)
	if forward.length_squared() < 0.000001:
		forward = Vector3.FORWARD.slide(up)
	var result: Dictionary = persistence.run_roundtrip_test(
		position,
		forward.normalized()
	)
	last_persistence_test_result = String(result.get("summary", "FAIL"))
	last_action_result = last_persistence_test_result
	return result


func run_entity_migration_mini_test() -> Dictionary:
	if entity_registry == null or zone_manager == null or player == null:
		last_mini_test_result = "FAIL: подсистемы не готовы"
		return {"passed": false, "reason": last_mini_test_result}
	entity_registry.unregister_entity(MINI_TEST_ENTITY_ID)
	var start_position: Vector3 = (
		player.get_stored_world_position()
		if spectator_enabled
		else player.get_world_position()
	)
	var start_partition: Dictionary = zone_manager.resolve_partition(start_position)
	var probe = EntityRecordScript.new()
	probe.setup(
		MINI_TEST_ENTITY_ID,
		"diagnostic_probe",
		start_position,
		{"purpose": {"name": "chunk_migration_mini_test"}}
	)
	var registered: bool = entity_registry.register_entity(probe)
	if not registered:
		last_mini_test_result = "FAIL: тестовая сущность не зарегистрирована"
		logger.error("integration_test", "entity_migration_test_failed", {
			"reason": last_mini_test_result,
		})
		return {"passed": false, "reason": last_mini_test_result}
	var transition_before: int = entity_registry.chunk_transition_count
	var target_position: Vector3 = start_position
	var target_partition: Dictionary = start_partition
	for multiplier in [1.35, 2.5, 4.0, 7.0]:
		target_position = zone_manager.offset_surface_position(
			start_position,
			zone_manager.get_nominal_chunk_size_m() * float(multiplier),
			zone_manager.get_nominal_chunk_size_m() * 0.37,
			0.0
		)
		target_partition = zone_manager.resolve_partition(target_position)
		if String(target_partition.get("chunk_id", "")) != String(start_partition.get("chunk_id", "")):
			break
	entity_registry.update_entity_position(MINI_TEST_ENTITY_ID, target_position)
	var chunk_changed: bool = (
		String(start_partition.get("chunk_id", ""))
		!= String(target_partition.get("chunk_id", ""))
	)
	var event_created: bool = entity_registry.chunk_transition_count > transition_before
	var passed: bool = chunk_changed and event_created
	last_mini_test_result = (
		"PASS: %s → %s" % [
			String(start_partition.get("chunk_name", "-")),
			String(target_partition.get("chunk_name", "-")),
		]
		if passed
		else "FAIL: граница чанка не зафиксирована"
	)
	var result: Dictionary = {
		"passed": passed,
		"from_zone": start_partition.get("zone_id", ""),
		"to_zone": target_partition.get("zone_id", ""),
		"from_chunk": start_partition.get("chunk_id", ""),
		"to_chunk": target_partition.get("chunk_id", ""),
		"chunk_event_created": event_created,
		"summary": last_mini_test_result,
	}
	logger.info("integration_test", "entity_migration_mini_test", result)
	entity_registry.unregister_entity(MINI_TEST_ENTITY_ID)
	return result


func run_terrain_streaming_mini_test() -> Dictionary:
	if moon_world == null or player == null:
		last_terrain_streaming_test_result = "FAIL: мир не готов"
		return {"passed": false, "summary": last_terrain_streaming_test_result}
	var forward_world: Vector3 = -player.get_view_basis().z
	var result: Dictionary = moon_world.run_terrain_streaming_mini_test(
		player.get_world_position(),
		forward_world
	)
	last_terrain_streaming_test_result = String(
		result.get("summary", "RUNNING")
	)
	logger.info("integration_test", "terrain_streaming_mini_test_started", result)
	return result


func _on_terrain_streaming_test_completed(summary: Dictionary) -> void:
	last_terrain_streaming_test_result = String(
		summary.get("summary", "PASS")
	)
	last_action_result = "Terrain streaming test завершён"
	logger.info("integration_test", "terrain_streaming_mini_test_completed", summary)


func save_diagnostic_snapshot() -> String:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(DIAGNOSTIC_DIR)
	)
	var stamp: String = Time.get_datetime_string_from_system(false, false)
	stamp = stamp.replace(":", "-")
	var path: String = "%s/diagnostic_%s.json" % [DIAGNOSTIC_DIR, stamp]
	var payload: Dictionary = {
		"schema": "lunar.diagnostic.v1",
		"project_version": PROJECT_VERSION,
		"build_id": BUILD_ID,
		"created_at_utc": Time.get_datetime_string_from_system(true, true),
		"engine": Engine.get_version_info(),
		"os": {
			"name": OS.get_name(),
			"version": OS.get_version(),
			"processor_count": OS.get_processor_count(),
		},
		"display": {
			"mode": get_display_mode_name(),
			"resolution": get_display_resolution_name(),
		},
		"gameplay": {
			"spectator_enabled": spectator_enabled,
			"player_world_position": _vector_to_array(
				player.get_stored_world_position()
				if spectator_enabled
				else player.get_world_position()
			),
			"last_mini_test_result": last_mini_test_result,
			"last_persistence_test_result": last_persistence_test_result,
			"last_controller_test_result": last_controller_test_result,
			"last_terrain_streaming_test_result": last_terrain_streaming_test_result,
			"last_action_result": last_action_result,
			"controller": player.get_controller_snapshot(),
			"camera_mode": player.get_camera_mode(),
			"interaction": get_interaction_snapshot(),
		},
		"partitions": zone_manager.create_partition_snapshot(),
		"entities": entity_registry.create_snapshot(),
		"persistence": persistence.create_snapshot(),
		"terrain_streaming": moon_world.get_terrain_streaming_snapshot(),
		"recent_migrations": entity_registry.get_recent_migrations(),
		"recent_logs": logger.get_recent_entries(),
		"log_path": logger.get_log_path(),
		"terrain_performance_log_path": moon_world.get_terrain_performance_log_path(),
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		last_diagnostic_path = "ERROR"
		logger.error("diagnostics", "snapshot_write_failed", {"path": path})
		return last_diagnostic_path
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	last_diagnostic_path = path
	logger.info("diagnostics", "snapshot_saved", {"path": path})
	return path


func get_last_mini_test_result() -> String:
	return last_mini_test_result


func get_last_persistence_test_result() -> String:
	return last_persistence_test_result


func get_last_controller_test_result() -> String:
	return last_controller_test_result


func get_last_terrain_streaming_test_result() -> String:
	return last_terrain_streaming_test_result


func get_last_action_result() -> String:
	return last_action_result


func get_last_diagnostic_path() -> String:
	return last_diagnostic_path


func toggle_fullscreen() -> void:
	fullscreen_enabled = not fullscreen_enabled
	_apply_display_settings()
	_save_display_settings()
	logger.info("display", "fullscreen_changed", {
		"enabled": fullscreen_enabled,
		"resolution": get_display_resolution_name(),
	})


func cycle_resolution() -> void:
	resolution_index = (resolution_index + 1) % WINDOWED_RESOLUTIONS.size()
	_apply_display_settings()
	_save_display_settings()
	logger.info("display", "resolution_changed", {
		"resolution": get_display_resolution_name(),
	})


func get_display_mode_name() -> String:
	return "Полный экран" if fullscreen_enabled else "Окно"


func get_display_resolution_name() -> String:
	var window_size: Vector2i = DisplayServer.window_get_size()
	if fullscreen_enabled:
		return "%d×%d (рабочий экран)" % [window_size.x, window_size.y]
	var preset_size: Vector2i = WINDOWED_RESOLUTIONS[resolution_index]
	return "%d×%d" % [preset_size.x, preset_size.y]


func _apply_display_settings() -> void:
	if fullscreen_enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var target_size: Vector2i = WINDOWED_RESOLUTIONS[resolution_index]
	DisplayServer.window_set_size(target_size)
	_center_window(target_size)


func _center_window(target_size: Vector2i) -> void:
	var screen_index: int = DisplayServer.window_get_current_screen()
	var screen_position: Vector2i = DisplayServer.screen_get_position(screen_index)
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen_index)
	var centered_position := Vector2i(
		screen_position.x + maxi(int((screen_size.x - target_size.x) / 2), 0),
		screen_position.y + maxi(int((screen_size.y - target_size.y) / 2), 0)
	)
	DisplayServer.window_set_position(centered_position)


func _load_display_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(DISPLAY_SETTINGS_PATH) != OK:
		return
	fullscreen_enabled = bool(cfg.get_value("display", "fullscreen", false))
	resolution_index = int(cfg.get_value("display", "resolution_index", resolution_index))
	resolution_index = clampi(resolution_index, 0, WINDOWED_RESOLUTIONS.size() - 1)


func _save_display_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen_enabled)
	cfg.set_value("display", "resolution_index", resolution_index)
	cfg.save(DISPLAY_SETTINGS_PATH)


func _ensure_player_entity_registered() -> void:
	if entity_registry.has_entity(PLAYER_ENTITY_ID):
		return
	var record = EntityRecordScript.new()
	record.setup(
		PLAYER_ENTITY_ID,
		"player_astronaut",
		player.get_world_position(),
		{
			"persistence": {"persistent": false},
			"controller": {
				"type": "local_player",
				"profile_id": player.get_controller_id(),
				"camera_mode": player.get_camera_mode(),
			},
		}
	)
	entity_registry.register_entity(record)


func _sync_player_entity() -> void:
	if entity_registry == null or player == null:
		return
	_ensure_player_entity_registered()
	var position: Vector3 = (
		player.get_stored_world_position()
		if spectator_enabled
		else player.get_world_position()
	)
	entity_registry.update_entity_position(PLAYER_ENTITY_ID, position)


func _on_player_controller_changed(previous_id: String, current_id: String) -> void:
	_sync_player_controller_component()
	if logger != null:
		logger.info("controller", "player_controller_changed", {
			"previous_id": previous_id,
			"current_id": current_id,
			"camera_mode": player.get_camera_mode(),
		})


func _on_player_camera_mode_changed(mode: String) -> void:
	_sync_player_controller_component()
	if logger != null:
		logger.info("controller", "player_camera_mode_changed", {
			"mode": mode,
			"controller_id": player.get_controller_id(),
		})


func _sync_player_controller_component() -> void:
	if entity_registry == null or player == null:
		return
	var record = entity_registry.get_entity(PLAYER_ENTITY_ID)
	if record == null:
		return
	record.set_component("controller", {
		"type": "local_player",
		"profile_id": player.get_controller_id(),
		"display_name": player.get_controller_display_name(),
		"camera_mode": player.get_camera_mode(),
	})


func _on_partition_window_changed(snapshot: Dictionary) -> void:
	if logger == null:
		return
	logger.info("partition", "active_partition_changed", {
		"active_zone": snapshot.get("active_zone", ""),
		"active_chunk": snapshot.get("active_chunk", ""),
		"observer": snapshot.get("observer", ""),
		"loaded_zones": zone_manager.get_loaded_zone_count(),
		"loaded_chunks": zone_manager.get_loaded_chunk_count(),
	})


func _set_mouse_capture(captured: bool) -> void:
	mouse_captured = captured
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func _ensure_input_actions() -> void:
	_set_single_key_action("move_forward", KEY_W)
	_set_single_key_action("move_back", KEY_S)
	_set_single_key_action("move_left", KEY_A)
	_set_single_key_action("move_right", KEY_D)
	_set_single_key_action("jump", KEY_SPACE)
	_set_single_key_action("move_up", KEY_SPACE)
	_set_single_key_action("move_down", KEY_CTRL)
	_set_single_key_action("boost", KEY_SHIFT)
	_set_single_key_action("random_spawn", KEY_R)
	_set_single_key_action("roll_left", KEY_E)
	_set_single_key_action("roll_right", KEY_Q)
	_set_single_key_action("level_horizon", KEY_H)
	_set_single_key_action("teleport_player", KEY_T)
	_set_single_key_action("cycle_surface_style", KEY_V)


func _set_single_key_action(action_name: StringName, physical_key: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey:
			InputMap.action_erase_event(action_name, existing_event)
	var input_event := InputEventKey.new()
	input_event.physical_keycode = physical_key
	InputMap.action_add_event(action_name, input_event)


func _vector_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if persistence != null and is_instance_valid(persistence):
			persistence.flush()
		get_tree().quit()


func _exit_tree() -> void:
	if persistence != null and is_instance_valid(persistence):
		persistence.flush()
