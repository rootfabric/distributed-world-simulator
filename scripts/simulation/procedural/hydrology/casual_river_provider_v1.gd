extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FeatureTypeScript = preload("res://scripts/simulation/procedural/contracts/feature_type.gd")
const WorldFeatureScript = preload("res://scripts/simulation/procedural/contracts/world_feature.gd")
const FluidTypeScript = preload("res://scripts/simulation/procedural/contracts/fluid_type.gd")
const FluidRegionIdScript = preload("res://scripts/simulation/procedural/contracts/fluid_region_id.gd")
const FluidSurfaceDescriptorScript = preload("res://scripts/simulation/procedural/contracts/fluid_surface_descriptor.gd")
const RiverSplineScript = preload("res://scripts/simulation/procedural/contracts/river_spline.gd")
const RiverChannelProfileScript = preload("res://scripts/simulation/procedural/contracts/river_channel_profile.gd")

const PROVIDER_ID: String = "hydro-provider/casual-river-v1"
const PROVIDER_VERSION: String = "1.0.0"
const CONTROL_POINT_COUNT: int = 7
const EPSILON_SQ: float = 0.000000000001
const MAX_MEANDER_AMPLITUDE_M: float = 25000.0


static func compile(
	river_feature: Dictionary,
	valley_feature: Dictionary = {},
	fluid_type_id: String = "fluid-type/water"
) -> Dictionary:
	var river_validation: Dictionary = WorldFeatureScript.validate(river_feature)
	if not bool(river_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_G6_1_RIVER_FEATURE", {"cause": river_validation.get("error_code", "")})
	if String(river_feature.get("feature_type", "")) != FeatureTypeScript.RIVER:
		return GeoUtilsScript.failure("G6_1_SOURCE_FEATURE_NOT_RIVER")
	var type_validation: Dictionary = FluidTypeScript.validate(fluid_type_id)
	if not bool(type_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_G6_1_FLUID_TYPE", {"cause": type_validation.get("error_code", "")})

	var valley_validation: Dictionary = _validate_valley(river_feature, valley_feature)
	if not bool(valley_validation.get("success", false)):
		return valley_validation

	var source_anchor: Dictionary = _find_anchor(river_feature, "feature-anchor-role/source")
	var mouth_anchor: Dictionary = _find_anchor(river_feature, "feature-anchor-role/mouth")
	if source_anchor.is_empty():
		return GeoUtilsScript.failure("G6_1_RIVER_SOURCE_ANCHOR_REQUIRED")
	if mouth_anchor.is_empty():
		return GeoUtilsScript.failure("G6_1_RIVER_MOUTH_ANCHOR_REQUIRED")

	var source_position := _vector3(source_anchor["position_m"])
	var mouth_position := _vector3(mouth_anchor["position_m"])
	if source_position.distance_squared_to(mouth_position) <= EPSILON_SQ:
		return GeoUtilsScript.failure("G6_1_DEGENERATE_RIVER_ENDPOINTS")

	var source_feature_id: String = String(river_feature["feature_id"])
	var identity_hash: String = GeoUtilsScript.payload_hash({
		"provider_id": PROVIDER_ID,
		"source_feature_id": source_feature_id,
		"fluid_type_id": fluid_type_id,
	})
	var fluid_stable_key := "fluid-key/river-%s" % identity_hash
	var spline_stable_key := "river-spline-key/main-%s" % identity_hash
	var region_result: Dictionary = FluidRegionIdScript.derive(
		String(river_feature["body_id"]),
		fluid_type_id,
		int(river_feature["seed"]),
		String(river_feature["generator_version"]),
		fluid_stable_key
	)
	if not bool(region_result.get("success", false)):
		return GeoUtilsScript.failure("G6_1_FLUID_REGION_DERIVATION_FAILED", {"cause": region_result.get("error_code", "")})
	var fluid_region_id: String = String(region_result["details"]["fluid_region_id"])

	var geometry_salt: String = GeoUtilsScript.payload_hash({
		"river_feature_checksum": String(river_feature["checksum"]),
		"valley_feature_checksum": String(valley_feature.get("checksum", "")),
		"provider_version": PROVIDER_VERSION,
	})
	var spline_points: Array = _build_casual_points(source_position, mouth_position, geometry_salt)
	var spline: Dictionary = RiverSplineScript.create(
		fluid_region_id,
		spline_stable_key,
		String(river_feature["frame_id"]),
		spline_points
	)
	var spline_validation: Dictionary = RiverSplineScript.validate(spline)
	if not bool(spline_validation.get("success", false)):
		return GeoUtilsScript.failure("G6_1_GENERATED_SPLINE_INVALID", {"cause": spline_validation.get("error_code", "")})

	var channel_profile: Dictionary = _build_channel_profile(fluid_region_id, source_position.distance_to(mouth_position), source_feature_id)
	var channel_validation: Dictionary = RiverChannelProfileScript.validate(channel_profile)
	if not bool(channel_validation.get("success", false)):
		return GeoUtilsScript.failure("G6_1_GENERATED_CHANNEL_PROFILE_INVALID", {"cause": channel_validation.get("error_code", "")})

	var reference_level_m := 0.5 * (source_position.length() + mouth_position.length())
	var surface_descriptor: Dictionary = FluidSurfaceDescriptorScript.create(
		fluid_region_id,
		String(river_feature["body_id"]),
		fluid_type_id,
		int(river_feature["seed"]),
		String(river_feature["generator_version"]),
		fluid_stable_key,
		String(river_feature["frame_id"]),
		source_feature_id,
		Dictionary(river_feature["bounds"]),
		FluidSurfaceDescriptorScript.PROFILED,
		reference_level_m,
		{
			"provider_id": PROVIDER_ID,
			"provider_version": PROVIDER_VERSION,
			"river_spline_id": String(spline["spline_id"]),
			"river_spline_checksum": String(spline["checksum"]),
			"channel_profile_id": String(channel_profile["profile_id"]),
			"channel_profile_checksum": String(channel_profile["checksum"]),
			"valley_feature_id": String(valley_feature.get("feature_id", "")),
			"canonical_geography": true,
		}
	)
	var surface_validation: Dictionary = FluidSurfaceDescriptorScript.validate(surface_descriptor)
	if not bool(surface_validation.get("success", false)):
		return GeoUtilsScript.failure("G6_1_GENERATED_SURFACE_DESCRIPTOR_INVALID", {"cause": surface_validation.get("error_code", "")})

	var manifest_hash: String = GeoUtilsScript.payload_hash({
		"provider_id": PROVIDER_ID,
		"provider_version": PROVIDER_VERSION,
		"source_feature_id": source_feature_id,
		"valley_feature_id": String(valley_feature.get("feature_id", "")),
		"fluid_region_id": fluid_region_id,
		"spline_id": String(spline["spline_id"]),
		"spline_checksum": String(spline["checksum"]),
		"profile_id": String(channel_profile["profile_id"]),
		"profile_checksum": String(channel_profile["checksum"]),
		"surface_checksum": String(surface_descriptor["checksum"]),
	})
	return GeoUtilsScript.success({
		"provider_id": PROVIDER_ID,
		"provider_version": PROVIDER_VERSION,
		"source_feature_id": source_feature_id,
		"source_feature_checksum": String(river_feature["checksum"]),
		"valley_feature_id": String(valley_feature.get("feature_id", "")),
		"fluid_region_id": fluid_region_id,
		"river_spline": spline,
		"channel_profile": channel_profile,
		"fluid_surface_descriptor": surface_descriptor,
		"manifest_hash": manifest_hash,
	})


static func _validate_valley(river_feature: Dictionary, valley_feature: Dictionary) -> Dictionary:
	if valley_feature.is_empty():
		return GeoUtilsScript.success()
	var validation: Dictionary = WorldFeatureScript.validate(valley_feature)
	if not bool(validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_G6_1_VALLEY_FEATURE", {"cause": validation.get("error_code", "")})
	if String(valley_feature.get("feature_type", "")) != FeatureTypeScript.VALLEY:
		return GeoUtilsScript.failure("G6_1_SUPPORT_FEATURE_NOT_VALLEY")
	if String(valley_feature["body_id"]) != String(river_feature["body_id"]):
		return GeoUtilsScript.failure("G6_1_VALLEY_BODY_MISMATCH")
	if String(valley_feature["frame_id"]) != String(river_feature["frame_id"]):
		return GeoUtilsScript.failure("G6_1_VALLEY_FRAME_MISMATCH")
	var parent_feature_id := String(river_feature.get("parent_feature_id", ""))
	if not parent_feature_id.is_empty() and parent_feature_id != String(valley_feature["feature_id"]):
		return GeoUtilsScript.failure("G6_1_VALLEY_PARENT_MISMATCH")
	return GeoUtilsScript.success()


static func _find_anchor(feature: Dictionary, role: String) -> Dictionary:
	for raw_anchor in feature.get("anchors", []):
		if raw_anchor is Dictionary and String(raw_anchor.get("role", "")) == role:
			return Dictionary(raw_anchor).duplicate(true)
	return {}


static func _build_casual_points(source: Vector3, mouth: Vector3, geometry_salt: String) -> Array:
	var points: Array = []
	var chord_length := source.distance_to(mouth)
	var amplitude := minf(MAX_MEANDER_AMPLITUDE_M, maxf(25.0, chord_length * 0.015))
	var phase := _phase_from_hash(geometry_salt)
	var radial_mode := source.length_squared() > EPSILON_SQ and mouth.length_squared() > EPSILON_SQ
	var source_direction := source.normalized() if radial_mode else Vector3.ZERO
	var mouth_direction := mouth.normalized() if radial_mode else Vector3.ZERO
	var antipodal := radial_mode and source_direction.dot(mouth_direction) < -0.999

	for index in range(CONTROL_POINT_COUNT):
		var t := float(index) / float(CONTROL_POINT_COUNT - 1)
		if index == 0:
			points.append(_array3(source))
			continue
		if index == CONTROL_POINT_COUNT - 1:
			points.append(_array3(mouth))
			continue
		var base := source.lerp(mouth, t)
		var target_radius := lerpf(source.length(), mouth.length(), t)
		if radial_mode and not antipodal:
			base = source_direction.slerp(mouth_direction, t).normalized() * target_radius
		var normal := base.normalized() if base.length_squared() > EPSILON_SQ else Vector3.UP
		var forward := mouth - source
		var tangent := forward - normal * forward.dot(normal)
		if tangent.length_squared() <= EPSILON_SQ:
			tangent = normal.cross(Vector3.UP)
		if tangent.length_squared() <= EPSILON_SQ:
			tangent = normal.cross(Vector3.RIGHT)
		tangent = tangent.normalized()
		var lateral := normal.cross(tangent).normalized()
		var envelope := sin(PI * t)
		var wave := sin(TAU * 2.0 * t + phase)
		var candidate := base + lateral * amplitude * envelope * wave
		if radial_mode and candidate.length_squared() > EPSILON_SQ:
			candidate = candidate.normalized() * target_radius
		points.append(_array3(candidate))
	return points


static func _build_channel_profile(fluid_region_id: String, endpoint_distance_m: float, source_feature_id: String) -> Dictionary:
	var scale := clampf(sqrt(maxf(endpoint_distance_m, 1.0) / 500000.0), 0.5, 3.0)
	var source_width := 8.0 * scale
	var mouth_width := 28.0 * scale
	var source_depth := 1.2 * scale
	var mouth_depth := 4.8 * scale
	var source_bank := 3.0 * scale
	var mouth_bank := 12.0 * scale
	var samples: Array = []
	for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var downstream := float(t)
		samples.append(RiverChannelProfileScript.sample(
			downstream,
			lerpf(source_width, mouth_width, downstream),
			lerpf(source_depth, mouth_depth, downstream),
			lerpf(source_bank, mouth_bank, downstream)
		))
	return RiverChannelProfileScript.create(fluid_region_id, samples, {
		"provider_id": PROVIDER_ID,
		"provider_version": PROVIDER_VERSION,
		"source_feature_id": source_feature_id,
		"profile": "casual-river-v1",
	})


static func _phase_from_hash(hash_value: String) -> float:
	if hash_value.length() < 8:
		return 0.0
	var bucket := int(hash_value.substr(0, 8).hex_to_int()) % 1000000
	return TAU * float(bucket) / 1000000.0


static func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
