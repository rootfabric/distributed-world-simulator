extends Node3D


func _ready() -> void:
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)
	for data in [
		["root", -1], ["hips", 0], ["spine", 1], ["head", 2],
		["upper_arm_l", 2], ["hand_l", 4], ["upper_arm_r", 2], ["hand_r", 6],
		["thigh_l", 1], ["foot_l", 8], ["thigh_r", 1], ["foot_r", 10],
	]:
		skeleton.add_bone(String(data[0]))
		var index := skeleton.get_bone_count() - 1
		skeleton.set_bone_parent(index, int(data[1]))

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	add_child(player)
	var library := AnimationLibrary.new()
	for animation_name in [
		"Idle",
		"Walk",
		"Run",
		"Jump_Start",
		"Jump",
		"Jump_Land",
		"Crouch_Idle",
		"Crouch_Fwd",
	]:
		var animation := Animation.new()
		animation.length = 1.0
		animation.loop_mode = Animation.LOOP_NONE if animation_name in ["Jump_Start", "Jump_Land"] else Animation.LOOP_LINEAR
		library.add_animation(animation_name, animation)
	player.add_animation_library("", library)