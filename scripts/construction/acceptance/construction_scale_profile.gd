extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const P = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")

const SCHEMA := "construction.large_scale_profile.v1"
const FIELDS: Array[String] = [
	"schema", "profile_id", "seed", "construct_count", "parts_per_construct", "build_plan_count", "agent_count",
	"fabrication_job_count", "procurement_order_count", "shipment_count", "damage_event_count", "collapse_event_count", "repair_event_count", "warehouse_count",
	"server_count", "authority_migration_count", "reconnect_wave_count", "soak_ticks",
	"commands_per_tick", "presentation_budget", "simulation_budget", "summary_budget",
	"persistence_checkpoint_tick", "max_wall_time_ms", "expected_min_operations",
	"checksum",
]

static func create(profile_id: String, values: Dictionary) -> Dictionary:
	var profile := {
		"schema": SCHEMA,
		"profile_id": profile_id,
		"seed": int(values.get("seed", 210021)),
		"construct_count": int(values.get("construct_count", 20000)),
		"parts_per_construct": int(values.get("parts_per_construct", 64)),
		"build_plan_count": int(values.get("build_plan_count", 1000)),
		"agent_count": int(values.get("agent_count", 256)),
		"fabrication_job_count": int(values.get("fabrication_job_count", 3000)),
		"procurement_order_count": int(values.get("procurement_order_count", 4000)),
		"shipment_count": int(values.get("shipment_count", 4000)),
		"damage_event_count": int(values.get("damage_event_count", 2000)),
		"collapse_event_count": int(values.get("collapse_event_count", 500)),
		"repair_event_count": int(values.get("repair_event_count", 1500)),
		"warehouse_count": int(values.get("warehouse_count", 32)),
		"server_count": int(values.get("server_count", 16)),
		"authority_migration_count": int(values.get("authority_migration_count", 1000)),
		"reconnect_wave_count": int(values.get("reconnect_wave_count", 32)),
		"soak_ticks": int(values.get("soak_ticks", 4096)),
		"commands_per_tick": int(values.get("commands_per_tick", 32)),
		"presentation_budget": int(values.get("presentation_budget", 512)),
		"simulation_budget": int(values.get("simulation_budget", 4096)),
		"summary_budget": int(values.get("summary_budget", 12000)),
		"persistence_checkpoint_tick": int(values.get("persistence_checkpoint_tick", 2048)),
		"max_wall_time_ms": int(values.get("max_wall_time_ms", 120000)),
		"expected_min_operations": int(values.get("expected_min_operations", 100000)),
		"checksum": "",
	}
	profile.checksum = compute_checksum(profile)
	return profile

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("CONSTRUCTION_SCALE_PROFILE_SCHEMA_INVALID")
	if typeof(value.get("profile_id")) != TYPE_STRING or String(value.profile_id).is_empty():
		return _failure("CONSTRUCTION_SCALE_PROFILE_ID_INVALID")
	var integer_fields: Array[String] = [
		"seed", "construct_count", "parts_per_construct", "build_plan_count", "agent_count", "fabrication_job_count",
		"procurement_order_count", "shipment_count", "damage_event_count", "collapse_event_count", "repair_event_count", "warehouse_count", "server_count",
		"authority_migration_count", "reconnect_wave_count", "soak_ticks", "commands_per_tick",
		"presentation_budget", "simulation_budget", "summary_budget", "persistence_checkpoint_tick",
		"max_wall_time_ms", "expected_min_operations",
	]
	for field in integer_fields:
		if not Utils.is_json_integer(value.get(field)):
			return _failure("CONSTRUCTION_SCALE_PROFILE_FIELD_INVALID", {"field": field})
	if int(value.construct_count) < 1 or int(value.construct_count) > 1000000:
		return _failure("CONSTRUCTION_SCALE_PROFILE_CONSTRUCT_COUNT_INVALID")
	if int(value.parts_per_construct) < 1 or int(value.parts_per_construct) > 100000:
		return _failure("CONSTRUCTION_SCALE_PROFILE_PARTS_PER_CONSTRUCT_INVALID")
	if int(value.build_plan_count) < 1 or int(value.build_plan_count) > int(value.construct_count):
		return _failure("CONSTRUCTION_SCALE_PROFILE_BUILD_PLAN_COUNT_INVALID")
	if int(value.agent_count) < 1 or int(value.agent_count) > 100000:
		return _failure("CONSTRUCTION_SCALE_PROFILE_AGENT_COUNT_INVALID")
	if int(value.server_count) < 1 or int(value.server_count) > 4096:
		return _failure("CONSTRUCTION_SCALE_PROFILE_SERVER_COUNT_INVALID")
	if int(value.warehouse_count) < 1 or int(value.warehouse_count) > 100000:
		return _failure("CONSTRUCTION_SCALE_PROFILE_WAREHOUSE_COUNT_INVALID")
	if int(value.soak_ticks) < 1 or int(value.soak_ticks) > 10000000:
		return _failure("CONSTRUCTION_SCALE_PROFILE_SOAK_TICKS_INVALID")
	if int(value.commands_per_tick) < 1 or int(value.commands_per_tick) > 100000:
		return _failure("CONSTRUCTION_SCALE_PROFILE_COMMAND_RATE_INVALID")
	if int(value.presentation_budget) < 0 or int(value.simulation_budget) < int(value.presentation_budget):
		return _failure("CONSTRUCTION_SCALE_PROFILE_PRESENTATION_BUDGET_INVALID")
	if int(value.summary_budget) < int(value.simulation_budget) or int(value.summary_budget) > int(value.construct_count):
		return _failure("CONSTRUCTION_SCALE_PROFILE_SUMMARY_BUDGET_INVALID")
	if int(value.persistence_checkpoint_tick) < 0 or int(value.persistence_checkpoint_tick) > int(value.soak_ticks):
		return _failure("CONSTRUCTION_SCALE_PROFILE_CHECKPOINT_INVALID")
	for field in ["fabrication_job_count", "procurement_order_count", "shipment_count", "damage_event_count", "collapse_event_count", "repair_event_count", "authority_migration_count", "reconnect_wave_count", "max_wall_time_ms", "expected_min_operations"]:
		if int(value[field]) < 0:
			return _failure("CONSTRUCTION_SCALE_PROFILE_FIELD_NEGATIVE", {"field": field})
	if typeof(value.get("checksum")) != TYPE_STRING or String(value.checksum) != compute_checksum(value):
		return _failure("CONSTRUCTION_SCALE_PROFILE_CHECKSUM_MISMATCH")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload["checksum"] = ""
	return Utils.payload_hash(payload)

static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": ""}
	result.merge(details, true)
	return result

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
