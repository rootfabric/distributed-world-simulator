extends RefCounted
## Characterized electrochemical floor linked to canonical Matter material.
## This is a bounded simulation primitive, not atom-level chemistry.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterMaterial = preload("res://scripts/simulation/matter/contracts/matter_material_definition.gd")

const SCHEMA := "planet_simulator.fabric_battery_electrochemical_profile.v1"
const FIELDS: Array[String] = [
	"schema", "profile_id", "active_material_id", "active_material_checksum",
	"empty_voltage_v", "nominal_voltage_v", "full_voltage_v",
	"specific_capacity_c_per_kg", "effective_conductivity_s_m",
	"contact_resistivity_ohm_m2", "max_current_density_a_m2",
	"resistance_temp_coefficient_per_k", "reference_temperature_k",
	"min_temperature_k", "max_temperature_k", "checksum",
]

static func create(
	profile_id: String,
	active_material: Dictionary,
	empty_voltage_v: float,
	nominal_voltage_v: float,
	full_voltage_v: float,
	specific_capacity_c_per_kg: float,
	effective_conductivity_s_m: float,
	contact_resistivity_ohm_m2: float,
	max_current_density_a_m2: float,
	resistance_temp_coefficient_per_k: float,
	reference_temperature_k: float,
	min_temperature_k: float,
	max_temperature_k: float
) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"profile_id": profile_id,
		"active_material_id": String(active_material.get("material_id", "")),
		"active_material_checksum": String(active_material.get("checksum", "")),
		"empty_voltage_v": empty_voltage_v,
		"nominal_voltage_v": nominal_voltage_v,
		"full_voltage_v": full_voltage_v,
		"specific_capacity_c_per_kg": specific_capacity_c_per_kg,
		"effective_conductivity_s_m": effective_conductivity_s_m,
		"contact_resistivity_ohm_m2": contact_resistivity_ohm_m2,
		"max_current_density_a_m2": max_current_density_a_m2,
		"resistance_temp_coefficient_per_k": resistance_temp_coefficient_per_k,
		"reference_temperature_k": reference_temperature_k,
		"min_temperature_k": min_temperature_k,
		"max_temperature_k": max_temperature_k,
		"checksum": "",
	}
	value.checksum = U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA:
		return U.failure("UNSUPPORTED_BATTERY_ELECTROCHEMICAL_PROFILE_SCHEMA")
	if not U.is_canonical_id(value.get("profile_id"), 2):
		return U.failure("INVALID_BATTERY_PROFILE_ID")
	if not U.is_canonical_id(value.get("active_material_id"), 2):
		return U.failure("INVALID_BATTERY_PROFILE_MATERIAL_ID")
	if not U.is_lower_hex_64(value.get("active_material_checksum")):
		return U.failure("INVALID_BATTERY_PROFILE_MATERIAL_CHECKSUM")
	for field in [
		"empty_voltage_v", "nominal_voltage_v", "full_voltage_v",
		"specific_capacity_c_per_kg", "effective_conductivity_s_m",
		"contact_resistivity_ohm_m2", "max_current_density_a_m2",
		"reference_temperature_k", "min_temperature_k", "max_temperature_k"
	]:
		if not U.is_positive_number(value.get(field)):
			return U.failure("INVALID_BATTERY_PROFILE_PROPERTY", {"field": field})
	if not U.is_non_negative_number(value.get("resistance_temp_coefficient_per_k")):
		return U.failure("INVALID_BATTERY_PROFILE_TEMP_COEFFICIENT")
	if not (float(value.empty_voltage_v) < float(value.nominal_voltage_v) and float(value.nominal_voltage_v) < float(value.full_voltage_v)):
		return U.failure("INVALID_BATTERY_PROFILE_VOLTAGE_ORDER")
	if not (float(value.min_temperature_k) < float(value.reference_temperature_k) and float(value.reference_temperature_k) < float(value.max_temperature_k)):
		return U.failure("INVALID_BATTERY_PROFILE_TEMPERATURE_ORDER")
	return U.validate_checksum(value)

static func validate_against_material(value: Dictionary, material: Dictionary) -> Dictionary:
	var checked := validate(value)
	if not checked.success:
		return checked
	var matter_checked: Dictionary = MatterMaterial.validate(material)
	if not bool(matter_checked.get("success", false)):
		return U.failure("BATTERY_PROFILE_MATTER_MATERIAL_INVALID")
	if String(value.active_material_id) != String(material.material_id):
		return U.failure("BATTERY_PROFILE_MATERIAL_ID_MISMATCH")
	if String(value.active_material_checksum) != String(material.checksum):
		return U.failure("BATTERY_PROFILE_MATERIAL_CHECKSUM_MISMATCH")
	return U.success()
