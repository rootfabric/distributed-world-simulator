extends Node3D

const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const Definition = preload("res://scripts/items/domain/item_definition.gd")
const ContainerState = preload("res://scripts/containers/container_state.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const Presenter = preload("res://scripts/items/presentation/item_representation_system.gd")

var domain: Dictionary
var presenter
var backpack
var crate
var rock
var lidar
var chassis
var status_label: Label
var operation_counter: int = 1


func _ready() -> void:
	_build_environment()
	_build_domain()
	_build_ui()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			_pickup(rock.instance_id)
		KEY_2:
			_drop(rock.instance_id, Vector3(-1.5, 2.0, 0.0))
		KEY_3:
			_pickup(crate.instance_id)
		KEY_4:
			_drop(crate.instance_id, Vector3(0.0, 2.0, 0.0))
		KEY_5:
			_pickup(lidar.instance_id)
		KEY_6:
			_attach_lidar()
		KEY_7:
			_detach_lidar()
		KEY_T:
			_run_embedded_smoke_check()


func _build_domain() -> void:
	domain = Factory.create()
	var items = domain.items
	items.register_definition(Definition.new({
		"id": "lunar_rock", "display_name": "Лунный камень", "max_stack": 50,
		"unit_mass_kg": 2.0, "external_volume_l": 0.8, "tags": ["rock", "resource"],
	}))
	items.register_definition(Definition.new({
		"id": "portable_crate", "display_name": "Переносной ящик", "max_stack": 1,
		"unit_mass_kg": 4.0, "external_volume_l": 30.0, "tags": ["container"],
	}))
	items.register_definition(Definition.new({
		"id": "lidar_module", "display_name": "Лидар", "max_stack": 1,
		"unit_mass_kg": 3.0, "external_volume_l": 5.0, "tags": ["lidar", "sensor", "mountable"],
	}))
	items.register_definition(Definition.new({
		"id": "rover_chassis", "display_name": "Корпус ровера", "max_stack": 1,
		"unit_mass_kg": 120.0, "external_volume_l": 400.0, "tags": ["assembly_root"],
	}))
	backpack = ContainerState.new({
		"container_id": "player_backpack", "owner_kind": "ACTOR", "owner_id": "player",
		"slot_count": 8, "maximum_mass_kg": 80.0, "maximum_volume_l": 100.0,
		"allow_nested_containers": true, "maximum_nested_depth": 2,
	})
	domain.containers.add_container(backpack)
	crate = items.create_item("portable_crate", 1, {
		"container": {"container_id": "crate_contents"},
	}, Relations.world(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0))))
	var crate_contents = ContainerState.new({
		"container_id": "crate_contents", "owner_kind": "ITEM_INSTANCE", "owner_id": crate.instance_id,
		"slot_count": 6, "maximum_mass_kg": 50.0, "maximum_volume_l": 24.0,
		"allow_nested_containers": false,
	})
	domain.containers.add_container(crate_contents)
	rock = items.create_item("lunar_rock", 3, {}, Relations.world(Transform3D(Basis.IDENTITY, Vector3(-1.5, 2.0, 0.0))))
	var crate_rocks = items.create_item("lunar_rock", 3, {}, Relations.container("crate_contents"))
	crate_contents.item_ids.append(crate_rocks.instance_id)
	lidar = items.create_item("lidar_module", 1, {}, Relations.world(Transform3D(Basis.IDENTITY, Vector3(1.5, 2.0, 0.0))))
	chassis = items.create_item("rover_chassis", 1, {}, Relations.world(Transform3D(Basis.IDENTITY, Vector3(4.0, 1.0, 0.0))))
	domain.attachments.register_socket("rover_01", chassis.instance_id, "roof_sensor", ["lidar"])
	presenter = Presenter.new()
	add_child(presenter)
	presenter.setup(items, $WorldItems, $Rover/AttachmentRoot)
	domain.transfer.relation_changed.connect(_on_relation_changed)
	domain.transfer.item_removed.connect(_on_item_removed)


func _build_environment() -> void:
	var world_items := Node3D.new()
	world_items.name = "WorldItems"
	add_child(world_items)
	var rover := Node3D.new()
	rover.name = "Rover"
	rover.position = Vector3(4.0, 0.65, 0.0)
	add_child(rover)
	var rover_body := MeshInstance3D.new()
	var rover_mesh := BoxMesh.new()
	rover_mesh.size = Vector3(2.6, 0.7, 1.6)
	rover_body.mesh = rover_mesh
	var rover_material := StandardMaterial3D.new()
	rover_material.albedo_color = Color(0.18, 0.24, 0.20)
	rover_body.material_override = rover_material
	rover.add_child(rover_body)
	var attachment_root := Node3D.new()
	attachment_root.name = "AttachmentRoot"
	attachment_root.position = Vector3(0.0, 0.55, 0.0)
	rover.add_child(attachment_root)
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(20.0, 0.4, 12.0)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	var floor_mesh_instance := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = floor_shape.size
	floor_mesh_instance.mesh = floor_mesh
	floor_body.add_child(floor_mesh_instance)
	floor_body.position.y = -0.2
	add_child(floor_body)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	light.shadow_enabled = true
	add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(8.0, 7.0, 11.0)
	camera.look_at_from_position(camera.position, Vector3(1.0, 0.5, 0.0))
	add_child(camera)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	status_label = Label.new()
	status_label.position = Vector2(20.0, 20.0)
	status_label.size = Vector2(760.0, 500.0)
	status_label.add_theme_font_size_override("font_size", 18)
	layer.add_child(status_label)


func _pickup(item_id: String) -> void:
	domain.transfer.move_item(item_id, Relations.container("player_backpack"), _operation("pickup"))
	_refresh()


func _drop(item_id: String, position: Vector3) -> void:
	domain.transfer.move_item(item_id, Relations.world(Transform3D(Basis.IDENTITY, position), Vector3(0.0, 0.0, -1.0)), _operation("drop"))
	_refresh()


func _attach_lidar() -> void:
	domain.attachments.attach(lidar.instance_id, "rover_01", "roof_sensor", _operation("attach"))
	_refresh()


func _detach_lidar() -> void:
	domain.attachments.detach_to_container(lidar.instance_id, "player_backpack", _operation("detach"))
	_refresh()


func _on_relation_changed(item_id: String, _old_relation: Dictionary, _new_relation: Dictionary) -> void:
	presenter.synchronize_item(item_id)


func _on_item_removed(item_id: String) -> void:
	presenter.synchronize_item(item_id)


func _refresh() -> void:
	presenter.synchronize_all()
	var rock_state = domain.items.get_item(rock.instance_id)
	var crate_state = domain.items.get_item(crate.instance_id)
	var lidar_state = domain.items.get_item(lidar.instance_id)
	status_label.text = "ITEM RELATION LAB\n\n" \
		+ "1 — подобрать камень    2 — выбросить камень\n" \
		+ "3 — подобрать ящик      4 — выбросить ящик\n" \
		+ "5 — подобрать лидар     6 — установить на ровер\n" \
		+ "7 — снять лидар в рюкзак  T — smoke check\n\n" \
		+ "Камень: %s\n" % _relation_text(rock_state) \
		+ "Ящик: %s; внутри: %d предмет(а)\n" % [_relation_text(crate_state), domain.containers.get_container("crate_contents").item_ids.size()] \
		+ "Лидар: %s\n" % _relation_text(lidar_state) \
		+ "Рюкзак: %s\n" % str(backpack.item_ids) \
		+ "Масса рюкзака: %.2f кг\n" % domain.mass.container_mass_kg("player_backpack") \
		+ "Граф: %s" % str(domain.validator.validate_graph())


func _relation_text(item) -> String:
	return "REMOVED" if item == null else str(item.relation)


func _operation(prefix: String) -> String:
	var result := "%s_%d" % [prefix, operation_counter]
	operation_counter += 1
	return result


func _run_embedded_smoke_check() -> void:
	var graph_result: Dictionary = domain.validator.validate_graph()
	print("Item relation lab smoke check: ", graph_result)

