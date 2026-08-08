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
