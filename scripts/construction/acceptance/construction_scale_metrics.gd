extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "construction.large_scale_metrics.v1"
const FIELDS: Array[String] = [
	"schema", "ticks_completed", "operations_attempted", "operations_committed", "exact_replays",
	"operation_conflicts", "duplicate_commits", "build_plans_created", "build_plans_completed",
	"constructs_registered", "item_backed_parts_modeled", "fabrication_jobs_completed", "procurement_orders_completed",
	"shipments_delivered", "damage_events_applied", "collapse_events_completed", "repair_events_completed", "authority_migrations_completed", "stale_epoch_rejections",
	"reconnect_waves_completed", "agent_goals_completed", "lost_item_identities", "material_balance_delta",
	"max_presented", "max_simulated", "max_summarized", "max_queue_depth", "wall_time_ms",
	"checkpoint_count", "checksum",
]

static func create() -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"ticks_completed": 0,
		"operations_attempted": 0,
		"operations_committed": 0,
		"exact_replays": 0,
		"operation_conflicts": 0,
		"duplicate_commits": 0,
		"build_plans_created": 0,
		"build_plans_completed": 0,
		"constructs_registered": 0,
		"item_backed_parts_modeled": 0,
		"fabrication_jobs_completed": 0,
		"procurement_orders_completed": 0,
		"shipments_delivered": 0,
		"damage_events_applied": 0,
		"collapse_events_completed": 0,
		"repair_events_completed": 0,
		"authority_migrations_completed": 0,
		"stale_epoch_rejections": 0,
		"reconnect_waves_completed": 0,
		"agent_goals_completed": 0,
		"lost_item_identities": 0,
		"material_balance_delta": 0,
		"max_presented": 0,
		"max_simulated": 0,
		"max_summarized": 0,
		"max_queue_depth": 0,
		"wall_time_ms": 0,
		"checkpoint_count": 0,
		"checksum": "",
	}
	value.checksum = compute_checksum(value)
	return value

static func seal(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	result["checksum"] = compute_checksum(result)
	return result

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("CONSTRUCTION_SCALE_METRICS_SCHEMA_INVALID")
	for field in FIELDS:
		if field in ["schema", "checksum"]:
			continue
		if not Utils.is_json_integer(value.get(field)) or int(value[field]) < 0:
			return _failure("CONSTRUCTION_SCALE_METRICS_FIELD_INVALID", {"field": field})
	if String(value.get("checksum", "")) != compute_checksum(value):
		return _failure("CONSTRUCTION_SCALE_METRICS_CHECKSUM_MISMATCH")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload["checksum"] = ""
	return Utils.payload_hash(payload)

static func _success() -> Dictionary:
	return {"success": true, "error_code": "", "message": ""}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
