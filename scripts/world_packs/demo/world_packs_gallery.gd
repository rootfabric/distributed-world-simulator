extends Node3D

const PACKS := [
	{"name": "Moon Industrial", "x": -18.0, "ground": Color(0.16, 0.17, 0.18), "accent": Color(0.9, 0.28, 0.08)},
	{"name": "Mars Dust", "x": 0.0, "ground": Color(0.48, 0.18, 0.09), "accent": Color(1.0, 0.62, 0.18)},
	{"name": "Frozen", "x": 18.0, "ground": Color(0.62, 0.72, 0.78), "accent": Color(0.2, 0.7, 1.0)}
]

func _ready() -> void:
	_build_environment()
	for pack in PACKS:
		_build_pad(pack)
	_build_camera()
	print("WORLD_PACKS_GALLERY_READY")

func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.01, 0.012, 0.02)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.25, 0.27, 0.32)
	environment.ambient_light_energy = 0.55
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -25.0, 0.0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)

func _build_pad(pack: Dictionary) -> void:
	var root := Node3D.new()
	root.name = String(pack["name"]).replace(" ", "")
	root.position.x = float(pack["x"])
	add_child(root)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 14.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = pack["ground"]
	ground_material.roughness = 0.95
	ground.material_override = ground_material
	root.add_child(ground)

	for index in range(7):
		var prop := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.1 + 0.15 * index, 0.6 + 0.08 * index, 0.8)
		prop.mesh = mesh
		prop.position = Vector3(-4.5 + 1.45 * index, 0.35 + 0.04 * index, -1.7 + 0.35 * (index % 2))
		prop.rotation_degrees.y = 11.0 * index
		var prop_material := StandardMaterial3D.new()
		prop_material.albedo_color = pack["accent"]
		prop_material.metallic = 0.35
		prop_material.roughness = 0.7
		prop.material_override = prop_material
		root.add_child(prop)

	var marker := MeshInstance3D.new()
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 0.14
	marker_mesh.bottom_radius = 0.2
	marker_mesh.height = 4.0
	marker.mesh = marker_mesh
	marker.position = Vector3(0.0, 2.0, 2.5)
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = pack["accent"]
	marker.material_override = marker_material
	root.add_child(marker)

func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 22.0, 37.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.0, 0.0))
	camera.current = true
	add_child(camera)
