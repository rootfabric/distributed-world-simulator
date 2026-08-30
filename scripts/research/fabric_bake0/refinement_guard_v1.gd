extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_refinement_guard.v1"
const FIELDS: Array[String] = [
	"schema", "guard_id", "observed_boundary_quantities", "conservative_bound",
	"trigger_threshold", "mapped_source_region", "required_refinement_level",
	"uncertainty_margin", "checksum",
]

static func create(
	guard_id: String, observed_boundary_quantities: Array, conservative_bound: float,
	trigger_threshold: float, mapped_source_region: String,
	required_refinement_level: int, uncertainty_margin: float
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"guard_id": guard_id,
		"observed_boundary_quantities": Utils.sorted_strings(observed_boundary_quantities),
		"conservative_bound": conservative_bound,
		"trigger_threshold": trigger_threshold,
		"mapped_source_region": mapped_source_region,
		"required_refinement_level": required_refinement_level,
		"uncertainty_margin": uncertainty_margin,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_REFINEMENT_GUARD_SCHEMA")
	if not Utils.is_canonical_id(value.get("guard_id"), 2):
		return Utils.failure("INVALID_REFINEMENT_GUARD_ID")
	checked = Utils.validate_sorted_unique_strings(value.get("observed_boundary_quantities"), false)
	if not bool(checked.get("success", false)):
		return checked
	for quantity_id in value["observed_boundary_quantities"]:
		if not Utils.is_canonical_id(quantity_id, 2):
			return Utils.failure("INVALID_REFINEMENT_GUARD_QUANTITY")
	if not Utils.is_positive_number(value.get("conservative_bound")) or not Utils.is_non_negative_number(value.get("trigger_threshold")):
		return Utils.failure("INVALID_REFINEMENT_GUARD_BOUND")
	if not Utils.is_non_negative_number(value.get("uncertainty_margin")):
		return Utils.failure("INVALID_REFINEMENT_GUARD_UNCERTAINTY")
	if float(value["trigger_threshold"]) + float(value["uncertainty_margin"]) > float(value["conservative_bound"]):
		return Utils.failure("REFINEMENT_GUARD_NOT_CONSERVATIVE")
	if not Utils.is_canonical_id(value.get("mapped_source_region"), 2):
		return Utils.failure("INVALID_REFINEMENT_GUARD_REGION")
	if not Utils.is_json_integer(value.get("required_refinement_level")) or int(value["required_refinement_level"]) < 1:
		return Utils.failure("INVALID_REFINEMENT_GUARD_LEVEL")
	return Utils.validate_checksum(value)

static func evaluate(value: Dictionary, guard_values: Dictionary) -> Dictionary:
	var checked := validate(value)
	if not bool(checked.get("success", false)):
		return checked
	var guard_id := String(value["guard_id"])
	if not guard_values.has(guard_id) or not Utils.is_non_negative_number(guard_values[guard_id]):
		return Utils.failure("BAKE_REFINEMENT_GUARD_UNOBSERVED", {"guard_id": guard_id})
	var observed := float(guard_values[guard_id])
	var trigger := float(value["trigger_threshold"])
	var uncertainty := float(value["uncertainty_margin"])
	if observed + uncertainty >= trigger:
		return Utils.failure("BAKE_REFINEMENT_REQUIRED", {
			"guard_id": guard_id,
			"mapped_source_region": value["mapped_source_region"],
			"required_refinement_level": value["required_refinement_level"],
		})
	return Utils.success({"remaining_guard_margin": trigger - observed - uncertainty})
