extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MaterialLaw = preload("res://scripts/research/fabric_bake0/fabric_physics_r2_material_law_v1.gd")

const SCHEMA := "planet_simulator.fabric_physics_r2_model_contract.v1"
const DIMENSION_BASIS := ["kg", "m", "s", "A", "K", "mol", "cd"]
const EXECUTION_MODE_FULL := "FULL"
const EXECUTION_REASON := "PHYSICS_R2_TYPED_BAKE_NOT_CERTIFIED"

# SI base-dimension exponents in DIMENSION_BASIS order.
const MECHANICAL_DIMENSIONS := {
	"mass_kg": [1, 0, 0, 0, 0, 0, 0],
	"length_m": [0, 1, 0, 0, 0, 0, 0],
	"area_m2": [0, 2, 0, 0, 0, 0, 0],
	"youngs_modulus_pa": [1, -1, -2, 0, 0, 0, 0],
	"stiffness_n_per_m": [1, 0, -2, 0, 0, 0, 0],
	"damping_ns_per_m": [1, 0, -1, 0, 0, 0, 0],
	"capacity_n": [1, 1, -2, 0, 0, 0, 0],
	"force_n": [1, 1, -2, 0, 0, 0, 0],
	"displacement_m": [0, 1, 0, 0, 0, 0, 0],
	"energy_j": [1, 2, -2, 0, 0, 0, 0],
}
const ELECTRICAL_DIMENSIONS := {
	"length_m": [0, 1, 0, 0, 0, 0, 0],
	"area_m2": [0, 2, 0, 0, 0, 0, 0],
	"resistivity_ohm_m": [1, 3, -3, -2, 0, 0, 0],
	"resistance_ohm": [1, 2, -3, -2, 0, 0, 0],
	"conductance_siemens": [-1, -2, 3, 2, 0, 0, 0],
}

static func bind(model: Dictionary) -> Dictionary:
	var checksum_check := Utils.validate_checksum(model)
	if not checksum_check.success:
		return Utils.failure("PHYSICS_R2_MODEL_CHECKSUM_INVALID")
	var domain := String(model.get("domain", ""))
	var dimensions: Dictionary = {}
	match domain:
		MaterialLaw.DOMAIN_MECHANICAL_AXIAL:
			dimensions = MECHANICAL_DIMENSIONS.duplicate(true)
		MaterialLaw.DOMAIN_ELECTRICAL_RESISTIVE:
			dimensions = ELECTRICAL_DIMENSIONS.duplicate(true)
		_:
			return Utils.failure("PHYSICS_R2_MODEL_DOMAIN_UNSUPPORTED", {"domain": domain})

	var contract: Dictionary = {
		"schema": SCHEMA,
		"domain": domain,
		"model_checksum": String(model["checksum"]),
		"dimension_basis": DIMENSION_BASIS.duplicate(),
		"dimensions": dimensions,
		"execution_mode": EXECUTION_MODE_FULL,
		"bake_certified": false,
		"legacy_surrogate_compatible": false,
		"execution_reason": EXECUTION_REASON,
		"checksum": "",
	}
	contract["checksum"] = Utils.compute_checksum(contract)
	return Utils.success({"contract": contract})

static func validate(contract: Dictionary) -> Dictionary:
	var required := [
		"schema", "domain", "model_checksum", "dimension_basis", "dimensions",
		"execution_mode", "bake_certified", "legacy_surrogate_compatible",
		"execution_reason", "checksum",
	]
	var checked := Utils.validate_exact_fields(contract, required)
	if not checked.success:
		return checked
	if contract.get("schema") != SCHEMA:
		return Utils.failure("PHYSICS_R2_MODEL_CONTRACT_SCHEMA_UNSUPPORTED")
	if not [MaterialLaw.DOMAIN_MECHANICAL_AXIAL, MaterialLaw.DOMAIN_ELECTRICAL_RESISTIVE].has(String(contract.get("domain", ""))):
		return Utils.failure("PHYSICS_R2_MODEL_DOMAIN_UNSUPPORTED")
	if contract.get("dimension_basis") != DIMENSION_BASIS:
		return Utils.failure("PHYSICS_R2_DIMENSION_BASIS_INVALID")
	if typeof(contract.get("dimensions")) != TYPE_DICTIONARY or Dictionary(contract["dimensions"]).is_empty():
		return Utils.failure("PHYSICS_R2_DIMENSIONS_INVALID")
	if contract.get("execution_mode") != EXECUTION_MODE_FULL:
		return Utils.failure("PHYSICS_R2_EXECUTION_MODE_INVALID")
	if contract.get("bake_certified") != false:
		return Utils.failure("PHYSICS_R2_UNCERTIFIED_BAKE_FORBIDDEN")
	if contract.get("legacy_surrogate_compatible") != false:
		return Utils.failure("PHYSICS_R2_LEGACY_SURROGATE_FORBIDDEN")
	if contract.get("execution_reason") != EXECUTION_REASON:
		return Utils.failure("PHYSICS_R2_EXECUTION_REASON_INVALID")
	return Utils.validate_checksum(contract)
