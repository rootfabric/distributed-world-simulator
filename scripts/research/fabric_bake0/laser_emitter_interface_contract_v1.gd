extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_laser_emitter_interface.v1"
const FIELDS: Array[String] = [
	"schema", "input_quantities", "output_quantities", "state_quantities",
	"interface_hash", "checksum",
]

static func create() -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"input_quantities": ["CURRENT_A", "DT_S", "JUNCTION_TEMPERATURE_K"],
		"output_quantities": [
			"BEAM_DIVERGENCE_HALF_ANGLE_RAD", "ELECTRICAL_ENERGY_J", "ENERGY_RESIDUAL_J",
			"OPTICAL_ENERGY_J", "PHOTON_COUNT", "TERMINAL_VOLTAGE_V",
			"WASTE_HEAT_J", "WAVELENGTH_M",
		],
		"state_quantities": [],
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
		return U.failure("UNSUPPORTED_LASER_EMITTER_INTERFACE_SCHEMA")
	for field in ["input_quantities", "output_quantities", "state_quantities"]:
		checked = U.validate_sorted_unique_strings(value.get(field), field == "state_quantities", true)
		if not checked.success:
			return U.failure("INVALID_LASER_EMITTER_INTERFACE_QUANTITIES", {"field": field})
	if not U.is_lower_hex_64(value.get("interface_hash")) or String(value.interface_hash) != U.canonical_hash(_identity(value)):
		return U.failure("LASER_EMITTER_INTERFACE_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity(value: Dictionary) -> Dictionary:
	return {
		"input_quantities": value.input_quantities,
		"output_quantities": value.output_quantities,
		"state_quantities": value.state_quantities,
	}
