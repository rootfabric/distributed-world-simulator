extends Node3D

const Relations = preload("res://scripts/items/domain/item_relations.gd")

const ROCK_ALBEDO_PATH := "res://assets/textures/generated/rock_surface_albedo.png"
const ROCK_NORMAL_PATH := "res://assets/textures/generated/rock_surface_normal.png"
const ROCK_ROUGHNESS_PATH := "res://assets/textures/generated/rock_surface_roughness.png"

var item_registry
var world_root: Node3D
var default_attachment_root: Node3D
var show_debug_labels: bool = false

var world_nodes: Dictionary = {}
var attached_nodes: Dictionary = {}
var attachment_anchors: Dictionary = {}


func setup(
	new_item_registry,
	new_world_root: Node3D,
	new_attachment_root: Node3D,
	debug_labels: bool = false
) -> void:
	item_registry = new_item_registry
	world_root = new_world_root
	default_attachment_root = new_attachment_root
	show_debug_labels = debug_labels


func register_attachment_anchor(
	assembly_id: String,
	socket_id: String,
	anchor: Node3D
) -> void:
	if anchor == null:
		return
	attachment_anchors[_anchor_key(assembly_id, socket_id)] = anchor


func synchronize_item(item_id: String) -> void:
	var item = item_registry.get_item(item_id)
	if item == null:
		_remove_world_node(item_id)
		_remove_attached_node(item_id)
		return
	if _uses_external_presentation(item):
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


func capture_world_state(item_id: String) -> bool:
	var item = item_registry.get_item(item_id)
	var body: RigidBody3D = world_nodes.get(item_id)
	if (
		item == null
		or body == null
		or not is_instance_valid(body)
		or Relations.kind_of(item.relation) != Relations.WORLD
	):
		return false
	item.set_relation(Relations.update_world_state(
		item.relation,
		body.transform,
		body.linear_velocity,
		body.angular_velocity
	))
	item.revision += 1
	return true


func capture_all_world_states() -> void:
	for item_id in world_nodes.keys():
		capture_world_state(String(item_id))


func _ensure_world_node(item) -> void:
	var body: RigidBody3D = world_nodes.get(item.instance_id)
	if body == null or not is_instance_valid(body):
		body = RigidBody3D.new()
		body.name = "WorldItem_%s" % _safe_node_name(item.instance_id)
		body.set_meta("item_instance_id", item.instance_id)
		body.add_child(_create_visual_node(item))
		body.add_child(_create_collision(item))
		if show_debug_labels:
			body.add_child(_create_debug_label(item))
		world_root.add_child(body)
		world_nodes[item.instance_id] = body

	var definition = item_registry.get_definition(item.definition_id)
	body.mass = maxf(
		0.01,
		definition.unit_mass_kg * float(item.quantity)
	)
	# The main lunar project disables Godot's global gravity because the Moon
	# applies its own radial field. The isolated item lab uses a local constant
	# lunar force so loose objects visibly fall and collide with the floor.
	body.constant_force = Vector3(0.0, -1.62 * body.mass, 0.0)
	body.transform = Relations.transform_from_relation(item.relation)
	body.linear_velocity = Relations.velocity_from_relation(item.relation)
	body.angular_velocity = Relations.angular_velocity_from_relation(item.relation)


func _ensure_attached_node(item) -> void:
	var assembly_id = String(item.relation.get("assembly_id", ""))
	var socket_id = String(item.relation.get("socket_id", ""))
	var anchor = _resolve_attachment_anchor(assembly_id, socket_id)
	var holder: Node3D = attached_nodes.get(item.instance_id)

	if holder == null or not is_instance_valid(holder):
		holder = Node3D.new()
		holder.name = "AttachedItem_%s" % _safe_node_name(item.instance_id)
		holder.set_meta("item_instance_id", item.instance_id)
		holder.add_child(_create_visual_node(item))
		if show_debug_labels:
			holder.add_child(_create_debug_label(item))
		anchor.add_child(holder)
		attached_nodes[item.instance_id] = holder
	elif holder.get_parent() != anchor:
		holder.reparent(anchor, false)

	holder.position = Vector3.ZERO
	holder.rotation = Vector3.ZERO
	holder.set_meta("assembly_id", assembly_id)
	holder.set_meta("socket_id", socket_id)


func _resolve_attachment_anchor(
	assembly_id: String,
	socket_id: String
) -> Node3D:
	var anchor: Node3D = attachment_anchors.get(
		_anchor_key(assembly_id, socket_id)
	)
	return anchor if anchor != null else default_attachment_root


func _create_visual_node(item) -> Node3D:
	var definition = item_registry.get_definition(item.definition_id)
	if not definition.world_scene_path.is_empty():
		var resource = load(definition.world_scene_path)
		if resource is PackedScene:
			var scene_instance = resource.instantiate()
			if scene_instance is Node3D:
				return scene_instance

	var mesh_instance = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = _definition_size(definition)
	mesh_instance.mesh = box
	mesh_instance.material_override = _create_material(definition)
	return mesh_instance


func _create_collision(item) -> CollisionShape3D:
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	var definition = item_registry.get_definition(item.definition_id)
	shape.size = _definition_size(definition)
	collision.shape = shape
	return collision


func _create_debug_label(item) -> Label3D:
	var definition = item_registry.get_definition(item.definition_id)
	var label = Label3D.new()
	label.name = "DebugLabel"
	label.text = "%s\n%s × %d" % [
		definition.display_name,
		item.instance_id,
		item.quantity,
	]
	label.font_size = 24
	label.outline_size = 4
	label.position = Vector3(
		0.0,
		_definition_size(definition).y * 0.85 + 0.25,
		0.0
	)
	label.modulate = Color(0.92, 0.96, 1.0)
	label.double_sided = true
	label.no_depth_test = true
	return label


func _definition_size(definition) -> Vector3:
	var configured = definition.metadata.get("size", [])
	if configured is Array and configured.size() >= 3:
		return Vector3(
			float(configured[0]),
			float(configured[1]),
			float(configured[2])
		)
	if definition.has_tag("rock"):
		return Vector3(0.34, 0.26, 0.36)
	if definition.has_tag("container"):
		return Vector3(0.90, 0.55, 0.68)
	if definition.has_tag("lidar"):
		return Vector3(0.38, 0.24, 0.38)
	return Vector3(0.45, 0.25, 0.45)


func _create_material(definition) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = _definition_color(definition.id)
	material.roughness = 0.75
	if definition.has_tag("rock"):
		var albedo = load(ROCK_ALBEDO_PATH)
		var normal = load(ROCK_NORMAL_PATH)
		var roughness = load(ROCK_ROUGHNESS_PATH)
		if albedo is Texture2D:
			material.albedo_texture = albedo
		if normal is Texture2D:
			material.normal_enabled = true
			material.normal_texture = normal
		if roughness is Texture2D:
			material.roughness_texture = roughness
	return material


func _definition_color(definition_id: String) -> Color:
	match definition_id:
		"lunar_rock", "rock":
			return Color(0.72, 0.72, 0.74)
		"portable_crate", "crate":
			return Color(0.58, 0.37, 0.16)
		"lidar_module", "lidar":
			return Color(0.10, 0.72, 0.78)
	return Color(0.70, 0.70, 0.72)


func _uses_external_presentation(item) -> bool:
	var definition = item_registry.get_definition(item.definition_id)
	if definition == null:
		return false
	return String(
		definition.metadata.get("presentation_mode", "")
	) == "EXTERNAL"


func _remove_world_node(item_id: String) -> void:
	var node: Node = world_nodes.get(item_id)
	if node != null and is_instance_valid(node):
		node.queue_free()
	world_nodes.erase(item_id)


func _remove_attached_node(item_id: String) -> void:
	var node: Node = attached_nodes.get(item_id)
	if node != null and is_instance_valid(node):
		node.queue_free()
	attached_nodes.erase(item_id)


func _anchor_key(assembly_id: String, socket_id: String) -> String:
	return assembly_id + "::" + socket_id


func _safe_node_name(value: String) -> String:
	return value.replace("/", "_").replace("\\", "_").replace(":", "_")
