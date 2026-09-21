extends RefCounted
## Characterized electromagnetic floor linked to canonical Matter materials.
## Generic Matter does not yet carry resistivity or magnetic remanence.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterMaterial = preload("res://scripts/simulation/matter/contracts/matter_material_definition.gd")

const SCHEMA := "planet_simulator.fabric_motor_electromagnetic_profile.v1"
const FIELDS: Array[String] = [
	"schema", "profile_id",
	"conductor_material_id", "conductor_material_checksum",
	"magnet_material_id", "magnet_material_checksum",
	"conductor_resistivity_ohm_m", "flux_density_t",
	"max_current_density_a_m2", "checksum",
]

static func create(
	profile_id: String,
	conductor_material: Dictionary,
	magnet_material: Dictionary,
	conductor_resistivity_ohm_m: float,
	flux_density_t: float,
	max_current_density_a_m2: float
) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"profile_id": profile_id,
		"conductor_material_id": String(conductor_material.get("material_id", "")),
		"conductor_material_checksum": String(conductor_material.get("checksum", "")),
		"magnet_material_id": String(magnet_material.get("material_id", "")),
		"magnet_material_checksum": String(magnet_material.get("checksum", "")),
		"conductor_resistivity_ohm_m": conductor_resistivity_ohm_m,
		"flux_density_t": flux_density_t,
		"max_current_density_a_m2": max_current_density_a_m2,
		"checksum": "",
	}
	value.checksum = U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA:
		return U.failure("UNSUPPORTED_MOTOR_EM_PROFILE_SCHEMA")
	if not U.is_canonical_id(value.get("profile_id"), 2):
		return U.failure("INVALID_MOTOR_EM_PROFILE_ID")
	for field in ["conductor_material_id", "magnet_material_id"]:
		if not U.is_canonical_id(value.get(field), 2):
			return U.failure("INVALID_MOTOR_EM_PROFILE_MATERIAL_ID", {"field": field})
	for field in ["conductor_material_checksum", "magnet_material_checksum"]:
		if not U.is_lower_hex_64(value.get(field)):
			return U.failure("INVALID_MOTOR_EM_PROFILE_MATERIAL_CHECKSUM", {"field": field})
	for field in ["conductor_resistivity_ohm_m", "flux_density_t", "max_current_density_a_m2"]:
		if not U.is_positive_number(value.get(field)):
			return U.failure("INVALID_MOTOR_EM_PROFILE_PROPERTY", {"field": field})
	return U.validate_checksum(value)

static func validate_against_materials(value: Dictionary, conductor: Dictionary, magnet: Dictionary) -> Dictionary:
	var checked := validate(value)
	if not checked.success:
		return checked
	var c = MatterMaterial.validate(conductor)
	var m = MatterMaterial.validate(magnet)
	if not bool(c.get("success", false)) or not bool(m.get("success", false)):
		return U.failure("MOTOR_EM_PROFILE_MATTER_INVALID")
	if String(value.conductor_material_id) != String(conductor.material_id) or String(value.conductor_material_checksum) != String(conductor.checksum):
		return U.failure("MOTOR_EM_PROFILE_CONDUCTOR_BINDING_MISMATCH")
	if String(value.magnet_material_id) != String(magnet.material_id) or String(value.magnet_material_checksum) != String(magnet.checksum):
		return U.failure("MOTOR_EM_PROFILE_MAGNET_BINDING_MISMATCH")
	return U.success()
