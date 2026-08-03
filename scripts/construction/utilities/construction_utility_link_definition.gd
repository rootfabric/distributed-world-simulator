extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ContractUtils = preload("res://scripts/construction/utilities/construction_utility_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_utility_link_definition.v1"
const FIELDS: Array[String] = ["schema", "link_id", "network_id", "utility_kind", "node_a_id", "node_b_id", "capacity_per_tick", "loss_fraction", "enabled", "properties", "checksum"]

static func create(link_id: String, network_id: String, utility_kind: String, node_a_id: String, node_b_id: String, capacity_per_tick: float, loss_fraction: float = 0.0, enabled: bool = true, properties: Dictionary = {}) -> Dictionary:
	var endpoints := [node_a_id, node_b_id]; endpoints.sort()
	var value := {"schema": SCHEMA, "link_id": link_id, "network_id": network_id, "utility_kind": utility_kind, "node_a_id": endpoints[0], "node_b_id": endpoints[1], "capacity_per_tick": capacity_per_tick, "loss_fraction": loss_fraction, "enabled": enabled, "properties": properties.duplicate(true), "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return ContractUtils.failure("UNSUPPORTED_CONSTRUCTION_UTILITY_LINK_SCHEMA")
	if not ContractUtils.is_path(String(value.get("link_id", "")), "utility-link/") or not ContractUtils.is_path(String(value.get("network_id", "")), "utility-network/"): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_LINK_ID")
	if typeof(value.get("utility_kind")) != TYPE_STRING or not ContractUtils.VALID_KINDS.has(String(value["utility_kind"])): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_KIND")
	for field in ["node_a_id", "node_b_id"]:
		if not ContractUtils.is_path(String(value.get(field, "")), "utility-node/"): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_LINK_ENDPOINT")
	if String(value["node_a_id"]) >= String(value["node_b_id"]): return ContractUtils.failure("NON_CANONICAL_CONSTRUCTION_UTILITY_LINK_ENDPOINTS")
	if not ContractUtils.positive(value.get("capacity_per_tick")): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_LINK_CAPACITY")
	if not ContractUtils.ratio(value.get("loss_fraction")) or float(value["loss_fraction"]) >= 1.0: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_LINK_LOSS")
	if typeof(value.get("enabled")) != TYPE_BOOL: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_LINK_ENABLED")
	if typeof(value.get("properties")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["properties"]).get("success", false)): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_LINK_PROPERTIES")
	if String(value.get("checksum", "")) != compute_checksum(value): return ContractUtils.failure("CONSTRUCTION_UTILITY_LINK_CHECKSUM_MISMATCH")
	return ContractUtils.success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
