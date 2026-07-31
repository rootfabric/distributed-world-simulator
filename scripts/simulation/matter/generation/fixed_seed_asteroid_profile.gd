extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")

const SCHEMA: String = "planet_simulator.fixed_seed_asteroid_profile.v1"
const GENERATOR_ID: String = "matter-generator/fixed-seed-asteroid"
const GENERATOR_VERSION: String = "1.0.0"
const DEFAULT_SEED: int = 2026073101
const DEFAULT_RADIUS_M: float = 1000.0
const FIELDS: Array[String] = [
	"schema",
	"generator_id",
	"generator_version",
	"generator_seed",
	"reference_radius_m",
	"axis_scale",
	"root_bounds_radius_ratio",
	"surface_noise_frequencies_per_m",
	"surface_noise_amplitudes_m",
	"surface_regolith_depth_m",
	"fractured_shell_depth_m",
	"ore_max_mass_fraction",
	"ice_max_mass_fraction",
	"surface_temperature_k",
	"interior_temperature_k",
	"vacuum_temperature_k",
	"checksum",
]


static func create(data: Dictionary = {}) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"generator_id": String(data.get("generator_id", GENERATOR_ID)).strip_edges().to_lower(),
		"generator_version": String(data.get("generator_version", GENERATOR_VERSION)).strip_edges(),
		"generator_seed": int(data.get("generator_seed", DEFAULT_SEED)),
		"reference_radius_m": float(data.get("reference_radius_m", DEFAULT_RADIUS_M)),
		"axis_scale": _float_array(data.get("axis_scale", [1.12, 0.94, 1.04])),
		"root_bounds_radius_ratio": float(data.get("root_bounds_radius_ratio", 1.45)),
		"surface_noise_frequencies_per_m": _float_array(data.get(
			"surface_noise_frequencies_per_m", [0.00085, 0.0027, 0.0095]
		)),
		"surface_noise_amplitudes_m": _float_array(data.get(
			"surface_noise_amplitudes_m", [62.0, 24.0, 8.0]
		)),
		"surface_regolith_depth_m": float(data.get("surface_regolith_depth_m", 14.0)),
		"fractured_shell_depth_m": float(data.get("fractured_shell_depth_m", 72.0)),
		"ore_max_mass_fraction": float(data.get("ore_max_mass_fraction", 0.42)),
		"ice_max_mass_fraction": float(data.get("ice_max_mass_fraction", 0.34)),
		"surface_temperature_k": float(data.get("surface_temperature_k", 145.0)),
		"interior_temperature_k": float(data.get("interior_temperature_k", 235.0)),
		"vacuum_temperature_k": float(data.get("vacuum_temperature_k", 3.0)),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func default_profile() -> Dictionary:
	return create()


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_ASTEROID_PROFILE_SCHEMA")
	if String(value.get("generator_id", "")) != GENERATOR_ID:
		return MatterUtilsScript.failure("INVALID_ASTEROID_GENERATOR_ID")
	if String(value.get("generator_version", "")) != GENERATOR_VERSION:
		return MatterUtilsScript.failure("INVALID_ASTEROID_GENERATOR_VERSION")
	if not MatterUtilsScript.is_json_integer(value.get("generator_seed")):
		return MatterUtilsScript.failure("INVALID_ASTEROID_GENERATOR_SEED")
	if not MatterUtilsScript.is_positive_number(value.get("reference_radius_m")):
		return MatterUtilsScript.failure("INVALID_ASTEROID_REFERENCE_RADIUS")
	if not _is_positive_vector3(value.get("axis_scale")):
		return MatterUtilsScript.failure("INVALID_ASTEROID_AXIS_SCALE")
	if not MatterUtilsScript.is_positive_number(value.get("root_bounds_radius_ratio")) \
		or float(value["root_bounds_radius_ratio"]) <= 1.0 \
		or float(value["root_bounds_radius_ratio"]) > 2.5:
		return MatterUtilsScript.failure("INVALID_ASTEROID_ROOT_BOUNDS")
	if not _is_positive_number_array(value.get("surface_noise_frequencies_per_m"), 3):
		return MatterUtilsScript.failure("INVALID_ASTEROID_NOISE_FREQUENCIES")
	if not _is_non_negative_number_array(value.get("surface_noise_amplitudes_m"), 3):
		return MatterUtilsScript.failure("INVALID_ASTEROID_NOISE_AMPLITUDES")
	if not MatterUtilsScript.is_positive_number(value.get("surface_regolith_depth_m")) \
		or not MatterUtilsScript.is_positive_number(value.get("fractured_shell_depth_m")):
		return MatterUtilsScript.failure("INVALID_ASTEROID_SHELL_DEPTH")
	if float(value["surface_regolith_depth_m"]) >= float(value["fractured_shell_depth_m"]) \
		or float(value["fractured_shell_depth_m"]) >= float(value["reference_radius_m"]):
		return MatterUtilsScript.failure("INVALID_ASTEROID_SHELL_ORDER")
	for field in ["ore_max_mass_fraction", "ice_max_mass_fraction"]:
		if not MatterUtilsScript.is_ratio(value.get(field)):
			return MatterUtilsScript.failure("INVALID_ASTEROID_RESOURCE_FRACTION", {"field": field})
	if float(value["ore_max_mass_fraction"]) + float(value["ice_max_mass_fraction"]) > 0.85:
		return MatterUtilsScript.failure("ASTEROID_RESOURCE_FRACTIONS_TOO_LARGE")
	for field in ["surface_temperature_k", "interior_temperature_k", "vacuum_temperature_k"]:
		if not MatterUtilsScript.is_non_negative_number(value.get(field)):
			return MatterUtilsScript.failure("INVALID_ASTEROID_TEMPERATURE", {"field": field})
	if float(value["interior_temperature_k"]) < float(value["surface_temperature_k"]):
		return MatterUtilsScript.failure("INVALID_ASTEROID_TEMPERATURE_GRADIENT")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.fixed_seed_asteroid_profile")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return MatterUtilsScript.normalize(value, validate)


static func _float_array(raw) -> Array:
	var result: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return result
	for component in raw:
		result.append(float(component))
	return result


static func _is_positive_vector3(value) -> bool:
	return _is_positive_number_array(value, 3)


static func _is_positive_number_array(value, expected_size: int) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != expected_size:
		return false
	for component in value:
		if not MatterUtilsScript.is_positive_number(component):
			return false
	return true


static func _is_non_negative_number_array(value, expected_size: int) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != expected_size:
		return false
	for component in value:
		if not MatterUtilsScript.is_non_negative_number(component):
			return false
	return true
