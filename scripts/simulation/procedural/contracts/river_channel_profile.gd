extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const SCHEMA: String = "planet_simulator.river_channel_profile.v1"
const FIELDS: Array[String] = [
	"schema",
	"width_source_m",
	"width_mouth_m",
	"depth_source_m",
	"depth_mouth_m",
	"flow_speed_source_mps",
	"flow_speed_mouth_mps",
	"bank_falloff_m",
	"checksum",
]


static func create(
	width_source_m: float,
	width_mouth_m: float,
	depth_source_m: float,
	depth_mouth_m: float,
	flow_speed_source_mps: float,
	flow_speed_mouth_mps: float,
	bank_falloff_m: float
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"width_source_m": width_source_m,
		"width_mouth_m": width_mouth_m,
		"depth_source_m": depth_source_m,
		"depth_mouth_m": depth_mouth_m,
		"flow_speed_source_mps": flow_speed_source_mps,
		"flow_speed_mouth_mps": flow_speed_mouth_mps,
		"bank_falloff_m": bank_falloff_m,
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_RIVER_CHANNEL_PROFILE_SCHEMA")
	for field in ["width_source_m", "width_mouth_m", "depth_source_m", "depth_mouth_m"]:
		if not GeoUtilsScript.is_positive_number(value.get(field)):
			return GeoUtilsScript.failure("INVALID_RIVER_CHANNEL_POSITIVE_FIELD", {"field": field})
	for field in ["flow_speed_source_mps", "flow_speed_mouth_mps", "bank_falloff_m"]:
		if not GeoUtilsScript.is_non_negative_number(value.get(field)):
			return GeoUtilsScript.failure("INVALID_RIVER_CHANNEL_NON_NEGATIVE_FIELD", {"field": field})
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.river_channel_profile")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func sample(value: Dictionary, normalized_distance: float) -> Dictionary:
	var validation: Dictionary = validate(value)
	if not bool(validation.get("success", false)):
		return validation
	if not is_finite(normalized_distance) or normalized_distance < 0.0 or normalized_distance > 1.0:
		return GeoUtilsScript.failure("RIVER_CHANNEL_SAMPLE_OUT_OF_RANGE")
	return GeoUtilsScript.success({
		"normalized_distance": normalized_distance,
		"width_m": lerpf(float(value["width_source_m"]), float(value["width_mouth_m"]), normalized_distance),
		"depth_m": lerpf(float(value["depth_source_m"]), float(value["depth_mouth_m"]), normalized_distance),
		"flow_speed_mps": lerpf(float(value["flow_speed_source_mps"]), float(value["flow_speed_mouth_mps"]), normalized_distance),
		"bank_falloff_m": float(value["bank_falloff_m"]),
	})
