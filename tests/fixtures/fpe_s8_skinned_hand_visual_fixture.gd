extends Node3D


func _init() -> void:
	set_meta("fpe_hand_visual_schema", "planet_simulator.fpe_skinned_hand_visual_asset.v1")
	set_meta("fpe_compatible_skeleton_schema", "planet_simulator.fpe_hand_skeleton.v1")
	set_meta("fpe_rest_space_policy", "CANONICAL_COMPATIBLE_BIND_SPACE")
	set_meta("fpe_hand", "both")
	set_meta("fpe_provider_id", "fpe_s8_weighted_skinned_fixture_v1")
	set_meta("fpe_bone_map", {
		"source_hand_palm": "Palm",
		"source_index_01": "IndexProximal",
		"source_thumb_01": "ThumbProximal",
	})

	var visual := MeshInstance3D.new()
	visual.name = "WeightedSkinnedHandFixture"
	visual.mesh = _build_weighted_mesh()
	visual.skin = _build_named_skin()
	add_child(visual)


func _build_weighted_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array([
		Vector3(-0.052, 0.0, 0.025),
		Vector3(0.052, 0.0, 0.025),
		Vector3(0.052, 0.0, -0.085),
		Vector3(-0.052, 0.0, -0.085),
		Vector3(0.022, 0.002, -0.075),
		Vector3(0.046, 0.002, -0.075),
		Vector3(0.046, 0.002, -0.190),
		Vector3(0.022, 0.002, -0.190),
		Vector3(0.040, -0.002, -0.030),
		Vector3(0.067, -0.002, -0.042),
		Vector3(0.080, -0.002, -0.115),
		Vector3(0.054, -0.002, -0.105),
	])
	var normals := PackedVector3Array()
	for _index in range(vertices.size()):
		normals.append(Vector3(0.0, 1.0, 0.0))

	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for vertex_index in range(vertices.size()):
		var bind_index := 0
		if vertex_index >= 8:
			bind_index = 2
		elif vertex_index >= 4:
			bind_index = 1
		bones.append(bind_index)
		bones.append(0)
		bones.append(0)
		bones.append(0)
		weights.append(1.0)
		weights.append(0.0)
		weights.append(0.0)
		weights.append(0.0)

	var indices := PackedInt32Array([
		0, 1, 2, 0, 2, 3,
		4, 5, 6, 4, 6, 7,
		8, 9, 10, 8, 10, 11,
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.78, 0.58, 0.46, 1.0)
	material.roughness = 0.84
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	return mesh


func _build_named_skin() -> Skin:
	var skin := Skin.new()
	skin.set_bind_count(3)
	skin.set_bind_name(0, &"source_hand_palm")
	skin.set_bind_pose(0, Transform3D.IDENTITY)
	skin.set_bind_name(1, &"source_index_01")
	skin.set_bind_pose(1, Transform3D.IDENTITY)
	skin.set_bind_name(2, &"source_thumb_01")
	skin.set_bind_pose(2, Transform3D.IDENTITY)
	return skin
