extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/smart_servo_interface_contract_v1.gd")

const SCHEMA := "planet_simulator.fabric_smart_servo_descriptor.v1"
const FIELDS: Array[String] = [
	"schema","graph_hash","interface_contract","motor_capsule_checksum","gearbox_capsule_checksum",
	"gear_ratio","motor_resistance_ohm","torque_constant_nm_a",
	"motor_rotor_inertia_kg_m2","gearbox_reflected_inertia_kg_m2","combined_input_inertia_kg_m2",
	"motor_child_max_abs_current_a","motor_child_max_abs_omega_rad_s",
	"gearbox_child_max_abs_input_torque_nm","gearbox_child_max_abs_input_omega_rad_s",
	"position_kp_nm_rad","velocity_kd_nm_s_rad","position_tolerance_rad","velocity_tolerance_rad_s",
	"max_abs_current_a","max_abs_motor_omega_rad_s","max_abs_output_omega_rad_s","max_abs_output_torque_nm",
	"source_component_count","source_operation_count","compiled_operation_count",
	"descriptor_hash","checksum",
]

static func create(data:Dictionary)->Dictionary:
	var value:={
		"schema":SCHEMA,
		"graph_hash":String(data.graph_hash),
		"interface_contract":data.interface_contract.duplicate(true),
		"motor_capsule_checksum":String(data.motor_capsule_checksum),
		"gearbox_capsule_checksum":String(data.gearbox_capsule_checksum),
		"gear_ratio":float(data.gear_ratio),
		"motor_resistance_ohm":float(data.motor_resistance_ohm),
		"torque_constant_nm_a":float(data.torque_constant_nm_a),
		"motor_rotor_inertia_kg_m2":float(data.motor_rotor_inertia_kg_m2),
		"gearbox_reflected_inertia_kg_m2":float(data.gearbox_reflected_inertia_kg_m2),
		"combined_input_inertia_kg_m2":float(data.combined_input_inertia_kg_m2),
		"motor_child_max_abs_current_a":float(data.motor_child_max_abs_current_a),
		"motor_child_max_abs_omega_rad_s":float(data.motor_child_max_abs_omega_rad_s),
		"gearbox_child_max_abs_input_torque_nm":float(data.gearbox_child_max_abs_input_torque_nm),
		"gearbox_child_max_abs_input_omega_rad_s":float(data.gearbox_child_max_abs_input_omega_rad_s),
		"position_kp_nm_rad":float(data.position_kp_nm_rad),
		"velocity_kd_nm_s_rad":float(data.velocity_kd_nm_s_rad),
		"position_tolerance_rad":float(data.position_tolerance_rad),
		"velocity_tolerance_rad_s":float(data.velocity_tolerance_rad_s),
		"max_abs_current_a":float(data.max_abs_current_a),
		"max_abs_motor_omega_rad_s":float(data.max_abs_motor_omega_rad_s),
		"max_abs_output_omega_rad_s":float(data.max_abs_output_omega_rad_s),
		"max_abs_output_torque_nm":float(data.max_abs_output_torque_nm),
		"source_component_count":int(data.source_component_count),
		"source_operation_count":int(data.source_operation_count),
		"compiled_operation_count":int(data.compiled_operation_count),
		"descriptor_hash":"",
		"checksum":"",
	}
	value.descriptor_hash=U.canonical_hash(_identity(value))
	value.checksum=U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value:Dictionary)->Dictionary:
	var checked:=U.validate_exact_fields(value,FIELDS)
	if not checked.success:return checked
	if value.get("schema")!=SCHEMA:
		return U.failure("UNSUPPORTED_SMART_SERVO_DESCRIPTOR_SCHEMA")
	for field in ["graph_hash","motor_capsule_checksum","gearbox_capsule_checksum","descriptor_hash"]:
		if not U.is_lower_hex_64(value.get(field)):
			return U.failure("INVALID_SMART_SERVO_DESCRIPTOR_HASH",{"field":field})
	checked=Interface.validate(value.interface_contract)
	if not checked.success:return checked
	for field in [
		"motor_resistance_ohm","torque_constant_nm_a","motor_rotor_inertia_kg_m2",
		"gearbox_reflected_inertia_kg_m2","combined_input_inertia_kg_m2",
		"motor_child_max_abs_current_a","motor_child_max_abs_omega_rad_s",
		"gearbox_child_max_abs_input_torque_nm","gearbox_child_max_abs_input_omega_rad_s",
		"position_kp_nm_rad","velocity_kd_nm_s_rad","position_tolerance_rad","velocity_tolerance_rad_s",
		"max_abs_current_a","max_abs_motor_omega_rad_s","max_abs_output_omega_rad_s","max_abs_output_torque_nm"
	]:
		if not U.is_positive_number(value.get(field)):
			return U.failure("INVALID_SMART_SERVO_DESCRIPTOR_SCALAR",{"field":field})
	if not U.is_finite_number(value.get("gear_ratio")) or absf(float(value.gear_ratio))<=1.0e-18:
		return U.failure("INVALID_SMART_SERVO_GEAR_RATIO")
	for field in ["source_component_count","source_operation_count","compiled_operation_count"]:
		if not U.is_json_integer(value.get(field)) or int(value[field])<1:
			return U.failure("INVALID_SMART_SERVO_DESCRIPTOR_INTEGER",{"field":field})
	var expected_inertia:=float(value.motor_rotor_inertia_kg_m2)+float(value.gearbox_reflected_inertia_kg_m2)
	if absf(float(value.combined_input_inertia_kg_m2)-expected_inertia)>1.0e-12*maxf(1.0,expected_inertia):
		return U.failure("SMART_SERVO_DESCRIPTOR_INERTIA_RELATION_MISMATCH")
	var expected_max_current:=minf(
		float(value.motor_child_max_abs_current_a),
		float(value.gearbox_child_max_abs_input_torque_nm)/float(value.torque_constant_nm_a)
	)
	if absf(float(value.max_abs_current_a)-expected_max_current)>1.0e-12*maxf(1.0,expected_max_current):
		return U.failure("SMART_SERVO_DESCRIPTOR_CURRENT_ENVELOPE_MISMATCH")
	var expected_max_motor_omega:=minf(
		float(value.motor_child_max_abs_omega_rad_s),
		float(value.gearbox_child_max_abs_input_omega_rad_s)
	)
	if absf(float(value.max_abs_motor_omega_rad_s)-expected_max_motor_omega)>1.0e-12*maxf(1.0,expected_max_motor_omega):
		return U.failure("SMART_SERVO_DESCRIPTOR_SPEED_ENVELOPE_MISMATCH")
	var expected_output_omega:=float(value.max_abs_motor_omega_rad_s)*absf(float(value.gear_ratio))
	if absf(float(value.max_abs_output_omega_rad_s)-expected_output_omega)>1.0e-12*maxf(1.0,expected_output_omega):
		return U.failure("SMART_SERVO_DESCRIPTOR_OUTPUT_SPEED_RELATION_MISMATCH")
	var expected_output_torque:=float(value.torque_constant_nm_a)*float(value.max_abs_current_a)/absf(float(value.gear_ratio))
	if absf(float(value.max_abs_output_torque_nm)-expected_output_torque)>1.0e-12*maxf(1.0,expected_output_torque):
		return U.failure("SMART_SERVO_DESCRIPTOR_OUTPUT_TORQUE_RELATION_MISMATCH")
	if int(value.source_operation_count)<=int(value.compiled_operation_count):
		return U.failure("INSUFFICIENT_SMART_SERVO_COMPRESSION")
	if String(value.descriptor_hash)!=U.canonical_hash(_identity(value)):
		return U.failure("SMART_SERVO_DESCRIPTOR_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity(value:Dictionary)->Dictionary:
	var payload:=value.duplicate(true)
	payload.erase("descriptor_hash");payload.erase("checksum")
	return payload
