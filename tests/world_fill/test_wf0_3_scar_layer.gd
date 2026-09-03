extends SceneTree

## WF0.3 Surface Scars / Decals tests.
## Run: godot --headless --path <project> --script res://tests/world_fill/test_wf0_3_scar_layer.gd

const ScarLayerScript = preload("res://scripts/world_fill/decals/world_fill_scar_layer.gd")

var failures: Array[String] = []


func _init() -> void:
	_test_event_derival_mapping()
	_test_budget_evicts_oldest()
	_test_lifetime_aging()
	_test_fail_soft_unknown_event()
	_test_debug_marks_hidden_by_default()
	_test_no_canonical_state_owned()
	_finish()


func _event(event_type: String, position: Vector3) -> Dictionary:
	return {"type": event_type, "position": position, "normal": Vector3.UP}


func _test_event_derival_mapping() -> void:
	var layer := ScarLayerScript.new()
	layer.record_event(_event("DIG_SUCCESS", Vector3(1.0, 0.0, 2.0)), 10)
	layer.record_event(_event("BUILD_COMMIT", Vector3(-3.0, 0.0, 1.0)), 11)
	var report := layer.scar_report()
	_assert(int(report.get("active", 0)) == 2, "Two events did not produce two active scars.")
	var by_family: Dictionary = report.get("by_family", {})
	_assert(int(by_family.get("dig_scar", 0)) == 1, "DIG_SUCCESS did not map to dig_scar.")
	_assert(int(by_family.get("construction_footprint", 0)) == 1, "BUILD_COMMIT did not map to construction_footprint.")
	var mark_count := 0
	for child in layer.get_children():
		if child is MeshInstance3D:
			mark_count += 1
			_assert(
				child.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"Decal mark casts shadows (presentation-only violation)."
			)
	_assert(mark_count == 2, "Mark node count mismatch.")
	layer.free()


func _test_budget_evicts_oldest() -> void:
	var layer := ScarLayerScript.new()
	for index in ScarLayerScript.MAX_ACTIVE_DECALS + 36:
		layer.record_event(
			_event("DIG_IMPACT", Vector3(float(index % 10), 0.0, float(floori(index / 10.0)))),
			index
		)
	var report := layer.scar_report()
	_assert(
		int(report.get("active", -1)) == ScarLayerScript.MAX_ACTIVE_DECALS,
		"Scar layer exceeded its bounded budget."
	)
	var first_mark := layer.get_child(0)
	var last_record_position := Vector3(
		9.0, 0.0, float(floori((ScarLayerScript.MAX_ACTIVE_DECALS + 35) / 10.0))
	)
	var found_newest := false
	for child in layer.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).position.distance_to(last_record_position) < 0.5:
			found_newest = true
	_assert(found_newest, "Newest scar was evicted instead of the oldest.")
	_assert(first_mark is MeshInstance3D, "Oldest surviving mark is not a MeshInstance3D.")
	layer.free()


func _test_lifetime_aging() -> void:
	var layer := ScarLayerScript.new()
	layer.record_event(_event("DIG_SUCCESS", Vector3(0.0, 0.0, 0.0)), 100)
	layer.record_event(_event("DIG_SUCCESS", Vector3(5.0, 0.0, 0.0)), 200)
	var boundary_report := layer.age_out(100 + ScarLayerScript.LIFETIME_TICKS)
	_assert(
		int(boundary_report.get("active", -1)) == 2,
		"Scar exactly at lifetime must survive (removal is strictly older-than)."
	)
	var expired_one_report := layer.age_out(100 + ScarLayerScript.LIFETIME_TICKS + 1)
	_assert(
		int(expired_one_report.get("active", -1)) == 1,
		"Age-out did not remove the first scar one tick past its lifetime."
	)
	var end_report := layer.age_out(200 + ScarLayerScript.LIFETIME_TICKS + 1)
	_assert(int(end_report.get("active", -1)) == 0, "Age-out did not remove expired scars.")
	_assert(layer.get_child_count() == 0, "Expired scar nodes were not freed.")
	layer.free()


func _test_fail_soft_unknown_event() -> void:
	var layer := ScarLayerScript.new()
	var report := layer.record_event(_event("TOTALLY_UNKNOWN", Vector3(1.0, 0.0, 1.0)), 5)
	var by_family: Dictionary = report.get("by_family", {})
	_assert(int(by_family.get("surface_wear", 0)) == 1, "Unknown event did not degrade to surface_wear.")
	layer.free()


func _test_debug_marks_hidden_by_default() -> void:
	var layer := ScarLayerScript.new()
	layer.record_event(_event("COMMAND_REJECTED", Vector3(2.0, 0.0, 2.0)), 7)
	layer.record_event(_event("DIG_IMPACT", Vector3(3.0, 0.0, 2.0)), 8)
	var debug_visible := -1
	var normal_visible := -1
	for child in layer.get_children():
		if child is MeshInstance3D:
			if (child as MeshInstance3D).position.distance_to(Vector3(2.02, 0.0, 2.0)) < 0.2:
				debug_visible = (child as MeshInstance3D).visible
			else:
				normal_visible = (child as MeshInstance3D).visible
	_assert(debug_visible == 0, "Rejected-action debug mark is visible by default.")
	_assert(normal_visible == 1, "Normal scar is not visible by default.")
	layer.set_debug_marks_visible(true)
	for child in layer.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).position.distance_to(Vector3(2.02, 0.0, 2.0)) < 0.2:
			debug_visible = (child as MeshInstance3D).visible
	_assert(debug_visible == 1, "Debug marks did not become visible in debug mode.")
	layer.free()


func _test_no_canonical_state_owned() -> void:
	var layer := ScarLayerScript.new()
	layer.record_event(_event("CONTACT_TRACE", Vector3(0.0, 0.0, 0.0)), 1)
	var report: Dictionary = layer.scar_report()
	for key in report.keys():
		_assert(
			key in ["schema", "active", "max_active", "lifetime_ticks", "by_family", "debug_only"],
			"Scar report exposes unexpected state key: %s" % String(key)
		)
	_assert(String(report.get("schema", "")) == ScarLayerScript.SCHEMA, "Scar report schema missing.")
	layer.free()


func _finish() -> void:
	if failures.is_empty():
		print("WF0.3 scar layer tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("WF0.3 scar layer tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
