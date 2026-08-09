class_name GarmentVertexInflationSceneFactory
extends RefCounted

const MAX_OFFSET_M := 0.02
const MIN_HEIGHT_EPSILON_M := 0.000001


static func create(source_scene: PackedScene, height_profile: Array, included_material_names: Array = []) -> Dictionary:
	if source_scene == null:
		return _result(false, "MISSING_GARMENT_SCENE")
	var profile_result: Dictionary = _validate_profile(height_profile)
	if not bool(profile_result.get("success", false)):
		return profile_result
	var profile: Array = profile_result.get("details", {}).get("profile", [])
	var material_filter := _material_name_set(included_material_names)
	var profile_min_offset := INF
	var profile_max_offset := -INF
	for point in profile:
		var configured_offset := float((point as Dictionary).get("offset_m", 0.0))
		profile_min_offset = minf(profile_min_offset, configured_offset)
		profile_max_offset = maxf(profile_max_offset, configured_offset)

	var instance = source_scene.instantiate()
	if not instance is Node3D:
		if instance is Node:
			(instance as Node).free()
		return _result(false, "GARMENT_ROOT_NOT_NODE3D")
	var root := instance as Node3D
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	if meshes.is_empty():
		root.free()
		return _result(false, "GARMENT_VERTEX_INFLATION_HAS_NO_MESHES")

	var inflated_meshes := 0
	var inflated_vertices := 0
	var kept_surfaces := 0
	var filtered_surfaces := 0
	var observed_min_offset := INF
	var observed_max_offset := -INF
	for mesh_instance in meshes:
		var inflate_result: Dictionary = _inflate_mesh(mesh_instance, profile, material_filter)
		if not bool(inflate_result.get("success", false)):
			root.free()
			return inflate_result
		var details: Dictionary = inflate_result.get("details", {})
		inflated_meshes += 1
		inflated_vertices += int(details.get("vertex_count", 0))
		kept_surfaces += int(details.get("kept_surface_count", 0))
		filtered_surfaces += int(details.get("filtered_surface_count", 0))
		observed_min_offset = minf(observed_min_offset, float(details.get("min_offset_m", 0.0)))
		observed_max_offset = maxf(observed_max_offset, float(details.get("max_offset_m", 0.0)))

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	root.free()
	if pack_error != OK:
		return _result(false, "GARMENT_VERTEX_INFLATION_PACK_FAILED", {"error": int(pack_error)})

	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"scene": packed,
		"profile": profile.duplicate(true),
		"profile_min_offset_m": 0.0 if profile_min_offset == INF else profile_min_offset,
		"profile_max_offset_m": 0.0 if profile_max_offset == -INF else profile_max_offset,
		"mesh_count": inflated_meshes,
		"vertex_count": inflated_vertices,
		"kept_surface_count": kept_surfaces,
		"filtered_surface_count": filtered_surfaces,
		"included_material_names": _sorted_keys(material_filter),
		"min_offset_m": 0.0 if observed_min_offset == INF else observed_min_offset,
		"max_offset_m": 0.0 if observed_max_offset == -INF else observed_max_offset,
		"mutates_source_scene": false,
		"mutates_source_material": false,
		"preserves_skin_arrays": true,
		"moves_gameplay_body": false,
		"owns_network_state": false,
	})


static func _inflate_mesh(mesh_instance: MeshInstance3D, profile: Array, material_filter: Dictionary) -> Dictionary:
	if mesh_instance.mesh == null:
		return _result(false, "GARMENT_VERTEX_INFLATION_MESH_MISSING", {"mesh_name": String(mesh_instance.name)})
	if not mesh_instance.mesh is ArrayMesh:
		return _result(false, "GARMENT_VERTEX_INFLATION_REQUIRES_ARRAY_MESH", {
			"mesh_name": String(mesh_instance.name),
			"mesh_class": mesh_instance.mesh.get_class(),
		})
	var source_mesh := mesh_instance.mesh as ArrayMesh
	if source_mesh.get_blend_shape_count() != 0:
		return _result(false, "GARMENT_VERTEX_INFLATION_BLEND_SHAPES_UNSUPPORTED", {
			"mesh_name": String(mesh_instance.name),
			"blend_shape_count": source_mesh.get_blend_shape_count(),
		})

	var min_y := INF
	var max_y := -INF
	var surfaces: Array[Dictionary] = []
	var filtered_surface_count := 0
	for source_surface_index in range(source_mesh.get_surface_count()):
		if source_mesh.surface_get_primitive_type(source_surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			return _result(false, "GARMENT_VERTEX_INFLATION_REQUIRES_TRIANGLES", {
				"mesh_name": String(mesh_instance.name),
				"surface_index": source_surface_index,
			})
		var material := source_mesh.surface_get_material(source_surface_index)
		var material_name := _material_name(material)
		if not material_filter.is_empty() and not material_filter.has(material_name):
			filtered_surface_count += 1
			continue
		var arrays: Array = source_mesh.surface_get_arrays(source_surface_index)
		if arrays.size() <= Mesh.ARRAY_NORMAL:
			return _result(false, "GARMENT_VERTEX_INFLATION_ARRAYS_INVALID", {
				"mesh_name": String(mesh_instance.name),
				"surface_index": source_surface_index,
			})
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		if vertices.is_empty() or normals.size() != vertices.size():
			return _result(false, "GARMENT_VERTEX_INFLATION_NORMALS_REQUIRED", {
				"mesh_name": String(mesh_instance.name),
				"surface_index": source_surface_index,
				"vertex_count": vertices.size(),
				"normal_count": normals.size(),
			})
		for vertex in vertices:
			min_y = minf(min_y, vertex.y)
			max_y = maxf(max_y, vertex.y)
		surfaces.append({"arrays": arrays, "material": material, "material_name": material_name})

	if surfaces.is_empty():
		return _result(false, "GARMENT_VERTEX_INFLATION_NO_SELECTED_SURFACES", {
			"mesh_name": String(mesh_instance.name),
			"included_material_names": _sorted_keys(material_filter),
		})
	if min_y == INF or max_y == -INF or max_y - min_y <= MIN_HEIGHT_EPSILON_M:
		return _result(false, "GARMENT_VERTEX_INFLATION_HEIGHT_INVALID", {
			"mesh_name": String(mesh_instance.name),
			"min_y": min_y,
			"max_y": max_y,
		})

	var inflated_mesh := ArrayMesh.new()
	inflated_mesh.resource_name = "%s_VertexInflated" % String(source_mesh.resource_name)
	var total_vertices := 0
	var min_offset := INF
	var max_offset := -INF
	var kept_material_names: Array[String] = []
	for surface in surfaces:
		var output_arrays: Array = (surface["arrays"] as Array).duplicate(true)
		var vertices: PackedVector3Array = output_arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = output_arrays[Mesh.ARRAY_NORMAL]
		for vertex_index in range(vertices.size()):
			var height_fraction := clampf((vertices[vertex_index].y - min_y) / (max_y - min_y), 0.0, 1.0)
			var offset_m := _sample_profile(profile, height_fraction)
			var normal := normals[vertex_index]
			if normal.length_squared() > 0.00000001:
				vertices[vertex_index] += normal.normalized() * offset_m
			min_offset = minf(min_offset, offset_m)
			max_offset = maxf(max_offset, offset_m)
		output_arrays[Mesh.ARRAY_VERTEX] = vertices
		inflated_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, output_arrays)
		var output_surface_index := inflated_mesh.get_surface_count() - 1
		inflated_mesh.surface_set_material(output_surface_index, surface["material"])
		kept_material_names.append(String(surface["material_name"]))
		total_vertices += vertices.size()

	mesh_instance.mesh = inflated_mesh
	kept_material_names.sort()
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"mesh_name": String(mesh_instance.name),
		"vertex_count": total_vertices,
		"kept_surface_count": surfaces.size(),
		"filtered_surface_count": filtered_surface_count,
		"kept_material_names": kept_material_names,
		"min_offset_m": 0.0 if min_offset == INF else min_offset,
		"max_offset_m": 0.0 if max_offset == -INF else max_offset,
		"height_min_m": min_y,
		"height_max_m": max_y,
	})


static func _validate_profile(raw_profile: Array) -> Dictionary:
	if raw_profile.size() < 2:
		return _result(false, "GARMENT_VERTEX_INFLATION_PROFILE_TOO_SHORT")
	var profile: Array = []
	var previous_t := -1.0
	for raw_point in raw_profile:
		if not raw_point is Dictionary:
			return _result(false, "GARMENT_VERTEX_INFLATION_PROFILE_POINT_INVALID")
		var point := raw_point as Dictionary
		var t := float(point.get("t", -1.0))
		var offset_m := float(point.get("offset_m", -1.0))
		if not is_finite(t) or t < 0.0 or t > 1.0 or t <= previous_t:
			return _result(false, "GARMENT_VERTEX_INFLATION_PROFILE_T_INVALID", {"t": t})
		if not is_finite(offset_m) or offset_m < 0.0 or offset_m > MAX_OFFSET_M:
			return _result(false, "GARMENT_VERTEX_INFLATION_PROFILE_OFFSET_INVALID", {
				"offset_m": offset_m,
				"max_offset_m": MAX_OFFSET_M,
			})
		profile.append({"t": t, "offset_m": offset_m})
		previous_t = t
	if not is_equal_approx(float(profile[0]["t"]), 0.0) or not is_equal_approx(float(profile[-1]["t"]), 1.0):
		return _result(false, "GARMENT_VERTEX_INFLATION_PROFILE_ENDPOINTS_REQUIRED")
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {"profile": profile})


static func _sample_profile(profile: Array, t: float) -> float:
	if t <= float(profile[0]["t"]):
		return float(profile[0]["offset_m"])
	for index in range(1, profile.size()):
		var right: Dictionary = profile[index]
		if t > float(right["t"]):
			continue
		var left: Dictionary = profile[index - 1]
		var span := float(right["t"]) - float(left["t"])
		if span <= 0.0:
			return float(right["offset_m"])
		var local_t := clampf((t - float(left["t"])) / span, 0.0, 1.0)
		return lerpf(float(left["offset_m"]), float(right["offset_m"]), local_t)
	return float(profile[-1]["offset_m"])


static func _material_name(material: Material) -> String:
	if material == null:
		return ""
	return String(material.resource_name).strip_edges()

static func _material_name_set(raw_names: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_name in raw_names:
		var name := String(raw_name).strip_edges()
		if not name.is_empty():
			result[name] = true
	return result

static func _sorted_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in values.keys():
		result.append(String(key))
	result.sort()
	return result

static func _collect_meshes(root_node: Node, output: Array[MeshInstance3D]) -> void:
	if root_node is MeshInstance3D:
		output.append(root_node as MeshInstance3D)
	for child in root_node.get_children():
		_collect_meshes(child, output)

static func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": success, "code": code, "details": details.duplicate(true)}
