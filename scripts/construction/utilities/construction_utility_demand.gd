extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ContractUtils = preload("res://scripts/construction/utilities/construction_utility_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_utility_demand.v1"
const FIELDS: Array[String] = ["schema", "demand_id", "network_id", "consumer_node_id", "requested_per_tick", "minimum_required_per_tick", "priority", "shed_group", "metadata", "checksum"]

static func create(demand_id: String, network_id: String, consumer_node_id: String, requested_per_tick: float, minimum_required_per_tick: float, priority: int, shed_group: String = "default", metadata: Dictionary = {}) -> Dictionary:
	var value := {"schema": SCHEMA, "demand_id": demand_id, "network_id": network_id, "consumer_node_id": consumer_node_id, "requested_per_tick": requested_per_tick, "minimum_required_per_tick": minimum_required_per_tick, "priority": priority, "shed_group": shed_group, "metadata": metadata.duplicate(true), "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return ContractUtils.failure("UNSUPPORTED_CONSTRUCTION_UTILITY_DEMAND_SCHEMA")
	if not ContractUtils.is_path(String(value.get("demand_id", "")), "utility-demand/") or not ContractUtils.is_path(String(value.get("network_id", "")), "utility-network/") or not ContractUtils.is_path(String(value.get("consumer_node_id", "")), "utility-node/"): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_DEMAND_IDENTITY")
	if not ContractUtils.positive(value.get("requested_per_tick")) or not ContractUtils.non_negative(value.get("minimum_required_per_tick")) or float(value["minimum_required_per_tick"]) > float(value["requested_per_tick"]): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_DEMAND_QUANTITY")
	if not UtilsScript.is_json_integer(value.get("priority")) or int(value["priority"]) < 0 or int(value["priority"]) > 1000: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_DEMAND_PRIORITY")
	if typeof(value.get("shed_group")) != TYPE_STRING or String(value["shed_group"]).strip_edges().is_empty(): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_SHED_GROUP")
	if typeof(value.get("metadata")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["metadata"]).get("success", false)): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_DEMAND_METADATA")
	if String(value.get("checksum", "")) != compute_checksum(value): return ContractUtils.failure("CONSTRUCTION_UTILITY_DEMAND_CHECKSUM_MISMATCH")
	return ContractUtils.success()
static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
