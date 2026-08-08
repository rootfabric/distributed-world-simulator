extends RefCounted

const RiverSpline = preload("res://scripts/simulation/procedural/contracts/river_spline.gd")
const RiverChannelProfile = preload("res://scripts/simulation/procedural/contracts/river_channel_profile.gd")
const CasualRiverProvider = preload("res://scripts/simulation/procedural/hydrology/casual_river_provider_v1.gd")

const BODY_ID: String = "body/procedural-g6"
const FRAME_ID: String = "body/procedural-g6/fixed"
const RADIUS_M: float = 6000000.0
const SEED: int = 2026080806
const GENERATOR_VERSION: String = "1.0.0"
const FEATURE_STABLE_KEY: String = "feature-key/g6-mega-river-001"
const FLUID_STABLE_KEY: String = "fluid-region-key/g6-mega-river-001"


static func river_spline() -> Dictionary:
	var points: Array = []
	for index in range(9):
		var longitude := 34.0 + float(index) * 3.0
		var latitude := 4.0 + sin(float(index) * 0.8) * 2.2
		var radius := RADIUS_M + 140.0 - float(index) * 15.0
		points.append(RiverSpline.point(
			"river-point/g6-%02d" % index,
			_array3(_direction(latitude, longitude) * radius)
		))
	return RiverSpline.create(FRAME_ID, points, RiverSpline.INTERPOLATION_SPHERICAL_RADIAL)


static func channel_profile() -> Dictionary:
	return RiverChannelProfile.create(60.0, 180.0, 3.0, 9.0, 1.2, 2.4, 24.0)


static func provider():
	var result = CasualRiverProvider.new()
	var configured: Dictionary = result.configure(
		BODY_ID,
		FRAME_ID,
		SEED,
		GENERATOR_VERSION,
		FEATURE_STABLE_KEY,
		FLUID_STABLE_KEY,
		river_spline(),
		channel_profile()
	)
	if not bool(configured.get("success", false)):
		return null
	return result


static func _direction(latitude_deg: float, longitude_deg: float) -> Vector3:
	var lat := deg_to_rad(latitude_deg)
	var lon := deg_to_rad(longitude_deg)
	var cos_lat := cos(lat)
	return Vector3(cos_lat * cos(lon), sin(lat), cos_lat * sin(lon)).normalized()


static func _array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
