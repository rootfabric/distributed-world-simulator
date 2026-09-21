extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/power_stage_interface_contract_v1.gd")

const SCHEMA := "planet_simulator.fabric_power_stage_descriptor.v1"
const FIELDS: Array[String] = [
	"schema", "graph_hash", "material_catalog_hash", "interface_contract",
	"switch_die_count", "active_die_count", "bank_count", "profile_id",
	"bank_resistance_ref_ohm", "bank_max_abs_current_a", "bank_effective_transition_time_s",
	"positive_path_resistance_ref_ohm", "negative_path_resistance_ref_ohm",
	"positive_path_max_abs_current_a", "negative_path_max_abs_current_a",
	"positive_path_transition_time_s", "negative_path_transition_time_s",
	"resistance_temp_coefficient_per_k", "reference_temperature_k",
	"min_temperature_k", "max_temperature_k", "max_bus_voltage_v",
	"total_semiconductor_mass_kg", "source_operation_count", "compiled_operation_count",
	"descriptor_hash", "checksum",
]

static func create(data: Dictionary) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"graph_hash": String(data.graph_hash),
		"material_catalog_hash": String(data.material_catalog_hash),
		"interface_contract": data.interface_contract.duplicate(true),
		"switch_die_count": int(data.switch_die_count),
		"active_die_count": int(data.active_die_count),
		"bank_count": int(data.bank_count),
		"profile_id": String(data.profile_id),
		"bank_resistance_ref_ohm": data.bank_resistance_ref_ohm.duplicate(),
		"bank_max_abs_current_a": data.bank_max_abs_current_a.duplicate(),
		"bank_effective_transition_time_s": data.bank_effective_transition_time_s.duplicate(),
		"positive_path_resistance_ref_ohm": float(data.positive_path_resistance_ref_ohm),
		"negative_path_resistance_ref_ohm": float(data.negative_path_resistance_ref_ohm),
		"positive_path_max_abs_current_a": float(data.positive_path_max_abs_current_a),
		"negative_path_max_abs_current_a": float(data.negative_path_max_abs_current_a),
		"positive_path_transition_time_s": float(data.positive_path_transition_time_s),
		"negative_path_transition_time_s": float(data.negative_path_transition_time_s),
		"resistance_temp_coefficient_per_k": float(data.resistance_temp_coefficient_per_k),
		"reference_temperature_k": float(data.reference_temperature_k),
		"min_temperature_k": float(data.min_temperature_k),
		"max_temperature_k": float(data.max_temperature_k),
		"max_bus_voltage_v": float(data.max_bus_voltage_v),
		"total_semiconductor_mass_kg": float(data.total_semiconductor_mass_kg),
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
		return U.failure("UNSUPPORTED_POWER_STAGE_DESCRIPTOR_SCHEMA")
	for field in ["graph_hash", "material_catalog_hash", "descriptor_hash"]:
		if not U.is_lower_hex_64(value.get(field)):
			return U.failure("INVALID_POWER_STAGE_DESCRIPTOR_HASH", {"field": field})
	checked = Interface.validate(value.interface_contract)
	if not checked.success:
		return checked
	for field in ["switch_die_count", "active_die_count", "bank_count", "source_operation_count", "compiled_operation_count"]:
		if not U.is_json_integer(value.get(field)) or int(value[field]) < 1:
			return U.failure("INVALID_POWER_STAGE_DESCRIPTOR_INTEGER", {"field": field})
	if int(value.bank_count) != 4 or int(value.active_die_count) > int(value.switch_die_count):
		return U.failure("POWER_STAGE_DESCRIPTOR_TOPOLOGY_INVALID")
	if not U.is_canonical_id(value.get("profile_id"), 2):
		return U.failure("INVALID_POWER_STAGE_DESCRIPTOR_PROFILE_ID")
	for field in ["bank_resistance_ref_ohm", "bank_max_abs_current_a", "bank_effective_transition_time_s"]:
		if typeof(value.get(field)) != TYPE_ARRAY or value[field].size() != 4:
			return U.failure("POWER_STAGE_DESCRIPTOR_BANK_ARRAY_SIZE", {"field": field})
		for number in value[field]:
			if not U.is_positive_number(number):
				return U.failure("INVALID_POWER_STAGE_DESCRIPTOR_BANK_VALUE", {"field": field})
	for field in [
		"positive_path_resistance_ref_ohm", "negative_path_resistance_ref_ohm",
		"positive_path_max_abs_current_a", "negative_path_max_abs_current_a",
		"positive_path_transition_time_s", "negative_path_transition_time_s",
		"reference_temperature_k", "min_temperature_k", "max_temperature_k",
		"max_bus_voltage_v", "total_semiconductor_mass_kg"
	]:
		if not U.is_positive_number(value.get(field)):
			return U.failure("INVALID_POWER_STAGE_DESCRIPTOR_SCALAR", {"field": field})
	if not U.is_non_negative_number(value.get("resistance_temp_coefficient_per_k")):
		return U.failure("INVALID_POWER_STAGE_DESCRIPTOR_TEMP_COEFFICIENT")
	if float(value.min_temperature_k) >= float(value.reference_temperature_k) or float(value.reference_temperature_k) >= float(value.max_temperature_k):
		return U.failure("POWER_STAGE_DESCRIPTOR_TEMPERATURE_ORDER_INVALID")
	if int(value.active_die_count) > int(value.switch_die_count) or int(value.active_die_count) < int(value.bank_count):
		return U.failure("POWER_STAGE_DESCRIPTOR_ACTIVE_DIE_COUNT_INVALID")
	var expected_positive_r := float(value.bank_resistance_ref_ohm[0]) + float(value.bank_resistance_ref_ohm[3])
	var expected_negative_r := float(value.bank_resistance_ref_ohm[1]) + float(value.bank_resistance_ref_ohm[2])
	var expected_positive_current := minf(float(value.bank_max_abs_current_a[0]), float(value.bank_max_abs_current_a[3]))
	var expected_negative_current := minf(float(value.bank_max_abs_current_a[1]), float(value.bank_max_abs_current_a[2]))
	var expected_positive_transition := float(value.bank_effective_transition_time_s[0]) + float(value.bank_effective_transition_time_s[3])
	var expected_negative_transition := float(value.bank_effective_transition_time_s[1]) + float(value.bank_effective_transition_time_s[2])
	var consistency_checks := [
		["positive_path_resistance_ref_ohm", float(value.positive_path_resistance_ref_ohm), expected_positive_r],
		["negative_path_resistance_ref_ohm", float(value.negative_path_resistance_ref_ohm), expected_negative_r],
		["positive_path_max_abs_current_a", float(value.positive_path_max_abs_current_a), expected_positive_current],
		["negative_path_max_abs_current_a", float(value.negative_path_max_abs_current_a), expected_negative_current],
		["positive_path_transition_time_s", float(value.positive_path_transition_time_s), expected_positive_transition],
		["negative_path_transition_time_s", float(value.negative_path_transition_time_s), expected_negative_transition],
	]
	for relation in consistency_checks:
		var actual := float(relation[1])
		var expected := float(relation[2])
		var scale := maxf(1.0e-18, maxf(absf(actual), absf(expected)))
		if absf(actual - expected) > 1.0e-12 * scale:
			return U.failure("POWER_STAGE_DESCRIPTOR_PATH_RELATION_MISMATCH", {"field": String(relation[0]), "actual": actual, "expected": expected})
	if int(value.source_operation_count) <= int(value.compiled_operation_count):
		return U.failure("INSUFFICIENT_POWER_STAGE_COMPRESSION")
	if String(value.descriptor_hash) != U.canonical_hash(_identity(value)):
		return U.failure("POWER_STAGE_DESCRIPTOR_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("descriptor_hash")
	payload.erase("checksum")
	return payload
