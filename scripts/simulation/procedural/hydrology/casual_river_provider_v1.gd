extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FeatureBoundsScript = preload("res://scripts/simulation/procedural/contracts/feature_bounds.gd")
const RiverSplineScript = preload("res://scripts/simulation/procedural/contracts/river_spline.gd")
const RiverChannelProfileScript = preload("res://scripts/simulation/procedural/contracts/river_channel_profile.gd")
const FluidSurfaceDescriptorScript = preload("res://scripts/simulation/procedural/contracts/fluid_surface_descriptor.gd")
const WaterSurfaceQueryScript = preload("res://scripts/simulation/procedural/contracts/water_surface_query.gd")
const WaterSurfaceSampleScript = preload("res://scripts/simulation/procedural/contracts/water_surface_sample.gd")
const RiverFeatureScript = preload("res://scripts/simulation/procedural/features/river_feature.gd")

const PROVIDER_ID: String = "hydro-provider/casual-river-v1"
const PROVIDER_VERSION: String = "1.0.0"
const FLUID_TYPE_WATER: String = "fluid/water"
const EPSILON_SQ: float = 0.000000000001

var _configured: bool = false
var _body_id: String = ""
var _frame_id: String = ""
var _river_feature: Dictionary = {}
var _fluid_surface: Dictionary = {}
var _manifest_hash: String = ""


func configure(
	body_id: String,
	frame_id: String,
	seed: int,
	generator_version: String,
	feature_stable_key: String,
	fluid_stable_key: String,
	river_spline: Dictionary,
	channel_profile: Dictionary,
	parent_feature_id: String = "",
	relations: Array = []
) -> Dictionary:
	if _configured:
		return GeoUtilsScript.failure("CASUAL_RIVER_PROVIDER_ALREADY_CONFIGURED")
	var spline_validation: Dictionary = RiverSplineScript.validate(river_spline)
	if not bool(spline_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_CASUAL_RIVER_SPLINE", {"cause": spline_validation.get("error_code", "")})
	if String(river_spline["frame_id"]) != frame_id:
		return GeoUtilsScript.failure("CASUAL_RIVER_SPLINE_FRAME_MISMATCH")
	var profile_validation: Dictionary = RiverChannelProfileScript.validate(channel_profile)
	if not bool(profile_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_CASUAL_RIVER_CHANNEL_PROFILE", {"cause": profile_validation.get("error_code", "")})
	var bounds := _derive_bounds(frame_id, river_spline, channel_profile)
	var descriptor := FluidSurfaceDescriptorScript.create(
		body_id,
		frame_id,
		FLUID_TYPE_WATER,
		seed,
		generator_version,
		fluid_stable_key,
		bounds,
		FluidSurfaceDescriptorScript.LOCAL_SPLINE,
		{
			"provider_id": PROVIDER_ID,
			"provider_version": PROVIDER_VERSION,
			"river_spline_checksum": String(river_spline["checksum"]),
			"channel_profile_checksum": String(channel_profile["checksum"]),
		},
		{"canonical_geography": true, "simulation_model": "kinematic-surface-v0"}
	)
	var descriptor_validation: Dictionary = FluidSurfaceDescriptorScript.validate(descriptor)
	if not bool(descriptor_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_CASUAL_RIVER_FLUID_SURFACE", {"cause": descriptor_validation.get("error_code", "")})
	var feature := RiverFeatureScript.create(
		body_id,
		seed,
		generator_version,
		feature_stable_key,
		frame_id,
		bounds,
		river_spline,
		channel_profile,
		descriptor,
		parent_feature_id,
		relations
	)
	var feature_validation: Dictionary = RiverFeatureScript.validate(feature)
	if not bool(feature_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_CASUAL_RIVER_FEATURE", {"cause": feature_validation.get("error_code", "")})
	_body_id = body_id
	_frame_id = frame_id
	_river_feature = feature.duplicate(true)
	_fluid_surface = descriptor.duplicate(true)
	_manifest_hash = GeoUtilsScript.payload_hash({
		"provider_id": PROVIDER_ID,
		"provider_version": PROVIDER_VERSION,
		"river_feature": _river_feature,
		"fluid_surface": _fluid_surface,
	})
	_configured = true
	return GeoUtilsScript.success({
		"provider_id": PROVIDER_ID,
		"provider_version": PROVIDER_VERSION,
		"feature_id": String(_river_feature["feature_id"]),
		"fluid_region_id": String(_fluid_surface["fluid_region_id"]),
		"manifest_hash": _manifest_hash,
	})


func install_into_graph(feature_graph) -> Dictionary:
	if not _configured:
		return GeoUtilsScript.failure("CASUAL_RIVER_PROVIDER_NOT_CONFIGURED")
	if feature_graph == null or not feature_graph.has_method("add_feature"):
		return GeoUtilsScript.failure("INVALID_CASUAL_RIVER_FEATURE_GRAPH")
	return feature_graph.add_feature(_river_feature.duplicate(true))


func query_surface(query: Dictionary) -> Dictionary:
	if not _configured:
		return GeoUtilsScript.failure("CASUAL_RIVER_PROVIDER_NOT_CONFIGURED")
	var query_validation: Dictionary = WaterSurfaceQueryScript.validate(query)
	if not bool(query_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_CASUAL_RIVER_WATER_QUERY", {"cause": query_validation.get("error_code", "")})
	if String(query["body_id"]) != _body_id:
		return GeoUtilsScript.failure("CASUAL_RIVER_QUERY_BODY_MISMATCH")
	if String(query["frame_id"]) != _frame_id:
		return GeoUtilsScript.failure("CASUAL_RIVER_QUERY_FRAME_MISMATCH")
	var region_filter := String(query["fluid_region_id"])
	if not region_filter.is_empty() and region_filter != String(_fluid_surface["fluid_region_id"]):
		return GeoUtilsScript.success({"matched": false, "reason": "FLUID_REGION_FILTER_MISS"})
	var spline: Dictionary = RiverFeatureScript.spline(_river_feature)
	var profile: Dictionary = RiverFeatureScript.channel_profile(_river_feature)
	var closest: Dictionary = RiverSplineScript.closest_sample(spline, query["position_m"])
	if not bool(closest.get("success", false)):
		return closest
	var distance_to_centerline := float(closest["details"]["distance_to_centerline_m"])
	if distance_to_centerline > float(query["max_distance_m"]):
		return GeoUtilsScript.success({
			"matched": false,
			"reason": "OUTSIDE_QUERY_DISTANCE",
			"distance_to_centerline_m": distance_to_centerline,
		})
	var normalized := float(closest["details"]["normalized_distance"])
	var profile_sample: Dictionary = RiverChannelProfileScript.sample(profile, normalized)
	if not bool(profile_sample.get("success", false)):
		return profile_sample
	var center := _vector3(closest["details"]["position_m"])
	var tangent := _vector3(closest["details"]["tangent"])
	var normal := center.normalized()
	if normal.length_squared() <= EPSILON_SQ:
		return GeoUtilsScript.failure("CASUAL_RIVER_ZERO_SURFACE_NORMAL")
	var flow_tangent := tangent - normal * tangent.dot(normal)
	if flow_tangent.length_squared() <= EPSILON_SQ:
		return GeoUtilsScript.failure("CASUAL_RIVER_ZERO_FLOW_TANGENT")
	flow_tangent = flow_tangent.normalized()
	var lateral := normal.cross(flow_tangent).normalized()
	var query_position := _vector3(query["position_m"])
	var lateral_offset := (query_position - center).dot(lateral)
	var half_width := float(profile_sample["details"]["width_m"]) * 0.5
	var inside_channel := absf(lateral_offset) <= half_width
	var surface_position := center + lateral * clampf(lateral_offset, -half_width, half_width)
	if String(spline["interpolation_mode"]) == RiverSplineScript.INTERPOLATION_SPHERICAL_RADIAL and surface_position.length_squared() > EPSILON_SQ:
		surface_position = surface_position.normalized() * center.length()
	var flow_vector := flow_tangent * float(profile_sample["details"]["flow_speed_mps"])
	var sample := WaterSurfaceSampleScript.create(
		String(_river_feature["feature_id"]),
		String(_fluid_surface["fluid_region_id"]),
		_body_id,
		_frame_id,
		FLUID_TYPE_WATER,
		Array(query["position_m"]),
		_array3(center),
		_array3(surface_position),
		_array3(normal),
		_array3(flow_vector),
		float(profile_sample["details"]["width_m"]),
		float(profile_sample["details"]["depth_m"]),
		distance_to_centerline,
		normalized,
		inside_channel
	)
	var sample_validation: Dictionary = WaterSurfaceSampleScript.validate(sample)
	if not bool(sample_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_CASUAL_RIVER_WATER_SAMPLE", {"cause": sample_validation.get("error_code", "")})
	return GeoUtilsScript.success({"matched": true, "sample": sample})


func river_feature() -> Dictionary:
	return _river_feature.duplicate(true)


func fluid_surface_descriptor() -> Dictionary:
	return _fluid_surface.duplicate(true)


func manifest_hash() -> String:
	return _manifest_hash


func is_configured() -> bool:
	return _configured


func _derive_bounds(frame_id: String, river_spline: Dictionary, channel_profile: Dictionary) -> Dictionary:
	var center := Vector3.ZERO
	for point_value in river_spline["points"]:
		center += _vector3(point_value["position_m"])
	center /= float(river_spline["points"].size())
	var radius := 0.0
	for point_value in river_spline["points"]:
		radius = maxf(radius, center.distance_to(_vector3(point_value["position_m"])))
	var margin := maxf(float(channel_profile["width_source_m"]), float(channel_profile["width_mouth_m"])) * 0.5
	margin += maxf(float(channel_profile["depth_source_m"]), float(channel_profile["depth_mouth_m"]))
	margin += float(channel_profile["bank_falloff_m"])
	return FeatureBoundsScript.sphere(frame_id, _array3(center), radius + margin)


func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
