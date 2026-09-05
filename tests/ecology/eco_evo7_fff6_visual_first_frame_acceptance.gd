extends SceneTree

const LabScene = preload("res://scenes/labs/ecology/eco_evo7_form_function_feedback_lab.tscn")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var lab = LabScene.instantiate()
	root.add_child(lab)

	_check(lab != null, "FFF6 visual lab instantiates")
	_check(lab.result.is_empty(), "FFF6 heavy 100-cycle computation is not executed synchronously inside _ready")
	_check(lab.hud != null and lab.hud.is_inside_tree(), "FFF6 HUD exists on first frame shell")
	_check(String(lab.hud.text).contains("Preparing deterministic 100-cycle community"), "FFF6 first-frame loading message is visible")
	_check(lab.status != null and lab.status.is_inside_tree(), "FFF6 status label exists on first frame shell")
	_check(String(lab.status.text).contains("Initializing FFF6 visual observatory"), "FFF6 status explains initialization before heavy compute")

	var current_camera_found := false
	for node in lab.get_children():
		if node is Camera3D and (node as Camera3D).is_current():
			current_camera_found = true
			break
	_check(current_camera_found, "FFF6 standalone lab explicitly owns the current Camera3D")

	lab.queue_free()
	_finish()

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: %s" % label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 FFF6 Visual First Frame: PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("ECO.EVO7 FFF6 Visual First Frame: FAIL (%d/%d failed)" % [failures.size(), assertions])
		for failure in failures:
			print("  - %s" % failure)
		quit(1)
