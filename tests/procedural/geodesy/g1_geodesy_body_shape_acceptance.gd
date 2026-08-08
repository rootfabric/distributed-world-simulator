extends SceneTree

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const PlanetDefinition = preload("res://scripts/simulation/procedural/contracts/planet_definition.gd")
const BodyFixedPosition = preload("res://scripts/simulation/procedural/contracts/body_fixed_position.gd")
const GeodeticPosition = preload("res://scripts/simulation/procedural/contracts/geodetic_position.gd")
const LocalTangentFrame = preload("res://scripts/simulation/procedural/contracts/local_tangent_frame.gd")
const BodyShapeProvider = preload("res://scripts/simulation/procedural/geodesy/body_shape_provider.gd")
const SphereBodyShapeProvider = preload("res://scripts/simulation/procedural/geodesy/sphere_body_shape_provider.gd")
const GeodesyService = preload("res://scripts/simulation/procedural/geodesy/geodesy_service.gd")

const BODY_ID := "body/procedural-g1"
const RECIPE_ID := "planet-recipe/g1-sphere"
const SHAPE_ID := "body-shape/sphere-v1"
const MANIFEST_VERSION := "1.0.0"
const RADIUS_M := 6000000.0
const POSITION_TOLERANCE_M := 0.000001
const ANGLE_TOLERANCE_DEG := 0.000000001
const AXIS_TOLERANCE := 0.00000001

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_manifest_and_contracts()
	_test_service_binding()
	_test_equator_and_poles()
	_test_arbitrary_roundtrip()
	_test_altitude_and_normals()
	_test_tangent_frames()
	_test_double_precision_and_invalid_values()
	_test_source_boundaries()
	_finish()


func _test_manifest_and_contracts() -> void:
	var path := "res://config/procedural/g1-geodesy-body-shape.v1.json"
	_check(FileAccess.file_exists(path), "manifest exists")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary, "manifest is JSON object")
	if parsed is Dictionary:
		_check(String(parsed.get("checkpoint", "")) == "g1-geodesy-body-shape-v0", "manifest checkpoint")
		_check(String(parsed.get("implementation_branch", "")) == "feature/g1-geodesy-body-shape", "manifest branch")
		_check(float(parsed.get("nominal_radius_m", 0.0)) == RADIUS_M, "manifest radius")
		_check(String(parsed.get("body_shape_id", "")) == SHAPE_ID, "manifest shape")
		_check(not bool(parsed.get("runtime_worlds_changed", true)), "runtime worlds unchanged")
		_check(not bool(parsed.get("production_terrain_changed", true)), "production terrain unchanged")

	var body := BodyFixedPosition.create(BODY_ID, [RADIUS_M, 0.0, 0.0])
	_ok(BodyFixedPosition.validate(body), "body fixed position")
	_check(BodyFixedPosition.normalize(body) == body, "body fixed normalization")
	var geo := GeodeticPosition.create(BODY_ID, 0.0, 540.0, 10.0)
	_ok(GeodeticPosition.validate(geo), "geodetic position")
	_check(float(geo["longitude_deg"]) == -180.0, "longitude canonicalized")
	var pole := GeodeticPosition.create(BODY_ID, 90.0, 123.0, 0.0)
	_ok(GeodeticPosition.validate(pole), "pole geodetic")
	_check(float(pole["longitude_deg"]) == 0.0, "pole longitude canonicalized")

	var frame := LocalTangentFrame.create(BODY_ID, [RADIUS_M, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, 1.0, 0.0], [1.0, 0.0, 0.0])
	_ok(LocalTangentFrame.validate(frame), "local tangent frame")
	var bad_frame := frame.duplicate(true)
	bad_frame["east"] = [1.0, 0.0, 0.0]
	bad_frame["checksum"] = GeoUtils.compute_checksum(bad_frame)
	_error(LocalTangentFrame.validate(bad_frame), "LOCAL_TANGENT_FRAME_NOT_ORTHOGONAL", "non-orthogonal tangent frame")


func _test_service_binding() -> void:
	var service = GeodesyService.new()
	_check(not service.is_configured(), "service starts unconfigured")
	_error(service.body_to_geodetic(BodyFixedPosition.create(BODY_ID, [RADIUS_M, 0.0, 0.0])), "GEODESY_SERVICE_NOT_CONFIGURED", "unconfigured service")
	var provider = SphereBodyShapeProvider.new()
	var result: Dictionary = service.configure(_definition(), provider)
	_ok(result, "sphere service configure")
	_check(service.is_configured(), "service configured")
	_check(String(result["details"]["body_shape_id"]) == SHAPE_ID, "shape identity bound")
	_check(GeoUtils.is_lower_hex_64(service.get_body_shape_manifest_hash()), "shape manifest hash")
	_check(service.get_planet_definition() == _definition(), "definition retained")

	var wrong_shape_definition := PlanetDefinition.create(BODY_ID, 2026080802, RECIPE_ID, "body-shape/other", RADIUS_M, MANIFEST_VERSION)
	_error(GeodesyService.new().configure(wrong_shape_definition, provider), "BODY_SHAPE_ID_MISMATCH", "shape mismatch")
	_error(GeodesyService.new().configure(_definition(), BodyShapeProvider.new()), "INVALID_BODY_SHAPE_PROVIDER_ID", "abstract provider rejected")


func _test_equator_and_poles() -> void:
	var service = _service()
	var equator := BodyFixedPosition.create(BODY_ID, [RADIUS_M, 0.0, 0.0])
	var equator_geo := _geo(service, equator, "equator body to geodetic")
	_check(_approx(float(equator_geo.get("latitude_deg", NAN)), 0.0, ANGLE_TOLERANCE_DEG), "equator latitude")
	_check(_approx(float(equator_geo.get("longitude_deg", NAN)), 0.0, ANGLE_TOLERANCE_DEG), "equator longitude")
	_check(_approx(float(equator_geo.get("altitude_m", NAN)), 0.0, POSITION_TOLERANCE_M), "equator altitude")
	_check(_body_distance(_body(service, equator_geo, "equator geodetic to body"), equator) <= POSITION_TOLERANCE_M, "equator roundtrip")

	var east_equator := BodyFixedPosition.create(BODY_ID, [0.0, 0.0, RADIUS_M])
	var east_geo := _geo(service, east_equator, "east equator")
	_check(_approx(float(east_geo.get("longitude_deg", NAN)), 90.0, ANGLE_TOLERANCE_DEG), "+Z longitude is +90")

	var north_pole := BodyFixedPosition.create(BODY_ID, [0.0, RADIUS_M, 0.0])
	var north_geo := _geo(service, north_pole, "north pole")
	_check(_approx(float(north_geo.get("latitude_deg", NAN)), 90.0, ANGLE_TOLERANCE_DEG), "north latitude")
	_check(_approx(float(north_geo.get("longitude_deg", NAN)), 0.0, ANGLE_TOLERANCE_DEG), "north pole canonical longitude")
	_check(_body_distance(_body(service, north_geo, "north roundtrip"), north_pole) <= POSITION_TOLERANCE_M, "north pole roundtrip")

	var south_pole := BodyFixedPosition.create(BODY_ID, [0.0, -RADIUS_M, 0.0])
	var south_geo := _geo(service, south_pole, "south pole")
	_check(_approx(float(south_geo.get("latitude_deg", NAN)), -90.0, ANGLE_TOLERANCE_DEG), "south latitude")
	_check(_body_distance(_body(service, south_geo, "south roundtrip"), south_pole) <= POSITION_TOLERANCE_M, "south pole roundtrip")


func _test_arbitrary_roundtrip() -> void:
	var service = _service()
	for sample in [
		[37.7749295, -122.4194155, 12345.678901],
		[-33.8688197, 151.2092955, 500.125],
		[64.1465820, -21.9426354, -250.75],
	]:
		var original := GeodeticPosition.create(BODY_ID, float(sample[0]), float(sample[1]), float(sample[2]))
		_ok(GeodeticPosition.validate(original), "arbitrary geodetic input")
		var body := _body(service, original, "arbitrary geodetic to body")
		var restored := _geo(service, body, "arbitrary body to geodetic")
		_check(_approx(float(restored.get("latitude_deg", NAN)), float(original["latitude_deg"]), ANGLE_TOLERANCE_DEG), "arbitrary latitude roundtrip")
		_check(_angle_distance_deg(float(restored.get("longitude_deg", NAN)), float(original["longitude_deg"])) <= ANGLE_TOLERANCE_DEG, "arbitrary longitude roundtrip")
		_check(_approx(float(restored.get("altitude_m", NAN)), float(original["altitude_m"]), POSITION_TOLERANCE_M), "arbitrary altitude roundtrip")
		var body_again := _body(service, restored, "arbitrary second body")
		_check(_body_distance(body, body_again) <= POSITION_TOLERANCE_M, "arbitrary body roundtrip")


func _test_altitude_and_normals() -> void:
	var service = _service()
	for altitude_m in [-1000.0, 0.0, 1.25, 50000.0]:
		var geo := GeodeticPosition.create(BODY_ID, 0.0, 0.0, altitude_m)
		var body := _body(service, geo, "altitude body")
		var altitude_result: Dictionary = service.altitude(body)
		_ok(altitude_result, "altitude query")
		if _success(altitude_result):
			_check(_approx(float(altitude_result["details"]["altitude_m"]), altitude_m, POSITION_TOLERANCE_M), "altitude value")

	var normal_body := BodyFixedPosition.create(BODY_ID, [RADIUS_M + 100.0, 0.0, 0.0])
	var normal_result: Dictionary = service.surface_normal(normal_body)
	_ok(normal_result, "surface normal")
	if _success(normal_result):
		_check(_vector_distance(Array(normal_result["details"]["normal"]), [1.0, 0.0, 0.0]) <= AXIS_TOLERANCE, "equator surface normal")
	var arbitrary := _body(service, GeodeticPosition.create(BODY_ID, 42.0, 73.0, 1000.0), "normal arbitrary body")
	var arbitrary_normal: Dictionary = service.surface_normal(arbitrary)
	_ok(arbitrary_normal, "arbitrary surface normal")
	if _success(arbitrary_normal):
		_check(_approx(_vector(Array(arbitrary_normal["details"]["normal"])).length(), 1.0, AXIS_TOLERANCE), "normal is unit")


func _test_tangent_frames() -> void:
	var service = _service()
	var equator := BodyFixedPosition.create(BODY_ID, [RADIUS_M, 0.0, 0.0])
	var result: Dictionary = service.local_tangent_frame(equator)
	_ok(result, "equator tangent frame")
	if _success(result):
		var frame: Dictionary = result["details"]["local_tangent_frame"]
		_ok(LocalTangentFrame.validate(frame), "equator tangent contract")
		_check(_vector_distance(Array(frame["up"]), [1.0, 0.0, 0.0]) <= AXIS_TOLERANCE, "equator Up")
		_check(_vector_distance(Array(frame["east"]), [0.0, 0.0, 1.0]) <= AXIS_TOLERANCE, "equator East")
		_check(_vector_distance(Array(frame["north"]), [0.0, 1.0, 0.0]) <= AXIS_TOLERANCE, "equator North")

	for geo in [
		GeodeticPosition.create(BODY_ID, 45.0, 45.0, 0.0),
		GeodeticPosition.create(BODY_ID, 90.0, 0.0, 0.0),
		GeodeticPosition.create(BODY_ID, -90.0, 0.0, 0.0),
	]:
		var body := _body(service, geo, "tangent body")
		var tangent_result: Dictionary = service.local_tangent_frame(body)
		_ok(tangent_result, "tangent result")
		if _success(tangent_result):
			var frame: Dictionary = tangent_result["details"]["local_tangent_frame"]
			_ok(LocalTangentFrame.validate(frame), "tangent contract")
			var east := _vector(Array(frame["east"]))
			var north := _vector(Array(frame["north"]))
			var up := _vector(Array(frame["up"]))
			_check(absf(east.dot(north)) <= AXIS_TOLERANCE, "east north orthogonal")
			_check(absf(east.dot(up)) <= AXIS_TOLERANCE, "east up orthogonal")
			_check(absf(north.dot(up)) <= AXIS_TOLERANCE, "north up orthogonal")
			_check(east.cross(up).dot(north) >= 1.0 - AXIS_TOLERANCE, "E x U = N handedness")


func _test_double_precision_and_invalid_values() -> void:
	var service = _service()
	var precise := GeodeticPosition.create(BODY_ID, 12.345678901234, -98.765432109876, 0.123456789)
	var body := _body(service, precise, "precise body")
	var restored := _geo(service, body, "precise roundtrip")
	_check(_approx(float(restored.get("latitude_deg", NAN)), float(precise["latitude_deg"]), ANGLE_TOLERANCE_DEG), "double latitude precision")
	_check(_angle_distance_deg(float(restored.get("longitude_deg", NAN)), float(precise["longitude_deg"])) <= ANGLE_TOLERANCE_DEG, "double longitude precision")
	_check(_approx(float(restored.get("altitude_m", NAN)), float(precise["altitude_m"]), POSITION_TOLERANCE_M), "double altitude precision")

	var nan_body := BodyFixedPosition.create(BODY_ID, [NAN, 0.0, 0.0])
	_error(BodyFixedPosition.validate(nan_body), "INVALID_BODY_FIXED_POSITION_VECTOR", "NaN body contract")
	var inf_geo := GeodeticPosition.create(BODY_ID, INF, 0.0, 0.0)
	_error(GeodeticPosition.validate(inf_geo), "INVALID_GEODETIC_LATITUDE", "INF geodetic contract")
	var out_of_range := GeodeticPosition.create(BODY_ID, 91.0, 0.0, 0.0)
	_error(GeodeticPosition.validate(out_of_range), "GEODETIC_LATITUDE_OUT_OF_RANGE", "latitude range")
	var other_body := BodyFixedPosition.create("body/other", [RADIUS_M, 0.0, 0.0])
	_error(service.body_to_geodetic(other_body), "GEODESY_BODY_MISMATCH", "body identity mismatch")
	var center := BodyFixedPosition.create(BODY_ID, [0.0, 0.0, 0.0])
	_error(service.body_to_geodetic(center), "BODY_SHAPE_QUERY_FAILED", "center geodetic undefined")
	var center_geo := GeodeticPosition.create(BODY_ID, 0.0, 0.0, -RADIUS_M)
	_error(service.geodetic_to_body(center_geo), "BODY_SHAPE_QUERY_FAILED", "center altitude rejected")


func _test_source_boundaries() -> void:
	var paths: Array[String] = [
		"res://scripts/simulation/procedural/contracts/body_fixed_position.gd",
		"res://scripts/simulation/procedural/contracts/geodetic_position.gd",
		"res://scripts/simulation/procedural/contracts/local_tangent_frame.gd",
		"res://scripts/simulation/procedural/geodesy/body_shape_provider.gd",
		"res://scripts/simulation/procedural/geodesy/sphere_body_shape_provider.gd",
		"res://scripts/simulation/procedural/geodesy/geodesy_service.gd",
	]
	var forbidden := ["extends Node", "extends SceneTree", "MeshInstance3D", "ArrayMesh", "RenderingServer", "Terrain3D", "VoxelLodTerrain", "RandomNumberGenerator", "randf(", "randi(", "MultiplayerPeer"]
	for path in paths:
		var source := FileAccess.get_file_as_string(path)
		_check(not source.is_empty(), "source exists: %s" % path)
		for marker in forbidden:
			_check(not source.contains(marker), "no %s in %s" % [marker, path])


func _definition() -> Dictionary:
	return PlanetDefinition.create(BODY_ID, 2026080802, RECIPE_ID, SHAPE_ID, RADIUS_M, MANIFEST_VERSION)


func _service():
	var service = GeodesyService.new()
	_ok(service.configure(_definition(), SphereBodyShapeProvider.new()), "service fixture configure")
	return service


func _geo(service, body: Dictionary, label: String) -> Dictionary:
	var result: Dictionary = service.body_to_geodetic(body)
	_ok(result, label)
	if not _success(result):
		return {}
	return result["details"]["geodetic_position"]


func _body(service, geo: Dictionary, label: String) -> Dictionary:
	var result: Dictionary = service.geodetic_to_body(geo)
	_ok(result, label)
	if not _success(result):
		return {}
	return result["details"]["body_fixed_position"]


func _body_distance(a: Dictionary, b: Dictionary) -> float:
	if a.is_empty() or b.is_empty():
		return INF
	return _vector(Array(a["position_m"])).distance_to(_vector(Array(b["position_m"])) )


func _vector_distance(a: Array, b: Array) -> float:
	return _vector(a).distance_to(_vector(b))


func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _angle_distance_deg(a: float, b: float) -> float:
	return absf(fposmod(a - b + 180.0, 360.0) - 180.0)


func _approx(a: float, b: float, tolerance: float) -> bool:
	return is_finite(a) and is_finite(b) and absf(a - b) <= tolerance


func _success(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _ok(result: Dictionary, label: String) -> void:
	_check(_success(result), "%s: %s" % [label, String(result.get("error_code", ""))])


func _error(result: Dictionary, code: String, label: String) -> void:
	_check(not _success(result), "%s unexpectedly succeeded" % label)
	if not _success(result):
		_check(String(result.get("error_code", "")) == code, "%s expected %s got %s" % [label, code, String(result.get("error_code", ""))])


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("G1 geodesy + body shape: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G1 geodesy + body shape: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
