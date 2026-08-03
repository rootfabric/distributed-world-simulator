extends RefCounted

const Lod = preload("res://scripts/construction/streaming/construction_lod_profile.gd")

static func apply(runtime_node, profile: Dictionary) -> Dictionary:
	var checked := Lod.validate(profile); if not bool(checked.get("success", false)): return checked
	if runtime_node == null or not is_instance_valid(runtime_node): return _failure("CONSTRUCTION_LOD_RUNTIME_NODE_REQUIRED")
	runtime_node.set_meta("construction_lod_tier", String(profile["lod_tier"]))
	runtime_node.set_meta("construction_mesh_detail_ratio", float(profile["mesh_detail_ratio"]))
	runtime_node.set_meta("construction_animation_enabled", bool(profile["animation_enabled"]))
	if runtime_node is Node3D: runtime_node.visible = not [Lod.IMPOSTOR, Lod.NONE].has(String(profile["lod_tier"]))
	runtime_node.process_mode = Node.PROCESS_MODE_INHERIT if bool(profile["animation_enabled"]) else Node.PROCESS_MODE_DISABLED
	_set_collision(runtime_node, bool(profile["collision_enabled"]))
	return {"success": true, "error_code": "", "message": "", "lod_tier": String(profile["lod_tier"])}

static func _set_collision(node: Node, enabled: bool) -> void:
	if node is CollisionShape3D: node.disabled = not enabled
	for child in node.get_children(): _set_collision(child, enabled)
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}
