extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const ErrorEnvelope = preload("res://scripts/research/fabric_bake0/error_envelope_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_runtime_error_estimator.v1"
const FIELDS: Array[String] = [
	"schema", "estimator_id", "effort_error_bound", "flow_error_bound",
	"power_error_bound", "motion_error_bound", "energy_drift_bound",
	"momentum_drift_bound", "remaining_validity_margin", "guard_margin",
	"estimated_horizon_s", "checksum",
]

static func create(
	estimator_id: String, effort_error_bound: float, flow_error_bound: float,
	power_error_bound: float, motion_error_bound: float, energy_drift_bound: float,
	momentum_drift_bound: float, remaining_validity_margin: float,
	guard_margin: float, estimated_horizon_s: float
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"estimator_id": estimator_id,
		"effort_error_bound": effort_error_bound,
		"flow_error_bound": flow_error_bound,
		"power_error_bound": power_error_bound,
		"motion_error_bound": motion_error_bound,
		"energy_drift_bound": energy_drift_bound,
		"momentum_drift_bound": momentum_drift_bound,
		"remaining_validity_margin": remaining_validity_margin,
		"guard_margin": guard_margin,
		"estimated_horizon_s": estimated_horizon_s,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_RUNTIME_ERROR_ESTIMATOR_SCHEMA")
	if not Utils.is_canonical_id(value.get("estimator_id"), 2):
		return Utils.failure("INVALID_RUNTIME_ERROR_ESTIMATOR_ID")
	for field in [
		"effort_error_bound", "flow_error_bound", "power_error_bound", "motion_error_bound",
		"energy_drift_bound", "momentum_drift_bound", "remaining_validity_margin",
		"guard_margin", "estimated_horizon_s",
	]:
		if not Utils.is_non_negative_number(value.get(field)):
			return Utils.failure("INVALID_RUNTIME_ERROR_ESTIMATOR_BOUND", {"field": field})
	return Utils.validate_checksum(value)

static func validate_against(value: Dictionary, envelope: Dictionary) -> Dictionary:
	var checked := validate(value)
	if not bool(checked.get("success", false)):
		return checked
	checked = ErrorEnvelope.validate(envelope)
	if not bool(checked.get("success", false)):
		return checked
	var pairs := [
		["effort_error_bound", "effort_abs"],
		["flow_error_bound", "flow_abs"],
		["power_error_bound", "power_abs"],
		["motion_error_bound", "motion_abs"],
		["energy_drift_bound", "energy_drift"],
		["momentum_drift_bound", "momentum_drift"],
	]
	for pair in pairs:
		if float(value[pair[0]]) > float(envelope[pair[1]]):
			return Utils.failure("BAKE_RUNTIME_ERROR_BOUND_EXCEEDED", {"field": pair[0]})
	if float(value["estimated_horizon_s"]) > float(envelope["time_horizon_s"]):
		return Utils.failure("BAKE_RUNTIME_ERROR_HORIZON_EXCEEDED")
	return Utils.success()
