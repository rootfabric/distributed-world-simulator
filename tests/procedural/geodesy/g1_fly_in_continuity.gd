extends SceneTree

const PlanetDefinition = preload("res://scripts/simulation/procedural/contracts/planet_definition.gd")
const BodyFixedPosition = preload("res://scripts/simulation/procedural/contracts/body_fixed_position.gd")
const GeodeticPosition = preload("res://scripts/simulation/procedural/contracts/geodetic_position.gd")
const SphereBodyShapeProvider = preload("res://scripts/simulation/procedural/geodesy/sphere_body_shape_provider.gd")
const GeodesyService = preload("res://scripts/simulation/procedural/geodesy/geodesy_service.gd")

const BODY_ID := "body/procedural-g1"
const RECIPE_ID := "planet-recipe/g1-sphere"
const SHAPE_ID := "body-shape/sphere-v1"
const MANIFEST_VERSION := "1.0.0"
const RADIUS_M := 6000000.0
const POSITION_TOLERANCE_M := 0.000001
const ANGLE_TOLERANCE_DEG := 0.000000001
const BASIS_TOLERANCE := 0.00000001

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var service = GeodesyService.new()
	_check(_success(service.configure(_definition(), SphereBodyShapeProvider.new())), "service configure")

	var previous_body: Dictionary = {}
	var previous_altitude: float = INF
	var reference_up: Vector3 = Vector3.ZERO
	var reference_east: Vector3 = Vector3.ZERO
	var reference_north: Vector3 = Vector3.ZERO
	var latitude_deg: float = 37.25
	var longitude_deg: float = -122.5

	for altitude_m in [50000.0, 25000.0, 10000.0, 5000.0, 1000.0, 250.0, 50.0, 10.0, 1.0, 0.0]:
		var geodetic := GeodeticPosition.create(BODY_ID, latitude_deg, longitude_deg, altitude_m)
		_check(_success(GeodeticPosition.validate(geodetic)), "input geodetic valid at %.3f m" % altitude_m)
		var body_result: Dictionary = service.geodetic_to_body(geodetic)
		_check(_success(body_result), "geodetic_to_body at %.3f m" % altitude_m)
		if not _success(body_result):
			continue
		var body: Dictionary = body_result["details"]["body_fixed_position"]
		_check(_success(BodyFixedPosition.validate(body)), "body contract at %.3f m" % altitude_m)

		var restored_result: Dictionary = service.body_to_geodetic(body)
		_check(_success(restored_result), "body_to_geodetic at %.3f m" % altitude_m)
		if _success(restored_result):
			var restored: Dictionary = restored_result["details"]["geodetic_position"]
			_check(absf(float(restored["altitude_m"]) - altitude_m) <= POSITION_TOLERANCE_M, "altitude roundtrip at %.3f m" % altitude_m)
			_check(absf(float(restored["latitude_deg"]) - latitude_deg) <= ANGLE_TOLERANCE_DEG, "latitude stable at %.3f m" % altitude_m)
			_check(_angle_distance_deg(float(restored["longitude_deg"]), longitude_deg) <= ANGLE_TOLERANCE_DEG, "longitude stable at %.3f m" % altitude_m)

		var tangent_result: Dictionary = service.local_tangent_frame(body)
		_check(_success(tangent_result), "tangent frame at %.3f m" % altitude_m)
		if _success(tangent_result):
			var frame: Dictionary = tangent_result["details"]["local_tangent_frame"]
			var up := _vector(Array(frame["up"]))
			var east := _vector(Array(frame["east"]))
			var north := _vector(Array(frame["north"]))
			if reference_up == Vector3.ZERO:
				reference_up = up
				reference_east = east
				reference_north = north
			else:
				_check(up.distance_to(reference_up) <= BASIS_TOLERANCE, "Up stable through fly-in")
				_check(east.distance_to(reference_east) <= BASIS_TOLERANCE, "East stable through fly-in")
				_check(north.distance_to(reference_north) <= BASIS_TOLERANCE, "North stable through fly-in")

		if not previous_body.is_empty():
			var expected_step: float = previous_altitude - altitude_m
			var actual_step: float = _vector(Array(previous_body["position_m"])).distance_to(_vector(Array(body["position_m"])) )
			_check(absf(actual_step - expected_step) <= POSITION_TOLERANCE_M, "radial step continuous %.3f -> %.3f m" % [previous_altitude, altitude_m])
		previous_body = body
		previous_altitude = altitude_m

	_finish()


func _definition() -> Dictionary:
	return PlanetDefinition.create(BODY_ID, 2026080802, RECIPE_ID, SHAPE_ID, RADIUS_M, MANIFEST_VERSION)


func _angle_distance_deg(a: float, b: float) -> float:
	return absf(fposmod(a - b + 180.0, 360.0) - 180.0)


func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _success(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("G1 fly-in geodesy continuity: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G1 fly-in geodesy continuity: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
