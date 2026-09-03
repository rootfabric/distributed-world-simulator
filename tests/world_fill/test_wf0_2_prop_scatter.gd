extends SceneTree

## WF0.2 Deterministic Prop Scatter tests.
## Run: godot --headless --path <project> --script res://tests/world_fill/test_wf0_2_prop_scatter.gd

const ScatterScript = preload("res://scripts/world_fill/scatter/world_fill_prop_scatter.gd")
const DressingScript = preload("res://scripts/world_fill/dressing/world_fill_dressing.gd")

var failures: Array[String] = []


func _init() -> void:
	_test_determinism_identical_transforms()
	_test_budget_respected_and_capped()
	_test_fail_soft_on_empty_decision()
	_test_no_collision_nodes()
	_test_clear_scatter_resets()
	_finish()


func _make_decision(seed_value: int) -> Dictionary:
	return DressingScript.derive({
		"surface_type": "regolith",
		"position": Vector3(4.0, 0.0, -2.0),
		"seed": seed_value,
	})


func _collect_transforms(scatter: Node3D) -> Array:
	var captured: Array = []
	for child in scatter.get_children():
		if child is MultiMeshInstance3D:
			var multimesh: MultiMesh = child.multimesh
			var family_arrays: Array = []
			for index in multimesh.instance_count:
				var t := multimesh.get_instance_transform(index)
				family_arrays.append([
					t.origin.x, t.origin.y, t.origin.z,
					t.basis.x.x, t.basis.x.y, t.basis.x.z,
					t.basis.y.x, t.basis.y.y, t.basis.y.z,
					t.basis.z.x, t.basis.z.y, t.basis.z.z,
				])
			captured.append(family_arrays)
	return captured


func _test_determinism_identical_transforms() -> void:
	var first := ScatterScript.new()
	var second := ScatterScript.new()
	var report_a := first.build_from_decision(_make_decision(7), Vector2(60.0, 60.0), 11)
	var report_b := second.build_from_decision(_make_decision(7), Vector2(60.0, 60.0), 11)
	_assert(_deep_equal(report_a, report_b), "Same decision+seed produced different scatter reports.")
	var transforms_a := _collect_transforms(first)
	var transforms_b := _collect_transforms(second)
	_assert(_deep_equal(transforms_a, transforms_b), "Same decision+seed produced different transforms.")
	_assert((transforms_a as Array).size() > 0, "Scatter produced no MultiMesh nodes.")
	_assert(int(report_a.get("total_instances", 0)) > 0, "Scatter produced zero instances.")
	first.free()
	second.free()


func _test_budget_respected_and_capped() -> void:
	var decision := DressingScript.derive({
		"surface_type": "metal",
		"seed": 21,
	})
	var scatter := ScatterScript.new()
	var report := scatter.build_from_decision(decision, Vector2(50.0, 50.0), 5)
	var families: Dictionary = report.get("families", {})
	for family in families:
		var entry_band := ""
		for profile in decision.get("prop_families", []):
			if String(profile.get("family", "")) == String(family):
				entry_band = String(profile.get("density_band", "none"))
		var budget := int(ScatterScript.DENSITY_BUDGETS.get(entry_band, 0))
		_assert(int(families[family]) <= budget, "Family %s exceeded its band budget." % String(family))
	_assert(
		int(report.get("total_instances", 0)) <= ScatterScript.TOTAL_INSTANCE_CAP,
		"Total instances exceeded the documented global cap."
	)
	scatter.free()


func _test_fail_soft_on_empty_decision() -> void:
	var scatter := ScatterScript.new()
	var report := scatter.build_from_decision({}, Vector2(40.0, 40.0), 3)
	_assert(int(report.get("total_instances", -1)) == 0, "Empty decision did not degrade to zero instances.")
	_assert(int(report.get("multimesh_nodes", -1)) == 0, "Empty decision created MultiMesh nodes.")
	scatter.free()


func _test_no_collision_nodes() -> void:
	var scatter := ScatterScript.new()
	scatter.build_from_decision(_make_decision(9), Vector2(60.0, 60.0), 1)
	var stack: Array[Node] = [scatter]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		_assert(
			not (node is CollisionObject3D) and not (node is CollisionShape3D),
			"Scatter created a collision node: %s" % node.name
		)
		for child in node.get_children():
			stack.append(child)
	scatter.free()


func _test_clear_scatter_resets() -> void:
	var scatter := ScatterScript.new()
	scatter.build_from_decision(_make_decision(13), Vector2(40.0, 40.0), 2)
	_assert(scatter.get_child_count() > 0, "Scatter built no children before clear.")
	var report := scatter.build_from_decision({}, Vector2(40.0, 40.0), 2)
	_assert(scatter.get_child_count() == 0, "Rebuild on empty decision left children behind.")
	_assert(int(report.get("multimesh_nodes", -1)) == 0, "Report after clear is not empty.")
	scatter.free()


func _deep_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_DICTIONARY:
			var dict_a: Dictionary = a
			var dict_b: Dictionary = b
			if dict_a.size() != dict_b.size():
				return false
			for key in dict_a:
				if not dict_b.has(key) or not _deep_equal(dict_a[key], dict_b[key]):
					return false
			return true
		TYPE_ARRAY:
			var array_a: Array = a
			var array_b: Array = b
			if array_a.size() != array_b.size():
				return false
			for index in array_a.size():
				if not _deep_equal(array_a[index], array_b[index]):
					return false
			return true
		_:
			return a == b


func _finish() -> void:
	if failures.is_empty():
		print("WF0.2 prop scatter tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("WF0.2 prop scatter tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
