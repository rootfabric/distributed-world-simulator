extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/battery_interface_contract_v1.gd")

const SCHEMA := "planet_simulator.fabric_battery_pack_descriptor.v1"
const FIELDS: Array[String] = [
	"schema", "graph_hash", "material_catalog_hash", "interface_contract",
	"series_group_count", "source_cell_count", "active_cell_count",
	"group_profile_ids", "group_capacity_c", "group_resistance_ref_ohm",
	"group_empty_voltage_v", "group_nominal_voltage_v", "group_full_voltage_v",
	"group_max_current_a", "group_resistance_temp_coefficient_per_k",
	"group_reference_temperature_k", "total_mass_kg", "thermal_capacity_j_k",
	"thermal_conductance_w_k", "min_temperature_k", "max_temperature_k",
	"max_continuous_current_a", "empty_voltage_v", "nominal_voltage_v",
	"full_voltage_v", "full_chemical_energy_j", "source_operation_count",
	"compiled_operation_count", "descriptor_hash", "checksum",
]

static func create(data: Dictionary) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"graph_hash": data.graph_hash,
		"material_catalog_hash": data.material_catalog_hash,
		"interface_contract": data.interface_contract.duplicate(true),
		"series_group_count": int(data.series_group_count),
		"source_cell_count": int(data.source_cell_count),
		"active_cell_count": int(data.active_cell_count),
		"group_profile_ids": data.group_profile_ids.duplicate(),
		"group_capacity_c": data.group_capacity_c.duplicate(),
		"group_resistance_ref_ohm": data.group_resistance_ref_ohm.duplicate(),
		"group_empty_voltage_v": data.group_empty_voltage_v.duplicate(),
		"group_nominal_voltage_v": data.group_nominal_voltage_v.duplicate(),
		"group_full_voltage_v": data.group_full_voltage_v.duplicate(),
		"group_max_current_a": data.group_max_current_a.duplicate(),
		"group_resistance_temp_coefficient_per_k": data.group_resistance_temp_coefficient_per_k.duplicate(),
		"group_reference_temperature_k": data.group_reference_temperature_k.duplicate(),
		"total_mass_kg": float(data.total_mass_kg),
		"thermal_capacity_j_k": float(data.thermal_capacity_j_k),
		"thermal_conductance_w_k": float(data.thermal_conductance_w_k),
		"min_temperature_k": float(data.min_temperature_k),
		"max_temperature_k": float(data.max_temperature_k),
		"max_continuous_current_a": float(data.max_continuous_current_a),
		"empty_voltage_v": float(data.empty_voltage_v),
		"nominal_voltage_v": float(data.nominal_voltage_v),
		"full_voltage_v": float(data.full_voltage_v),
		"full_chemical_energy_j": float(data.full_chemical_energy_j),
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
		return U.failure("UNSUPPORTED_BATTERY_PACK_DESCRIPTOR_SCHEMA")
	for field in ["graph_hash", "material_catalog_hash", "descriptor_hash"]:
		if not U.is_lower_hex_64(value.get(field)):
			return U.failure("INVALID_BATTERY_DESCRIPTOR_HASH", {"field": field})
	if typeof(value.get("interface_contract")) != TYPE_DICTIONARY:
		return U.failure("INVALID_BATTERY_DESCRIPTOR_INTERFACE")
	checked = Interface.validate(value.interface_contract)
	if not checked.success:
		return checked
	for field in ["series_group_count", "source_cell_count", "active_cell_count", "source_operation_count", "compiled_operation_count"]:
		if not U.is_json_integer(value.get(field)) or int(value[field]) < 1:
			return U.failure("INVALID_BATTERY_DESCRIPTOR_INTEGER", {"field": field})
	var n := int(value.series_group_count)
	if int(value.active_cell_count) > int(value.source_cell_count):
		return U.failure("BATTERY_DESCRIPTOR_ACTIVE_CELL_COUNT_INVALID")
	for field in [
		"group_profile_ids", "group_capacity_c", "group_resistance_ref_ohm",
		"group_empty_voltage_v", "group_nominal_voltage_v", "group_full_voltage_v",
		"group_max_current_a", "group_resistance_temp_coefficient_per_k",
		"group_reference_temperature_k"
	]:
		if typeof(value.get(field)) != TYPE_ARRAY or value[field].size() != n:
			return U.failure("BATTERY_DESCRIPTOR_GROUP_ARRAY_SIZE", {"field": field})
	for profile_id in value.group_profile_ids:
		if not U.is_canonical_id(profile_id, 2):
			return U.failure("INVALID_BATTERY_DESCRIPTOR_PROFILE_ID")
	for field in [
		"group_capacity_c", "group_resistance_ref_ohm", "group_empty_voltage_v",
		"group_nominal_voltage_v", "group_full_voltage_v", "group_max_current_a",
		"group_reference_temperature_k"
	]:
		for number in value[field]:
			if not U.is_positive_number(number):
				return U.failure("INVALID_BATTERY_DESCRIPTOR_GROUP_VALUE", {"field": field})
	for number in value.group_resistance_temp_coefficient_per_k:
		if not U.is_non_negative_number(number):
			return U.failure("INVALID_BATTERY_DESCRIPTOR_TEMP_COEFFICIENT")
	for field in [
		"total_mass_kg", "thermal_capacity_j_k", "thermal_conductance_w_k",
		"min_temperature_k", "max_temperature_k", "max_continuous_current_a",
		"empty_voltage_v", "nominal_voltage_v", "full_voltage_v", "full_chemical_energy_j"
	]:
		if not U.is_positive_number(value.get(field)):
			return U.failure("INVALID_BATTERY_DESCRIPTOR_SCALAR", {"field": field})
	if float(value.min_temperature_k) >= float(value.max_temperature_k):
		return U.failure("BATTERY_DESCRIPTOR_TEMPERATURE_RANGE_INVALID")
	if not (float(value.empty_voltage_v) < float(value.nominal_voltage_v) and float(value.nominal_voltage_v) < float(value.full_voltage_v)):
		return U.failure("BATTERY_DESCRIPTOR_VOLTAGE_ORDER_INVALID")
	if int(value.source_operation_count) <= int(value.compiled_operation_count):
		return U.failure("INSUFFICIENT_BATTERY_COMPRESSION")
	if String(value.descriptor_hash) != U.canonical_hash(_identity(value)):
		return U.failure("BATTERY_DESCRIPTOR_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("descriptor_hash")
	payload.erase("checksum")
	return payload
