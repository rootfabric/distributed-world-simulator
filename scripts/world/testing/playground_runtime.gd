extends Node3D

const PlayerScript = preload("res://scripts/actors/player/lunar_player.gd")
const FlatWorldAdapterScript = preload(
	"res://scripts/world/testing/flat_world_adapter.gd"
)

var simulator
var command_registry
var test_registry
var world_definition: Dictionary = {}
var command_owner: String = "active_world"
var test_owner: String = "active_world"
var world_adapter
var player
var spawned_objects: Node3D
var spawn_position: Vector3 = Vector3(0.0, 1.2, 6.0)
var object_counter: int = 0
var overlay_label: Label


func configure_runtime(context: Dictionary) -> void:
	simulator = context.get("simulator_app")
	command_registry = context.get("command_registry")
	test_registry = context.get("test_registry")
	world_definition = context.get("world_definition", {}).duplicate(true)
	command_owner = String(context.get("command_owner_id", command_owner))
	test_owner = String(context.get("test_owner_id", test_owner))
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


func create_runtime_snapshot() -> Dictionary:
	return {
		"schema": "planet_simulator.playground_runtime.v1",
		"world_id": String(world_definition.get("id", "playground")),
		"player_position": _vector_to_array(
			player.get_world_position() if player != null else Vector3.ZERO
		),
		"controller": player.get_controller_snapshot() if player != null else {},
		"spawned_object_count": spawned_objects.get_child_count() if spawned_objects != null else 0,
	}


func prepare_for_unload() -> void:
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
		+ "~ — универсальная консоль, Tab — освободить мышь\n"
		+ "Команды: player.camera.toggle, playground.spawn_box, test.run world"
	)
	overlay_label.add_theme_font_size_override("font_size", 15)
	canvas.add_child(overlay_label)


func _command_camera_toggle(_arguments: Array[String]) -> Dictionary:
	var mode: String = player.toggle_camera_mode()
	return {"success": true, "output": "Камера: %s" % mode}


func _command_player_reset(_arguments: Array[String]) -> Dictionary:
	world_adapter.recover_actor(player)
	return {"success": true, "output": "Персонаж возвращён в стартовую точку"}


func set_runtime_mouse_capture(captured: bool) -> void:
	Input.mouse_mode = (
		Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	)


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


func _register_command(registry, owner_id: String, definition: Dictionary, callback: Callable) -> void:
	if not registry.register_command(definition, callback, owner_id):
		push_error("Playground command registration failed: %s" % definition.get("id", ""))


func _vector_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
