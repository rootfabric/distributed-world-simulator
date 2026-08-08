extends Node3D

const Relations = preload("res://scripts/items/domain/item_relations.gd")
const GravityBodyDriver = preload(
	"res://scripts/simulation/gravity/gravity_body_driver.gd"
)
const ItemWorldBody = preload(
	"res://scripts/items/presentation/item_world_body.gd"
)
const SpatialRefScript = preload("res://scripts/simulation/spatial/spatial_ref.gd")

const ROCK_ALBEDO_PATH := "res://assets/textures/generated/rock_surface_albedo.png"
const ROCK_NORMAL_PATH := "res://assets/textures/generated/rock_surface_normal.png"
const ROCK_ROUGHNESS_PATH := "res://assets/textures/generated/rock_surface_roughness.png"

var item_registry
var world_entity_store
var world_root: Node3D
var default_attachment_root: Node3D
var show_debug_labels: bool = false
var mass_service
var gravity_field
var physics_frame_id: String = ""
var gravity_reference_body_id: String = ""
var interaction_controller

var world_nodes: Dictionary = {}
var attached_nodes: Dictionary = {}
var attachment_anchors: Dictionary = {}
var world_applied_revisions: Dictionary = {}
var world_applied_spatial_states: Dictionary = {}
var synchronization_batch_depth: int = 0


func setup(
	new_item_registry,
	new_world_root: Node3D,
	new_attachment_root: Node3D,
	debug_labels: bool = false,
	new_mass_service = null,
	new_gravity_field = null,
	new_physics_frame_id: String = "",
	new_gravity_reference_body_id: String = "",
	new_world_entity_store = null
) -> void:
	item_registry = new_item_registry
	world_root = new_world_root
	default_attachment_root = new_attachment_root
	show_debug_labels = debug_labels
	mass_service = new_mass_service
	gravity_field = new_gravity_field
	physics_frame_id = new_physics_frame_id
	gravity_reference_body_id = new_gravity_reference_body_id
	world_entity_store = new_world_entity_store


func set_interaction_controller(controller) -> void:
	interaction_controller = controller
	for item_id in world_nodes.keys():
		var body = world_nodes[item_id]
		if body != null and is_instance_valid(body) and body.has_method("setup_interaction"):
			body.setup_interaction(controller, String(item_id))


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
		_finish_synchronize()
		return
	if _uses_external_presentation(item):
		_remove_world_node(item_id)
		_remove_attached_node(item_id)
		_finish_synchronize()
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
	_finish_synchronize()


func synchronize_all() -> void:
	synchronization_batch_depth += 1
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
	synchronization_batch_depth = maxi(0, synchronization_batch_depth - 1)
	_refresh_existing_world_physics()


func get_world_node(item_id: String) -> Node3D:
	return world_nodes.get(item_id)


func get_attached_node(item_id: String) -> Node3D:
	return attached_nodes.get(item_id)


func get_world_physical_mass_kg(item_id: String) -> float:
	var body: RigidBody3D = world_nodes.get(item_id)
	return body.mass if body != null and is_instance_valid(body) else 0.0


func get_world_gravity_acceleration_mps2(item_id: String) -> Vector3:
	var body: RigidBody3D = world_nodes.get(item_id)
	if body == null or not is_instance_valid(body):
		return Vector3.ZERO
	return body.get_meta("gravity_acceleration_mps2", Vector3.ZERO)


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
	var aggregate = _get_world_aggregate(item)
	if aggregate != null:
		var current_ref: Dictionary = aggregate.spatial_ref
		var next_ref: Dictionary = SpatialRefScript.create(
			String(current_ref.get("frame_id", SpatialRefScript.DEFAULT_FRAME_ID)),
			body.transform.origin,
			body.transform.basis,
			body.linear_velocity,
			body.angular_velocity,
			float(current_ref.get("sample_time_s", 0.0)),
			String(current_ref.get("universe_id", SpatialRefScript.DEFAULT_UNIVERSE_ID)),
			String(current_ref.get("space_id", SpatialRefScript.DEFAULT_SPACE_ID)),
			String(current_ref.get("instance_id", SpatialRefScript.DEFAULT_INSTANCE_ID))
		)
		var physics_state: Dictionary = {
			"sleeping": bool(body.sleeping),
			"freeze": bool(body.freeze),
			"mass_kg": float(body.mass),
		}
		var capture_result: Dictionary = aggregate.apply_spatial_state(
			next_ref,
			physics_state,
			aggregate.partition_address,
			-1,
			aggregate.authority_epoch
		)
		if not bool(capture_result.get("success", false)):
			return false
		world_applied_spatial_states[item_id] = _aggregate_presentation_state(aggregate)
		return true
	var updated_relation: Dictionary = Relations.update_world_state(
		item.relation,
		body.transform,
		body.linear_velocity,
		body.angular_velocity
	)
	if item.relation == updated_relation:
		world_applied_revisions[item_id] = int(item.revision)
		return true
	item.set_relation(updated_relation)
	item.revision += 1
	world_applied_revisions[item_id] = int(item.revision)
	return true


func capture_all_world_states() -> void:
	for item_id in world_nodes.keys():
		capture_world_state(String(item_id))


func _ensure_world_node(item) -> void:
	var body: RigidBody3D = world_nodes.get(item.instance_id)
	var created := false
	if body == null or not is_instance_valid(body):
		body = ItemWorldBody.new()
		body.name = "WorldItem_%s" % _safe_node_name(item.instance_id)
		body.set_meta("item_instance_id", item.instance_id)
		body.add_child(_create_visual_node(item))
		body.add_child(_create_collision(item))
		if show_debug_labels:
			body.add_child(_create_debug_label(item))
		world_root.add_child(body)
		if interaction_controller != null and body.has_method("setup_interaction"):
			body.setup_interaction(interaction_controller, item.instance_id)
		world_nodes[item.instance_id] = body
		created = true

	body.mass = maxf(0.01, _physical_mass_kg(item))
	var definition = item_registry.get_definition(item.definition_id)
	body.freeze = bool(definition.metadata.get("freeze_world_body", false)) if definition != null else false

	# A live WORLD body owns its transform between explicit domain relation
	# revisions. Reapplying the stored relation during every synchronize_all()
	# made an already dropped object jump back whenever another stack item was
	# dropped. Apply pose/velocity only for a newly created representation or
	# when the item's relation revision actually changed.
	var aggregate = _get_world_aggregate(item)
	var should_apply_state: bool = created
	var spatial_ref: Dictionary = {}
	if aggregate != null:
		var presentation_state: Dictionary = _aggregate_presentation_state(aggregate)
		should_apply_state = should_apply_state or world_applied_spatial_states.get(item.instance_id, {}) != presentation_state
		spatial_ref = aggregate.spatial_ref
		if should_apply_state:
			world_applied_spatial_states[item.instance_id] = presentation_state.duplicate(true)
	else:
		var presentation_revision: int = int(item.revision)
		should_apply_state = should_apply_state or int(world_applied_revisions.get(item.instance_id, -1)) != presentation_revision
		spatial_ref = Relations.spatial_ref_from_relation(item.relation)
		if should_apply_state:
			world_applied_revisions[item.instance_id] = presentation_revision
	if should_apply_state:
		body.transform = Transform3D(
			SpatialRefScript.get_basis(spatial_ref),
			SpatialRefScript.get_position(spatial_ref)
		)
		body.linear_velocity = SpatialRefScript.get_linear_velocity(spatial_ref)
		body.angular_velocity = SpatialRefScript.get_angular_velocity(spatial_ref)
		if aggregate != null:
			body.sleeping = bool(aggregate.physics_state.get("sleeping", false))

	var gravity_driver = _ensure_gravity_driver(body)
	gravity_driver.setup(
		body,
		gravity_field,
		physics_frame_id,
		gravity_reference_body_id,
		world_root
	)


func _get_world_aggregate(item):
	if world_entity_store == null or item == null:
		return null
	var entity_id: String = Relations.world_entity_id(item.relation)
	if entity_id.is_empty():
		return null
	return world_entity_store.get_entity(entity_id)


func _aggregate_presentation_state(aggregate) -> Dictionary:
	return {
		"spatial_ref": aggregate.spatial_ref.duplicate(true),
		"physics_state": aggregate.physics_state.duplicate(true),
	}


func _finish_synchronize() -> void:
	if synchronization_batch_depth == 0:
		_refresh_existing_world_physics()


func _refresh_existing_world_physics() -> void:
	for item_id_value in world_nodes.keys():
		var item_id: String = String(item_id_value)
		var item = item_registry.get_item(item_id)
		var body: RigidBody3D = world_nodes.get(item_id)
		if item == null or body == null or not is_instance_valid(body):
			continue
		body.mass = maxf(0.01, _physical_mass_kg(item))
		var driver = body.get_node_or_null("GravityBodyDriver")
		if driver != null and driver.has_method("apply_now"):
			driver.apply_now()


func _physical_mass_kg(item) -> float:
	if mass_service != null and mass_service.has_method("item_recursive_mass_kg"):
		return float(mass_service.item_recursive_mass_kg(item.instance_id))
	var definition = item_registry.get_definition(item.definition_id)
	if definition == null:
		return 0.01
	return float(definition.unit_mass_kg) * float(item.quantity)


func _ensure_gravity_driver(body: RigidBody3D):
	var existing = body.get_node_or_null("GravityBodyDriver")
	if existing != null:
		return existing
	var driver = GravityBodyDriver.new()
	driver.name = "GravityBodyDriver"
	body.add_child(driver)
	return driver


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
		"survey_beacon":
			return Color(1.0, 0.34, 0.05)
		"battery_pack":
			return Color(0.20, 0.82, 0.32)
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
	world_applied_revisions.erase(item_id)
	world_applied_spatial_states.erase(item_id)


func _remove_attached_node(item_id: String) -> void:
	var node: Node = attached_nodes.get(item_id)
	if node != null and is_instance_valid(node):
		node.queue_free()
	attached_nodes.erase(item_id)


func _anchor_key(assembly_id: String, socket_id: String) -> String:
	return assembly_id + "::" + socket_id


func _safe_node_name(value: String) -> String:
	return value.replace("/", "_").replace("\\", "_").replace(":", "_")
