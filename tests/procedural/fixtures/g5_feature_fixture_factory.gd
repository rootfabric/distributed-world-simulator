extends RefCounted

const FeatureBounds = preload("res://scripts/simulation/procedural/contracts/feature_bounds.gd")
const FeatureAnchor = preload("res://scripts/simulation/procedural/contracts/feature_anchor.gd")
const FeatureRelation = preload("res://scripts/simulation/procedural/contracts/feature_relation.gd")
const FeatureType = preload("res://scripts/simulation/procedural/contracts/feature_type.gd")
const WorldFeature = preload("res://scripts/simulation/procedural/contracts/world_feature.gd")

const BODY_ID := "body/procedural-g5"
const FRAME_ID := "body/procedural-g5/fixed"
const RADIUS_M := 6000000.0
const SEED := 2026080805
const GENERATOR_VERSION := "1.0.0"


static func seam_fault() -> Dictionary:
	var anchors: Array = []
	for index in range(5):
		var longitude: float = 35.0 + float(index) * 5.0
		anchors.append(FeatureAnchor.create(
			"feature-anchor/seam-fault-%02d" % index,
			FRAME_ID,
			"feature-anchor-role/control-point",
			_array3(_direction(2.0 * sin(float(index)), longitude) * RADIUS_M)
		))
	var center := _direction(0.0, 45.0) * RADIUS_M
	return WorldFeature.create(
		BODY_ID,
		FeatureType.FAULT,
		SEED,
		GENERATOR_VERSION,
		"feature-key/seam-fault-001",
		FRAME_ID,
		FeatureBounds.sphere(FRAME_ID, _array3(center), 1500000.0),
		anchors,
		"",
		[],
		{"geometry_kind": "polyline", "semantic": "cube-seam-crossing-fault"}
	)


static func valley() -> Dictionary:
	var center := _direction(8.0, 25.0) * RADIUS_M
	return WorldFeature.create(
		BODY_ID,
		FeatureType.VALLEY,
		SEED,
		GENERATOR_VERSION,
		"feature-key/valley-001",
		FRAME_ID,
		FeatureBounds.sphere(FRAME_ID, _array3(center), 900000.0),
		[
			FeatureAnchor.create("feature-anchor/valley-start", FRAME_ID, "feature-anchor-role/start", _array3(_direction(5.0, 18.0) * RADIUS_M)),
			FeatureAnchor.create("feature-anchor/valley-end", FRAME_ID, "feature-anchor-role/end", _array3(_direction(11.0, 32.0) * RADIUS_M)),
		],
		"",
		[],
		{"geometry_kind": "spline"}
	)


static func river(valley_id: String) -> Dictionary:
	var center := _direction(8.0, 25.0) * (RADIUS_M + 10.0)
	return WorldFeature.create(
		BODY_ID,
		FeatureType.RIVER,
		SEED + 1,
		GENERATOR_VERSION,
		"feature-key/river-001",
		FRAME_ID,
		FeatureBounds.sphere(FRAME_ID, _array3(center), 700000.0),
		[
			FeatureAnchor.create("feature-anchor/river-source", FRAME_ID, "feature-anchor-role/source", _array3(_direction(11.0, 20.0) * (RADIUS_M + 5.0))),
			FeatureAnchor.create("feature-anchor/river-mouth", FRAME_ID, "feature-anchor-role/mouth", _array3(_direction(5.0, 30.0) * (RADIUS_M + 5.0))),
		],
		valley_id,
		[FeatureRelation.create("feature-relation/flows-through", valley_id, {"strength": 1.0})],
		{"geometry_kind": "spline", "fluid_type_id": "fluid/water"}
	)


static func cave_system() -> Dictionary:
	var center := _direction(-18.0, -110.0) * (RADIUS_M - 12000.0)
	return WorldFeature.create(
		BODY_ID,
		FeatureType.CAVE_SYSTEM,
		SEED + 2,
		GENERATOR_VERSION,
		"feature-key/cave-system-001",
		FRAME_ID,
		FeatureBounds.sphere(FRAME_ID, _array3(center), 18000.0),
		[FeatureAnchor.create("feature-anchor/cave-core", FRAME_ID, "feature-anchor-role/core", _array3(center))],
		"",
		[],
		{"geometry_kind": "volume-network", "depth_m": 12000.0}
	)


static func floating_island() -> Dictionary:
	var center := _direction(35.0, 140.0) * (RADIUS_M + 450000.0)
	return WorldFeature.create(
		BODY_ID,
		FeatureType.FLOATING_ISLAND,
		SEED + 3,
		GENERATOR_VERSION,
		"feature-key/floating-island-001",
		FRAME_ID,
		FeatureBounds.aabb(FRAME_ID, _array3(center), [120000.0, 80000.0, 120000.0]),
		[FeatureAnchor.create("feature-anchor/floating-island-core", FRAME_ID, "feature-anchor-role/core", _array3(center))],
		"",
		[],
		{"geometry_kind": "volume-body"}
	)


static func all_features() -> Array:
	var valley_feature := valley()
	return [seam_fault(), valley_feature, river(String(valley_feature["feature_id"])), cave_system(), floating_island()]


static func _direction(latitude_deg: float, longitude_deg: float) -> Vector3:
	var lat := deg_to_rad(latitude_deg)
	var lon := deg_to_rad(longitude_deg)
	var cos_lat := cos(lat)
	return Vector3(cos_lat * cos(lon), sin(lat), cos_lat * sin(lon)).normalized()


static func _array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
