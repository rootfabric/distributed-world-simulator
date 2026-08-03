extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Level = preload("res://scripts/construction/streaming/construction_activity_level.gd")
const Request = preload("res://scripts/construction/streaming/construction_streaming_request.gd")
const Lod = preload("res://scripts/construction/streaming/construction_lod_profile.gd")
const COST_FIELDS: Array[String] = ["summary_bytes", "simulation_units", "presentation_bytes"]
const SCHEMA := "planet_simulator.construction_activity_record.v1"
const FIELDS: Array[String] = ["schema", "construct_id", "authority_epoch", "source_revision", "source_checksum", "requested_level", "effective_level", "minimum_level", "authority_mode", "lod_tier", "last_transition_tick", "last_interest_tick", "outside_summary_since_tick", "last_simulated_tick", "next_due_tick", "interest_score", "estimated_costs", "summary_checksum", "runtime_descriptor_checksum", "simulation_checksum", "pending_job_ids", "pending_operation_ids", "eviction_reasons", "generation", "checksum"]

static func create(request: Dictionary, tick: int = 0) -> Dictionary:
	var snapshot: Dictionary = request["construct_snapshot"]
	var value := {"schema": SCHEMA, "construct_id": String(request["construct_id"]), "authority_epoch": int(request["authority_epoch"]), "source_revision": int(snapshot["state_revision"]), "source_checksum": String(snapshot["checksum"]), "requested_level": String(request["minimum_level"]), "effective_level": Level.DORMANT, "minimum_level": String(request["minimum_level"]), "authority_mode": String(request["authority_mode"]), "lod_tier": Lod.NONE, "last_transition_tick": tick, "last_interest_tick": tick, "outside_summary_since_tick": -1, "last_simulated_tick": tick, "next_due_tick": tick, "interest_score": 0, "estimated_costs": request["estimated_costs"].duplicate(true), "summary_checksum": "", "runtime_descriptor_checksum": "", "simulation_checksum": "", "pending_job_ids": request["pending_job_ids"].duplicate(true), "pending_operation_ids": request["pending_operation_ids"].duplicate(true), "eviction_reasons": [], "generation": 0, "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func with_updates(value: Dictionary, updates: Dictionary) -> Dictionary:
	var next := value.duplicate(true)
	for key in updates: next[key] = updates[key]
	next["checksum"] = compute_checksum(next); return next

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA or not String(value.get("construct_id", "")).begins_with("construct/"): return _failure("INVALID_CONSTRUCTION_ACTIVITY_RECORD_IDENTITY")
	for field in ["authority_epoch", "source_revision", "last_transition_tick", "last_interest_tick", "last_simulated_tick", "next_due_tick", "interest_score", "generation"]:
		if not Utils.is_json_integer(value.get(field)) or int(value[field]) < 0: return _failure("INVALID_CONSTRUCTION_ACTIVITY_RECORD_INTEGER")
	if not Utils.is_json_integer(value.get("outside_summary_since_tick")) or int(value["outside_summary_since_tick"]) < -1: return _failure("INVALID_CONSTRUCTION_ACTIVITY_RECORD_OUTSIDE_TICK")
	if int(value["authority_epoch"]) < 1 or String(value.get("source_checksum", "")).length() != 64: return _failure("INVALID_CONSTRUCTION_ACTIVITY_RECORD_SOURCE")
	for field in ["requested_level", "effective_level", "minimum_level"]:
		if not Level.is_valid(value.get(field)): return _failure("INVALID_CONSTRUCTION_ACTIVITY_RECORD_LEVEL")
	if not Request.AUTHORITY_MODES.has(String(value.get("authority_mode", ""))): return _failure("INVALID_CONSTRUCTION_ACTIVITY_AUTHORITY_MODE")
	if not Lod.TIERS.has(String(value.get("lod_tier", ""))): return _failure("INVALID_CONSTRUCTION_ACTIVITY_LOD_TIER")
	if typeof(value.get("estimated_costs")) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_ACTIVITY_COSTS")
	exact = Utils.validate_exact_fields(value["estimated_costs"], COST_FIELDS); if not bool(exact.get("success", false)): return exact
	for field in COST_FIELDS:
		if not Utils.is_json_integer(value["estimated_costs"].get(field)) or int(value["estimated_costs"][field]) < 0: return _failure("INVALID_CONSTRUCTION_ACTIVITY_COST")
	for field in ["summary_checksum", "runtime_descriptor_checksum", "simulation_checksum"]:
		var checksum := String(value.get(field, "")); if not checksum.is_empty() and checksum.length() != 64: return _failure("INVALID_CONSTRUCTION_ACTIVITY_DERIVED_CHECKSUM")
	for field in ["pending_job_ids", "pending_operation_ids", "eviction_reasons"]:
		if typeof(value.get(field)) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_ACTIVITY_COLLECTION")
		var sorted := Array(value[field]).duplicate(); sorted.sort(); if sorted != value[field]: return _failure("NON_CANONICAL_CONSTRUCTION_ACTIVITY_COLLECTION")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_ACTIVITY_RECORD_CHECKSUM_MISMATCH")
	return _success()

static func compute_checksum(value: Dictionary) -> String: var payload := value.duplicate(true); payload["checksum"] = ""; return Utils.payload_hash(payload)
static func _success() -> Dictionary: return {"success": true, "error_code": "", "message": ""}
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}
