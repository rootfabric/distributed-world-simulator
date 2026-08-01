extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_structural_load_path.v1"
const FIELDS: Array[String] = ["schema", "load_path_id", "source_part_id", "support_part_id", "part_ids", "bond_ids", "load_n", "checksum"]

static func create(load_path_id: String, source_part_id: String, support_part_id: String, part_ids: Array, bond_ids: Array, load_n: float) -> Dictionary:
	var value := {"schema": SCHEMA, "load_path_id": load_path_id, "source_part_id": source_part_id, "support_part_id": support_part_id, "part_ids": part_ids.duplicate(), "bond_ids": bond_ids.duplicate(), "load_n": load_n, "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_STRUCTURAL_LOAD_PATH_SCHEMA")
	if not String(value.get("load_path_id", "")).begins_with("load-path/"): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_LOAD_PATH_ID")
	if not String(value.get("source_part_id", "")).begins_with("part/") or not String(value.get("support_part_id", "")).begins_with("part/"): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_LOAD_PATH_ENDPOINT")
	if typeof(value.get("part_ids")) != TYPE_ARRAY or Array(value["part_ids"]).size() < 2: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_LOAD_PATH_PARTS")
	if typeof(value.get("bond_ids")) != TYPE_ARRAY or Array(value["bond_ids"]).size() != Array(value["part_ids"]).size() - 1: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_LOAD_PATH_BONDS")
	if String(value["part_ids"][0]) != String(value["source_part_id"]) or String(value["part_ids"][-1]) != String(value["support_part_id"]): return _failure("CONSTRUCTION_STRUCTURAL_LOAD_PATH_ENDPOINT_MISMATCH")
	var seen_parts := {}; for part_id in value["part_ids"]:
		if typeof(part_id) != TYPE_STRING or not String(part_id).begins_with("part/") or seen_parts.has(part_id): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_LOAD_PATH_PART")
		seen_parts[part_id] = true
	var seen_bonds := {}; for bond_id in value["bond_ids"]:
		if typeof(bond_id) != TYPE_STRING or not String(bond_id).begins_with("bond/") or seen_bonds.has(bond_id): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_LOAD_PATH_BOND")
		seen_bonds[bond_id] = true
	if not _positive(value.get("load_n")): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_LOAD_PATH_LOAD")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_STRUCTURAL_LOAD_PATH_CHECKSUM_MISMATCH")
	return UtilsScript.validation_success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _positive(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and not is_nan(float(value)) and not is_inf(float(value)) and float(value) > 0.0
static func _failure(code: String) -> Dictionary: return UtilsScript.validation_failure(code, code)
