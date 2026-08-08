class_name GarmentTopologyOcclusionBuilder
extends RefCounted

const MIN_THRESHOLD_M := 0.005
const MAX_THRESHOLD_M := 0.12
const DEFAULT_BOUNDARY_PAD_M := 0.006


static func create_masked_mesh(
	body_target: MeshInstance3D,
	character_root: Node3D,
	garment_descriptors: Array
) -> Dictionary:
	if body_target == null or body_target.mesh == null:
		return _result(false, "TOPOLOGY_BODY_MESH_MISSING")
	if character_root == null:
		return _result(false, "TOPOLOGY_CHARACTER_ROOT_MISSING")
	if not body_target.mesh is ArrayMesh:
		return _result(false, "TOPOLOGY_BODY_MESH_NOT_ARRAY_MESH", {
			"mesh_class": body_target.mesh.get_class(),
		})
	var source_mesh := body_target.mesh as ArrayMesh
	if source_mesh.get_surface_count() != 1:
		return _result(false, "TOPOLOGY_BODY_EXPECTS_SINGLE_SURFACE", {
			"surface_count": source_mesh.get_surface_count(),
		})
	if source_mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
		return _result(false, "TOPOLOGY_BODY_EXPECTS_TRIANGLES")
	if source_mesh.get_blend_shape_count() != 0:
		return _result(false, "TOPOLOGY_BODY_BLEND_SHAPES_UNSUPPORTED", {
			"blend_shape_count": source_mesh.get_blend_shape_count(),
		})
	if garment_descriptors.is_empty():
		return _result(false, "TOPOLOGY_GARMENT_DESCRIPTOR_REQUIRED")

	var arrays: Array = source_mesh.surface_get_arrays(0)
	if arrays.size() <= Mesh.ARRAY_INDEX:
		return _result(false, "TOPOLOGY_BODY_ARRAYS_INVALID")
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.is_empty():
		return _result(false, "TOPOLOGY_BODY_VERTICES_MISSING")
	var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if source_indices.is_empty():
		source_indices = PackedInt32Array()
		for vertex_index in range(vertices.size()):
			source_indices.append(vertex_index)
	if source_indices.size() % 3 != 0:
		return _result(false, "TOPOLOGY_BODY_INDEX_COUNT_INVALID", {
			"index_count": source_indices.size(),
		})

	var samplers: Array[Dictionary] = []
	var sample_count := 0
	for raw_descriptor in garment_descriptors:
		if not raw_descriptor is Dictionary:
			return _result(false, "TOPOLOGY_GARMENT_DESCRIPTOR_INVALID")
		var descriptor := raw_descriptor as Dictionary
		var scene = descriptor.get("scene")
		if not scene is PackedScene:
			return _result(false, "TOPOLOGY_GARMENT_SCENE_MISSING")
		var threshold_m := float(descriptor.get("threshold_m", 0.0))
		if not is_finite(threshold_m) or threshold_m < MIN_THRESHOLD_M or threshold_m > MAX_THRESHOLD_M:
			return _result(false, "TOPOLOGY_THRESHOLD_INVALID", {
				"threshold_m": threshold_m,
				"min_threshold_m": MIN_THRESHOLD_M,
				"max_threshold_m": MAX_THRESHOLD_M,
			})
		var boundary_pad_m := float(descriptor.get("boundary_pad_m", DEFAULT_BOUNDARY_PAD_M))
		if not is_finite(boundary_pad_m) or boundary_pad_m < 0.0 or boundary_pad_m > threshold_m:
			return _result(false, "TOPOLOGY_BOUNDARY_PAD_INVALID", {
				"boundary_pad_m": boundary_pad_m,
				"threshold_m": threshold_m,
			})
		var sampler_result: Dictionary = _build_sampler(scene as PackedScene, threshold_m, boundary_pad_m)
		if not bool(sampler_result.get("success", false)):
			return sampler_result
		var sampler: Dictionary = sampler_result.get("details", {})
		samplers.append(sampler)
		sample_count += int(sampler.get("sample_count", 0))

	var body_to_root := character_root.global_transform.affine_inverse() * body_target.global_transform
	var filtered_indices := PackedInt32Array()
	var removed_triangles := 0
	var total_triangles := source_indices.size() / 3
	for triangle_index in range(total_triangles):
		var offset := triangle_index * 3
		var i0 := int(source_indices[offset])
		var i1 := int(source_indices[offset + 1])
		var i2 := int(source_indices[offset + 2])
		if i0 < 0 or i1 < 0 or i2 < 0 or i0 >= vertices.size() or i1 >= vertices.size() or i2 >= vertices.size():
			return _result(false, "TOPOLOGY_BODY_INDEX_OUT_OF_RANGE", {"triangle_index": triangle_index})
		var p0 := body_to_root * vertices[i0]
		var p1 := body_to_root * vertices[i1]
		var p2 := body_to_root * vertices[i2]
		if _triangle_is_covered(p0, p1, p2, samplers):
			removed_triangles += 1
			continue
		filtered_indices.append(i0)
		filtered_indices.append(i1)
		filtered_indices.append(i2)

	if removed_triangles <= 0:
		return _result(false, "TOPOLOGY_MASK_REMOVED_NO_TRIANGLES", {
			"total_triangles": total_triangles,
			"sample_count": sample_count,
		})
	if filtered_indices.is_empty():
		return _result(false, "TOPOLOGY_MASK_REMOVED_ALL_TRIANGLES", {
			"total_triangles": total_triangles,
			"removed_triangles": removed_triangles,
		})

	var output_arrays: Array = arrays.duplicate(true)
	output_arrays[Mesh.ARRAY_INDEX] = filtered_indices
	var masked_mesh := ArrayMesh.new()
	masked_mesh.resource_name = "%s_TopologyMasked" % String(source_mesh.resource_name)
	masked_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, output_arrays)
	masked_mesh.surface_set_material(0, source_mesh.surface_get_material(0))

	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"mesh": masked_mesh,
		"total_triangles": total_triangles,
		"removed_triangles": removed_triangles,
		"remaining_triangles": filtered_indices.size() / 3,
		"removed_ratio": float(removed_triangles) / float(maxi(1, total_triangles)),
		"sample_count": sample_count,
		"descriptor_count": samplers.size(),
		"preserves_skin_arrays": true,
		"presentation_only": true,
		"moves_gameplay_body": false,
		"owns_network_state": false,
	})


static func _build_sampler(scene: PackedScene, threshold_m: float, boundary_pad_m: float) -> Dictionary:
	var instance = scene.instantiate()
	if not instance is Node3D:
		if instance is Node:
			(instance as Node).free()
		return _result(false, "TOPOLOGY_GARMENT_ROOT_NOT_NODE3D")
	var root := instance as Node3D
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	if meshes.is_empty():
		root.free()
		return _result(false, "TOPOLOGY_GARMENT_HAS_NO_MESHES")

	var points: Array[Vector3] = []
	var min_bound := Vector3(INF, INF, INF)
	var max_bound := Vector3(-INF, -INF, -INF)
	for mesh in meshes:
		if mesh.mesh == null:
			continue
		var mesh_to_root := _transform_to_root(mesh, root)
		for surface_index in range(mesh.mesh.get_surface_count()):
			if mesh.mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays: Array = mesh.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if vertices.is_empty():
				continue
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				indices = PackedInt32Array()
				for vertex_index in range(vertices.size()):
					indices.append(vertex_index)
			if indices.size() % 3 != 0:
				root.free()
				return _result(false, "TOPOLOGY_GARMENT_INDEX_COUNT_INVALID", {
					"mesh_name": String(mesh.name),
					"surface_index": surface_index,
				})
			for triangle_index in range(indices.size() / 3):
				var offset := triangle_index * 3
				var p0 := mesh_to_root * vertices[int(indices[offset])]
				var p1 := mesh_to_root * vertices[int(indices[offset + 1])]
				var p2 := mesh_to_root * vertices[int(indices[offset + 2])]
				for sample in [
					p0,
					p1,
					p2,
					(p0 + p1) * 0.5,
					(p1 + p2) * 0.5,
					(p2 + p0) * 0.5,
					(p0 + p1 + p2) / 3.0,
				]:
					var point: Vector3 = sample
					points.append(point)
					min_bound = Vector3(minf(min_bound.x, point.x), minf(min_bound.y, point.y), minf(min_bound.z, point.z))
					max_bound = Vector3(maxf(max_bound.x, point.x), maxf(max_bound.y, point.y), maxf(max_bound.z, point.z))

	root.free()
	if points.is_empty():
		return _result(false, "TOPOLOGY_GARMENT_HAS_NO_TRIANGLE_SAMPLES")

	var cell_size := threshold_m
	var cells: Dictionary = {}
	for point in points:
		var key := _cell_key(point, cell_size)
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(point)

	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"cells": cells,
		"cell_size": cell_size,
		"threshold_m": threshold_m,
		"threshold_sq": threshold_m * threshold_m,
		"boundary_pad_m": boundary_pad_m,
		"bounds_min": min_bound,
		"bounds_max": max_bound,
		"sample_count": points.size(),
	})


static func _triangle_is_covered(p0: Vector3, p1: Vector3, p2: Vector3, samplers: Array[Dictionary]) -> bool:
	var centroid := (p0 + p1 + p2) / 3.0
	if _point_is_covered(centroid, samplers):
		return true
	var covered := 0
	for point in [
		p0,
		p1,
		p2,
		(p0 + p1) * 0.5,
		(p1 + p2) * 0.5,
		(p2 + p0) * 0.5,
	]:
		if _point_is_covered(point, samplers):
			covered += 1
	return covered >= 2


static func _point_is_covered(point: Vector3, samplers: Array[Dictionary]) -> bool:
	for sampler in samplers:
		if _point_is_near_sampler(point, sampler):
			return true
	return false


static func _point_is_near_sampler(point: Vector3, sampler: Dictionary) -> bool:
	var pad := float(sampler.get("boundary_pad_m", DEFAULT_BOUNDARY_PAD_M))
	var min_bound: Vector3 = sampler.get("bounds_min", Vector3.ZERO)
	var max_bound: Vector3 = sampler.get("bounds_max", Vector3.ZERO)
	if (
		point.x < min_bound.x - pad or point.x > max_bound.x + pad
		or point.y < min_bound.y - pad or point.y > max_bound.y + pad
		or point.z < min_bound.z - pad or point.z > max_bound.z + pad
	):
		return false
	var cell_size := float(sampler.get("cell_size", 0.0))
	if cell_size <= 0.0:
		return false
	var center := _cell_key(point, cell_size)
	var cells: Dictionary = sampler.get("cells", {})
	var threshold_sq := float(sampler.get("threshold_sq", 0.0))
	for x_offset in range(-1, 2):
		for y_offset in range(-1, 2):
			for z_offset in range(-1, 2):
				var key := center + Vector3i(x_offset, y_offset, z_offset)
				if not cells.has(key):
					continue
				for raw_sample in cells[key]:
					var sample: Vector3 = raw_sample
					if point.distance_squared_to(sample) <= threshold_sq:
						return true
	return false


static func _cell_key(point: Vector3, cell_size: float) -> Vector3i:
	return Vector3i(
		floori(point.x / cell_size),
		floori(point.y / cell_size),
		floori(point.z / cell_size)
	)


static func _transform_to_root(node: Node3D, root: Node3D) -> Transform3D:
	var chain: Array[Transform3D] = []
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			chain.push_front((current as Node3D).transform)
		current = current.get_parent()
	var result := Transform3D.IDENTITY
	for local_transform in chain:
		result = result * local_transform
	return result


static func _collect_meshes(root_node: Node, output: Array[MeshInstance3D]) -> void:
	if root_node is MeshInstance3D:
		output.append(root_node as MeshInstance3D)
	for child in root_node.get_children():
		_collect_meshes(child, output)


static func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": success,
		"code": code,
		"details": details,
	}
