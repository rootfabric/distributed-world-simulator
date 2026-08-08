extends "res://scripts/simulation/procedural/geodesy/body_shape_provider.gd"

const PlanetDefinitionScript = preload("res://scripts/simulation/procedural/contracts/planet_definition.gd")

const SHAPE_ID: String = "body-shape/sphere-v1"
const GENERATOR_VERSION: String = "1.0.0"
const MIN_RADIAL_DISTANCE_M: float = 0.000001


func get_shape_id() -> String:
	return SHAPE_ID


func get_generator_version() -> String:
	return GENERATOR_VERSION


func is_deterministic() -> bool:
	return true


func supports_planet_definition(planet_definition: Dictionary) -> bool:
	return bool(_validate_definition(planet_definition).get("success", false))


func body_to_geodetic(planet_definition: Dictionary, position_m: Array) -> Dictionary:
	var definition_validation: Dictionary = _validate_definition(planet_definition)
	if not bool(definition_validation.get("success", false)):
		return definition_validation
	if not GeoUtilsScript.is_vector3_array(position_m):
		return GeoUtilsScript.failure("INVALID_BODY_SHAPE_POSITION")
	var position: Vector3 = _vector3(position_m)
	var radial_distance: float = position.length()
	if radial_distance <= MIN_RADIAL_DISTANCE_M:
		return GeoUtilsScript.failure("BODY_SHAPE_POSITION_AT_CENTER")
	var latitude_rad: float = asin(clampf(position.y / radial_distance, -1.0, 1.0))
	var longitude_rad: float = atan2(position.z, position.x)
	return GeoUtilsScript.success({
		"latitude_deg": rad_to_deg(latitude_rad),
		"longitude_deg": rad_to_deg(longitude_rad),
		"altitude_m": radial_distance - float(planet_definition["nominal_radius_m"]),
	})


func geodetic_to_body(
	planet_definition: Dictionary,
	latitude_deg: float,
	longitude_deg: float,
	altitude_m: float
) -> Dictionary:
	var definition_validation: Dictionary = _validate_definition(planet_definition)
	if not bool(definition_validation.get("success", false)):
		return definition_validation
	for value in [latitude_deg, longitude_deg, altitude_m]:
		if not is_finite(float(value)):
			return GeoUtilsScript.failure("INVALID_BODY_SHAPE_GEODETIC_COORDINATE")
	if latitude_deg < -90.0 or latitude_deg > 90.0 or longitude_deg < -180.0 or longitude_deg >= 180.0:
		return GeoUtilsScript.failure("BODY_SHAPE_GEODETIC_COORDINATE_OUT_OF_RANGE")
	var radial_distance: float = float(planet_definition["nominal_radius_m"]) + altitude_m
	if radial_distance <= MIN_RADIAL_DISTANCE_M:
		return GeoUtilsScript.failure("BODY_SHAPE_RADIAL_DISTANCE_NOT_POSITIVE")
	var latitude_rad: float = deg_to_rad(latitude_deg)
	var longitude_rad: float = deg_to_rad(longitude_deg)
	var cos_latitude: float = cos(latitude_rad)
	var position: Vector3 = Vector3(
		radial_distance * cos_latitude * cos(longitude_rad),
		radial_distance * sin(latitude_rad),
		radial_distance * cos_latitude * sin(longitude_rad)
	)
	return GeoUtilsScript.success({"position_m": _array3(position)})


func surface_normal(planet_definition: Dictionary, position_m: Array) -> Dictionary:
	var definition_validation: Dictionary = _validate_definition(planet_definition)
	if not bool(definition_validation.get("success", false)):
		return definition_validation
	if not GeoUtilsScript.is_vector3_array(position_m):
		return GeoUtilsScript.failure("INVALID_BODY_SHAPE_POSITION")
	var position: Vector3 = _vector3(position_m)
	if position.length() <= MIN_RADIAL_DISTANCE_M:
		return GeoUtilsScript.failure("BODY_SHAPE_POSITION_AT_CENTER")
	return GeoUtilsScript.success({"normal": _array3(position.normalized())})


func altitude(planet_definition: Dictionary, position_m: Array) -> Dictionary:
	var definition_validation: Dictionary = _validate_definition(planet_definition)
	if not bool(definition_validation.get("success", false)):
		return definition_validation
	if not GeoUtilsScript.is_vector3_array(position_m):
		return GeoUtilsScript.failure("INVALID_BODY_SHAPE_POSITION")
	var position: Vector3 = _vector3(position_m)
	if position.length() <= MIN_RADIAL_DISTANCE_M:
		return GeoUtilsScript.failure("BODY_SHAPE_POSITION_AT_CENTER")
	return GeoUtilsScript.success({
		"altitude_m": position.length() - float(planet_definition["nominal_radius_m"]),
	})


func _validate_definition(planet_definition: Dictionary) -> Dictionary:
	var validation: Dictionary = PlanetDefinitionScript.validate(planet_definition)
	if not bool(validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_BODY_SHAPE_PLANET_DEFINITION", {"cause": validation.get("error_code", "")})
	if String(planet_definition["body_shape_id"]) != SHAPE_ID:
		return GeoUtilsScript.failure("BODY_SHAPE_ID_MISMATCH")
	return GeoUtilsScript.success()


func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
