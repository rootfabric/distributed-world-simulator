extends RefCounted

const LocalSurfaceShader = preload("res://shaders/earth_surface_presentation.gdshader")

var surface_material: ShaderMaterial
var global_surface_material: StandardMaterial3D
var billboard_materials: Dictionary = {}
var grass_materials: Dictionary = {}
var rock_materials: Array[StandardMaterial3D] = []
var tree_meshes: Dictionary = {}
var billboard_meshes: Dictionary = {}
var grass_meshes: Dictionary = {}
var rock_meshes: Array[Mesh] = []


func setup() -> void:
	_create_surface_materials()
	_create_tree_assets()
	_create_grass_assets()
	_create_rock_assets()


func get_surface_material(global_lod: bool = false) -> Material:
	return global_surface_material if global_lod else surface_material


func set_surface_debug_mode(enabled: bool) -> void:
	if surface_material != null:
		surface_material.set_shader_parameter("debug_mode", enabled)
	if global_surface_material != null:
		global_surface_material.shading_mode = (
			BaseMaterial3D.SHADING_MODE_UNSHADED
			if enabled
			else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		)


func get_tree_mesh(type_id: String) -> Mesh:
	return tree_meshes.get(type_id, tree_meshes.get("broadleaf"))


func get_billboard_mesh(type_id: String) -> Mesh:
	return billboard_meshes.get(type_id, billboard_meshes.get("broadleaf"))


func get_billboard_material(type_id: String) -> Material:
	return billboard_materials.get(type_id, billboard_materials.get("broadleaf"))


func get_grass_mesh(type_id: String) -> Mesh:
	return grass_meshes.get(type_id, grass_meshes.get("short"))


func get_grass_material(type_id: String) -> Material:
	return grass_materials.get(type_id, grass_materials.get("short"))


func get_rock_mesh(index: int) -> Mesh:
	return rock_meshes[index % rock_meshes.size()]


func get_rock_material(index: int) -> Material:
	return rock_materials[index % rock_materials.size()]


func _create_surface_materials() -> void:
	# V0-P1 is presentation-only. The procedural mesh continues to supply the
	# canonical biome/surface vertex color; the shader adds deterministic local
	# macro/detail variation without changing geometry, collision or gameplay.
	surface_material = ShaderMaterial.new()
	surface_material.shader = LocalSurfaceShader
	surface_material.set_shader_parameter("debug_mode", false)

	# Keep global/orbital LOD intentionally cheap and unchanged in semantics.
	global_surface_material = StandardMaterial3D.new()
	global_surface_material.vertex_color_use_as_albedo = true
	global_surface_material.roughness = 0.88
	global_surface_material.metallic = 0.0
	global_surface_material.cull_mode = BaseMaterial3D.CULL_BACK


func _create_tree_assets() -> void:
	var definitions := {
		"conifer": {
			"trunk": Color(0.20, 0.115, 0.055),
			"crown": Color(0.035, 0.19, 0.075),
			"billboard_size": Vector2(7.2, 13.5),
		},
		"broadleaf": {
			"trunk": Color(0.22, 0.13, 0.065),
			"crown": Color(0.075, 0.30, 0.075),
			"billboard_size": Vector2(10.5, 11.5),
		},
		"columnar": {
			"trunk": Color(0.18, 0.105, 0.05),
			"crown": Color(0.045, 0.245, 0.095),
			"billboard_size": Vector2(5.8, 14.0),
		},
		"small_broadleaf": {
			"trunk": Color(0.24, 0.15, 0.07),
			"crown": Color(0.11, 0.34, 0.09),
			"billboard_size": Vector2(7.0, 7.5),
		},
	}
	for type_id in definitions.keys():
		var definition: Dictionary = definitions[type_id]
		tree_meshes[type_id] = _create_tree_mesh(
			type_id,
			definition["trunk"],
			definition["crown"]
		)

		var billboard_material := StandardMaterial3D.new()
		billboard_material.albedo_texture = _create_tree_texture(
			type_id,
			definition["trunk"],
			definition["crown"]
		)
		billboard_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		billboard_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		billboard_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		billboard_material.billboard_keep_scale = true
		billboard_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		billboard_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		billboard_materials[type_id] = billboard_material
		var billboard_size: Vector2 = definition["billboard_size"]
		var quad := QuadMesh.new()
		quad.size = billboard_size
		quad.center_offset = Vector3(0.0, billboard_size.y * 0.5, 0.0)
		billboard_meshes[type_id] = quad


func _create_tree_mesh(type_id: String, trunk_color: Color, crown_color: Color) -> ArrayMesh:
	var mesh := ArrayMesh.new()

	var trunk_surface := SurfaceTool.new()
	trunk_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.26
	trunk.bottom_radius = 0.34
	trunk.height = 4.6
	trunk.radial_segments = 7
	trunk.rings = 1
	_append_colored_mesh(
		trunk_surface,
		trunk,
		Transform3D(Basis.IDENTITY, Vector3(0.0, 2.3, 0.0)),
		trunk_color
	)
	trunk_surface.commit(mesh)
	mesh.surface_set_material(0, _create_colored_material(trunk_color))

	var crown_surface := SurfaceTool.new()
	crown_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	match type_id:
		"conifer":
			_append_cone(crown_surface, 3.6, 0.0, 5.0, 4.6, crown_color.darkened(0.06))
			_append_cone(crown_surface, 3.0, 0.0, 4.6, 7.1, crown_color)
			_append_cone(crown_surface, 2.25, 0.0, 4.0, 9.2, crown_color.lightened(0.035))
		"columnar":
			_append_scaled_sphere(
				crown_surface,
				Vector3(2.15, 5.4, 2.15),
				Vector3(0.0, 7.1, 0.0),
				crown_color
			)
		"small_broadleaf":
			_append_scaled_sphere(
				crown_surface,
				Vector3(3.3, 2.7, 3.2),
				Vector3(0.0, 5.7, 0.0),
				crown_color
			)
		_:
			_append_scaled_sphere(
				crown_surface,
				Vector3(4.5, 3.5, 4.2),
				Vector3(0.0, 6.7, 0.0),
				crown_color
			)
			_append_scaled_sphere(
				crown_surface,
				Vector3(2.9, 2.8, 2.9),
				Vector3(2.6, 6.1, 0.6),
				crown_color.lightened(0.03)
			)
	crown_surface.commit(mesh)
	mesh.surface_set_material(1, _create_colored_material(crown_color))
	return mesh


func _create_colored_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	return material


func _append_cone(
	surface_tool: SurfaceTool,
	bottom_radius: float,
	top_radius: float,
	height: float,
	center_y: float,
	color: Color
) -> void:
	var cone := CylinderMesh.new()
	cone.bottom_radius = bottom_radius
	cone.top_radius = top_radius
	cone.height = height
	cone.radial_segments = 8
	cone.rings = 1
	_append_colored_mesh(
		surface_tool,
		cone,
		Transform3D(Basis.IDENTITY, Vector3(0.0, center_y, 0.0)),
		color
	)


func _append_scaled_sphere(
	surface_tool: SurfaceTool,
	scale_value: Vector3,
	position_value: Vector3,
	color: Color
) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	var basis := Basis.IDENTITY.scaled(scale_value)
	_append_colored_mesh(
		surface_tool,
		sphere,
		Transform3D(basis, position_value),
		color
	)


func _append_colored_mesh(
	surface_tool: SurfaceTool,
	mesh: Mesh,
	transform_value: Transform3D,
	_color: Color
) -> void:
	surface_tool.append_from(mesh, 0, transform_value)


func _create_tree_texture(type_id: String, trunk_color: Color, crown_color: Color) -> ImageTexture:
	var width: int = 64
	var height: int = 128
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in range(height):
		var v: float = 1.0 - float(y) / float(height - 1)
		for x in range(width):
			var u: float = float(x) / float(width - 1) * 2.0 - 1.0
			var color := Color(0.0, 0.0, 0.0, 0.0)
			if absf(u) < 0.075 and v < 0.47:
				color = trunk_color
			var crown: bool = false
			match type_id:
				"conifer":
					var width_at_height: float = (1.0 - v) * 0.90
					crown = v > 0.20 and absf(u) < width_at_height
				"columnar":
					var oval: float = u * u / 0.22 + pow((v - 0.62) / 0.40, 2.0)
					crown = oval < 1.0
				"small_broadleaf":
					var small_oval: float = u * u / 0.58 + pow((v - 0.61) / 0.28, 2.0)
					crown = small_oval < 1.0
				_:
					var broad_oval: float = u * u / 0.78 + pow((v - 0.65) / 0.31, 2.0)
					crown = broad_oval < 1.0
			if crown:
				var edge_mix: float = clampf(absf(u) * 0.22 + (1.0 - v) * 0.08, 0.0, 0.16)
				color = crown_color.lightened(edge_mix)
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _create_grass_assets() -> void:
	var definitions := {
		"short": {"height": 0.46, "width": 0.24, "color": Color(0.18, 0.42, 0.08)},
		"meadow": {"height": 0.78, "width": 0.32, "color": Color(0.28, 0.51, 0.10)},
		"coarse": {"height": 1.05, "width": 0.40, "color": Color(0.36, 0.47, 0.12)},
	}
	for type_id in definitions.keys():
		var definition: Dictionary = definitions[type_id]
		grass_meshes[type_id] = _create_cross_blade_mesh(
			float(definition["width"]),
			float(definition["height"])
		)
		var material := StandardMaterial3D.new()
		material.albedo_color = definition["color"]
		material.roughness = 1.0
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		grass_materials[type_id] = material


func _create_cross_blade_mesh(width: float, height: float) -> ArrayMesh:
	var vertices := PackedVector3Array([
		Vector3(-width, 0.0, 0.0), Vector3(width, 0.0, 0.0), Vector3(0.0, height, 0.0),
		Vector3(0.0, 0.0, -width), Vector3(0.0, 0.0, width), Vector3(0.0, height, 0.0),
	])
	var normals := PackedVector3Array([
		Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD,
		Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT,
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _create_rock_assets() -> void:
	var colors := [
		Color(0.31, 0.30, 0.285),
		Color(0.40, 0.38, 0.34),
		Color(0.25, 0.27, 0.29),
	]
	for index in range(3):
		var sphere := SphereMesh.new()
		sphere.radius = 0.72 + float(index) * 0.12
		sphere.height = sphere.radius * 1.65
		sphere.radial_segments = 7 + index
		sphere.rings = 4 + index
		rock_meshes.append(sphere)
		var material := StandardMaterial3D.new()
		material.albedo_color = colors[index]
		material.roughness = 0.98
		rock_materials.append(material)
