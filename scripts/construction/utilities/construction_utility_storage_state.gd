extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ContractUtils = preload("res://scripts/construction/utilities/construction_utility_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_utility_storage_state.v1"
const FIELDS: Array[String] = ["schema", "network_id", "node_id", "tick", "revision", "stored_amount", "capacity", "checksum"]

static func create(network_id: String, node_id: String, tick: int, revision: int, stored_amount: float, capacity: float) -> Dictionary:
	var value := {"schema": SCHEMA, "network_id": network_id, "node_id": node_id, "tick": tick, "revision": revision, "stored_amount": stored_amount, "capacity": capacity, "checksum": ""}; value["checksum"] = compute_checksum(value); return value
static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return ContractUtils.failure("UNSUPPORTED_CONSTRUCTION_UTILITY_STORAGE_STATE_SCHEMA")
	if not ContractUtils.is_path(String(value.get("network_id", "")), "utility-network/") or not ContractUtils.is_path(String(value.get("node_id", "")), "utility-node/"): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_STORAGE_STATE_IDENTITY")
	for field in ["tick", "revision"]:
		if not UtilsScript.is_json_integer(value.get(field)) or int(value[field]) < 0: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_STORAGE_STATE_VERSION")
	if not ContractUtils.positive(value.get("capacity")) or not ContractUtils.non_negative(value.get("stored_amount")) or float(value["stored_amount"]) > float(value["capacity"]): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_STORAGE_STATE_AMOUNT")
	if String(value.get("checksum", "")) != compute_checksum(value): return ContractUtils.failure("CONSTRUCTION_UTILITY_STORAGE_STATE_CHECKSUM_MISMATCH")
	return ContractUtils.success()
static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
