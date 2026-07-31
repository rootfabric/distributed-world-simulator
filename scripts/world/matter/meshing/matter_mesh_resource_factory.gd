extends RefCounted

const MeshDataScript = preload("res://scripts/world/matter/meshing/matter_brick_mesh_data.gd")


static func create_array_mesh(mesh_data: Dictionary) -> ArrayMesh:
	if not bool(MeshDataScript.validate(mesh_data).get("success", false)) \
		or String(mesh_data["status"]) == MeshDataScript.STATUS_EMPTY:
		return null
	var vertices: PackedVector3Array = mesh_data["vertices"]
	var normals: PackedVector3Array = mesh_data["normals"]
	var colors: PackedColorArray = mesh_data["colors"]
	var indices: PackedInt32Array = mesh_data["indices"]
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func create_concave_shape(mesh_data: Dictionary) -> ConcavePolygonShape3D:
	if not bool(MeshDataScript.validate(mesh_data).get("success", false)) \
		or String(mesh_data["status"]) == MeshDataScript.STATUS_EMPTY:
		return null
	var faces: PackedVector3Array = MeshDataScript.collision_faces(mesh_data)
	if faces.is_empty():
		return null
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	return shape


static func create_vertex_color_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.94
	material.metallic = 0.03
	material.cull_mode = BaseMaterial3D.CULL_BACK
	return material


static func create_presenter(
	mesh_data: Dictionary,
	material: Material = null,
	with_collision: bool = true
) -> Node3D:
	if not bool(MeshDataScript.validate(mesh_data).get("success", false)):
		return null
	var root := Node3D.new()
	root.name = "MatterBrick_%s" % String(mesh_data["address"]["address_id"]).sha256_text().substr(0, 12)
	var origin: Vector3 = mesh_data["origin_body_local_m"]
	root.position = origin
	if String(mesh_data["status"]) == MeshDataScript.STATUS_EMPTY:
		return root
	var array_mesh: ArrayMesh = create_array_mesh(mesh_data)
	if array_mesh == null:
		return null
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Surface"
	mesh_instance.mesh = array_mesh
	mesh_instance.material_override = material if material != null else create_vertex_color_material()
	root.add_child(mesh_instance)
	if with_collision:
		var shape: ConcavePolygonShape3D = create_concave_shape(mesh_data)
		if shape != null:
			var static_body := StaticBody3D.new()
			static_body.name = "Collision"
			var collision_shape := CollisionShape3D.new()
			collision_shape.name = "Shape"
			collision_shape.shape = shape
			static_body.add_child(collision_shape)
			root.add_child(static_body)
	return root
