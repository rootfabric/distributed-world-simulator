extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ContractUtils = preload("res://scripts/construction/utilities/construction_utility_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_utility_node_definition.v1"
const FIELDS: Array[String] = ["schema", "node_id", "network_id", "utility_kind", "node_kind", "construct_id", "part_id", "capacity_per_tick", "dispatch_priority", "properties", "checksum"]
const NODE_KINDS: Array[String] = ["SOURCE", "CONSUMER", "STORAGE", "JUNCTION"]

static func create(node_id: String, network_id: String, utility_kind: String, node_kind: String, construct_id: String, part_id: String, capacity_per_tick: float, dispatch_priority: int = 100, properties: Dictionary = {}) -> Dictionary:
	var value := {"schema": SCHEMA, "node_id": node_id, "network_id": network_id, "utility_kind": utility_kind, "node_kind": node_kind, "construct_id": construct_id, "part_id": part_id, "capacity_per_tick": capacity_per_tick, "dispatch_priority": dispatch_priority, "properties": properties.duplicate(true), "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return ContractUtils.failure("UNSUPPORTED_CONSTRUCTION_UTILITY_NODE_SCHEMA")
	if not ContractUtils.is_path(String(value.get("node_id", "")), "utility-node/"): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_NODE_ID")
	if not ContractUtils.is_path(String(value.get("network_id", "")), "utility-network/"): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_NODE_NETWORK_ID")
	if typeof(value.get("utility_kind")) != TYPE_STRING or not ContractUtils.VALID_KINDS.has(String(value["utility_kind"])): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_KIND")
	if typeof(value.get("node_kind")) != TYPE_STRING or not NODE_KINDS.has(String(value["node_kind"])): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_NODE_KIND")
	if not ContractUtils.is_path(String(value.get("construct_id", "")), "construct/") or not ContractUtils.is_path(String(value.get("part_id", "")), "part/"): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_NODE_PROVIDER")
	if not ContractUtils.non_negative(value.get("capacity_per_tick")): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_NODE_CAPACITY")
	if String(value["node_kind"]) in ["SOURCE", "STORAGE"] and float(value["capacity_per_tick"]) <= 0.0: return ContractUtils.failure("CONSTRUCTION_UTILITY_SUPPLY_CAPACITY_REQUIRED")
	if not UtilsScript.is_json_integer(value.get("dispatch_priority")) or int(value["dispatch_priority"]) < 0 or int(value["dispatch_priority"]) > 1000: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_DISPATCH_PRIORITY")
	if typeof(value.get("properties")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["properties"]).get("success", false)): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_NODE_PROPERTIES")
	if String(value["node_kind"]) == "STORAGE":
		for field in ["storage_capacity", "max_charge_per_tick", "max_discharge_per_tick"]:
			if not ContractUtils.positive(value["properties"].get(field)): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_STORAGE_DEFINITION")
		for field in ["charge_efficiency", "discharge_efficiency"]:
			if not ContractUtils.ratio(value["properties"].get(field), false): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_STORAGE_EFFICIENCY")
	if String(value.get("checksum", "")) != compute_checksum(value): return ContractUtils.failure("CONSTRUCTION_UTILITY_NODE_CHECKSUM_MISMATCH")
	return ContractUtils.success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
