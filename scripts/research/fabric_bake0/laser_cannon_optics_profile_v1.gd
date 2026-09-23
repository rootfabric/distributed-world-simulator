extends RefCounted
## Characterized optical-surface floor bound to canonical Matter.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterMaterial = preload("res://scripts/simulation/matter/contracts/matter_material_definition.gd")

const SCHEMA := "planet_simulator.fabric_laser_cannon_optics_profile.v1"
const FIELDS: Array[String] = [
	"schema", "profile_id", "optical_material_id", "optical_material_checksum",
	"surface_transmission_ratio", "max_surface_fluence_j_m2",
	"min_temperature_k", "max_temperature_k", "checksum",
]

static func create(
	profile_id: String,
	material: Dictionary,
	surface_transmission_ratio: float,
	max_surface_fluence_j_m2: float,
	min_temperature_k: float,
	max_temperature_k: float
) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"profile_id": profile_id,
		"optical_material_id": String(material.get("material_id", "")),
		"optical_material_checksum": String(material.get("checksum", "")),
		"surface_transmission_ratio": surface_transmission_ratio,
		"max_surface_fluence_j_m2": max_surface_fluence_j_m2,
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
		return U.failure("UNSUPPORTED_LASER_CANNON_OPTICS_PROFILE_SCHEMA")
	if not U.is_canonical_id(value.get("profile_id"), 2) or not U.is_canonical_id(value.get("optical_material_id"), 2):
		return U.failure("INVALID_LASER_CANNON_OPTICS_PROFILE_ID")
	if not U.is_lower_hex_64(value.get("optical_material_checksum")):
		return U.failure("INVALID_LASER_CANNON_OPTICS_MATERIAL_CHECKSUM")
	if not U.is_positive_number(value.get("surface_transmission_ratio")) or float(value.surface_transmission_ratio) >= 1.0:
		return U.failure("INVALID_LASER_CANNON_OPTICS_TRANSMISSION")
	for field in ["max_surface_fluence_j_m2", "min_temperature_k", "max_temperature_k"]:
		if not U.is_positive_number(value.get(field)):
			return U.failure("INVALID_LASER_CANNON_OPTICS_PROFILE_PROPERTY", {"field":field})
	if float(value.min_temperature_k) >= float(value.max_temperature_k):
		return U.failure("LASER_CANNON_OPTICS_TEMPERATURE_DOMAIN_EMPTY")
	return U.validate_checksum(value)

static func validate_against_material(value: Dictionary, material: Dictionary) -> Dictionary:
	var checked := validate(value)
	if not checked.success:
		return checked
	var matter = MatterMaterial.validate(material)
	if not bool(matter.get("success", false)):
		return U.failure("LASER_CANNON_OPTICS_MATTER_INVALID")
	if String(value.optical_material_id) != String(material.material_id) or String(value.optical_material_checksum) != String(material.checksum):
		return U.failure("LASER_CANNON_OPTICS_MATERIAL_BINDING_MISMATCH")
	if float(value.max_temperature_k) >= float(material.melting_temperature_k):
		return U.failure("LASER_CANNON_OPTICS_PROFILE_EXCEEDS_MATERIAL_DOMAIN")
	return U.success()
