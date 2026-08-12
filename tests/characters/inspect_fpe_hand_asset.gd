extends SceneTree

const SCENE_ARG_PREFIX := "--fpe-inspect-hand-scene="

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene_path := _find_arg(SCENE_ARG_PREFIX)
	if scene_path.is_empty():
		_fail("FPE_HAND_INSPECT_SCENE_REQUIRED")
		_finish({})
		return
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		_fail("FPE_HAND_INSPECT_SCENE_NOT_FOUND:%s" % scene_path)
		_finish({"scene_path": scene_path})
		return
	var resource: Resource = load(scene_path)
	if not resource is PackedScene:
		_fail("FPE_HAND_INSPECT_SCENE_NOT_PACKED:%s" % scene_path)
		_finish({"scene_path": scene_path})
		return
	var instance: Node = (resource as PackedScene).instantiate()
	if not instance is Node3D:
		if instance != null:
			instance.free()
		_fail("FPE_HAND_INSPECT_ROOT_NOT_NODE3D")
		_finish({"scene_path": scene_path})
		return
	get_root().add_child(instance)
	var root := instance as Node3D
	var report := {
		"schema": "planet_simulator.fpe_hand_asset_inspection.v1",
		"scene_path": scene_path,
		"root_name": root.name,
		"root_type": root.get_class(),
		"root_metadata": _safe_metadata(root),
		"skinned_meshes": [],
		"skeletons": [],
		"animation_players": [],
		"mesh_count": 0,
		"skinned_mesh_count": 0,
		"skeleton_count": 0,
		"named_skin_bind_count": 0,
		"index_only_skin_bind_count": 0,
		"weighted_surface_count": 0,
		"handedness_name_clues": [],
	}
	_walk(root, root, report)
	root.queue_free()
	_finish(report)


func _walk(node: Node, root: Node, report: Dictionary) -> void:
	var lower_name := String(node.name).to_lower()
	if "left" in lower_name or "right" in lower_name or lower_name.begins_with("l_") or lower_name.begins_with("r_"):
		var clues: Array = report["handedness_name_clues"]
		clues.append(String(root.get_path_to(node)))
	if node is Skeleton3D:
		var skeleton := node as Skeleton3D
		var bones: Array[String] = []
		for bone_index in range(skeleton.get_bone_count()):
			bones.append(skeleton.get_bone_name(bone_index))
		var skeletons: Array = report["skeletons"]
		skeletons.append({
			"node_path": String(root.get_path_to(skeleton)),
			"name": skeleton.name,
			"bone_count": skeleton.get_bone_count(),
			"bones": bones,
		})
		report["skeleton_count"] = int(report["skeleton_count"]) + 1
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		report["mesh_count"] = int(report["mesh_count"]) + 1
		if mesh_instance.mesh != null and mesh_instance.skin != null:
			var binds: Array = []
			var skin := mesh_instance.skin
			for bind_index in range(skin.get_bind_count()):
				var bind_name := String(skin.get_bind_name(bind_index)).strip_edges()
				binds.append({"index": bind_index, "name": bind_name})
				if bind_name.is_empty():
					report["index_only_skin_bind_count"] = int(report["index_only_skin_bind_count"]) + 1
				else:
					report["named_skin_bind_count"] = int(report["named_skin_bind_count"]) + 1
			var weighted_surfaces := _weighted_surface_count(mesh_instance.mesh)
			report["weighted_surface_count"] = int(report["weighted_surface_count"]) + weighted_surfaces
			var aabb := mesh_instance.mesh.get_aabb()
			var meshes: Array = report["skinned_meshes"]
			meshes.append({
				"node_path": String(root.get_path_to(mesh_instance)),
				"name": mesh_instance.name,
				"mesh_class": mesh_instance.mesh.get_class(),
				"skeleton_path": String(mesh_instance.skeleton),
				"skin_bind_count": skin.get_bind_count(),
				"skin_binds": binds,
				"weighted_surface_count": weighted_surfaces,
				"aabb_size": [aabb.size.x, aabb.size.y, aabb.size.z],
				"aabb_position": [aabb.position.x, aabb.position.y, aabb.position.z],
				"transform": _transform_to_array(mesh_instance.transform),
			})
			report["skinned_mesh_count"] = int(report["skinned_mesh_count"]) + 1
	if node is AnimationPlayer:
		var player := node as AnimationPlayer
		var libraries: Array = []
		for library_name in player.get_animation_library_list():
			var library := player.get_animation_library(library_name)
			libraries.append({
				"library": String(library_name),
				"animations": Array(library.get_animation_list()) if library != null else [],
			})
		var players: Array = report["animation_players"]
		players.append({"node_path": String(root.get_path_to(player)), "libraries": libraries})
	for child in node.get_children():
		_walk(child, root, report)


func _weighted_surface_count(mesh: Mesh) -> int:
	if not mesh is ArrayMesh:
		return 0
	var count := 0
	var array_mesh := mesh as ArrayMesh
	for surface_index in range(array_mesh.get_surface_count()):
		var arrays: Array = array_mesh.surface_get_arrays(surface_index)
		if arrays.size() < Mesh.ARRAY_MAX:
			continue
		var vertices_value: Variant = arrays[Mesh.ARRAY_VERTEX]
		var bones_value: Variant = arrays[Mesh.ARRAY_BONES]
		var weights_value: Variant = arrays[Mesh.ARRAY_WEIGHTS]
		if typeof(vertices_value) != TYPE_PACKED_VECTOR3_ARRAY:
			continue
		var vertex_count := (vertices_value as PackedVector3Array).size()
		if vertex_count <= 0:
			continue
		if _packed_size(bones_value) == vertex_count * 4 and _packed_size(weights_value) == vertex_count * 4:
			count += 1
	return count


func _packed_size(value: Variant) -> int:
	match typeof(value):
		TYPE_PACKED_INT32_ARRAY:
			return (value as PackedInt32Array).size()
		TYPE_PACKED_FLOAT32_ARRAY:
			return (value as PackedFloat32Array).size()
		TYPE_PACKED_FLOAT64_ARRAY:
			return (value as PackedFloat64Array).size()
		_:
			return 0


func _safe_metadata(node: Node) -> Dictionary:
	var result: Dictionary = {}
	for key in node.get_meta_list():
		var value: Variant = node.get_meta(key)
		if value is String or value is StringName or value is int or value is float or value is bool:
			result[String(key)] = value
	return result


func _transform_to_array(transform: Transform3D) -> Dictionary:
	return {
		"origin": [transform.origin.x, transform.origin.y, transform.origin.z],
		"basis_x": [transform.basis.x.x, transform.basis.x.y, transform.basis.x.z],
		"basis_y": [transform.basis.y.x, transform.basis.y.y, transform.basis.y.z],
		"basis_z": [transform.basis.z.x, transform.basis.z.y, transform.basis.z.z],
	}


func _find_arg(prefix: String) -> String:
	for raw_arg in OS.get_cmdline_user_args():
		var arg := String(raw_arg)
		if arg.begins_with(prefix):
			return arg.substr(prefix.length()).strip_edges()
	return ""


func _fail(message: String) -> void:
	failures.append(message)


func _finish(report: Dictionary) -> void:
	if failures.is_empty():
		print("FPE hand asset inspector: PASS")
		print("FPE_HAND_ASSET_INSPECTION_JSON:%s" % JSON.stringify(report))
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE hand asset inspector: FAIL")
	if not report.is_empty():
		print("FPE_HAND_ASSET_INSPECTION_JSON:%s" % JSON.stringify(report))
	quit(1)
