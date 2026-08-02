extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_proxy_interest_request.v1"
const FIELDS: Array[String] = ["schema", "observer_id", "construct_id", "authority_epoch", "distance_m", "focus_local_m", "entered_cell_id", "visible_section_ids", "bandwidth_budget_bytes", "max_section_artifacts", "max_interactive_parts", "checksum"]

static func create(observer_id: String, construct_id: String, authority_epoch: int, distance_m: float, focus_local_m: Array, entered_cell_id: String = "", visible_section_ids: Array = [], bandwidth_budget_bytes: int = 1048576, max_section_artifacts: int = 12, max_interactive_parts: int = 64) -> Dictionary:
	var value := {"schema": SCHEMA, "observer_id": observer_id, "construct_id": construct_id, "authority_epoch": authority_epoch, "distance_m": distance_m, "focus_local_m": focus_local_m.duplicate(true), "entered_cell_id": entered_cell_id, "visible_section_ids": C.sorted_strings(visible_section_ids), "bandwidth_budget_bytes": bandwidth_budget_bytes, "max_section_artifacts": max_section_artifacts, "max_interactive_parts": max_interactive_parts, "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA or not C.path_id(String(value.get("observer_id", "")), "observer/") or not C.path_id(String(value.get("construct_id", "")), "construct/"): return C.failure("INVALID_CONSTRUCTION_PROXY_INTEREST_IDENTITY")
	if not Utils.is_json_integer(value.get("authority_epoch")) or int(value["authority_epoch"]) < 1 or not C.finite_number(value.get("distance_m")) or float(value["distance_m"]) < 0.0 or not C.finite_vector(value.get("focus_local_m"), 3): return C.failure("INVALID_CONSTRUCTION_PROXY_INTEREST_SCOPE")
	var cell_id := String(value.get("entered_cell_id", "")); if not cell_id.is_empty() and not C.path_id(cell_id, "interior-cell/"): return C.failure("INVALID_CONSTRUCTION_PROXY_INTEREST_CELL")
	if not C.sorted_unique_strings(value.get("visible_section_ids"), "section/"): return C.failure("INVALID_CONSTRUCTION_PROXY_INTEREST_SECTIONS")
	for field in ["bandwidth_budget_bytes", "max_section_artifacts", "max_interactive_parts"]:
		if not Utils.is_json_integer(value.get(field)) or int(value[field]) < 0: return C.failure("INVALID_CONSTRUCTION_PROXY_INTEREST_BUDGET")
	if String(value.get("checksum", "")) != compute_checksum(value): return C.failure("CONSTRUCTION_PROXY_INTEREST_CHECKSUM_MISMATCH")
	return C.success()
static func compute_checksum(value: Dictionary) -> String: return C.compute_checksum(value)
