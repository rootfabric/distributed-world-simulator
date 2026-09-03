extends SceneTree

## WF0.9 Labels / Signs / Identity tests.
## Run: godot --headless --path <project> --script res://tests/world_fill/test_wf0_9_sign_kit.gd

const SignKitScript = preload("res://scripts/world_fill/labels/world_fill_sign_kit.gd")

var failures: Array[String] = []


func _init() -> void:
	_test_sign_creation_all_styles()
	_test_text_sanitization()
	_test_budget_evicts_oldest()
	_test_fail_soft_invalid_input()
	_test_report_presentation_only()
	_test_clear_signs()
	_finish()


func _test_sign_creation_all_styles() -> void:
	var kit := SignKitScript.new()
	var index := 0
	for style in SignKitScript.STYLES:
		var report: Dictionary = kit.create_sign("Label %d" % index, Vector3(float(index) * 2.0, 0.0, 0.0), style)
		_assert(bool(report.get("spawned", false)), "Style %s did not spawn." % String(style))
		_assert(String(report.get("text", "")) == "Label %d" % index, "Style %s lost its text." % String(style))
		index += 1
	_assert(int(kit.sign_report().get("active", 0)) == SignKitScript.STYLES.size(), "Sign count mismatch.")
	var label_count := 0
	for child in kit.get_children():
		for sub in child.get_children():
			if sub is Label3D:
				label_count += 1
	_assert(label_count == SignKitScript.STYLES.size(), "Each sign must carry exactly one Label3D.")
	kit.free()


func _test_text_sanitization() -> void:
	var kit := SignKitScript.new()
	var long_text := "SECTOR 7G RELAY STATION NORTH ACCESS MAINTENANCE HATCH ONLY"
	var report: Dictionary = kit.create_sign(long_text, Vector3.ZERO)
	_assert(String(report.get("text", "")) == long_text.substr(0, SignKitScript.MAX_TEXT_LENGTH),
		"Long text was not capped at %d." % SignKitScript.MAX_TEXT_LENGTH)
	var multiline: Dictionary = kit.create_sign("LINE ONE\nLINE TWO", Vector3(1.0, 0.0, 0.0))
	_assert(String(multiline.get("text", "")) == "LINE ONE LINE TWO", "Newlines were not flattened.")
	kit.free()


func _test_budget_evicts_oldest() -> void:
	var kit := SignKitScript.new()
	for index in SignKitScript.MAX_SIGNS + 10:
		kit.create_sign("S%03d" % index, Vector3(float(index), 0.0, 0.0), "container_label", {"with_post": false})
	var report: Dictionary = kit.sign_report()
	_assert(int(report.get("active", -1)) == SignKitScript.MAX_SIGNS, "Sign kit exceeded its budget.")
	_assert(kit.get_child_count() == SignKitScript.MAX_SIGNS, "Evicted sign nodes were not freed.")
	var first_name := String(kit.get_child(0).name)
	_assert(first_name.contains("S010"), "Oldest sign was not evicted first (found %s)." % first_name)
	kit.free()


func _test_fail_soft_invalid_input() -> void:
	var kit := SignKitScript.new()
	var empty: Dictionary = kit.create_sign("   ", Vector3.ZERO)
	_assert(not bool(empty.get("spawned", true)), "Whitespace-only sign spawned.")
	_assert(String(empty.get("reason", "")) == "EMPTY_TEXT", "Empty-text reason missing.")
	var unknown_style: Dictionary = kit.create_sign("VALID", Vector3.ZERO, "neon_gothic")
	_assert(bool(unknown_style.get("spawned", false)), "Unknown style must fall back, not fail.")
	var summary: Dictionary = kit.sign_report()
	var by_style: Dictionary = summary.get("by_style", {})
	_assert(int(by_style.get("location_name", 0)) == 1, "Unknown style did not fall back to location_name.")
	kit.free()


func _test_report_presentation_only() -> void:
	var kit := SignKitScript.new()
	kit.create_sign("HELLO", Vector3.ZERO)
	var report: Dictionary = kit.sign_report()
	for key in report.keys():
		_assert(
			key in ["schema", "active", "max_signs", "by_style"],
			"Sign report exposes unexpected key: %s" % String(key)
		)
	_assert(String(report.get("schema", "")) == SignKitScript.SCHEMA, "Sign report schema missing.")
	kit.free()


func _test_clear_signs() -> void:
	var kit := SignKitScript.new()
	kit.create_sign("A", Vector3.ZERO)
	kit.create_sign("B", Vector3(1.0, 0.0, 0.0))
	kit.clear_signs()
	_assert(int(kit.sign_report().get("active", -1)) == 0, "clear_signs left records behind.")
	_assert(kit.get_child_count() == 0, "clear_signs left nodes behind.")
	kit.free()


func _finish() -> void:
	if failures.is_empty():
		print("WF0.9 sign kit tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("WF0.9 sign kit tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
