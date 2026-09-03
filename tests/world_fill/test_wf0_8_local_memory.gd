extends SceneTree

## WF0.8 Local World Memory tests.
## Run: godot --headless --path <project> --script res://tests/world_fill/test_wf0_8_local_memory.gd

const MemoryScript = preload("res://scripts/world_fill/memory/world_fill_local_memory.gd")

const TEST_MEMORY_ID := "test_wf0_8"

var failures: Array[String] = []


func _init() -> void:
	_test_event_derived_crumbs()
	_test_note_sanitization()
	_test_budget_evicts_oldest()
	_test_save_load_roundtrip()
	_test_local_only_report()
	_test_fail_soft_paths()
	_test_cleanup()
	_finish()


func _fresh_memory() -> RefCounted:
	var memory: RefCounted = MemoryScript.new()
	memory.configure_storage(TEST_MEMORY_ID)
	memory.clear_storage()
	return memory


func _test_event_derived_crumbs() -> void:
	var memory := _fresh_memory()
	memory.record_observed({"type": "VISIT", "position": Vector3.ZERO}, 10)
	memory.record_observed({"type": "DIG_SUCCESS", "position": Vector3(1.0, 0.0, 1.0)}, 11)
	memory.record_observed({"type": "HANDOFF_OBSERVED", "position": Vector3(2.0, 0.0, 2.0)}, 12)
	memory.record_observed({"type": "PHOTO_CAPTURED"}, 13)
	var report: Dictionary = memory.memory_report()
	_assert(int(report.get("active", 0)) == 4, "Four observed events did not create four crumbs.")
	var by_type: Dictionary = report.get("by_type", {})
	_assert(int(by_type.get("dug_here", 0)) == 1, "DIG_SUCCESS did not create dug_here crumb.")
	_assert(int(by_type.get("observed_handoff", 0)) == 1, "HANDOFF_OBSERVED did not create handoff crumb.")
	memory.clear_storage()


func _test_note_sanitization() -> void:
	var memory := _fresh_memory()
	var long_text := ""
	for index in 40:
		long_text += "ab "
	memory.record_observed({"type": "LOCAL_NOTE", "text": "line1\nline2\n" + long_text}, 20)
	var report: Dictionary = memory.memory_report()
	_assert(int(report.get("active", 0)) == 1, "Note did not record.")
	var stored_text := String(memory.storage_path())
	_assert(stored_text.contains("test_wf0_8"), "Storage path lost the memory id.")
	var parsed: Dictionary = memory.memory_report()
	_assert(String(parsed.get("schema", "")) == MemoryScript.SCHEMA, "Report schema missing.")
	_assert(int(report.get("by_type", {}).get("local_note", 0)) == 1, "Note crumb type missing.")
	memory.clear_storage()


func _test_budget_evicts_oldest() -> void:
	var memory := _fresh_memory()
	for index in MemoryScript.MAX_CRUMBS + 12:
		memory.record_observed({"type": "VISIT", "position": Vector3(float(index), 0.0, 0.0)}, index)
	var report: Dictionary = memory.memory_report()
	_assert(int(report.get("active", -1)) == MemoryScript.MAX_CRUMBS, "Memory exceeded its crumb budget.")
	memory.clear_storage()


func _test_save_load_roundtrip() -> void:
	var writer := _fresh_memory()
	writer.record_observed({"type": "DIG_SUCCESS", "position": Vector3(3.0, 0.0, 4.0)}, 30)
	writer.record_observed({"type": "LOCAL_NOTE", "text": "good dig spot"}, 31)
	_assert(bool(writer.save()), "Save to user:// failed.")

	var reader: RefCounted = MemoryScript.new()
	reader.configure_storage(TEST_MEMORY_ID)
	var loaded: bool = reader.load_memory()
	_assert(bool(loaded), "Load from user:// failed.")
	var report: Dictionary = reader.memory_report()
	_assert(int(report.get("active", 0)) == 2, "Roundtrip lost crumbs.")
	var by_type: Dictionary = report.get("by_type", {})
	_assert(int(by_type.get("dug_here", 0)) == 1 and int(by_type.get("local_note", 0)) == 1, "Roundtrip changed crumb types.")
	reader.clear_storage()


func _test_local_only_report() -> void:
	var memory := _fresh_memory()
	var report: Dictionary = memory.memory_report()
	_assert(bool(report.get("server_synced", true)) == false, "Local memory must never claim server sync.")
	_assert(String(report.get("storage", "")).begins_with("user://world_memory/"), "Storage is not under user://world_memory/.")
	memory.clear_storage()


func _test_fail_soft_paths() -> void:
	var memory: RefCounted = MemoryScript.new()
	memory.configure_storage("test_wf0_8_missing")
	_assert(not bool(memory.load_memory()), "Loading a missing file must return false, not error.")
	_assert(int(memory.memory_report().get("active", -1)) == 0, "Missing file produced crumbs.")
	memory.record_observed({"type": "TOTALLY_UNKNOWN"}, 1)
	_assert(int(memory.memory_report().get("active", -1)) == 0, "Unknown event created a crumb.")
	memory.clear_storage()


func _test_cleanup() -> void:
	var memory := _fresh_memory()
	memory.record_observed({"type": "VISIT", "position": Vector3.ZERO}, 1)
	memory.save()
	memory.clear_storage()
	_assert(not FileAccess.file_exists(memory.storage_path()), "clear_storage left the file behind.")
	var reloaded: RefCounted = MemoryScript.new()
	reloaded.configure_storage(TEST_MEMORY_ID)
	_assert(not bool(reloaded.load_memory()), "Cleared memory loaded again.")


func _finish() -> void:
	if failures.is_empty():
		print("WF0.8 local memory tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("WF0.8 local memory tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
