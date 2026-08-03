extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Profile = preload("res://scripts/construction/acceptance/construction_scale_profile.gd")
const Metrics = preload("res://scripts/construction/acceptance/construction_scale_metrics.gd")

const SCHEMA := "construction.large_scale_report.v1"
const FIELDS: Array[String] = [
	"schema", "report_id", "profile", "status", "metrics", "invariant_failures", "state_checksum",
	"determinism_checksum", "generated_at_tick", "checksum",
]

static func create(report_id: String, profile: Dictionary, status: String, metrics: Dictionary, invariant_failures: Array, state_checksum: String, determinism_checksum: String, generated_at_tick: int) -> Dictionary:
	var report := {
		"schema": SCHEMA,
		"report_id": report_id,
		"profile": profile.duplicate(true),
		"status": status,
		"metrics": Metrics.seal(metrics),
		"invariant_failures": invariant_failures.duplicate(true),
		"state_checksum": state_checksum,
		"determinism_checksum": determinism_checksum,
		"generated_at_tick": generated_at_tick,
		"checksum": "",
	}
	report.checksum = compute_checksum(report)
	return report

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("CONSTRUCTION_SCALE_REPORT_SCHEMA_INVALID")
	if typeof(value.get("report_id")) != TYPE_STRING or String(value.report_id).is_empty():
		return _failure("CONSTRUCTION_SCALE_REPORT_ID_INVALID")
	var pv := Profile.validate(Dictionary(value.get("profile", {})))
	if not bool(pv.get("success", false)):
		return _failure("CONSTRUCTION_SCALE_REPORT_PROFILE_INVALID", {"cause": pv})
	var mv := Metrics.validate(Dictionary(value.get("metrics", {})))
	if not bool(mv.get("success", false)):
		return _failure("CONSTRUCTION_SCALE_REPORT_METRICS_INVALID", {"cause": mv})
	if String(value.get("status", "")) not in ["PASS", "FAIL"]:
		return _failure("CONSTRUCTION_SCALE_REPORT_STATUS_INVALID")
	if typeof(value.get("invariant_failures")) != TYPE_ARRAY:
		return _failure("CONSTRUCTION_SCALE_REPORT_FAILURES_INVALID")
	for failure in value.invariant_failures:
		if typeof(failure) != TYPE_STRING or String(failure).is_empty():
			return _failure("CONSTRUCTION_SCALE_REPORT_FAILURE_INVALID")
	for field in ["state_checksum", "determinism_checksum", "checksum"]:
		if typeof(value.get(field)) != TYPE_STRING or String(value[field]).is_empty():
			return _failure("CONSTRUCTION_SCALE_REPORT_CHECKSUM_FIELD_INVALID", {"field": field})
	if not Utils.is_json_integer(value.get("generated_at_tick")) or int(value.generated_at_tick) < 0:
		return _failure("CONSTRUCTION_SCALE_REPORT_TICK_INVALID")
	if String(value.checksum) != compute_checksum(value):
		return _failure("CONSTRUCTION_SCALE_REPORT_CHECKSUM_MISMATCH")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload["checksum"] = ""
	return Utils.payload_hash(payload)

static func _success() -> Dictionary:
	return {"success": true, "error_code": "", "message": ""}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
