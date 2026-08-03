extends RefCounted

const H = preload("res://scripts/construction/hardening/construction_hardening_utils.gd")
const Operation = preload("res://scripts/construction/hardening/construction_production_operation.gd")

static func operation_cases(valid_operation: Dictionary) -> Array:
	var cases: Array = []
	for field in Operation.FIELDS:
		var missing := valid_operation.duplicate(true)
		missing.erase(field)
		cases.append(missing)
	var invalid_values := {
		"schema": "invalid",
		"operation_id": "operation/UPPER",
		"subject_id": "subject//broken",
		"construct_id": "construct/",
		"action": "contains space",
		"permission_epoch": -1,
		"release_id": "release/UPPER",
		"operation_version": 99,
		"tick": -1,
		"payload": [],
		"payload_checksum": "0",
		"checksum": "0",
	}
	for field in invalid_values:
		var mutated := valid_operation.duplicate(true)
		mutated[field] = invalid_values[field]
		cases.append(mutated)
	var extra := valid_operation.duplicate(true)
	extra["unexpected"] = true
	cases.append(extra)
	var nested_runtime := valid_operation.duplicate(true)
	nested_runtime["payload"] = {"runtime": Vector3.ZERO}
	nested_runtime["payload_checksum"] = ""
	nested_runtime["checksum"] = H.checksum(nested_runtime)
	cases.append(nested_runtime)
	return cases

static func verify_rejected(cases: Array) -> Dictionary:
	var accepted: Array = []
	for index in range(cases.size()):
		var checked := Operation.validate(cases[index])
		if bool(checked.get("success", false)):
			accepted.append(index)
	if not accepted.is_empty():
		return H.failure("CONSTRUCTION_DTO_FUZZ_CASE_ACCEPTED", {"accepted_indices": accepted})
	return H.success({"case_count": cases.size()})
