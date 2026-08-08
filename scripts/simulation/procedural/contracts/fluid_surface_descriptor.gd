extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FeatureBoundsScript = preload("res://scripts/simulation/procedural/contracts/feature_bounds.gd")
const FluidRegionIdScript = preload("res://scripts/simulation/procedural/contracts/fluid_region_id.gd")

const SCHEMA: String = "planet_simulator.fluid_surface_descriptor.v1"
const SURFACE_MODE_PREFIX: String = "fluid-surface-mode/"
const LOCAL_SPLINE: String = "fluid-surface-mode/local-spline"
const CONSTANT_LEVEL: String = "fluid-surface-mode/constant-level"
const FREE_SURFACE: String = "fluid-surface-mode/free-surface"
const FIELDS: Array[String] = [
	"schema",
	"fluid_region_id",
	"body_id",
	"frame_id",
	"fluid_type_id",
	"seed",
	"generator_version",
	"stable_key",
	"bounds",
	"surface_mode",
	"surface_parameters",
	"attributes",
	"checksum",
]


static func create(
	body_id: String,
	frame_id: String,
	fluid_type_id: String,
	seed: int,
	generator_version: String,
	stable_key: String,
	bounds: Dictionary,
	surface_mode: String,
	surface_parameters: Dictionary = {},
	attributes: Dictionary = {}
) -> Dictionary:
	var id_result: Dictionary = FluidRegionIdScript.derive(body_id, fluid_type_id, seed, generator_version, stable_key)
	var value: Dictionary = {
		"schema": SCHEMA,
		"fluid_region_id": String(id_result.get("details", {}).get("fluid_region_id", "")),
		"body_id": body_id,
		"frame_id": frame_id,
		"fluid_type_id": fluid_type_id,
		"seed": seed,
		"generator_version": generator_version,
		"stable_key": stable_key,
		"bounds": bounds.duplicate(true),
		"surface_mode": surface_mode,
		"surface_parameters": surface_parameters.duplicate(true),
		"attributes": attributes.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_FLUID_SURFACE_DESCRIPTOR_SCHEMA")
	if not GeoUtilsScript.is_canonical_id(value.get("body_id"), 2):
		return GeoUtilsScript.failure("INVALID_FLUID_SURFACE_BODY_ID")
	if not GeoUtilsScript.is_canonical_id(value.get("frame_id"), 2):
		return GeoUtilsScript.failure("INVALID_FLUID_SURFACE_FRAME_ID")
	if not GeoUtilsScript.is_canonical_id(value.get("fluid_type_id"), 2) or not String(value["fluid_type_id"]).begins_with(FluidRegionIdScript.FLUID_TYPE_PREFIX):
		return GeoUtilsScript.failure("INVALID_FLUID_TYPE_ID")
	if not GeoUtilsScript.is_json_integer(value.get("seed")):
		return GeoUtilsScript.failure("INVALID_FLUID_REGION_SEED")
	if not GeoUtilsScript.is_semantic_version(value.get("generator_version")):
		return GeoUtilsScript.failure("INVALID_FLUID_REGION_GENERATOR_VERSION")
	if not GeoUtilsScript.is_canonical_id(value.get("stable_key"), 2) or not String(value["stable_key"]).begins_with(FluidRegionIdScript.STABLE_KEY_PREFIX):
		return GeoUtilsScript.failure("INVALID_FLUID_REGION_STABLE_KEY")
	var id_result: Dictionary = FluidRegionIdScript.derive(
		String(value["body_id"]), String(value["fluid_type_id"]), int(value["seed"]),
		String(value["generator_version"]), String(value["stable_key"])
	)
	if not bool(id_result.get("success", false)) or String(value.get("fluid_region_id", "")) != String(id_result["details"]["fluid_region_id"]):
		return GeoUtilsScript.failure("FLUID_REGION_IDENTITY_MISMATCH")
	var bounds_value = value.get("bounds")
	if typeof(bounds_value) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_FLUID_SURFACE_BOUNDS")
	var bounds_validation: Dictionary = FeatureBoundsScript.validate(bounds_value)
	if not bool(bounds_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_FLUID_SURFACE_BOUNDS", {"cause": bounds_validation.get("error_code", "")})
	if String(bounds_value["frame_id"]) != String(value["frame_id"]):
		return GeoUtilsScript.failure("FLUID_SURFACE_BOUNDS_FRAME_MISMATCH")
	if not GeoUtilsScript.is_canonical_id(value.get("surface_mode"), 2) or not String(value["surface_mode"]).begins_with(SURFACE_MODE_PREFIX):
		return GeoUtilsScript.failure("INVALID_FLUID_SURFACE_MODE")
	if typeof(value.get("surface_parameters")) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_FLUID_SURFACE_PARAMETERS")
	if typeof(value.get("attributes")) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_FLUID_SURFACE_ATTRIBUTES")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.fluid_surface_descriptor")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)
