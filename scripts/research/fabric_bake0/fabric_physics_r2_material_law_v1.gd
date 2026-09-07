extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_physics_r2_material_law.v1"
const REFERENCE_TEMPERATURE_K := 293.15
const DOMAIN_MECHANICAL_AXIAL := "MECHANICAL_AXIAL"
const DOMAIN_ELECTRICAL_RESISTIVE := "ELECTRICAL_RESISTIVE"
const DOMAINS: Array[String] = [DOMAIN_ELECTRICAL_RESISTIVE, DOMAIN_MECHANICAL_AXIAL]
const FIELDS: Array[String] = [
	"schema", "law_id", "material_id", "domain", "reference_temperature_k",
	"parameters", "checksum",
]

# Nominal R2 model constants at the reference temperature. These values are
# intentionally explicit and versioned; PHYSICS-R2 does not invent defaults.
const YOUNGS_MODULUS_PA := {
	"material/aluminum": 6.90e10,
	"material/copper": 1.10e11,
	"material/rubber": 1.00e6,
	"material/steel": 2.00e11,
}
const RESISTIVITY_OHM_M := {
	"material/aluminum": 2.82e-8,
	"material/copper": 1.68e-8,
	"material/rubber": 1.00e13,
	"material/steel": 1.43e-7,
}

static func resolve(material_id: String, domain: String) -> Dictionary:
	var normalized_material := material_id.strip_edges().to_lower()
	if not Utils.is_canonical_id(normalized_material, 2):
		return Utils.failure("PHYSICS_R2_MATERIAL_ID_INVALID")
	if not DOMAINS.has(domain):
		return Utils.failure("PHYSICS_R2_MATERIAL_DOMAIN_UNSUPPORTED", {"domain": domain})

	var parameters: Dictionary = {}
	match domain:
		DOMAIN_MECHANICAL_AXIAL:
			if not YOUNGS_MODULUS_PA.has(normalized_material):
				return Utils.failure("PHYSICS_R2_MATERIAL_LAW_MISSING", {
					"material_id": normalized_material,
					"domain": domain,
				})
			parameters = {"youngs_modulus_pa": float(YOUNGS_MODULUS_PA[normalized_material])}
		DOMAIN_ELECTRICAL_RESISTIVE:
			if not RESISTIVITY_OHM_M.has(normalized_material):
				return Utils.failure("PHYSICS_R2_MATERIAL_LAW_MISSING", {
					"material_id": normalized_material,
					"domain": domain,
				})
			parameters = {"resistivity_ohm_m": float(RESISTIVITY_OHM_M[normalized_material])}

	var law: Dictionary = {
		"schema": SCHEMA,
		"law_id": _law_id(normalized_material, domain),
		"material_id": normalized_material,
		"domain": domain,
		"reference_temperature_k": REFERENCE_TEMPERATURE_K,
		"parameters": parameters,
		"checksum": "",
	}
	law["checksum"] = Utils.compute_checksum(law)
	var checked := validate(law)
	if not checked.success:
		return checked
	return Utils.success({"law": law})

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("PHYSICS_R2_MATERIAL_LAW_SCHEMA_UNSUPPORTED")
	if not Utils.is_canonical_id(value.get("law_id"), 3):
		return Utils.failure("PHYSICS_R2_MATERIAL_LAW_ID_INVALID")
	if not Utils.is_canonical_id(value.get("material_id"), 2):
		return Utils.failure("PHYSICS_R2_MATERIAL_ID_INVALID")
	if typeof(value.get("domain")) != TYPE_STRING or not DOMAINS.has(String(value["domain"])):
		return Utils.failure("PHYSICS_R2_MATERIAL_DOMAIN_UNSUPPORTED")
	if not Utils.is_positive_number(value.get("reference_temperature_k")):
		return Utils.failure("PHYSICS_R2_REFERENCE_TEMPERATURE_INVALID")
	if not _near(float(value["reference_temperature_k"]), REFERENCE_TEMPERATURE_K, 1.0e-12):
		return Utils.failure("PHYSICS_R2_REFERENCE_TEMPERATURE_MISMATCH")
	if typeof(value.get("parameters")) != TYPE_DICTIONARY:
		return Utils.failure("PHYSICS_R2_MATERIAL_PARAMETERS_INVALID")

	var parameters: Dictionary = value["parameters"]
	match String(value["domain"]):
		DOMAIN_MECHANICAL_AXIAL:
			if parameters.keys() != ["youngs_modulus_pa"] or not Utils.is_positive_number(parameters.get("youngs_modulus_pa")):
				return Utils.failure("PHYSICS_R2_MECHANICAL_LAW_INVALID")
		DOMAIN_ELECTRICAL_RESISTIVE:
			if parameters.keys() != ["resistivity_ohm_m"] or not Utils.is_positive_number(parameters.get("resistivity_ohm_m")):
				return Utils.failure("PHYSICS_R2_ELECTRICAL_LAW_INVALID")

	return Utils.validate_checksum(value)

static func _law_id(material_id: String, domain: String) -> String:
	var material_slug := material_id.trim_prefix("material/").replace("_", "-")
	return "law/physics-r2/%s/%s" % [material_slug, domain.to_lower().replace("_", "-")]

static func _near(left: float, right: float, rel_tol: float) -> bool:
	if not is_finite(left) or not is_finite(right):
		return false
	return absf(left - right) <= rel_tol * maxf(1.0, maxf(absf(left), absf(right)))
