extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CompositionScript = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")

const SCHEMA: String = "planet_simulator.matter_sample.v1"
const FIELDS: Array[String] = [
	"schema",
	"signed_distance_m",
	"occupancy_ratio",
	"density_kg_m3",
	"composition",
	"integrity_ratio",
	"temperature_k",
	"porosity_ratio",
	"flags",
	"checksum",
]
const SURFACE_EPSILON_M: float = 0.000000001


static func create(
	signed_distance_m: float,
	occupancy_ratio: float,
	density_kg_m3: float,
	composition: Dictionary,
	integrity_ratio: float,
	temperature_k: float,
	porosity_ratio: float,
	flags: Array = []
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"signed_distance_m": signed_distance_m,
		"occupancy_ratio": occupancy_ratio,
		"density_kg_m3": density_kg_m3,
		"composition": composition.duplicate(true),
		"integrity_ratio": integrity_ratio,
		"temperature_k": temperature_k,
		"porosity_ratio": porosity_ratio,
		"flags": MatterUtilsScript.sorted_unique_ids(flags),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func vacuum(signed_distance_m: float, temperature_k: float = 0.0) -> Dictionary:
	return create(
		maxf(signed_distance_m, 0.0),
		0.0,
		0.0,
		CompositionScript.empty(),
		0.0,
		temperature_k,
		0.0,
		["matter-state/vacuum"]
	)


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_SAMPLE_SCHEMA")
	if not MatterUtilsScript.is_finite_number(value.get("signed_distance_m")):
		return MatterUtilsScript.failure("INVALID_SIGNED_DISTANCE")
	for field in ["occupancy_ratio", "integrity_ratio", "porosity_ratio"]:
		if not MatterUtilsScript.is_ratio(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_SAMPLE_RATIO", {"field": field})
	for field in ["density_kg_m3", "temperature_k"]:
		if not MatterUtilsScript.is_non_negative_number(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_SAMPLE_PROPERTY", {"field": field})
	if typeof(value.get("composition")) != TYPE_DICTIONARY \
		or not bool(CompositionScript.validate(value["composition"]).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_SAMPLE_COMPOSITION")
	var flags: Dictionary = MatterUtilsScript.validate_sorted_unique_ids(value.get("flags"), true)
	if not bool(flags.get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_SAMPLE_FLAGS")
	var occupancy: float = float(value["occupancy_ratio"])
	var distance: float = float(value["signed_distance_m"])
	var empty_composition: bool = CompositionScript.is_empty(value["composition"])
	if occupancy <= 0.0:
		if float(value["density_kg_m3"]) != 0.0 or not empty_composition or float(value["integrity_ratio"]) != 0.0:
			return MatterUtilsScript.failure("VACUUM_SAMPLE_CONTAINS_MATTER")
		if distance < -SURFACE_EPSILON_M:
			return MatterUtilsScript.failure("VACUUM_SAMPLE_INSIDE_SURFACE")
	else:
		if float(value["density_kg_m3"]) <= 0.0 or empty_composition:
			return MatterUtilsScript.failure("OCCUPIED_SAMPLE_MISSING_MATTER")
		if distance > SURFACE_EPSILON_M:
			return MatterUtilsScript.failure("OCCUPIED_SAMPLE_OUTSIDE_SURFACE")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_sample")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return MatterUtilsScript.normalize(value, validate)
