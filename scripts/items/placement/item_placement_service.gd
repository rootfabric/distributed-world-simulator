extends Node

const Relations = preload("res://scripts/items/domain/item_relations.gd")
const PlacementContract = preload("res://scripts/items/placement/item_placement_contract.gd")
const ItemMountSocket = preload("res://scripts/items/presentation/item_mount_socket.gd")

var gameplay_controller
var actor: Node3D
var world_root: Node3D
var fixture_nodes: Dictionary = {}
var placement_factories: Dictionary = {}


func setup(controller, actor_reference: Node3D, world_root_reference: Node3D) -> void:
	gameplay_controller = controller
	actor = actor_reference
	world_root = world_root_reference
	register_placement_factory(PlacementContract.KIND_MOUNT_SOCKET, Callable(self, "_create_mount_socket_fixture"))


func register_placement_factory(kind: String, factory: Callable) -> void:
	var normalized := kind.strip_edges().to_upper()
	if normalized.is_empty() or not factory.is_valid():
		return
	placement_factories[normalized] = factory


func can_place_definition(definition) -> bool:
	var profile := PlacementContract.get_profile(definition)
	return not profile.is_empty() and placement_factories.has(String(profile.get("kind", "")))


func query_surface_from_actor(definition) -> Dictionary:
	if actor == null or not is_instance_valid(actor) or not actor.has_method("get_active_camera"):
		return {"success": false, "error_code": "PLACEMENT_ACTOR_NOT_READY", "message": "Камера игрока недоступна"}
	var camera := actor.call("get_active_camera") as Camera3D
	if camera == null or not is_instance_valid(camera):
		return {"success": false, "error_code": "PLACEMENT_CAMERA_NOT_READY", "message": "Камера игрока недоступна"}
	var profile := PlacementContract.get_profile(definition)
	if profile.is_empty():
		return {"success": false, "error_code": "ITEM_NOT_PLACEABLE", "message": "Выбранный предмет нельзя установить"}
	var from := camera.global_position
	var forward := (-camera.global_transform.basis.z).normalized()
	var to := from + forward * float(profile.get("max_distance_m", 8.0))
	var query := PhysicsRayQueryParameters3D.create(from, to, int(profile.get("collision_mask", 1)))
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var collision_actor := actor as CollisionObject3D
	if collision_actor != null:
		query.exclude = [collision_actor.get_rid()]
	var world := actor.get_world_3d()
	if world == null:
		return {"success": false, "error_code": "PLACEMENT_WORLD_NOT_READY", "message": "Физический мир недоступен"}
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"success": false, "error_code": "PLACEMENT_SURFACE_NOT_FOUND", "message": "Наведите центр экрана на поверхность рядом с игроком"}
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var transform := PlacementContract.build_surface_transform(
		hit.get("position", to),
		normal,
		forward,
		world_root,
		float(profile.get("surface_offset_m", 0.0))
	)
	return {
		"success": true,
		"transform": transform,
		"hit_position": hit.get("position", to),
		"hit_normal": normal,
		"profile": profile,
	}


func synchronize_all() -> void:
	if gameplay_controller == null:
		return
	var active: Dictionary = {}
	for item in gameplay_controller.domain.items.all_items():
		if _is_installed_fixture(item):
			active[item.instance_id] = true
			_synchronize_fixture(item)
	for item_id in fixture_nodes.keys():
		if not active.has(item_id):
			_remove_fixture(String(item_id))


func synchronize_item(item_id: String) -> void:
	var item = gameplay_controller.get_item(item_id) if gameplay_controller != null else null
	if item != null and _is_installed_fixture(item):
		_synchronize_fixture(item)
	else:
		_remove_fixture(item_id)


func get_fixture_node(item_id: String) -> Node3D:
	return fixture_nodes.get(item_id)


func _is_installed_fixture(item) -> bool:
	if item == null or Relations.kind_of(item.relation) != Relations.WORLD:
		return false
	var placement = item.components.get("placement", {})
	return placement is Dictionary and bool(placement.get("installed", false))


func _synchronize_fixture(item) -> void:
	var definition = gameplay_controller.get_definition(item.definition_id)
	var profile := PlacementContract.get_profile(definition)
	var kind := String(profile.get("kind", ""))
	var factory: Callable = placement_factories.get(kind, Callable())
	if not factory.is_valid():
		return
	var node: Node3D = fixture_nodes.get(item.instance_id)
	if node == null or not is_instance_valid(node):
		node = factory.call(item, profile)
		if node == null:
			return
		world_root.add_child(node)
		fixture_nodes[item.instance_id] = node
	node.transform = gameplay_controller.get_world_item_transform(item.instance_id)
	_bind_mount_socket(item, node, profile)


func _create_mount_socket_fixture(item, _profile: Dictionary) -> Node3D:
	var socket := ItemMountSocket.new()
	socket.name = "PlacedMount_%s" % _safe_name(item.instance_id)
	socket.collision_layer = 1
	socket.collision_mask = 3
	socket.set_meta("item_instance_id", item.instance_id)
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.55
	mesh.bottom_radius = 0.72
	mesh.height = 0.32
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.18, 0.48, 0.60)
	material.metallic = 0.55
	material.roughness = 0.38
	mesh_instance.material_override = material
	socket.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.name = "InteractionCollision"
	var shape := CylinderShape3D.new()
	shape.radius = 0.72
	# The mounted beacon is visual-only and sits above the base. The socket owns
	# interaction, so its collider must cover that visual as well; otherwise a
	# ray aimed at the beacon misses the base and falls back to placement.
	shape.height = 1.0
	collision.shape = shape
	collision.position = Vector3(0.0, 0.34, 0.0)
	socket.add_child(collision)
	var anchor := Node3D.new()
	anchor.name = "MountedItemAnchor"
	anchor.position = Vector3(0.0, 0.42, 0.0)
	socket.add_child(anchor)
	return socket


func _bind_mount_socket(item, node: Node3D, profile: Dictionary) -> void:
	if not node is ItemMountSocket:
		return
	var placement: Dictionary = Dictionary(item.components.get("placement", {}))
	var assembly_id := String(placement.get("assembly_id", "fixture/%s" % item.instance_id))
	var socket_profile = profile.get("socket", {})
	var socket_id := String(placement.get("socket_id", Dictionary(socket_profile).get("socket_id", "primary")))
	var accepted_tags: Array = Dictionary(socket_profile).get("accepted_tags", [])
	gameplay_controller.domain.attachments.ensure_socket(assembly_id, item.instance_id, socket_id, accepted_tags)
	var anchor := node.get_node_or_null("MountedItemAnchor") as Node3D
	if anchor != null:
		gameplay_controller.presenter.register_attachment_anchor(assembly_id, socket_id, anchor)
	(node as ItemMountSocket).setup_socket(gameplay_controller, assembly_id, socket_id, item.instance_id)


func _remove_fixture(item_id: String) -> void:
	var node: Node = fixture_nodes.get(item_id)
	if node != null and is_instance_valid(node):
		node.queue_free()
	fixture_nodes.erase(item_id)


func _safe_name(value: String) -> String:
	var result := value.replace("/", "_").replace(":", "_")
	return result.left(80)
