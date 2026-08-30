extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_error_envelope.v1"
const FIELDS: Array[String] = [
	"schema", "effort_abs", "effort_rel", "flow_abs", "flow_rel",
	"power_abs", "power_rel", "motion_abs", "motion_rel",
	"energy_drift", "momentum_drift", "event_time_error",
	"time_horizon_s", "event_order_strict", "checksum",
]

static func create(
	effort_abs: float, effort_rel: float, flow_abs: float, flow_rel: float,
	power_abs: float, power_rel: float, motion_abs: float, motion_rel: float,
	energy_drift: float, momentum_drift: float, event_time_error: float,
	time_horizon_s: float, event_order_strict: bool = true
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"effort_abs": effort_abs,
		"effort_rel": effort_rel,
		"flow_abs": flow_abs,
		"flow_rel": flow_rel,
		"power_abs": power_abs,
		"power_rel": power_rel,
		"motion_abs": motion_abs,
		"motion_rel": motion_rel,
		"energy_drift": energy_drift,
		"momentum_drift": momentum_drift,
		"event_time_error": event_time_error,
		"time_horizon_s": time_horizon_s,
		"event_order_strict": event_order_strict,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_ERROR_ENVELOPE_SCHEMA")
	for field in [
		"effort_abs", "effort_rel", "flow_abs", "flow_rel", "power_abs", "power_rel",
		"motion_abs", "motion_rel", "energy_drift", "momentum_drift", "event_time_error",
	]:
		if not Utils.is_non_negative_number(value.get(field)):
			return Utils.failure("INVALID_ERROR_ENVELOPE_BOUND", {"field": field})
	if not Utils.is_positive_number(value.get("time_horizon_s")):
		return Utils.failure("INVALID_ERROR_ENVELOPE_HORIZON")
	if typeof(value.get("event_order_strict")) != TYPE_BOOL:
		return Utils.failure("INVALID_ERROR_ENVELOPE_EVENT_ORDER")
	return Utils.validate_checksum(value)
