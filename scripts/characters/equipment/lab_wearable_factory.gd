class_name LabWearableFactory
extends RefCounted


static func create_helmet_scene() -> PackedScene:
	var root := Node3D.new()
	root.name = "HelmetMk1"

	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = 0.24
	shell_mesh.height = 0.36
	shell.mesh = shell_mesh
	shell.scale = Vector3(1.08, 0.92, 1.02)
	shell.material_override = _material(Color(0.16, 0.20, 0.28), 0.55, 0.15)
	root.add_child(shell)
	shell.owner = root

	var visor := MeshInstance3D.new()
	visor.name = "Visor"
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.34, 0.13, 0.055)
	visor.mesh = visor_mesh
	visor.position = Vector3(0.0, 0.015, -0.205)
	visor.material_override = _material(Color(0.08, 0.18, 0.24), 0.18, 0.7)
	root.add_child(visor)
	visor.owner = root

	return _pack_and_free(root)


static func create_backpack_scene() -> PackedScene:
	var root := Node3D.new()
	root.name = "BackpackMk1"

	var pack := MeshInstance3D.new()
	pack.name = "Pack"
	var pack_mesh := BoxMesh.new()
	pack_mesh.size = Vector3(0.44, 0.58, 0.22)
	pack.mesh = pack_mesh
	pack.position = Vector3(0.0, 0.0, 0.02)
	pack.material_override = _material(Color(0.20, 0.25, 0.18), 0.75, 0.05)
	root.add_child(pack)
	pack.owner = root

	for side in [-1.0, 1.0]:
		var tank := MeshInstance3D.new()
		tank.name = "TankLeft" if side < 0.0 else "TankRight"
		var tank_mesh := CapsuleMesh.new()
		tank_mesh.radius = 0.075
		tank_mesh.height = 0.46
		tank.mesh = tank_mesh
		tank.position = Vector3(0.16 * side, 0.0, 0.13)
		tank.material_override = _material(Color(0.31, 0.33, 0.36), 0.5, 0.25)
		root.add_child(tank)
		tank.owner = root

	return _pack_and_free(root)


static func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


static func _pack_and_free(root: Node3D) -> PackedScene:
	var packed := PackedScene.new()
	var error := packed.pack(root)
	root.free()
	return packed if error == OK else null
