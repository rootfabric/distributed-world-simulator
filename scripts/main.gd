extends Node3D

const MoonWorldScript = preload("res://scripts/moon_world.gd")
const LunarPlayerScript = preload("res://scripts/lunar_player.gd")
const SpectatorScript = preload("res://scripts/spectator_controller.gd")
const HudScript = preload("res://scripts/hud.gd")

var moon_world
var player
var spectator
var hud
var spectator_enabled: bool = false
var mouse_captured: bool = true


func _ready() -> void:
	_ensure_input_actions()
	moon_world = MoonWorldScript.new()
	moon_world.name = "MoonWorld"
	add_child(moon_world)
	moon_world.setup()

	player = LunarPlayerScript.new()
	player.name = "LunarPlayer"
	add_child(player)
	player.setup(moon_world)

	spectator = SpectatorScript.new()
	spectator.name = "SpectatorController"
	add_child(spectator)
	spectator.setup(moon_world)

	hud = HudScript.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(self, moon_world, player, spectator)

	random_spawn()
	_set_mouse_capture(true)


func _process(_delta: float) -> void:
	if moon_world == null or player == null:
		return

	var active_world_position: Vector3
	if spectator_enabled:
		active_world_position = spectator.get_world_position()
		moon_world.update_for_view(
			active_world_position,
			active_world_position,
			true,
			_delta
		)
	else:
		active_world_position = player.get_world_position()
		moon_world.update_for_view(
			active_world_position,
			moon_world.get_render_origin(),
			false,
			_delta
		)

	if hud != null:
		hud.update_values(
			spectator_enabled,
			mouse_captured,
			player.get_world_position() if not spectator_enabled else player.get_stored_world_position(),
			active_world_position
		)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
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
		if event.keycode == KEY_F6 or event.physical_keycode == KEY_R:
			random_spawn()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_T and spectator_enabled:
			teleport_player_to_spectator()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_TAB or event.keycode == KEY_ESCAPE:
			_set_mouse_capture(not mouse_captured)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not mouse_captured:
			_set_mouse_capture(true)
			get_viewport().set_input_as_handled()


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


func toggle_spectator_lod_tracking() -> void:
	moon_world.set_spectator_tracking_enabled(
		not moon_world.is_spectator_tracking_enabled()
	)


func toggle_lod_debug_colors() -> void:
	moon_world.set_lod_debug_enabled(not moon_world.is_lod_debug_enabled())


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


func teleport_player_to_spectator() -> void:
	if not spectator_enabled or spectator == null:
		return

	var spectator_world_position: Vector3 = spectator.get_world_position()
	if spectator_world_position.length_squared() < 1.0:
		return

	# The player is placed on the lunar surface directly below the spectator.
	# Keeping the spectator latitude/longitude avoids an unsafe long fall from orbit.
	var target_direction: Vector3 = spectator_world_position.normalized()
	spectator_enabled = false
	spectator.deactivate()
	moon_world.prepare_surface_region(target_direction, true)
	moon_world.set_render_origin(moon_world.get_surface_anchor())
	player.teleport_to_surface(target_direction)
	player.activate_after_spawn()
	_set_mouse_capture(true)


func _set_mouse_capture(captured: bool) -> void:
	mouse_captured = captured
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func _ensure_input_actions() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("move_up", KEY_SPACE)
	_add_key_action("move_down", KEY_CTRL)
	_add_key_action("boost", KEY_SHIFT)
	_add_key_action("random_spawn", KEY_R)
	_add_key_action("roll_left", KEY_Q)
	_add_key_action("roll_right", KEY_E)
	_add_key_action("level_horizon", KEY_H)
	_add_key_action("teleport_player", KEY_T)


func _add_key_action(action_name: StringName, physical_key: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var input_event := InputEventKey.new()
	input_event.physical_keycode = physical_key
	if not InputMap.action_has_event(action_name, input_event):
		InputMap.action_add_event(action_name, input_event)
