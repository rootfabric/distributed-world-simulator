extends RefCounted
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ContractUtils = preload("res://scripts/construction/utilities/construction_utility_contract_utils.gd")
const ProfileScript = preload("res://scripts/construction/utilities/construction_utility_execution_profile.gd")
const SCHEMA := "planet_simulator.construction_utility_summary.v1"
const FIELDS: Array[String] = ["schema", "network_id", "utility_kind", "tick", "profile_checksum", "status", "demand_count", "shed_demand_ids", "total_requested", "total_delivered", "storage_amount", "checksum"]
static func compile(profile: Dictionary) -> Dictionary:
	var checked := ProfileScript.validate(profile); if not bool(checked.get("success", false)): return checked
	var shed: Array = []; var storage_amount := 0.0
	for allocation in profile["allocations"]:
		if String(allocation["status"]) == "SHED": shed.append(String(allocation["demand_id"]))
	for state in profile["storage_states"]: storage_amount += float(state["stored_amount"])
	var value := {"schema": SCHEMA, "network_id": String(profile["network_id"]), "utility_kind": String(profile["utility_kind"]), "tick": int(profile["tick"]), "profile_checksum": String(profile["checksum"]), "status": String(profile["status"]), "demand_count": profile["allocations"].size(), "shed_demand_ids": shed, "total_requested": float(profile["total_requested"]), "total_delivered": float(profile["total_delivered"]), "storage_amount": storage_amount, "checksum": ""}; value["checksum"] = compute_checksum(value); return ContractUtils.success({"summary": value})
static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA or not ContractUtils.is_path(String(value.get("network_id", "")), "utility-network/") or not ContractUtils.VALID_KINDS.has(String(value.get("utility_kind", ""))): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_SUMMARY_IDENTITY")
	if not UtilsScript.is_json_integer(value.get("tick")) or int(value["tick"]) < 0 or String(value.get("profile_checksum", "")).length() != 64 or not ProfileScript.STATUSES.has(String(value.get("status", ""))): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_SUMMARY_STATE")
	if not UtilsScript.is_json_integer(value.get("demand_count")) or int(value["demand_count"]) < 0: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_SUMMARY_COUNT")
	var refs := ContractUtils.sorted_unique_strings(value.get("shed_demand_ids"), "utility-demand/", true); if not bool(refs.get("success", false)): return refs
	for field in ["total_requested", "total_delivered", "storage_amount"]:
		if not ContractUtils.non_negative(value.get(field)): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_SUMMARY_QUANTITY")
	if String(value.get("checksum", "")) != compute_checksum(value): return ContractUtils.failure("CONSTRUCTION_UTILITY_SUMMARY_CHECKSUM_MISMATCH")
	return ContractUtils.success()
static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
