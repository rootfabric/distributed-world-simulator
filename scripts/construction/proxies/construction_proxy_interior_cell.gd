extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_proxy_interior_cell.v1"
const FIELDS: Array[String] = ["schema", "cell_id", "bounds_min_m", "bounds_max_m", "interactive_part_ids", "checksum"]

static func create(cell_id: String, bounds_min_m: Array, bounds_max_m: Array, interactive_part_ids: Array = []) -> Dictionary:
	var value := {"schema": SCHEMA, "cell_id": cell_id, "bounds_min_m": bounds_min_m.duplicate(true), "bounds_max_m": bounds_max_m.duplicate(true), "interactive_part_ids": C.sorted_strings(interactive_part_ids), "checksum": ""}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA or not C.path_id(String(value.get("cell_id", "")), "interior-cell/"): return C.failure("INVALID_CONSTRUCTION_PROXY_INTERIOR_CELL_IDENTITY")
	if not C.finite_vector(value.get("bounds_min_m"), 3) or not C.finite_vector(value.get("bounds_max_m"), 3): return C.failure("INVALID_CONSTRUCTION_PROXY_INTERIOR_CELL_BOUNDS")
	for index in range(3):
		if float(value["bounds_max_m"][index]) <= float(value["bounds_min_m"][index]): return C.failure("INVALID_CONSTRUCTION_PROXY_INTERIOR_CELL_BOUNDS")
	if not C.sorted_unique_strings(value.get("interactive_part_ids"), "part/"): return C.failure("INVALID_CONSTRUCTION_PROXY_INTERIOR_CELL_PARTS")
	if String(value.get("checksum", "")) != compute_checksum(value): return C.failure("CONSTRUCTION_PROXY_INTERIOR_CELL_CHECKSUM_MISMATCH")
	return C.success()

static func compute_checksum(value: Dictionary) -> String: return C.compute_checksum(value)
