extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_motor_generator_interface.v1"
const STATE_OWNER := "CALLER_CANONICAL_OWNER"
const SIGN_CONVENTION := "CURRENT_POSITIVE_MOTOR_TORQUE__EXTERNAL_TORQUE_POSITIVE_INTO_ROTOR"
const FIELDS: Array[String] = [
	"schema", "input_quantities", "output_quantities", "state_quantities",
	"state_owner", "sign_convention", "interface_hash", "checksum",
]

static func create() -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"input_quantities": ["CURRENT_A", "DT_S", "EXTERNAL_SHAFT_TORQUE_NM"],
		"output_quantities": [
			"ELECTRICAL_ENERGY_J", "ELECTROMAGNETIC_MECHANICAL_ENERGY_J",
			"ELECTROMAGNETIC_TORQUE_NM", "KINETIC_ENERGY_DELTA_J",
			"RESISTIVE_HEAT_J", "SHAFT_BOUNDARY_ENERGY_J", "TERMINAL_VOLTAGE_V",
		],
		"state_quantities": ["ANGULAR_VELOCITY_RAD_S"],
		"state_owner": STATE_OWNER,
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
		return U.failure("UNSUPPORTED_MOTOR_GENERATOR_INTERFACE_SCHEMA")
	for field in ["input_quantities", "output_quantities", "state_quantities"]:
		checked = U.validate_sorted_unique_strings(value.get(field), false, true)
		if not checked.success:
			return U.failure("INVALID_MOTOR_GENERATOR_INTERFACE_QUANTITIES", {"field": field})
	if value.get("state_owner") != STATE_OWNER or value.get("sign_convention") != SIGN_CONVENTION:
		return U.failure("UNSUPPORTED_MOTOR_GENERATOR_INTERFACE_SEMANTICS")
	if not U.is_lower_hex_64(value.get("interface_hash")) or String(value.interface_hash) != U.canonical_hash(_identity(value)):
		return U.failure("MOTOR_GENERATOR_INTERFACE_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity(value: Dictionary) -> Dictionary:
	return {
		"input_quantities": value.input_quantities,
		"output_quantities": value.output_quantities,
		"state_quantities": value.state_quantities,
		"state_owner": value.state_owner,
		"sign_convention": value.sign_convention,
	}
