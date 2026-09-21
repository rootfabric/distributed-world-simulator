extends RefCounted
## Characterized semiconductor floor linked to canonical Matter material.
## Generic Matter does not yet carry ON-state resistivity, current density or switching transition time.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterMaterial = preload("res://scripts/simulation/matter/contracts/matter_material_definition.gd")

const SCHEMA := "planet_simulator.fabric_power_stage_semiconductor_profile.v1"
const FIELDS: Array[String] = [
	"schema", "profile_id", "semiconductor_material_id", "semiconductor_material_checksum",
	"effective_on_resistivity_ohm_m", "max_current_density_a_m2",
	"transition_time_s", "resistance_temp_coefficient_per_k",
	"reference_temperature_k", "min_temperature_k", "max_temperature_k",
	"max_bus_voltage_v", "checksum",
]

static func create(
	profile_id: String,
	material: Dictionary,
	effective_on_resistivity_ohm_m: float,
	max_current_density_a_m2: float,
	transition_time_s: float,
	resistance_temp_coefficient_per_k: float,
	reference_temperature_k: float,
	min_temperature_k: float,
	max_temperature_k: float,
	max_bus_voltage_v: float
) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"profile_id": profile_id,
		"semiconductor_material_id": String(material.get("material_id", "")),
		"semiconductor_material_checksum": String(material.get("checksum", "")),
		"effective_on_resistivity_ohm_m": effective_on_resistivity_ohm_m,
		"max_current_density_a_m2": max_current_density_a_m2,
		"transition_time_s": transition_time_s,
		"resistance_temp_coefficient_per_k": resistance_temp_coefficient_per_k,
		"reference_temperature_k": reference_temperature_k,
		"min_temperature_k": min_temperature_k,
		"max_temperature_k": max_temperature_k,
		"max_bus_voltage_v": max_bus_voltage_v,
		"checksum": "",
	}
	value.checksum = U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA:
		return U.failure("UNSUPPORTED_POWER_STAGE_SEMICONDUCTOR_PROFILE_SCHEMA")
	if not U.is_canonical_id(value.get("profile_id"), 2):
		return U.failure("INVALID_POWER_STAGE_PROFILE_ID")
	if not U.is_canonical_id(value.get("semiconductor_material_id"), 2):
		return U.failure("INVALID_POWER_STAGE_PROFILE_MATERIAL_ID")
	if not U.is_lower_hex_64(value.get("semiconductor_material_checksum")):
		return U.failure("INVALID_POWER_STAGE_PROFILE_MATERIAL_CHECKSUM")
	for field in [
		"effective_on_resistivity_ohm_m", "max_current_density_a_m2", "transition_time_s",
		"reference_temperature_k", "min_temperature_k", "max_temperature_k", "max_bus_voltage_v"
	]:
		if not U.is_positive_number(value.get(field)):
			return U.failure("INVALID_POWER_STAGE_PROFILE_PROPERTY", {"field": field})
	if not U.is_non_negative_number(value.get("resistance_temp_coefficient_per_k")):
		return U.failure("INVALID_POWER_STAGE_PROFILE_TEMP_COEFFICIENT")
	if float(value.min_temperature_k) >= float(value.reference_temperature_k) or float(value.reference_temperature_k) >= float(value.max_temperature_k):
		return U.failure("POWER_STAGE_PROFILE_TEMPERATURE_ORDER_INVALID")
	return U.validate_checksum(value)

static func validate_against_material(value: Dictionary, material: Dictionary) -> Dictionary:
	var checked := validate(value)
	if not checked.success:
		return checked
	var matter = MatterMaterial.validate(material)
	if not bool(matter.get("success", false)):
		return U.failure("POWER_STAGE_PROFILE_MATTER_INVALID")
	if String(value.semiconductor_material_id) != String(material.material_id) or String(value.semiconductor_material_checksum) != String(material.checksum):
		return U.failure("POWER_STAGE_PROFILE_MATERIAL_BINDING_MISMATCH")
	return U.success()
