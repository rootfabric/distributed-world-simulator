extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const PlanetDefinitionScript = preload("res://scripts/simulation/procedural/contracts/planet_definition.gd")
const BodyFixedPositionScript = preload("res://scripts/simulation/procedural/contracts/body_fixed_position.gd")
const GeodeticPositionScript = preload("res://scripts/simulation/procedural/contracts/geodetic_position.gd")
const LocalTangentFrameScript = preload("res://scripts/simulation/procedural/contracts/local_tangent_frame.gd")

const MIN_AXIS_LENGTH_SQUARED: float = 0.000000000000000001
const UNIT_TOLERANCE: float = 0.00000001

var _configured: bool = false
var _planet_definition: Dictionary = {}
var _body_shape_provider = null
var _body_shape_manifest_hash: String = ""


func configure(planet_definition: Dictionary, body_shape_provider) -> Dictionary:
	_clear()
	var definition_validation: Dictionary = PlanetDefinitionScript.validate(planet_definition)
	if not bool(definition_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_GEODESY_PLANET_DEFINITION", {"cause": definition_validation.get("error_code", "")})
	if body_shape_provider == null or not body_shape_provider is RefCounted:
		return GeoUtilsScript.failure("INVALID_BODY_SHAPE_PROVIDER")
	for method in [
		"get_shape_id",
		"get_contract_version",
		"get_generator_version",
		"is_deterministic",
		"supports_planet_definition",
		"body_to_geodetic",
		"geodetic_to_body",
		"surface_normal",
		"altitude",
	]:
		if not body_shape_provider.has_method(method):
			return GeoUtilsScript.failure("INVALID_BODY_SHAPE_PROVIDER", {"missing_method": method})
	var shape_id = body_shape_provider.get_shape_id()
	var contract_version = body_shape_provider.get_contract_version()
	var generator_version = body_shape_provider.get_generator_version()
	if not GeoUtilsScript.is_canonical_id(shape_id, 2):
		return GeoUtilsScript.failure("INVALID_BODY_SHAPE_PROVIDER_ID")
	if String(shape_id) != String(planet_definition["body_shape_id"]):
		return GeoUtilsScript.failure("BODY_SHAPE_ID_MISMATCH")
	if not GeoUtilsScript.is_semantic_version(contract_version):
		return GeoUtilsScript.failure("INVALID_BODY_SHAPE_CONTRACT_VERSION")
	if not GeoUtilsScript.is_semantic_version(generator_version):
		return GeoUtilsScript.failure("INVALID_BODY_SHAPE_GENERATOR_VERSION")
	if not bool(body_shape_provider.is_deterministic()):
		return GeoUtilsScript.failure("NON_DETERMINISTIC_BODY_SHAPE_PROVIDER")
	if not bool(body_shape_provider.supports_planet_definition(planet_definition)):
		return GeoUtilsScript.failure("BODY_SHAPE_PROVIDER_REJECTED_PLANET")
	var manifest_payload: Dictionary = {
		"body_id": planet_definition["body_id"],
		"body_shape_id": shape_id,
		"contract_version": contract_version,
		"generator_version": generator_version,
		"planet_definition_checksum": planet_definition["checksum"],
	}
	var manifest_hash: String = GeoUtilsScript.payload_hash(manifest_payload)
	if manifest_hash.is_empty():
		return GeoUtilsScript.failure("INVALID_BODY_SHAPE_MANIFEST_HASH")
	_planet_definition = planet_definition.duplicate(true)
	_body_shape_provider = body_shape_provider
	_body_shape_manifest_hash = manifest_hash
	_configured = true
	return GeoUtilsScript.success({
		"body_shape_id": String(shape_id),
		"body_shape_manifest_hash": manifest_hash,
	})


func is_configured() -> bool:
	return _configured


func get_body_shape_manifest_hash() -> String:
	return _body_shape_manifest_hash


func get_planet_definition() -> Dictionary:
	return _planet_definition.duplicate(true)


func body_to_geodetic(body_fixed_position: Dictionary) -> Dictionary:
	var input_validation: Dictionary = _validate_body_position(body_fixed_position)
	if not bool(input_validation.get("success", false)):
		return input_validation
	var provider_result = _body_shape_provider.body_to_geodetic(_planet_definition, Array(body_fixed_position["position_m"]))
	if not provider_result is Dictionary or not bool(provider_result.get("success", false)):
		return _provider_failure(provider_result)
	var raw_details = provider_result.get("details", {})
	if not raw_details is Dictionary:
		return GeoUtilsScript.failure("INVALID_BODY_SHAPE_PROVIDER_RESPONSE")
	var details: Dictionary = raw_details
	for field in ["latitude_deg", "longitude_deg", "altitude_m"]:
		if not GeoUtilsScript.is_finite_number(details.get(field)):
			return GeoUtilsScript.failure("INVALID_BODY_SHAPE_PROVIDER_RESPONSE", {"field": field})
	var geodetic: Dictionary = GeodeticPositionScript.create(
		String(_planet_definition["body_id"]),
		float(details["latitude_deg"]),
		float(details["longitude_deg"]),
		float(details["altitude_m"])
	)
	var validation: Dictionary = GeodeticPositionScript.validate(geodetic)
	if not bool(validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_GEODETIC_RESULT", {"cause": validation.get("error_code", "")})
	return GeoUtilsScript.success({
		"geodetic_position": geodetic,
		"body_shape_manifest_hash": _body_shape_manifest_hash,
	})


func geodetic_to_body(geodetic_position: Dictionary) -> Dictionary:
	var input_validation: Dictionary = _validate_geodetic_position(geodetic_position)
	if not bool(input_validation.get("success", false)):
		return input_validation
	var provider_result = _body_shape_provider.geodetic_to_body(
		_planet_definition,
		float(geodetic_position["latitude_deg"]),
		float(geodetic_position["longitude_deg"]),
		float(geodetic_position["altitude_m"])
	)
	if not provider_result is Dictionary or not bool(provider_result.get("success", false)):
		return _provider_failure(provider_result)
	var raw_details = provider_result.get("details", {})
	if not raw_details is Dictionary or not GeoUtilsScript.is_vector3_array(raw_details.get("position_m")):
		return GeoUtilsScript.failure("INVALID_BODY_SHAPE_PROVIDER_RESPONSE")
	var body_fixed: Dictionary = BodyFixedPositionScript.create(String(_planet_definition["body_id"]), Array(raw_details["position_m"]))
	var validation: Dictionary = BodyFixedPositionScript.validate(body_fixed)
	if not bool(validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_BODY_FIXED_RESULT", {"cause": validation.get("error_code", "")})
	return GeoUtilsScript.success({
		"body_fixed_position": body_fixed,
		"body_shape_manifest_hash": _body_shape_manifest_hash,
	})


func surface_normal(body_fixed_position: Dictionary) -> Dictionary:
	var input_validation: Dictionary = _validate_body_position(body_fixed_position)
	if not bool(input_validation.get("success", false)):
		return input_validation
	var provider_result = _body_shape_provider.surface_normal(_planet_definition, Array(body_fixed_position["position_m"]))
	if not provider_result is Dictionary or not bool(provider_result.get("success", false)):
		return _provider_failure(provider_result)
	var raw_details = provider_result.get("details", {})
	if not raw_details is Dictionary or not GeoUtilsScript.is_vector3_array(raw_details.get("normal")):
		return GeoUtilsScript.failure("INVALID_BODY_SHAPE_PROVIDER_RESPONSE")
	var normal: Vector3 = _vector3(Array(raw_details["normal"]))
	if absf(normal.length() - 1.0) > UNIT_TOLERANCE:
		return GeoUtilsScript.failure("BODY_SHAPE_NORMAL_NOT_UNIT")
	return GeoUtilsScript.success({
		"normal": _array3(normal),
		"body_shape_manifest_hash": _body_shape_manifest_hash,
	})


func altitude(body_fixed_position: Dictionary) -> Dictionary:
	var input_validation: Dictionary = _validate_body_position(body_fixed_position)
	if not bool(input_validation.get("success", false)):
		return input_validation
	var provider_result = _body_shape_provider.altitude(_planet_definition, Array(body_fixed_position["position_m"]))
	if not provider_result is Dictionary or not bool(provider_result.get("success", false)):
		return _provider_failure(provider_result)
	var raw_details = provider_result.get("details", {})
	if not raw_details is Dictionary or not GeoUtilsScript.is_finite_number(raw_details.get("altitude_m")):
		return GeoUtilsScript.failure("INVALID_BODY_SHAPE_PROVIDER_RESPONSE")
	return GeoUtilsScript.success({
		"altitude_m": float(raw_details["altitude_m"]),
		"body_shape_manifest_hash": _body_shape_manifest_hash,
	})


func local_tangent_frame(body_fixed_position: Dictionary) -> Dictionary:
	var geodetic_result: Dictionary = body_to_geodetic(body_fixed_position)
	if not bool(geodetic_result.get("success", false)):
		return geodetic_result
	var normal_result: Dictionary = surface_normal(body_fixed_position)
	if not bool(normal_result.get("success", false)):
		return normal_result
	var geodetic: Dictionary = geodetic_result["details"]["geodetic_position"]
	var up: Vector3 = _vector3(Array(normal_result["details"]["normal"]))
	var longitude_rad: float = deg_to_rad(float(geodetic["longitude_deg"]))
	var reference_east: Vector3 = Vector3(-sin(longitude_rad), 0.0, cos(longitude_rad))
	var east: Vector3 = reference_east - up * reference_east.dot(up)
	if east.length_squared() <= MIN_AXIS_LENGTH_SQUARED:
		var fallback: Vector3 = Vector3(0.0, 0.0, 1.0) if absf(up.z) < 0.9 else Vector3(1.0, 0.0, 0.0)
		east = fallback - up * fallback.dot(up)
	if east.length_squared() <= MIN_AXIS_LENGTH_SQUARED:
		return GeoUtilsScript.failure("LOCAL_TANGENT_FRAME_DEGENERATE")
	east = east.normalized()
	var north: Vector3 = east.cross(up)
	if north.length_squared() <= MIN_AXIS_LENGTH_SQUARED:
		return GeoUtilsScript.failure("LOCAL_TANGENT_FRAME_DEGENERATE")
	north = north.normalized()
	east = up.cross(north).normalized()
	var frame: Dictionary = LocalTangentFrameScript.create(
		String(_planet_definition["body_id"]),
		Array(body_fixed_position["position_m"]),
		_array3(east),
		_array3(north),
		_array3(up)
	)
	var validation: Dictionary = LocalTangentFrameScript.validate(frame)
	if not bool(validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_LOCAL_TANGENT_FRAME", {"cause": validation.get("error_code", "")})
	return GeoUtilsScript.success({
		"local_tangent_frame": frame,
		"body_shape_manifest_hash": _body_shape_manifest_hash,
	})


func _validate_body_position(body_fixed_position: Dictionary) -> Dictionary:
	if not _configured:
		return GeoUtilsScript.failure("GEODESY_SERVICE_NOT_CONFIGURED")
	var validation: Dictionary = BodyFixedPositionScript.validate(body_fixed_position)
	if not bool(validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_BODY_FIXED_POSITION", {"cause": validation.get("error_code", "")})
	if String(body_fixed_position["body_id"]) != String(_planet_definition["body_id"]):
		return GeoUtilsScript.failure("GEODESY_BODY_MISMATCH")
	return GeoUtilsScript.success()


func _validate_geodetic_position(geodetic_position: Dictionary) -> Dictionary:
	if not _configured:
		return GeoUtilsScript.failure("GEODESY_SERVICE_NOT_CONFIGURED")
	var validation: Dictionary = GeodeticPositionScript.validate(geodetic_position)
	if not bool(validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_GEODETIC_POSITION", {"cause": validation.get("error_code", "")})
	if String(geodetic_position["body_id"]) != String(_planet_definition["body_id"]):
		return GeoUtilsScript.failure("GEODESY_BODY_MISMATCH")
	return GeoUtilsScript.success()


func _provider_failure(provider_result) -> Dictionary:
	var cause: String = "INVALID_PROVIDER_RESPONSE"
	if provider_result is Dictionary:
		cause = String(provider_result.get("error_code", cause))
	return GeoUtilsScript.failure("BODY_SHAPE_QUERY_FAILED", {"cause": cause})


func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _clear() -> void:
	_configured = false
	_planet_definition = {}
	_body_shape_provider = null
	_body_shape_manifest_hash = ""
