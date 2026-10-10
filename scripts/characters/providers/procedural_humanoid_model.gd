class_name ProceduralHumanoid
extends Node3D

const REQUIRED_ANIMATIONS := [
	"idle", "walk", "run", "strafe_left", "strafe_right",
	"jump_start", "fall", "land", "pickup", "use",
]

var _built := false
var _animation_player: AnimationPlayer
var _skeleton: Skeleton3D
var _materials: Dictionary = {}

func _ready() -> void:
	build_now()

func build_now() -> void:
	if _built:
		return
	_built = true
	name = "ProceduralHumanoid"
	var visual_root := Node3D.new()
	visual_root.name = "VisualRoot"
	add_child(visual_root)
	_build_skeleton(visual_root)
	_build_body(visual_root)
	_build_sockets(visual_root)
	_build_animations()
	apply_appearance({})

func _build_skeleton(parent: Node3D) -> void:
	_skeleton = Skeleton3D.new()
	_skeleton.name = "HumanoidSkeleton"
	parent.add_child(_skeleton)
	var bones := [
		["root", -1], ["hips", 0], ["spine", 1], ["head", 2],
		["upper_arm_l", 2], ["hand_l", 4], ["upper_arm_r", 2], ["hand_r", 6],
		["thigh_l", 1], ["foot_l", 8], ["thigh_r", 1], ["foot_r", 10],
	]
	for bone_data in bones:
		_skeleton.add_bone(String(bone_data[0]))
		var index := _skeleton.get_bone_count() - 1
		_skeleton.set_bone_parent(index, int(bone_data[1]))

func _material(key: String, color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "ProceduralHumanoid_%s" % key
	material.albedo_color = color
	material.roughness = 0.75
	_materials[key] = material
	return material

func _mesh_part(parent: Node3D, part_name: String, mesh: PrimitiveMesh, position_value: Vector3, material_key: String) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = part_name
	pivot.position = position_value
	parent.add_child(pivot)
	var instance := MeshInstance3D.new()
	instance.name = "Mesh"
	instance.mesh = mesh
	instance.material_override = _materials[material_key]
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pivot.add_child(instance)
	return pivot

func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	return mesh

func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return mesh

func _build_body(parent: Node3D) -> void:
	_material("body", Color(0.18, 0.45, 0.82, 1.0))
	_material("accent", Color(0.08, 0.12, 0.2, 1.0))
	_material("skin", Color(0.72, 0.52, 0.38, 1.0))
	_material("visor", Color(0.1, 0.8, 0.95, 0.9))
	_mesh_part(parent, "Pelvis", _box(Vector3(0.42, 0.25, 0.24)), Vector3(0, 0.95, 0), "accent")
	_mesh_part(parent, "Torso", _box(Vector3(0.55, 0.65, 0.28)), Vector3(0, 1.34, 0), "body")
	_mesh_part(parent, "Head", _sphere(0.18), Vector3(0, 1.83, 0), "skin")
	var visor := _mesh_part(parent, "Visor", _box(Vector3(0.25, 0.09, 0.03)), Vector3(0, 1.86, -0.17), "visor")
	visor.rotation.x = -0.08
	_mesh_part(parent, "LeftArm", _capsule(0.075, 0.62), Vector3(-0.39, 1.39, 0), "body")
	_mesh_part(parent, "RightArm", _capsule(0.075, 0.62), Vector3(0.39, 1.39, 0), "body")
	_mesh_part(parent, "LeftHand", _sphere(0.09), Vector3(-0.39, 1.05, 0), "skin")
	_mesh_part(parent, "RightHand", _sphere(0.09), Vector3(0.39, 1.05, 0), "skin")
	_mesh_part(parent, "LeftLeg", _capsule(0.09, 0.78), Vector3(-0.15, 0.53, 0), "accent")
	_mesh_part(parent, "RightLeg", _capsule(0.09, 0.78), Vector3(0.15, 0.53, 0), "accent")
	_mesh_part(parent, "LeftFoot", _box(Vector3(0.2, 0.12, 0.34)), Vector3(-0.15, 0.09, -0.06), "accent")
	_mesh_part(parent, "RightFoot", _box(Vector3(0.2, 0.12, 0.34)), Vector3(0.15, 0.09, -0.06), "accent")

func _build_sockets(parent: Node3D) -> void:
	var sockets := Node3D.new()
	sockets.name = "Sockets"
	parent.add_child(sockets)
	_add_socket(sockets, "Head", Vector3(0, 2.02, 0))
	_add_socket(sockets, "HandLeft", Vector3(-0.39, 0.98, -0.03))
	_add_socket(sockets, "HandRight", Vector3(0.39, 0.98, -0.03))
	_add_socket(sockets, "Chest", Vector3(0, 1.45, -0.18))
	_add_socket(sockets, "Back", Vector3(0, 1.45, 0.2))
	_add_socket(sockets, "Hip", Vector3(0.28, 0.95, 0))

func _add_socket(parent: Node3D, socket_name: String, position_value: Vector3) -> void:
	var marker := Marker3D.new()
	marker.name = socket_name
	marker.position = position_value
	parent.add_child(marker)

func _animation(length: float, looped: bool = false) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
	return animation

func _rotation_track(animation: Animation, path: String, keys: Array, values: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("%s:rotation" % path))
	animation.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
	for index in range(keys.size()):
		animation.track_insert_key(track, float(keys[index]), values[index])

func _position_track(animation: Animation, path: String, keys: Array, values: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("%s:position" % path))
	animation.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
	for index in range(keys.size()):
		animation.track_insert_key(track, float(keys[index]), values[index])

func _build_animations() -> void:
	_animation_player = AnimationPlayer.new()
	_animation_player.name = "AnimationPlayer"
	add_child(_animation_player)
	var library := AnimationLibrary.new()
	library.add_animation("RESET", _animation(0.05))
	var idle := _animation(2.0, true)
	_rotation_track(idle, "VisualRoot/Torso", [0.0, 1.0, 2.0], [Vector3(0, 0, 0), Vector3(0.025, 0, 0), Vector3(0, 0, 0)])
	library.add_animation("idle", idle)
	var walk := _animation(0.8, true)
	_add_locomotion_tracks(walk, 0.55)
	library.add_animation("walk", walk)
	var run := _animation(0.55, true)
	_add_locomotion_tracks(run, 0.95)
	library.add_animation("run", run)
	var strafe_left := _animation(0.8, true)
	_add_locomotion_tracks(strafe_left, 0.45)
	_rotation_track(strafe_left, "VisualRoot/Torso", [0.0, 0.4, 0.8], [Vector3(0, 0, -0.08), Vector3(0, 0, 0.08), Vector3(0, 0, -0.08)])
	library.add_animation("strafe_left", strafe_left)
	var strafe_right := _animation(0.8, true)
	_add_locomotion_tracks(strafe_right, 0.45)
	_rotation_track(strafe_right, "VisualRoot/Torso", [0.0, 0.4, 0.8], [Vector3(0, 0, 0.08), Vector3(0, 0, -0.08), Vector3(0, 0, 0.08)])
	library.add_animation("strafe_right", strafe_right)
	var jump_start := _animation(0.3)
	_position_track(jump_start, "VisualRoot", [0.0, 0.15, 0.3], [Vector3.ZERO, Vector3(0, -0.08, 0), Vector3.ZERO])
	_rotation_track(jump_start, "VisualRoot/LeftArm", [0.0, 0.3], [Vector3.ZERO, Vector3(-0.65, 0, 0)])
	_rotation_track(jump_start, "VisualRoot/RightArm", [0.0, 0.3], [Vector3.ZERO, Vector3(-0.65, 0, 0)])
	library.add_animation("jump_start", jump_start)
	var fall := _animation(0.7, true)
	_rotation_track(fall, "VisualRoot/LeftArm", [0.0, 0.7], [Vector3(-0.35, 0, -0.12), Vector3(-0.35, 0, 0.12)])
	_rotation_track(fall, "VisualRoot/RightArm", [0.0, 0.7], [Vector3(-0.35, 0, 0.12), Vector3(-0.35, 0, -0.12)])
	library.add_animation("fall", fall)
	var land := _animation(0.35)
	_position_track(land, "VisualRoot", [0.0, 0.16, 0.35], [Vector3.ZERO, Vector3(0, -0.12, 0), Vector3.ZERO])
	library.add_animation("land", land)
	var pickup := _animation(0.7)
	_rotation_track(pickup, "VisualRoot/Torso", [0.0, 0.35, 0.7], [Vector3.ZERO, Vector3(0.55, 0, 0), Vector3.ZERO])
	_rotation_track(pickup, "VisualRoot/RightArm", [0.0, 0.35, 0.7], [Vector3.ZERO, Vector3(-1.0, 0, 0), Vector3.ZERO])
	library.add_animation("pickup", pickup)
	var use := _animation(0.55)
	_rotation_track(use, "VisualRoot/RightArm", [0.0, 0.2, 0.55], [Vector3.ZERO, Vector3(-1.25, 0, 0), Vector3.ZERO])
	library.add_animation("use", use)
	_animation_player.add_animation_library("", library)
	_animation_player.play("idle")

func _add_locomotion_tracks(animation: Animation, amplitude: float) -> void:
	var half := animation.length * 0.5
	var keys := [0.0, half, animation.length]
	_rotation_track(animation, "VisualRoot/LeftArm", keys, [Vector3(amplitude, 0, 0), Vector3(-amplitude, 0, 0), Vector3(amplitude, 0, 0)])
	_rotation_track(animation, "VisualRoot/RightArm", keys, [Vector3(-amplitude, 0, 0), Vector3(amplitude, 0, 0), Vector3(-amplitude, 0, 0)])
	_rotation_track(animation, "VisualRoot/LeftLeg", keys, [Vector3(-amplitude, 0, 0), Vector3(amplitude, 0, 0), Vector3(-amplitude, 0, 0)])
	_rotation_track(animation, "VisualRoot/RightLeg", keys, [Vector3(amplitude, 0, 0), Vector3(-amplitude, 0, 0), Vector3(amplitude, 0, 0)])

func apply_appearance(parameters: Dictionary) -> void:
	if not _built:
		build_now()
	_set_material_color("body", _color_parameter(parameters, "body_color", Color(0.18, 0.45, 0.82, 1.0)))
	_set_material_color("accent", _color_parameter(parameters, "accent_color", Color(0.08, 0.12, 0.2, 1.0)))
	_set_material_color("skin", _color_parameter(parameters, "skin_color", Color(0.72, 0.52, 0.38, 1.0)))

func _color_parameter(parameters: Dictionary, key: String, fallback: Color) -> Color:
	var raw = parameters.get(key, [])
	if raw is Array and raw.size() == 4:
		return Color(clampf(float(raw[0]), 0.0, 1.0), clampf(float(raw[1]), 0.0, 1.0), clampf(float(raw[2]), 0.0, 1.0), clampf(float(raw[3]), 0.0, 1.0))
	return fallback

func _set_material_color(key: String, color: Color) -> void:
	if _materials.has(key):
		_materials[key].albedo_color = color

func get_animation_player() -> AnimationPlayer:
	return _animation_player

func get_skeleton() -> Skeleton3D:
	return _skeleton

func get_socket(socket_name: StringName) -> Node3D:
	return get_node_or_null(NodePath("VisualRoot/Sockets/%s" % String(socket_name))) as Node3D

func create_report() -> Dictionary:
	var animations: Array[String] = []
	if _animation_player != null:
		for animation_name in _animation_player.get_animation_list():
			animations.append(String(animation_name))
	animations.sort()
	return {"schema": "planet_simulator.procedural_humanoid.v1", "built": _built, "bone_count": _skeleton.get_bone_count() if _skeleton != null else 0, "animations": animations, "required_animation_count": REQUIRED_ANIMATIONS.size()}
