extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ContractUtils = preload("res://scripts/construction/utilities/construction_utility_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_machine_utility_lease.v1"
const FIELDS: Array[String] = ["schema", "lease_id", "machine_construct_id", "job_id", "machine_profile_checksum", "recipe_checksum", "tick", "status", "max_work_units", "requirements", "profile_checksums", "allocation_checksums", "checksum"]
const REQUIREMENT_FIELDS: Array[String] = ["utility_kind", "network_id", "demand_id", "units_per_work_unit", "minimum_ratio"]
const STATUSES: Array[String] = ["ONLINE", "DEGRADED", "OFFLINE"]

static func create(lease_id: String, machine_construct_id: String, job_id: String, machine_profile_checksum: String, recipe_checksum: String, tick: int, status: String, max_work_units: int, requirements: Array, profile_checksums: Dictionary, allocation_checksums: Dictionary) -> Dictionary:
	var rows := requirements.duplicate(true); rows.sort_custom(func(a,b):
		var ak := "%s|%s|%s" % [String(a.get("utility_kind", "")), String(a.get("network_id", "")), String(a.get("demand_id", ""))]
		var bk := "%s|%s|%s" % [String(b.get("utility_kind", "")), String(b.get("network_id", "")), String(b.get("demand_id", ""))]
		return ak < bk)
	var value := {"schema": SCHEMA, "lease_id": lease_id, "machine_construct_id": machine_construct_id, "job_id": job_id, "machine_profile_checksum": machine_profile_checksum, "recipe_checksum": recipe_checksum, "tick": tick, "status": status, "max_work_units": max_work_units, "requirements": rows, "profile_checksums": profile_checksums.duplicate(true), "allocation_checksums": allocation_checksums.duplicate(true), "checksum": ""}; value["checksum"] = compute_checksum(value); return value
static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA or not ContractUtils.is_path(String(value.get("lease_id", "")), "utility-lease/") or not ContractUtils.is_path(String(value.get("machine_construct_id", "")), "construct/") or not ContractUtils.is_path(String(value.get("job_id", "")), "fabrication-job/"): return ContractUtils.failure("INVALID_CONSTRUCTION_MACHINE_UTILITY_LEASE_IDENTITY")
	for field in ["machine_profile_checksum", "recipe_checksum"]:
		if typeof(value.get(field)) != TYPE_STRING or String(value[field]).length() != 64: return ContractUtils.failure("INVALID_CONSTRUCTION_MACHINE_UTILITY_LEASE_REFERENCE")
	if not UtilsScript.is_json_integer(value.get("tick")) or int(value["tick"]) < 0 or not UtilsScript.is_json_integer(value.get("max_work_units")) or int(value["max_work_units"]) < 0 or not STATUSES.has(String(value.get("status", ""))): return ContractUtils.failure("INVALID_CONSTRUCTION_MACHINE_UTILITY_LEASE_STATE")
	if typeof(value.get("requirements")) != TYPE_ARRAY or Array(value["requirements"]).is_empty() or typeof(value.get("profile_checksums")) != TYPE_DICTIONARY or typeof(value.get("allocation_checksums")) != TYPE_DICTIONARY: return ContractUtils.failure("INVALID_CONSTRUCTION_MACHINE_UTILITY_LEASE_COLLECTION")
	var previous := ""; var kinds := {}
	for row in value["requirements"]:
		if typeof(row) != TYPE_DICTIONARY: return ContractUtils.failure("INVALID_CONSTRUCTION_MACHINE_UTILITY_REQUIREMENT")
		var row_exact := UtilsScript.validate_exact_fields(row, REQUIREMENT_FIELDS); if not bool(row_exact.get("success", false)): return row_exact
		var kind := String(row.get("utility_kind", "")); var network_id := String(row.get("network_id", "")); var demand_id := String(row.get("demand_id", "")); var key := "%s|%s|%s" % [kind, network_id, demand_id]
		if not ContractUtils.VALID_KINDS.has(kind) or not ContractUtils.is_path(network_id, "utility-network/") or not ContractUtils.is_path(demand_id, "utility-demand/") or kinds.has(kind) or (not previous.is_empty() and key < previous): return ContractUtils.failure("NON_CANONICAL_CONSTRUCTION_MACHINE_UTILITY_REQUIREMENTS")
		if not ContractUtils.positive(row.get("units_per_work_unit")) or not ContractUtils.ratio(row.get("minimum_ratio"), false): return ContractUtils.failure("INVALID_CONSTRUCTION_MACHINE_UTILITY_REQUIREMENT_QUANTITY")
		if String(value["profile_checksums"].get(network_id, "")).length() != 64 or String(value["allocation_checksums"].get(demand_id, "")).length() != 64: return ContractUtils.failure("CONSTRUCTION_MACHINE_UTILITY_LEASE_PIN_MISSING")
		kinds[kind] = true; previous = key
	if value["profile_checksums"].size() != value["requirements"].size() or value["allocation_checksums"].size() != value["requirements"].size(): return ContractUtils.failure("CONSTRUCTION_MACHINE_UTILITY_LEASE_PIN_MISMATCH")
	if String(value["status"]) == "OFFLINE" and int(value["max_work_units"]) != 0: return ContractUtils.failure("OFFLINE_CONSTRUCTION_MACHINE_UTILITY_LEASE_HAS_WORK")
	if String(value["status"]) != "OFFLINE" and int(value["max_work_units"]) < 1: return ContractUtils.failure("ONLINE_CONSTRUCTION_MACHINE_UTILITY_LEASE_HAS_NO_WORK")
	if not bool(UtilsScript.canonicalize(value["profile_checksums"]).get("success", false)) or not bool(UtilsScript.canonicalize(value["allocation_checksums"]).get("success", false)): return ContractUtils.failure("CONSTRUCTION_MACHINE_UTILITY_LEASE_NOT_JSON_SAFE")
	if String(value.get("checksum", "")) != compute_checksum(value): return ContractUtils.failure("CONSTRUCTION_MACHINE_UTILITY_LEASE_CHECKSUM_MISMATCH")
	return ContractUtils.success()
static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
