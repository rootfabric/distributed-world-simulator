extends SceneTree

const VisualAdapter = preload("res://scripts/labs/ecology/eco_evo6_generated_rule_fly_lab.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var node = VisualAdapter.new()
	_check(node._load_evo6_generated_fates(), "generated EVO6 fates load fail-closed")
	_check(node._fates.size() == 196, "all 196 terrain cells are bound to generated fates")
	var source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo6_generated_rule_fly_lab.gd")
	_check(source.find("evo5_r2_rule_outcomes.v1.json") < 0, "R3.1 adapter does not read static R2 outcomes")
	_check(source.find("super._establish") >= 0, "R3.1 reuses the existing R3 presenter")
	var scene_source := FileAccess.get_file_as_string("res://scenes/labs/ecology/eco_evo6_generated_rule_fly_lab.tscn")
	_check(
		scene_source.find("eco_evo6_generated_rule_fly_lab.gd") >= 0,
		"dedicated generated-rule flyover scene binds adapter"
	)
	node.free()
	_finish()

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO6 R3.1 visual adapter: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO6 R3.1 FAIL: %s" % failure)
	print(
		"ECO.EVO6 R3.1 visual adapter: FAIL (%d assertions, %d failures)"
		% [assertions, failures.size()]
	)
	quit(1)
