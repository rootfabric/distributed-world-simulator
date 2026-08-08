class_name SkinnedGarmentPoseBridge
extends Node3D

const MIN_SOURCE_OVERLAP := 0.60

var source_skeleton: Skeleton3D
var garment_root: Node3D
var garment_skeletons: Array[Skeleton3D] = []

var _maps: Array[Dictionary] = []
var _matched_bones := 0
var _source_bone_count := 0
var _garment_bone_count := 0
var _skinned_mesh_count := 0
var _mesh_filter_active := false
var _requested_mesh_names: Array[String] = []
var _selected_mesh_names: Array[String] = []


func setup(
	p_source_skeleton: Skeleton3D,
	garment_scene: PackedScene,
	local_transform: Transform3D = Transform3D.IDENTITY,
	visible_mesh_names: Array = []
) -> Dictionary:
	clear()
	if p_source_skeleton == null:
		return _result(false, "MISSING_SOURCE_SKELETON")
	if garment_scene == null:
		return _result(false, "MISSING_GARMENT_SCENE")

	var instance = garment_scene.instantiate()
	if not instance is Node3D:
		if instance is Node:
			(instance as Node).free()
		return _result(false, "GARMENT_ROOT_NOT_NODE3D")

	source_skeleton = p_source_skeleton
	_source_bone_count = source_skeleton.get_bone_count()
	garment_root = instance as Node3D
	garment_root.name = "GarmentVisual"
	garment_root.transform = local_transform

	var filter_result := _apply_mesh_filter(garment_root, visible_mesh_names)
	if not bool(filter_result.get("success", false)):
		garment_root.free()
		garment_root = null
		source_skeleton = null
		return filter_result

	add_child(garment_root)
	_collect_skeletons(garment_root, garment_skeletons)
	_skinned_mesh_count = _count_skinned_meshes(garment_root)
	if garment_skeletons.is_empty():
		clear()
		return _result(false, "GARMENT_SKELETON_MISSING")
	if _mesh_filter_active and _skinned_mesh_count != _selected_mesh_names.size():
		var count_details := create_report()
		clear()
		return _result(false, "GARMENT_SELECTED_MESH_COUNT_MISMATCH", count_details)

	for target_skeleton in garment_skeletons:
		var map_result := _build_bone_map(source_skeleton, target_skeleton)
		var matched := int(map_result.get("matched_bones", 0))
		var source_overlap := float(map_result.get("source_overlap", 0.0))
		if source_overlap < MIN_SOURCE_OVERLAP:
			var details := create_report()
			details["failed_target_skeleton"] = String(target_skeleton.name)
			details["failed_source_overlap"] = source_overlap
			clear()
			return _result(false, "GARMENT_BONE_OVERLAP_TOO_LOW", details)
		_maps.append({
			"target": target_skeleton,
			"pairs": map_result.get("pairs", []),
		})
		_matched_bones += matched
		_garment_bone_count += target_skeleton.get_bone_count()

	process_priority = 100
	set_process(true)
	sync_pose_now()
	return _result(true, CharacterEquipmentDomain.RESULT_OK, create_report())


func clear() -> void:
	set_process(false)
	_maps.clear()
	garment_skeletons.clear()
	_matched_bones = 0
	_source_bone_count = 0
	_garment_bone_count = 0
	_skinned_mesh_count = 0
	_mesh_filter_active = false
	_requested_mesh_names.clear()
	_selected_mesh_names.clear()
	if garment_root != null and is_instance_valid(garment_root):
		var parent := garment_root.get_parent()
		if parent != null:
			parent.remove_child(garment_root)
		garment_root.queue_free()
	garment_root = null
	source_skeleton = null


func _process(_delta: float) -> void:
	sync_pose_now()


func sync_pose_now() -> Dictionary:
	if source_skeleton == null or not is_instance_valid(source_skeleton):
		return _result(false, "SOURCE_SKELETON_UNAVAILABLE")
	var copied := 0
	for map_entry in _maps:
		var target = map_entry.get("target")
		if not (target is Skeleton3D and is_instance_valid(target)):
			continue
		var target_skeleton := target as Skeleton3D
		for raw_pair in map_entry.get("pairs", []):
			var pair: Vector2i = raw_pair
			if pair.x < 0 or pair.y < 0:
				continue
			target_skeleton.set_bone_pose_position(pair.y, source_skeleton.get_bone_pose_position(pair.x))
			target_skeleton.set_bone_pose_rotation(pair.y, source_skeleton.get_bone_pose_rotation(pair.x))
			target_skeleton.set_bone_pose_scale(pair.y, source_skeleton.get_bone_pose_scale(pair.x))
			copied += 1
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {"copied_bones": copied})


func get_visual_root() -> Node3D:
	return garment_root if garment_root != null and is_instance_valid(garment_root) else null


func create_report() -> Dictionary:
	var overlaps: Array[float] = []
	for map_entry in _maps:
		var pairs = map_entry.get("pairs", [])
		overlaps.append(float(pairs.size()) / float(maxi(1, _source_bone_count)))
	return {
		"schema": "planet_simulator.skinned_garment_pose_bridge.v1",
		"source_bone_count": _source_bone_count,
		"garment_skeleton_count": garment_skeletons.size(),
		"garment_bone_count": _garment_bone_count,
		"matched_bones": _matched_bones,
		"source_overlaps": overlaps,
		"skinned_mesh_count": _skinned_mesh_count,
		"mesh_filter_active": _mesh_filter_active,
		"requested_mesh_names": _requested_mesh_names.duplicate(),
		"selected_mesh_names": _selected_mesh_names.duplicate(),
		"ready": source_skeleton != null and garment_root != null and not _maps.is_empty(),
		"moves_gameplay_body": false,
		"reads_input": false,
		"owns_network_state": false,
	}


func _apply_mesh_filter(root_node: Node, visible_mesh_names: Array) -> Dictionary:
	var requested_set: Dictionary = {}
	for raw_name in visible_mesh_names:
		var mesh_name := String(raw_name).strip_edges()
		if not mesh_name.is_empty():
			requested_set[mesh_name] = true
	_requested_mesh_names = _sorted_string_keys(requested_set)
	_mesh_filter_active = not _requested_mesh_names.is_empty()
	if not _mesh_filter_active:
		var all_meshes: Array[MeshInstance3D] = []
		_collect_mesh_instances(root_node, all_meshes)
		for mesh in all_meshes:
			_selected_mesh_names.append(String(mesh.name))
		_selected_mesh_names.sort()
		return _result(true, CharacterEquipmentDomain.RESULT_OK)

	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(root_node, meshes)
	var found: Dictionary = {}
	var remove: Array[MeshInstance3D] = []
	for mesh in meshes:
		var mesh_name := String(mesh.name)
		if requested_set.has(mesh_name):
			found[mesh_name] = true
		else:
			remove.append(mesh)

	var missing: Array[String] = []
	for requested_name in _requested_mesh_names:
		if not found.has(requested_name):
			missing.append(requested_name)
	if not missing.is_empty():
		return _result(false, "GARMENT_REQUESTED_MESH_MISSING", {
			"requested_mesh_names": _requested_mesh_names.duplicate(),
			"missing_mesh_names": missing,
			"available_mesh_names": _mesh_names(meshes),
		})

	for mesh in remove:
		if is_instance_valid(mesh):
			mesh.free()
	_selected_mesh_names = _sorted_string_keys(found)
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"selected_mesh_names": _selected_mesh_names.duplicate(),
	})


func _build_bone_map(source: Skeleton3D, target: Skeleton3D) -> Dictionary:
	var target_by_name: Dictionary = {}
	for target_index in range(target.get_bone_count()):
		var key := _normalized_bone_name(String(target.get_bone_name(target_index)))
		if not target_by_name.has(key):
			target_by_name[key] = target_index

	var pairs: Array[Vector2i] = []
	for source_index in range(source.get_bone_count()):
		var key := _normalized_bone_name(String(source.get_bone_name(source_index)))
		if target_by_name.has(key):
			pairs.append(Vector2i(source_index, int(target_by_name[key])))
	return {
		"pairs": pairs,
		"matched_bones": pairs.size(),
		"source_overlap": float(pairs.size()) / float(maxi(1, source.get_bone_count())),
		"target_overlap": float(pairs.size()) / float(maxi(1, target.get_bone_count())),
	}


func _collect_skeletons(root_node: Node, output: Array[Skeleton3D]) -> void:
	if root_node is Skeleton3D:
		output.append(root_node as Skeleton3D)
	for child in root_node.get_children():
		_collect_skeletons(child, output)


func _collect_mesh_instances(root_node: Node, output: Array[MeshInstance3D]) -> void:
	if root_node is MeshInstance3D:
		output.append(root_node as MeshInstance3D)
	for child in root_node.get_children():
		_collect_mesh_instances(child, output)


func _count_skinned_meshes(root_node: Node) -> int:
	var count := 0
	if root_node is MeshInstance3D:
		var mesh := root_node as MeshInstance3D
		if mesh.skin != null or not mesh.skeleton.is_empty():
			count += 1
	for child in root_node.get_children():
		count += _count_skinned_meshes(child)
	return count


func _mesh_names(meshes: Array[MeshInstance3D]) -> Array[String]:
	var result: Array[String] = []
	for mesh in meshes:
		result.append(String(mesh.name))
	result.sort()
	return result


func _sorted_string_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in values.keys():
		result.append(String(key))
	result.sort()
	return result


func _normalized_bone_name(value: String) -> String:
	var normalized := value.to_lower()
	for token in ["_", "-", " ", "/", ".", ":", "|"]:
		normalized = normalized.replace(token, "")
	for prefix in ["mixamorig", "def", "org", "armature"]:
		if normalized.begins_with(prefix):
			normalized = normalized.trim_prefix(prefix)
	return normalized.replace("left", "l").replace("right", "r")


func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": success,
		"code": code,
		"details": details.duplicate(true),
	}
