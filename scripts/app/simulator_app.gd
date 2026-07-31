extends Node3D

const CommandRegistryScript = preload("res://scripts/core/command_registry.gd")
const RuntimeTestRegistryScript = preload("res://scripts/core/runtime_test_registry.gd")
const WorldCatalogScript = preload("res://scripts/core/world_catalog.gd")
const DeveloperConsoleScript = preload("res://scripts/ui/developer_console.gd")
const SystemMenuScript = preload("res://scripts/ui/system_menu.gd")
const SimulationClockScript = preload(
	"res://scripts/simulation/time/simulation_clock.gd"
)
const LaunchOptionsScript = preload("res://scripts/runtime/launch_options.gd")
const RuntimeDescriptorScript = preload("res://scripts/runtime/runtime_descriptor.gd")
const RuntimeRoleScript = preload("res://scripts/runtime/runtime_role.gd")
const LifecycleCoordinatorScript = preload("res://scripts/runtime/lifecycle_coordinator.gd")
const SimulationKernelScript = preload("res://scripts/runtime/simulation_kernel.gd")
const PresentationHostScript = preload("res://scripts/runtime/presentation_host.gd")
const EntityRegistryKernelPortScript = preload("res://scripts/runtime/ports/entity_registry_kernel_port.gd")
const WorldRepositoryKernelPortScript = preload("res://scripts/runtime/ports/world_repository_kernel_port.gd")
const ListenHostRuntimeScript = preload("res://scripts/runtime/listen_host/listen_host_runtime.gd")
const DedicatedGameplayServerRuntimeScript = preload("res://scripts/runtime/networked_gameplay/transports/dedicated_gameplay_server_runtime.gd")
const GraphicalGameClientRuntimeScript = preload("res://scripts/runtime/networked_gameplay/transports/graphical_game_client_runtime.gd")
const M2GraphicalAcceptanceDriverScript = preload("res://scripts/runtime/networked_gameplay/m2_graphical_acceptance_driver.gd")
const M3DedicatedServerRuntimeScript = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
const M3GraphicalClientRuntimeScript = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")
const M3GraphicalAcceptanceDriverScript = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_acceptance_driver.gd")
const M5GraphicalAcceptanceDriverScript = preload("res://scripts/runtime/networked_gameplay/m5/m5_graphical_acceptance_driver.gd")

const WORLD_CATALOG_PATH := "res://config/worlds/catalog.json"
const FOUNDATION_CHECKPOINT: String = "v16.10.4-testing-m5-graphical-multiplayer-acceptance"
const FOUNDATION_BUILD_ID: String = "m5-ui-driven-graphical-multiplayer-acceptance"
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
var listen_host_authority_host: Node
var developer_console
var system_menu
var current_runtime: Node
var current_world_id: String = ""
var current_world_definition: Dictionary = {}
var world_history: Array[String] = []
var _runtime_process_mode_before_console: int = Node.PROCESS_MODE_INHERIT
var _mouse_mode_before_console: int = Input.MOUSE_MODE_VISIBLE
var _runtime_process_mode_before_system: int = Node.PROCESS_MODE_INHERIT
var _mouse_mode_before_system: int = Input.MOUSE_MODE_VISIBLE
var launch_options: Dictionary = {}
var runtime_descriptor: Dictionary = {}
var launch_option_errors: Array[String] = []
var _cli_test_scope: String = ""
var _loading_world: bool = false
var _windowed_resolution_index: int = 2
var lifecycle_coordinator
var simulation_kernel
var presentation_host
var presentation_enabled: bool = true
var local_input_enabled: bool = true
var _shutdown_in_progress: bool = false
var _requested_exit_code: int = 0
var _shutdown_reason: String = ""
var _last_runtime_drain: Dictionary = {}
var _role_policy_removed_nodes: int = 0
var _detached_presentation_nodes: Array[Node] = []
var _emergency_shutdown_scheduled: bool = false
var _runtime_release_blocked: bool = false
var _process_quit_handler: Callable
var listen_host_runtime
var listen_host_runtime_setup: Dictionary = {}
var dedicated_gameplay_server_runtime
var dedicated_gameplay_server_setup: Dictionary = {}
var graphical_game_client_runtime
var graphical_game_client_setup: Dictionary = {}
var m2_graphical_acceptance_driver
var m3_graphical_acceptance_driver
var m5_graphical_acceptance_driver
var _m3_mode: bool = false
var _m5_mode: bool = false


func _ready() -> void:
	name = "SimulatorApp"
	get_tree().auto_accept_quit = false
	launch_options = _parse_launch_options()
	if not launch_option_errors.is_empty():
		for error_message in launch_option_errors:
			push_error(error_message)
		get_tree().quit(2)
		return
	var runtime_role: String = String(
		launch_options.get("role", RuntimeRoleScript.OFFLINE)
	)
	presentation_enabled = RuntimeRoleScript.presentation_enabled(runtime_role)
	local_input_enabled = RuntimeRoleScript.accepts_local_input(runtime_role)
	set_process_unhandled_input(local_input_enabled)
	# Controller code still queries action names in server mode. Registering the
	# actions does not enable local input; input callbacks remain disabled.
	_ensure_input_actions()
	if presentation_enabled:
		_sync_windowed_resolution_index()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	lifecycle_coordinator = LifecycleCoordinatorScript.new()
	lifecycle_coordinator.setup({
		"node_id": String(launch_options.get("node_id", "local-offline")),
	})

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

	simulation_kernel = SimulationKernelScript.new()
	var kernel_result: Dictionary = simulation_kernel.setup({
		"simulation_clock": simulation_clock,
		"command_gateway": command_registry,
		"test_registry": test_registry,
		"lifecycle_coordinator": lifecycle_coordinator,
	})
	if not bool(kernel_result.get("success", false)):
		push_error("SimulationKernel boundary validation failed: %s" % kernel_result)
		get_tree().quit(3)
		return

	if runtime_role == RuntimeRoleScript.LISTEN_HOST:
		listen_host_authority_host = Node.new()
		listen_host_authority_host.name = "ListenHostAuthorityHost"
		add_child(listen_host_authority_host)
		listen_host_runtime = ListenHostRuntimeScript.new()
		listen_host_runtime_setup = listen_host_runtime.setup({
			"authority_host": listen_host_authority_host,
			"authority_owner_id": String(launch_options.get("node_id", "local-listen-host")),
			"authority_epoch": 1,
			"server_tick": 0,
			"session_id": "session/runtime/listen-host/%d" % OS.get_process_id(),
		})
		if not bool(listen_host_runtime_setup.get("success", false)):
			push_error("ListenHostRuntime setup failed: %s" % listen_host_runtime_setup)
			get_tree().quit(4)
			return

	_m5_mode = not String(launch_options.get("m5_result_file", "")).strip_edges().is_empty()
	_m3_mode = _m5_mode or not String(launch_options.get("m3_result_file", "")).strip_edges().is_empty()
	if runtime_role == RuntimeRoleScript.DEDICATED_SERVER:
		dedicated_gameplay_server_runtime = (
			M3DedicatedServerRuntimeScript.new()
			if _m3_mode
			else DedicatedGameplayServerRuntimeScript.new()
		)
		dedicated_gameplay_server_runtime.name = "M3DedicatedServerRuntime" if _m3_mode else "DedicatedGameplayServerRuntime"
		add_child(dedicated_gameplay_server_runtime)
		var dedicated_config := {
			"host": String(launch_options.get("server_address", "127.0.0.1")),
			"port": int(launch_options.get("server_port", 24580)),
			"result_file": (
				String(launch_options.get("m5_result_file", ""))
				if _m5_mode
				else String(launch_options.get("m3_result_file", "")) if _m3_mode
				else String(launch_options.get("m2_result_file", ""))
			),
			"authority_owner_id": String(launch_options.get("node_id", "local-dedicated-server")),
			"authority_epoch": 1,
			"gameplay_session_id": "session/m2/player/%s" % String(launch_options.get("player_identity", "local-astronaut")),
		}
		dedicated_gameplay_server_setup = dedicated_gameplay_server_runtime.setup(dedicated_config)
		if not bool(dedicated_gameplay_server_setup.get("success", false)):
			push_error("Dedicated gameplay server setup failed: %s" % dedicated_gameplay_server_setup)
			get_tree().quit(5)
			return

	if runtime_role == RuntimeRoleScript.GAME_CLIENT:
		graphical_game_client_runtime = (
			M3GraphicalClientRuntimeScript.new()
			if _m3_mode
			else GraphicalGameClientRuntimeScript.new()
		)
		graphical_game_client_runtime.name = "M3GraphicalClientRuntime" if _m3_mode else "GraphicalGameClientRuntime"
		add_child(graphical_game_client_runtime)
		graphical_game_client_runtime.session_ready.connect(_on_graphical_game_client_session_ready)
		graphical_game_client_runtime.connection_failed.connect(_on_graphical_game_client_connection_failed)
		graphical_game_client_setup = graphical_game_client_runtime.setup({
			"host": String(launch_options.get("server_address", "127.0.0.1")),
			"port": int(launch_options.get("server_port", 24580)),
			"logical_player_id": String(launch_options.get("player_identity", "a" if _m3_mode else "local-astronaut")),
			"connect_timeout_ms": int(launch_options.get("connect_timeout_ms", 15000)),
			"command_timeout_ms": int(launch_options.get("command_timeout_ms", 5000)),
			"automated_acceptance": (
				(_m5_mode and int(launch_options.get("m5_phase", 0)) > 0)
				or (_m3_mode and int(launch_options.get("m3_phase", 0)) > 0)
			),
			"result_file": "",
		})
		if not bool(graphical_game_client_setup.get("success", false)):
			push_error("Graphical game client setup failed: %s" % graphical_game_client_setup)
			get_tree().quit(6)
			return

	_register_core_commands()
	_register_core_tests()

	world_host = Node3D.new()
	world_host.name = "WorldHost"
	add_child(world_host)

	if presentation_enabled:
		presentation_host = PresentationHostScript.new()
		presentation_host.name = "PresentationHost"
		presentation_host.setup(true)
		add_child(presentation_host)
		developer_console = DeveloperConsoleScript.new()
		developer_console.name = "DeveloperConsole"
		presentation_host.attach_presentation(developer_console)
		developer_console.setup(command_registry, self)
		developer_console.set_completion_provider(Callable(self, "get_console_completions"))
		developer_console.console_visibility_changed.connect(_on_console_visibility_changed)
		system_menu = SystemMenuScript.new()
		system_menu.name = "SystemMenu"
		presentation_host.attach_presentation(system_menu)
		system_menu.setup(self, world_catalog)
		system_menu.menu_visibility_changed.connect(_on_system_menu_visibility_changed)

	_cli_test_scope = String(launch_options.get("run_tests", ""))
	var requested_world: String = String(launch_options.get("world", ""))
	if requested_world.is_empty():
		requested_world = world_catalog.get_default_world_id()
	launch_options["world"] = requested_world
	runtime_descriptor = RuntimeDescriptorScript.create(launch_options, {
		"checkpoint": FOUNDATION_CHECKPOINT,
		"build_id": FOUNDATION_BUILD_ID,
	})
	var load_result: Dictionary = load_world(requested_world, false)
	if not bool(load_result.get("success", false)):
		push_error(String(load_result.get("output", "World load failed")))
		lifecycle_coordinator.mark_failed(String(load_result.get("output", "World load failed")))
		if not _cli_test_scope.is_empty():
			get_tree().quit(1)
		return
	_refresh_runtime_descriptor()
	if bool(launch_options.get("print_runtime_descriptor", false)):
		print("[runtime_descriptor] %s" % JSON.stringify(runtime_descriptor, "", true, true))
	lifecycle_coordinator.mark_running("world_ready")
	_print_lifecycle_event("node_ready", {
		"world_id": current_world_id,
		"runtime_role": runtime_role,
		"presentation_enabled": presentation_enabled,
		"local_input_enabled": local_input_enabled,
		"active_presentation_nodes": count_runtime_presentation_nodes(),
		"suppressed_presentation_roots": _role_policy_removed_nodes,
		"simulation_kernel": simulation_kernel.create_snapshot(),
		"presentation_host": (
			presentation_host.create_snapshot()
			if presentation_host != null
			else {"schema": "planet_simulator.presentation_host.v1", "enabled": false, "active_node_count": 0}
		),
	})
	var shutdown_after_ms: int = int(launch_options.get("shutdown_after_ms", 0))
	if shutdown_after_ms > 0:
		_schedule_shutdown(shutdown_after_ms)
	if not _cli_test_scope.is_empty():
		call_deferred("_run_cli_tests")


func _refresh_runtime_descriptor() -> void:
	if runtime_descriptor.is_empty():
		return
	runtime_descriptor["world_id"] = current_world_id
	if listen_host_runtime != null:
		runtime_descriptor["listen_host_runtime"] = listen_host_runtime.get_report()
	if dedicated_gameplay_server_runtime != null:
		runtime_descriptor["dedicated_gameplay_server"] = dedicated_gameplay_server_runtime.get_report()
	if graphical_game_client_runtime != null:
		runtime_descriptor["graphical_game_client"] = graphical_game_client_runtime.get_report()


func _physics_process(delta: float) -> void:
	if simulation_clock != null:
		simulation_clock.advance(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not local_input_enabled or _shutdown_in_progress:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10 and not event.shift_pressed:
		if developer_console != null and developer_console.is_open():
			developer_console.set_open(false)
		if system_menu != null:
			system_menu.set_open(not system_menu.is_open())
		get_viewport().set_input_as_handled()
		return
	if system_menu != null and system_menu.is_open():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			system_menu.set_open(false)
			get_viewport().set_input_as_handled()
		return
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
		var command_line: String = get_inventory_hotbar_command_for_key(event.physical_keycode)
		if command_line.is_empty():
			match event.physical_keycode:
				KEY_TAB:
					command_line = "inventory.toggle" if command_registry.has_command("inventory.toggle") else "input.mouse.toggle"
				KEY_E:
					command_line = "player.interact"
				KEY_G:
					command_line = "inventory.drop"
				KEY_F:
					command_line = "player.flashlight.toggle"
				_:
					pass
		var command_id := command_line.get_slice(" ", 0)
		if not command_line.is_empty() and command_registry.has_command(command_id):
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
	for command_line in command_ids:
		var command_id := command_line.get_slice(" ", 0)
		if command_registry.has_command(command_id):
			execute_command(command_line)
			return true
	return false


func get_inventory_hotbar_command_for_key(keycode: int) -> String:
	match keycode:
		KEY_1: return "inventory.hotbar.select 1"
		KEY_2: return "inventory.hotbar.select 2"
		KEY_3: return "inventory.hotbar.select 3"
		KEY_4: return "inventory.hotbar.select 4"
		KEY_5: return "inventory.hotbar.select 5"
		KEY_6: return "inventory.hotbar.select 6"
		KEY_7: return "inventory.hotbar.select 7"
		KEY_8: return "inventory.hotbar.select 8"
		KEY_9: return "inventory.hotbar.select 9"
		KEY_0: return "inventory.hotbar.select 10"
	return ""


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
		KEY_F5:
			return ["player.camera.toggle"]
		KEY_J:
			return ["player.controller.toggle"]
	return []


func load_world(world_id: String, remember_current: bool = true) -> Dictionary:
	# A failed drain is a hard release fence. It must remain authoritative even
	# when the worker finishes later: only the emergency shutdown path may retry
	# the drain and clear the fence. UI callers (including SystemMenu) call this
	# method directly, so the guard belongs at the world-loading boundary.
	if _runtime_release_blocked:
		return _failure(
			"RUNTIME_RELEASE_BLOCKED",
			"Загрузка мира запрещена: предыдущий runtime не прошёл drain barrier"
		)
	if (
		lifecycle_coordinator != null
		and lifecycle_coordinator.state == LifecycleCoordinatorScript.FAILED
	):
		return _failure(
			"LIFECYCLE_FAILED",
			"Загрузка мира запрещена после отказа lifecycle; требуется аварийное завершение процесса"
		)
	if _shutdown_in_progress:
		return _failure("RUNTIME_DRAINING", "Процесс уже завершает работу")
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
	var previous_world_id: String = current_world_id
	var unload_result: Dictionary = _unload_current_world("world_switch")
	if not bool(unload_result.get("success", false)):
		runtime.free()
		_loading_world = false
		var blocked_result: Dictionary = unload_result.duplicate(true)
		blocked_result["target_world_id"] = normalized
		blocked_result["output"] = (
			"Переключение на %s отменено: предыдущий runtime не прошёл drain barrier"
			% normalized
		)
		blocked_result["message"] = blocked_result["output"]
		return blocked_result
	if remember_current and not previous_world_id.is_empty() and previous_world_id != normalized:
		world_history.append(previous_world_id)
		if world_history.size() > 16:
			world_history.pop_front()

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
		"runtime_role": String(launch_options.get("role", "offline")),
		"presentation_enabled": presentation_enabled,
		"local_input_enabled": local_input_enabled,
		"node_id": String(launch_options.get("node_id", "local-offline")),
		"launch_options": launch_options.duplicate(true),
		"runtime_descriptor": runtime_descriptor.duplicate(true),
		"lifecycle": lifecycle_coordinator.create_snapshot() if lifecycle_coordinator != null else {},
		"simulation_kernel": simulation_kernel,
		"last_runtime_drain": _last_runtime_drain.duplicate(true),
		"role_policy_removed_nodes": _role_policy_removed_nodes,
	}
	runtime.call("configure_runtime", context)
	current_runtime = runtime
	current_world_id = normalized
	current_world_definition = definition.duplicate(true)
	if not runtime_descriptor.is_empty():
		runtime_descriptor["world_id"] = current_world_id
	runtime.name = "WorldRuntime_%s" % normalized
	world_host.add_child(runtime)
	var playable_attach: Dictionary = _attach_playable_listen_host(runtime)
	if not bool(playable_attach.get("success", false)):
		return _abort_runtime_load(normalized, [{
			"owner_id": RUNTIME_COMMAND_OWNER,
			"reason": String(
				playable_attach.get("error_code", "PLAYABLE_LISTEN_HOST_ATTACH_FAILED")
			),
			"details": playable_attach.get("details", {}),
		}])
	var dedicated_attach: Dictionary = _attach_dedicated_gameplay_server(runtime)
	if not bool(dedicated_attach.get("success", false)):
		return _abort_runtime_load(normalized, [{
			"owner_id": RUNTIME_COMMAND_OWNER,
			"reason": String(
				dedicated_attach.get("error_code", "DEDICATED_GAMEPLAY_ATTACH_FAILED")
			),
			"details": dedicated_attach.get("details", {}),
		}])
	if graphical_game_client_runtime != null and graphical_game_client_runtime.is_ready():
		var remote_attach: Dictionary = (
			_attach_m3_graphical_game_client(runtime, graphical_game_client_runtime)
			if _m3_mode
			else _attach_graphical_game_client(runtime, graphical_game_client_runtime.get_playable_client_session())
		)
		if not bool(remote_attach.get("success", false)):
			return _abort_runtime_load(normalized, [{
				"owner_id": RUNTIME_COMMAND_OWNER,
				"reason": String(remote_attach.get("error_code", "GRAPHICAL_GAME_CLIENT_ATTACH_FAILED")),
				"details": remote_attach.get("details", {}),
			}])
	if listen_host_runtime != null and not runtime_descriptor.is_empty():
		runtime_descriptor["listen_host_runtime"] = listen_host_runtime.get_report()
	_bind_runtime_kernel_services(runtime)
	_apply_runtime_role_policy(runtime)
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
	elif system_menu != null and system_menu.is_open():
		_runtime_process_mode_before_system = runtime.process_mode
		_mouse_mode_before_system = Input.mouse_mode
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
	if system_menu != null and system_menu.is_open():
		system_menu.call_deferred("refresh")
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
	var dispose_result: Dictionary = _dispose_current_runtime(
		"runtime_registration_failed"
	)
	if developer_console != null:
		developer_console.set_world_context("-", "runtime не загружен")
	_loading_world = false
	if not bool(dispose_result.get("success", false)):
		if lifecycle_coordinator != null:
			lifecycle_coordinator.mark_failed(
				"Registration abort could not drain runtime"
			)
		return {
			"success": false,
			"error_code": "RUNTIME_ABORT_DRAIN_FAILED",
			"output": "Runtime регистрации удержан: drain barrier не подтверждён",
			"message": "Runtime регистрации удержан: drain barrier не подтверждён",
			"drain": dispose_result,
		}
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
	var command_id: String = command_line.strip_edges().get_slice(" ", 0)
	if (
		lifecycle_coordinator != null
		and not lifecycle_coordinator.accepts_commands()
		and command_id != "app.quit"
	):
		return _failure("RUNTIME_DRAINING", "Процесс не принимает новые команды")
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


func _unload_current_world(reason: String = "world_unload") -> Dictionary:
	var dispose_result: Dictionary = _dispose_current_runtime(reason)
	if not bool(dispose_result.get("success", false)):
		return dispose_result
	command_registry.unregister_owner(RUNTIME_COMMAND_OWNER)
	test_registry.unregister_owner(RUNTIME_TEST_OWNER)
	return dispose_result


func _dispose_current_runtime(reason: String) -> Dictionary:
	var runtime := current_runtime
	if runtime == null or not is_instance_valid(runtime):
		current_runtime = null
		current_world_id = ""
		current_world_definition.clear()
		_runtime_release_blocked = false
		_last_runtime_drain = {
			"success": true,
			"drained": true,
			"details": {},
			"reason": reason,
		}
		return _last_runtime_drain.duplicate(true)

	if lifecycle_coordinator != null:
		_last_runtime_drain = lifecycle_coordinator.drain_runtime(
			runtime,
			reason,
			int(launch_options.get("shutdown_timeout_ms", 30000))
		)
	else:
		runtime.call("prepare_for_unload")
		_last_runtime_drain = {
			"success": true,
			"drained": true,
			"details": {},
		}

	var drain_success: bool = bool(_last_runtime_drain.get("success", false))
	var fully_drained: bool = bool(_last_runtime_drain.get("drained", false))
	if not drain_success or not fully_drained:
		_runtime_release_blocked = true
		return {
			"success": false,
			"drained": fully_drained,
			"error_code": "RUNTIME_DRAIN_FAILED",
			"message": "Runtime retained because drain barrier was not confirmed",
			"runtime_retained": true,
			"world_id": current_world_id,
			"drain": _last_runtime_drain.duplicate(true),
		}

	if listen_host_runtime != null:
		var playable_detach: Dictionary = listen_host_runtime.detach_playable_world()
		if not bool(playable_detach.get("success", false)):
			_runtime_release_blocked = true
			return {
				"success": false,
				"drained": true,
				"error_code": "PLAYABLE_AUTHORITY_DETACH_FAILED",
				"runtime_retained": true,
				"world_id": current_world_id,
				"details": playable_detach,
			}
	if dedicated_gameplay_server_runtime != null:
		var dedicated_detach: Dictionary = dedicated_gameplay_server_runtime.detach_playable_world()
		if not bool(dedicated_detach.get("success", false)):
			_runtime_release_blocked = true
			return {
				"success": false,
				"drained": true,
				"error_code": "DEDICATED_GAMEPLAY_DETACH_FAILED",
				"runtime_retained": true,
				"world_id": current_world_id,
				"details": dedicated_detach,
			}
	if runtime.get_parent() != null:
		runtime.get_parent().remove_child(runtime)
	runtime.free()
	for detached in _detached_presentation_nodes:
		if detached != null and is_instance_valid(detached):
			detached.free()
	_detached_presentation_nodes.clear()
	current_runtime = null
	current_world_id = ""
	current_world_definition.clear()
	_runtime_release_blocked = false
	return {
		"success": true,
		"drained": true,
		"runtime_retained": false,
		"drain": _last_runtime_drain.duplicate(true),
	}


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
		"id": "runtime.descriptor",
		"description": "Показать роль процесса и диагностический runtime descriptor.",
		"usage": "runtime.descriptor",
		"category": "diagnostics",
	}, Callable(self, "_command_runtime_descriptor"))
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
	if developer_console == null:
		return _failure("PRESENTATION_DISABLED", "Консоль недоступна в этой runtime-роли")
	developer_console.set_open(not developer_console.is_open())
	return {
		"success": true,
		"output": "Консоль: %s" % (
			"открыта" if developer_console.is_open() else "закрыта"
		),
	}


func _command_console_open(_arguments: Array[String]) -> Dictionary:
	if developer_console == null:
		return _failure("PRESENTATION_DISABLED", "Консоль недоступна в этой runtime-роли")
	developer_console.set_open(true)
	return {"success": true, "output": "Консоль открыта"}


func _command_console_close(_arguments: Array[String]) -> Dictionary:
	if developer_console == null:
		return _failure("PRESENTATION_DISABLED", "Консоль недоступна в этой runtime-роли")
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
			+ "  Q/E — крен в профилях свободного полёта, H — выравнивание"
		),
	}


func _command_input_mouse_toggle(_arguments: Array[String]) -> Dictionary:
	if not local_input_enabled:
		return _failure("LOCAL_INPUT_DISABLED", "Локальный ввод отключён для runtime-роли")
	var capture: bool = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	if developer_console != null and developer_console.is_open():
		developer_console.set_open(false)
		capture = true
	_set_runtime_mouse_capture(capture)
	return {
		"success": true,
		"output": "Мышь: %s" % ("захвачена" if capture else "свободна"),
	}


func _command_input_mouse_capture(_arguments: Array[String]) -> Dictionary:
	if not local_input_enabled:
		return _failure("LOCAL_INPUT_DISABLED", "Локальный ввод отключён для runtime-роли")
	if developer_console != null and developer_console.is_open():
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


func _command_runtime_descriptor(_arguments: Array[String]) -> Dictionary:
	return {
		"success": true,
		"output": JSON.stringify(runtime_descriptor, "  ", true, true),
		"runtime_descriptor": runtime_descriptor.duplicate(true),
	}


func _command_runtime_snapshot(_arguments: Array[String]) -> Dictionary:
	var snapshot: Dictionary = {
		"schema": "planet_simulator.runtime_shell.v1",
		"world_id": current_world_id,
		"world_definition": get_current_world_definition(),
		"command_count": command_registry.get_command_count(),
		"test_count": test_registry.get_test_count(),
		"simulation_clock": simulation_clock.create_snapshot(),
		"runtime_descriptor": runtime_descriptor.duplicate(true),
		"simulation_kernel": simulation_kernel.create_snapshot(),
		"presentation_host": (
			presentation_host.create_snapshot()
			if presentation_host != null
			else {"schema": "planet_simulator.presentation_host.v1", "enabled": false, "active_node_count": 0}
		),
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
	call_deferred("request_graceful_shutdown", "command_app_quit", 0)
	return {"success": true, "output": "Запущено корректное завершение симулятора"}


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


func get_debug_item_catalog() -> Array[Dictionary]:
	if current_runtime == null or not is_instance_valid(current_runtime) or not current_runtime.has_method("get_item_gameplay_controller"):
		return []
	var controller = current_runtime.call("get_item_gameplay_controller")
	if controller == null or not controller.has_method("list_debug_item_catalog"):
		return []
	return controller.call("list_debug_item_catalog")


func grant_debug_item(definition_id: String, quantity: int) -> Dictionary:
	if current_runtime == null or not is_instance_valid(current_runtime) or not current_runtime.has_method("get_item_gameplay_controller"):
		return {"success": false, "message": "В текущей локации нет инвентаря игрока"}
	var controller = current_runtime.call("get_item_gameplay_controller")
	if controller == null or not controller.has_method("grant_debug_item"):
		return {"success": false, "message": "Админская выдача недоступна"}
	return controller.call("grant_debug_item", definition_id, maxi(1, quantity))


func get_console_completions(command_line: String, caret_column: int = -1) -> Array[String]:
	var limit := command_line.length() if caret_column < 0 else clampi(caret_column, 0, command_line.length())
	var before := command_line.left(limit)
	var trailing_space := before.ends_with(" ") or before.ends_with("\t")
	var parsed: Dictionary = command_registry.parse_command_line(before)
	if not bool(parsed.get("success", false)):
		return []
	var tokens: Array[String] = parsed.get("tokens", [])
	if tokens.is_empty():
		return command_registry.find_completions("")
	if tokens.size() == 1 and not trailing_space:
		return command_registry.find_completions(tokens[0])
	var command_id := String(tokens[0]).to_lower()
	var argument_prefix := "" if trailing_space else String(tokens[-1])
	var candidates: Array[String] = []
	match command_id:
		"world.load":
			for world in world_catalog.list_worlds():
				candidates.append(String(world.get("id", "")))
		"test.run":
			candidates = ["all", "core", "world"]
			for test_definition in test_registry.list_tests():
				candidates.append(String(test_definition.get("id", "")))
		"test.list":
			candidates = ["core", "world"]
		"inventory.hotbar.select":
			for index in range(1, 11):
				candidates.append(str(index))
		"inventory.profile":
			candidates = ["planet_default", "rust_like", "seven_days_like"]
		"inventory.debug.grant":
			for row in get_debug_item_catalog():
				candidates.append(String(row.get("definition_id", "")))
		_:
			var command: Dictionary = command_registry.get_command(command_id)
			if not command.is_empty() and String(command.get("usage", "")).contains("<"):
				candidates = []
	var results: Array[String] = []
	for candidate in candidates:
		if argument_prefix.is_empty() or candidate.begins_with(argument_prefix.to_lower()):
			results.append(candidate)
	results.sort()
	return results


func _on_system_menu_visibility_changed(opened: bool) -> void:
	if current_runtime == null or not is_instance_valid(current_runtime):
		return
	if opened:
		_runtime_process_mode_before_system = current_runtime.process_mode
		_mouse_mode_before_system = Input.mouse_mode
		current_runtime.process_mode = Node.PROCESS_MODE_DISABLED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		current_runtime.process_mode = _runtime_process_mode_before_system
		Input.mouse_mode = _mouse_mode_before_system


func _on_console_visibility_changed(opened: bool) -> void:
	if opened and system_menu != null and system_menu.is_open():
		system_menu.set_open(false)
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
	var parsed: Dictionary = LaunchOptionsScript.from_os()
	launch_option_errors.clear()
	for error_value in parsed.get("errors", []):
		launch_option_errors.append(String(error_value))
	var options_value = parsed.get("options", {})
	return options_value.duplicate(true) if options_value is Dictionary else {}


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
	request_graceful_shutdown(
		"cli_tests_complete",
		0 if bool(result.get("passed", false)) else 1
	)


func request_graceful_shutdown(reason: String = "shutdown", exit_code: int = 0) -> Dictionary:
	if _shutdown_in_progress:
		return {
			"success": true,
			"already_in_progress": true,
			"reason": _shutdown_reason,
			"exit_code": _requested_exit_code,
		}
	var requested_reason: String = (
		reason.strip_edges() if not reason.strip_edges().is_empty() else "shutdown"
	)
	if lifecycle_coordinator != null:
		var begin_result: Dictionary = lifecycle_coordinator.begin_shutdown(
			requested_reason,
			exit_code
		)
		if not bool(begin_result.get("success", false)):
			_schedule_emergency_shutdown(
				"begin_shutdown_failed",
				requested_reason,
				exit_code,
				begin_result
			)
			var failed_begin: Dictionary = begin_result.duplicate(true)
			failed_begin["emergency_shutdown_scheduled"] = true
			return failed_begin

	_shutdown_in_progress = true
	_shutdown_reason = requested_reason
	_requested_exit_code = exit_code
	_print_lifecycle_event("node_draining", {
		"reason": _shutdown_reason,
		"exit_code": _requested_exit_code,
		"world_id": current_world_id,
	})
	call_deferred("_complete_graceful_shutdown")
	return {"success": true, "reason": _shutdown_reason, "exit_code": _requested_exit_code}


func _complete_graceful_shutdown() -> void:
	var unload_result: Dictionary = _unload_current_world(
		"process_shutdown:%s" % _shutdown_reason
	)
	if not bool(unload_result.get("success", false)):
		if lifecycle_coordinator != null:
			lifecycle_coordinator.mark_failed(
				"Runtime drain barrier failed during shutdown"
			)
		_print_lifecycle_event("node_shutdown_failed", {
			"reason": _shutdown_reason,
			"exit_code": _requested_exit_code,
			"failure_stage": "runtime_drain",
			"runtime_retained": true,
			"will_quit": false,
			"unload": unload_result,
			"lifecycle": lifecycle_coordinator.create_snapshot() if lifecycle_coordinator != null else {},
		})
		_shutdown_in_progress = false
		return

	if lifecycle_coordinator != null:
		var stopping_result: Dictionary = lifecycle_coordinator.mark_stopping(
			"runtime_drained"
		)
		if not bool(stopping_result.get("success", false)):
			_complete_emergency_shutdown(
				"mark_stopping_failed",
				_shutdown_reason,
				_requested_exit_code,
				stopping_result
			)
			return
		var stopped_result: Dictionary = lifecycle_coordinator.mark_stopped(
			"runtime_drained"
		)
		if not bool(stopped_result.get("success", false)):
			_complete_emergency_shutdown(
				"mark_stopped_failed",
				_shutdown_reason,
				_requested_exit_code,
				stopped_result
			)
			return
	_stop_networked_gameplay_runtimes()
	_print_lifecycle_event("node_stopped", {
		"reason": _shutdown_reason,
		"exit_code": _requested_exit_code,
		"last_runtime_drain": _last_runtime_drain,
		"lifecycle": lifecycle_coordinator.create_snapshot() if lifecycle_coordinator != null else {},
	})
	_quit_process(_requested_exit_code)


func _schedule_emergency_shutdown(
	trigger: String,
	reason: String,
	exit_code: int,
	failure: Dictionary
) -> void:
	if _emergency_shutdown_scheduled:
		return
	_emergency_shutdown_scheduled = true
	call_deferred(
		"_complete_emergency_shutdown",
		trigger,
		reason,
		exit_code,
		failure.duplicate(true)
	)


func _complete_emergency_shutdown(
	trigger: String,
	reason: String,
	exit_code: int,
	failure: Dictionary
) -> Dictionary:
	_emergency_shutdown_scheduled = false
	_shutdown_in_progress = true
	_shutdown_reason = reason
	_requested_exit_code = exit_code if exit_code != 0 else 1
	var cleanup_result: Dictionary = _unload_current_world(
		"emergency_shutdown:%s" % trigger
	)
	var cleanup_safe: bool = bool(cleanup_result.get("success", false))
	if lifecycle_coordinator != null and lifecycle_coordinator.state != LifecycleCoordinatorScript.FAILED:
		lifecycle_coordinator.mark_failed(
			"Emergency shutdown: %s" % trigger
		)
	_print_lifecycle_event("node_shutdown_failed", {
		"reason": _shutdown_reason,
		"exit_code": _requested_exit_code,
		"failure_stage": trigger,
		"failure": failure,
		"cleanup": cleanup_result,
		"runtime_retained": not cleanup_safe,
		"will_quit": cleanup_safe,
		"lifecycle": lifecycle_coordinator.create_snapshot() if lifecycle_coordinator != null else {},
	})
	if not cleanup_safe:
		_runtime_release_blocked = true
		_shutdown_in_progress = false
		return {
			"success": false,
			"error_code": "EMERGENCY_DRAIN_FAILED",
			"runtime_retained": true,
			"cleanup": cleanup_result,
		}
	_quit_process(_requested_exit_code)
	return {
		"success": true,
		"exit_code": _requested_exit_code,
		"runtime_retained": false,
	}


func set_process_quit_handler_for_tests(handler: Callable) -> void:
	_process_quit_handler = handler


func _quit_process(exit_code: int) -> void:
	if _process_quit_handler.is_valid():
		_process_quit_handler.call(exit_code)
		return
	var scene_tree := get_tree()
	if scene_tree != null:
		scene_tree.quit(exit_code)


func _schedule_shutdown(delay_ms: int) -> void:
	var delay_seconds: float = maxf(float(delay_ms) / 1000.0, 0.001)
	var timer := get_tree().create_timer(delay_seconds)
	timer.timeout.connect(func() -> void:
		request_graceful_shutdown("scheduled_shutdown", 0)
	)


func _attach_playable_listen_host(runtime: Node) -> Dictionary:
	if listen_host_runtime == null or runtime == null:
		return {"success": true, "error_code": "", "details": {"required": false}}
	if (
		not runtime.has_method("create_playable_listen_host_config")
		or not runtime.has_method("attach_playable_client_session")
	):
		return {"success": true, "error_code": "", "details": {"required": false}}
	var config_value = runtime.call("create_playable_listen_host_config")
	if not config_value is Dictionary or Dictionary(config_value).is_empty():
		return {
			"success": false,
			"error_code": "PLAYABLE_LISTEN_HOST_CONFIG_REQUIRED",
			"details": {},
		}
	var authority_attach: Dictionary = listen_host_runtime.attach_playable_world(
		Dictionary(config_value)
	)
	if not bool(authority_attach.get("success", false)):
		return authority_attach
	var client_session = listen_host_runtime.get_playable_client_session()
	var client_attach_value = runtime.call(
		"attach_playable_client_session", client_session
	)
	if not client_attach_value is Dictionary:
		listen_host_runtime.detach_playable_world()
		return {
			"success": false,
			"error_code": "INVALID_PLAYABLE_CLIENT_ATTACH_RESULT",
			"details": {},
		}
	var client_attach: Dictionary = Dictionary(client_attach_value)
	if not bool(client_attach.get("success", false)):
		listen_host_runtime.detach_playable_world()
		return client_attach
	return {
		"success": true,
		"error_code": "",
		"details": {
			"required": true,
			"authority": authority_attach.get("details", {}),
			"client": client_attach.duplicate(true),
		},
	}


func _attach_dedicated_gameplay_server(runtime: Node) -> Dictionary:
	if dedicated_gameplay_server_runtime == null or runtime == null:
		return {"success": true, "error_code": "", "details": {"required": false}}
	if _m3_mode:
		return {"success": true, "error_code": "", "details": {"required": true, "profile": "MULTIPLAYER_CORE"}}
	if not runtime.has_method("create_playable_listen_host_config"):
		return {"success": true, "error_code": "", "details": {"required": false}}
	var config_value = runtime.call("create_playable_listen_host_config")
	if not config_value is Dictionary or Dictionary(config_value).is_empty():
		return {"success": false, "error_code": "DEDICATED_PLAYABLE_CONFIG_REQUIRED", "details": {}}
	return dedicated_gameplay_server_runtime.attach_playable_world(Dictionary(config_value))


func _attach_graphical_game_client(runtime: Node, session) -> Dictionary:
	if graphical_game_client_runtime == null or runtime == null:
		return {"success": true, "error_code": "", "details": {"required": false}}
	if not runtime.has_method("attach_playable_client_session"):
		return {"success": false, "error_code": "GRAPHICAL_RUNTIME_SESSION_ATTACH_MISSING", "details": {}}
	var attached_value = runtime.call("attach_playable_client_session", session)
	if not attached_value is Dictionary:
		return {"success": false, "error_code": "INVALID_GRAPHICAL_CLIENT_ATTACH_RESULT", "details": {}}
	var attached: Dictionary = Dictionary(attached_value)
	if bool(attached.get("success", false)):
		_setup_m2_graphical_acceptance_driver()
	return attached


func _attach_m3_graphical_game_client(runtime: Node, client_runtime) -> Dictionary:
	if client_runtime == null or runtime == null:
		return {"success": true, "error_code": "", "details": {"required": false}}
	if not runtime.has_method("attach_m3_multiplayer_client"):
		return {"success": false, "error_code": "M3_GRAPHICAL_RUNTIME_ATTACH_MISSING", "details": {}}
	var result_value = runtime.call("attach_m3_multiplayer_client", client_runtime)
	var result: Dictionary = Dictionary(result_value) if result_value is Dictionary else {"success": false, "error_code": "INVALID_M3_ATTACH_RESULT"}
	if bool(result.get("success", false)):
		if _m5_mode:
			_setup_m5_graphical_acceptance_driver()
		else:
			_setup_m3_graphical_acceptance_driver()
	return result


func _setup_m3_graphical_acceptance_driver() -> void:
	if not _m3_mode or _m5_mode or m3_graphical_acceptance_driver != null:
		return
	var result_file := String(launch_options.get("m3_result_file", "")).strip_edges()
	var phase := int(launch_options.get("m3_phase", 0))
	if result_file.is_empty() or phase not in [1, 2, 3]:
		return
	m3_graphical_acceptance_driver = M3GraphicalAcceptanceDriverScript.new()
	m3_graphical_acceptance_driver.name = "M3GraphicalAcceptanceDriver"
	add_child(m3_graphical_acceptance_driver)
	var setup_result: Dictionary = m3_graphical_acceptance_driver.setup(self, graphical_game_client_runtime, {
		"result_file": result_file,
		"peer_result_file": String(launch_options.get("m3_peer_result_file", "")),
		"client_id": String(launch_options.get("player_identity", "")),
		"phase": phase,
	})
	if not bool(setup_result.get("success", false)):
		push_error("M3 acceptance driver setup failed: %s" % setup_result)
		request_graceful_shutdown("m3_acceptance_driver_setup_failed", 10)


func _setup_m5_graphical_acceptance_driver() -> void:
	if not _m5_mode or m5_graphical_acceptance_driver != null:
		return
	var result_file := String(launch_options.get("m5_result_file", "")).strip_edges()
	var phase := int(launch_options.get("m5_phase", 0))
	if result_file.is_empty() or phase not in [1, 2, 3]:
		return
	m5_graphical_acceptance_driver = M5GraphicalAcceptanceDriverScript.new()
	m5_graphical_acceptance_driver.name = "M5GraphicalAcceptanceDriver"
	add_child(m5_graphical_acceptance_driver)
	var setup_result: Dictionary = m5_graphical_acceptance_driver.setup(
		self,
		graphical_game_client_runtime,
		{
			"result_file": result_file,
			"peer_result_file": String(launch_options.get("m5_peer_result_file", "")),
			"control_file": String(launch_options.get("m5_control_file", "")),
			"screenshot_dir": String(launch_options.get("m5_screenshot_dir", "")),
			"client_id": String(launch_options.get("player_identity", "")),
			"phase": phase,
		}
	)
	if not bool(setup_result.get("success", false)):
		push_error("M5 acceptance driver setup failed: %s" % setup_result)
		request_graceful_shutdown("m5_acceptance_driver_setup_failed", 11)


func _on_graphical_game_client_session_ready(session) -> void:
	if current_runtime == null or not is_instance_valid(current_runtime):
		return
	var attached: Dictionary = (
		_attach_m3_graphical_game_client(current_runtime, session)
		if _m3_mode
		else _attach_graphical_game_client(current_runtime, session)
	)
	if not bool(attached.get("success", false)):
		push_error("Graphical game client attach failed: %s" % attached)
		request_graceful_shutdown("graphical_game_client_attach_failed", 7)
	_refresh_runtime_descriptor()


func _on_graphical_game_client_connection_failed(error_code: String, details: Dictionary) -> void:
	push_error("Graphical game client connection failed: %s %s" % [error_code, details])
	request_graceful_shutdown("graphical_game_client_connection_failed", 8)


func _setup_m2_graphical_acceptance_driver() -> void:
	if m2_graphical_acceptance_driver != null:
		return
	var phase: int = int(launch_options.get("m2_phase", 0))
	var result_file: String = String(launch_options.get("m2_result_file", "")).strip_edges()
	if phase not in [1, 2] or result_file.is_empty():
		return
	m2_graphical_acceptance_driver = M2GraphicalAcceptanceDriverScript.new()
	m2_graphical_acceptance_driver.name = "M2GraphicalAcceptanceDriver"
	add_child(m2_graphical_acceptance_driver)
	var setup_result: Dictionary = m2_graphical_acceptance_driver.setup(self, graphical_game_client_runtime, {
		"result_file": result_file,
		"expected_state_file": String(launch_options.get("m2_expected_state_file", "")),
		"phase": phase,
	})
	if not bool(setup_result.get("success", false)):
		push_error("M2 graphical acceptance driver setup failed: %s" % setup_result)
		request_graceful_shutdown("m2_acceptance_driver_setup_failed", 9)


func _stop_networked_gameplay_runtimes() -> void:
	if graphical_game_client_runtime != null and is_instance_valid(graphical_game_client_runtime):
		graphical_game_client_runtime.stop()
	if dedicated_gameplay_server_runtime != null and is_instance_valid(dedicated_gameplay_server_runtime):
		dedicated_gameplay_server_runtime.stop()


func _bind_runtime_kernel_services(runtime: Node) -> void:
	if simulation_kernel == null:
		return
	var store = null
	if listen_host_runtime != null:
		store = listen_host_runtime.get_playable_authority_world_entity_store_for_kernel()
	if store == null and dedicated_gameplay_server_runtime != null:
		store = dedicated_gameplay_server_runtime.get_world_entity_store_for_kernel()
	if store == null and runtime != null and runtime.has_method("get_world_entity_store"):
		store = runtime.call("get_world_entity_store")
	simulation_kernel.set_world_entity_store(store)

	var entity_port = null
	if runtime != null and runtime.has_method("get_entity_registry_snapshot"):
		var entity_snapshot = runtime.call("get_entity_registry_snapshot")
		if entity_snapshot is Dictionary and not entity_snapshot.is_empty():
			entity_port = EntityRegistryKernelPortScript.new()
			if not bool(entity_port.setup(entity_snapshot).get("success", false)):
				entity_port = null
	simulation_kernel.set_entity_registry_port(entity_port)

	var repository_port = null
	if runtime != null and runtime.has_method("get_world_repository_snapshot"):
		var repository_snapshot = runtime.call("get_world_repository_snapshot")
		if repository_snapshot is Dictionary and not repository_snapshot.is_empty():
			repository_port = WorldRepositoryKernelPortScript.new()
			if not bool(repository_port.setup(repository_snapshot).get("success", false)):
				repository_port = null
	simulation_kernel.set_world_repository_port(repository_port)


func _apply_runtime_role_policy(runtime: Node) -> void:
	if runtime == null or not is_instance_valid(runtime):
		return
	if not local_input_enabled:
		_disable_local_input_recursive(runtime)
	if presentation_enabled:
		return
	var presentation_roots: Array[Node] = []
	_collect_presentation_roots(runtime, presentation_roots, false)
	for node in presentation_roots:
		if node == null or not is_instance_valid(node):
			continue
		_suppress_presentation_node(node)
		_role_policy_removed_nodes += 1


func _suppress_presentation_node(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is Camera3D:
		node.current = false
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		_detached_presentation_nodes.append(node)
	elif node is Camera2D:
		node.enabled = false
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		_detached_presentation_nodes.append(node)
	elif node is Control:
		node.visible = false
	elif node is CanvasLayer:
		node.visible = false
	elif node is Window:
		node.visible = false
	elif node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		node.stop()


func _disable_local_input_recursive(node: Node) -> void:
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	node.set_process_shortcut_input(false)
	for child in node.get_children():
		_disable_local_input_recursive(child)


func _collect_presentation_roots(
	node: Node,
	output: Array[Node],
	parent_is_presentation: bool
) -> void:
	var is_presentation: bool = (
		node is Control
		or node is CanvasLayer
		or node is Camera2D
		or node is Camera3D
		or node is AudioStreamPlayer
		or node is AudioStreamPlayer2D
		or node is AudioStreamPlayer3D
		or node is Window
	)
	if is_presentation and not parent_is_presentation:
		output.append(node)
		return
	for child in node.get_children():
		_collect_presentation_roots(child, output, parent_is_presentation or is_presentation)


func count_runtime_presentation_nodes() -> int:
	if current_runtime == null or not is_instance_valid(current_runtime):
		return 0
	var nodes: Array[Node] = []
	_collect_presentation_roots(current_runtime, nodes, false)
	var active_count: int = 0
	for node in nodes:
		if node == null or not is_instance_valid(node):
			continue
		if node is Camera3D and node.current:
			active_count += 1
		elif node is Camera2D and node.enabled:
			active_count += 1
		elif node is Control and node.visible:
			active_count += 1
		elif node is CanvasLayer and node.visible:
			active_count += 1
		elif node is Window and node.visible:
			active_count += 1
	return active_count


func _print_lifecycle_event(event_name: String, data: Dictionary) -> void:
	var payload: Dictionary = data.duplicate(true)
	payload["event"] = event_name
	payload["checkpoint"] = FOUNDATION_CHECKPOINT
	payload["build_id"] = FOUNDATION_BUILD_ID
	payload["node_id"] = String(launch_options.get("node_id", "local-offline"))
	payload["ticks_msec"] = Time.get_ticks_msec()
	print("[lifecycle] %s" % JSON.stringify(payload, "", true, true))


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
	_stop_networked_gameplay_runtimes()
	if _runtime_release_blocked:
		return
	if current_runtime != null and is_instance_valid(current_runtime):
		_dispose_current_runtime("exit_tree")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_graceful_shutdown("window_close", 0)


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
