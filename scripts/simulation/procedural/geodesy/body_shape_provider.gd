extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const CONTRACT_VERSION: String = "1.0.0"


func get_shape_id() -> String:
	return ""


func get_contract_version() -> String:
	return CONTRACT_VERSION


func get_generator_version() -> String:
	return "0.0.0"


func is_deterministic() -> bool:
	return false


func supports_planet_definition(_planet_definition: Dictionary) -> bool:
	return false


func body_to_geodetic(_planet_definition: Dictionary, _position_m: Array) -> Dictionary:
	return GeoUtilsScript.failure("BODY_SHAPE_OPERATION_UNSUPPORTED")


func geodetic_to_body(
	_planet_definition: Dictionary,
	_latitude_deg: float,
	_longitude_deg: float,
	_altitude_m: float
) -> Dictionary:
	return GeoUtilsScript.failure("BODY_SHAPE_OPERATION_UNSUPPORTED")


func surface_normal(_planet_definition: Dictionary, _position_m: Array) -> Dictionary:
	return GeoUtilsScript.failure("BODY_SHAPE_OPERATION_UNSUPPORTED")


func altitude(_planet_definition: Dictionary, _position_m: Array) -> Dictionary:
	return GeoUtilsScript.failure("BODY_SHAPE_OPERATION_UNSUPPORTED")
