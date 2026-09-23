extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_smart_servo_interface.v1"
const STATE_OWNER := "CALLER_CANONICAL_OWNER"
const SIGN_CONVENTION := "OUTPUT_TORQUE_POSITIVE_INTO_OUTPUT_SHAFT__MOTOR_TO_OUTPUT_RATIO_SIGNED"
const FIELDS: Array[String] = [
	"schema","input_quantities","output_quantities","state_quantities",
	"state_owner","sign_convention","interface_hash","checksum",
]

static func create()->Dictionary:
	var value:={
		"schema":SCHEMA,
		"input_quantities":[
			"DT_S","EXTERNAL_OUTPUT_TORQUE_NM","TARGET_POSITION_RAD","TARGET_VELOCITY_RAD_S",
		],
		"output_quantities":[
			"CURRENT_COMMAND_A","CURRENT_COMMAND_SATURATED","ELECTRICAL_ENERGY_J",
			"ENERGY_RESIDUAL_J","KINETIC_ENERGY_DELTA_J","OUTPUT_BOUNDARY_ENERGY_J",
			"OUTPUT_POSITION_RAD","OUTPUT_TORQUE_COMMAND_NM","OUTPUT_VELOCITY_RAD_S",
			"RESISTIVE_HEAT_J","SETTLED","TERMINAL_VOLTAGE_V",
		],
		"state_quantities":["MOTOR_ANGULAR_VELOCITY_RAD_S","OUTPUT_POSITION_RAD"],
		"state_owner":STATE_OWNER,
		"sign_convention":SIGN_CONVENTION,
		"interface_hash":"",
		"checksum":"",
	}
	value.interface_hash=U.canonical_hash(_identity(value))
	value.checksum=U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value:Dictionary)->Dictionary:
	var checked:=U.validate_exact_fields(value,FIELDS)
	if not checked.success:return checked
	if value.get("schema")!=SCHEMA:
		return U.failure("UNSUPPORTED_SMART_SERVO_INTERFACE_SCHEMA")
	for field in ["input_quantities","output_quantities","state_quantities"]:
		checked=U.validate_sorted_unique_strings(value.get(field),false,true)
		if not checked.success:
			return U.failure("INVALID_SMART_SERVO_INTERFACE_QUANTITIES",{"field":field})
	if value.get("state_owner")!=STATE_OWNER or value.get("sign_convention")!=SIGN_CONVENTION:
		return U.failure("UNSUPPORTED_SMART_SERVO_INTERFACE_SEMANTICS")
	if not U.is_lower_hex_64(value.get("interface_hash")) or String(value.interface_hash)!=U.canonical_hash(_identity(value)):
		return U.failure("SMART_SERVO_INTERFACE_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity(value:Dictionary)->Dictionary:
	return {
		"input_quantities":value.input_quantities,
		"output_quantities":value.output_quantities,
		"state_quantities":value.state_quantities,
		"state_owner":value.state_owner,
		"sign_convention":value.sign_convention,
	}
