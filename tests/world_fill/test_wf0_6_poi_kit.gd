extends SceneTree

## WF0.6 Landmarks / POI Kit tests.
## Run: godot --headless --path <project> --script res://tests/world_fill/test_wf0_6_poi_kit.gd

const PoiKitScript = preload("res://scripts/world_fill/landmarks/world_fill_poi_kit.gd")
const DressingScript = preload("res://scripts/world_fill/dressing/world_fill_dressing.gd")

var failures: Array[String] = []


func _init() -> void:
	_test_all_kinds_spawn_with_labels()
	_test_budget_evicts_oldest()
	_test_eligibility_gate()
	_test_unknown_kind_fail_soft()
	_test_report_presentation_only()
	_test_recognizable_fixture_content()
	_finish()


func _test_all_kinds_spawn_with_labels() -> void:
	var kit := PoiKitScript.new()
	var index := 0
	for kind in PoiKitScript.POI_KINDS:
		var report: Dictionary = kit.spawn_poi(kind, Vector3(float(index) * 8.0, 0.0, 0.0))
		_assert(bool(report.get("spawned", false)), "Kind %s did not spawn." % String(kind))
		index += 1
	var summary: Dictionary = kit.poi_report()
	_assert(int(summary.get("active", 0)) == PoiKitScript.POI_KINDS.size(), "POI count mismatch after all kinds.")
	var label_count := 0
	var stack: Array[Node] = [kit]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Label3D:
			label_count += 1
		for child in node.get_children():
			stack.append(child)
	_assert(label_count == PoiKitScript.POI_KINDS.size(), "Each POI must carry exactly one label.")
	kit.free()


func _test_budget_evicts_oldest() -> void:
	var kit := PoiKitScript.new()
	for index in PoiKitScript.MAX_POIS + 8:
		kit.spawn_poi("radio_beacon", Vector3(float(index), 0.0, 0.0), {"include_label": false})
	var summary: Dictionary = kit.poi_report()
	_assert(int(summary.get("active", -1)) == PoiKitScript.MAX_POIS, "POI kit exceeded its budget.")
	_assert(kit.get_child_count() == PoiKitScript.MAX_POIS, "Evicted POI nodes were not freed.")
	var first_name := String(kit.get_child(0).name)
	_assert(first_name.contains("_8"), "Oldest POI was not evicted first (found %s)." % first_name)
	kit.free()


func _test_eligibility_gate() -> void:
	var decision := DressingScript.derive({"surface_type": "regolith", "seed": 5})
	var eligibility: Dictionary = decision.get("poi_eligibility", {})
	var kit := PoiKitScript.new()
	var outpost_report: Dictionary = kit.spawn_poi("outpost", Vector3.ZERO, {
		"require_eligible": true,
		"poi_eligibility": eligibility,
	})
	_assert(bool(outpost_report.get("spawned", false)), "Eligible outpost was rejected.")
	var cave_report: Dictionary = kit.spawn_poi("cave_entrance_marker", Vector3(4.0, 0.0, 0.0), {
		"require_eligible": true,
		"poi_eligibility": eligibility,
	})
	_assert(not bool(cave_report.get("spawned", true)), "Ineligible cave marker was spawned.")
	_assert(String(cave_report.get("reason", "")) == "INELIGIBLE", "Ineligible skip reason missing.")
	_assert(int(kit.poi_report().get("active", -1)) == 1, "Ineligible spawn must not create a node.")
	kit.free()


func _test_unknown_kind_fail_soft() -> void:
	var kit := PoiKitScript.new()
	var report: Dictionary = kit.spawn_poi("death_star", Vector3.ZERO)
	_assert(not bool(report.get("spawned", true)), "Unknown kind spawned.")
	_assert(String(report.get("reason", "")) == "UNKNOWN_POI_KIND", "Unknown kind reason missing.")
	_assert(kit.get_child_count() == 0, "Unknown kind created a node.")
	kit.free()


func _test_report_presentation_only() -> void:
	var kit := PoiKitScript.new()
	kit.spawn_poi("landing_site", Vector3.ZERO)
	var report: Dictionary = kit.poi_report()
	for key in report.keys():
		_assert(
			key in ["schema", "active", "max_pois", "by_kind"],
			"POI report exposes unexpected key: %s" % String(key)
		)
	_assert(String(report.get("schema", "")) == PoiKitScript.SCHEMA, "POI report schema missing.")
	kit.free()


func _test_recognizable_fixture_content() -> void:
	var kit := PoiKitScript.new()
	kit.spawn_poi("outpost", Vector3.ZERO, {"include_label": false})
	var fixture: Node3D = kit.get_child(0)
	var mesh_count := 0
	for child in fixture.get_children():
		if child is MeshInstance3D:
			mesh_count += 1
	_assert(mesh_count >= 3, "Outpost fixture is too sparse to be recognizable.")
	for child in fixture.get_children():
		var instance := child as MeshInstance3D
		if instance != null:
			_assert(
				instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				or instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED,
				"Fixture meshes should keep default shadow behavior."
			)
	kit.free()


func _finish() -> void:
	if failures.is_empty():
		print("WF0.6 POI kit tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("WF0.6 POI kit tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
