extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_proxy_portal.v1"
const FIELDS: Array[String] = ["schema", "portal_id", "cell_a_id", "cell_b_id", "local_position_m", "open", "checksum"]

static func create(portal_id: String, cell_a_id: String, cell_b_id: String, local_position_m: Array, open: bool = true) -> Dictionary:
	var value := {"schema": SCHEMA, "portal_id": portal_id, "cell_a_id": cell_a_id, "cell_b_id": cell_b_id, "local_position_m": local_position_m.duplicate(true), "open": open, "checksum": ""}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA or not C.path_id(String(value.get("portal_id", "")), "portal/"): return C.failure("INVALID_CONSTRUCTION_PROXY_PORTAL_IDENTITY")
	for field in ["cell_a_id", "cell_b_id"]:
		if not C.path_id(String(value.get(field, "")), "interior-cell/"): return C.failure("INVALID_CONSTRUCTION_PROXY_PORTAL_CELL")
	if String(value["cell_a_id"]) == String(value["cell_b_id"]): return C.failure("INVALID_CONSTRUCTION_PROXY_PORTAL_LOOP")
	if not C.finite_vector(value.get("local_position_m"), 3) or typeof(value.get("open")) != TYPE_BOOL: return C.failure("INVALID_CONSTRUCTION_PROXY_PORTAL_STATE")
	if String(value.get("checksum", "")) != compute_checksum(value): return C.failure("CONSTRUCTION_PROXY_PORTAL_CHECKSUM_MISMATCH")
	return C.success()

static func compute_checksum(value: Dictionary) -> String: return C.compute_checksum(value)
