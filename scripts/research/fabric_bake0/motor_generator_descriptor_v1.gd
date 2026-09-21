extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/motor_generator_interface_contract_v1.gd")

const SCHEMA := "planet_simulator.fabric_motor_generator_descriptor.v1"
const FIELDS: Array[String] = [
	"schema", "graph_hash", "material_catalog_hash", "interface_contract",
	"winding_segment_count", "rotor_sector_count",
	"total_resistance_ohm", "torque_constant_nm_a", "back_emf_constant_v_s_rad",
	"max_abs_current_a", "winding_mass_kg", "rotor_mass_kg", "rotor_inertia_kg_m2",
	"max_abs_angular_velocity_rad_s", "source_operation_count", "compiled_operation_count",
	"descriptor_hash", "checksum",
]

static func create(data: Dictionary) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"graph_hash": String(data.graph_hash),
		"material_catalog_hash": String(data.material_catalog_hash),
		"interface_contract": data.interface_contract.duplicate(true),
		"winding_segment_count": int(data.winding_segment_count),
		"rotor_sector_count": int(data.rotor_sector_count),
		"total_resistance_ohm": float(data.total_resistance_ohm),
		"torque_constant_nm_a": float(data.torque_constant_nm_a),
		"back_emf_constant_v_s_rad": float(data.back_emf_constant_v_s_rad),
		"max_abs_current_a": float(data.max_abs_current_a),
		"winding_mass_kg": float(data.winding_mass_kg),
		"rotor_mass_kg": float(data.rotor_mass_kg),
		"rotor_inertia_kg_m2": float(data.rotor_inertia_kg_m2),
		"max_abs_angular_velocity_rad_s": float(data.max_abs_angular_velocity_rad_s),
		"source_operation_count": int(data.source_operation_count),
		"compiled_operation_count": int(data.compiled_operation_count),
		"descriptor_hash": "",
		"checksum": "",
	}
	value.descriptor_hash = U.canonical_hash(_identity(value))
	value.checksum = U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA:
		return U.failure("UNSUPPORTED_MOTOR_GENERATOR_DESCRIPTOR_SCHEMA")
	for field in ["graph_hash", "material_catalog_hash", "descriptor_hash"]:
		if not U.is_lower_hex_64(value.get(field)):
			return U.failure("INVALID_MOTOR_GENERATOR_DESCRIPTOR_HASH", {"field": field})
	checked = Interface.validate(value.interface_contract)
	if not checked.success:
		return checked
	for field in ["winding_segment_count", "rotor_sector_count", "source_operation_count", "compiled_operation_count"]:
		if not U.is_json_integer(value.get(field)) or int(value[field]) < 1:
			return U.failure("INVALID_MOTOR_GENERATOR_DESCRIPTOR_INTEGER", {"field": field})
	for field in [
		"total_resistance_ohm", "torque_constant_nm_a", "back_emf_constant_v_s_rad",
		"max_abs_current_a", "winding_mass_kg", "rotor_mass_kg", "rotor_inertia_kg_m2",
		"max_abs_angular_velocity_rad_s"
	]:
		if not U.is_positive_number(value.get(field)):
			return U.failure("INVALID_MOTOR_GENERATOR_DESCRIPTOR_SCALAR", {"field": field})
	if absf(float(value.torque_constant_nm_a) - float(value.back_emf_constant_v_s_rad)) > 1.0e-12:
		return U.failure("MOTOR_GENERATOR_SI_COUPLING_MISMATCH")
	if int(value.source_operation_count) <= int(value.compiled_operation_count):
		return U.failure("INSUFFICIENT_MOTOR_GENERATOR_COMPRESSION")
	if String(value.descriptor_hash) != U.canonical_hash(_identity(value)):
		return U.failure("MOTOR_GENERATOR_DESCRIPTOR_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("descriptor_hash")
	payload.erase("checksum")
	return payload
