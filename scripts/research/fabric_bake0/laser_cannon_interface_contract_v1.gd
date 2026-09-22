extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_laser_cannon_interface.v1"
const STATE_OWNER := "CALLER_CANONICAL_OWNER"
const FIELDS: Array[String] = [
	"schema", "input_quantities", "output_quantities", "state_quantities",
	"state_owner", "interface_hash", "checksum",
]

static func create() -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"input_quantities": [
			"AMBIENT_TEMPERATURE_K", "BUS_VOLTAGE_V", "CURRENT_A", "DT_S",
			"MASS_FLOW_KG_S", "PWM_FREQUENCY_HZ", "TARGET_RANGE_M",
		],
		"output_quantities": [
			"BEAM_DIVERGENCE_HALF_ANGLE_RAD", "BUS_CURRENT_A", "BUS_INPUT_ENERGY_J",
			"COOLING_PUMP_HYDRAULIC_ENERGY_J", "ENERGY_RESIDUAL_J", "MUZZLE_OPTICAL_ENERGY_J",
			"OPTICS_ABSORBED_HEAT_J", "SPOT_FLUENCE_J_M2", "SPOT_RADIUS_M",
			"TOTAL_INTERNAL_HEAT_J", "WAVELENGTH_M",
		],
		"state_quantities": [
			"COLD_COOLANT_TEMPERATURE_K", "HOT_COOLANT_TEMPERATURE_K",
			"PLATE_TEMPERATURE_K", "RADIATOR_TEMPERATURE_K",
		],
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
		return U.failure("UNSUPPORTED_LASER_CANNON_INTERFACE_SCHEMA")
	for field in ["input_quantities","output_quantities","state_quantities"]:
		checked = U.validate_sorted_unique_strings(value.get(field), false, true)
		if not checked.success:
			return U.failure("INVALID_LASER_CANNON_INTERFACE_QUANTITIES", {"field":field})
	if value.get("state_owner") != STATE_OWNER:
		return U.failure("UNSUPPORTED_LASER_CANNON_STATE_OWNER")
	if not U.is_lower_hex_64(value.get("interface_hash")) or String(value.interface_hash) != U.canonical_hash(_identity(value)):
		return U.failure("LASER_CANNON_INTERFACE_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity(value: Dictionary) -> Dictionary:
	return {
		"input_quantities":value.input_quantities,
		"output_quantities":value.output_quantities,
		"state_quantities":value.state_quantities,
		"state_owner":value.state_owner,
	}
