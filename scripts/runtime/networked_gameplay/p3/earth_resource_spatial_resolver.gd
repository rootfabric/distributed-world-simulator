extends RefCounted

const EARTH_CONFIG_PATH := "res://config/planets/earth.json"

var _configured := false
var _radius_m := 0.0
var _spawn_latitude_deg := 0.0
var _spawn_longitude_deg := 0.0
var _spawn_altitude_m := 0.0


func setup(config_path: String = EARTH_CONFIG_PATH) -> Dictionary:
	if _configured:
		return _failure("EARTH_RESOURCE_RESOLVER_ALREADY_CONFIGURED")
	var path := config_path.strip_edges()
	if path.is_empty() or not FileAccess.file_exists(path):
		return _failure("EARTH_RESOURCE_CONFIG_NOT_FOUND")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return _failure("EARTH_RESOURCE_CONFIG_INVALID")
	var config: Dictionary = parsed
	var spawn_value = config.get("default_spawn", {})
	if not spawn_value is Dictionary:
		return _failure("EARTH_RESOURCE_SPAWN_CONFIG_INVALID")
	var spawn: Dictionary = spawn_value
	if (
		not _is_number(config.get("radius_m"))
		or not _is_number(spawn.get("latitude_deg"))
		or not _is_number(spawn.get("longitude_deg"))
		or not _is_number(spawn.get("altitude_m"))
	):
		return _failure("EARTH_RESOURCE_CONFIG_INVALID")
	_radius_m = float(config.get("radius_m", 0.0))
	_spawn_latitude_deg = float(spawn.get("latitude_deg", 0.0))
	_spawn_longitude_deg = float(spawn.get("longitude_deg", 0.0))
	_spawn_altitude_m = float(spawn.get("altitude_m", 0.0))
	if _radius_m <= 0.0:
		return _failure("EARTH_RESOURCE_RADIUS_INVALID")
	_configured = true
	return _success({
		"radius_m": _radius_m,
		"spawn_latitude_deg": _spawn_latitude_deg,
		"spawn_longitude_deg": _spawn_longitude_deg,
		"spawn_altitude_m": _spawn_altitude_m,
	})


func resolve_planar(spatial: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("EARTH_RESOURCE_RESOLVER_NOT_CONFIGURED")
	if String(spatial.get("frame", "")) != "earth-fixed":
		return _failure("RESOURCE_SPATIAL_FRAME_UNSUPPORTED")
	if (
		not _is_number(spatial.get("latitude_deg"))
		or not _is_number(spatial.get("longitude_deg"))
		or not _is_number(spatial.get("altitude_m"))
	):
		return _failure("RESOURCE_SPATIAL_COORDINATES_INVALID")
	var latitude_deg := float(spatial.get("latitude_deg", 0.0))
	var longitude_deg := float(spatial.get("longitude_deg", 0.0))
	var altitude_m := float(spatial.get("altitude_m", 0.0))
	if latitude_deg < -90.0 or latitude_deg > 90.0 or longitude_deg < -180.0 or longitude_deg > 180.0:
		return _failure("RESOURCE_SPATIAL_COORDINATES_INVALID")

	var anchor := _direction(_spawn_latitude_deg, _spawn_longitude_deg)
	var target := _direction(latitude_deg, longitude_deg)
	var east := Vector3.UP.cross(anchor)
	if east.length_squared() < 0.000001:
		east = Vector3.RIGHT.cross(anchor)
	east = east.normalized()
	var north := anchor.cross(east).normalized()
	var anchor_position := anchor * (_radius_m + _spawn_altitude_m)
	var target_position := target * (_radius_m + altitude_m)
	var delta := target_position - anchor_position
	return _success({
		"planar_position": {
			"x": delta.dot(east),
			"y": delta.dot(anchor),
			"z": -delta.dot(north),
		},
		"anchor": {
			"latitude_deg": _spawn_latitude_deg,
			"longitude_deg": _spawn_longitude_deg,
			"altitude_m": _spawn_altitude_m,
		},
	})


func _direction(latitude_deg: float, longitude_deg: float) -> Vector3:
	var latitude := deg_to_rad(latitude_deg)
	var longitude := deg_to_rad(longitude_deg)
	var horizontal := cos(latitude)
	return Vector3(
		horizontal * cos(longitude),
		sin(latitude),
		horizontal * sin(longitude)
	).normalized()


func _is_number(value) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
