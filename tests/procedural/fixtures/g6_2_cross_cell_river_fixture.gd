extends RefCounted

const FeatureBounds = preload("res://scripts/simulation/procedural/contracts/feature_bounds.gd")
const FeatureAnchor = preload("res://scripts/simulation/procedural/contracts/feature_anchor.gd")
const FeatureType = preload("res://scripts/simulation/procedural/contracts/feature_type.gd")
const WorldFeature = preload("res://scripts/simulation/procedural/contracts/world_feature.gd")

const BODY_ID: String = "body/procedural-g6-continuity"
const FRAME_ID: String = "body/procedural-g6-continuity/fixed"
const RADIUS_M: float = 6000000.0
const SEED: int = 20260808062
const GENERATOR_VERSION: String = "1.0.0"
const STABLE_KEY: String = "feature-key/g6-cross-cell-river-001"


static func river() -> Dictionary:
	var source := _direction(4.0, 34.0) * (RADIUS_M + 120.0)
	var mouth := _direction(6.0, 58.0) * (RADIUS_M + 20.0)
	var center := _direction(5.0, 46.0) * (RADIUS_M + 70.0)
	return WorldFeature.create(
		BODY_ID,
		FeatureType.RIVER,
		SEED,
		GENERATOR_VERSION,
		STABLE_KEY,
		FRAME_ID,
		FeatureBounds.sphere(FRAME_ID, _array3(center), 1500000.0),
		[
			FeatureAnchor.create(
				"feature-anchor/g6-cross-cell-river-source",
				FRAME_ID,
				"feature-anchor-role/source",
				_array3(source)
			),
			FeatureAnchor.create(
				"feature-anchor/g6-cross-cell-river-mouth",
				FRAME_ID,
				"feature-anchor-role/mouth",
				_array3(mouth)
			),
		],
		"",
		[],
		{
			"geometry_kind": "spline",
			"semantic": "g6-cross-cell-cross-lod-continuity-fixture",
			"expected_cube_faces": ["PX", "PZ"],
		}
	)


static func _direction(latitude_deg: float, longitude_deg: float) -> Vector3:
	var lat := deg_to_rad(latitude_deg)
	var lon := deg_to_rad(longitude_deg)
	var cos_lat := cos(lat)
	return Vector3(cos_lat * cos(lon), sin(lat), cos_lat * sin(lon)).normalized()


static func _array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
