extends Node3D

func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_rocks()
	_build_outpost_marker()
	_build_camera()
	print("WORLD_FILL_DEMO_READY")

func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.008, 0.01, 0.018)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.18, 0.2, 0.26)
	environment.ambient_light_energy = 0.45
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	add_child(sun)

func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(80.0, 80.0)
	ground.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.17, 0.18)
	material.roughness = 0.96
	ground.material_override = material
	add_child(ground)

func _build_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x57464C30
	for index in range(36):
		var rock := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.25
		mesh.height = 0.5
		rock.mesh = mesh
		var scale_value := rng.randf_range(0.45, 2.1)
		rock.scale = Vector3(scale_value, rng.randf_range(0.35, 0.8) * scale_value, scale_value)
		rock.position = Vector3(rng.randf_range(-24.0, 24.0), 0.12, rng.randf_range(-18.0, 16.0))
		rock.rotation_degrees.y = rng.randf_range(0.0, 360.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.11, 0.12, 0.13)
		material.roughness = 1.0
		rock.material_override = material
		add_child(rock)

func _build_outpost_marker() -> void:
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.12
	pole_mesh.bottom_radius = 0.18
	pole_mesh.height = 5.0
	pole.mesh = pole_mesh
	pole.position = Vector3(0.0, 2.5, -8.0)
	var pole_material := StandardMaterial3D.new()
	pole_material.albedo_color = Color(0.38, 0.4, 0.43)
	pole_material.metallic = 0.65
	pole.material_override = pole_material
	add_child(pole)

	var beacon := MeshInstance3D.new()
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.38
	beacon_mesh.height = 0.76
	beacon.mesh = beacon_mesh
	beacon.position = Vector3(0.0, 5.2, -8.0)
	var beacon_material := StandardMaterial3D.new()
	beacon_material.albedo_color = Color(0.9, 0.28, 0.08)
	beacon_material.emission_enabled = true
	beacon_material.emission = Color(0.9, 0.08, 0.02)
	beacon_material.emission_energy_multiplier = 2.5
	beacon.material_override = beacon_material
	add_child(beacon)

func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(17.0, 10.0, 22.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.2, -3.0))
	camera.current = true
	add_child(camera)
