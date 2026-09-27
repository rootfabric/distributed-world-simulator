extends SceneTree

# Test-only input driver. Production scene has no autonomous movement path.
const Scene = preload("res://scenes/labs/mvp/v0_mvp_seam_shared_scene.tscn")
var game: Node3D
var phase := 0


func _initialize() -> void:
	game = Scene.instantiate()
	root.add_child(game)
	game.set_manual_input_enabled(false)


func _process(_delta: float) -> bool:
	if not is_instance_valid(game):
		return false
	var observation: Dictionary = game.observation()
	if observation["client_id"] != "a" or not observation["started"] or observation["finished"] or observation["pending"]:
		return false
	var continuity: Dictionary = observation["continuity"]
	var state: Dictionary = continuity["last_state"]
	if state.is_empty():
		return false
	var x: float = float(state["position_x"])
	var epochs: Array = continuity["epochs"]
	if phase == 0 and epochs.size() >= 2 and x >= 11.0:
		phase = 1
	if phase == 1 and epochs.size() >= 3 and x <= -1.0:
		phase = 2
	if phase == 0:
		game.submit_axis(1.0)
	elif phase == 1:
		game.submit_axis(-1.0)
	else:
		game.finish_route()
	return false
