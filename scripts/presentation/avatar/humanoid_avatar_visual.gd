extends "res://scripts/presentation/avatar/avatar_visual_port.gd"
# Replaceable procedural CHAR1 fallback: head, torso, arms, legs, facing and
# basic idle/walk/run animation. A custom PackedScene can implement the same port.
var _body: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _lamp: SpotLight3D
var _phase := 0.0
var _motion := "idle"

func _ready() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_part(_body, "Torso", Vector3(0, 1.1, 0), Vector3(0.64, 0.84, 0.34), Color(0.22, 0.48, 0.72))
	_part(_body, "Head", Vector3(0, 1.72, 0), Vector3(0.42, 0.44, 0.4), Color(0.83, 0.7, 0.57))
	_left_arm = _joint("LeftArm", Vector3(-0.44, 1.42, 0))
	_right_arm = _joint("RightArm", Vector3(0.44, 1.42, 0))
	_left_leg = _joint("LeftLeg", Vector3(-0.2, 0.72, 0))
	_right_leg = _joint("RightLeg", Vector3(0.2, 0.72, 0))
	_part(_left_arm, "Mesh", Vector3(0, -0.31, 0), Vector3(0.23, 0.64, 0.24), Color(0.18, 0.36, 0.55))
	_part(_right_arm, "Mesh", Vector3(0, -0.31, 0), Vector3(0.23, 0.64, 0.24), Color(0.18, 0.36, 0.55))
	_part(_left_leg, "Mesh", Vector3(0, -0.34, 0), Vector3(0.28, 0.68, 0.28), Color(0.15, 0.19, 0.28))
	_part(_right_leg, "Mesh", Vector3(0, -0.34, 0), Vector3(0.28, 0.68, 0.28), Color(0.15, 0.19, 0.28))
	_lamp = SpotLight3D.new()
	_lamp.name = "Flashlight"
	_lamp.position = Vector3(0.28, 1.43, -0.18)
	_lamp.spot_range = 14.0
	_lamp.spot_angle = 32.0
	_lamp.light_energy = 2.0
	_lamp.visible = false
	add_child(_lamp)

func _joint(joint_name: String, at: Vector3) -> Node3D:
	var joint := Node3D.new()
	joint.name = joint_name
	joint.position = at
	_body.add_child(joint)
	return joint

func _part(parent: Node3D, part_name: String, at: Vector3, dimensions: Vector3, tint: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = part_name
	mesh.position = at
	var box := BoxMesh.new()
	box.size = dimensions
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	mesh.material_override = material
	parent.add_child(mesh)

func apply_avatar_state(state: Dictionary, delta: float) -> void:
	if _body == null:
		return
	var velocity: Vector3 = state.get("velocity", Vector3.ZERO)
	var speed := Vector2(velocity.x, velocity.z).length()
	_motion = "run" if speed > 3.5 else ("walk" if speed > 0.16 else "idle")
	var weight := clampf(speed / 2.2, 0.0, 1.0)
	_phase += maxf(delta, 0.0) * (9.0 if _motion == "run" else 6.0)
	var swing := sin(_phase) * 0.55 * weight
	_left_arm.rotation.x = -swing
	_right_arm.rotation.x = swing
	_left_leg.rotation.x = swing
	_right_leg.rotation.x = -swing
	_body.position.y = absf(sin(_phase)) * 0.035 * weight
	# The presenter/root owns heading. Avoid applying yaw twice on its child visual.
	_lamp.visible = bool(state.get("flashlight_enabled", false))

func get_avatar_report() -> Dictionary:
	return {"contract": "CHAR1_AVATAR_VISUAL_V1", "visual_type": "procedural_humanoid", "motion": _motion}
