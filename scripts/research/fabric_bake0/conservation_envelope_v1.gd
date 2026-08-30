extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_conservation_envelope.v1"
const FIELDS: Array[String] = [
	"schema", "power_balance_error_max", "energy_creation_max",
	"linear_momentum_drift_max", "angular_momentum_drift_max",
	"matter_balance_error_max", "checksum",
]

static func create(
	power_balance_error_max: float, energy_creation_max: float,
	linear_momentum_drift_max: float, angular_momentum_drift_max: float,
	matter_balance_error_max: float
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"power_balance_error_max": power_balance_error_max,
		"energy_creation_max": energy_creation_max,
		"linear_momentum_drift_max": linear_momentum_drift_max,
		"angular_momentum_drift_max": angular_momentum_drift_max,
		"matter_balance_error_max": matter_balance_error_max,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_CONSERVATION_ENVELOPE_SCHEMA")
	for field in [
		"power_balance_error_max", "energy_creation_max", "linear_momentum_drift_max",
		"angular_momentum_drift_max", "matter_balance_error_max",
	]:
		if not Utils.is_non_negative_number(value.get(field)):
			return Utils.failure("INVALID_CONSERVATION_ENVELOPE_BOUND", {"field": field})
	return Utils.validate_checksum(value)
