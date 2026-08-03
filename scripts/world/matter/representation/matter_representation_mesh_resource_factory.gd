extends RefCounted

const MeshData = preload("res://scripts/simulation/representation/matter/meshing/contracts/matter_multiresolution_mesh_data.gd")
const Transition = preload("res://scripts/simulation/representation/matter/meshing/contracts/matter_cross_level_transition.gd")


static func create_array_mesh(artifact: Dictionary) -> ArrayMesh:
	if not _validate_artifact(artifact) or String(artifact["status"]) == "EMPTY":
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(artifact["vertices"])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(artifact["normals"])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(artifact["colors"])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(artifact["indices"])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func create_concave_shape(mesh_data: Dictionary) -> ConcavePolygonShape3D:
	if not bool(MeshData.validate(mesh_data).get("success", false)) \
		or String(mesh_data["status"]) != MeshData.STATUS_READY \
		or String(mesh_data["representation_key"]["artifact_kind"]) != "DETAIL":
		return null
	var vertices: PackedVector3Array = mesh_data["vertices"]
	var indices: PackedInt32Array = mesh_data["indices"]
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for index in range(indices.size()):
		faces[index] = vertices[int(indices[index])]
	if faces.is_empty():
		return null
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	return shape


static func create_vertex_color_material(two_sided: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.94
	material.metallic = 0.03
	material.cull_mode = BaseMaterial3D.CULL_DISABLED if two_sided else BaseMaterial3D.CULL_BACK
	return material


static func create_presenter(
	mesh_data: Dictionary,
	transition_artifacts: Array = [],
	material: Material = null,
	transition_material: Material = null,
	with_collision: bool = true
) -> Node3D:
	if not bool(MeshData.validate(mesh_data).get("success", false)):
		return null
	var key: Dictionary = mesh_data["representation_key"]
	for transition_value in transition_artifacts:
		if typeof(transition_value) != TYPE_DICTIONARY \
			or not bool(Transition.validate(transition_value).get("success", false)) \
			or String(transition_value["fine_representation_key"]["checksum"]) != String(key["checksum"]):
			return null
	var root := Node3D.new()
	root.name = "MatterRepresentation_%s" % String(key["checksum"]).substr(0, 12)
	root.position = mesh_data["origin_body_local_m"]
	if String(mesh_data["status"]) == MeshData.STATUS_READY:
		var surface_mesh: ArrayMesh = create_array_mesh(mesh_data)
		if surface_mesh == null:
			root.free()
			return null
		var surface := MeshInstance3D.new()
		surface.name = "Surface"
		surface.mesh = surface_mesh
		surface.material_override = material if material != null else create_vertex_color_material()
		root.add_child(surface)
		if with_collision:
			var shape: ConcavePolygonShape3D = create_concave_shape(mesh_data)
			if shape != null:
				var collision_body := StaticBody3D.new()
				collision_body.name = "Collision"
				var collision_shape := CollisionShape3D.new()
				collision_shape.name = "Shape"
				collision_shape.shape = shape
				collision_body.add_child(collision_shape)
				root.add_child(collision_body)
	var transition_index: int = 0
	for transition_value in transition_artifacts:
		var transition: Dictionary = transition_value
		if String(transition["status"]) != Transition.STATUS_READY:
			continue
		var transition_mesh: ArrayMesh = create_array_mesh(transition)
		if transition_mesh == null:
			root.free()
			return null
		var transition_instance := MeshInstance3D.new()
		transition_instance.name = "Transition_%02d" % transition_index
		transition_instance.position = transition["origin_body_local_m"] - mesh_data["origin_body_local_m"]
		transition_instance.mesh = transition_mesh
		transition_instance.material_override = transition_material \
			if transition_material != null else create_vertex_color_material(true)
		root.add_child(transition_instance)
		transition_index += 1
	return root


static func _validate_artifact(artifact: Dictionary) -> bool:
	return bool(MeshData.validate(artifact).get("success", false)) \
		or bool(Transition.validate(artifact).get("success", false))
