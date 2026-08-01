extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_streaming_policy.v1"
const FIELDS: Array[String] = ["schema", "presented_distance_m", "simulated_distance_m", "summary_distance_m", "hysteresis_m", "dormant_after_ticks", "summary_budget_bytes", "simulation_budget_units", "presentation_budget_bytes", "catch_up_interval_ticks", "maximum_catch_up_steps", "checksum"]

static func create(presented_distance_m: float = 25.0, simulated_distance_m: float = 100.0, summary_distance_m: float = 500.0, hysteresis_m: float = 10.0, dormant_after_ticks: int = 30, summary_budget_bytes: int = 1048576, simulation_budget_units: int = 1000, presentation_budget_bytes: int = 1048576, catch_up_interval_ticks: int = 10, maximum_catch_up_steps: int = 32) -> Dictionary:
	var value := {"schema": SCHEMA, "presented_distance_m": presented_distance_m, "simulated_distance_m": simulated_distance_m, "summary_distance_m": summary_distance_m, "hysteresis_m": hysteresis_m, "dormant_after_ticks": dormant_after_ticks, "summary_budget_bytes": summary_budget_bytes, "simulation_budget_units": simulation_budget_units, "presentation_budget_bytes": presentation_budget_bytes, "catch_up_interval_ticks": catch_up_interval_ticks, "maximum_catch_up_steps": maximum_catch_up_steps, "checksum": ""}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_STREAMING_POLICY_SCHEMA")
	for field in ["presented_distance_m", "simulated_distance_m", "summary_distance_m", "hysteresis_m"]:
		if typeof(value.get(field)) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(value[field])) or is_inf(float(value[field])) or float(value[field]) < 0.0:
			return _failure("INVALID_CONSTRUCTION_STREAMING_POLICY_DISTANCE")
	if float(value["presented_distance_m"]) > float(value["simulated_distance_m"]) or float(value["simulated_distance_m"]) > float(value["summary_distance_m"]):
		return _failure("NON_MONOTONIC_CONSTRUCTION_STREAMING_DISTANCES")
	for field in ["dormant_after_ticks", "summary_budget_bytes", "simulation_budget_units", "presentation_budget_bytes", "catch_up_interval_ticks", "maximum_catch_up_steps"]:
		if not Utils.is_json_integer(value.get(field)) or int(value[field]) < 0: return _failure("INVALID_CONSTRUCTION_STREAMING_POLICY_INTEGER")
	if int(value["catch_up_interval_ticks"]) < 1 or int(value["maximum_catch_up_steps"]) < 1: return _failure("INVALID_CONSTRUCTION_STREAMING_CATCH_UP_POLICY")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_STREAMING_POLICY_CHECKSUM_MISMATCH")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return Utils.payload_hash(payload)
static func _success() -> Dictionary: return {"success": true, "error_code": "", "message": ""}
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}
