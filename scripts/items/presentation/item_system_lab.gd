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

var domain: Dictionary
var presenter
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


func _ready() -> void:
	_build_environment()
	_build_domain()
	_build_ui()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
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
				_operation("attach_lidar")
			)
		"detach_lidar":
			result = domain.attachments.detach_to_container(
				lidar.instance_id,
				"player_backpack",
				_operation("detach_lidar")
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
		Relations.world(
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
		Relations.world(
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
		Relations.world(
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
		Relations.world(
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

	presenter = Presenter.new()
	presenter.name = "ItemRepresentationSystem"
	add_child(presenter)
	presenter.setup(
		items,
		$WorldItems,
		$Rover/AttachmentRoot,
		true
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
	title.text = "ЛАБОРАТОРИЯ ПРЕДМЕТОВ v15.4.1"
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
		"1. Подобрать камень",
		"pickup_rock"
	)
	_add_action_button(
		grid,
		"2. Выбросить камень",
		"drop_rock"
	)
	_add_action_button(
		grid,
		"3. Подобрать ящик",
		"pickup_crate"
	)
	_add_action_button(
		grid,
		"4. Выбросить ящик",
		"drop_crate"
	)
	_add_action_button(
		grid,
		"5. Подобрать лидар",
		"pickup_lidar"
	)
	_add_action_button(
		grid,
		"6. Поставить лидар",
		"attach_lidar"
	)
	_add_action_button(
		grid,
		"7. Снять лидар",
		"detach_lidar"
	)
	_add_action_button(
		grid,
		"T. Проверить граф",
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
		"Вернуться в основной мир (F5 / Esc)"
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
	run_lab_action(action_id)


func _pickup(item_id: String) -> Dictionary:
	presenter.capture_world_state(item_id)
	return domain.transfer.move_item(
		item_id,
		Relations.container("player_backpack"),
		_operation("pickup")
	)


func _drop(
	item_id: String,
	position: Vector3
) -> Dictionary:
	return domain.transfer.move_item(
		item_id,
		Relations.world(
			Transform3D(
				Basis.IDENTITY,
				position
			),
			Vector3(0.0, 0.0, -1.0)
		),
		_operation("drop")
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
