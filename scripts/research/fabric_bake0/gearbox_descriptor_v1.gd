extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/gearbox_interface_contract_v1.gd")

const SCHEMA := "planet_simulator.fabric_gearbox_descriptor.v1"
const FIELDS: Array[String] = [
	"schema", "graph_hash", "material_catalog_hash", "interface_contract",
	"stage_count", "source_gear_count", "source_tooth_count", "stage_speed_ratios",
	"total_speed_ratio", "equivalent_input_inertia_kg_m2", "total_mass_kg",
	"max_abs_input_torque_nm", "max_abs_output_torque_nm",
	"max_abs_input_omega_rad_s", "max_abs_output_omega_rad_s",
	"source_operation_count", "compiled_operation_count", "descriptor_hash", "checksum",
]

static func create(data: Dictionary) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"graph_hash": String(data.graph_hash),
		"material_catalog_hash": String(data.material_catalog_hash),
		"interface_contract": data.interface_contract.duplicate(true),
		"stage_count": int(data.stage_count),
		"source_gear_count": int(data.source_gear_count),
		"source_tooth_count": int(data.source_tooth_count),
		"stage_speed_ratios": data.stage_speed_ratios.duplicate(),
		"total_speed_ratio": float(data.total_speed_ratio),
		"equivalent_input_inertia_kg_m2": float(data.equivalent_input_inertia_kg_m2),
		"total_mass_kg": float(data.total_mass_kg),
		"max_abs_input_torque_nm": float(data.max_abs_input_torque_nm),
		"max_abs_output_torque_nm": float(data.max_abs_output_torque_nm),
		"max_abs_input_omega_rad_s": float(data.max_abs_input_omega_rad_s),
		"max_abs_output_omega_rad_s": float(data.max_abs_output_omega_rad_s),
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
		return U.failure("UNSUPPORTED_GEARBOX_DESCRIPTOR_SCHEMA")
	for field in ["graph_hash", "material_catalog_hash", "descriptor_hash"]:
		if not U.is_lower_hex_64(value.get(field)):
			return U.failure("INVALID_GEARBOX_DESCRIPTOR_HASH", {"field": field})
	checked = Interface.validate(value.interface_contract)
	if not checked.success:
		return checked
	for field in ["stage_count", "source_gear_count", "source_tooth_count", "source_operation_count", "compiled_operation_count"]:
		if not U.is_json_integer(value.get(field)) or int(value[field]) < 1:
			return U.failure("INVALID_GEARBOX_DESCRIPTOR_INTEGER", {"field": field})
	if int(value.source_gear_count) != int(value.stage_count) * 2:
		return U.failure("GEARBOX_DESCRIPTOR_GEAR_COUNT_INVALID")
	if typeof(value.get("stage_speed_ratios")) != TYPE_ARRAY or value.stage_speed_ratios.size() != int(value.stage_count):
		return U.failure("GEARBOX_DESCRIPTOR_STAGE_RATIO_SIZE")
	var expected_ratio := 1.0
	for ratio in value.stage_speed_ratios:
		if not U.is_finite_number(ratio) or absf(float(ratio)) <= 1.0e-18:
			return U.failure("INVALID_GEARBOX_STAGE_RATIO")
		expected_ratio *= float(ratio)
	var ratio_scale := maxf(1.0e-18, maxf(absf(expected_ratio), absf(float(value.total_speed_ratio))))
	if absf(expected_ratio - float(value.total_speed_ratio)) > 1.0e-12 * ratio_scale:
		return U.failure("GEARBOX_DESCRIPTOR_TOTAL_RATIO_MISMATCH")
	for field in [
		"equivalent_input_inertia_kg_m2", "total_mass_kg", "max_abs_input_torque_nm",
		"max_abs_output_torque_nm", "max_abs_input_omega_rad_s", "max_abs_output_omega_rad_s"
	]:
		if not U.is_positive_number(value.get(field)):
			return U.failure("INVALID_GEARBOX_DESCRIPTOR_SCALAR", {"field": field})
	var expected_output_torque := float(value.max_abs_input_torque_nm) / absf(float(value.total_speed_ratio))
	var expected_output_omega := float(value.max_abs_input_omega_rad_s) * absf(float(value.total_speed_ratio))
	if absf(float(value.max_abs_output_torque_nm) - expected_output_torque) > 1.0e-12 * maxf(1.0, expected_output_torque):
		return U.failure("GEARBOX_DESCRIPTOR_OUTPUT_TORQUE_MISMATCH")
	if absf(float(value.max_abs_output_omega_rad_s) - expected_output_omega) > 1.0e-12 * maxf(1.0, expected_output_omega):
		return U.failure("GEARBOX_DESCRIPTOR_OUTPUT_SPEED_MISMATCH")
	if int(value.source_operation_count) <= int(value.compiled_operation_count):
		return U.failure("INSUFFICIENT_GEARBOX_COMPRESSION")
	if String(value.descriptor_hash) != U.canonical_hash(_identity(value)):
		return U.failure("GEARBOX_DESCRIPTOR_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("descriptor_hash")
	payload.erase("checksum")
	return payload
