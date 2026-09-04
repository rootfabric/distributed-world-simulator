extends SceneTree

const SCENE := "res://scenes/labs/fabric/complex2_modular_machine_lab.tscn"

func _initialize() -> void:
	var packed := load(SCENE)
	assert(packed is PackedScene)
	var scene := (packed as PackedScene).instantiate()
	assert(scene != null)
	assert(String(scene.name) == "COMPLEX2ModularMachineLab")
	scene.free()
	print("FABRIC COMPLEX2 Scene Smoke: PASS (3 assertions)")
	quit(0)
