class_name CharacterRigAdapter
extends RefCounted

var rig_profile_id := ""
var _anchor_paths: Dictionary = {}
var _body_region_paths: Dictionary = {}


func setup(
	p_rig_profile_id: String,
	anchor_paths: Dictionary,
	body_region_paths: Dictionary = {}
) -> Dictionary:
	rig_profile_id = p_rig_profile_id.strip_edges()
	_anchor_paths.clear()
	_body_region_paths.clear()
	if not CharacterEquipmentDomain.is_valid_semantic_id(rig_profile_id):
		return _result(false, "INVALID_RIG_PROFILE")
	for raw_anchor in anchor_paths.keys():
		var anchor_id := String(raw_anchor).strip_edges()
		var node_path := NodePath(String(anchor_paths[raw_anchor]))
		if CharacterEquipmentDomain.is_valid_semantic_id(anchor_id) and not node_path.is_empty():
			_anchor_paths[anchor_id] = node_path
	for raw_region in body_region_paths.keys():
		var region_id := String(raw_region).strip_edges()
		var node_path := NodePath(String(body_region_paths[raw_region]))
		if CharacterEquipmentDomain.is_valid_semantic_id(region_id) and not node_path.is_empty():
			_body_region_paths[region_id] = node_path
	return _result(true, CharacterEquipmentDomain.RESULT_OK)


func supports_anchor(anchor_id: String) -> bool:
	return _anchor_paths.has(anchor_id)


func resolve_anchor(character_visual_root: Node, anchor_id: String) -> Node3D:
	if character_visual_root == null or not _anchor_paths.has(anchor_id):
		return null
	var node := character_visual_root.get_node_or_null(_anchor_paths[anchor_id])
	return node as Node3D if node is Node3D else null


func supports_body_region(region_id: String) -> bool:
	return _body_region_paths.has(region_id)


func resolve_body_region(character_visual_root: Node, region_id: String) -> Node:
	if character_visual_root == null or not _body_region_paths.has(region_id):
		return null
	return character_visual_root.get_node_or_null(_body_region_paths[region_id])


# Resolve the rendered geometry controlled by one semantic body region. The
# default implementation expands the configured region node recursively. A
# concrete rig may override this when its imported mesh is coarser than the
# semantic regions (for example, one full-body skinned mesh).
func resolve_body_region_visuals(
	character_visual_root: Node,
	region_id: String
) -> Array[GeometryInstance3D]:
	var result: Array[GeometryInstance3D] = []
	var region_root := resolve_body_region(character_visual_root, region_id)
	if region_root != null:
		_collect_geometry_instances(region_root, result)
	return result


# Optional presentation hook for SKINNED_GARMENT. Rigid-only rigs can leave
# this unresolved and the equipment presenter will reject the strategy without
# mutating canonical equipment state.
func resolve_pose_skeleton(character_visual_root: Node) -> Skeleton3D:
	return _find_first_skeleton(character_visual_root)


# Parent under which a skinned garment should be instantiated. Generic rigs use
# their visual root; concrete rigs may return a compensated/yaw presentation root.
func resolve_skinned_parent(character_visual_root: Node) -> Node3D:
	return character_visual_root as Node3D if character_visual_root is Node3D else null


func anchor_ids() -> Array[String]:
	return _sorted_keys(_anchor_paths)


func body_region_ids() -> Array[String]:
	return _sorted_keys(_body_region_paths)


func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.character_rig_adapter.v2",
		"rig_profile_id": rig_profile_id,
		"anchors": anchor_ids(),
		"body_regions": body_region_ids(),
	}


func _find_first_skeleton(root: Node) -> Skeleton3D:
	if root == null:
		return null
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_first_skeleton(child)
		if found != null:
			return found
	return null


func _collect_geometry_instances(
	root: Node,
	output: Array[GeometryInstance3D]
) -> void:
	if root == null:
		return
	if root is GeometryInstance3D:
		output.append(root as GeometryInstance3D)
	for child in root.get_children():
		_collect_geometry_instances(child, output)


func _sorted_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in values.keys():
		result.append(String(key))
	result.sort()
	return result


func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": success,
		"code": code,
		"details": details.duplicate(true),
	}
