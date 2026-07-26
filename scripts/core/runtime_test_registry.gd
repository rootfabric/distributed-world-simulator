extends RefCounted

signal test_registered(test_id: String)
signal test_completed(test_id: String, result: Dictionary)

var _tests: Dictionary = {}
var _registration_errors: Array[Dictionary] = []


func register_test(
	definition: Dictionary,
	callback: Callable,
	owner_id: String = "core"
) -> bool:
	var test_id: String = String(definition.get("id", "")).strip_edges().to_lower()
	if test_id.is_empty():
		_record_registration_error(owner_id, test_id, "EMPTY_TEST_ID")
		return false
	if not callback.is_valid():
		_record_registration_error(owner_id, test_id, "INVALID_CALLBACK")
		return false
	if _tests.has(test_id):
		_record_registration_error(owner_id, test_id, "TEST_ID_COLLISION")
		return false
	_tests[test_id] = {
		"id": test_id,
		"description": String(definition.get("description", "")),
		"category": String(definition.get("category", "runtime")),
		"callback": callback,
		"owner_id": owner_id,
	}
	test_registered.emit(test_id)
	return true


func unregister_owner(owner_id: String) -> int:
	var removed: Array[String] = []
	for test_id_value in _tests.keys():
		var test_id: String = String(test_id_value)
		if String(_tests[test_id].get("owner_id", "")) == owner_id:
			removed.append(test_id)
	for test_id in removed:
		_tests.erase(test_id)
	return removed.size()


func clear_registration_errors() -> void:
	_registration_errors.clear()


func get_registration_errors() -> Array[Dictionary]:
	return _registration_errors.duplicate(true)


func get_owner_test_count(owner_id: String) -> int:
	var count: int = 0
	for test_id_value in _tests.keys():
		var record: Dictionary = _tests[String(test_id_value)]
		if String(record.get("owner_id", "")) == owner_id:
			count += 1
	return count


func list_tests(owner_filter: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for test_id_value in _tests.keys():
		var test_id: String = String(test_id_value)
		var record: Dictionary = _tests[test_id]
		if (
			not owner_filter.is_empty()
			and String(record.get("owner_id", "")) != owner_filter
		):
			continue
		result.append({
			"id": test_id,
			"description": record.get("description", ""),
			"category": record.get("category", "runtime"),
			"owner_id": record.get("owner_id", ""),
		})
	result.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return String(first.get("id", "")) < String(second.get("id", ""))
	)
	return result


func run_test(test_id: String) -> Dictionary:
	var normalized: String = test_id.strip_edges().to_lower()
	if not _tests.has(normalized):
		return {
			"success": false,
			"passed": false,
			"test_id": normalized,
			"output": "Тест не найден: %s" % normalized,
			"error_code": "UNKNOWN_TEST",
		}
	var record: Dictionary = _tests[normalized]
	var callback: Callable = record["callback"]
	var started_msec: int = Time.get_ticks_msec()
	var raw_result = callback.call()
	var result: Dictionary = _normalize_result(raw_result)
	result["test_id"] = normalized
	result["duration_msec"] = Time.get_ticks_msec() - started_msec
	result["description"] = record.get("description", "")
	test_completed.emit(normalized, result)
	return result


func run_all(owner_filter: String = "") -> Dictionary:
	var test_records: Array[Dictionary] = list_tests(owner_filter)
	var results: Array[Dictionary] = []
	var passed_count: int = 0
	for test_record in test_records:
		var result: Dictionary = run_test(String(test_record.get("id", "")))
		results.append(result)
		if bool(result.get("passed", false)):
			passed_count += 1
	var failed_count: int = results.size() - passed_count
	return {
		"success": failed_count == 0,
		"passed": failed_count == 0,
		"passed_count": passed_count,
		"failed_count": failed_count,
		"total_count": results.size(),
		"results": results,
		"output": "Тесты: %d PASS, %d FAIL, всего %d" % [
			passed_count,
			failed_count,
			results.size(),
		],
	}


func get_test_count() -> int:
	return _tests.size()


func _record_registration_error(owner_id: String, test_id: String, reason: String) -> void:
	_registration_errors.append({
		"owner_id": owner_id,
		"test_id": test_id,
		"reason": reason,
	})


func _normalize_result(raw_result) -> Dictionary:
	if raw_result is Dictionary:
		var result: Dictionary = raw_result.duplicate(true)
		if not result.has("passed"):
			result["passed"] = bool(result.get("success", true))
		if not result.has("success"):
			result["success"] = bool(result.get("passed", false))
		if not result.has("output"):
			result["output"] = String(result.get("summary", "PASS" if result["passed"] else "FAIL"))
		return result
	if raw_result is bool:
		return {
			"success": raw_result,
			"passed": raw_result,
			"output": "PASS" if raw_result else "FAIL",
		}
	return {
		"success": raw_result != null,
		"passed": raw_result != null,
		"output": String(raw_result) if raw_result != null else "FAIL",
	}
