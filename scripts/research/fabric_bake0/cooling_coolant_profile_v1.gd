extends RefCounted
## Characterized coolant properties absent from generic Matter: dynamic viscosity and external convection floor.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterMaterial = preload("res://scripts/simulation/matter/contracts/matter_material_definition.gd")

const SCHEMA := "planet_simulator.fabric_cooling_coolant_profile.v1"
const FIELDS: Array[String] = [
	"schema", "profile_id", "coolant_material_id", "coolant_material_checksum",
	"dynamic_viscosity_pa_s", "ambient_heat_transfer_coefficient_w_m2_k",
	"laminar_reynolds_limit", "checksum",
]

static func create(
	profile_id: String,
	coolant_material: Dictionary,
	dynamic_viscosity_pa_s: float,
	ambient_heat_transfer_coefficient_w_m2_k: float,
	laminar_reynolds_limit: float
) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"profile_id": profile_id,
		"coolant_material_id": String(coolant_material.get("material_id", "")),
		"coolant_material_checksum": String(coolant_material.get("checksum", "")),
		"dynamic_viscosity_pa_s": dynamic_viscosity_pa_s,
		"ambient_heat_transfer_coefficient_w_m2_k": ambient_heat_transfer_coefficient_w_m2_k,
		"laminar_reynolds_limit": laminar_reynolds_limit,
		"checksum": "",
	}
	value.checksum = U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA:
		return U.failure("UNSUPPORTED_COOLING_COOLANT_PROFILE_SCHEMA")
	if not U.is_canonical_id(value.get("profile_id"), 2):
		return U.failure("INVALID_COOLING_COOLANT_PROFILE_ID")
	if not U.is_canonical_id(value.get("coolant_material_id"), 2):
		return U.failure("INVALID_COOLING_COOLANT_MATERIAL_ID")
	if not U.is_lower_hex_64(value.get("coolant_material_checksum")):
		return U.failure("INVALID_COOLING_COOLANT_MATERIAL_CHECKSUM")
	for field in ["dynamic_viscosity_pa_s", "ambient_heat_transfer_coefficient_w_m2_k", "laminar_reynolds_limit"]:
		if not U.is_positive_number(value.get(field)):
			return U.failure("INVALID_COOLING_COOLANT_PROFILE_PROPERTY", {"field": field})
	if float(value.laminar_reynolds_limit) > 2300.0:
		return U.failure("COOLING_COOLANT_PROFILE_LAMINAR_LIMIT_TOO_HIGH")
	return U.validate_checksum(value)

static func validate_against_material(value: Dictionary, material: Dictionary) -> Dictionary:
	var checked := validate(value)
	if not checked.success:
		return checked
	var matter = MatterMaterial.validate(material)
	if not bool(matter.get("success", false)):
		return U.failure("COOLING_COOLANT_PROFILE_MATTER_INVALID")
	if String(material.get("phase", "")) != "LIQUID":
		return U.failure("COOLING_COOLANT_MATERIAL_NOT_LIQUID")
	if String(value.coolant_material_id) != String(material.material_id) or String(value.coolant_material_checksum) != String(material.checksum):
		return U.failure("COOLING_COOLANT_PROFILE_MATERIAL_BINDING_MISMATCH")
	return U.success()
