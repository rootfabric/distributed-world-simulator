extends RefCounted

const SubjectScript = preload("res://scripts/construction/behavior/construction_runtime_subject_state.gd")

const SCHEMA: String = "planet_simulator.construction_runtime_failure_policy.v1"
const LEVEL_NONE: String = "NONE"
const LEVEL_OPTIONAL: String = "OPTIONAL"
const LEVEL_REQUIRED: String = "REQUIRED"
const OPERABILITY_ONLINE: String = "ONLINE"
const OPERABILITY_DEGRADED: String = "DEGRADED"
const OPERABILITY_OFFLINE: String = "OFFLINE"

const REQUIREMENT_KEYS: Array[String] = ["power", "data", "dependency"]
const FAILURE_CODE_BY_KEY: Dictionary = {
	"power": "POWER_UNAVAILABLE",
	"data": "DATA_UNAVAILABLE",
	"dependency": "DEPENDENCY_UNAVAILABLE",
}


static func project(subject: Dictionary, requirements: Dictionary, availability: Dictionary) -> Dictionary:
	var subject_validation: Dictionary = SubjectScript.validate(subject)
	if not bool(subject_validation.get("success", false)):
		return subject_validation
	var requirement_validation: Dictionary = _validate_requirements(requirements)
	if not bool(requirement_validation.get("success", false)):
		return requirement_validation
	var availability_validation: Dictionary = _validate_availability(availability)
	if not bool(availability_validation.get("success", false)):
		return availability_validation

	var required_failures: Array[String] = []
	var optional_failures: Array[String] = []
	for key in REQUIREMENT_KEYS:
		var level: String = String(requirements.get(key, LEVEL_NONE))
		if level == LEVEL_NONE or bool(availability.get(key, false)):
			continue
		var code: String = String(FAILURE_CODE_BY_KEY[key])
		if level == LEVEL_REQUIRED:
			required_failures.append(code)
		else:
			optional_failures.append(code)

	required_failures.sort()
	optional_failures.sort()
	var failure_codes: Array[String] = []
	failure_codes.append_array(required_failures)
	failure_codes.append_array(optional_failures)

	var operability: String = OPERABILITY_ONLINE
	if not required_failures.is_empty():
		operability = OPERABILITY_OFFLINE
	elif not optional_failures.is_empty():
		operability = OPERABILITY_DEGRADED

	var next_state: Dictionary = Dictionary(subject.get("state", {})).duplicate(true)
	next_state["operability"] = operability
	next_state["failure_codes"] = failure_codes

	return _success({
		"schema": SCHEMA,
		"runtime_id": String(subject.get("runtime_id", "")),
		"construct_id": String(subject.get("construct_id", "")),
		"expected_revision": int(subject.get("revision", -1)),
		"next_state": next_state,
		"operability": operability,
		"failure_codes": failure_codes,
		"mutates_construct_snapshot": false,
		"requires_new_aggregate": false,
	})


static func _validate_requirements(requirements: Dictionary) -> Dictionary:
	if requirements.size() != REQUIREMENT_KEYS.size():
		return _failure("INVALID_CONSTRUCTION_RUNTIME_FAILURE_REQUIREMENTS")
	for key in REQUIREMENT_KEYS:
		if not requirements.has(key):
			return _failure("INVALID_CONSTRUCTION_RUNTIME_FAILURE_REQUIREMENTS")
		var level: String = String(requirements[key])
		if level not in [LEVEL_NONE, LEVEL_OPTIONAL, LEVEL_REQUIRED]:
			return _failure("INVALID_CONSTRUCTION_RUNTIME_FAILURE_REQUIREMENT_LEVEL", {"key": key, "level": level})
	return _success()


static func _validate_availability(availability: Dictionary) -> Dictionary:
	if availability.size() != REQUIREMENT_KEYS.size():
		return _failure("INVALID_CONSTRUCTION_RUNTIME_FAILURE_AVAILABILITY")
	for key in REQUIREMENT_KEYS:
		if not availability.has(key) or typeof(availability[key]) != TYPE_BOOL:
			return _failure("INVALID_CONSTRUCTION_RUNTIME_FAILURE_AVAILABILITY", {"key": key})
	return _success()


static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
