extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_power_stage_interface.v1"
const SIGN_CONVENTION := "BUS_CURRENT_POSITIVE_SOURCE_TO_STAGE__LOAD_CURRENT_POSITIVE_STAGE_TO_LOAD__DUTY_SIGN_SETS_OUTPUT_POLARITY"
const FIELDS: Array[String] = [
	"schema", "input_quantities", "output_quantities", "state_quantities",
	"sign_convention", "interface_hash", "checksum",
]

static func create() -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"input_quantities": ["BUS_VOLTAGE_V", "DT_S", "DUTY_RATIO", "JUNCTION_TEMPERATURE_K", "LOAD_CURRENT_A", "PWM_FREQUENCY_HZ"],
		"output_quantities": ["BUS_CURRENT_A", "CONDUCTION_HEAT_J", "ELECTRICAL_INPUT_ENERGY_J", "ELECTRICAL_OUTPUT_ENERGY_J", "ENERGY_RESIDUAL_J", "LOAD_VOLTAGE_V", "SWITCHING_HEAT_J"],
		"state_quantities": [],
		"sign_convention": SIGN_CONVENTION,
		"interface_hash": "",
		"checksum": "",
	}
	value.interface_hash = U.canonical_hash(_identity(value))
	value.checksum = U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA:
		return U.failure("UNSUPPORTED_POWER_STAGE_INTERFACE_SCHEMA")
	checked = U.validate_sorted_unique_strings(value.get("input_quantities"), false, true)
	if not checked.success:
		return U.failure("INVALID_POWER_STAGE_INTERFACE_INPUTS")
	checked = U.validate_sorted_unique_strings(value.get("output_quantities"), false, true)
	if not checked.success:
		return U.failure("INVALID_POWER_STAGE_INTERFACE_OUTPUTS")
	checked = U.validate_sorted_unique_strings(value.get("state_quantities"), true, true)
	if not checked.success:
		return U.failure("INVALID_POWER_STAGE_INTERFACE_STATE")
	if value.get("sign_convention") != SIGN_CONVENTION:
		return U.failure("UNSUPPORTED_POWER_STAGE_INTERFACE_SEMANTICS")
	if not U.is_lower_hex_64(value.get("interface_hash")) or String(value.interface_hash) != U.canonical_hash(_identity(value)):
		return U.failure("POWER_STAGE_INTERFACE_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity(value: Dictionary) -> Dictionary:
	return {
		"input_quantities": value.input_quantities,
		"output_quantities": value.output_quantities,
		"state_quantities": value.state_quantities,
		"sign_convention": value.sign_convention,
	}
