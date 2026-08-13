extends Node3D

const EarthWorldScript = preload(
	"res://scripts/world/earth/procedural_earth_world.gd"
)
const CelestialSystemScript = preload(
	"res://scripts/world/planetary/celestial_system.gd"
)
const EarthExplorerScript = preload(
	"res://scripts/actors/earth/earth_explorer.gd"
)
const AtmosphereManagerScript = preload(
	"res://scripts/world/atmosphere/atmosphere_manager.gd"
)
const PlanetaryOverlayScript = preload(
	"res://scripts/ui/planetary_overlay.gd"
)
const LoggerScript = preload(
	"res://scripts/diagnostics/lunar_logger.gd"
)
const RemotePlayerPresenterScript = preload(
	"res://scripts/app/earth_m3_remote_spectator_presenter.gd"
)
const ConstructionPresentationScript = preload(
	"res://scripts/app/earth_construction_presentation.gd"
)

var simulator_app
var simulation_clock
var runtime_universe_id: String = "main"
var runtime_instance_id: String = "persistent"
var local_authority_id: String = "local-process"
var runtime_command_registry
var runtime_test_registry
var runtime_world_definition: Dictionary = {}
var runtime_command_owner: String = "active_world"
var runtime_test_owner: String = "active_world"
var runtime_role: String = "offline"
var presentation_enabled: bool = true
var local_input_enabled: bool = true

var logger
var celestial_system
var earth_world
var earth_explorer
var atmosphere_manager
var planetary_overlay
var initialized: bool = false
var atmosphere_initialized: bool = false
var last_diagnostic_path: String = "-"
var visible_body_ids: Array[String] = ["earth"]
var m3_multiplayer_client_runtime
var _m3_attached: bool = false
var _m3_remote_presenters: Dictionary = {}
var _m3_local_sync_count: int = 0
var _m3_remote_spawn_count: int = 0
var _m3_remote_despawn_count: int = 0
var _m3_remote_update_count: int = 0
var _m3_input_accumulator: float = 0.0
var _m3_local_planar_position := Vector2.ZERO
var _m4_item_graph_snapshot: Dictionary = {}
var _m4_item_snapshot_updates: int = 0
var _m4_item_commands: int = 0
var _m4_item_rejections: int = 0
var construction_presentation


func configure_runtime(context: Dictionary) -> void:
	simulator_app = context.get("simulator_app")
	simulation_clock = context.get("simulation_clock")
	runtime_universe_id = String(context.get("universe_id", runtime_universe_id))
	runtime_instance_id = String(context.get("instance_id", runtime_instance_id))
	local_authority_id = String(context.get("local_authority_id", local_authority_id))
	runtime_command_registry = context.get("command_registry")
	runtime_test_registry = context.get("test_registry")
	runtime_world_definition = context.get("world_definition", {}).duplicate(true)
	runtime_command_owner = String(
		context.get("command_owner_id", runtime_command_owner)
	)
	runtime_test_owner = String(context.get("test_owner_id", runtime_test_owner))
	runtime_role = String(context.get("runtime_role", runtime_role))
	presentation_enabled = bool(context.get("presentation_enabled", true))
	local_input_enabled = bool(context.get("local_input_enabled", true))


func _ready() -> void:
	if simulator_app == null:
		_ensure_input_actions()
	logger = LoggerScript.new()
	logger.name = "EarthRuntimeLogger"
	add_child(logger)
	logger.setup(false)

	celestial_system = CelestialSystemScript.new()
	celestial_system.name = "EarthCelestialSystem"
	add_child(celestial_system)
	if not celestial_system.setup(
		visible_body_ids,
		simulation_clock,
		runtime_instance_id
	):
		push_error("Earth runtime failed to initialize its celestial system.")
		return

	earth_world = EarthWorldScript.new()
	earth_world.name = "ProceduralEarthWorld"
	add_child(earth_world)
	if not earth_world.setup(logger):
		push_error("Earth runtime failed to initialize procedural terrain.")
		return

	earth_explorer = EarthExplorerScript.new()
	earth_explorer.name = "EarthExplorer"
	add_child(earth_explorer)
	earth_explorer.setup(earth_world, celestial_system, null)
	if presentation_enabled:
		construction_presentation = ConstructionPresentationScript.new()
		construction_presentation.name = "EarthConstructionPresentation"
		add_child(construction_presentation)
		construction_presentation.setup("client/earth/%s" % runtime_instance_id.replace("/", "-"))

	atmosphere_manager = AtmosphereManagerScript.new()
	atmosphere_manager.name = "AtmosphereManager"
	add_child(atmosphere_manager)
	atmosphere_initialized = atmosphere_manager.setup(
		celestial_system,
		{"earth": earth_world},
		null,
		logger
	)

	planetary_overlay = PlanetaryOverlayScript.new()
	planetary_overlay.name = "EarthOverlay"
	add_child(planetary_overlay)
	planetary_overlay.setup()

	initialized = true
	_spawn_explorer_at_canonical_spawn()
	earth_world.set_primary_lighting_enabled(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	logger.info("application", "earth_runtime_ready", {
		"world_id": get_runtime_id(),
		"body_ids": celestial_system.get_body_ids(),
		"canonical_spawn": earth_world.get_canonical_spawn_snapshot(),
		"atmosphere_initialized": atmosphere_initialized,
	})


func _process(delta: float) -> void:
	if not initialized or earth_explorer == null:
		return
	var space_position: Vector3 = earth_explorer.get_world_position()
	var earth_local_position: Vector3 = celestial_system.to_body_local(
		space_position,
		"earth"
	)
	var observer_frame_id: String = earth_explorer.get_reference_frame_id()
	earth_world.basis = celestial_system.get_relative_basis(
		celestial_system.get_body_fixed_frame_id("earth"),
		observer_frame_id
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
			delta,
			observer_frame_id
		)
	if planetary_overlay != null:
		planetary_overlay.show_shared_space_mode(
			celestial_system,
			earth_world,
			null,
			earth_explorer,
			"earth",
			0.0,
			atmosphere_manager if atmosphere_initialized else null,
			visible_body_ids
		)
	_apply_m3_network_input(delta)


func register_runtime_commands(registry, owner_id: String) -> void:
	_register_command(registry, owner_id, {
		"id": "space.teleport.body",
		"description": "Перейти к поверхности тела, доступного в текущем мире.",
		"usage": "space.teleport.body earth",
		"category": "space",
	}, Callable(self, "_command_space_teleport_body"))
	_register_command(registry, owner_id, {
		"id": "earth.teleport.biome",
		"description": "Перейти к одному из контрольных биомов Земли.",
		"usage": "earth.teleport.biome <forest|grassland|desert|tundra|alpine_snow>",
		"category": "earth",
	}, Callable(self, "_command_earth_teleport_biome"))
	_register_command(registry, owner_id, {
		"id": "earth.debug.cycle",
		"description": "Переключить final/biome/elevation/ecology отображение Земли.",
		"usage": "earth.debug.cycle",
		"category": "earth",
	}, Callable(self, "_command_earth_debug_cycle"))
	_register_command(registry, owner_id, {
		"id": "earth.rules.reload",
		"description": "Перечитать procedural rules Земли из JSON.",
		"usage": "earth.rules.reload",
		"category": "earth",
	}, Callable(self, "_command_earth_rules_reload"))
	_register_command(registry, owner_id, {
		"id": "space.frame.current",
		"description": "Показать систему отсчёта наблюдателя.",
		"usage": "space.frame.current",
		"category": "space",
	}, Callable(self, "_command_space_frame_current"))
	_register_command(registry, owner_id, {
		"id": "space.frame.set",
		"description": "Сменить систему отсчёта без телепортации объекта.",
		"usage": "space.frame.set <system|earth.inertial|earth.fixed>",
		"category": "space",
	}, Callable(self, "_command_space_frame_set"))
	_register_command(registry, owner_id, {
		"id": "diagnostics.save",
		"description": "Сохранить диагностический JSON Earth runtime.",
		"usage": "diagnostics.save",
		"category": "diagnostics",
	}, Callable(self, "_command_diagnostics_save"))


func register_runtime_tests(registry, owner_id: String) -> void:
	registry.register_test({
		"id": "world.earth.boot",
		"description": "Earth runtime создал только Землю, observer и атмосферу.",
		"category": "world",
	}, Callable(self, "_test_earth_boot"), owner_id)
	registry.register_test({
		"id": "world.earth.reference_frame",
		"description": "Наблюдатель Земли хранится в body-fixed frame.",
		"category": "world",
	}, Callable(self, "_test_earth_reference_frame"), owner_id)
	registry.register_test({
		"id": "world.earth.canonical_spawn",
		"description": "Earth runtime запускает наблюдателя из неизменяемой координаты default_spawn.",
		"category": "world",
	}, Callable(self, "_test_earth_canonical_spawn"), owner_id)
	registry.register_test({
		"id": "world.earth.body_isolation",
		"description": "Каталог тел Earth runtime не содержит скрытой Луны.",
		"category": "world",
	}, Callable(self, "_test_earth_body_isolation"), owner_id)


func create_runtime_snapshot() -> Dictionary:
	return {
		"schema": "planet_simulator.earth_world_runtime.v2",
		"world_id": get_runtime_id(),
		"universe_id": runtime_universe_id,
		"instance_id": runtime_instance_id,
		"local_authority_id": local_authority_id,
		"initialized": initialized,
		"observer_position_m": _vector_to_array(
			earth_explorer.get_world_position()
			if earth_explorer != null
			else Vector3.ZERO
		),
		"observer_spatial_ref": (
			earth_explorer.get_spatial_ref() if earth_explorer != null else {}
		),
		"simulation_clock": (
			simulation_clock.create_snapshot() if simulation_clock != null else {}
		),
		"celestial_system": (
			celestial_system.create_snapshot() if celestial_system != null else {}
		),
		"earth": earth_world.create_snapshot() if earth_world != null else {},
		"canonical_spawn": (
			earth_world.get_canonical_spawn_snapshot() if earth_world != null else {}
		),
		"atmosphere": (
			atmosphere_manager.create_snapshot()
			if atmosphere_manager != null
			else {}
		),
		"last_diagnostic_path": last_diagnostic_path,
		"m3_spectator": create_m3_graphical_client_report(),
	}


func attach_m3_multiplayer_client(runtime) -> Dictionary:
	if runtime_role != "game-client":
		return {"success": false, "error_code": "M3_GAME_CLIENT_ROLE_REQUIRED"}
	if (
		runtime == null
		or not runtime.has_signal("replica_updated")
		or not runtime.has_method("get_snapshot")
		or not runtime.has_method("get_local_player_id")
		or not runtime.has_method("move_blocking")
		or not runtime.has_method("move_nonblocking")
		or not runtime.has_method("get_item_graph_snapshot")
		or not runtime.has_method("execute_item_command_blocking")
		or not runtime.has_signal("item_graph_updated")
	):
		return {"success": false, "error_code": "INVALID_M3_CLIENT_RUNTIME"}
	if _m3_attached:
		return {"success": false, "error_code": "M3_CLIENT_ALREADY_ATTACHED"}
	m3_multiplayer_client_runtime = runtime
	if not runtime.replica_updated.is_connected(_on_m3_replica_updated):
		runtime.replica_updated.connect(_on_m3_replica_updated)
	if not runtime.item_graph_updated.is_connected(_on_m4_item_graph_updated):
		runtime.item_graph_updated.connect(_on_m4_item_graph_updated)
	_m3_attached = true
	if earth_explorer != null:
		earth_explorer.set_network_replica_mode(true)
	_on_m3_replica_updated(runtime.get_snapshot())
	_on_m4_item_graph_updated(runtime.get_item_graph_snapshot())
	return {"success": true, "error_code": "", "details": {"local_player_id": runtime.get_local_player_id(), "mode": "EARTH_NETWORK_SPECTATOR", "m4_item_graph": not _m4_item_graph_snapshot.is_empty()}}


func _on_m3_replica_updated(snapshot: Dictionary) -> void:
	if not _m3_attached or m3_multiplayer_client_runtime == null:
		return
	var local_id: String = m3_multiplayer_client_runtime.get_local_player_id()
	var seen: Dictionary = {}
	for player_value in snapshot.get("players", []):
		if not player_value is Dictionary:
			continue
		var record: Dictionary = player_value
		var logical_id: String = String(record.get("logical_player_id", ""))
		if logical_id == local_id:
			if bool(record.get("connected", false)):
				_apply_m3_local_spectator_record(record)
				_m3_local_sync_count += 1
			continue
		if not bool(record.get("connected", false)):
			continue
		seen[logical_id] = true
		var presenter = _m3_remote_presenters.get(logical_id)
		if presenter == null or not is_instance_valid(presenter):
			presenter = RemotePlayerPresenterScript.new()
			add_child(presenter)
			var setup_result: Dictionary = presenter.setup(
				record, snapshot, Callable(self, "_map_m3_position_to_earth_world")
			)
			if not bool(setup_result.get("success", false)):
				presenter.queue_free()
				continue
			presenter.set_local_planar_position(_m3_local_planar_position)
			_m3_remote_presenters[logical_id] = presenter
			_m3_remote_spawn_count += 1
		else:
			presenter.set_local_planar_position(_m3_local_planar_position)
			presenter.apply_replica(record, snapshot)
		_m3_remote_update_count += 1
	for logical_id_value in _m3_remote_presenters.keys().duplicate():
		var logical_id: String = String(logical_id_value)
		if seen.has(logical_id):
			continue
		var stale_presenter = _m3_remote_presenters.get(logical_id)
		if stale_presenter != null and is_instance_valid(stale_presenter):
			stale_presenter.queue_free()
		_m3_remote_presenters.erase(logical_id)
		_m3_remote_despawn_count += 1


func _apply_m3_local_spectator_record(record: Dictionary) -> void:
	if earth_world == null or earth_explorer == null:
		return
	var position: Dictionary = record.get("position", {})
	_m3_local_planar_position = Vector2(
		float(position.get("x", 0.0)), float(position.get("z", 0.0))
	)
	var mapped_direction: Vector3 = _map_m3_position_to_earth_direction(
		float(position.get("x", 0.0)),
		float(position.get("z", 0.0))
	)
	earth_explorer.apply_network_replica_pose(
		mapped_direction,
		earth_world.get_canonical_spawn_altitude_m()
	)


func _on_m4_item_graph_updated(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	_m4_item_graph_snapshot = snapshot.duplicate(true)
	_m4_item_snapshot_updates += 1


func _map_m3_position_to_earth_direction(x: float, z: float) -> Vector3:
	var up: Vector3 = earth_world.get_canonical_spawn_direction()
	var east: Vector3 = Vector3.UP.cross(up)
	if east.length_squared() < 0.000001:
		east = Vector3.RIGHT.cross(up)
	east = east.normalized()
	var north: Vector3 = up.cross(east).normalized()
	var surface: Vector3 = earth_world.get_surface_point(up)
	return (surface + east * x + north * z).normalized()


func _map_m3_position_to_earth_world(x: float, z: float) -> Vector3:
	var direction: Vector3 = _map_m3_position_to_earth_direction(x, z)
	return earth_world.get_surface_point(direction) + direction * earth_world.get_canonical_spawn_altitude_m()


func _apply_m3_network_input(delta: float) -> void:
	if not _m3_attached or m3_multiplayer_client_runtime == null or not local_input_enabled:
		return
	if m3_multiplayer_client_runtime.has_method("is_automated_acceptance") and m3_multiplayer_client_runtime.is_automated_acceptance():
		return
	_m3_input_accumulator += delta
	if _m3_input_accumulator < 0.05:
		return
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_vector.length_squared() < 0.000001:
		return
	var step: float = minf(_m3_input_accumulator, 0.1)
	_m3_input_accumulator = 0.0
	var speed: float = 11.0 if Input.is_action_pressed("boost") else 6.0
	m3_multiplayer_client_runtime.move_nonblocking(input_vector.x * speed * step, -input_vector.y * speed * step)


func m3_apply_test_input_offset(offset: Vector3) -> Dictionary:
	if not _m3_attached or m3_multiplayer_client_runtime == null:
		return {"success": false, "error_code": "M3_GAME_CLIENT_NOT_READY"}
	return m3_multiplayer_client_runtime.move_blocking(offset.x, offset.z)


func m4_execute_item_command(
	command_type: String,
	payload: Dictionary,
	operation_id: String = ""
) -> Dictionary:
	if not _m3_attached or m3_multiplayer_client_runtime == null:
		return {"success": false, "error_code": "M4_EARTH_SPECTATOR_NOT_READY"}
	var result: Dictionary = m3_multiplayer_client_runtime.execute_item_command_blocking(
		command_type, payload, operation_id
	)
	_m4_item_commands += 1
	if not bool(result.get("success", false)):
		_m4_item_rejections += 1
	return result


func create_m3_graphical_client_report() -> Dictionary:
	var presenters: Dictionary = {}
	for logical_id_value in _m3_remote_presenters.keys():
		var presenter = _m3_remote_presenters[logical_id_value]
		if presenter != null and is_instance_valid(presenter):
			presenters[String(logical_id_value)] = presenter.get_report()
	return {
		"schema": "planet_simulator.m3_earth_spectator_report.v1",
		"world_id": get_runtime_id(),
		"runtime_role": runtime_role,
		"attached": _m3_attached,
		"spectator_ready": earth_explorer != null and earth_explorer.active,
		"local_player_id": m3_multiplayer_client_runtime.get_local_player_id() if m3_multiplayer_client_runtime != null else "",
		"local_player_position": _vector_to_array(earth_explorer.get_world_position()) if earth_explorer != null else [],
		"active_camera": String(earth_explorer.get_camera().get_path()) if earth_explorer != null and earth_explorer.get_camera() != null and earth_explorer.get_camera().current else "",
		"presentation_enabled": presentation_enabled,
		"local_input_enabled": local_input_enabled,
		"network_replica_mode": bool(earth_explorer.is_network_replica_mode()) if earth_explorer != null else false,
		"local_sync_count": _m3_local_sync_count,
		"remote_presenter_count": _m3_remote_presenters.size(),
		"remote_spawn_count": _m3_remote_spawn_count,
		"remote_despawn_count": _m3_remote_despawn_count,
		"remote_update_count": _m3_remote_update_count,
		"remote_presenters": presenters,
		"canonical_spawn": earth_world.get_canonical_spawn_snapshot() if earth_world != null else {},
		"m4_item_graph_revision": int(_m4_item_graph_snapshot.get("revision", -1)),
		"m4_item_graph_checksum": String(_m4_item_graph_snapshot.get("checksum", "")),
		"m4_item_snapshot_updates": _m4_item_snapshot_updates,
		"m4_item_commands": _m4_item_commands,
		"m4_item_rejections": _m4_item_rejections,
		"construction_presentation": construction_presentation.get_report() if construction_presentation != null else {},
		"snapshot_checksum": String(m3_multiplayer_client_runtime.get_snapshot().get("checksum", "")) if m3_multiplayer_client_runtime != null else "",
		"direct_authority_references": 0,
	}


func prepare_for_unload() -> void:
	if atmosphere_manager != null:
		atmosphere_manager.deactivate()
	if earth_explorer != null:
		earth_explorer.deactivate()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func set_runtime_mouse_capture(captured: bool) -> void:
	Input.mouse_mode = (
		Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	)


func get_runtime_id() -> String:
	return String(runtime_world_definition.get("id", "earth"))


func get_runtime_display_name() -> String:
	return String(runtime_world_definition.get("display_name", "Земля"))


func execute_runtime_command(command_line: String) -> Dictionary:
	if simulator_app != null and simulator_app.has_method("execute_command"):
		return simulator_app.execute_command(command_line)
	if runtime_command_registry != null:
		return runtime_command_registry.execute_line(command_line)
	return {"success": false, "output": "Командный реестр не подключён"}


func _command_space_teleport_body(arguments: Array[String]) -> Dictionary:
	if arguments.is_empty() or arguments[0].to_lower() != "earth":
		return {
			"success": false,
			"output": "В мире earth доступно только тело earth",
		}
	_spawn_explorer_at_canonical_spawn()
	return {"success": true, "output": "Переход к поверхности Земли"}


func _command_earth_teleport_biome(arguments: Array[String]) -> Dictionary:
	if arguments.is_empty():
		return {
			"success": false,
			"output": "Использование: earth.teleport.biome <forest|grassland|desert|tundra|alpine_snow>",
		}
	return _teleport_to_earth_biome(arguments[0].to_lower())


func _command_space_frame_current(_arguments: Array[String]) -> Dictionary:
	if earth_explorer == null:
		return {"success": false, "output": "Наблюдатель не инициализирован"}
	return {
		"success": true,
		"output": "Frame: %s" % earth_explorer.get_reference_frame_id(),
		"spatial_ref": earth_explorer.get_spatial_ref(),
	}


func _command_space_frame_set(arguments: Array[String]) -> Dictionary:
	if arguments.is_empty():
		return {"success": false, "output": "Использование: space.frame.set <system|earth.inertial|earth.fixed>"}
	var target_frame_id: String = _resolve_frame_alias(arguments[0])
	if target_frame_id.is_empty() or not earth_explorer.set_reference_frame(target_frame_id, true):
		return {"success": false, "output": "Неизвестная или недоступная система отсчёта: %s" % arguments[0]}
	return _command_space_frame_current([])


func _command_earth_debug_cycle(_arguments: Array[String]) -> Dictionary:
	if earth_world == null:
		return {"success": false, "output": "Земля не инициализирована"}
	var debug_name: String = earth_world.cycle_debug_view()
	return {"success": true, "output": "Debug-режим Земли: %s" % debug_name}


func _command_earth_rules_reload(_arguments: Array[String]) -> Dictionary:
	if earth_world == null:
		return {"success": false, "output": "Земля не инициализирована"}
	var reloaded: bool = earth_world.reload_rules()
	return {
		"success": reloaded,
		"output": "Правила Земли перечитаны" if reloaded else "Не удалось перечитать правила Земли",
	}


func _command_diagnostics_save(_arguments: Array[String]) -> Dictionary:
	last_diagnostic_path = _save_diagnostic_snapshot()
	return {
		"success": last_diagnostic_path != "ERROR",
		"output": "Диагностика: %s" % last_diagnostic_path,
	}


func _teleport_to_earth_biome(biome_name: String) -> Dictionary:
	if not initialized or earth_world == null or earth_explorer == null:
		return {"success": false, "output": "Earth runtime ещё не готов"}
	var direction: Vector3 = earth_world.find_biome_direction(biome_name)
	if direction.length_squared() < 0.5:
		return {"success": false, "output": "Биом не найден: %s" % biome_name}
	earth_explorer.activate(direction)
	return {"success": true, "output": "Биом Земли: %s" % biome_name}


func _spawn_explorer_at_canonical_spawn() -> void:
	if earth_world == null or earth_explorer == null:
		return
	earth_explorer.activate(
		earth_world.get_canonical_spawn_direction(),
		earth_world.get_canonical_spawn_altitude_m()
	)


func _save_diagnostic_snapshot() -> String:
	var directory_path: String = "user://diagnostics"
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(directory_path)
	)
	var path: String = "%s/earth_runtime_%d.json" % [
		directory_path,
		int(Time.get_unix_time_from_system()),
	]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "ERROR"
	file.store_string(JSON.stringify(create_runtime_snapshot(), "  "))
	return path


func _test_earth_boot() -> Dictionary:
	var passed: bool = (
		initialized
		and earth_world != null
		and earth_world.initialized
		and earth_explorer != null
		and earth_explorer.get_camera() != null
		and atmosphere_manager != null
		and atmosphere_initialized
	)
	return {
		"success": passed,
		"passed": passed,
		"output": "PASS: earth runtime boot" if passed else "FAIL: earth runtime boot",
	}


func _test_earth_body_isolation() -> Dictionary:
	var body_ids: Array[String] = []
	if celestial_system != null:
		body_ids = celestial_system.get_body_ids()
	var passed: bool = body_ids.size() == 1 and body_ids.has("earth")
	return {
		"success": passed,
		"passed": passed,
		"output": (
			"PASS: earth body isolation"
			if passed
			else "FAIL: unexpected bodies %s" % body_ids
		),
	}


func _test_earth_reference_frame() -> Dictionary:
	var expected: String = celestial_system.get_body_fixed_frame_id("earth")
	var actual: String = earth_explorer.get_reference_frame_id() if earth_explorer != null else ""
	var passed: bool = actual == expected
	return {
		"success": passed,
		"passed": passed,
		"output": "PASS: earth body-fixed frame" if passed else "FAIL: frame=%s expected=%s" % [actual, expected],
	}


func _test_earth_canonical_spawn() -> Dictionary:
	if earth_world == null or earth_explorer == null or celestial_system == null:
		return {"success": false, "passed": false, "output": "FAIL: earth canonical spawn unavailable"}
	var direction: Vector3 = earth_world.get_canonical_spawn_direction()
	var altitude: float = earth_world.get_canonical_spawn_altitude_m()
	var expected_position: Vector3 = earth_world.get_surface_point(direction) + direction * altitude
	var actual_position: Vector3 = earth_explorer.get_frame_position()
	var expected_frame: String = celestial_system.get_body_fixed_frame_id("earth")
	var passed: bool = (
		earth_explorer.get_reference_frame_id() == expected_frame
		and actual_position.distance_to(expected_position) < 0.1
		and absf(earth_world.get_altitude(actual_position) - altitude) < 0.1
	)
	return {
		"success": passed,
		"passed": passed,
		"output": "PASS: earth canonical spawn" if passed else "FAIL: earth canonical spawn",
		"canonical_spawn": earth_world.get_canonical_spawn_snapshot(),
	}


func _resolve_frame_alias(value: String) -> String:
	match value.strip_edges().to_lower():
		"system", "root", "sol", "sol.barycentric":
			return celestial_system.get_root_frame_id()
		"earth.inertial", "body/earth/inertial":
			return celestial_system.get_body_inertial_frame_id("earth")
		"earth.fixed", "body/earth/fixed":
			return celestial_system.get_body_fixed_frame_id("earth")
		_:
			return ""


func _register_command(
	registry,
	owner_id: String,
	definition: Dictionary,
	callback: Callable
) -> void:
	if not registry.register_command(definition, callback, owner_id):
		push_error("Earth command registration failed: %s" % definition.get("id", ""))


func _vector_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _ensure_input_actions() -> void:
	for binding in [
		["move_forward", KEY_W], ["move_back", KEY_S],
		["move_left", KEY_A], ["move_right", KEY_D],
		["move_up", KEY_SPACE], ["move_down", KEY_CTRL],
		["boost", KEY_SHIFT], ["roll_left", KEY_E],
		["roll_right", KEY_Q], ["level_horizon", KEY_H],
	]:
		var action: StringName = StringName(binding[0])
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			var event := InputEventKey.new()
			event.physical_keycode = int(binding[1])
			InputMap.action_add_event(action, event)
