extends "res://scripts/app/earth_app.gd"

# V0 Earth is a playable tangent-plane projection over the canonical procedural
# planet. The server keeps authoritative M3 X/Z state; this adapter maps it to a
# deterministic land patch and consumes the already accepted NX4 prediction
# presentation instead of snapping the camera to 20 Hz authoritative updates.

const MVP_SURFACE_EYE_ALTITUDE_M := 1.75
const MVP_PREFERRED_BIOMES: Array[String] = ["grassland", "forest", "desert"]
const MVP_SPECTATOR_SPEED_MPS := 25.0
const MVP_LOCAL_BODY_VISUAL_OFFSET_M := -0.85
const LIVE2_MINING_TOOL_DEFINITION_ID := "item/tool/mining"
const LIVE2_MINING_TOOL_SLOT_ID := "tool/main"
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
var _live2_status_layer: CanvasLayer
var _live2_status_root: Control
var _live2_connection_label: Label
var _live2_action_label: Label
var _live2_connection_state := "CONNECTING"
var _live2_last_action_text := ""
var _live2_action_hide_at_msec := 0
var _live2_build_mode := false
var _live2_pending_actions: Dictionary = {}
var _live2_async_results := 0
var _live2_async_rejections := 0

# R3.4 external automation is an opt-in input source only. It does not create
# a second movement authority: the resulting intent still passes through the
# existing prediction -> network input -> authoritative server path.
var _automation_movement_enabled := false
var _automation_movement_expires_ms := 0
var _automation_movement_intent: Dictionary = {}
var _automation_jump_pending := false
var _automation_movement_updates := 0
var _automation_expirations := 0


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
	_live2_pending_actions.clear()
	_automation_movement_enabled = false
	_automation_movement_expires_ms = 0
	_automation_movement_intent.clear()
	_automation_jump_pending = false
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
	if runtime != null and runtime.has_signal("command_result_received"):
		var async_callback := Callable(self, "_on_live2_async_command_result")
		if not runtime.is_connected("command_result_received", async_callback):
			runtime.connect("command_result_received", async_callback)

	var inventory_setup: Dictionary = _ensure_mvp_inventory_shell(runtime)
	if not bool(inventory_setup.get("success", false)):
		return inventory_setup
	_ensure_mvp_local_body()
	_update_mvp_local_body_visual()
	_ensure_live2_status_overlay()
	set_network_connection_status("CONNECTED", {"source": "attach_m3_multiplayer_client"})

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
		"id": "player.primary",
		"description": "Основное действие LIVE.2: interact либо placement в build mode.",
		"usage": "player.primary",
		"category": "gameplay",
	}, Callable(self, "_command_live2_primary"))
	_register_command(registry, owner_id, {
		"id": "construction.mode.toggle",
		"description": "Включить/выключить режим постановки выбранного основания.",
		"usage": "construction.mode.toggle",
		"category": "construction",
	}, Callable(self, "_command_live2_build_mode_toggle"))
	_register_command(registry, owner_id, {
		"id": "construction.place",
		"description": "Поставить выбранное canonical основание перед игроком.",
		"usage": "construction.place",
		"category": "construction",
	}, Callable(self, "_command_live2_place_selected"))
	_register_command(registry, owner_id, {
		"id": "tool.mining.equip",
		"description": "Экипировать канонический добывающий инструмент.",
		"usage": "tool.mining.equip",
		"category": "gameplay",
	}, Callable(self, "_command_live2_equip_mining_tool"))
	_register_command(registry, owner_id, {
		"id": "construction.build.next",
		"description": "Построить следующий канонический этап MVP-базы из ресурсов игрока.",
		"usage": "construction.build.next",
		"category": "construction",
	}, Callable(self, "_command_live2_build_next_stage"))
	_register_command(registry, owner_id, {
		"id": "network.reconnect",
		"description": "Немедленно повторить подключение к текущему server.",
		"usage": "network.reconnect",
		"category": "network",
	}, Callable(self, "_command_live2_reconnect"))
	_register_command(registry, owner_id, {
		"id": "network.jitter.snapshot",
		"description": "Показать read-only local prediction и remote interpolation метрики.",
		"usage": "network.jitter.snapshot",
		"category": "network",
	}, Callable(self, "_command_live2_jitter_snapshot"))
	_register_command(registry, owner_id, {
		"id": "player.spectator.toggle",
		"description": "Отделить spectator-камеру от тела игрока или вернуться в тело.",
		"usage": "player.spectator.toggle",
		"category": "player",
	}, Callable(self, "_command_mvp_spectator_toggle"))


func _process(delta: float) -> void:
	super._process(delta)
	if (
		_live2_action_label != null
		and _live2_action_label.visible
		and _live2_action_hide_at_msec > 0
		and Time.get_ticks_msec() >= _live2_action_hide_at_msec
	):
		_live2_action_label.visible = false
		_live2_action_hide_at_msec = 0
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

	var intent: Dictionary = {}
	if _automation_movement_enabled:
		if Time.get_ticks_msec() >= _automation_movement_expires_ms:
			_automation_movement_enabled = false
			_automation_movement_intent.clear()
			_automation_jump_pending = false
			_automation_expirations += 1
			_submit_mvp_neutral_input()
			return
		intent = _automation_movement_intent.duplicate(true)
		intent["jump_pressed"] = _automation_jump_pending
		_automation_jump_pending = false
		intent["delta_seconds"] = maxf(delta, 0.000001)
	else:
		var input_vector: Vector2 = Input.get_vector(
			"move_left",
			"move_right",
			"move_forward",
			"move_back"
		)
		intent = {
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


func automation_set_movement_intent(params: Dictionary) -> Dictionary:
	if not _m3_attached or m3_multiplayer_client_runtime == null:
		return {"success": false, "error_code": "AUTOMATION_NETWORK_RUNTIME_NOT_READY"}
	if _mvp_spectator_enabled:
		return {"success": false, "error_code": "AUTOMATION_MOVEMENT_BLOCKED_BY_SPECTATOR"}
	if _mvp_inventory_visible:
		return {"success": false, "error_code": "AUTOMATION_MOVEMENT_BLOCKED_BY_INVENTORY"}

	var move_x_value = params.get("move_x", 0.0)
	var move_z_value = params.get("move_z", 0.0)
	var look_yaw_value = params.get(
		"look_yaw",
		earth_explorer.get_surface_relative_yaw() if earth_explorer != null else 0.0
	)
	var look_pitch_value = params.get("look_pitch", 0.0)
	for value in [move_x_value, move_z_value, look_yaw_value, look_pitch_value]:
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
			return {"success": false, "error_code": "AUTOMATION_MOVEMENT_NUMBER_REQUIRED"}
		if is_nan(float(value)) or is_inf(float(value)):
			return {"success": false, "error_code": "AUTOMATION_MOVEMENT_NUMBER_INVALID"}

	var move_x := clampf(float(move_x_value), -1.0, 1.0)
	var move_z := clampf(float(move_z_value), -1.0, 1.0)
	var look_yaw := wrapf(float(look_yaw_value), -PI, PI)
	var look_pitch := clampf(float(look_pitch_value), -1.45, 1.45)
	var sprint := bool(params.get("sprint", false))
	var jump := bool(params.get("jump", false))
	var ttl_ms := clampi(int(params.get("ttl_ms", 750)), 100, 10000)

	if earth_explorer != null and earth_explorer.has_method("set_network_surface_view"):
		var view_result: Dictionary = earth_explorer.set_network_surface_view(
			look_yaw, look_pitch
		)
		if not bool(view_result.get("success", false)):
			return view_result

	_automation_movement_intent = {
		"move_x": move_x,
		"move_z": move_z,
		"look_yaw": look_yaw,
		"look_pitch": look_pitch,
		"sprint": sprint,
	}
	_automation_jump_pending = _automation_jump_pending or jump
	_automation_movement_enabled = true
	_automation_movement_expires_ms = Time.get_ticks_msec() + ttl_ms
	_automation_movement_updates += 1
	return {
		"success": true,
		"error_code": "",
		"details": automation_get_state(),
	}


func automation_stop_movement() -> Dictionary:
	var was_enabled := _automation_movement_enabled
	_automation_movement_enabled = false
	_automation_movement_expires_ms = 0
	_automation_movement_intent.clear()
	_automation_jump_pending = false
	if was_enabled:
		_submit_mvp_neutral_input()
	return {
		"success": true,
		"error_code": "",
		"details": automation_get_state(),
	}


func automation_set_view(params: Dictionary) -> Dictionary:
	if earth_explorer == null or not earth_explorer.has_method("set_network_surface_view"):
		return {"success": false, "error_code": "AUTOMATION_VIEW_NOT_READY"}
	var yaw_value = params.get("yaw", earth_explorer.get_surface_relative_yaw())
	var pitch_value = params.get("pitch", 0.0)
	if typeof(yaw_value) not in [TYPE_INT, TYPE_FLOAT] or typeof(pitch_value) not in [TYPE_INT, TYPE_FLOAT]:
		return {"success": false, "error_code": "AUTOMATION_VIEW_NUMBER_REQUIRED"}
	if (
		is_nan(float(yaw_value))
		or is_inf(float(yaw_value))
		or is_nan(float(pitch_value))
		or is_inf(float(pitch_value))
	):
		return {"success": false, "error_code": "AUTOMATION_VIEW_NUMBER_INVALID"}
	return earth_explorer.set_network_surface_view(float(yaw_value), float(pitch_value))


func automation_get_state() -> Dictionary:
	var gameplay_snapshot: Dictionary = {}
	var item_graph: Dictionary = {}
	var resource_mining: Dictionary = {}
	var construction: Dictionary = {}
	var local_player: Dictionary = {}
	var construction_construct_checksums: Dictionary = {}
	if m3_multiplayer_client_runtime != null:
		if m3_multiplayer_client_runtime.has_method("get_snapshot"):
			gameplay_snapshot = m3_multiplayer_client_runtime.get_snapshot()
		if m3_multiplayer_client_runtime.has_method("get_item_graph_snapshot"):
			item_graph = m3_multiplayer_client_runtime.get_item_graph_snapshot()
		if m3_multiplayer_client_runtime.has_method("get_resource_mining_snapshot"):
			resource_mining = m3_multiplayer_client_runtime.get_resource_mining_snapshot()
		if m3_multiplayer_client_runtime.has_method("get_construction_bundle"):
			construction = m3_multiplayer_client_runtime.get_construction_bundle()
		if m3_multiplayer_client_runtime.has_method("get_local_player_record"):
			local_player = m3_multiplayer_client_runtime.get_local_player_record()
	for snapshot_value in construction.get("constructs", []):
		if not snapshot_value is Dictionary:
			continue
		var construct: Dictionary = snapshot_value
		var construct_id := String(construct.get("construct_id", ""))
		var construct_checksum := String(construct.get("checksum", ""))
		if not construct_id.is_empty() and not construct_checksum.is_empty():
			construction_construct_checksums[construct_id] = construct_checksum
	return {
		"schema": "dws.live3.automation.product_state.v1",
		"movement_enabled": _automation_movement_enabled,
		"expires_in_ms": (
			maxi(_automation_movement_expires_ms - Time.get_ticks_msec(), 0)
			if _automation_movement_enabled else 0
		),
		"movement_intent": _automation_movement_intent.duplicate(true),
		"jump_pending": _automation_jump_pending,
		"movement_updates": _automation_movement_updates,
		"expirations": _automation_expirations,
		"input_owner": _mvp_input_owner,
		"inventory_visible": _mvp_inventory_visible,
		"build_mode": _live2_build_mode,
		"connection_state": _live2_connection_state,
		"logical_player_id": String(local_player.get("logical_player_id", "")),
		"player_entity_id": String(local_player.get("player_entity_id", "")),
		"ownership_epoch": int(local_player.get("ownership_epoch", 0)),
		"local_player": local_player.duplicate(true),
		"gameplay_revision": int(gameplay_snapshot.get("revision", -1)),
		"gameplay_checksum": String(gameplay_snapshot.get("checksum", "")),
		"item_graph_revision": int(item_graph.get("revision", -1)),
		"item_graph_checksum": String(item_graph.get("checksum", "")),
		"resource_generation": int(resource_mining.get("generation", -1)),
		"resource_checksum": String(resource_mining.get("checksum", "")),
		"construction_generation": int(construction.get("server_generation", -1)),
		"construction_checksum": String(construction.get("checksum", "")),
		"construction_construct_checksums": construction_construct_checksums.duplicate(true),
	}


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
		var empty := {"success": false, "output": "В выбранном слоте хотбара нет предмета"}
		_show_live2_action_feedback(String(empty["output"]), false)
		return empty
	return _submit_live2_item_action_async(
		"item.drop",
		{"item_id": item_id, "quantity": -1},
		{
			"kind": "item_drop",
			"pending_text": "Выбрасываем предмет…",
			"success_text": "Предмет выброшен",
			"error_prefix": "Выбросить предмет",
		}
	)


func _command_live2_primary(_arguments: Array[String]) -> Dictionary:
	if _mvp_inventory_visible:
		return {"success": false, "output": "Закройте инвентарь перед действием"}
	if _live2_build_mode:
		return _command_live2_place_selected([])
	return execute_runtime_command("player.interact")


func _command_live2_build_mode_toggle(_arguments: Array[String]) -> Dictionary:
	_live2_build_mode = not _live2_build_mode
	var selected := _get_mvp_selected_hotbar_item_id()
	var item := _live2_item_by_id(selected)
	var definition := String(item.get("definition_id", ""))
	var text := (
		"BUILD MODE · LMB — поставить основание · B — выйти"
		if _live2_build_mode
		else "BUILD MODE выключен"
	)
	if _live2_build_mode and definition != "item/mount-base":
		text = "BUILD MODE · выберите Основание (обычно слот 2) · LMB"
	_show_live2_action_feedback(text, true, 5000)
	return {
		"success": true,
		"output": text,
		"build_mode": _live2_build_mode,
		"selected_definition_id": definition,
	}


func _command_live2_place_selected(_arguments: Array[String]) -> Dictionary:
	var item_id := _get_mvp_selected_hotbar_item_id()
	var item := _live2_item_by_id(item_id)
	if String(item.get("definition_id", "")) != "item/mount-base":
		item = _find_live2_inventory_item("item/mount-base")
		item_id = String(item.get("item_id", ""))
	if item_id.is_empty():
		var missing := {
			"success": false,
			"output": "Основание не найдено в инвентаре",
		}
		_show_live2_action_feedback(String(missing["output"]), false)
		return missing
	return _submit_live2_item_action_async(
		"item.place",
		{"item_id": item_id},
		{
			"kind": "item_place",
			"pending_text": "Устанавливаем основание…",
			"success_text": "Основание установлено",
			"error_prefix": "Установка основания",
		}
	)


func _live2_item_by_id(item_id: String) -> Dictionary:
	if item_id.is_empty():
		return {}
	for item_value in _m4_item_graph_snapshot.get("items", []):
		if item_value is Dictionary and String(Dictionary(item_value).get("item_id", "")) == item_id:
			return Dictionary(item_value).duplicate(true)
	return {}


func _find_live2_inventory_item(definition_id: String) -> Dictionary:
	if m3_multiplayer_client_runtime == null:
		return {}
	var player_id := String(m3_multiplayer_client_runtime.get_local_player_id())
	for item_value in _m4_item_graph_snapshot.get("items", []):
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		if String(item.get("definition_id", "")) != definition_id:
			continue
		var location_value = item.get("location", {})
		if (
			location_value is Dictionary
			and String(Dictionary(location_value).get("kind", "")) == "INVENTORY"
			and String(Dictionary(location_value).get("player_id", "")) == player_id
		):
			return item.duplicate(true)
	return {}


func is_mvp_inventory_visible() -> bool:
	return _mvp_inventory_visible


func set_network_connection_status(state: String, details: Dictionary = {}) -> void:
	_ensure_live2_status_overlay()
	_live2_connection_state = state.strip_edges().to_upper()
	var suffix := ""
	if _live2_connection_state == "RECONNECTING":
		var attempt := int(details.get("attempt", 0))
		suffix = " · попытка %d" % attempt if attempt > 0 else ""
	elif _live2_connection_state in ["FAILED", "DISCONNECTED"]:
		var reason := String(details.get("reason", details.get("error_code", "")))
		if not reason.is_empty():
			suffix = " · %s" % reason
	var title := "Связь: %s%s" % [_live2_connection_state, suffix]
	_live2_connection_label.text = title
	match _live2_connection_state:
		"CONNECTED":
			_live2_connection_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55))
		"CONNECTING", "RECONNECTING":
			_live2_connection_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
		_:
			_live2_connection_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_live2_connection_label.visible = true


func show_network_error(error_code: String, details: Dictionary = {}) -> void:
	set_network_connection_status("DISCONNECTED", {
		"reason": error_code,
		"details": details.duplicate(true),
	})
	_show_live2_action_feedback(
		"Связь потеряна · выполняется переподключение",
		false,
		5000
	)


func _ensure_live2_status_overlay() -> void:
	if _live2_status_layer != null and is_instance_valid(_live2_status_layer):
		return
	_live2_status_layer = CanvasLayer.new()
	_live2_status_layer.name = "V0Live2Status"
	_live2_status_layer.layer = 90
	add_child(_live2_status_layer)
	_live2_status_root = Control.new()
	_live2_status_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_live2_status_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live2_status_layer.add_child(_live2_status_root)

	_live2_connection_label = Label.new()
	_live2_connection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_live2_connection_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_live2_connection_label.offset_left = -520.0
	_live2_connection_label.offset_right = -18.0
	_live2_connection_label.offset_top = 16.0
	_live2_connection_label.offset_bottom = 52.0
	_live2_connection_label.add_theme_font_size_override("font_size", 18)
	_live2_connection_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_live2_connection_label.add_theme_constant_override("outline_size", 4)
	_live2_connection_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live2_status_root.add_child(_live2_connection_label)

	_live2_action_label = Label.new()
	_live2_action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_live2_action_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_live2_action_label.offset_left = -420.0
	_live2_action_label.offset_right = 420.0
	_live2_action_label.offset_top = -170.0
	_live2_action_label.offset_bottom = -125.0
	_live2_action_label.add_theme_font_size_override("font_size", 19)
	_live2_action_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_live2_action_label.add_theme_constant_override("outline_size", 4)
	_live2_action_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live2_action_label.visible = false
	_live2_status_root.add_child(_live2_action_label)


func _show_live2_action_feedback(
	text: String,
	success: bool = true,
	duration_msec: int = 2800
) -> void:
	_ensure_live2_status_overlay()
	_live2_last_action_text = text
	_live2_action_label.text = text
	_live2_action_label.add_theme_color_override(
		"font_color",
		Color(0.72, 1.0, 0.78) if success else Color(1.0, 0.5, 0.42)
	)
	_live2_action_label.visible = not text.is_empty()
	_live2_action_hide_at_msec = (
		Time.get_ticks_msec() + duration_msec
		if not text.is_empty() and duration_msec > 0
		else 0
	)


func _submit_live2_item_action_async(
	command_type: String,
	payload: Dictionary,
	context: Dictionary
) -> Dictionary:
	var result: Dictionary = m4_execute_item_command_async(command_type, payload)
	if not bool(result.get("success", false)):
		var send_error := String(result.get("error_code", "ASYNC_ITEM_SEND_FAILED"))
		_show_live2_action_feedback(
			"%s: %s" % [String(context.get("error_prefix", "Команда")), send_error],
			false,
			4200
		)
		return result
	var operation_id := String(result.get("details", {}).get(
		"operation_id",
		result.get("operation_id", "")
	))
	if operation_id.is_empty():
		return {"success": false, "error_code": "ASYNC_OPERATION_ID_MISSING"}
	_track_live2_async_action(operation_id, context)
	_show_live2_action_feedback(
		String(context.get("pending_text", "Команда отправлена…")),
		true,
		2400
	)
	return {
		"success": true,
		"operation_id": operation_id,
		"pending": true,
		"output": String(context.get("pending_text", "Команда отправлена…")),
	}


func _track_live2_async_action(operation_id: String, context: Dictionary) -> void:
	if operation_id.is_empty():
		return
	_live2_pending_actions[operation_id] = context.duplicate(true)


func _on_live2_async_command_result(result: Dictionary) -> void:
	_live2_async_results += 1
	var operation_id := String(result.get("operation_id", ""))
	var context: Dictionary = Dictionary(
		_live2_pending_actions.get(operation_id, {})
	).duplicate(true)
	if not context.is_empty():
		_live2_pending_actions.erase(operation_id)
		var succeeded := String(result.get("status", "")) == "SUCCEEDED"
		if succeeded:
			_show_live2_action_feedback(
				String(context.get("success_text", "Команда подтверждена сервером")),
				true,
				3200
			)
		else:
			_live2_async_rejections += 1
			_show_live2_action_feedback(
				"%s: %s" % [
					String(context.get("error_prefix", "Команда")),
					String(result.get("error_code", "REJECTED")),
				],
				false,
				5000
			)
	_handle_live2_async_command_extension(result, context)


func _handle_live2_async_command_extension(
	_result: Dictionary,
	_context: Dictionary
) -> void:
	pass


func _find_live2_mining_tool() -> Dictionary:
	return _find_live2_inventory_item(LIVE2_MINING_TOOL_DEFINITION_ID)


func _live2_mining_tool_is_equipped() -> bool:
	var tool := _find_live2_mining_tool()
	if tool.is_empty():
		return false
	var equipment_value = tool.get("equipment", {})
	return (
		equipment_value is Dictionary
		and String(Dictionary(equipment_value).get("player_id", ""))
			== String(m3_multiplayer_client_runtime.get_local_player_id())
		and String(Dictionary(equipment_value).get("slot_id", ""))
			== LIVE2_MINING_TOOL_SLOT_ID
	)


func ensure_live2_mining_tool_equipped() -> Dictionary:
	# Blocking compatibility seam retained for deterministic integration tests.
	if _live2_mining_tool_is_equipped():
		return {"success": true, "already_equipped": true}
	var tool := _find_live2_mining_tool()
	if tool.is_empty():
		return {"success": false, "error_code": "LIVE2_MINING_TOOL_NOT_IN_INVENTORY"}
	var result := m4_execute_item_command("item.equip", {
		"item_id": String(tool.get("item_id", "")),
		"slot_id": LIVE2_MINING_TOOL_SLOT_ID,
	})
	if bool(result.get("success", false)):
		_show_live2_action_feedback("Добывающий инструмент экипирован", true)
	else:
		_show_live2_action_feedback(
			"Не удалось экипировать инструмент: %s" % String(result.get("error_code", "UNKNOWN")),
			false
		)
	return result


func ensure_live2_mining_tool_equipped_async(context: Dictionary = {}) -> Dictionary:
	if _live2_mining_tool_is_equipped():
		return {
			"success": true,
			"already_equipped": true,
			"pending": false,
		}
	var tool := _find_live2_mining_tool()
	if tool.is_empty():
		var missing := {
			"success": false,
			"error_code": "LIVE2_MINING_TOOL_NOT_IN_INVENTORY",
		}
		_show_live2_action_feedback("Добывающий инструмент не найден", false)
		return missing
	var action_context := context.duplicate(true)
	if String(action_context.get("kind", "")).is_empty():
		action_context["kind"] = "tool_equip"
	if String(action_context.get("pending_text", "")).is_empty():
		action_context["pending_text"] = "Экипируем добывающий инструмент…"
	if String(action_context.get("success_text", "")).is_empty():
		action_context["success_text"] = "Добывающий инструмент экипирован"
	if String(action_context.get("error_prefix", "")).is_empty():
		action_context["error_prefix"] = "Экипировка инструмента"
	return _submit_live2_item_action_async(
		"item.equip",
		{
			"item_id": String(tool.get("item_id", "")),
			"slot_id": LIVE2_MINING_TOOL_SLOT_ID,
		},
		action_context
	)


func _command_live2_equip_mining_tool(_arguments: Array[String]) -> Dictionary:
	return ensure_live2_mining_tool_equipped_async()


func _command_live2_build_next_stage(_arguments: Array[String]) -> Dictionary:
	if _mvp_inventory_shell == null or not is_instance_valid(_mvp_inventory_shell):
		var missing := {"success": false, "output": "Construction UI ещё не готов"}
		_show_live2_action_feedback(String(missing["output"]), false)
		return missing
	if not _mvp_inventory_shell.has_method("build_next_stage_async"):
		var unavailable := {"success": false, "output": "Construction async action недоступен"}
		_show_live2_action_feedback(String(unavailable["output"]), false)
		return unavailable
	var result: Dictionary = _mvp_inventory_shell.build_next_stage_async()
	if not bool(result.get("success", false)):
		var failed := {
			"success": false,
			"output": "Стройка: %s" % String(result.get("error_code", "UNKNOWN")),
			"details": result,
		}
		_show_live2_action_feedback(String(failed["output"]), false, 4200)
		return failed
	var operation_id := String(result.get("details", {}).get("operation_id", ""))
	if not operation_id.is_empty():
		_track_live2_async_action(operation_id, {
			"kind": "construction_stage",
			"pending_text": "Этап строительства отправлен · игра продолжается",
			"success_text": "Этап строительства подтверждён сервером",
			"error_prefix": "Стройка",
		})
	_show_live2_action_feedback("Этап строительства отправлен · игра продолжается", true, 2600)
	return {
		"success": true,
		"output": "Этап строительства отправлен",
		"operation_id": operation_id,
		"pending": true,
		"details": result,
	}


func _command_live2_jitter_snapshot(_arguments: Array[String]) -> Dictionary:
	if m3_multiplayer_client_runtime == null:
		return {"success": false, "output": "Network runtime недоступен"}
	var runtime_report: Dictionary = m3_multiplayer_client_runtime.get_report()
	var client_prediction: Dictionary = Dictionary(
		runtime_report.get("client_prediction", {})
	)
	var prediction: Dictionary = Dictionary(client_prediction.get("runtime", {}))
	var local := {
		"last_error_m": float(prediction.get("last_error_m", 0.0)),
		"maximum_error_m": float(prediction.get("maximum_error_m", 0.0)),
		"correction_mode": String(prediction.get("last_correction_mode", "NONE")),
		"hard_corrections": int(prediction.get("hard_corrections", 0)),
		"history_miss_resets": int(prediction.get("history_miss_resets", 0)),
		"ticks_replayed": int(prediction.get("ticks_replayed", 0)),
		"visual_offset_m": float(prediction.get("visual_offset_m", 0.0)),
		"submit_failures": int(client_prediction.get("submit_failures", 0)),
		"reconcile_failures": int(client_prediction.get("reconcile_failures", 0)),
	}
	var earth_report: Dictionary = create_m3_graphical_client_report()
	var remote_reports: Dictionary = Dictionary(
		earth_report.get("remote_presenters", {})
	)
	var remotes: Dictionary = {}
	for logical_id_value in remote_reports.keys():
		var logical_id := String(logical_id_value)
		var remote: Dictionary = Dictionary(remote_reports[logical_id_value])
		var interpolation: Dictionary = Dictionary(remote.get("interpolation", {}))
		remotes[logical_id] = {
			"mode": String(remote.get("interpolation_mode", "UNKNOWN")),
			"buffer_size": int(interpolation.get("buffer_size", 0)),
			"interpolation_samples": int(interpolation.get("interpolation_samples", 0)),
			"extrapolation_samples": int(interpolation.get("extrapolation_samples", 0)),
			"hold_samples": int(interpolation.get("hold_samples", 0)),
			"buffering_samples": int(interpolation.get("buffering_samples", 0)),
			"identity_resets": int(interpolation.get("identity_resets", 0)),
			"teleport_segments": int(interpolation.get("teleport_segments", 0)),
			"max_snapshot_interval_ms": int(remote.get("max_snapshot_interval_ms", 0)),
			"max_accepted_sample_interval_ms": int(remote.get("max_accepted_sample_interval_ms", 0)),
			"max_presenter_arrival_interval_ms": int(remote.get("max_presenter_arrival_interval_ms", 0)),
			"snapshot_clock_source": String(remote.get("snapshot_clock_source", "")),
			"snapshot_clock_context": Dictionary(remote.get("snapshot_clock_context", {})).duplicate(true),
			"presenter_arrivals": int(remote.get("presenter_arrivals", 0)),
			"accepted_presenter_samples": int(remote.get("accepted_presenter_samples", 0)),
			"duplicate_presenter_samples": int(remote.get("duplicate_presenter_samples", 0)),
			"stale_presenter_samples": int(remote.get("stale_presenter_samples", 0)),
			"rejected_presenter_samples": int(remote.get("rejected_presenter_samples", 0)),
			"sample_mode_time_ms": Dictionary(remote.get("sample_mode_time_ms", {})).duplicate(true),
			"render_frames": int(remote.get("render_frames", 0)),
			"long_render_frames": int(remote.get("long_render_frames", 0)),
			"max_render_delta_ms": float(remote.get("max_render_delta_ms", 0.0)),
		}
	var snapshot := {
		"local": local,
		"remotes": remotes,
		"connection_state": _live2_connection_state,
		"async_pending": _live2_pending_actions.size(),
	}
	return {
		"success": true,
		"output": JSON.stringify(snapshot),
		"jitter": snapshot,
	}


func _command_live2_reconnect(_arguments: Array[String]) -> Dictionary:
	if m3_multiplayer_client_runtime == null or not m3_multiplayer_client_runtime.has_method("request_reconnect_now"):
		return {"success": false, "output": "Reconnect runtime недоступен"}
	var result: Dictionary = m3_multiplayer_client_runtime.request_reconnect_now()
	_show_live2_action_feedback(
		"Повторное подключение запрошено",
		bool(result.get("success", false))
	)
	return _mvp_command_result(result, "Повторное подключение запрошено")


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
	report["live2_async_gameplay"] = {
		"pending": _live2_pending_actions.size(),
		"results": _live2_async_results,
		"rejections": _live2_async_rejections,
	}
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
	report["live2_connection_state"] = _live2_connection_state
	report["live2_last_action_text"] = _live2_last_action_text
	report["live2_mining_tool_equipped"] = _live2_mining_tool_is_equipped()
	report["live2_build_mode"] = _live2_build_mode
	report["automation_input"] = automation_get_state()
	report["spectator_enabled"] = _mvp_spectator_enabled
	report["spectator_body_visible"] = (
		_mvp_local_body != null
		and is_instance_valid(_mvp_local_body)
		and _mvp_local_body.visible
	)
	return report
