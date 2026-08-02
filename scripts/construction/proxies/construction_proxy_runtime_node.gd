extends Node3D

const Packet = preload("res://scripts/construction/proxies/construction_proxy_network_packet.gd")

var _packet: Dictionary = {}
var _proxy_root: Node3D
var _interactive_root: Node3D
var _collision_root: Node3D

func _init() -> void:
	_proxy_root = Node3D.new(); _proxy_root.name = "CompiledProxyMeshes"; add_child(_proxy_root)
	_interactive_root = Node3D.new(); _interactive_root.name = "InteractiveLocalParts"; add_child(_interactive_root)
	_collision_root = Node3D.new(); _collision_root.name = "CompiledProxyCollision"; add_child(_collision_root)

func apply_packet(packet: Dictionary) -> Dictionary:
	var checked := Packet.validate(packet)
	if not bool(checked.get("success", false)): return checked
	_clear(_proxy_root); _clear(_interactive_root); _clear(_collision_root)
	name = String(packet["construct_id"]).replace("/", "__")
	position = _v3(packet["world_origin_m"]); quaternion = _q(packet["world_rotation_quaternion"])
	set_meta("construct_id", String(packet["construct_id"])); set_meta("source_checksum", String(packet["source_checksum"])); set_meta("detail_mode", String(packet["detail_mode"])); set_meta("suppressed_part_count", int(packet["suppressed_part_count"]))
	for artifact in packet["artifact_payloads"]:
		var mesh_instance := MeshInstance3D.new(); mesh_instance.name = String(artifact["artifact_kind"]).to_pascal_case() + "_" + String(artifact["artifact_id"]).right(8)
		var mesh := BoxMesh.new(); mesh.size = _v3(_size(artifact["bounds_min_m"], artifact["bounds_max_m"])); mesh_instance.mesh = mesh; mesh_instance.position = _v3(_center(artifact["bounds_min_m"], artifact["bounds_max_m"])); mesh_instance.set_meta("artifact_id", String(artifact["artifact_id"])); mesh_instance.set_meta("artifact_kind", String(artifact["artifact_kind"])); mesh_instance.set_meta("merged_quad_count", int(artifact["merged_quad_count"])); _proxy_root.add_child(mesh_instance)
		if String(packet["detail_mode"]) != "DISTANT_SHELL":
			for collision_box in artifact["collision_boxes"]:
				var body := StaticBody3D.new(); body.name = "ProxyCollision_" + String(artifact["artifact_id"]).right(8); body.position = _v3(collision_box["center_m"]); body.set_meta("artifact_id", String(artifact["artifact_id"]))
				var shape_node := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = _v3(collision_box["size_m"]); shape_node.shape = shape; body.add_child(shape_node); _collision_root.add_child(body)
	for descriptor in packet["interactive_part_descriptors"]:
		var part := Node3D.new(); part.name = String(descriptor["part_id"]).replace("/", "__"); part.position = _v3(descriptor["local_position_m"]); part.quaternion = _q(descriptor["local_rotation_quaternion"]); part.set_meta("part_id", String(descriptor["part_id"])); part.set_meta("item_instance_id", String(descriptor["item_instance_id"])); part.set_meta("exact_interactive", true)
		var mesh_instance := MeshInstance3D.new(); var mesh := BoxMesh.new(); mesh.size = _v3(descriptor["dimensions_m"]); mesh_instance.mesh = mesh; part.add_child(mesh_instance); _interactive_root.add_child(part)
	_packet = packet.duplicate(true)
	return {"success": true, "error_code": "", "message": "", "proxy_mesh_count": get_proxy_mesh_count(), "collision_proxy_count": get_collision_proxy_count(), "interactive_part_count": get_interactive_part_count()}

func get_packet() -> Dictionary: return _packet.duplicate(true)
func get_detail_mode() -> String: return String(_packet.get("detail_mode", ""))
func get_proxy_mesh_count() -> int: return _proxy_root.get_child_count()
func get_interactive_part_count() -> int: return _interactive_root.get_child_count()
func get_collision_proxy_count() -> int: return _collision_root.get_child_count()
func get_interactive_part_ids() -> Array:
	var result: Array = []
	for child in _interactive_root.get_children(): result.append(String(child.get_meta("part_id", "")))
	result.sort(); return result
func get_suppressed_part_count() -> int: return int(_packet.get("suppressed_part_count", 0))
func _clear(parent: Node) -> void:
	for child in parent.get_children(): parent.remove_child(child); child.free()
func _v3(value: Array) -> Vector3: return Vector3(float(value[0]), float(value[1]), float(value[2]))
func _q(value: Array) -> Quaternion: return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
func _center(min_v: Array, max_v: Array) -> Array: return [(float(min_v[0]) + float(max_v[0])) * 0.5, (float(min_v[1]) + float(max_v[1])) * 0.5, (float(min_v[2]) + float(max_v[2])) * 0.5]
func _size(min_v: Array, max_v: Array) -> Array: return [float(max_v[0]) - float(min_v[0]), float(max_v[1]) - float(min_v[1]), float(max_v[2]) - float(min_v[2])]
