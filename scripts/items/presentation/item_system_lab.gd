extends Node3D

const MAIN_SCENE_PATH := "res://main.tscn"

const Factory = preload(
	"res://scripts/items/services/item_domain_factory.gd"
)
const Definition = preload(
	"res://scripts/items/domain/item_definition.gd"
)
const ContainerState = preload(
	"res://scripts/containers/container_state.gd"
)
const Relations = preload(
	"res://scripts/items/domain/item_relations.gd"
)
const Presenter = preload(
	"res://scripts/items/presentation/item_representation_system.gd"
)
const GravityField = preload(
	"res://scripts/simulation/gravity/gravity_field.gd"
)

var domain: Dictionary
var presenter
var gravity_field
var backpack
var crate
var crate_contents
var rock
var crate_rocks
var lidar
var chassis

var status_label: Label
var action_label: Label
var operation_counter: int = 1
var last_action_result: Dictionary = {
	"success": true,
	"message": "Лаборатория готова",
}
var simulator_app
var runtime_command_registry
var runtime_test_registry
var runtime_world_definition: Dictionary = {}
var runtime_universe_id: String = "main"
var runtime_instance_id: String = "scenario-item-lab"
var runtime_space_id: String = "scenario/item-lab"
var runtime_frame_id: String = "scenario/item-lab/local"


func configure_runtime(context: Dictionary) -> void:
	simulator_app = context.get("simulator_app")
	runtime_command_registry = context.get("command_registry")
	runtime_test_registry = context.get("test_registry")
	runtime_world_definition = context.get("world_definition", {}).duplicate(true)
	runtime_universe_id = String(context.get("universe_id", runtime_universe_id))
	runtime_instance_id = String(context.get("instance_id", runtime_instance_id))


func _ready() -> void:
	_build_environment()
	_build_domain()
	_build_ui()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if simulator_app != null:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_1:
			run_lab_action("pickup_rock")
		KEY_2:
			run_lab_action("drop_rock")
		KEY_3:
			run_lab_action("pickup_crate")
		KEY_4:
			run_lab_action("drop_crate")
		KEY_5:
			run_lab_action("pickup_lidar")
		KEY_6:
			run_lab_action("attach_lidar")
		KEY_7:
			run_lab_action("detach_lidar")
		KEY_T:
			run_lab_action("validate")
		KEY_F5:
			return_to_main()
		KEY_ESCAPE:
			return_to_main()


func run_lab_action(action_id: String) -> Dictionary:
	var result: Dictionary
	match action_id:
		"pickup_rock":
			result = _pickup(rock.instance_id)
		"drop_rock":
			result = _drop(
				rock.instance_id,
				Vector3(-1.5, 2.0, 0.0)
			)
		"pickup_crate":
			result = _pickup(crate.instance_id)
		"drop_crate":
			result = _drop(
				crate.instance_id,
				Vector3(0.0, 2.0, 0.0)
			)
		"pickup_lidar":
			result = _pickup(lidar.instance_id)
		"attach_lidar":
			result = domain.attachments.attach(
				lidar.instance_id,
				"rover_01",
				"roof_sensor",
				_operation("attach_lidar"),
				int(lidar.revision)
			)
		"detach_lidar":
			result = domain.attachments.detach_to_container(
				lidar.instance_id,
				"player_backpack",
				_operation("detach_lidar"),
				int(lidar.revision)
			)
		"validate":
			result = domain.validator.validate_graph()
		_:
			result = {
				"success": false,
				"error_code": "UNKNOWN_LAB_ACTION",
			}
	last_action_result = result.duplicate(true)
	last_action_result["message"] = _result_message(
		action_id,
		result
	)
	_refresh()
	return result


func get_debug_snapshot() -> Dictionary:
	var graph_result: Dictionary = domain.validator.validate_graph()
	var socket_state: Dictionary = domain.attachments.get_socket_state(
		"rover_01",
		"roof_sensor"
	)
	return {
		"rock_id": rock.instance_id,
		"crate_id": crate.instance_id,
		"crate_rocks_id": crate_rocks.instance_id,
		"lidar_id": lidar.instance_id,
		"rock_relation": _relation_kind(rock.instance_id),
		"crate_relation": _relation_kind(crate.instance_id),
		"crate_rocks_relation": _relation_kind(
			crate_rocks.instance_id
		),
		"lidar_relation": _relation_kind(lidar.instance_id),
		"backpack_item_ids": backpack.item_ids.duplicate(),
		"crate_item_ids": crate_contents.item_ids.duplicate(),
		"backpack_mass_kg": domain.mass.container_mass_kg(
			"player_backpack"
		),
		"crate_recursive_mass_kg": domain.mass.item_recursive_mass_kg(
			crate.instance_id
		),
		"crate_physical_mass_kg": presenter.get_world_physical_mass_kg(
			crate.instance_id
		),
		"rock_gravity_acceleration_mps2": _vector_to_array(
			presenter.get_world_gravity_acceleration_mps2(rock.instance_id)
		),
		"rock_world_body": (
			presenter.get_world_node(rock.instance_id)
			is RigidBody3D
		),
		"crate_world_body": (
			presenter.get_world_node(crate.instance_id)
			is RigidBody3D
		),
		"lidar_world_body": (
			presenter.get_world_node(lidar.instance_id)
			is RigidBody3D
		),
		"lidar_attached_node": (
			presenter.get_attached_node(lidar.instance_id)
			is Node3D
		),
		"chassis_world_body": (
			presenter.get_world_node(chassis.instance_id)
			is RigidBody3D
		),
		"socket_item_id": String(
			socket_state.get("item_id", "")
		),
		"graph_valid": bool(
			graph_result.get("success", false)
		),
		"graph_result": graph_result,
		"rock_has_texture": _world_item_has_albedo_texture(
			rock.instance_id
		),
	}


func return_to_main() -> void:
	if simulator_app != null and simulator_app.has_method("execute_command"):
		simulator_app.execute_command("world.back")
		return
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _build_domain() -> void:
	domain = Factory.create()
	var items = domain.items

	items.register_definition(Definition.new({
		"id": "lunar_rock",
		"display_name": "Лунный камень",
		"max_stack": 50,
		"unit_mass_kg": 2.0,
		"external_volume_l": 0.8,
		"tags": ["rock", "resource"],
		"metadata": {
			"size": [0.34, 0.26, 0.36],
		},
	}))
	items.register_definition(Definition.new({
		"id": "portable_crate",
		"display_name": "Переносной ящик",
		"max_stack": 1,
		"unit_mass_kg": 4.0,
		"external_volume_l": 30.0,
		"tags": ["container"],
		"metadata": {
			"size": [0.90, 0.55, 0.68],
		},
	}))
	items.register_definition(Definition.new({
		"id": "lidar_module",
		"display_name": "Лидар",
		"max_stack": 1,
		"unit_mass_kg": 3.0,
		"external_volume_l": 5.0,
		"tags": ["lidar", "sensor", "mountable"],
		"metadata": {
			"size": [0.38, 0.24, 0.38],
		},
	}))
	items.register_definition(Definition.new({
		"id": "rover_chassis",
		"display_name": "Корпус ровера",
		"max_stack": 1,
		"unit_mass_kg": 120.0,
		"external_volume_l": 400.0,
		"tags": ["assembly_root"],
		"metadata": {
			"presentation_mode": "EXTERNAL",
		},
	}))

	backpack = ContainerState.new({
		"container_id": "player_backpack",
		"owner_kind": "ACTOR",
		"owner_id": "player",
		"slot_count": 8,
		"maximum_mass_kg": 80.0,
		"maximum_volume_l": 100.0,
		"allow_nested_containers": true,
		"maximum_nested_depth": 2,
	})
	domain.containers.add_container(backpack)

	crate = items.create_item(
		"portable_crate",
		1,
		{
			"container": {
				"container_id": "crate_contents",
			},
		},
		_world_relation(
			Transform3D(
				Basis.IDENTITY,
				Vector3(0.0, 2.0, 0.0)
			)
		)
	)
	crate_contents = ContainerState.new({
		"container_id": "crate_contents",
		"owner_kind": "ITEM_INSTANCE",
		"owner_id": crate.instance_id,
		"slot_count": 6,
		"maximum_mass_kg": 50.0,
		"maximum_volume_l": 24.0,
		"allow_nested_containers": false,
	})
	domain.containers.add_container(crate_contents)

	rock = items.create_item(
		"lunar_rock",
		3,
		{},
		_world_relation(
			Transform3D(
				Basis.IDENTITY,
				Vector3(-1.5, 2.0, 0.0)
			)
		)
	)
	crate_rocks = items.create_item(
		"lunar_rock",
		3,
		{},
		Relations.container("crate_contents")
	)
	crate_contents.item_ids.append(crate_rocks.instance_id)

	lidar = items.create_item(
		"lidar_module",
		1,
		{},
		_world_relation(
			Transform3D(
				Basis.IDENTITY,
				Vector3(1.5, 2.0, 0.0)
			)
		)
	)
	chassis = items.create_item(
		"rover_chassis",
		1,
		{},
		_world_relation(
			Transform3D(
				Basis.IDENTITY,
				Vector3(4.0, 1.0, 0.0)
			)
		)
	)

	domain.attachments.register_socket(
		"rover_01",
		chassis.instance_id,
		"roof_sensor",
		["lidar"]
	)

	gravity_field = GravityField.new()
	gravity_field.setup_static_sources([
		{
			"id": "moon-lab",
			"radius_m": 1_737_400.0,
			"gravitational_parameter_m3_s2": 4_890_065_191_200.0,
			"center_m": [0.0, -1_737_400.0, 0.0],
			"interior_model": "uniform_sphere",
		},
	], runtime_frame_id)

	presenter = Presenter.new()
	presenter.name = "ItemRepresentationSystem"
	add_child(presenter)
	presenter.setup(
		items,
		$WorldItems,
		$Rover/AttachmentRoot,
		true,
		domain.mass,
		gravity_field,
		runtime_frame_id
	)
	presenter.register_attachment_anchor(
		"rover_01",
		"roof_sensor",
		$Rover/AttachmentRoot
	)

	domain.transfer.relation_changed.connect(
		_on_relation_changed
	)
	domain.transfer.item_removed.connect(
		_on_item_removed
	)
	domain.transfer.quantity_changed.connect(
		_on_quantity_changed
	)


func _build_environment() -> void:
	var world_items = Node3D.new()
	world_items.name = "WorldItems"
	add_child(world_items)

	var rover = Node3D.new()
	rover.name = "Rover"
	rover.position = Vector3(4.0, 0.65, 0.0)
	add_child(rover)

	var rover_body = MeshInstance3D.new()
	rover_body.name = "RoverBody"
	var rover_mesh = BoxMesh.new()
	rover_mesh.size = Vector3(2.6, 0.7, 1.6)
	rover_body.mesh = rover_mesh
	var rover_material = StandardMaterial3D.new()
	rover_material.albedo_color = Color(
		0.18,
		0.24,
		0.20
	)
	rover_material.metallic = 0.25
	rover_material.roughness = 0.65
	rover_body.material_override = rover_material
	rover.add_child(rover_body)

	var attachment_root = Node3D.new()
	attachment_root.name = "AttachmentRoot"
	attachment_root.position = Vector3(
		0.0,
		0.55,
		0.0
	)
	rover.add_child(attachment_root)

	var socket_marker = MeshInstance3D.new()
	socket_marker.name = "RoofSensorSocketMarker"
	var socket_mesh = CylinderMesh.new()
	socket_mesh.top_radius = 0.24
	socket_mesh.bottom_radius = 0.24
	socket_mesh.height = 0.08
	socket_marker.mesh = socket_mesh
	var socket_material = StandardMaterial3D.new()
	socket_material.albedo_color = Color(
		0.95,
		0.70,
		0.12
	)
	socket_material.emission_enabled = true
	socket_material.emission = Color(
		0.35,
		0.18,
		0.02
	)
	socket_marker.material_override = socket_material
	attachment_root.add_child(socket_marker)

	var rover_label = Label3D.new()
	rover_label.text = "РОВЕР\nсокет лидара"
	rover_label.font_size = 24
	rover_label.outline_size = 4
	rover_label.position = Vector3(0.0, 1.1, 0.0)
	rover_label.double_sided = true
	rover_label.no_depth_test = true
	rover.add_child(rover_label)

	var floor_body = StaticBody3D.new()
	floor_body.name = "Floor"
	var floor_collision = CollisionShape3D.new()
	var floor_shape = BoxShape3D.new()
	floor_shape.size = Vector3(20.0, 0.4, 12.0)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)

	var floor_mesh_instance = MeshInstance3D.new()
	var floor_mesh = BoxMesh.new()
	floor_mesh.size = floor_shape.size
	floor_mesh_instance.mesh = floor_mesh
	var floor_material = StandardMaterial3D.new()
	floor_material.albedo_color = Color(
		0.10,
		0.11,
		0.13
	)
	floor_material.roughness = 0.95
	floor_mesh_instance.material_override = floor_material
	floor_body.add_child(floor_mesh_instance)
	floor_body.position.y = -0.2
	add_child(floor_body)

	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(
		-55.0,
		-30.0,
		0.0
	)
	light.shadow_enabled = true
	light.light_energy = 1.25
	add_child(light)

	var environment_node = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(
		0.015,
		0.018,
		0.028
	)
	environment.ambient_light_source = (
		Environment.AMBIENT_SOURCE_COLOR
	)
	environment.ambient_light_color = Color(
		0.35,
		0.39,
		0.48
	)
	environment.ambient_light_energy = 0.65
	environment_node.environment = environment
	add_child(environment_node)

	var camera = Camera3D.new()
	camera.name = "LabCamera"
	camera.position = Vector3(8.0, 7.0, 11.0)
	camera.look_at_from_position(
		camera.position,
		Vector3(1.0, 0.5, 0.0)
	)
	camera.current = true
	add_child(camera)


func _build_ui() -> void:
	var layer = CanvasLayer.new()
	layer.name = "LabUI"
	add_child(layer)

	var panel = PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.size = Vector2(600.0, 680.0)
	layer.add_child(panel)

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(
		0.018,
		0.022,
		0.035,
		0.94
	)
	panel_style.border_color = Color(
		0.22,
		0.42,
		0.58,
		0.9
	)
	panel_style.set_border_width_all(1)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", panel_style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vertical = VBoxContainer.new()
	vertical.add_theme_constant_override("separation", 8)
	margin.add_child(vertical)

	var title = Label.new()
	title.text = "ЛАБОРАТОРИЯ ПРЕДМЕТОВ v15.8 / R1.3"
	title.add_theme_font_size_override("font_size", 22)
	vertical.add_child(title)

	var description = Label.new()
	description.text = (
		"Один ItemInstance меняет отношение:\n"
		+ "WORLD ↔ CONTAINER ↔ ATTACHMENT.\n"
		+ "Физика существует только в WORLD."
	)
	description.add_theme_font_size_override(
		"font_size",
		14
	)
	vertical.add_child(description)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(
		"h_separation",
		8
	)
	grid.add_theme_constant_override(
		"v_separation",
		6
	)
	vertical.add_child(grid)

	_add_action_button(
		grid,
		"Подобрать камень",
		"pickup_rock"
	)
	_add_action_button(
		grid,
		"Выбросить камень",
		"drop_rock"
	)
	_add_action_button(
		grid,
		"Подобрать ящик",
		"pickup_crate"
	)
	_add_action_button(
		grid,
		"Выбросить ящик",
		"drop_crate"
	)
	_add_action_button(
		grid,
		"Подобрать лидар",
		"pickup_lidar"
	)
	_add_action_button(
		grid,
		"Поставить лидар",
		"attach_lidar"
	)
	_add_action_button(
		grid,
		"Снять лидар",
		"detach_lidar"
	)
	_add_action_button(
		grid,
		"Проверить граф",
		"validate"
	)

	action_label = Label.new()
	action_label.add_theme_font_size_override(
		"font_size",
		14
	)
	action_label.modulate = Color(
		0.95,
		0.82,
		0.36
	)
	vertical.add_child(action_label)

	status_label = Label.new()
	status_label.custom_minimum_size = Vector2(
		560.0,
		270.0
	)
	status_label.add_theme_font_size_override(
		"font_size",
		14
	)
	status_label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)
	vertical.add_child(status_label)

	var return_button = Button.new()
	return_button.text = (
		"Вернуться в предыдущий мир"
	)
	return_button.pressed.connect(return_to_main)
	vertical.add_child(return_button)


func _add_action_button(
	parent: Control,
	text_value: String,
	action_id: String
) -> void:
	var button = Button.new()
	button.text = text_value
	button.pressed.connect(
		_on_action_button_pressed.bind(action_id)
	)
	parent.add_child(button)


func _on_action_button_pressed(action_id: String) -> void:
	if simulator_app != null and simulator_app.has_method("execute_command"):
		simulator_app.execute_command("item.action %s" % action_id)
		return
	run_lab_action(action_id)


func _world_relation(
	transform: Transform3D = Transform3D.IDENTITY,
	linear_velocity: Vector3 = Vector3.ZERO
) -> Dictionary:
	return Relations.world(
		transform,
		linear_velocity,
		runtime_frame_id,
		0.0,
		runtime_universe_id,
		runtime_space_id,
		runtime_instance_id
	)


func _pickup(item_id: String) -> Dictionary:
	presenter.capture_world_state(item_id)
	var item = domain.items.get_item(item_id)
	var expected_revision: int = int(item.revision) if item != null else -1
	return domain.transfer.move_item(
		item_id,
		Relations.container("player_backpack"),
		_operation("pickup"),
		expected_revision
	)


func _drop(
	item_id: String,
	position: Vector3
) -> Dictionary:
	var item = domain.items.get_item(item_id)
	var expected_revision: int = int(item.revision) if item != null else -1
	return domain.transfer.move_item(
		item_id,
		_world_relation(
			Transform3D(
				Basis.IDENTITY,
				position
			),
			Vector3(0.0, 0.0, -1.0)
		),
		_operation("drop"),
		expected_revision
	)


func _on_relation_changed(
	item_id: String,
	_old_relation: Dictionary,
	_new_relation: Dictionary
) -> void:
	presenter.synchronize_item(item_id)


func _on_item_removed(item_id: String) -> void:
	presenter.synchronize_item(item_id)


func _on_quantity_changed(
	item_id: String,
	_old_quantity: int,
	_new_quantity: int
) -> void:
	presenter.synchronize_item(item_id)


func _refresh() -> void:
	presenter.synchronize_all()
	var snapshot = get_debug_snapshot()
	action_label.text = "Последняя операция: %s" % String(
		last_action_result.get("message", "-")
	)
	action_label.modulate = (
		Color(0.45, 0.95, 0.58)
		if bool(last_action_result.get("success", false))
		else Color(1.0, 0.42, 0.30)
	)
	status_label.text = (
		"Камень: %s | физика: %s | texture: %s\n"
		+ "Ящик: %s | физика: %s\n"
		+ "  Внутри ящика: %s\n"
		+ "  Положение содержимого: %s\n"
		+ "Лидар: %s | world body: %s | attached: %s\n"
		+ "Сокет ровера: %s\n"
		+ "Рюкзак: %s\n"
		+ "Масса рюкзака: %.2f кг\n"
		+ "Корпус имеет внешнее представление: %s\n"
		+ "Целостность графа: %s"
	) % [
		snapshot.rock_relation,
		str(snapshot.rock_world_body),
		str(snapshot.rock_has_texture),
		snapshot.crate_relation,
		str(snapshot.crate_world_body),
		str(snapshot.crate_item_ids),
		snapshot.crate_rocks_relation,
		snapshot.lidar_relation,
		str(snapshot.lidar_world_body),
		str(snapshot.lidar_attached_node),
		snapshot.socket_item_id,
		str(snapshot.backpack_item_ids),
		float(snapshot.backpack_mass_kg),
		str(not snapshot.chassis_world_body),
		str(snapshot.graph_result),
	]


func _relation_kind(item_id: String) -> String:
	var item = domain.items.get_item(item_id)
	if item == null:
		return "REMOVED"
	return Relations.kind_of(item.relation)


func _operation(prefix: String) -> String:
	var result = "%s_%d" % [
		prefix,
		operation_counter,
	]
	operation_counter += 1
	return result


func _result_message(
	action_id: String,
	result: Dictionary
) -> String:
	if bool(result.get("success", false)):
		return "%s: PASS" % action_id
	return "%s: FAIL %s" % [
		action_id,
		String(result.get("error_code", "UNKNOWN")),
	]


func _world_item_has_albedo_texture(
	item_id: String
) -> bool:
	var body = presenter.get_world_node(item_id)
	if body == null:
		return false
	for child in body.get_children():
		if child is MeshInstance3D:
			var material = child.material_override
			if (
				material is StandardMaterial3D
				and material.albedo_texture != null
			):
				return true
	return false


func register_runtime_commands(registry, owner_id: String) -> void:
	_register_lab_command(registry, owner_id, {
		"id": "item.action",
		"description": "Выполнить действие лаборатории по идентификатору.",
		"usage": "item.action <pickup_rock|drop_rock|pickup_crate|drop_crate|pickup_lidar|attach_lidar|detach_lidar|validate>",
		"category": "items",
	}, Callable(self, "_command_item_action"))
	for action_definition in [
		["item.rock.pickup", "pickup_rock", "Поместить лунный камень в рюкзак."],
		["item.rock.drop", "drop_rock", "Вернуть лунный камень в физический мир."],
		["item.crate.pickup", "pickup_crate", "Поместить заполненный ящик в рюкзак."],
		["item.crate.drop", "drop_crate", "Вернуть заполненный ящик в физический мир."],
		["item.lidar.pickup", "pickup_lidar", "Поместить лидар в рюкзак."],
		["item.lidar.attach", "attach_lidar", "Закрепить лидар на сокете ровера."],
		["item.lidar.detach", "detach_lidar", "Снять лидар обратно в рюкзак."],
		["item.graph.validate", "validate", "Проверить граф отношений предметов."],
	]:
		_register_lab_command(registry, owner_id, {
			"id": String(action_definition[0]),
			"description": String(action_definition[2]),
			"usage": String(action_definition[0]),
			"category": "items",
		}, Callable(self, "_command_bound_action").bind(String(action_definition[1])))
	_register_lab_command(registry, owner_id, {
		"id": "item.lab.reset",
		"description": "Пересоздать предметный домен лаборатории.",
		"usage": "item.lab.reset",
		"category": "items",
	}, Callable(self, "_command_reset_lab"))


func register_runtime_tests(registry, owner_id: String) -> void:
	registry.register_test({
		"id": "world.item_lab.boot",
		"description": "Лаборатория создала предметный домен и физические представления.",
		"category": "world",
	}, Callable(self, "_test_lab_boot"), owner_id)
	registry.register_test({
		"id": "world.item_lab.relations",
		"description": "Граф предметных отношений валиден после полного цикла действий.",
		"category": "world",
	}, Callable(self, "_test_lab_relations"), owner_id)


func create_runtime_snapshot() -> Dictionary:
	return {
		"schema": "planet_simulator.item_lab_runtime.v1",
		"world_id": String(runtime_world_definition.get("id", "item_lab")),
		"universe_id": runtime_universe_id,
		"instance_id": runtime_instance_id,
		"space_id": runtime_space_id,
		"frame_id": runtime_frame_id,
		"last_action_result": last_action_result.duplicate(true),
		"items": get_debug_snapshot(),
	}


func set_runtime_mouse_capture(captured: bool) -> void:
	Input.mouse_mode = (
		Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	)


func prepare_for_unload() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _command_item_action(arguments: Array[String]) -> Dictionary:
	if arguments.is_empty():
		return {
			"success": false,
			"output": "Использование: item.action <action_id>",
		}
	var result: Dictionary = run_lab_action(arguments[0])
	result["output"] = String(last_action_result.get("message", "Действие завершено"))
	return result


func _command_bound_action(arguments: Array[String], action_id: String) -> Dictionary:
	var result: Dictionary = run_lab_action(action_id)
	result["output"] = String(last_action_result.get("message", action_id))
	return result

func _command_reset_lab(_arguments: Array[String]) -> Dictionary:
	_reset_lab_state()
	return {"success": true, "output": "Лаборатория пересоздана"}


func _reset_lab_state() -> void:
	if presenter != null and is_instance_valid(presenter):
		presenter.free()
	for child in $WorldItems.get_children():
		child.free()
	operation_counter = 1
	last_action_result = {
		"success": true,
		"message": "Лаборатория готова",
	}
	_build_domain()
	if status_label != null:
		_refresh()


func _test_lab_boot() -> Dictionary:
	_reset_lab_state()
	var snapshot: Dictionary = get_debug_snapshot()
	var passed: bool = (
		domain is Dictionary
		and not domain.is_empty()
		and bool(snapshot.get("graph_valid", false))
		and bool(snapshot.get("rock_world_body", false))
		and bool(snapshot.get("crate_world_body", false))
	)
	return {
		"success": passed,
		"passed": passed,
		"output": "PASS: item lab boot" if passed else "FAIL: item lab boot",
	}


func _test_lab_relations() -> Dictionary:
	_reset_lab_state()
	var initial_snapshot: Dictionary = get_debug_snapshot()
	var pickup_result: Dictionary = run_lab_action("pickup_lidar")
	var attach_result: Dictionary = run_lab_action("attach_lidar")
	var detach_result: Dictionary = run_lab_action("detach_lidar")
	var validation: Dictionary = run_lab_action("validate")
	var final_snapshot: Dictionary = get_debug_snapshot()
	var passed: bool = (
		bool(initial_snapshot.get("graph_valid", false))
		and bool(pickup_result.get("success", false))
		and bool(attach_result.get("success", false))
		and bool(detach_result.get("success", false))
		and bool(validation.get("success", false))
		and bool(final_snapshot.get("graph_valid", false))
	)
	var output: String = (
		"PASS: item relations cycle" if passed else "FAIL: item relations cycle"
	)
	_reset_lab_state()
	return {
		"success": passed,
		"passed": passed,
		"output": output,
	}


func _register_lab_command(
	registry,
	owner_id: String,
	definition: Dictionary,
	callback: Callable
) -> void:
	if not registry.register_command(definition, callback, owner_id):
		push_error("Item lab command registration failed: %s" % definition.get("id", ""))


func _vector_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
