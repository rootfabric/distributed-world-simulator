extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FeatureIdScript = preload("res://scripts/simulation/procedural/contracts/feature_id.gd")
const WaterSurfaceQueryScript = preload("res://scripts/simulation/procedural/contracts/water_surface_query.gd")
const WaterSurfaceSampleScript = preload("res://scripts/simulation/procedural/contracts/water_surface_sample.gd")
const FluidSurfaceDescriptorScript = preload("res://scripts/simulation/procedural/contracts/fluid_surface_descriptor.gd")
const RiverSplineScript = preload("res://scripts/simulation/procedural/contracts/river_spline.gd")
const RiverChannelProfileScript = preload("res://scripts/simulation/procedural/contracts/river_channel_profile.gd")

const RESOLVER_ID: String = "hydro-resolver/water-surface-v1"
const RESOLVER_VERSION: String = "1.0.0"
const CURVE_SUBDIVISIONS_PER_SEGMENT: int = 16
const EPSILON_SQ: float = 0.000000000001
const DISTANCE_EPSILON_M: float = 0.000001


static func resolve(query: Dictionary, compiled_geographies: Array) -> Dictionary:
	var query_validation: Dictionary = WaterSurfaceQueryScript.validate(query)
	if not bool(query_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_G6_3_WATER_SURFACE_QUERY", {"cause": query_validation.get("error_code", "")})

	var eligible_count := 0
	var best_sample: Dictionary = {}
	for index in range(compiled_geographies.size()):
		var prepared: Dictionary = _prepare_candidate(compiled_geographies[index])
		if not bool(prepared.get("success", false)):
			return GeoUtilsScript.failure("INVALID_G6_3_COMPILED_GEOGRAPHY", {
				"index": index,
				"cause": prepared.get("error_code", ""),
			})
		var candidate: Dictionary = prepared["details"]["candidate"]
		var descriptor: Dictionary = candidate["fluid_surface_descriptor"]
		if String(descriptor["body_id"]) != String(query["body_id"]):
			continue
		if String(descriptor["frame_id"]) != String(query["frame_id"]):
			continue
		if not query["fluid_type_ids"].has(String(descriptor["fluid_type_id"])):
			continue
		eligible_count += 1

		var sampled: Dictionary = _sample_candidate(candidate, query)
		if not bool(sampled.get("success", false)):
			return sampled
		var sample: Dictionary = sampled["details"]["sample"]
		if float(sample["distance_to_surface_m"]) > float(query["max_distance_m"]) + DISTANCE_EPSILON_M:
			continue
		if best_sample.is_empty() or _is_better_sample(sample, best_sample):
			best_sample = sample

	if best_sample.is_empty():
		return GeoUtilsScript.success({
			"matched": false,
			"reason": "NO_FLUID_SURFACE_WITHIN_DISTANCE",
			"eligible_candidates": eligible_count,
			"resolver_id": RESOLVER_ID,
			"resolver_version": RESOLVER_VERSION,
		})

	return GeoUtilsScript.success({
		"matched": true,
		"sample": best_sample,
		"eligible_candidates": eligible_count,
		"resolver_id": RESOLVER_ID,
		"resolver_version": RESOLVER_VERSION,
	})


static func _prepare_candidate(raw_candidate) -> Dictionary:
	if typeof(raw_candidate) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("G6_3_CANDIDATE_NOT_DICTIONARY")
	var candidate: Dictionary = Dictionary(raw_candidate)
	if candidate.has("success"):
		if not bool(candidate.get("success", false)):
			return GeoUtilsScript.failure("G6_3_SOURCE_PROVIDER_RESULT_FAILED")
		if typeof(candidate.get("details")) != TYPE_DICTIONARY:
			return GeoUtilsScript.failure("G6_3_SOURCE_PROVIDER_DETAILS_REQUIRED")
		candidate = Dictionary(candidate["details"])

	for field in ["source_feature_id", "fluid_region_id", "river_spline", "channel_profile", "fluid_surface_descriptor"]:
		if not candidate.has(field):
			return GeoUtilsScript.failure("G6_3_CANDIDATE_FIELD_REQUIRED", {"field": field})
	if not bool(FeatureIdScript.validate(candidate["source_feature_id"]).get("success", false)):
		return GeoUtilsScript.failure("INVALID_G6_3_SOURCE_FEATURE_ID")
	if typeof(candidate["river_spline"]) != TYPE_DICTIONARY or not bool(RiverSplineScript.validate(candidate["river_spline"]).get("success", false)):
		return GeoUtilsScript.failure("INVALID_G6_3_RIVER_SPLINE")
	if typeof(candidate["channel_profile"]) != TYPE_DICTIONARY or not bool(RiverChannelProfileScript.validate(candidate["channel_profile"]).get("success", false)):
		return GeoUtilsScript.failure("INVALID_G6_3_CHANNEL_PROFILE")
	if typeof(candidate["fluid_surface_descriptor"]) != TYPE_DICTIONARY or not bool(FluidSurfaceDescriptorScript.validate(candidate["fluid_surface_descriptor"]).get("success", false)):
		return GeoUtilsScript.failure("INVALID_G6_3_FLUID_SURFACE_DESCRIPTOR")

	var region_id := String(candidate["fluid_region_id"])
	var spline: Dictionary = candidate["river_spline"]
	var profile: Dictionary = candidate["channel_profile"]
	var descriptor: Dictionary = candidate["fluid_surface_descriptor"]
	if region_id != String(spline["fluid_region_id"]) or region_id != String(profile["fluid_region_id"]) or region_id != String(descriptor["fluid_region_id"]):
		return GeoUtilsScript.failure("G6_3_FLUID_REGION_COMPOSITION_MISMATCH")
	if String(candidate["source_feature_id"]) != String(descriptor["source_feature_id"]):
		return GeoUtilsScript.failure("G6_3_SOURCE_FEATURE_COMPOSITION_MISMATCH")
	if String(spline["frame_id"]) != String(descriptor["frame_id"]):
		return GeoUtilsScript.failure("G6_3_FRAME_COMPOSITION_MISMATCH")
	if String(descriptor["surface_mode"]) != FluidSurfaceDescriptorScript.PROFILED:
		return GeoUtilsScript.failure("UNSUPPORTED_G6_3_FLUID_SURFACE_MODE")

	return GeoUtilsScript.success({"candidate": candidate.duplicate(true)})


static func _sample_candidate(candidate: Dictionary, query: Dictionary) -> Dictionary:
	var spline: Dictionary = candidate["river_spline"]
	var closest: Dictionary = _closest_centerline_sample(spline, _vector3(query["position_m"]))
	if not bool(closest.get("success", false)):
		return closest
	var closest_details: Dictionary = closest["details"]
	var downstream_t := float(closest_details["downstream_t"])
	var channel: Dictionary = _interpolate_channel(candidate["channel_profile"], downstream_t)
	if not bool(channel.get("success", false)):
		return channel
	var channel_details: Dictionary = channel["details"]

	var query_position := _vector3(query["position_m"])
	var centerline_position := _vector3(closest_details["position_m"])
	var surface_normal := centerline_position.normalized()
	if surface_normal.length_squared() <= EPSILON_SQ:
		return GeoUtilsScript.failure("G6_3_ZERO_SURFACE_NORMAL")
	var tangent := _vector3(closest_details["tangent"])
	var flow_direction := tangent - surface_normal * tangent.dot(surface_normal)
	if flow_direction.length_squared() <= EPSILON_SQ:
		return GeoUtilsScript.failure("G6_3_ZERO_FLOW_DIRECTION")
	flow_direction = flow_direction.normalized()
	var lateral := surface_normal.cross(flow_direction)
	if lateral.length_squared() <= EPSILON_SQ:
		return GeoUtilsScript.failure("G6_3_ZERO_LATERAL_DIRECTION")
	lateral = lateral.normalized()

	var lateral_offset := (query_position - centerline_position).dot(lateral)
	var half_width := float(channel_details["width_m"]) * 0.5
	var inside_channel := absf(lateral_offset) <= half_width + DISTANCE_EPSILON_M
	var surface_position := centerline_position + lateral * clampf(lateral_offset, -half_width, half_width)
	if surface_position.length_squared() > EPSILON_SQ:
		surface_position = surface_position.normalized() * centerline_position.length()
	var final_normal := surface_position.normalized()
	if final_normal.length_squared() <= EPSILON_SQ:
		return GeoUtilsScript.failure("G6_3_ZERO_FINAL_SURFACE_NORMAL")

	var descriptor: Dictionary = candidate["fluid_surface_descriptor"]
	var sample := WaterSurfaceSampleScript.create(
		String(candidate["source_feature_id"]),
		String(candidate["fluid_region_id"]),
		String(descriptor["body_id"]),
		String(descriptor["frame_id"]),
		String(descriptor["fluid_type_id"]),
		Array(query["position_m"]),
		_array3(centerline_position),
		_array3(surface_position),
		_array3(final_normal),
		_array3(flow_direction),
		float(channel_details["width_m"]),
		float(channel_details["depth_m"]),
		float(channel_details["bank_width_m"]),
		query_position.distance_to(centerline_position),
		query_position.distance_to(surface_position),
		downstream_t,
		inside_channel
	)
	var sample_validation: Dictionary = WaterSurfaceSampleScript.validate(sample)
	if not bool(sample_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_G6_3_WATER_SURFACE_SAMPLE", {"cause": sample_validation.get("error_code", "")})
	return GeoUtilsScript.success({"sample": sample})


static func _closest_centerline_sample(spline: Dictionary, query_position: Vector3) -> Dictionary:
	var points: Array = spline["points_m"]
	var segment_count := points.size() - 1
	var best_distance_squared := INF
	var best_t := 0.0
	var best_position := Vector3.ZERO
	var best_tangent := Vector3.ZERO

	for segment_index in range(segment_count):
		var p0 := _vector3(points[segment_index])
		var p1 := _vector3(points[segment_index + 1])
		for subdivision in range(CURVE_SUBDIVISIONS_PER_SEGMENT):
			var ta := float(subdivision) / float(CURVE_SUBDIVISIONS_PER_SEGMENT)
			var tb := float(subdivision + 1) / float(CURVE_SUBDIVISIONS_PER_SEGMENT)
			var a := _sample_radial_segment(p0, p1, ta)
			var b := _sample_radial_segment(p0, p1, tb)
			var chord := b - a
			var chord_length_squared := chord.length_squared()
			if chord_length_squared <= EPSILON_SQ:
				continue
			var local_u := clampf((query_position - a).dot(chord) / chord_length_squared, 0.0, 1.0)
			var candidate_position := a.lerp(b, local_u)
			var target_radius := lerpf(a.length(), b.length(), local_u)
			if candidate_position.length_squared() > EPSILON_SQ:
				candidate_position = candidate_position.normalized() * target_radius
			var distance_squared := query_position.distance_squared_to(candidate_position)
			var local_segment_t := (float(subdivision) + local_u) / float(CURVE_SUBDIVISIONS_PER_SEGMENT)
			var global_t := (float(segment_index) + local_segment_t) / float(segment_count)
			if distance_squared < best_distance_squared - EPSILON_SQ or (absf(distance_squared - best_distance_squared) <= EPSILON_SQ and global_t < best_t):
				best_distance_squared = distance_squared
				best_t = global_t
				best_position = candidate_position
				best_tangent = chord

	if best_distance_squared == INF or best_tangent.length_squared() <= EPSILON_SQ:
		return GeoUtilsScript.failure("G6_3_NO_VALID_RIVER_SEGMENT")
	return GeoUtilsScript.success({
		"position_m": _array3(best_position),
		"tangent": _array3(best_tangent.normalized()),
		"downstream_t": clampf(best_t, 0.0, 1.0),
	})


static func _interpolate_channel(profile: Dictionary, downstream_t: float) -> Dictionary:
	var samples: Array = profile["samples"]
	var t := clampf(downstream_t, 0.0, 1.0)
	for index in range(samples.size() - 1):
		var left: Dictionary = samples[index]
		var right: Dictionary = samples[index + 1]
		var left_t := float(left["t"])
		var right_t := float(right["t"])
		if t <= right_t + 0.000000001:
			var span := right_t - left_t
			var alpha := 0.0 if span <= 0.0 else clampf((t - left_t) / span, 0.0, 1.0)
			return GeoUtilsScript.success({
				"width_m": lerpf(float(left["width_m"]), float(right["width_m"]), alpha),
				"depth_m": lerpf(float(left["depth_m"]), float(right["depth_m"]), alpha),
				"bank_width_m": lerpf(float(left["bank_width_m"]), float(right["bank_width_m"]), alpha),
			})
	var last: Dictionary = samples[samples.size() - 1]
	return GeoUtilsScript.success({
		"width_m": float(last["width_m"]),
		"depth_m": float(last["depth_m"]),
		"bank_width_m": float(last["bank_width_m"]),
	})


static func _sample_radial_segment(a: Vector3, b: Vector3, t: float) -> Vector3:
	if a.length_squared() <= EPSILON_SQ or b.length_squared() <= EPSILON_SQ:
		return a.lerp(b, t)
	var a_dir := a.normalized()
	var b_dir := b.normalized()
	if a_dir.dot(b_dir) < -0.999:
		return a.lerp(b, t)
	var direction := a_dir.slerp(b_dir, t)
	if direction.length_squared() <= EPSILON_SQ:
		return a.lerp(b, t)
	return direction.normalized() * lerpf(a.length(), b.length(), t)


static func _is_better_sample(candidate: Dictionary, current: Dictionary) -> bool:
	var candidate_distance := float(candidate["distance_to_surface_m"])
	var current_distance := float(current["distance_to_surface_m"])
	if candidate_distance < current_distance - DISTANCE_EPSILON_M:
		return true
	if absf(candidate_distance - current_distance) <= DISTANCE_EPSILON_M:
		return String(candidate["fluid_region_id"]) < String(current["fluid_region_id"])
	return false


static func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
