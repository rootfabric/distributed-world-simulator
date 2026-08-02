extends Node3D

const Packet = preload("res://scripts/construction/proxies/construction_proxy_network_packet.gd")
const MeshCache = preload("res://scripts/construction/proxies/construction_proxy_mesh_cache.gd")

var _packet: Dictionary = {}
var _proxy_root: Node3D
var _interactive_root: Node3D
var _collision_root: Node3D
var _mesh_cache

func _init(mesh_cache = null) -> void:
	_mesh_cache = mesh_cache if mesh_cache != null else MeshCache.new()
	_proxy_root = Node3D.new()
	_proxy_root.name = "CompiledProxyMeshes"
	add_child(_proxy_root)
	_interactive_root = Node3D.new()
	_interactive_root.name = "InteractiveLocalParts"
	add_child(_interactive_root)
	_collision_root = Node3D.new()
	_collision_root.name = "CompiledProxyCollision"
	add_child(_collision_root)

func apply_packet(packet: Dictionary) -> Dictionary:
	var checked: Dictionary = Packet.validate(packet)
	if not bool(checked.get("success", false)):
		return checked
	# Materialize every resource before changing the active SceneTree. A malformed
	# artifact must not leave the previous presentation half-replaced.
	var materialized_rows: Array = []
	for artifact_value in packet["artifact_payloads"]:
		var artifact: Dictionary = artifact_value
		var materialized: Dictionary = _mesh_cache.materialize(artifact)
		if not bool(materialized.get("success", false)):
			return materialized
		materialized_rows.append({
			"artifact": artifact,
			"mesh": materialized["mesh"],
			"descriptor": materialized["descriptor"],
			"cache_hit": bool(materialized["cache_hit"]),
			"cache_bypassed": bool(materialized.get("cache_bypassed", false)),
		})

	_clear(_proxy_root)
	_clear(_interactive_root)
	_clear(_collision_root)
	name = String(packet["construct_id"]).replace("/", "__")
	position = _v3(packet["world_origin_m"])
	quaternion = _q(packet["world_rotation_quaternion"])
	set_meta("construct_id", String(packet["construct_id"]))
	set_meta("source_checksum", String(packet["source_checksum"]))
	set_meta("detail_mode", String(packet["detail_mode"]))
	set_meta("suppressed_part_count", int(packet["suppressed_part_count"]))

	var cache_hit_count := 0
	var cache_bypass_count := 0
	var total_vertices := 0
	var total_triangles := 0
	var total_surfaces := 0
	for row_value in materialized_rows:
		var row: Dictionary = row_value
		var artifact: Dictionary = row["artifact"]
		var descriptor: Dictionary = row["descriptor"]
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = String(artifact["artifact_kind"]).to_pascal_case() + "_" + String(artifact["artifact_id"]).right(8)
		mesh_instance.mesh = row["mesh"]
		mesh_instance.set_meta("artifact_id", String(artifact["artifact_id"]))
		mesh_instance.set_meta("artifact_kind", String(artifact["artifact_kind"]))
		mesh_instance.set_meta("merged_quad_count", int(artifact["merged_quad_count"]))
		mesh_instance.set_meta("array_mesh_backend", true)
		mesh_instance.set_meta("mesh_signature", String(descriptor["mesh_signature"]))
		mesh_instance.set_meta("vertex_count", int(descriptor["vertex_count"]))
		mesh_instance.set_meta("triangle_count", int(descriptor["triangle_count"]))
		mesh_instance.set_meta("surface_count", int(descriptor["surface_count"]))
		mesh_instance.set_meta("mesh_cache_hit", bool(row["cache_hit"]))
		mesh_instance.set_meta("mesh_cache_bypassed", bool(row["cache_bypassed"]))
		_proxy_root.add_child(mesh_instance)
		cache_hit_count += 1 if bool(row["cache_hit"]) else 0
		cache_bypass_count += 1 if bool(row["cache_bypassed"]) else 0
		total_vertices += int(descriptor["vertex_count"])
		total_triangles += int(descriptor["triangle_count"])
		total_surfaces += int(descriptor["surface_count"])
		if String(packet["detail_mode"]) != "DISTANT_SHELL":
			for collision_box_value in artifact["collision_boxes"]:
				var collision_box: Dictionary = collision_box_value
				var body := StaticBody3D.new()
				body.name = "ProxyCollision_" + String(artifact["artifact_id"]).right(8)
				body.position = _v3(collision_box["center_m"])
				body.set_meta("artifact_id", String(artifact["artifact_id"]))
				var shape_node := CollisionShape3D.new()
				var shape := BoxShape3D.new()
				shape.size = _v3(collision_box["size_m"])
				shape_node.shape = shape
				body.add_child(shape_node)
				_collision_root.add_child(body)
	for descriptor_value in packet["interactive_part_descriptors"]:
		var descriptor: Dictionary = descriptor_value
		var part := Node3D.new()
		part.name = String(descriptor["part_id"]).replace("/", "__")
		part.position = _v3(descriptor["local_position_m"])
		part.quaternion = _q(descriptor["local_rotation_quaternion"])
		part.set_meta("part_id", String(descriptor["part_id"]))
		part.set_meta("item_instance_id", String(descriptor["item_instance_id"]))
		part.set_meta("exact_interactive", true)
		var exact_mesh_instance := MeshInstance3D.new()
		var exact_mesh := BoxMesh.new()
		exact_mesh.size = _v3(descriptor["dimensions_m"])
		exact_mesh_instance.mesh = exact_mesh
		part.add_child(exact_mesh_instance)
		_interactive_root.add_child(part)
	_packet = packet.duplicate(true)
	return {
		"success": true,
		"error_code": "",
		"message": "",
		"proxy_mesh_count": get_proxy_mesh_count(),
		"collision_proxy_count": get_collision_proxy_count(),
		"interactive_part_count": get_interactive_part_count(),
		"mesh_cache_hit_count": cache_hit_count,
		"mesh_cache_bypass_count": cache_bypass_count,
		"vertex_count": total_vertices,
		"triangle_count": total_triangles,
		"surface_count": total_surfaces,
	}

func get_packet() -> Dictionary:
	return _packet.duplicate(true)

func get_detail_mode() -> String:
	return String(_packet.get("detail_mode", ""))

func get_proxy_mesh_count() -> int:
	return _proxy_root.get_child_count()

func get_interactive_part_count() -> int:
	return _interactive_root.get_child_count()

func get_collision_proxy_count() -> int:
	return _collision_root.get_child_count()

func get_total_proxy_vertex_count() -> int:
	var total := 0
	for child in _proxy_root.get_children():
		total += int(child.get_meta("vertex_count", 0))
	return total

func get_total_proxy_triangle_count() -> int:
	var total := 0
	for child in _proxy_root.get_children():
		total += int(child.get_meta("triangle_count", 0))
	return total

func get_total_proxy_surface_count() -> int:
	var total := 0
	for child in _proxy_root.get_children():
		total += int(child.get_meta("surface_count", 0))
	return total

func get_proxy_mesh_instances() -> Array:
	return _proxy_root.get_children()

func get_mesh_cache_stats() -> Dictionary:
	return _mesh_cache.get_stats()

func get_interactive_part_ids() -> Array:
	var result: Array = []
	for child in _interactive_root.get_children():
		result.append(String(child.get_meta("part_id", "")))
	result.sort()
	return result

func get_suppressed_part_count() -> int:
	return int(_packet.get("suppressed_part_count", 0))

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.free()

func _v3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _q(value: Array) -> Quaternion:
	return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
