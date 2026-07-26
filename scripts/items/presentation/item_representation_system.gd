extends Node3D

const Relations = preload("res://scripts/items/domain/item_relations.gd")

var item_registry
var world_root: Node3D
var attachment_root: Node3D
var world_nodes: Dictionary = {}
var attached_nodes: Dictionary = {}


func setup(new_item_registry, new_world_root: Node3D, new_attachment_root: Node3D) -> void:
	item_registry = new_item_registry
	world_root = new_world_root
	attachment_root = new_attachment_root


func synchronize_item(item_id: String) -> void:
	var item = item_registry.get_item(item_id)
	if item == null:
		_remove_world_node(item_id)
		_remove_attached_node(item_id)
		return
	match Relations.kind_of(item.relation):
		Relations.WORLD:
			_remove_attached_node(item_id)
			_ensure_world_node(item)
		Relations.ATTACHMENT:
			_remove_world_node(item_id)
			_ensure_attached_node(item)
		_:
			_remove_world_node(item_id)
			_remove_attached_node(item_id)


func synchronize_all() -> void:
	var active: Dictionary = {}
	for item in item_registry.all_items():
		active[item.instance_id] = true
		synchronize_item(item.instance_id)
	for item_id in world_nodes.keys():
		if not active.has(item_id):
			_remove_world_node(item_id)
	for item_id in attached_nodes.keys():
		if not active.has(item_id):
			_remove_attached_node(item_id)


func get_world_node(item_id: String) -> Node3D:
	return world_nodes.get(item_id)


func get_attached_node(item_id: String) -> Node3D:
	return attached_nodes.get(item_id)


func _ensure_world_node(item) -> void:
	if world_nodes.has(item.instance_id):
		return
	var body := RigidBody3D.new()
	body.name = "WorldItem_%s" % item.instance_id
	body.set_meta("item_instance_id", item.instance_id)
	body.mass = maxf(0.01, item_registry.get_definition(item.definition_id).unit_mass_kg * float(item.quantity))
	# The main lunar project disables global Godot gravity and applies its own gravity field.
	# The isolated lab therefore supplies a small constant lunar force explicitly.
	body.constant_force = Vector3(0.0, -1.62 * body.mass, 0.0)
	body.transform = Relations.transform_from_relation(item.relation)
	body.linear_velocity = Relations.velocity_from_relation(item.relation)
	body.add_child(_create_visual(item))
	body.add_child(_create_collision(item))
	world_root.add_child(body)
	world_nodes[item.instance_id] = body


func _ensure_attached_node(item) -> void:
	if attached_nodes.has(item.instance_id):
		return
	var holder := Node3D.new()
	holder.name = "AttachedItem_%s" % item.instance_id
	holder.set_meta("item_instance_id", item.instance_id)
	holder.set_meta("socket_id", String(item.relation.get("socket_id", "")))
	holder.add_child(_create_visual(item))
	attachment_root.add_child(holder)
	attached_nodes[item.instance_id] = holder


func _create_visual(item) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	var definition = item_registry.get_definition(item.definition_id)
	var size := Vector3(0.45, 0.25, 0.45)
	if definition.has_tag("rock"):
		size = Vector3(0.28, 0.22, 0.30)
	elif definition.has_tag("container"):
		size = Vector3(0.75, 0.45, 0.55)
	elif definition.has_tag("lidar"):
		size = Vector3(0.32, 0.22, 0.32)
	box.size = size
	mesh_instance.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = _definition_color(item.definition_id)
	material.roughness = 0.75
	mesh_instance.material_override = material
	return mesh_instance


func _create_collision(item) -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var definition = item_registry.get_definition(item.definition_id)
	if definition.has_tag("rock"):
		shape.size = Vector3(0.28, 0.22, 0.30)
	elif definition.has_tag("container"):
		shape.size = Vector3(0.75, 0.45, 0.55)
	elif definition.has_tag("lidar"):
		shape.size = Vector3(0.32, 0.22, 0.32)
	else:
		shape.size = Vector3(0.45, 0.25, 0.45)
	collision.shape = shape
	return collision


func _definition_color(definition_id: String) -> Color:
	match definition_id:
		"lunar_rock":
			return Color(0.44, 0.46, 0.50)
		"portable_crate":
			return Color(0.58, 0.37, 0.16)
		"lidar_module":
			return Color(0.10, 0.72, 0.78)
	return Color(0.70, 0.70, 0.72)


func _remove_world_node(item_id: String) -> void:
	var node: Node = world_nodes.get(item_id)
	if node != null:
		node.queue_free()
	world_nodes.erase(item_id)


func _remove_attached_node(item_id: String) -> void:
	var node: Node = attached_nodes.get(item_id)
	if node != null:
		node.queue_free()
	attached_nodes.erase(item_id)
