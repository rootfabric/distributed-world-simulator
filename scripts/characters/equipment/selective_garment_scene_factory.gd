class_name SelectiveGarmentSceneFactory
extends RefCounted


static func create(source_scene: PackedScene, selected_mesh_names: Array) -> Dictionary:
	if source_scene == null:
		return _result(false, "MISSING_SOURCE_GARMENT_SCENE")

	var selected_set: Dictionary = {}
	for raw_name in selected_mesh_names:
		var mesh_name := String(raw_name).strip_edges()
		if not mesh_name.is_empty():
			selected_set[mesh_name] = true
	var requested := _sorted_keys(selected_set)
	if requested.is_empty():
		return _result(false, "EMPTY_GARMENT_MESH_SELECTION")

	var instance = source_scene.instantiate()
	if not instance is Node3D:
		if instance is Node:
			(instance as Node).free()
		return _result(false, "SOURCE_GARMENT_ROOT_NOT_NODE3D")
	var root := instance as Node3D

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	var available_set: Dictionary = {}
	var found_set: Dictionary = {}
	var remove: Array[MeshInstance3D] = []
	for mesh in meshes:
		var mesh_name := String(mesh.name)
		available_set[mesh_name] = true
		if selected_set.has(mesh_name):
			found_set[mesh_name] = true
		else:
			remove.append(mesh)

	var missing: Array[String] = []
	for requested_name in requested:
		if not found_set.has(requested_name):
			missing.append(requested_name)
	if not missing.is_empty():
		root.free()
		return _result(false, "GARMENT_MESH_SELECTION_NOT_FOUND", {
			"requested_mesh_names": requested,
			"missing_mesh_names": missing,
			"available_mesh_names": _sorted_keys(available_set),
		})

	for mesh in remove:
		if is_instance_valid(mesh):
			mesh.free()

	var remaining_meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, remaining_meshes)
	var remaining_names: Array[String] = []
	var skinned_count := 0
	for mesh in remaining_meshes:
		remaining_names.append(String(mesh.name))
		if mesh.skin != null or not mesh.skeleton.is_empty():
			skinned_count += 1
	remaining_names.sort()

	if remaining_names != requested:
		root.free()
		return _result(false, "GARMENT_MESH_SELECTION_RESULT_MISMATCH", {
			"requested_mesh_names": requested,
			"remaining_mesh_names": remaining_names,
		})

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	root.free()
	if pack_error != OK:
		return _result(false, "GARMENT_MESH_SELECTION_PACK_FAILED", {"error": int(pack_error)})

	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"scene": packed,
		"selected_mesh_names": remaining_names,
		"selected_mesh_count": remaining_names.size(),
		"selected_skinned_mesh_count": skinned_count,
		"source_mesh_count": meshes.size(),
		"removed_mesh_count": remove.size(),
	})


static func _collect_meshes(root_node: Node, output: Array[MeshInstance3D]) -> void:
	if root_node is MeshInstance3D:
		output.append(root_node as MeshInstance3D)
	for child in root_node.get_children():
		_collect_meshes(child, output)


static func _sorted_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in values.keys():
		result.append(String(key))
	result.sort()
	return result


static func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": success,
		"code": code,
		"details": details,
	}
