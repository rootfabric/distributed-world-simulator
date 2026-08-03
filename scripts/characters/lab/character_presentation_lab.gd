class_name CharacterPresentationLab
extends Node3D

const Controller = preload("res://scripts/characters/lab/character_lab_controller.gd")

var player

func _ready() -> void:
	name = "CharacterPresentationLab"
	_build_environment()
	_build_floor()
	_build_reference_props()
	player = Controller.new()
	player.name = "CharacterLabPlayer"
	player.position = Vector3(0.0, 0.05, 0.0)
	add_child(player)
	_build_ui()

func _build_environment() -> void:
	var environment := WorldEnvironment.new()
	environment.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.055, 0.09, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.52, 0.65, 1.0)
	env.ambient_light_energy = 0.65
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)

func _build_floor() -> void:
	var floor := StaticBody3D.new()
	floor.name = "Floor"
	add_child(floor)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(30.0, 0.2, 30.0)
	mesh_instance.mesh = mesh
	mesh_instance.position.y = -0.1
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.19, 0.24, 1.0)
	material.roughness = 0.9
	mesh_instance.material_override = material
	floor.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30.0, 0.2, 30.0)
	collision.shape = shape
	collision.position.y = -0.1
	floor.add_child(collision)

func _build_reference_props() -> void:
	for index in range(6):
		var marker := MeshInstance3D.new()
		marker.name = "DistanceMarker%d" % index
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.25, 0.5 + index * 0.1, 0.25)
		marker.mesh = mesh
		marker.position = Vector3(-5.0 + index * 2.0, mesh.size.y * 0.5, -4.0)
		add_child(marker)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "InstructionsLayer"
	add_child(layer)
	var panel := ColorRect.new()
	panel.position = Vector2(16, 16)
	panel.size = Vector2(520, 148)
	panel.color = Color(0.02, 0.025, 0.04, 0.86)
	layer.add_child(panel)
	var label := Label.new()
	label.position = Vector2(16, 12)
	label.size = Vector2(490, 125)
	label.text = "CH3 Character Presentation Lab\nWASD — движение   Shift — бег   Space — прыжок\nE — pickup-анимация   Tab — смена персонажа\nF — first/third person\nВсе модели используют общий PlayerPresentationHost."
	label.add_theme_font_size_override("font_size", 18)
	panel.add_child(label)

func get_player():
	return player
