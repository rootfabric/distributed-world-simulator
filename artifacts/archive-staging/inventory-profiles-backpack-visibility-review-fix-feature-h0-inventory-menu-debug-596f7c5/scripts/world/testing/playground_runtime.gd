extends Node3D

const PlayerScript = preload("res://scripts/actors/player/lunar_player.gd")
const FlatWorldAdapterScript = preload(
	"res://scripts/world/testing/flat_world_adapter.gd"
)
const GravityFieldScript = preload("res://scripts/simulation/gravity/gravity_field.gd")
const ItemGameplayControllerScript = preload("res://scripts/items/presentation/item_gameplay_controller.gd")
const WorldInteractorScript = preload("res://scripts/interaction/world_interactor.gd")

var simulator
var command_registry
var test_registry
var world_definition: Dictionary = {}
var command_owner: String = "active_world"
var test_owner: String = "active_world"
var runtime_universe_id: String = "main"
var runtime_instance_id: String = "scenario-playground"
var world_adapter
var player
var spawned_objects: Node3D
var spawn_position: Vector3 = Vector3(0.0, 1.2, 6.0)
var object_counter: int = 0
var overlay_label: Label
var interaction_label: Label
var item_world_root: Node3D
var item_attachment_root: Node3D
var item_gameplay
var gravity_field
var world_interactor


func configure_runtime(context: Dictionary) -> void:
	simulator = context.get("simulator_app")
	command_registry = context.get("command_registry")
	test_registry = context.get("test_registry")
	world_definition = context.get("world_definition", {}).duplicate(true)
	command_owner = String(context.get("command_owner_id", command_owner))
	test_owner = String(context.get("test_owner_id", test_owner))
	runtime_universe_id = String(context.get("universe_id", runtime_universe_id))
	runtime_instance_id = String(context.get("instance_id", runtime_instance_id))
	var options: Dictionary = world_definition.get("options", {})
	var spawn_values = options.get("spawn", [0.0, 1.2, 6.0])
	if spawn_values is Array and spawn_values.size() >= 3:
		spawn_position = Vector3(
			float(spawn_values[0]),
			float(spawn_values[1]),
			float(spawn_values[2])
		)


func _ready() -> void:
	_build_environment()
	world_adapter = FlatWorldAdapterScript.new()
	world_adapter.name = "FlatWorldAdapter"
	add_child(world_adapter)
	world_adapter.setup(spawn_position)

	player = PlayerScript.new()
	player.name = "UniversalTestPlayer"
	add_child(player)
	player.setup(world_adapter, null, "flat_humanoid")
	player.set_world_position(spawn_position)
	player.align_body_to_up(Vector3.UP)
	player.activate_after_spawn()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_setup_item_gameplay()
	_build_overlay()


func register_runtime_commands(registry, owner_id: String) -> void:
	_register_command(registry, owner_id, {
		"id": "player.camera.toggle",
		"description": "Переключить первое и третье лицо.",
		"usage": "player.camera.toggle",
		"category": "player",
	}, Callable(self, "_command_camera_toggle"))
	_register_command(registry, owner_id, {
		"id": "player.reset",
		"description": "Вернуть персонажа в начальную точку полигона.",
		"usage": "player.reset",
		"category": "player",
	}, Callable(self, "_command_player_reset"))
	_register_command(registry, owner_id, {
		"id": "player.interact",
		"description": "Подобрать предмет, открыть контейнер или использовать mount.",
		"usage": "player.interact",
		"category": "player",
	}, Callable(self, "_command_player_interact"))
	_register_command(registry, owner_id, {"id": "player.flashlight.toggle", "description": "Включить или выключить круговой фонарь.", "usage": "player.flashlight.toggle", "category": "player"}, Callable(self, "_command_flashlight_toggle"))
	_register_command(registry, owner_id, {"id": "inventory.debug.grant", "description": "Выдать предмет в рюкзак.", "usage": "inventory.debug.grant <definition_id> [quantity]", "category": "items"}, Callable(self, "_command_debug_grant"))
	_register_command(registry, owner_id, {
		"id": "playground.spawn_box",
		"description": "Создать физический тестовый ящик перед персонажем.",
		"usage": "playground.spawn_box [size_m]",
		"category": "playground",
	}, Callable(self, "_command_spawn_box"))
	_register_command(registry, owner_id, {
		"id": "playground.clear",
		"description": "Удалить созданные на полигоне объекты.",
		"usage": "playground.clear",
		"category": "playground",
	}, Callable(self, "_command_clear"))
	_register_command(registry, owner_id, {"id": "inventory.toggle", "description": "Открыть инвентарь.", "usage": "inventory.toggle", "category": "items"}, Callable(self, "_command_inventory_toggle"))
	_register_command(registry, owner_id, {"id": "inventory.drop", "description": "Выбросить предмет выбранного hotbar stack.", "usage": "inventory.drop", "category": "items"}, Callable(self, "_command_inventory_drop"))
	_register_command(registry, owner_id, {"id": "inventory.hotbar.select", "description": "Выбрать быстрый слот 1-10.", "usage": "inventory.hotbar.select <1-10>", "category": "items"}, Callable(self, "_command_hotbar_select"))
	_register_command(registry, owner_id, {"id": "inventory.profile", "description": "Показать или сменить профиль управления инвентарём.", "usage": "inventory.profile [planet_default|rust_like|seven_days_like]", "category": "items"}, Callable(self, "_command_inventory_profile"))
	_register_command(registry, owner_id, {"id": "inventory.save", "description": "Сохранить полный item graph.", "usage": "inventory.save", "category": "items"}, Callable(self, "_command_inventory_save"))


func register_runtime_tests(registry, owner_id: String) -> void:
	registry.register_test({
		"id": "world.playground.boot",
		"description": "Полигон создал персонажа, пол и камеру.",
		"category": "world",
	}, Callable(self, "_test_boot"), owner_id)
	registry.register_test({
		"id": "world.playground.physics_object",
		"description": "Полигон создаёт и удаляет физический объект.",
		"category": "world",
	}, Callable(self, "_test_physics_object"), owner_id)
	registry.register_test({
		"id": "world.playground.inventory_demo",
		"description": "R2 demo создал рюкзак, hotbar, ящик, rack и socket.",
		"category": "world",
	}, Callable(self, "_test_inventory_demo"), owner_id)


func create_runtime_snapshot() -> Dictionary:
	return {
		"schema": "planet_simulator.playground_runtime.v1",
		"world_id": String(world_definition.get("id", "playground")),
		"universe_id": runtime_universe_id,
		"instance_id": runtime_instance_id,
		"player_position": _vector_to_array(
			player.get_world_position() if player != null else Vector3.ZERO
		),
		"controller": player.get_controller_snapshot() if player != null else {},
		"spawned_object_count": spawned_objects.get_child_count() if spawned_objects != null else 0,
		"item_gameplay": item_gameplay.create_debug_snapshot() if item_gameplay != null else {},
	}


func get_world_entity_store():
	if item_gameplay == null or item_gameplay.domain.is_empty():
		return null
	return item_gameplay.domain.world_entities


func prepare_for_unload() -> void:
	if item_gameplay != null:
		item_gameplay.save_graph()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_environment() -> void:
	var environment_node := WorldEnvironment.new()
	environment_node.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.10, 0.13, 0.18)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.78, 0.90)
	environment.ambient_light_energy = 0.75
	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

	spawned_objects = Node3D.new()
	spawned_objects.name = "SpawnedObjects"
	add_child(spawned_objects)
	item_world_root = Node3D.new()
	item_world_root.name = "ItemWorldRoot"
	add_child(item_world_root)
	item_attachment_root = Node3D.new()
	item_attachment_root.name = "ItemAttachmentRoot"
	add_child(item_attachment_root)

	_create_static_box("Floor", Vector3(40.0, 0.5, 40.0), Vector3(0.0, -0.25, 0.0))
	_create_static_box("NorthWall", Vector3(40.0, 4.0, 0.5), Vector3(0.0, 2.0, -20.0))
	_create_static_box("SouthWall", Vector3(40.0, 4.0, 0.5), Vector3(0.0, 2.0, 20.0))
	_create_static_box("WestWall", Vector3(0.5, 4.0, 40.0), Vector3(-20.0, 2.0, 0.0))
	_create_static_box("EastWall", Vector3(0.5, 4.0, 40.0), Vector3(20.0, 2.0, 0.0))

	for index in range(5):
		_create_static_box(
			"Step_%d" % index,
			Vector3(2.5, 0.35 + index * 0.25, 2.5),
			Vector3(-7.0 + index * 3.0, (0.35 + index * 0.25) * 0.5, -5.0)
		)



func _setup_item_gameplay() -> void:
	gravity_field = GravityFieldScript.new()
	gravity_field.setup_static_sources([{
		"id": "playground-moon",
		"radius_m": 1737400.0,
		"gravitational_parameter_m3_s2": 4890065191200.0,
		"center_m": [0.0, -1737400.0, 0.0],
		"interior_model": "uniform_sphere",
	}], "scenario/playground/local")
	item_gameplay = ItemGameplayControllerScript.new()
	item_gameplay.name = "ItemGameplayController"
	add_child(item_gameplay)
	item_gameplay.setup_runtime(player, item_world_root, item_attachment_root, gravity_field, "scenario/playground/local", "playground-moon", "playground-r2-demo", "playground", true)
	item_gameplay.inventory_visibility_changed.connect(_on_inventory_visibility_changed)
	world_interactor = WorldInteractorScript.new()
	world_interactor.name = "ItemWorldInteractor"
	add_child(world_interactor)
	world_interactor.setup(player, null)
	world_interactor.focus_changed.connect(_on_world_interaction_focus_changed)
	world_interactor.interaction_completed.connect(_on_world_interaction_completed)
	world_interactor.set_enabled(true)


func _on_inventory_visibility_changed(visible_value: bool) -> void:
	if world_interactor != null:
		world_interactor.set_enabled(not visible_value)



func _on_world_interaction_focus_changed(snapshot: Dictionary) -> void:
	if interaction_label == null:
		return
	if snapshot.is_empty():
		interaction_label.visible = false
		interaction_label.text = ""
		return
	interaction_label.text = "%s\n%s" % [
		String(snapshot.get("title", "Объект")),
		String(snapshot.get("prompt", "E — взаимодействовать")),
	]
	interaction_label.visible = true


func _on_world_interaction_completed(result: Dictionary) -> void:
	if interaction_label == null:
		return
	interaction_label.text = String(result.get("message", result.get("output", "Взаимодействие выполнено")))
	interaction_label.visible = true


func _create_static_box(node_name: String, size: Vector3, position_value: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position_value
	body.collision_layer = 1
	body.collision_mask = 3
	add_child(body)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.36, 0.43)
	material.roughness = 0.9
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)


func _build_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "PlaygroundOverlay"
	add_child(canvas)
	overlay_label = Label.new()
	overlay_label.position = Vector2(18.0, 18.0)
	overlay_label.text = (
		"ИСПЫТАТЕЛЬНЫЙ ПОЛИГОН\n"
		+ "WASD — движение, Shift — бег, Space — прыжок\n"
		+ "Tab — инвентарь, E — взаимодействие/установка, G — выбросить, F — фонарь\n"
		+ "1–0 — hotbar; ящик справа, battery rack слева, mount между ними"
	)
	overlay_label.add_theme_font_size_override("font_size", 15)
	canvas.add_child(overlay_label)

	interaction_label = Label.new()
	interaction_label.name = "InteractionHint"
	interaction_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	interaction_label.position = Vector2(-300.0, -105.0)
	interaction_label.size = Vector2(600.0, 72.0)
	interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	interaction_label.add_theme_font_size_override("font_size", 16)
	interaction_label.visible = false
	canvas.add_child(interaction_label)


func _command_camera_toggle(_arguments: Array[String]) -> Dictionary:
	var mode: String = player.toggle_camera_mode()
	return {"success": true, "output": "Камера: %s" % mode}


func _command_player_reset(_arguments: Array[String]) -> Dictionary:
	world_adapter.recover_actor(player)
	return {"success": true, "output": "Персонаж возвращён в стартовую точку"}


func _command_player_interact(_arguments: Array[String]) -> Dictionary:
	if world_interactor == null:
		return {"success": false, "output": "Взаимодействие не готово"}
	var result: Dictionary = world_interactor.perform_interaction()
	if not bool(result.get("success", false)) and String(result.get("message", "")) == "Нет объекта для взаимодействия" and item_gameplay != null:
		result = item_gameplay.place_selected_item_from_view()
	if not result.has("output"):
		result["output"] = String(result.get("message", "Взаимодействие выполнено"))
	return result


func set_runtime_mouse_capture(captured: bool) -> void:
	Input.mouse_mode = (
		Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	)


func _command_inventory_toggle(_arguments: Array[String]) -> Dictionary:
	return item_gameplay.toggle_inventory() if item_gameplay != null else {"success": false, "output": "Инвентарь не готов"}


func _command_inventory_drop(_arguments: Array[String]) -> Dictionary:
	return item_gameplay.drop_selected_item() if item_gameplay != null else {"success": false, "output": "Инвентарь не готов"}


func _command_hotbar_select(arguments: Array[String]) -> Dictionary:
	if item_gameplay == null or arguments.is_empty() or not arguments[0].is_valid_int():
		return {"success": false, "output": "Использование: inventory.hotbar.select <1-10>"}
	return item_gameplay.select_hotbar(clampi(int(arguments[0]), 1, 10) - 1)


func _command_inventory_profile(arguments: Array[String]) -> Dictionary:
	if item_gameplay == null or item_gameplay.inventory_ui == null or item_gameplay.inventory_ui.active_screen == null:
		return {"success": false, "output": "Инвентарь не готов"}
	var screen = item_gameplay.inventory_ui.active_screen
	if arguments.is_empty():
		var active = screen.active_interaction_profile
		return {
			"success": active != null,
			"output": "Профиль инвентаря: %s" % (active.profile_id if active != null else "недоступен"),
		}
	var profile_id := arguments[0].strip_edges().to_lower()
	var profile = screen.interaction_profile_loader.get_profile(profile_id)
	if profile == null:
		return {"success": false, "output": "Неизвестный профиль: %s" % profile_id}
	screen._apply_interaction_profile(profile, true, true)
	return {"success": true, "output": "Профиль инвентаря: %s" % profile.profile_id}


func _command_inventory_save(_arguments: Array[String]) -> Dictionary:
	return item_gameplay.save_graph() if item_gameplay != null else {"success": false, "output": "Инвентарь не готов"}



func _command_flashlight_toggle(_arguments: Array[String]) -> Dictionary:
	var enabled: bool = bool(player.toggle_flashlight()) if player != null else false
	return {"success": player != null, "output": "Фонарь: %s" % ("включён" if enabled else "выключен"), "enabled": enabled}


func _command_debug_grant(arguments: Array[String]) -> Dictionary:
	if item_gameplay == null or arguments.is_empty():
		return {"success": false, "output": "Использование: inventory.debug.grant <definition_id> [quantity]"}
	var quantity := 1
	if arguments.size() > 1 and arguments[1].is_valid_int():
		quantity = maxi(1, int(arguments[1]))
	var result: Dictionary = item_gameplay.grant_debug_item(arguments[0], quantity)
	result["output"] = item_gameplay.result_message(result)
	return result


func get_item_gameplay_controller():
	return item_gameplay


func _command_spawn_box(arguments: Array[String]) -> Dictionary:
	var size_value: float = 1.0
	if not arguments.is_empty() and arguments[0].is_valid_float():
		size_value = clampf(float(arguments[0]), 0.2, 4.0)
	var body := RigidBody3D.new()
	object_counter += 1
	body.name = "TestBox_%d" % object_counter
	body.mass = maxf(0.2, size_value * size_value * size_value * 12.0)
	body.collision_layer = 1
	body.collision_mask = 3
	var camera: Camera3D = player.get_active_camera()
	var forward: Vector3 = -camera.global_transform.basis.z
	body.position = camera.global_position + forward * 4.0 + Vector3.UP * 0.5
	spawned_objects.add_child(body)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size_value
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * size_value
	collision.shape = shape
	body.add_child(collision)
	return {
		"success": true,
		"output": "Создан %s" % body.name,
		"object_name": body.name,
	}


func _command_clear(_arguments: Array[String]) -> Dictionary:
	var removed_count: int = spawned_objects.get_child_count()
	for child in spawned_objects.get_children():
		child.free()
	return {
		"success": true,
		"output": "Удалено объектов: %d" % removed_count,
	}


func _test_boot() -> Dictionary:
	var passed: bool = (
		player != null
		and player.get_active_camera() != null
		and player.get_controller_id() == "flat_humanoid"
		and get_node_or_null("Floor") is StaticBody3D
	)
	return {
		"success": passed,
		"passed": passed,
		"output": "PASS: playground boot" if passed else "FAIL: playground boot",
	}


func _test_physics_object() -> Dictionary:
	var before: int = spawned_objects.get_child_count()
	var create_result: Dictionary = _command_spawn_box(["0.5"])
	var after_create: int = spawned_objects.get_child_count()
	var object_name: String = String(create_result.get("object_name", ""))
	var created_object: Node = spawned_objects.get_node_or_null(object_name)
	var object_was_found: bool = is_instance_valid(created_object)
	if object_was_found:
		created_object.free()
	var after_cleanup: int = spawned_objects.get_child_count()
	var passed: bool = (
		bool(create_result.get("success", false))
		and after_create == before + 1
		and object_was_found
		and after_cleanup == before
	)
	return {
		"success": passed,
		"passed": passed,
		"output": "PASS: physics object lifecycle" if passed else "FAIL: physics object lifecycle",
	}


func _test_inventory_demo() -> Dictionary:
	var passed: bool = (
		item_gameplay != null
		and item_gameplay.get_container(item_gameplay.player_inventory_id) != null
		and item_gameplay.get_container(item_gameplay.player_hotbar_id) != null
		and item_gameplay.get_container("demo_crate_contents") != null
		and item_gameplay.get_container("battery_rack_slots") != null
		and not item_gameplay.get_socket_state("demo_mount", "beacon_socket").is_empty()
		and item_gameplay.placement_service != null
		and item_gameplay.placement_service.fixture_nodes.size() >= 1
		and command_registry != null
		and command_registry.has_command("player.interact")
		and bool(item_gameplay.domain.validator.validate_graph().get("success", false))
	)
	return {"success": passed, "passed": passed, "output": "PASS: inventory demo" if passed else "FAIL: inventory demo"}



func _register_command(registry, owner_id: String, definition: Dictionary, callback: Callable) -> void:
	if not registry.register_command(definition, callback, owner_id):
		push_error("Playground command registration failed: %s" % definition.get("id", ""))


func _vector_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
