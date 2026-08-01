extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_catch_up_plan.v1"
const STEP_FIELDS: Array[String] = ["tick", "elapsed_ticks"]
const FIELDS: Array[String] = ["schema", "construct_id", "from_tick", "to_tick", "interval_ticks", "steps", "truncated", "checksum"]

static func compile(construct_id: String, from_tick: int, to_tick: int, interval_ticks: int, maximum_steps: int) -> Dictionary:
	if not construct_id.begins_with("construct/") or from_tick < 0 or to_tick < from_tick or interval_ticks < 1 or maximum_steps < 1: return _failure("INVALID_CONSTRUCTION_CATCH_UP_INPUT")
	var steps: Array = []; var cursor := from_tick + interval_ticks
	while cursor <= to_tick and steps.size() < maximum_steps:
		steps.append({"tick": cursor, "elapsed_ticks": interval_ticks}); cursor += interval_ticks
	var value := {"schema": SCHEMA, "construct_id": construct_id, "from_tick": from_tick, "to_tick": to_tick, "interval_ticks": interval_ticks, "steps": steps, "truncated": cursor <= to_tick, "checksum": ""}
	value["checksum"] = compute_checksum(value); return {"success": true, "error_code": "", "message": "", "plan": value}

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA or not String(value.get("construct_id", "")).begins_with("construct/"): return _failure("INVALID_CONSTRUCTION_CATCH_UP_IDENTITY")
	for field in ["from_tick", "to_tick", "interval_ticks"]:
		if not Utils.is_json_integer(value.get(field)) or int(value[field]) < 0: return _failure("INVALID_CONSTRUCTION_CATCH_UP_TICK")
	if int(value["to_tick"]) < int(value["from_tick"]) or int(value["interval_ticks"]) < 1: return _failure("INVALID_CONSTRUCTION_CATCH_UP_RANGE")
	if typeof(value.get("steps")) != TYPE_ARRAY or typeof(value.get("truncated")) != TYPE_BOOL: return _failure("INVALID_CONSTRUCTION_CATCH_UP_STEPS")
	var previous := int(value["from_tick"])
	for step in value["steps"]:
		if typeof(step) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_CATCH_UP_STEP")
		exact = Utils.validate_exact_fields(step, STEP_FIELDS); if not bool(exact.get("success", false)): return exact
		if not Utils.is_json_integer(step.get("tick")) or not Utils.is_json_integer(step.get("elapsed_ticks")): return _failure("INVALID_CONSTRUCTION_CATCH_UP_STEP")
		if int(step["tick"]) <= previous or int(step["elapsed_ticks"]) < 1 or int(step["tick"]) > int(value["to_tick"]): return _failure("INVALID_CONSTRUCTION_CATCH_UP_STEP")
		if int(step["tick"]) - previous != int(step["elapsed_ticks"]): return _failure("NON_CANONICAL_CONSTRUCTION_CATCH_UP_STEP")
		previous = int(step["tick"])
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_CATCH_UP_PLAN_CHECKSUM_MISMATCH")
	return _success()

static func compute_checksum(value: Dictionary) -> String: var payload := value.duplicate(true); payload["checksum"] = ""; return Utils.payload_hash(payload)
static func _success() -> Dictionary: return {"success": true, "error_code": "", "message": ""}
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}
