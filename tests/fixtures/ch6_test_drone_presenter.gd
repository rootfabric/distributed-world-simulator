extends Node3D

const PresentationProfile = preload("res://scripts/characters/presentation/controllable_presentation_profile.gd")

var world_visual_root: Node3D


func _init() -> void:
	world_visual_root = Node3D.new()
	world_visual_root.name = "DroneWorldVisual"
	add_child(world_visual_root)

	var body := MeshInstance3D.new()
	body.name = "DroneBody"
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(1.2, 0.28, 0.8)
	body.mesh = body_mesh
	world_visual_root.add_child(body)

	for x in [-0.72, 0.72]:
		for z in [-0.52, 0.52]:
			var rotor := MeshInstance3D.new()
			rotor.name = "Rotor_%s_%s" % [str(x), str(z)]
			var rotor_mesh := CylinderMesh.new()
			rotor_mesh.top_radius = 0.24
			rotor_mesh.bottom_radius = 0.24
			rotor_mesh.height = 0.025
			rotor.mesh = rotor_mesh
			rotor.position = Vector3(x, 0.1, z)
			world_visual_root.add_child(rotor)


func get_world_visual_root() -> Node:
	return world_visual_root


func get_first_person_viewmodel_root() -> Node:
	return null


func get_first_person_shadow_proxy_root() -> Node:
	return null


func create_presentation_profile() -> Resource:
	var result = PresentationProfile.new()
	result.profile_id = &"test_drone"
	result.entity_kind = &"drone"
	result.first_person_policy = PresentationProfile.FirstPersonPolicy.HIDE_WORLD_MODEL
	result.first_person_shadow_policy = PresentationProfile.FirstPersonShadowPolicy.WORLD_PROXY
	result.world_render_layer_index = 20
	result.viewmodel_render_layer_index = 19
	result.shadow_render_layer_index = 18
	result.keep_world_animation_active = true
	result.allow_shadow_from_hidden_world_model = true
	return result
