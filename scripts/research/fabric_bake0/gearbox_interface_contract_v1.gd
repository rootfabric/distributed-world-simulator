extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_gearbox_interface.v1"
const SIGN_CONVENTION := "SIGNED_SHAFT_OMEGA_AND_TORQUE__POWER_EQUALS_TORQUE_TIMES_OMEGA"
const FIELDS: Array[String] = [
	"schema", "input_quantities", "output_quantities", "state_quantities",
	"sign_convention", "interface_hash", "checksum",
]

static func create() -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"input_quantities": ["DT_S", "INPUT_ANGULAR_VELOCITY_RAD_S", "INPUT_TORQUE_NM"],
		"output_quantities": ["ENERGY_RESIDUAL_J", "EQUIVALENT_INPUT_INERTIA_KG_M2", "INPUT_MECHANICAL_ENERGY_J", "OUTPUT_ANGULAR_VELOCITY_RAD_S", "OUTPUT_MECHANICAL_ENERGY_J", "OUTPUT_TORQUE_NM"],
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
		return U.failure("UNSUPPORTED_GEARBOX_INTERFACE_SCHEMA")
	checked = U.validate_sorted_unique_strings(value.get("input_quantities"), false, true)
	if not checked.success:
		return U.failure("INVALID_GEARBOX_INTERFACE_INPUTS")
	checked = U.validate_sorted_unique_strings(value.get("output_quantities"), false, true)
	if not checked.success:
		return U.failure("INVALID_GEARBOX_INTERFACE_OUTPUTS")
	checked = U.validate_sorted_unique_strings(value.get("state_quantities"), true, true)
	if not checked.success:
		return U.failure("INVALID_GEARBOX_INTERFACE_STATE")
	if value.get("sign_convention") != SIGN_CONVENTION:
		return U.failure("UNSUPPORTED_GEARBOX_INTERFACE_SEMANTICS")
	if not U.is_lower_hex_64(value.get("interface_hash")) or String(value.interface_hash) != U.canonical_hash(_identity(value)):
		return U.failure("GEARBOX_INTERFACE_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity(value: Dictionary) -> Dictionary:
	return {
		"input_quantities": value.input_quantities,
		"output_quantities": value.output_quantities,
		"state_quantities": value.state_quantities,
		"sign_convention": value.sign_convention,
	}
