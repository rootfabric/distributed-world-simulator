extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_streaming_budget_report.v1"
const TOTAL_FIELDS: Array[String] = ["summary_bytes", "simulation_units", "presentation_bytes"]
const FIELDS: Array[String] = ["schema", "tick", "budgets", "used", "presented_construct_ids", "simulated_construct_ids", "summary_construct_ids", "dormant_construct_ids", "evicted_construct_ids", "checksum"]

static func create(tick: int, budgets: Dictionary, used: Dictionary, levels: Dictionary, evicted: Array) -> Dictionary:
	var value := {"schema": SCHEMA, "tick": tick, "budgets": budgets.duplicate(true), "used": used.duplicate(true), "presented_construct_ids": _sorted(levels.get("PRESENTED", [])), "simulated_construct_ids": _sorted(levels.get("SIMULATED", [])), "summary_construct_ids": _sorted(levels.get("SUMMARY", [])), "dormant_construct_ids": _sorted(levels.get("DORMANT", [])), "evicted_construct_ids": _sorted(evicted), "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA or not Utils.is_json_integer(value.get("tick")) or int(value["tick"]) < 0: return _failure("INVALID_CONSTRUCTION_STREAMING_BUDGET_REPORT")
	for field in ["budgets", "used"]:
		if typeof(value.get(field)) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STREAMING_BUDGET_TOTALS")
		exact = Utils.validate_exact_fields(value[field], TOTAL_FIELDS); if not bool(exact.get("success", false)): return exact
		for total in TOTAL_FIELDS:
			if not Utils.is_json_integer(value[field].get(total)) or int(value[field][total]) < 0: return _failure("INVALID_CONSTRUCTION_STREAMING_BUDGET_TOTAL")
	for field in ["presented_construct_ids", "simulated_construct_ids", "summary_construct_ids", "dormant_construct_ids", "evicted_construct_ids"]:
		if typeof(value.get(field)) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_STREAMING_BUDGET_IDS")
		var sorted := Array(value[field]).duplicate(); sorted.sort(); if sorted != value[field]: return _failure("NON_CANONICAL_CONSTRUCTION_STREAMING_BUDGET_IDS")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_STREAMING_BUDGET_REPORT_CHECKSUM_MISMATCH")
	return _success()

static func compute_checksum(value: Dictionary) -> String: var payload := value.duplicate(true); payload["checksum"] = ""; return Utils.payload_hash(payload)
static func _sorted(values) -> Array: var result := Array(values).duplicate(); result.sort(); return result
static func _success() -> Dictionary: return {"success": true, "error_code": "", "message": ""}
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}
