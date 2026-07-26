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

var logger
var celestial_system
var earth_world
var earth_explorer
var atmosphere_manager
var planetary_overlay
var default_earth_biome: String = "forest"
var initialized: bool = false
var atmosphere_initialized: bool = false
var last_diagnostic_path: String = "-"
var visible_body_ids: Array[String] = ["earth"]


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
	var options: Dictionary = runtime_world_definition.get("options", {})
	default_earth_biome = String(options.get("default_biome", "forest"))


func _ready() -> void:
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
	_teleport_to_earth_biome(default_earth_biome)
	earth_world.set_primary_lighting_enabled(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	logger.info("application", "earth_runtime_ready", {
		"world_id": get_runtime_id(),
		"body_ids": celestial_system.get_body_ids(),
		"default_biome": default_earth_biome,
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
		"default_biome": default_earth_biome,
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
		"atmosphere": (
			atmosphere_manager.create_snapshot()
			if atmosphere_manager != null
			else {}
		),
		"last_diagnostic_path": last_diagnostic_path,
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
	_teleport_to_earth_biome(default_earth_biome)
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
