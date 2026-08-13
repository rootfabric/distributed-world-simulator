class_name ProfiledSkinnedFirstPersonHandVisualProviderFix2
extends "res://scripts/characters/presentation/profiled_skinned_first_person_hand_visual_provider.gd"

const BIND_SPACE_FIX := "BAKE_SOURCE_TO_TARGET_BEFORE_CANONICAL_IBM"


func _build_adapted_scene(hand_id: String, target_skeleton: Skeleton3D) -> Dictionary:
	var inherited: Dictionary = super._build_adapted_scene(hand_id, target_skeleton)
	if not bool(inherited.get("success", false)):
		return inherited

	var retarget := Dictionary(hand_asset_profile.get("retarget", {}))
	var rest_policy := String(retarget.get("rest_space_policy", "")).strip_edges().to_upper()
	if rest_policy != REST_AUTO_CANONICAL_REBIND:
		return inherited

	var details := Dictionary(inherited.get("details", {})).duplicate(true)
	var scene_value: Variant = details.get("scene")
	if not scene_value is PackedScene:
		return _failure("FPE_HAND_PROFILE_BIND_SPACE_FIX_SCENE_REQUIRED")

	var instance: Node = (scene_value as PackedScene).instantiate()
	if not instance is Node3D:
		if instance != null:
			instance.free()
		return _failure("FPE_HAND_PROFILE_BIND_SPACE_FIX_ROOT_REQUIRED")
	var root := instance as Node3D
	var presentation := _profile_transform(Dictionary(hand_asset_profile.get("presentation", {})))
	if absf(presentation.basis.determinant()) <= 0.0000001:
		root.free()
		return _failure("FPE_HAND_PROFILE_PRESENTATION_TRANSFORM_SINGULAR")
	var presentation_inverse := presentation.affine_inverse()
	var baked_mesh_count := 0
	var before_aabb_size := Vector3.ZERO
	var after_aabb_size := Vector3.ZERO

	for child in root.get_children():
		if not child is MeshInstance3D:
			continue
		var mesh_instance := child as MeshInstance3D
		if not mesh_instance.mesh is ArrayMesh or mesh_instance.skin == null:
			continue
		var source_mesh := mesh_instance.mesh as ArrayMesh
		if source_mesh.get_blend_shape_count() > 0:
			root.free()
			return _failure("FPE_HAND_PROFILE_BIND_SPACE_FIX_BLEND_SHAPES_UNSUPPORTED", {
				"mesh": String(mesh_instance.name),
				"blend_shape_count": source_mesh.get_blend_shape_count(),
			})
		var bake_transform := presentation_inverse * mesh_instance.transform
		var bake_result := _bake_array_mesh_transform(source_mesh, bake_transform)
		if not bool(bake_result.get("success", false)):
			root.free()
			return bake_result
		var bake_details := Dictionary(bake_result.get("details", {}))
		var baked_value: Variant = bake_details.get("mesh")
		if not baked_value is ArrayMesh:
			root.free()
			return _failure("FPE_HAND_PROFILE_BIND_SPACE_FIX_RESULT_INVALID")
		if baked_mesh_count == 0:
			before_aabb_size = source_mesh.get_aabb().size
			after_aabb_size = (baked_value as ArrayMesh).get_aabb().size
		mesh_instance.mesh = baked_value as ArrayMesh
		# Skinning now receives vertices already expressed in canonical skeleton
		# space. Keep only the optional presentation transform outside skinning.
		mesh_instance.transform = presentation
		baked_mesh_count += 1

	if baked_mesh_count <= 0:
		root.free()
		return _failure("FPE_HAND_PROFILE_BIND_SPACE_FIX_NO_SKINNED_MESHES")

	var repacked := PackedScene.new()
	var pack_error := repacked.pack(root)
	root.free()
	if pack_error != OK:
		return _failure("FPE_HAND_PROFILE_BIND_SPACE_FIX_PACK_FAILED", {"error": int(pack_error)})

	var adaptation := Dictionary(details.get("adaptation_report", {})).duplicate(true)
	adaptation["calibration_baked_into_vertices"] = true
	adaptation["canonical_ibm_applied_after_vertex_bake"] = true
	adaptation["bind_space_fix"] = BIND_SPACE_FIX
	adaptation["baked_mesh_count"] = baked_mesh_count
	adaptation["pre_bake_aabb_size"] = [before_aabb_size.x, before_aabb_size.y, before_aabb_size.z]
	adaptation["post_bake_aabb_size"] = [after_aabb_size.x, after_aabb_size.y, after_aabb_size.z]
	details["scene"] = repacked
	details["adaptation_report"] = adaptation
	return _success(details)


func _bake_array_mesh_transform(source: ArrayMesh, transform: Transform3D) -> Dictionary:
	if source == null or source.get_surface_count() <= 0:
		return _failure("FPE_HAND_PROFILE_BIND_SPACE_FIX_ARRAY_MESH_REQUIRED")
	var output := ArrayMesh.new()
	var normal_basis := transform.basis.inverse().transposed()
	var tangent_basis := transform.basis.orthonormalized()
	var transformed_vertices := 0

	for surface_index in range(source.get_surface_count()):
		var arrays: Array = source.surface_get_arrays(surface_index)
		if arrays.size() < Mesh.ARRAY_MAX:
			return _failure("FPE_HAND_PROFILE_BIND_SPACE_FIX_SURFACE_ARRAYS_INVALID", {"surface": surface_index})
		var vertices_value: Variant = arrays[Mesh.ARRAY_VERTEX]
		if typeof(vertices_value) != TYPE_PACKED_VECTOR3_ARRAY:
			return _failure("FPE_HAND_PROFILE_BIND_SPACE_FIX_VERTICES_REQUIRED", {"surface": surface_index})
		var vertices := vertices_value as PackedVector3Array
		for vertex_index in range(vertices.size()):
			vertices[vertex_index] = transform * vertices[vertex_index]
			transformed_vertices += 1
		arrays[Mesh.ARRAY_VERTEX] = vertices

		var normals_value: Variant = arrays[Mesh.ARRAY_NORMAL]
		if typeof(normals_value) == TYPE_PACKED_VECTOR3_ARRAY:
			var normals := normals_value as PackedVector3Array
			for normal_index in range(normals.size()):
				normals[normal_index] = (normal_basis * normals[normal_index]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = normals

		var tangents_value: Variant = arrays[Mesh.ARRAY_TANGENT]
		if typeof(tangents_value) == TYPE_PACKED_FLOAT32_ARRAY:
			var tangents := tangents_value as PackedFloat32Array
			for tangent_index in range(0, tangents.size(), 4):
				if tangent_index + 3 >= tangents.size():
					break
				var tangent := Vector3(
					float(tangents[tangent_index]),
					float(tangents[tangent_index + 1]),
					float(tangents[tangent_index + 2])
				)
				tangent = (tangent_basis * tangent).normalized()
				tangents[tangent_index] = tangent.x
				tangents[tangent_index + 1] = tangent.y
				tangents[tangent_index + 2] = tangent.z
			arrays[Mesh.ARRAY_TANGENT] = tangents

		output.add_surface_from_arrays(source.surface_get_primitive_type(surface_index), arrays)
		output.surface_set_material(surface_index, source.surface_get_material(surface_index))

	return _success({
		"mesh": output,
		"transformed_vertices": transformed_vertices,
		"surface_count": output.get_surface_count(),
	})
