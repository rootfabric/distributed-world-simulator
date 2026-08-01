extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ContractUtils = preload("res://scripts/construction/utilities/construction_utility_contract_utils.gd")
const LeaseScript = preload("res://scripts/construction/utilities/construction_machine_utility_lease.gd")
const MachineProfileScript = preload("res://scripts/construction/fabrication/construction_fabrication_machine_profile.gd")
const STATE_SCHEMA := "planet_simulator.construction_executable_fabrication_runtime.v1"
const STATE_FIELDS: Array[String] = ["schema", "generation", "lease_usage", "terminal_operations", "checksum"]
const USAGE_FIELDS: Array[String] = ["lease_checksum", "used_work_units"]
const TERMINAL_FIELDS: Array[String] = ["operation_id", "request_checksum", "result"]
var _process; var _configured := false; var _lease_usage := {}; var _terminal := {}; var _generation := 0

func setup(fabrication_process) -> Dictionary:
	if fabrication_process == null or not fabrication_process.has_method("reserve_job") or not fabrication_process.has_method("advance_job") or not fabrication_process.has_method("complete_job"): return ContractUtils.failure("CONSTRUCTION_EXECUTABLE_FABRICATION_PROCESS_REQUIRED")
	_process = fabrication_process; _configured = true; return ContractUtils.success()
func reserve_job(job_id: String, machine_profile: Dictionary, lease: Dictionary, failure_mode: String = "") -> Dictionary:
	var checked := _validate_access(job_id, machine_profile, lease); if not bool(checked.get("success", false)): return checked
	if String(lease["status"]) == "OFFLINE": return ContractUtils.failure("CONSTRUCTION_FABRICATION_UTILITY_LEASE_OFFLINE")
	return _process.reserve_job(job_id, machine_profile, failure_mode)
func advance_job(job_id: String, machine_profile: Dictionary, work_units: int, operation_id: String, lease: Dictionary) -> Dictionary:
	var checked := _validate_access(job_id, machine_profile, lease); if not bool(checked.get("success", false)): return checked
	if String(lease["status"]) == "OFFLINE": return ContractUtils.failure("CONSTRUCTION_FABRICATION_UTILITY_LEASE_OFFLINE")
	if work_units < 1: return ContractUtils.failure("INVALID_CONSTRUCTION_FABRICATION_UTILITY_WORK_UNITS")
	var request_checksum := UtilsScript.payload_hash({"job_id": job_id, "machine_profile_checksum": String(machine_profile["checksum"]), "work_units": work_units, "operation_id": operation_id, "lease_checksum": String(lease["checksum"])})
	if _terminal.has(operation_id):
		var terminal: Dictionary = _terminal[operation_id]
		if String(terminal["request_checksum"]) != request_checksum: return ContractUtils.failure("CONSTRUCTION_EXECUTABLE_FABRICATION_OPERATION_ID_CONFLICT")
		var replay: Dictionary = Dictionary(terminal["result"]).duplicate(true); replay["utility_runtime_replay"] = true; return replay
	var lease_checksum := String(lease["checksum"]); var used := int(_lease_usage.get(lease_checksum, 0))
	if used + work_units > int(lease["max_work_units"]): return ContractUtils.failure("CONSTRUCTION_FABRICATION_UTILITY_LEASE_CAPACITY_EXCEEDED", {"available_work_units": int(lease["max_work_units"]) - used})
	var result: Dictionary = _process.advance_job(job_id, machine_profile, work_units, operation_id)
	if bool(result.get("success", false)):
		_lease_usage[lease_checksum] = used + work_units; _terminal[operation_id] = {"operation_id": operation_id, "request_checksum": request_checksum, "result": result.duplicate(true)}; _generation += 1
	return result
func complete_job(job_id: String, machine_profile: Dictionary, lease: Dictionary, failure_mode: String = "") -> Dictionary:
	var checked := _validate_access(job_id, machine_profile, lease); if not bool(checked.get("success", false)): return checked
	if String(lease["status"]) == "OFFLINE": return ContractUtils.failure("CONSTRUCTION_FABRICATION_UTILITY_LEASE_OFFLINE")
	return _process.complete_job(job_id, machine_profile, failure_mode)
func get_generation() -> int: return _generation
func get_used_work_units(lease_checksum: String) -> int: return int(_lease_usage.get(lease_checksum, 0))
func export_state() -> Dictionary:
	var usage: Array = []; for checksum in _lease_usage: usage.append({"lease_checksum": String(checksum), "used_work_units": int(_lease_usage[checksum])})
	usage.sort_custom(func(a,b): return String(a["lease_checksum"]) < String(b["lease_checksum"]))
	var terminal: Array = []; for operation_id in _terminal: terminal.append(Dictionary(_terminal[operation_id]).duplicate(true))
	terminal.sort_custom(func(a,b): return String(a["operation_id"]) < String(b["operation_id"]))
	var state := {"schema": STATE_SCHEMA, "generation": _generation, "lease_usage": usage, "terminal_operations": terminal, "checksum": ""}; state["checksum"] = compute_state_checksum(state); return state
func load_state(state: Dictionary) -> Dictionary:
	var checked := validate_state(state); if not bool(checked.get("success", false)): return checked
	var usage := {}; for row in state["lease_usage"]: usage[String(row["lease_checksum"])] = int(row["used_work_units"])
	var terminal := {}; for row in state["terminal_operations"]: terminal[String(row["operation_id"])] = Dictionary(row).duplicate(true)
	_lease_usage = usage; _terminal = terminal; _generation = int(state["generation"]); return ContractUtils.success()
func _validate_access(job_id: String, machine_profile: Dictionary, lease: Dictionary) -> Dictionary:
	if not _configured: return ContractUtils.failure("CONSTRUCTION_EXECUTABLE_FABRICATION_RUNTIME_NOT_CONFIGURED")
	var checked := MachineProfileScript.validate(machine_profile); if not bool(checked.get("success", false)): return checked
	checked = LeaseScript.validate(lease); if not bool(checked.get("success", false)): return checked
	if String(lease["job_id"]) != job_id or String(lease["machine_construct_id"]) != String(machine_profile["construct_id"]) or String(lease["machine_profile_checksum"]) != String(machine_profile["checksum"]): return ContractUtils.failure("CONSTRUCTION_FABRICATION_UTILITY_LEASE_PRECONDITION_MISMATCH")
	return ContractUtils.success()
static func validate_state(state: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(state, STATE_FIELDS); if not bool(exact.get("success", false)): return exact
	if state.get("schema") != STATE_SCHEMA or not UtilsScript.is_json_integer(state.get("generation")) or int(state["generation"]) < 0 or typeof(state.get("lease_usage")) != TYPE_ARRAY or typeof(state.get("terminal_operations")) != TYPE_ARRAY: return ContractUtils.failure("INVALID_CONSTRUCTION_EXECUTABLE_FABRICATION_RUNTIME_STATE")
	var previous := ""; var seen := {}
	for row in state["lease_usage"]:
		if typeof(row) != TYPE_DICTIONARY: return ContractUtils.failure("INVALID_CONSTRUCTION_EXECUTABLE_FABRICATION_LEASE_USAGE")
		var checked := UtilsScript.validate_exact_fields(row, USAGE_FIELDS); if not bool(checked.get("success", false)): return checked
		var checksum := String(row.get("lease_checksum", "")); if checksum.length() != 64 or seen.has(checksum) or (not previous.is_empty() and checksum < previous) or not UtilsScript.is_json_integer(row.get("used_work_units")) or int(row["used_work_units"]) < 0: return ContractUtils.failure("NON_CANONICAL_CONSTRUCTION_EXECUTABLE_FABRICATION_LEASE_USAGE")
		seen[checksum] = true; previous = checksum
	previous = ""; seen = {}
	for row in state["terminal_operations"]:
		if typeof(row) != TYPE_DICTIONARY: return ContractUtils.failure("INVALID_CONSTRUCTION_EXECUTABLE_FABRICATION_TERMINAL_OPERATION")
		var checked := UtilsScript.validate_exact_fields(row, TERMINAL_FIELDS); if not bool(checked.get("success", false)): return checked
		var operation_id := String(row.get("operation_id", "")); if operation_id.is_empty() or seen.has(operation_id) or (not previous.is_empty() and operation_id < previous) or String(row.get("request_checksum", "")).length() != 64 or typeof(row.get("result")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(row["result"]).get("success", false)): return ContractUtils.failure("NON_CANONICAL_CONSTRUCTION_EXECUTABLE_FABRICATION_TERMINAL_OPERATIONS")
		seen[operation_id] = true; previous = operation_id
	if String(state.get("checksum", "")) != compute_state_checksum(state): return ContractUtils.failure("CONSTRUCTION_EXECUTABLE_FABRICATION_RUNTIME_CHECKSUM_MISMATCH")
	return ContractUtils.success()
static func compute_state_checksum(state: Dictionary) -> String:
	var payload := state.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
