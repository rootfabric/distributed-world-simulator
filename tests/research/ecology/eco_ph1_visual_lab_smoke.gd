extends SceneTree
var assertions := 0
var failures: Array[String] = []
func _init() -> void:
	var packed := load("res://scenes/labs/ecology/eco_ph1_growth_graph_visual_lab.tscn") as PackedScene
	_check(packed != null, "visual lab scene loads")
	if packed != null:
		var node := packed.instantiate()
		_check(node != null, "visual lab scene instantiates")
		_check(node.get_script() != null, "visual lab has script")
		_check(node.has_node("UI/Status"), "visual lab status panel")
		node.free()
	var source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_ph1_growth_graph_visual_lab.gd").to_lower()
	_check(source.contains("growthgraph skeleton lab"), "lab identifies skeleton purpose")
	_check(source.contains("probes.make_probes"), "lab consumes controlled probe truth")
	_check(source.contains("probes.skeleton.build"), "lab consumes same skeleton generator")
	_check(not source.contains("meshinstance"), "lab does not create mesh truth")
	_check(not source.contains("plant_type"), "lab does not use canonical plant types")
	_check(not source.contains("biome"), "lab does not use biome rules")
	_finish()
func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition: failures.append(label)
func _finish() -> void:
	if failures.is_empty(): print("ECO.PH1 Visual Lab Smoke: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error("ECO.PH1 VISUAL FAIL: %s" % failure)
	print("ECO.PH1 Visual Lab Smoke: FAIL (%d assertions, %d failures)" % [assertions, failures.size()]); quit(1)
