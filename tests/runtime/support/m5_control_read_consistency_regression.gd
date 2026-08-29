extends SceneTree

const AtomicJson = preload("res://scripts/testing/process_harness/atomic_json_file.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/m5/m5_graphical_acceptance_support.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	var root := ProjectSettings.globalize_path(
		"res://artifacts/test-results/m5-control-read-regression-%d" % OS.get_process_id()
	)
	DirAccess.make_dir_recursive_absolute(root)

	_test_valid_empty_is_not_transient(root)
	_test_missing_read_recovers(root)
	_test_incomplete_read_recovers(root)
	_test_persistent_missing_exhausts(root)
	_test_non_retryable_error_stops_immediately()

	print("M5 control read consistency regression: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_valid_empty_is_not_transient(root: String) -> void:
	var path := root.path_join("valid-empty.json")
	var write_result := AtomicJson.write_dictionary(path, {})
	_assert(bool(write_result.get("success", false)), "valid empty JSON control fixture writes successfully")
	var read_result := Support.read_control_consistent(path)
	_assert(bool(read_result.get("success", false)), "valid empty JSON is a successful typed control read")
	_assert(int(read_result.get("attempts", 0)) == 1, "valid empty JSON is not retried as transient")
	_assert(Dictionary(read_result.get("value", {"unexpected": true})).is_empty(), "valid empty JSON remains an empty Dictionary value")


func _test_missing_read_recovers(root: String) -> void:
	var path := root.path_join("missing-then-valid.json")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var thread := Thread.new()
	var start_error := thread.start(
		Callable(self, "_delayed_atomic_write").bind(
			path,
			{"schema": Support.CONTROL_SCHEMA, "marker": "missing-recovered"},
			20
		)
	)
	_assert(start_error == OK, "missing-read recovery writer thread starts")
	if start_error != OK:
		return
	var read_result := AtomicJson.read_dictionary_with_retry(path, 12, 5)
	var writer_result = thread.wait_to_finish()
	_assert(bool(writer_result.get("success", false)), "missing-read delayed writer succeeds")
	_assert(bool(read_result.get("success", false)), "bounded read recovers after transient missing target")
	_assert(int(read_result.get("attempts", 0)) > 1, "missing target recovery required at least one retry")
	_assert(String(read_result.get("value", {}).get("marker", "")) == "missing-recovered", "missing target recovery returns the newly published JSON")


func _test_incomplete_read_recovers(root: String) -> void:
	var path := root.path_join("incomplete-then-valid.json")
	var incomplete := FileAccess.open(path, FileAccess.WRITE)
	_assert(incomplete != null, "incomplete JSON fixture opens")
	if incomplete == null:
		return
	incomplete.store_string("{")
	incomplete.flush()
	incomplete.close()

	var first := AtomicJson.read_dictionary(path)
	_assert(not bool(first.get("success", false)), "incomplete JSON one-shot read fails")
	_assert(String(first.get("error_code", "")) == "ATOMIC_JSON_INCOMPLETE", "incomplete JSON is typed as retryable incomplete read")

	var thread := Thread.new()
	var start_error := thread.start(
		Callable(self, "_delayed_atomic_write").bind(
			path,
			{"schema": Support.CONTROL_SCHEMA, "marker": "incomplete-recovered"},
			20
		)
	)
	_assert(start_error == OK, "incomplete-read recovery writer thread starts")
	if start_error != OK:
		return
	var read_result := AtomicJson.read_dictionary_with_retry(path, 12, 5)
	var writer_result = thread.wait_to_finish()
	_assert(bool(writer_result.get("success", false)), "incomplete-read delayed writer succeeds")
	_assert(bool(read_result.get("success", false)), "bounded read recovers after transient incomplete JSON")
	_assert(int(read_result.get("attempts", 0)) > 1, "incomplete JSON recovery required at least one retry")
	_assert(String(read_result.get("value", {}).get("marker", "")) == "incomplete-recovered", "incomplete JSON recovery returns the complete replacement")


func _test_persistent_missing_exhausts(root: String) -> void:
	var path := root.path_join("persistent-missing.json")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var read_result := AtomicJson.read_dictionary_with_retry(path, 3, 1)
	_assert(not bool(read_result.get("success", false)), "persistent missing control remains a failure")
	_assert(String(read_result.get("error_code", "")) == "ATOMIC_JSON_NOT_FOUND", "persistent missing control retains typed NOT_FOUND")
	_assert(int(read_result.get("attempts", 0)) == 3, "persistent missing control exhausts exactly the bounded attempts")
	_assert(bool(read_result.get("transient_exhausted", false)), "persistent missing control reports exhausted transient budget")


func _test_non_retryable_error_stops_immediately() -> void:
	var read_result := AtomicJson.read_dictionary_with_retry("", 8, 1)
	_assert(not bool(read_result.get("success", false)), "empty control path is rejected")
	_assert(String(read_result.get("error_code", "")) == "ATOMIC_JSON_PATH_EMPTY", "empty control path has a non-transient typed error")
	_assert(int(read_result.get("attempts", 0)) == 1, "non-transient empty path is not retried")
	_assert(not bool(read_result.get("transient_exhausted", true)), "non-transient empty path is not marked as retry exhaustion")


func _delayed_atomic_write(path: String, value: Dictionary, delay_ms: int) -> Dictionary:
	OS.delay_msec(delay_ms)
	return AtomicJson.write_dictionary(path, value)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)
