extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const SCHEMA: String = "planet_simulator.river_spline.v1"
const POINT_SCHEMA: String = "planet_simulator.river_spline_point.v1"
const POINT_ID_PREFIX: String = "river-point/"
const INTERPOLATION_PREFIX: String = "river-spline-interpolation/"
const INTERPOLATION_LINEAR: String = "river-spline-interpolation/linear"
const INTERPOLATION_SPHERICAL_RADIAL: String = "river-spline-interpolation/spherical-radial"
const FIELDS: Array[String] = ["schema", "frame_id", "interpolation_mode", "points", "checksum"]
const POINT_FIELDS: Array[String] = ["schema", "point_id", "position_m"]
const EPSILON_SQ: float = 0.000000000001
const SPHERICAL_COARSE_STEPS: int = 24
const SPHERICAL_REFINEMENT_STEPS: int = 24


static func point(point_id: String, position_m: Array) -> Dictionary:
	return {"schema": POINT_SCHEMA, "point_id": point_id, "position_m": position_m.duplicate()}


static func create(frame_id: String, points: Array, interpolation_mode: String = INTERPOLATION_SPHERICAL_RADIAL) -> Dictionary:
	var canonical_points: Array = []
	for raw_point in points:
		if raw_point is Dictionary:
			canonical_points.append(Dictionary(raw_point).duplicate(true))
	var value: Dictionary = {
		"schema": SCHEMA,
		"frame_id": frame_id,
		"interpolation_mode": interpolation_mode,
		"points": canonical_points,
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_RIVER_SPLINE_SCHEMA")
	if not GeoUtilsScript.is_canonical_id(value.get("frame_id"), 2):
		return GeoUtilsScript.failure("INVALID_RIVER_SPLINE_FRAME_ID")
	if not GeoUtilsScript.is_canonical_id(value.get("interpolation_mode"), 2) or not String(value["interpolation_mode"]).begins_with(INTERPOLATION_PREFIX):
		return GeoUtilsScript.failure("INVALID_RIVER_SPLINE_INTERPOLATION")
	if not String(value["interpolation_mode"]) in [INTERPOLATION_LINEAR, INTERPOLATION_SPHERICAL_RADIAL]:
		return GeoUtilsScript.failure("UNSUPPORTED_RIVER_SPLINE_INTERPOLATION")
	if typeof(value.get("points")) != TYPE_ARRAY or value["points"].size() < 2:
		return GeoUtilsScript.failure("RIVER_SPLINE_REQUIRES_TWO_POINTS")
	var seen: Dictionary = {}
	var previous_position := Vector3.ZERO
	for index in range(value["points"].size()):
		var raw_point = value["points"][index]
		if typeof(raw_point) != TYPE_DICTIONARY:
			return GeoUtilsScript.failure("INVALID_RIVER_SPLINE_POINT", {"index": index})
		var point_value: Dictionary = raw_point
		var point_fields: Dictionary = GeoUtilsScript.validate_exact_fields(point_value, POINT_FIELDS)
		if not bool(point_fields.get("success", false)):
			return GeoUtilsScript.failure("INVALID_RIVER_SPLINE_POINT", {"index": index, "cause": point_fields.get("error_code", "")})
		if String(point_value.get("schema", "")) != POINT_SCHEMA:
			return GeoUtilsScript.failure("INVALID_RIVER_SPLINE_POINT_SCHEMA", {"index": index})
		if not GeoUtilsScript.is_canonical_id(point_value.get("point_id"), 2) or not String(point_value["point_id"]).begins_with(POINT_ID_PREFIX):
			return GeoUtilsScript.failure("INVALID_RIVER_SPLINE_POINT_ID", {"index": index})
		if seen.has(String(point_value["point_id"])):
			return GeoUtilsScript.failure("DUPLICATE_RIVER_SPLINE_POINT_ID", {"index": index})
		seen[String(point_value["point_id"])] = true
		if not GeoUtilsScript.is_vector3_array(point_value.get("position_m")):
			return GeoUtilsScript.failure("INVALID_RIVER_SPLINE_POINT_POSITION", {"index": index})
		var position := _vector3(point_value["position_m"])
		if String(value["interpolation_mode"]) == INTERPOLATION_SPHERICAL_RADIAL and position.length_squared() <= EPSILON_SQ:
			return GeoUtilsScript.failure("ZERO_RIVER_SPLINE_RADIAL_POINT", {"index": index})
		if index > 0 and position.distance_squared_to(previous_position) <= EPSILON_SQ:
			return GeoUtilsScript.failure("DUPLICATE_ADJACENT_RIVER_SPLINE_POINT", {"index": index})
		previous_position = position
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.river_spline")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func total_length_m(value: Dictionary) -> Dictionary:
	var validation: Dictionary = validate(value)
	if not bool(validation.get("success", false)):
		return validation
	var lengths := _segment_lengths(value)
	var total := 0.0
	for segment_length in lengths:
		total += float(segment_length)
	return GeoUtilsScript.success({"length_m": total, "segment_lengths_m": lengths})


static func sample(value: Dictionary, normalized_distance: float) -> Dictionary:
	var validation: Dictionary = validate(value)
	if not bool(validation.get("success", false)):
		return validation
	if not is_finite(normalized_distance) or normalized_distance < 0.0 or normalized_distance > 1.0:
		return GeoUtilsScript.failure("RIVER_SPLINE_SAMPLE_OUT_OF_RANGE")
	var lengths := _segment_lengths(value)
	var total := 0.0
	for segment_length in lengths:
		total += float(segment_length)
	if total <= 0.0:
		return GeoUtilsScript.failure("ZERO_RIVER_SPLINE_LENGTH")
	var target := normalized_distance * total
	var cumulative := 0.0
	var segment_index := lengths.size() - 1
	var segment_t := 1.0
	for index in range(lengths.size()):
		var segment_length := float(lengths[index])
		if target <= cumulative + segment_length or index == lengths.size() - 1:
			segment_index = index
			segment_t = 0.0 if segment_length <= 0.0 else clampf((target - cumulative) / segment_length, 0.0, 1.0)
			break
		cumulative += segment_length
	var position := _sample_segment_position(value, segment_index, segment_t)
	var tangent := _segment_tangent(value, segment_index, segment_t)
	return GeoUtilsScript.success({
		"position_m": _array3(position),
		"tangent": _array3(tangent),
		"normalized_distance": normalized_distance,
		"distance_m": target,
		"total_length_m": total,
		"segment_index": segment_index,
		"segment_t": segment_t,
	})


static func closest_sample(value: Dictionary, position_m: Array) -> Dictionary:
	var validation: Dictionary = validate(value)
	if not bool(validation.get("success", false)):
		return validation
	if not GeoUtilsScript.is_vector3_array(position_m):
		return GeoUtilsScript.failure("INVALID_RIVER_SPLINE_QUERY_POSITION")
	var query := _vector3(position_m)
	var lengths := _segment_lengths(value)
	var total := 0.0
	for segment_length in lengths:
		total += float(segment_length)
	if total <= 0.0:
		return GeoUtilsScript.failure("ZERO_RIVER_SPLINE_LENGTH")
	var best_segment := 0
	var best_t := 0.0
	var best_distance_sq := INF
	var cumulative_before_best := 0.0
	var cumulative := 0.0
	for segment_index in range(lengths.size()):
		var candidate_t := _closest_t_on_segment(value, segment_index, query)
		var candidate_position := _sample_segment_position(value, segment_index, candidate_t)
		var candidate_distance_sq := candidate_position.distance_squared_to(query)
		if candidate_distance_sq < best_distance_sq:
			best_distance_sq = candidate_distance_sq
			best_segment = segment_index
			best_t = candidate_t
			cumulative_before_best = cumulative
		cumulative += float(lengths[segment_index])
	var distance_along := cumulative_before_best + float(lengths[best_segment]) * best_t
	var normalized := clampf(distance_along / total, 0.0, 1.0)
	var center := _sample_segment_position(value, best_segment, best_t)
	return GeoUtilsScript.success({
		"position_m": _array3(center),
		"tangent": _array3(_segment_tangent(value, best_segment, best_t)),
		"normalized_distance": normalized,
		"distance_m": distance_along,
		"total_length_m": total,
		"distance_to_centerline_m": sqrt(maxf(0.0, best_distance_sq)),
		"segment_index": best_segment,
		"segment_t": best_t,
	})


static func _segment_lengths(value: Dictionary) -> Array:
	var result: Array = []
	for index in range(value["points"].size() - 1):
		var a := _vector3(value["points"][index]["position_m"])
		var b := _vector3(value["points"][index + 1]["position_m"])
		if String(value["interpolation_mode"]) == INTERPOLATION_SPHERICAL_RADIAL:
			var radius_a := a.length()
			var radius_b := b.length()
			var angle := a.normalized().angle_to(b.normalized())
			var arc := 0.5 * (radius_a + radius_b) * angle
			var radial := radius_b - radius_a
			result.append(sqrt(arc * arc + radial * radial))
		else:
			result.append(a.distance_to(b))
	return result


static func _closest_t_on_segment(value: Dictionary, segment_index: int, query: Vector3) -> float:
	if String(value["interpolation_mode"]) == INTERPOLATION_LINEAR:
		var a := _vector3(value["points"][segment_index]["position_m"])
		var b := _vector3(value["points"][segment_index + 1]["position_m"])
		var ab := b - a
		return clampf((query - a).dot(ab) / maxf(ab.length_squared(), EPSILON_SQ), 0.0, 1.0)
	var best_t := 0.0
	var best_distance_sq := INF
	for step in range(SPHERICAL_COARSE_STEPS + 1):
		var t := float(step) / float(SPHERICAL_COARSE_STEPS)
		var distance_sq := _sample_segment_position(value, segment_index, t).distance_squared_to(query)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_t = t
	var half_window := 1.0 / float(SPHERICAL_COARSE_STEPS)
	var left := maxf(0.0, best_t - half_window)
	var right := minf(1.0, best_t + half_window)
	for _iteration in range(SPHERICAL_REFINEMENT_STEPS):
		var third := (right - left) / 3.0
		var t1 := left + third
		var t2 := right - third
		var d1 := _sample_segment_position(value, segment_index, t1).distance_squared_to(query)
		var d2 := _sample_segment_position(value, segment_index, t2).distance_squared_to(query)
		if d1 <= d2:
			right = t2
		else:
			left = t1
	return clampf((left + right) * 0.5, 0.0, 1.0)


static func _sample_segment_position(value: Dictionary, segment_index: int, t: float) -> Vector3:
	var a := _vector3(value["points"][segment_index]["position_m"])
	var b := _vector3(value["points"][segment_index + 1]["position_m"])
	if String(value["interpolation_mode"]) == INTERPOLATION_SPHERICAL_RADIAL:
		var direction := a.normalized().slerp(b.normalized(), t).normalized()
		return direction * lerpf(a.length(), b.length(), t)
	return a.lerp(b, t)


static func _segment_tangent(value: Dictionary, segment_index: int, t: float) -> Vector3:
	var delta := 0.0001
	var left := maxf(0.0, t - delta)
	var right := minf(1.0, t + delta)
	if right <= left:
		return Vector3.ZERO
	return (_sample_segment_position(value, segment_index, right) - _sample_segment_position(value, segment_index, left)).normalized()


static func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
