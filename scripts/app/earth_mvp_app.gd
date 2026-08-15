extends "res://scripts/app/earth_app.gd"

# V0 Earth is a playable tangent-plane projection over the canonical procedural
# planet. The server keeps authoritative M3 X/Z state; this adapter maps it to a
# deterministic land patch and consumes the already accepted NX4 prediction
# presentation instead of snapping the camera to 20 Hz authoritative updates.

const MVP_SURFACE_EYE_ALTITUDE_M := 1.75
const MVP_PREFERRED_BIOMES: Array[String] = ["grassland", "forest", "desert"]
const MVP_SPECTATOR_SPEED_MPS := 25.0
const MVP_LOCAL_BODY_VISUAL_OFFSET_M := -0.85
const M5NetworkedInventoryShellScript = preload(
	"res://scripts/ui/inventory/networked/m5_networked_inventory_shell.gd"
)

var _mvp_surface_anchor_direction := Vector3.ZERO
var _mvp_surface_biome := "unknown"
var _mvp_prediction_enabled := false
var _mvp_prediction_signal_connected := false
var _mvp_authoritative_seed_applied := false
var _mvp_prediction_updates := 0
var _mvp_prediction_failures := 0
var _mvp_local_vertical_offset_m := 0.0

var _mvp_inventory_visible := false
var _mvp_inventory_shell
var _mvp_inventory_setup_error := ""
var _mvp_input_owner := "GAMEPLAY"

var _mvp_spectator_enabled := false
var _mvp_spectator_saved_speed := 900.0
var _mvp_spectator_saved_orientation := Basis.IDENTITY
var _mvp_latest_local_record: Dictionary = {}
var _mvp_local_body: MeshInstance3D


func attach_m3_multiplayer_client(runtime) -> Dictionary:
	_mvp_prediction_enabled = (
		runtime != null
		and runtime.has_method("advance_local_prediction")
		and runtime.has_signal("prediction_updated")
	)
	_mvp_authoritative_seed_applied = false
	_mvp_prediction_updates = 0
	_mvp_prediction_failures = 0
	_mvp_local_vertical_offset_m = 0.0
	_mvp_latest_local_record.clear()
	_mvp_spectator_enabled = false
	_prepare_mvp_surface_anchor()

	var result: Dictionary = super.attach_m3_multiplayer_client(runtime)
	if not bool(result.get("success", false)):
		return result

	if _mvp_prediction_enabled:
		if not runtime.prediction_updated.is_connected(_on_mvp_prediction_updated):
			runtime.prediction_updated.connect(_on_mvp_prediction_updated)
		_mvp_prediction_signal_connected = true
	else:
		_mvp_prediction_signal_connected = false

	var inventory_setup: Dictionary = _ensure_mvp_inventory_shell(runtime)
	if not bool(inventory_setup.get("success", false)):
		return inventory_setup
	_ensure_mvp_local_body()
	_update_mvp_local_body_visual()

	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["mode"] = "EARTH_NETWORK_PLAYABLE_MVP"
	details["prediction_enabled"] = _mvp_prediction_enabled
	details["surface_biome"] = _mvp_surface_biome
	details["surface_eye_altitude_m"] = MVP_SURFACE_EYE_ALTITUDE_M
	result["details"] = details
	return result


func register_runtime_commands(registry, owner_id: String) -> void:
	super.register_runtime_commands(registry, owner_id)
	_register_command(registry, owner_id, {
		"id": "inventory.toggle",
		"description": "Открыть или закрыть MVP-инвентарь сетевого игрока.",
		"usage": "inventory.toggle",
		"category": "inventory",
	}, Callable(self, "_command_mvp_inventory_toggle"))
	_register_command(registry, owner_id, {
		"id": "inventory.hotbar.select",
		"description": "Выбрать слот хотбара сетевого игрока.",
		"usage": "inventory.hotbar.select <1-8>",
		"category": "inventory",
	}, Callable(self, "_command_mvp_inventory_hotbar_select"))
	_register_command(registry, owner_id, {
		"id": "inventory.drop",
		"description": "Выбросить выбранный предмет хотбара.",
		"usage": "inventory.drop",
		"category": "inventory",
	}, Callable(self, "_command_mvp_inventory_drop"))
	_register_command(registry, owner_id, {
		"id": "player.spectator.toggle",
		"description": "Отделить spectator-камеру от тела игрока или вернуться в тело.",
		"usage": "player.spectator.toggle",
		"category": "player",
	}, Callable(self, "_command_mvp_spectator_toggle"))


func _process(delta: float) -> void:
	super._process(delta)
	if _mvp_spectator_enabled:
		_sync_remote_presenter_origins()
		_update_mvp_local_body_visual()


func _prepare_mvp_surface_anchor() -> void:
	if earth_world == null or earth_explorer == null:
		return
	_mvp_surface_anchor_direction = Vector3.ZERO
	_mvp_surface_biome = "unknown"
	for biome_name in MVP_PREFERRED_BIOMES:
		var candidate: Vector3 = earth_world.find_biome_direction(biome_name)
		if candidate.length_squared() < 0.5:
			continue
		var resolved_biome: String = earth_world.get_biome_name_at(candidate)
		if resolved_biome == "ocean":
			continue
		_mvp_surface_anchor_direction = candidate.normalized()
		_mvp_surface_biome = resolved_biome
		break
	if _mvp_surface_anchor_direction.length_squared() < 0.5:
		_mvp_surface_anchor_direction = earth_world.get_canonical_spawn_direction()
		_mvp_surface_biome = earth_world.get_biome_name_at(_mvp_surface_anchor_direction)

	# activate() prepares the high-detail local terrain around the chosen anchor.
	# Base attach immediately switches translation back to authoritative replica
	# mode while preserving local mouse-look.
	earth_explorer.activate(
		_mvp_surface_anchor_direction,
		MVP_SURFACE_EYE_ALTITUDE_M
	)


func _apply_m3_local_spectator_record(record: Dictionary) -> void:
	# Normally NX4 prediction owns presentation after the first authoritative
	# seed. While local gameplay input is intentionally suspended (inventory or
	# detached spectator), raw authoritative records keep the parked body fresh.
	if (
		_mvp_prediction_enabled
		and _mvp_authoritative_seed_applied
		and not _mvp_spectator_enabled
		and not _mvp_inventory_visible
	):
		return
	_apply_mvp_presentation_record(record)
	_mvp_authoritative_seed_applied = true


func _on_mvp_prediction_updated(
	_predicted_state: Dictionary,
	presentation_state: Dictionary,
	_report: Dictionary
) -> void:
	if not _m3_attached or presentation_state.is_empty():
		return
	_apply_mvp_presentation_record(presentation_state)
	_mvp_prediction_updates += 1


func _on_m4_item_graph_updated(snapshot: Dictionary) -> void:
	# Keep Earth diagnostics synchronized. The V0-I1 shell listens directly to
	# the same canonical runtime signal through M5InventoryUiBridge.
	super._on_m4_item_graph_updated(snapshot)


func _apply_mvp_presentation_record(record: Dictionary) -> void:
	if earth_world == null or earth_explorer == null:
		return
	var position_value = record.get("position", {})
	if not position_value is Dictionary:
		return
	_mvp_latest_local_record = record.duplicate(true)
	var position: Dictionary = position_value
	var planar_x := float(position.get("x", 0.0))
	var planar_z := float(position.get("z", 0.0))
	var vertical_offset := maxf(float(position.get("y", 0.0)), 0.0)
	_m3_local_planar_position = Vector2(planar_x, planar_z)
	_mvp_local_vertical_offset_m = vertical_offset
	if not _mvp_spectator_enabled:
		var mapped_direction: Vector3 = _map_m3_position_to_earth_direction(
			planar_x,
			planar_z
		)
		earth_explorer.apply_network_replica_pose(
			mapped_direction,
			MVP_SURFACE_EYE_ALTITUDE_M + vertical_offset
		)
	_sync_remote_presenter_origins()
	_update_mvp_local_body_visual()


func _sync_remote_presenter_origins() -> void:
	var local_planar := _m3_local_planar_position
	var local_vertical_offset := _mvp_local_vertical_offset_m
	if _mvp_spectator_enabled and earth_explorer != null:
		var observer_state := _get_mvp_observer_plane_state()
		local_planar = observer_state.get("planar", local_planar)
		local_vertical_offset = float(
			observer_state.get("vertical_offset_m", local_vertical_offset)
		)
	for logical_id_value in _m3_remote_presenters.keys():
		var presenter = _m3_remote_presenters.get(logical_id_value)
		if presenter == null or not is_instance_valid(presenter):
			continue
		presenter.set_local_planar_position(local_planar)
		if presenter.has_method("set_local_vertical_offset"):
			presenter.set_local_vertical_offset(local_vertical_offset)


func _get_mvp_observer_plane_state() -> Dictionary:
	if earth_world == null or earth_explorer == null:
		return {
			"planar": _m3_local_planar_position,
			"vertical_offset_m": _mvp_local_vertical_offset_m,
		}
	var axes := _get_mvp_surface_axes()
	var up: Vector3 = axes["up"]
	var east: Vector3 = axes["east"]
	var north: Vector3 = axes["north"]
	var anchor_eye_position: Vector3 = _map_m3_position_to_earth_world(0.0, 0.0)
	var observer_offset: Vector3 = earth_explorer.get_frame_position() - anchor_eye_position
	return {
		"planar": Vector2(
			observer_offset.dot(east),
			-observer_offset.dot(north)
		),
		"vertical_offset_m": maxf(observer_offset.dot(up), 0.0),
	}


func _get_mvp_surface_axes() -> Dictionary:
	var up := Vector3.UP
	if earth_world != null:
		up = (
			_mvp_surface_anchor_direction
			if _mvp_surface_anchor_direction.length_squared() >= 0.5
			else earth_world.get_canonical_spawn_direction()
		).normalized()
	var east := Vector3.UP.cross(up)
	if east.length_squared() < 0.000001:
		east = Vector3.RIGHT.cross(up)
	east = east.normalized()
	var north := up.cross(east).normalized()
	return {"up": up, "east": east, "north": north}


func _map_m3_position_to_earth_direction(x: float, z: float) -> Vector3:
	if earth_world == null:
		return Vector3.UP
	var axes := _get_mvp_surface_axes()
	var up: Vector3 = axes["up"]
	var east: Vector3 = axes["east"]
	var north: Vector3 = axes["north"]
	var surface: Vector3 = earth_world.get_surface_point(up)
	# M3 follows Godot's local convention: +X is right and -Z is forward.
	# Therefore north is mapped to -Z, matching the camera's local -Z heading.
	return (surface + east * x - north * z).normalized()


func _map_m3_position_to_earth_world(x: float, z: float) -> Vector3:
	var direction: Vector3 = _map_m3_position_to_earth_direction(x, z)
	return (
		earth_world.get_surface_point(direction)
		+ direction * MVP_SURFACE_EYE_ALTITUDE_M
	)


func _apply_m3_network_input(delta: float) -> void:
	if _mvp_spectator_enabled or _mvp_inventory_visible:
		return
	if not _m3_attached or m3_multiplayer_client_runtime == null or not local_input_enabled:
		return
	if (
		m3_multiplayer_client_runtime.has_method("is_automated_acceptance")
		and m3_multiplayer_client_runtime.is_automated_acceptance()
	):
		return
	if not _mvp_prediction_enabled:
		super._apply_m3_network_input(delta)
		return

	var input_vector: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)
	var intent := {
		"move_x": input_vector.x,
		"move_z": -input_vector.y,
		"look_yaw": earth_explorer.get_surface_relative_yaw(),
		"look_pitch": 0.0,
		"jump_pressed": Input.is_action_just_pressed("move_up"),
		"sprint": Input.is_action_pressed("boost"),
		"delta_seconds": maxf(delta, 0.000001),
	}
	var advanced: Dictionary = m3_multiplayer_client_runtime.advance_local_prediction(
		intent,
		delta
	)
	if not bool(advanced.get("success", false)):
		_mvp_prediction_failures += 1
		return

	# Real M3 emits prediction_updated. Keep the return-value path as a bounded
	# compatibility fallback for deterministic test doubles and future adapters.
	if not _mvp_prediction_signal_connected:
		var details: Dictionary = Dictionary(advanced.get("details", {}))
		var presentation_value = details.get("presentation_state", {})
		if presentation_value is Dictionary and not Dictionary(presentation_value).is_empty():
			_apply_mvp_presentation_record(Dictionary(presentation_value))
			_mvp_prediction_updates += 1


func _submit_mvp_neutral_input() -> void:
	if not _m3_attached or m3_multiplayer_client_runtime == null:
		return
	if not _mvp_prediction_enabled:
		return
	var neutral_intent := {
		"move_x": 0.0,
		"move_z": 0.0,
		"look_yaw": (
			earth_explorer.get_surface_relative_yaw()
			if earth_explorer != null
			else 0.0
		),
		"look_pitch": 0.0,
		"jump_pressed": false,
		"sprint": false,
		"delta_seconds": 1.0 / 60.0,
	}
	var stopped: Dictionary = m3_multiplayer_client_runtime.advance_local_prediction(
		neutral_intent,
		1.0 / 60.0
	)
	if not bool(stopped.get("success", false)):
		_mvp_prediction_failures += 1


func _command_mvp_inventory_toggle(_arguments: Array[String]) -> Dictionary:
	if _mvp_inventory_shell == null or not is_instance_valid(_mvp_inventory_shell):
		return {"success": false, "output": "Сетевой инвентарь ещё не готов"}
	_set_mvp_inventory_visible(not _mvp_inventory_shell.is_inventory_visible())
	return {
		"success": true,
		"output": "Инвентарь открыт" if _mvp_inventory_visible else "Инвентарь закрыт",
	}


func _command_mvp_inventory_hotbar_select(arguments: Array[String]) -> Dictionary:
	if arguments.size() != 1 or not arguments[0].is_valid_int():
		return {"success": false, "output": "Использование: inventory.hotbar.select <1-8>"}
	var slot_number := int(arguments[0])
	if slot_number < 1 or slot_number > 8:
		return {"success": false, "output": "Слот хотбара должен быть в диапазоне 1..8"}
	if _mvp_inventory_shell == null or not is_instance_valid(_mvp_inventory_shell):
		return {"success": false, "output": "Сетевой инвентарь ещё не готов"}
	var result: Dictionary = _mvp_inventory_shell.select_hotbar(slot_number - 1)
	return _mvp_command_result(result, "Выбран слот %d" % slot_number)


func _command_mvp_inventory_drop(_arguments: Array[String]) -> Dictionary:
	var item_id := _get_mvp_selected_hotbar_item_id()
	if item_id.is_empty():
		return {"success": false, "output": "В выбранном слоте хотбара нет предмета"}
	var result := m4_execute_item_command("item.drop", {
		"item_id": item_id,
		"quantity": -1,
	})
	return _mvp_command_result(result, "Предмет выброшен")


func _command_mvp_spectator_toggle(_arguments: Array[String]) -> Dictionary:
	_set_mvp_spectator_enabled(not _mvp_spectator_enabled)
	return {
		"success": true,
		"output": (
			"Spectator включён: тело игрока оставлено на месте"
			if _mvp_spectator_enabled
			else "Spectator выключен: управление возвращено игроку"
		),
	}


func _set_mvp_inventory_visible(visible: bool) -> void:
	if _mvp_inventory_shell == null or not is_instance_valid(_mvp_inventory_shell):
		return
	if _mvp_inventory_visible == visible:
		return
	_mvp_inventory_visible = visible
	if visible:
		_submit_mvp_neutral_input()
	_mvp_inventory_shell.set_inventory_visible(visible)
	_sync_mvp_input_ownership()
	if _mvp_spectator_enabled and earth_explorer != null:
		earth_explorer.set_physics_process(not visible)


func _sync_mvp_input_ownership() -> void:
	# Earth MVP is the single owner of global mouse capture. Child UI layers may
	# expose visibility, but must not independently switch Input.mouse_mode.
	_mvp_input_owner = (
		"INVENTORY"
		if _mvp_inventory_visible
		else ("SPECTATOR" if _mvp_spectator_enabled else "GAMEPLAY")
	)
	Input.mouse_mode = (
		Input.MOUSE_MODE_VISIBLE
		if _mvp_input_owner == "INVENTORY"
		else Input.MOUSE_MODE_CAPTURED
	)


func _set_mvp_spectator_enabled(enabled: bool) -> void:
	if earth_explorer == null or _mvp_spectator_enabled == enabled:
		return
	if enabled:
		_set_mvp_inventory_visible(false)
		_submit_mvp_neutral_input()
		_mvp_spectator_saved_speed = earth_explorer.movement_speed
		_mvp_spectator_saved_orientation = earth_explorer.orientation
		_mvp_spectator_enabled = true
		earth_explorer.movement_speed = MVP_SPECTATOR_SPEED_MPS
		earth_explorer.set_network_replica_mode(false)
		_ensure_mvp_local_body()
		_mvp_local_body.visible = true
		_update_mvp_local_body_visual()
		_sync_remote_presenter_origins()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	_mvp_spectator_enabled = false
	earth_explorer.movement_speed = _mvp_spectator_saved_speed
	earth_explorer.set_network_replica_mode(true)
	if not _mvp_latest_local_record.is_empty():
		_apply_mvp_presentation_record(_mvp_latest_local_record)
	else:
		var direction := _map_m3_position_to_earth_direction(
			_m3_local_planar_position.x,
			_m3_local_planar_position.y
		)
		earth_explorer.apply_network_replica_pose(
			direction,
			MVP_SURFACE_EYE_ALTITUDE_M + _mvp_local_vertical_offset_m
		)
	earth_explorer.orientation = _mvp_spectator_saved_orientation.orthonormalized()
	earth_explorer.global_transform = Transform3D(earth_explorer.orientation, Vector3.ZERO)
	earth_explorer.reset_physics_interpolation()
	if _mvp_local_body != null:
		_mvp_local_body.visible = false
	_sync_remote_presenter_origins()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _ensure_mvp_local_body() -> void:
	if _mvp_local_body != null and is_instance_valid(_mvp_local_body):
		return
	_mvp_local_body = MeshInstance3D.new()
	_mvp_local_body.name = "LocalPlayerBodySpectatorVisual"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	_mvp_local_body.mesh = capsule
	_mvp_local_body.visible = false
	add_child(_mvp_local_body)


func _update_mvp_local_body_visual() -> void:
	if _mvp_local_body == null or not is_instance_valid(_mvp_local_body):
		return
	_mvp_local_body.visible = _mvp_spectator_enabled
	if not _mvp_spectator_enabled or earth_world == null or earth_explorer == null:
		return
	var direction := _map_m3_position_to_earth_direction(
		_m3_local_planar_position.x,
		_m3_local_planar_position.y
	)
	var body_world := (
		_map_m3_position_to_earth_world(
			_m3_local_planar_position.x,
			_m3_local_planar_position.y
		)
		+ direction * (
			_mvp_local_vertical_offset_m + MVP_LOCAL_BODY_VISUAL_OFFSET_M
		)
	)
	_mvp_local_body.position = body_world - earth_explorer.get_frame_position()
	var east := Vector3.UP.cross(direction)
	if east.length_squared() < 0.000001:
		east = Vector3.RIGHT.cross(direction)
	east = east.normalized()
	var north := direction.cross(east).normalized()
	_mvp_local_body.basis = Basis(east, direction, -north).orthonormalized()


func _ensure_mvp_inventory_shell(runtime) -> Dictionary:
	if _mvp_inventory_shell != null and is_instance_valid(_mvp_inventory_shell):
		return {"success": true, "error_code": "", "details": {"reused": true}}
	if runtime == null or not runtime.has_method("get_local_player_id"):
		_mvp_inventory_setup_error = "V0_I1_NETWORK_RUNTIME_REQUIRED"
		return {"success": false, "error_code": _mvp_inventory_setup_error, "details": {}}

	_mvp_inventory_shell = M5NetworkedInventoryShellScript.new()
	_mvp_inventory_shell.name = "V0NetworkedInventory"
	add_child(_mvp_inventory_shell)
	var setup_result: Dictionary = _mvp_inventory_shell.setup(
		runtime,
		String(runtime.get_local_player_id())
	)
	if not bool(setup_result.get("success", false)):
		_mvp_inventory_setup_error = String(
			setup_result.get("error_code", "V0_I1_INVENTORY_SETUP_FAILED")
		)
		_mvp_inventory_shell.queue_free()
		_mvp_inventory_shell = null
		return setup_result

	_mvp_inventory_setup_error = ""
	_mvp_inventory_visible = false
	_mvp_inventory_shell.set_inventory_visible(false)
	return {
		"success": true,
		"error_code": "",
		"details": {
			"ui": "M5_NETWORKED_INVENTORY_SHELL",
			"bridge": "M5_INVENTORY_UI_BRIDGE",
			"canonical_truth": "SERVER_M4_ITEM_GRAPH",
		},
	}


func _get_mvp_selected_hotbar_item_id() -> String:
	if _mvp_inventory_shell != null and is_instance_valid(_mvp_inventory_shell):
		var report: Dictionary = _mvp_inventory_shell.get_report()
		var hotbar_model: Dictionary = Dictionary(report.get("hotbar_model", {}))
		for cell_value in hotbar_model.get("cells", []):
			if not cell_value is Dictionary:
				continue
			var cell: Dictionary = cell_value
			if bool(cell.get("selected", false)):
				return String(cell.get("item_id", ""))

	# Bounded fallback for the initial snapshot before the shell has rendered.
	if m3_multiplayer_client_runtime == null or _m4_item_graph_snapshot.is_empty():
		return ""
	var player_id := String(m3_multiplayer_client_runtime.get_local_player_id())
	var inventories_value = _m4_item_graph_snapshot.get("inventories", {})
	if not inventories_value is Dictionary:
		return ""
	var inventory_value = Dictionary(inventories_value).get(player_id, {})
	if not inventory_value is Dictionary:
		return ""
	var inventory: Dictionary = inventory_value
	var hotbar_value = inventory.get("hotbar", [])
	if not hotbar_value is Array:
		return ""
	var hotbar: Array = hotbar_value
	var selected_index := int(inventory.get("selected_hotbar_index", 0))
	if selected_index < 0 or selected_index >= hotbar.size():
		return ""
	return String(hotbar[selected_index])


func _mvp_command_result(result: Dictionary, success_text: String) -> Dictionary:
	if bool(result.get("success", false)):
		return {"success": true, "output": success_text, "details": result}
	return {
		"success": false,
		"output": "Ошибка Item Graph: %s" % String(
			result.get("error_code", result.get("output", "UNKNOWN"))
		),
		"details": result,
	}


func create_m3_graphical_client_report() -> Dictionary:
	var report: Dictionary = super.create_m3_graphical_client_report()
	report["presentation_mode"] = (
		"NX4_PREDICTED_EARTH_SURFACE"
		if _mvp_prediction_enabled
		else "LEGACY_AUTHORITATIVE_EARTH_SURFACE"
	)
	report["prediction_enabled"] = _mvp_prediction_enabled
	report["prediction_updates"] = _mvp_prediction_updates
	report["prediction_failures"] = _mvp_prediction_failures
	report["playable_surface_biome"] = _mvp_surface_biome
	report["playable_surface_eye_altitude_m"] = MVP_SURFACE_EYE_ALTITUDE_M
	report["playable_surface_vertical_offset_m"] = _mvp_local_vertical_offset_m
	report["playable_surface_anchor_direction"] = [
		_mvp_surface_anchor_direction.x,
		_mvp_surface_anchor_direction.y,
		_mvp_surface_anchor_direction.z,
	]
	report["inventory_visible"] = _mvp_inventory_visible
	report["inventory_convergence"] = {
		"checkpoint": "V0-I1",
		"ready": _mvp_inventory_shell != null and is_instance_valid(_mvp_inventory_shell),
		"setup_error": _mvp_inventory_setup_error,
		"shell": (
			_mvp_inventory_shell.get_report()
			if _mvp_inventory_shell != null and is_instance_valid(_mvp_inventory_shell)
			else {}
		),
	}
	report["spectator_enabled"] = _mvp_spectator_enabled
	report["spectator_body_visible"] = (
		_mvp_local_body != null
		and is_instance_valid(_mvp_local_body)
		and _mvp_local_body.visible
	)
	return report
