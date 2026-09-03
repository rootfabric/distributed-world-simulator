extends SceneTree

## WF0.7 Digging Playground Composition tests.
## Run: godot --headless --path <project> --script res://tests/world_fill/test_wf0_7_playground.gd

const PlaygroundScript = preload("res://scripts/world_fill/composition/digging_playground.gd")

var failures: Array[String] = []


func _init() -> void:
	_test_composition_contents()
	_test_camera_path_bookmarks()
	_test_deterministic_rebuild()
	_test_no_new_implementation_surface()
	_finish()


func _test_composition_contents() -> void:
	var playground := PlaygroundScript.new()
	var report: Dictionary = playground.build_playground()
	_assert(String(report.get("schema", "")) == PlaygroundScript.SCHEMA, "Report schema missing.")
	_assert(String(report.get("ambience_preset", "")) == "clear", "Ambience was not applied.")
	_assert(int(report.get("scatter_instances", 0)) > 0, "Starter props scatter missing.")
	_assert(int(report.get("scar_events", 0)) >= 3, "Dig-pit scars missing.")
	_assert(int(report.get("pois", 0)) >= 1, "No POI in the composition.")
	_assert(int(report.get("signs", 0)) >= 2, "Signs missing.")
	_assert(int(report.get("seam_segments", 0)) == PlaygroundScript.SEAM_SEGMENT_COUNT, "Seam marker missing.")
	var pit := playground.get_node_or_null("DigPit")
	_assert(pit != null, "Dig pit presentation missing.")
	_assert(pit.get_child_count() >= 9, "Dig pit floor/rim incomplete.")
	var seam := playground.get_node_or_null("SeamMarker")
	_assert(seam != null and seam.get_child_count() == PlaygroundScript.SEAM_SEGMENT_COUNT, "Seam segment count wrong.")
	playground.free()


func _test_camera_path_bookmarks() -> void:
	var playground := PlaygroundScript.new()
	playground.build_playground()
	var summary: Dictionary = playground.playground_report()
	var expected := ["dig_site", "handoff", "horizon", "outpost", "seam", "spawn"]
	_assert(int(summary.get("waypoints", 0)) == expected.size(), "Waypoint count mismatch.")
	var camera: Camera3D = playground.get_node_or_null("SpectatorCamera")
	_assert(camera != null, "Spectator camera missing.")
	var waypoint_names := []
	for child in playground.get_children():
		waypoint_names.append(String(child.name))
	_assert(waypoint_names.has("SpectatorCamera"), "Camera not attached to the composition.")
	playground.free()


func _test_deterministic_rebuild() -> void:
	var first := PlaygroundScript.new()
	var second := PlaygroundScript.new()
	var report_a: Dictionary = first.build_playground()
	var report_b: Dictionary = second.build_playground()
	_assert(_deep_equal(report_a, report_b), "Two identical builds produced different reports.")
	first.free()
	second.free()


func _test_no_new_implementation_surface() -> void:
	var playground := PlaygroundScript.new()
	playground.build_playground()
	var stack: Array[Node] = [playground]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		_assert(
			not (node is CollisionObject3D) and not (node is CollisionShape3D),
			"Composition created a collision node: %s" % node.name
		)
		_assert(
			not (node is MultiplayerSpawner) and not (node is MultiplayerSynchronizer),
			"Composition created a replication node: %s" % node.name
		)
		for child in node.get_children():
			stack.append(child)
	playground.free()


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
		print("WF0.7 playground composition tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("WF0.7 playground composition tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
