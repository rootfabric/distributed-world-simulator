extends SceneTree

## WF0.10 Observe / Showcase Toolkit tests.
## Run: godot --headless --path <project> --script res://tests/world_fill/test_wf0_10_showcase.gd

const ShowcaseScript = preload("res://scripts/world_fill/showcase/world_fill_showcase_kit.gd")

const TEST_OBSERVATION_ID := "test_wf0_10"

var failures: Array[String] = []


func _init() -> void:
	_test_spectator_bookmarks()
	_test_capture_full_observation()
	_test_capture_fail_soft()
	_test_deterministic_capture()
	_test_save_load_roundtrip()
	_test_cleanup()
	_finish()


func _fresh_kit() -> RefCounted:
	var kit: RefCounted = ShowcaseScript.new()
	kit.clear_observation(TEST_OBSERVATION_ID)
	return kit


func _full_observation() -> Dictionary:
	return {
		"screenshot_path": "user://showcase/dig_site.png",
		"simulation_tick": 12345,
		"region_id": "body/moon/cell_0_0",
		"authority_id": "authority_a",
		"checksum": "abc123",
		"world_fill_preset": "clear",
		"scene_id": "digging_playground",
	}


func _test_spectator_bookmarks() -> void:
	var kit: RefCounted = ShowcaseScript.new()
	var bookmarks: Array = kit.list_bookmarks()
	var expected := ["dig_site", "handoff", "horizon", "outpost", "seam", "spawn"]
	_assert(bookmarks.size() == 6, "Bookmark count mismatch.")
	for index in bookmarks.size():
		var bookmark: Dictionary = bookmarks[index]
		_assert(String(bookmark.get("name", "")) == expected[index], "Bookmark order/name mismatch at %d." % index)
		_assert(bookmark.get("position") is Vector3 and bookmark.get("target") is Vector3, "Bookmark %s lacks vectors." % expected[index])
	var second: Array = kit.list_bookmarks()
	_assert(_deep_equal(bookmarks, second), "Bookmark listing is not deterministic.")


func _test_capture_full_observation() -> void:
	var kit: RefCounted = ShowcaseScript.new()
	var record: Dictionary = kit.capture_observation(_full_observation())
	_assert(String(record.get("schema", "")) == ShowcaseScript.SCHEMA, "Record schema missing.")
	_assert(int(record.get("simulation_tick", -1)) == 12345, "Tick lost.")
	_assert(String(record.get("world_fill_preset", "")) == "clear", "Preset lost.")
	_assert(String(record.get("checksum", "")) == "abc123", "Checksum lost.")
	_assert(bool(record.get("complete", false)), "Full observation must be complete.")
	_assert((record.get("reasons", []) as Array).is_empty(), "Complete observation has reasons.")


func _test_capture_fail_soft() -> void:
	var kit: RefCounted = ShowcaseScript.new()
	var record: Dictionary = kit.capture_observation({})
	_assert(not bool(record.get("complete", true)), "Empty observation must not be complete.")
	var reasons: Array = record.get("reasons", [])
	_assert(reasons.has("MISSING_SIMULATION_TICK"), "Missing tick not reported.")
	_assert(reasons.has("MISSING_WORLD_FILL_PRESET"), "Missing preset not reported.")
	_assert(String(record.get("screenshot_path", "MISSING")) == "", "Screenshot path must default empty.")


func _test_deterministic_capture() -> void:
	var kit: RefCounted = ShowcaseScript.new()
	var first: Dictionary = kit.capture_observation(_full_observation())
	var second: Dictionary = kit.capture_observation(_full_observation())
	_assert(_deep_equal(first, second), "Same inputs produced different observations.")


func _test_save_load_roundtrip() -> void:
	var kit := _fresh_kit()
	var record: Dictionary = kit.capture_observation(_full_observation())
	_assert(bool(kit.save_observation(TEST_OBSERVATION_ID, record)), "Save to user:// failed.")
	var loaded: Dictionary = kit.load_observation(TEST_OBSERVATION_ID)
	_assert(not loaded.is_empty(), "Load returned empty.")
	_assert(_deep_equal(record, loaded), "Roundtrip changed the record.")
	_assert(int(loaded.get("simulation_tick", -1)) == 12345, "Roundtrip lost the tick.")


func _test_cleanup() -> void:
	var kit := _fresh_kit()
	var record: Dictionary = kit.capture_observation(_full_observation())
	kit.save_observation(TEST_OBSERVATION_ID, record)
	kit.clear_observation(TEST_OBSERVATION_ID)
	_assert(kit.load_observation(TEST_OBSERVATION_ID).is_empty(), "Cleared observation still loads.")
	var invalid: RefCounted = ShowcaseScript.new()
	_assert(not bool(invalid.save_observation("", record)), "Empty id must refuse to save.")
	_assert(
		not bool(invalid.save_observation("bad_schema", {"schema": "wrong"})),
		"Wrong schema must refuse to save."
	)


func _deep_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		var numeric := (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) \
			and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT)
		if numeric:
			return float(a) == float(b)
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
		print("WF0.10 showcase kit tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("WF0.10 showcase kit tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
