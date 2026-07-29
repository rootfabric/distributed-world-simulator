extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ComputeUtilsScript = preload("res://scripts/simulation/compute/compute_contract_utils.gd")

const SCHEMA := "planet_simulator.execution_budget.v1"
const FIELDS: Array[String] = ["schema", "maximum_operations", "maximum_output_bytes", "maximum_instruction_units"]


static func create(maximum_operations: int, maximum_output_bytes: int, maximum_instruction_units: int) -> Dictionary:
	return {"schema": SCHEMA, "maximum_operations": maximum_operations, "maximum_output_bytes": maximum_output_bytes, "maximum_instruction_units": maximum_instruction_units}


static func validate(value: Dictionary) -> Dictionary:
	var exact := NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return ComputeUtilsScript.failure("UNSUPPORTED_EXECUTION_BUDGET_SCHEMA")
	for field in ["maximum_operations", "maximum_output_bytes", "maximum_instruction_units"]:
		if not NetworkUtilsScript.is_json_integer(value.get(field)) or int(value[field]) < 1:
			return ComputeUtilsScript.failure("INVALID_EXECUTION_BUDGET", {"field": field})
	if int(value["maximum_operations"]) > 100000 or int(value["maximum_output_bytes"]) > 67108864 or int(value["maximum_instruction_units"]) > 1000000000:
		return ComputeUtilsScript.failure("EXECUTION_BUDGET_OUT_OF_RANGE")
	return ComputeUtilsScript.success()


static func contains(limit: Dictionary, requested: Dictionary) -> bool:
	return int(requested.get("maximum_operations", 0)) <= int(limit.get("maximum_operations", 0)) \
		and int(requested.get("maximum_output_bytes", 0)) <= int(limit.get("maximum_output_bytes", 0)) \
		and int(requested.get("maximum_instruction_units", 0)) <= int(limit.get("maximum_instruction_units", 0))
