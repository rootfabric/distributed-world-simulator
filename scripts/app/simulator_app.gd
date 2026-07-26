extends Node3D

const CommandRegistryScript = preload("res://scripts/core/command_registry.gd")
const RuntimeTestRegistryScript = preload("res://scripts/core/runtime_test_registry.gd")
const WorldCatalogScript = preload("res://scripts/core/world_catalog.gd")
const DeveloperConsoleScript = preload("res://scripts/ui/developer_console.gd")
const SimulationClockScript = preload(
	"res://scripts/simulation/time/simulation_clock.gd"
)

const WORLD_CATALOG_PATH := "res://config/worlds/catalog.json"
const RUNTIME_COMMAND_OWNER := "active_world"
const RUNTIME_TEST_OWNER := "active_world"
const WINDOWED_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3440, 1440),
]
const REQUIRED_RUNTIME_METHODS := [
	"configure_runtime",
	"register_runtime_commands",
	"register_runtime_tests",
	"create_runtime_snapshot",
	"prepare_for_unload",
]

var command_registry
var simulation_clock
var test_registry
var world_catalog
var world_host: Node3D
var developer_console
var current_runtime: Node
var current_world_id: String = ""
var current_world_definition: Dictionary = {}
var world_history: Array[String] = []
var _runtime_process_mode_before_console: int = Node.PROCESS_MODE_INHERIT
var _mouse_mode_before_console: int = Input.MOUSE_MODE_VISIBLE
var _cli_test_scope: String = ""
var _loading_world: bool = false
var _windowed_resolution_index: int = 2


func _ready() -> void:
	name = "SimulatorApp"
	get_tree().auto_accept_quit = false
	_ensure_input_actions()
	_sync_windowed_resolution_index()

	simulation_clock = SimulationClockScript.new()
	simulation_clock.setup({
		"epoch_seconds": 0.0,
		"initial_time_s": 0.0,
		"time_scale": 1.0,
		"paused": false,
	})
	command_registry = CommandRegistryScript.new()
	test_registry = RuntimeTestRegistryScript.new()
	world_catalog = WorldCatalogScript.new()
	var catalog_loaded: bool = world_catalog.load_catalog(WORLD_CATALOG_PATH)
	if not catalog_loaded:
		for error_message in world_catalog.get_validation_errors():
			push_error(String(error_message))

	_register_core_commands()
	_register_core_tests()

	world_host = Node3D.new()
	world_host.name = "WorldHost"
	add_child(world_host)

	developer_console = DeveloperConsoleScript.new()
	developer_console.name = "DeveloperConsole"
	add_child(developer_console)
	developer_console.setup(command_registry, self)
	developer_console.console_visibility_changed.connect(_on_console_visibility_changed)

	var launch_options: Dictionary = _parse_launch_options()
	_cli_test_scope = String(launch_options.get("run_tests", ""))
	var requested_world: String = String(
		launch_options.get("world", world_catalog.get_default_world_id())
	)
	var load_result: Dictionary = load_world(requested_world, false)
	if not bool(load_result.get("success", false)):
		push_error(String(load_result.get("output", "World load failed")))
		if not _cli_test_scope.is_empty():
			get_tree().quit(1)
		return
	if not _cli_test_scope.is_empty():
		call_deferred("_run_cli_tests")


func _physics_process(delta: float) -> void:
	if simulation_clock != null:
		simulation_clock.advance(delta)


func _unhandled_input(event: InputEvent) -> void:
	if developer_console != null and developer_console.is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			developer_console.set_open(true)
			developer_console.execute_line("help")
			get_viewport().set_input_as_handled()
			return
		var hotkey_commands: Array[String] = get_hotkey_command_candidates(
			event.keycode
		)
		if _execute_first_available_command(hotkey_commands):
			get_viewport().set_input_as_handled()
			return
		var command_line: String = ""
		match event.physical_keycode:
			KEY_TAB:
				command_line = "input.mouse.toggle"
			KEY_E:
				command_line = "player.interact"
			_:
				pass
		if not command_line.is_empty() and command_registry.has_command(command_line):
			execute_command(command_line)
			get_viewport().set_input_as_handled()
			return
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		and command_registry.has_command("input.mouse.capture")
	):
		execute_command("input.mouse.capture")
		get_viewport().set_input_as_handled()


func _execute_first_available_command(command_ids: Array[String]) -> bool:
	for command_id in command_ids:
		if command_registry.has_command(command_id):
			execute_command(command_id)
			return true
	return false


func get_hotkey_command_candidates(keycode: int) -> Array[String]:
	match keycode:
		KEY_F2:
			return ["player.teleport.spectator"]
		KEY_F3:
			return [
				"space.mode.toggle",
				"player.spectator.toggle",
			]
		KEY_F4:
			return [
				"world.lod.debug.toggle",
				"earth.debug.cycle",
			]
	return []


func load_world(world_id: String, remember_current: bool = true) -> Dictionary:
	if _loading_world:
		return _failure("WORLD_LOAD_IN_PROGRESS", "Уже выполняется загрузка мира")
	var normalized: String = world_id.strip_edges().to_lower()
	if not world_catalog.has_world(normalized):
		return _failure(
			"UNKNOWN_WORLD",
			"Мир не найден: %s. Используйте world.list." % normalized
		)

	var definition: Dictionary = world_catalog.get_world(normalized)
	var runtime: Node = _instantiate_runtime(definition)
	if runtime == null:
		return _failure(
			"RUNTIME_INSTANTIATION_FAILED",
			"Не удалось создать runtime мира %s" % normalized
		)
	var contract_errors: PackedStringArray = _validate_runtime_contract(runtime)
	if not contract_errors.is_empty():
		runtime.free()
		return _failure(
			"INVALID_RUNTIME_CONTRACT",
			"Runtime %s не реализует WORLD_RUNTIME_V1: %s" % [
				normalized,
				", ".join(contract_errors),
			]
		)

	_loading_world = true
	if remember_current and not current_world_id.is_empty() and current_world_id != normalized:
		world_history.append(current_world_id)
		if world_history.size() > 16:
			world_history.pop_front()
	_unload_current_world()

	var context: Dictionary = {
		"simulator_app": self,
		"command_registry": command_registry,
		"test_registry": test_registry,
		"command_owner_id": RUNTIME_COMMAND_OWNER,
		"test_owner_id": RUNTIME_TEST_OWNER,
		"world_id": normalized,
		"world_definition": definition.duplicate(true),
		"options": definition.get("options", {}).duplicate(true),
		"simulation_clock": simulation_clock,
		"universe_id": String(definition.get("universe_id", "main")),
		"instance_id": String(definition.get("instance_id", "persistent")),
		"local_authority_id": String(
			definition.get("local_authority_id", "local-process")
		),
	}
	runtime.call("configure_runtime", context)
	current_runtime = runtime
	current_world_id = normalized
	current_world_definition = definition.duplicate(true)
	runtime.name = "WorldRuntime_%s" % normalized
	world_host.add_child(runtime)
	command_registry.clear_registration_errors()
	test_registry.clear_registration_errors()
	runtime.call("register_runtime_commands", command_registry, RUNTIME_COMMAND_OWNER)
	runtime.call("register_runtime_tests", test_registry, RUNTIME_TEST_OWNER)
	var registration_errors: Array[Dictionary] = []
	registration_errors.append_array(command_registry.get_registration_errors())
	registration_errors.append_array(test_registry.get_registration_errors())
	if command_registry.get_owner_command_count(RUNTIME_COMMAND_OWNER) == 0:
		registration_errors.append({
			"owner_id": RUNTIME_COMMAND_OWNER,
			"reason": "NO_RUNTIME_COMMANDS",
		})
	if test_registry.get_owner_test_count(RUNTIME_TEST_OWNER) == 0:
		registration_errors.append({
			"owner_id": RUNTIME_TEST_OWNER,
			"reason": "NO_RUNTIME_TESTS",
		})
	if not registration_errors.is_empty():
		return _abort_runtime_load(normalized, registration_errors)

	if developer_console != null and developer_console.is_open():
		_runtime_process_mode_before_console = runtime.process_mode
		_mouse_mode_before_console = Input.mouse_mode
		runtime.process_mode = Node.PROCESS_MODE_DISABLED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if developer_console != null:
		developer_console.set_world_context(
			current_world_id,
			String(current_world_definition.get("display_name", current_world_id))
		)
		developer_console.print_system(
			"Загружен мир: %s (%s)" % [
				String(current_world_definition.get("display_name", current_world_id)),
				current_world_id,
			]
		)
	_loading_world = false
	return {
		"success": true,
		"output": "Мир загружен: %s" % String(
			current_world_definition.get("display_name", current_world_id)
		),
		"world_id": current_world_id,
	}


func _abort_runtime_load(world_id: String, errors: Array[Dictionary]) -> Dictionary:
	command_registry.unregister_owner(RUNTIME_COMMAND_OWNER)
	test_registry.unregister_owner(RUNTIME_TEST_OWNER)
	if current_runtime != null and is_instance_valid(current_runtime):
		current_runtime.call("prepare_for_unload")
		if current_runtime.get_parent() != null:
			current_runtime.get_parent().remove_child(current_runtime)
		current_runtime.queue_free()
	current_runtime = null
	current_world_id = ""
	current_world_definition.clear()
	if developer_console != null:
		developer_console.set_world_context("-", "runtime не загружен")
	_loading_world = false
	return _failure(
		"RUNTIME_REGISTRATION_FAILED",
		"Runtime %s не прошёл регистрацию команд/тестов: %s" % [
			world_id,
			JSON.stringify(errors),
		]
	)


func load_previous_world() -> Dictionary:
	while not world_history.is_empty():
		var world_id: String = world_history.pop_back()
		if world_catalog.has_world(world_id):
			return load_world(world_id, false)
	return load_world(world_catalog.get_default_world_id(), false)


func execute_command(command_line: String) -> Dictionary:
	var result: Dictionary = command_registry.execute_line(command_line)
	if developer_console != null and not developer_console.is_open():
		var output: String = String(result.get("output", ""))
		if not output.is_empty():
			print("[command] %s -> %s" % [command_line, output])
	return result


func execute_runtime_command(command_line: String) -> Dictionary:
	return execute_command(command_line)


func get_current_runtime() -> Node:
	return current_runtime


func get_current_world_id() -> String:
	return current_world_id


func get_current_world_definition() -> Dictionary:
	return current_world_definition.duplicate(true)


func get_world_catalog_snapshot() -> Dictionary:
	return world_catalog.create_snapshot()


func open_item_system_lab() -> Dictionary:
	return load_world("item_lab")


func _instantiate_runtime(definition: Dictionary) -> Node:
	var scene_path: String = String(definition.get("runtime_scene", ""))
	if not scene_path.is_empty():
		var packed = load(scene_path)
		if packed is PackedScene:
			return packed.instantiate()
		return null
	var script_path: String = String(definition.get("runtime_script", ""))
	var runtime_script = load(script_path)
	if runtime_script == null or not runtime_script.can_instantiate():
		return null
	var instance = runtime_script.new()
	return instance if instance is Node else null


func _validate_runtime_contract(runtime: Node) -> PackedStringArray:
	var missing := PackedStringArray()
	for method_name in REQUIRED_RUNTIME_METHODS:
		if not runtime.has_method(String(method_name)):
			missing.append(String(method_name))
	return missing


func _unload_current_world() -> void:
	if current_runtime != null and is_instance_valid(current_runtime):
		current_runtime.call("prepare_for_unload")
	command_registry.unregister_owner(RUNTIME_COMMAND_OWNER)
	test_registry.unregister_owner(RUNTIME_TEST_OWNER)
	if current_runtime != null and is_instance_valid(current_runtime):
		if current_runtime.get_parent() != null:
			current_runtime.get_parent().remove_child(current_runtime)
		current_runtime.queue_free()
	current_runtime = null
	current_world_id = ""
	current_world_definition.clear()


func _register_core_commands() -> void:
	_register_command({
		"id": "help",
		"description": "Показать команды или справку по одной команде.",
		"usage": "help [command|category]",
		"category": "core",
		"aliases": ["?"],
	}, Callable(self, "_command_help"))
	_register_command({
		"id": "console.toggle",
		"description": "Открыть или закрыть универсальную консоль.",
		"usage": "console.toggle",
		"category": "core",
	}, Callable(self, "_command_console_toggle"))
	_register_command({
		"id": "console.open",
		"description": "Открыть универсальную консоль.",
		"usage": "console.open",
		"category": "core",
	}, Callable(self, "_command_console_open"))
	_register_command({
		"id": "console.close",
		"description": "Закрыть универсальную консоль.",
		"usage": "console.close",
		"category": "core",
	}, Callable(self, "_command_console_close"))
	_register_command({
		"id": "input.bindings",
		"description": "Показать минимальные общие клавиши симулятора.",
		"usage": "input.bindings",
		"category": "input",
	}, Callable(self, "_command_input_bindings"))
	_register_command({
		"id": "input.mouse.toggle",
		"description": "Захватить или освободить мышь во всех мирах.",
		"usage": "input.mouse.toggle",
		"category": "input",
	}, Callable(self, "_command_input_mouse_toggle"))
	_register_command({
		"id": "input.mouse.capture",
		"description": "Вернуть мышь активному runtime.",
		"usage": "input.mouse.capture",
		"category": "input",
	}, Callable(self, "_command_input_mouse_capture"))
	_register_command({
		"id": "display.fullscreen.toggle",
		"description": "Переключить полноэкранный режим для любого мира.",
		"usage": "display.fullscreen.toggle",
		"category": "display",
	}, Callable(self, "_command_display_fullscreen_toggle"))
	_register_command({
		"id": "display.resolution.cycle",
		"description": "Переключить общее оконное разрешение симулятора.",
		"usage": "display.resolution.cycle",
		"category": "display",
	}, Callable(self, "_command_display_resolution_cycle"))
	_register_command({
		"id": "time.status",
		"description": "Показать единое время симуляции.",
		"usage": "time.status",
		"category": "time",
	}, Callable(self, "_command_time_status"))
	_register_command({
		"id": "time.set",
		"description": "Установить абсолютное время симуляции в секундах.",
		"usage": "time.set <seconds>",
		"category": "time",
	}, Callable(self, "_command_time_set"))
	_register_command({
		"id": "time.scale",
		"description": "Установить множитель времени симуляции.",
		"usage": "time.scale <multiplier>",
		"category": "time",
	}, Callable(self, "_command_time_scale"))
	_register_command({
		"id": "time.pause",
		"description": "Приостановить единые часы симуляции.",
		"usage": "time.pause",
		"category": "time",
	}, Callable(self, "_command_time_pause"))
	_register_command({
		"id": "time.resume",
		"description": "Продолжить единые часы симуляции.",
		"usage": "time.resume",
		"category": "time",
	}, Callable(self, "_command_time_resume"))
	_register_command({
		"id": "time.step",
		"description": "Сдвинуть время вручную, не меняя режим паузы.",
		"usage": "time.step <seconds>",
		"category": "time",
	}, Callable(self, "_command_time_step"))
	_register_command({
		"id": "world.list",
		"description": "Показать доступные миры.",
		"usage": "world.list",
		"category": "world",
	}, Callable(self, "_command_world_list"))
	_register_command({
		"id": "world.load",
		"description": "Загрузить мир из каталога.",
		"usage": "world.load <world_id>",
		"category": "world",
		"aliases": ["map.load"],
	}, Callable(self, "_command_world_load"))
	_register_command({
		"id": "world.back",
		"description": "Вернуться в предыдущий мир.",
		"usage": "world.back",
		"category": "world",
	}, Callable(self, "_command_world_back"))
	_register_command({
		"id": "world.reload",
		"description": "Перезагрузить текущий runtime.",
		"usage": "world.reload",
		"category": "world",
	}, Callable(self, "_command_world_reload"))
	_register_command({
		"id": "world.current",
		"description": "Показать текущий мир.",
		"usage": "world.current",
		"category": "world",
	}, Callable(self, "_command_world_current"))
	_register_command({
		"id": "test.list",
		"description": "Показать зарегистрированные тесты.",
		"usage": "test.list [core|world]",
		"category": "test",
	}, Callable(self, "_command_test_list"))
	_register_command({
		"id": "test.run",
		"description": "Запустить один тест или набор тестов.",
		"usage": "test.run <test_id|all|core|world>",
		"category": "test",
	}, Callable(self, "_command_test_run"))
	_register_command({
		"id": "runtime.snapshot",
		"description": "Показать диагностический snapshot активного runtime.",
		"usage": "runtime.snapshot",
		"category": "diagnostics",
	}, Callable(self, "_command_runtime_snapshot"))
	_register_command({
		"id": "console.clear",
		"description": "Очистить вывод консоли.",
		"usage": "console.clear",
		"category": "core",
		"aliases": ["clear"],
	}, Callable(self, "_command_console_clear"))
	_register_command({
		"id": "app.quit",
		"description": "Завершить симулятор.",
		"usage": "app.quit",
		"category": "core",
		"aliases": ["quit", "exit"],
	}, Callable(self, "_command_app_quit"))


func _register_core_tests() -> void:
	test_registry.register_test({
		"id": "core.world_catalog",
		"description": "Каталог миров валиден и содержит обязательные карты.",
		"category": "core",
	}, Callable(self, "_test_world_catalog"), "core")
	test_registry.register_test({
		"id": "core.simulation_clock",
		"description": "Единые часы детерминированно масштабируют и останавливают время.",
		"category": "core",
	}, Callable(self, "_test_simulation_clock"), "core")
	test_registry.register_test({
		"id": "core.command_registry",
		"description": "Базовые команды зарегистрированы и парсер поддерживает кавычки.",
		"category": "core",
	}, Callable(self, "_test_command_registry"), "core")


func _register_command(definition: Dictionary, callback: Callable) -> void:
	if not command_registry.register_command(definition, callback, "core"):
		push_error("Не удалось зарегистрировать команду: %s" % definition.get("id", ""))


func _command_help(arguments: Array[String]) -> Dictionary:
	if not arguments.is_empty():
		var query: String = arguments[0].to_lower()
		var command: Dictionary = command_registry.get_command(query)
		if not command.is_empty():
			return {
				"success": true,
				"output": "%s\n  %s\n  %s" % [
					command.get("id", query),
					command.get("description", ""),
					command.get("usage", query),
				],
			}
		var category_commands: Array[Dictionary] = command_registry.list_commands(query)
		if not category_commands.is_empty():
			return {"success": true, "output": _format_command_list(category_commands)}
		return _failure("HELP_TARGET_NOT_FOUND", "Команда или категория не найдена: %s" % query)
	return {
		"success": true,
		"output": _format_command_list(command_registry.list_commands()),
	}


func _command_console_toggle(_arguments: Array[String]) -> Dictionary:
	developer_console.set_open(not developer_console.is_open())
	return {
		"success": true,
		"output": "Консоль: %s" % (
			"открыта" if developer_console.is_open() else "закрыта"
		),
	}


func _command_console_open(_arguments: Array[String]) -> Dictionary:
	developer_console.set_open(true)
	return {"success": true, "output": "Консоль открыта"}


func _command_console_close(_arguments: Array[String]) -> Dictionary:
	developer_console.set_open(false)
	return {"success": true, "output": "Консоль закрыта"}


func _command_input_bindings(_arguments: Array[String]) -> Dictionary:
	return {
		"success": true,
		"output": (
			"Общие клавиши:\n"
			+ "  ~ — консоль\n"
			+ "  F1 — help\n"
			+ "  Tab — захват/освобождение мыши\n"
			+ "  E — player.interact, когда команда доступна\n"
			+ "  WASD — движение, Space — прыжок/подъём, Shift — ускорение\n"
			+ "  Q/R — крен в профилях свободного полёта, H — выравнивание"
		),
	}


func _command_input_mouse_toggle(_arguments: Array[String]) -> Dictionary:
	var capture: bool = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	if developer_console.is_open():
		developer_console.set_open(false)
		capture = true
	_set_runtime_mouse_capture(capture)
	return {
		"success": true,
		"output": "Мышь: %s" % ("захвачена" if capture else "свободна"),
	}


func _command_input_mouse_capture(_arguments: Array[String]) -> Dictionary:
	if developer_console.is_open():
		developer_console.set_open(false)
	_set_runtime_mouse_capture(true)
	return {"success": true, "output": "Мышь захвачена"}


func _command_display_fullscreen_toggle(_arguments: Array[String]) -> Dictionary:
	var mode: int = DisplayServer.window_get_mode()
	var fullscreen: bool = mode in [
		DisplayServer.WINDOW_MODE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
	]
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var target_size: Vector2i = WINDOWED_RESOLUTIONS[_windowed_resolution_index]
		DisplayServer.window_set_size(target_size)
		_center_window(target_size)
	else:
		_sync_windowed_resolution_index()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	return {
		"success": true,
		"output": "Экран: %s" % (
			"окно" if fullscreen else "полный экран"
		),
	}


func _command_display_resolution_cycle(_arguments: Array[String]) -> Dictionary:
	_windowed_resolution_index = (
		(_windowed_resolution_index + 1) % WINDOWED_RESOLUTIONS.size()
	)
	var target_size: Vector2i = WINDOWED_RESOLUTIONS[_windowed_resolution_index]
	var mode: int = DisplayServer.window_get_mode()
	if mode not in [
		DisplayServer.WINDOW_MODE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
	]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(target_size)
		_center_window(target_size)
	return {
		"success": true,
		"output": "Оконное разрешение: %d×%d%s" % [
			target_size.x,
			target_size.y,
			" (применится после выхода из full screen)"
			if mode in [
				DisplayServer.WINDOW_MODE_FULLSCREEN,
				DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
			]
			else "",
		],
	}


func _sync_windowed_resolution_index() -> void:
	var current_size: Vector2i = DisplayServer.window_get_size()
	var best_index: int = 0
	var best_distance: int = 2147483647
	for index in range(WINDOWED_RESOLUTIONS.size()):
		var candidate: Vector2i = WINDOWED_RESOLUTIONS[index]
		var distance: int = absi(candidate.x - current_size.x) + absi(
			candidate.y - current_size.y
		)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	_windowed_resolution_index = best_index


func _center_window(target_size: Vector2i) -> void:
	var screen_index: int = DisplayServer.window_get_current_screen()
	var screen_position: Vector2i = DisplayServer.screen_get_position(screen_index)
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen_index)
	DisplayServer.window_set_position(Vector2i(
		screen_position.x + maxi(int((screen_size.x - target_size.x) / 2), 0),
		screen_position.y + maxi(int((screen_size.y - target_size.y) / 2), 0)
	))


func _set_runtime_mouse_capture(captured: bool) -> void:
	if current_runtime != null and current_runtime.has_method("set_runtime_mouse_capture"):
		current_runtime.call("set_runtime_mouse_capture", captured)
	else:
		Input.mouse_mode = (
			Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
		)


func _command_time_status(_arguments: Array[String]) -> Dictionary:
	return {
		"success": true,
		"output": JSON.stringify(simulation_clock.create_snapshot(), "  "),
		"clock": simulation_clock.create_snapshot(),
	}


func _command_time_set(arguments: Array[String]) -> Dictionary:
	if arguments.is_empty() or not arguments[0].is_valid_float():
		return _failure("INVALID_TIME", "Использование: time.set <seconds>")
	simulation_clock.set_time(float(arguments[0]))
	return _command_time_status([])


func _command_time_scale(arguments: Array[String]) -> Dictionary:
	if arguments.is_empty() or not arguments[0].is_valid_float():
		return _failure("INVALID_TIME_SCALE", "Использование: time.scale <multiplier>")
	var scale_value: float = float(arguments[0])
	if scale_value < 0.0:
		return _failure(
			"INVALID_TIME_SCALE",
			"Множитель времени не может быть отрицательным"
		)
	simulation_clock.set_time_scale(scale_value)
	return _command_time_status([])


func _command_time_pause(_arguments: Array[String]) -> Dictionary:
	simulation_clock.set_paused(true)
	return _command_time_status([])


func _command_time_resume(_arguments: Array[String]) -> Dictionary:
	simulation_clock.set_paused(false)
	return _command_time_status([])


func _command_time_step(arguments: Array[String]) -> Dictionary:
	if arguments.is_empty() or not arguments[0].is_valid_float():
		return _failure("INVALID_TIME_STEP", "Использование: time.step <seconds>")
	simulation_clock.step(float(arguments[0]))
	return _command_time_status([])


func _command_world_list(_arguments: Array[String]) -> Dictionary:
	var lines := PackedStringArray()
	for world in world_catalog.list_worlds():
		var marker: String = "*" if String(world.get("id", "")) == current_world_id else " "
		lines.append("%s %s — %s" % [
			marker,
			String(world.get("id", "")),
			String(world.get("display_name", "")),
		])
	return {"success": true, "output": "Доступные миры:\n" + "\n".join(lines)}


func _command_world_load(arguments: Array[String]) -> Dictionary:
	if arguments.is_empty():
		return _failure("MISSING_WORLD_ID", "Использование: world.load <world_id>")
	return load_world(arguments[0])


func _command_world_back(_arguments: Array[String]) -> Dictionary:
	return load_previous_world()


func _command_world_reload(_arguments: Array[String]) -> Dictionary:
	if current_world_id.is_empty():
		return _failure("NO_ACTIVE_WORLD", "Нет активного мира")
	return load_world(current_world_id, false)


func _command_world_current(_arguments: Array[String]) -> Dictionary:
	return {
		"success": true,
		"output": "%s — %s" % [
			current_world_id,
			String(current_world_definition.get("display_name", "")),
		],
		"world": get_current_world_definition(),
	}


func _command_test_list(arguments: Array[String]) -> Dictionary:
	var owner_filter: String = ""
	if not arguments.is_empty():
		match arguments[0].to_lower():
			"core":
				owner_filter = "core"
			"world", "runtime":
				owner_filter = RUNTIME_TEST_OWNER
			_:
				return _failure("UNKNOWN_TEST_SCOPE", "Допустимые области: core, world")
	var lines := PackedStringArray()
	for test_definition in test_registry.list_tests(owner_filter):
		lines.append("%s — %s" % [
			String(test_definition.get("id", "")),
			String(test_definition.get("description", "")),
		])
	return {
		"success": true,
		"output": "Тесты:\n" + ("\n".join(lines) if not lines.is_empty() else "нет"),
	}


func _command_test_run(arguments: Array[String]) -> Dictionary:
	if arguments.is_empty():
		return _failure(
			"MISSING_TEST_ID",
			"Использование: test.run <test_id|all|core|world>"
		)
	var target: String = arguments[0].to_lower()
	match target:
		"all":
			return _format_test_suite_result(test_registry.run_all())
		"core":
			return _format_test_suite_result(test_registry.run_all("core"))
		"world", "runtime":
			return _format_test_suite_result(test_registry.run_all(RUNTIME_TEST_OWNER))
		_:
			return _format_single_test_result(test_registry.run_test(target))


func _command_runtime_snapshot(_arguments: Array[String]) -> Dictionary:
	var snapshot: Dictionary = {
		"schema": "planet_simulator.runtime_shell.v1",
		"world_id": current_world_id,
		"world_definition": get_current_world_definition(),
		"command_count": command_registry.get_command_count(),
		"test_count": test_registry.get_test_count(),
		"simulation_clock": simulation_clock.create_snapshot(),
	}
	if current_runtime != null and current_runtime.has_method("create_runtime_snapshot"):
		snapshot["runtime"] = current_runtime.call("create_runtime_snapshot")
	return {
		"success": true,
		"output": JSON.stringify(snapshot, "  "),
		"snapshot": snapshot,
	}


func _command_console_clear(_arguments: Array[String]) -> Dictionary:
	if developer_console != null:
		developer_console.clear_output()
	return {"success": true, "output": ""}


func _command_app_quit(_arguments: Array[String]) -> Dictionary:
	_unload_current_world()
	get_tree().quit(0)
	return {"success": true, "output": "Завершение симулятора"}


func _test_world_catalog() -> Dictionary:
	var required_worlds := ["moon", "earth", "earth_moon", "item_lab", "playground"]
	var missing := PackedStringArray()
	for world_id in required_worlds:
		if not world_catalog.has_world(world_id):
			missing.append(world_id)
	var passed: bool = world_catalog.is_valid() and missing.is_empty()
	return {
		"success": passed,
		"passed": passed,
		"output": (
			"PASS: каталог содержит все обязательные миры"
			if passed
			else "FAIL: отсутствуют миры %s; ошибки %s" % [
				", ".join(missing),
				", ".join(PackedStringArray(world_catalog.get_validation_errors())),
			]
		),
	}


func _test_command_registry() -> Dictionary:
	var parsed: Dictionary = command_registry.parse_command_line(
		"world.load \"earth moon\""
	)
	var tokens = parsed.get("tokens", [])
	var passed: bool = (
		bool(parsed.get("success", false))
		and tokens is Array
		and tokens.size() == 2
		and String(tokens[1]) == "earth moon"
		and command_registry.has_command("world.list")
		and command_registry.has_command("display.fullscreen.toggle")
		and command_registry.has_command("display.resolution.cycle")
		and command_registry.has_command("help")
		and command_registry.has_command("time.status")
		and command_registry.has_command("time.scale")
	)
	return {
		"success": passed,
		"passed": passed,
		"output": "PASS: command registry" if passed else "FAIL: command registry",
	}


func _test_simulation_clock() -> Dictionary:
	var clock = SimulationClockScript.new()
	clock.setup({"initial_time_s": 100.0, "time_scale": 2.0})
	clock.advance(0.5)
	var first_pass: bool = is_equal_approx(clock.get_time_seconds(), 101.0)
	clock.set_paused(true)
	clock.advance(10.0)
	var pause_pass: bool = is_equal_approx(clock.get_time_seconds(), 101.0)
	clock.step(5.0)
	var step_pass: bool = is_equal_approx(clock.get_time_seconds(), 106.0)
	var passed: bool = first_pass and pause_pass and step_pass
	return {
		"success": passed,
		"passed": passed,
		"output": (
			"PASS: SimulationClock масштабирует, останавливает и пошагово меняет время"
			if passed
			else "FAIL: нарушен контракт SimulationClock"
		),
	}


func _on_console_visibility_changed(opened: bool) -> void:
	if current_runtime == null or not is_instance_valid(current_runtime):
		return
	if opened:
		_runtime_process_mode_before_console = current_runtime.process_mode
		_mouse_mode_before_console = Input.mouse_mode
		current_runtime.process_mode = Node.PROCESS_MODE_DISABLED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		current_runtime.process_mode = _runtime_process_mode_before_console
		Input.mouse_mode = _mouse_mode_before_console


func _parse_launch_options() -> Dictionary:
	var result: Dictionary = {}
	for argument_value in OS.get_cmdline_user_args():
		var argument: String = String(argument_value)
		if argument.begins_with("--world="):
			result["world"] = argument.trim_prefix("--world=")
		elif argument.begins_with("--run-tests="):
			result["run_tests"] = argument.trim_prefix("--run-tests=")
	return result


func _run_cli_tests() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var result: Dictionary
	match _cli_test_scope.to_lower():
		"core":
			result = test_registry.run_all("core")
		"world", "runtime":
			result = test_registry.run_all(RUNTIME_TEST_OWNER)
		_:
			result = test_registry.run_all()
	print(String(result.get("output", "Tests complete")))
	for test_result in result.get("results", []):
		print("[%s] %s" % [
			"PASS" if bool(test_result.get("passed", false)) else "FAIL",
			String(test_result.get("test_id", "unknown")),
		])
	get_tree().quit(0 if bool(result.get("passed", false)) else 1)


func _format_command_list(commands: Array[Dictionary]) -> String:
	var lines := PackedStringArray()
	var current_category: String = ""
	for command in commands:
		var category: String = String(command.get("category", "general"))
		if category != current_category:
			current_category = category
			lines.append("\n[%s]" % category)
		lines.append("  %s — %s" % [
			String(command.get("usage", command.get("id", ""))),
			String(command.get("description", "")),
		])
	return "Команды:" + "\n".join(lines)


func _format_test_suite_result(result: Dictionary) -> Dictionary:
	var lines := PackedStringArray([String(result.get("output", ""))])
	for test_result in result.get("results", []):
		lines.append("  [%s] %s — %s" % [
			"PASS" if bool(test_result.get("passed", false)) else "FAIL",
			String(test_result.get("test_id", "")),
			String(test_result.get("output", "")),
		])
	result["output"] = "\n".join(lines)
	return result


func _format_single_test_result(result: Dictionary) -> Dictionary:
	result["output"] = "[%s] %s — %s" % [
		"PASS" if bool(result.get("passed", false)) else "FAIL",
		String(result.get("test_id", "")),
		String(result.get("output", "")),
	]
	return result


func _failure(code: String, message: String) -> Dictionary:
	return {
		"success": false,
		"error_code": code,
		"output": message,
		"message": message,
	}


func _exit_tree() -> void:
	if current_runtime != null and is_instance_valid(current_runtime):
		current_runtime.call("prepare_for_unload")


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	_unload_current_world()
	var scene_tree := get_tree()
	if scene_tree != null:
		scene_tree.quit()


func _ensure_input_actions() -> void:
	_set_single_key_action("move_forward", KEY_W)
	_set_single_key_action("move_back", KEY_S)
	_set_single_key_action("move_left", KEY_A)
	_set_single_key_action("move_right", KEY_D)
	_set_single_key_action("jump", KEY_SPACE)
	_set_single_key_action("move_up", KEY_SPACE)
	_set_single_key_action("move_down", KEY_CTRL)
	_set_single_key_action("boost", KEY_SHIFT)
	_set_single_key_action("roll_left", KEY_E)
	_set_single_key_action("roll_right", KEY_Q)
	_set_single_key_action("level_horizon", KEY_H)


func _set_single_key_action(action_name: StringName, physical_key: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey:
			InputMap.action_erase_event(action_name, existing_event)
	var input_event := InputEventKey.new()
	input_event.physical_keycode = physical_key
	InputMap.action_add_event(action_name, input_event)
