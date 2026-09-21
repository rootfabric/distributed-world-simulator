extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_battery_interface.v1"
const SIGN_CONVENTION := "CURRENT_POSITIVE_DISCHARGE"
const STATE_OWNER := "CALLER_CANONICAL_OWNER"
const FIELDS: Array[String] = [
	"schema", "input_quantities", "output_quantities", "state_quantities",
	"sign_convention", "state_owner", "interface_hash", "checksum",
]

static func create() -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"input_quantities": ["AMBIENT_TEMPERATURE_K", "CURRENT_A", "DT_S"],
		"output_quantities": ["CHEMICAL_ENERGY_DELTA_J", "ELECTRICAL_ENERGY_J", "HEAT_GENERATED_J", "TERMINAL_VOLTAGE_V"],
		"state_quantities": ["GROUP_CHARGE_C", "TEMPERATURE_K"],
		"sign_convention": SIGN_CONVENTION,
		"state_owner": STATE_OWNER,
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
		return U.failure("UNSUPPORTED_BATTERY_INTERFACE_SCHEMA")
	for field in ["input_quantities", "output_quantities", "state_quantities"]:
		checked = U.validate_sorted_unique_strings(value.get(field), false, true)
		if not checked.success:
			return U.failure("INVALID_BATTERY_INTERFACE_QUANTITIES", {"field": field})
	if value.get("sign_convention") != SIGN_CONVENTION or value.get("state_owner") != STATE_OWNER:
		return U.failure("UNSUPPORTED_BATTERY_INTERFACE_SEMANTICS")
	if not U.is_lower_hex_64(value.get("interface_hash")) or String(value.interface_hash) != U.canonical_hash(_identity(value)):
		return U.failure("BATTERY_INTERFACE_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity(value: Dictionary) -> Dictionary:
	return {
		"input_quantities": value.input_quantities,
		"output_quantities": value.output_quantities,
		"state_quantities": value.state_quantities,
		"sign_convention": value.sign_convention,
		"state_owner": value.state_owner,
	}
