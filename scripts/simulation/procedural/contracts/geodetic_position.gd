extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const SCHEMA: String = "planet_simulator.geodetic_position.v1"
const FIELDS: Array[String] = [
	"schema",
	"body_id",
	"latitude_deg",
	"longitude_deg",
	"altitude_m",
	"checksum",
]
const POLE_TOLERANCE_DEG: float = 0.000000000001


static func create(body_id: String, latitude_deg: float, longitude_deg: float, altitude_m: float) -> Dictionary:
	var canonical_longitude: float = longitude_deg
	if is_finite(longitude_deg):
		canonical_longitude = _canonical_longitude_deg(longitude_deg)
	if is_finite(latitude_deg) and absf(absf(latitude_deg) - 90.0) <= POLE_TOLERANCE_DEG:
		canonical_longitude = 0.0
	var value: Dictionary = {
		"schema": SCHEMA,
		"body_id": body_id,
		"latitude_deg": latitude_deg,
		"longitude_deg": canonical_longitude,
		"altitude_m": altitude_m,
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_GEODETIC_POSITION_SCHEMA")
	if not GeoUtilsScript.is_canonical_id(value.get("body_id"), 2):
		return GeoUtilsScript.failure("INVALID_GEODETIC_POSITION_BODY_ID")
	if not GeoUtilsScript.is_finite_number(value.get("latitude_deg")):
		return GeoUtilsScript.failure("INVALID_GEODETIC_LATITUDE")
	if not GeoUtilsScript.is_finite_number(value.get("longitude_deg")):
		return GeoUtilsScript.failure("INVALID_GEODETIC_LONGITUDE")
	if not GeoUtilsScript.is_finite_number(value.get("altitude_m")):
		return GeoUtilsScript.failure("INVALID_GEODETIC_ALTITUDE")
	var latitude: float = float(value["latitude_deg"])
	var longitude: float = float(value["longitude_deg"])
	if latitude < -90.0 or latitude > 90.0:
		return GeoUtilsScript.failure("GEODETIC_LATITUDE_OUT_OF_RANGE")
	if longitude < -180.0 or longitude >= 180.0:
		return GeoUtilsScript.failure("GEODETIC_LONGITUDE_NOT_CANONICAL")
	if absf(absf(latitude) - 90.0) <= POLE_TOLERANCE_DEG and absf(longitude) > POLE_TOLERANCE_DEG:
		return GeoUtilsScript.failure("GEODETIC_POLE_LONGITUDE_NOT_CANONICAL")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.geodetic_position")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)


static func _canonical_longitude_deg(longitude_deg: float) -> float:
	var canonical: float = fposmod(longitude_deg + 180.0, 360.0) - 180.0
	if absf(canonical) <= POLE_TOLERANCE_DEG:
		return 0.0
	return canonical
