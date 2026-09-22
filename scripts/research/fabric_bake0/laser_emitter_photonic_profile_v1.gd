extends RefCounted
## Characterized photonic floor linked to canonical active-semiconductor Matter.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterMaterial = preload("res://scripts/simulation/matter/contracts/matter_material_definition.gd")

const PLANCK_J_S := 6.62607015e-34
const LIGHT_SPEED_M_S := 299792458.0
const ELEMENTARY_CHARGE_C := 1.602176634e-19

const SCHEMA := "planet_simulator.fabric_laser_emitter_photonic_profile.v1"
const FIELDS: Array[String] = [
	"schema", "profile_id", "active_material_id", "active_material_checksum",
	"threshold_current_density_a_m2", "max_current_density_a_m2",
	"effective_resistivity_ohm_m", "forward_voltage_v",
	"reference_optical_efficiency_ratio", "efficiency_temp_coefficient_per_k",
	"reference_temperature_k", "min_temperature_k", "max_temperature_k",
	"wavelength_m", "beam_quality_m2", "checksum",
]

static func create(
	profile_id: String,
	active_material: Dictionary,
	threshold_current_density_a_m2: float,
	max_current_density_a_m2: float,
	effective_resistivity_ohm_m: float,
	forward_voltage_v: float,
	reference_optical_efficiency_ratio: float,
	efficiency_temp_coefficient_per_k: float,
	reference_temperature_k: float,
	min_temperature_k: float,
	max_temperature_k: float,
	wavelength_m: float,
	beam_quality_m2: float
) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"profile_id": profile_id,
		"active_material_id": String(active_material.get("material_id", "")),
		"active_material_checksum": String(active_material.get("checksum", "")),
		"threshold_current_density_a_m2": threshold_current_density_a_m2,
		"max_current_density_a_m2": max_current_density_a_m2,
		"effective_resistivity_ohm_m": effective_resistivity_ohm_m,
		"forward_voltage_v": forward_voltage_v,
		"reference_optical_efficiency_ratio": reference_optical_efficiency_ratio,
		"efficiency_temp_coefficient_per_k": efficiency_temp_coefficient_per_k,
		"reference_temperature_k": reference_temperature_k,
		"min_temperature_k": min_temperature_k,
		"max_temperature_k": max_temperature_k,
		"wavelength_m": wavelength_m,
		"beam_quality_m2": beam_quality_m2,
		"checksum": "",
	}
	value.checksum = U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA:
		return U.failure("UNSUPPORTED_LASER_PHOTONIC_PROFILE_SCHEMA")
	if not U.is_canonical_id(value.get("profile_id"), 2):
		return U.failure("INVALID_LASER_PHOTONIC_PROFILE_ID")
	if not U.is_canonical_id(value.get("active_material_id"), 2):
		return U.failure("INVALID_LASER_PHOTONIC_MATERIAL_ID")
	if not U.is_lower_hex_64(value.get("active_material_checksum")):
		return U.failure("INVALID_LASER_PHOTONIC_MATERIAL_CHECKSUM")
	for field in [
		"threshold_current_density_a_m2", "max_current_density_a_m2",
		"effective_resistivity_ohm_m", "forward_voltage_v",
		"reference_temperature_k", "min_temperature_k", "max_temperature_k",
		"wavelength_m", "beam_quality_m2"
	]:
		if not U.is_positive_number(value.get(field)):
			return U.failure("INVALID_LASER_PHOTONIC_PROFILE_PROPERTY", {"field": field})
	if float(value.max_current_density_a_m2) <= float(value.threshold_current_density_a_m2):
		return U.failure("LASER_PHOTONIC_CURRENT_DENSITY_ORDER_INVALID")
	if not U.is_positive_number(value.get("reference_optical_efficiency_ratio")) or float(value.reference_optical_efficiency_ratio) >= 1.0:
		return U.failure("INVALID_LASER_PHOTONIC_EFFICIENCY")
	if not U.is_non_negative_number(value.get("efficiency_temp_coefficient_per_k")):
		return U.failure("INVALID_LASER_PHOTONIC_TEMP_COEFFICIENT")
	if float(value.min_temperature_k) >= float(value.reference_temperature_k) or float(value.reference_temperature_k) >= float(value.max_temperature_k):
		return U.failure("LASER_PHOTONIC_TEMPERATURE_ORDER_INVALID")
	if float(value.beam_quality_m2) < 1.0:
		return U.failure("LASER_PHOTONIC_BEAM_QUALITY_INVALID")
	var photon_voltage := PLANCK_J_S * LIGHT_SPEED_M_S / (float(value.wavelength_m) * ELEMENTARY_CHARGE_C)
	var reference_quantum_yield := float(value.reference_optical_efficiency_ratio) * float(value.forward_voltage_v) / photon_voltage
	if reference_quantum_yield > 1.0 + 1.0e-12:
		return U.failure("LASER_PHOTONIC_QUANTUM_YIELD_UNSAFE", {"reference_quantum_yield": reference_quantum_yield})
	return U.validate_checksum(value)

static func validate_against_material(value: Dictionary, material: Dictionary) -> Dictionary:
	var checked := validate(value)
	if not checked.success:
		return checked
	var matter = MatterMaterial.validate(material)
	if not bool(matter.get("success", false)):
		return U.failure("LASER_PHOTONIC_MATTER_INVALID")
	if String(value.active_material_id) != String(material.material_id) or String(value.active_material_checksum) != String(material.checksum):
		return U.failure("LASER_PHOTONIC_MATERIAL_BINDING_MISMATCH")
	if float(value.max_temperature_k) >= float(material.melting_temperature_k):
		return U.failure("LASER_PHOTONIC_PROFILE_EXCEEDS_MATERIAL_DOMAIN")
	return U.success()
