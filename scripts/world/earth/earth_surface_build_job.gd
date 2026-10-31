extends RefCounted

# R3C3 R1: CPU-only deterministic Earth mesh staging. NO live world Node,
# ArrayMesh, RenderingServer, worker thread or gameplay authority in this job.
# The owning Earth scene advances a bounded number of operations per frame.
# The exact legacy sample/winding/normal ordering is preserved.
const PHASE_SAMPLES := "SAMPLES"
const PHASE_INDICES := "INDICES"
const PHASE_NORMAL_INIT := "NORMAL_INIT"
const PHASE_NORMAL_TRIANGLES := "NORMAL_TRIANGLES"
const PHASE_NORMAL_OUTPUT := "NORMAL_OUTPUT"
const PHASE_READY := "READY"
const PHASE_FAILED := "FAILED"

var _pipeline
var _mode := ""
var _phase := PHASE_FAILED
var _planet_radius_m := 0.0
var _global_segments := 0
var _global_rings := 0
var _global_offset_m := 0.0
var _local_radius_m := 0.0
var _local_rings := 0
var _local_segments := 0
var _center := Vector3.UP
var _east := Vector3.RIGHT
var _north := Vector3.FORWARD
var _anchor := Vector3.ZERO
var _debug_view := 0
var _sample_cursor := 0
var _sample_count := 0
var _index_cursor := 0
var _index_step_count := 0
var _normal_init_cursor := 0
var _triangle_cursor := 0
var _normal_output_cursor := 0
var _slope_sum := 0.0
var _maximum_slope := 0.0
var _statistics: Dictionary = {}
var _failure := ""

var _vertices := PackedVector3Array()
var _directions := PackedVector3Array()
var _colors := PackedColorArray()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()
var _accumulated: Array[Vector3] = []
var _normals := PackedVector3Array()


func configure_global(
	pipeline_reference, planet_radius: float, rings: int, segments: int,
	offset_m: float, debug_view: int = 0
) -> Dictionary:
	if pipeline_reference == null or not pipeline_reference.has_method("sample"):
		return _fail("R3C3_RULE_PIPELINE_REQUIRED")
	if rings < 1 or segments < 3 or planet_radius <= 0.0:
		return _fail("R3C3_GLOBAL_GEOMETRY_INVALID")
	_reset("global", pipeline_reference, planet_radius, debug_view)
	_global_segments = segments
	_global_rings = rings
	_global_offset_m = offset_m
	_sample_count = (rings + 1) * (segments + 1)
	_index_step_count = rings * segments
	return _ok()


func configure_local(
	pipeline_reference, planet_radius: float, radius_m: float,
	rings: int, segments: int,
	center: Vector3, east: Vector3, north: Vector3,
	anchor: Vector3, debug_view: int = 0
) -> Dictionary:
	if pipeline_reference == null or not pipeline_reference.has_method("sample"):
		return _fail("R3C3_RULE_PIPELINE_REQUIRED")
	if rings < 1 or segments < 3 or planet_radius <= 0.0 or radius_m <= 0.0:
		return _fail("R3C3_LOCAL_GEOMETRY_INVALID")
	if center.length_squared() < 0.99 or east.length_squared() < 0.99 or north.length_squared() < 0.99:
		return _fail("R3C3_LOCAL_BASIS_INVALID")
	_reset("local", pipeline_reference, planet_radius, debug_view)
	_local_radius_m = radius_m
	_local_rings = rings
	_local_segments = segments
	_center = center
	_east = east
	_north = north
	_anchor = anchor
	_sample_count = 1 + rings * segments
	_index_step_count = rings * segments
	return _ok()


func advance(max_units: int = 128, budget_us: int = 2000) -> Dictionary:
	if _phase == PHASE_FAILED:
		return _fail(_failure if not _failure.is_empty() else "R3C3_UNCONFIGURED_JOB")
	if max_units < 1 or budget_us < 1:
		return _fail("R3C3_INVALID_SLICE_BUDGET")
	var started_us: int = Time.get_ticks_usec()
	var done_units := 0
	while done_units < max_units and _phase != PHASE_READY:
		if done_units > 0 and Time.get_ticks_usec() - started_us >= budget_us:
			break
		match _phase:
			PHASE_SAMPLES:
				if _sample_cursor < _sample_count:
					_append_sample(_sample_cursor)
					_sample_cursor += 1
				else:
					_phase = PHASE_INDICES
			PHASE_INDICES:
				if _index_cursor < _index_step_count:
					_append_indices(_index_cursor)
					_index_cursor += 1
				else:
					_accumulated.resize(_vertices.size())
					_phase = PHASE_NORMAL_INIT
			PHASE_NORMAL_INIT:
				if _normal_init_cursor < _accumulated.size():
					_accumulated[_normal_init_cursor] = Vector3.ZERO
					_normal_init_cursor += 1
				else:
					_phase = PHASE_NORMAL_TRIANGLES
			PHASE_NORMAL_TRIANGLES:
				if _triangle_cursor < _indices.size():
					_accumulate_triangle(_triangle_cursor)
					_triangle_cursor += 3
				else:
					_phase = PHASE_NORMAL_OUTPUT
			PHASE_NORMAL_OUTPUT:
				if _normal_output_cursor < _vertices.size():
					_append_final_normal(_normal_output_cursor)
					_normal_output_cursor += 1
				else:
					_finalize_statistics()
					_accumulated.clear()
					_phase = PHASE_READY
			_:
				return _fail("R3C3_UNKNOWN_BUILD_PHASE")
		done_units += 1
	return {
		"success": true, "error_code": "",
		"details": {
			"phase": _phase, "processed_units": done_units,
			"elapsed_us": Time.get_ticks_usec() - started_us,
			"sampled": _sample_cursor, "sample_total": _sample_count,
			"index_steps": _index_cursor, "index_total": _index_step_count,
			"ready": is_ready(),
		},
	}


func is_ready() -> bool:
	return _phase == PHASE_READY


func get_arrays() -> Array:
	if not is_ready():
		return []
	# Packed*Array is copy-on-write and no sampling or mutation follows READY.
	# Building the GPU ArrayMesh is the Earth scene's main-thread responsibility.
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	return arrays


func get_statistics() -> Dictionary:
	return _statistics.duplicate(true) if is_ready() else {}


func get_report() -> Dictionary:
	return {
		"mode": _mode, "phase": _phase,
		"ready": is_ready(), "error": _failure,
		"sampled": _sample_cursor, "sample_total": _sample_count,
		"index_steps": _index_cursor, "index_total": _index_step_count,
		"normal_triangles": _triangle_cursor / 3,
		"normal_vertices": _normal_output_cursor,
		"vertex_count": _vertices.size(),
		"index_count": _indices.size(),
	}


func _reset(mode: String, pipeline_reference, planet_radius: float, debug_view: int) -> void:
	_pipeline = pipeline_reference
	_mode = mode
	_phase = PHASE_SAMPLES
	_planet_radius_m = planet_radius
	_debug_view = debug_view
	_sample_cursor = 0
	_index_cursor = 0
	_normal_init_cursor = 0
	_triangle_cursor = 0
	_normal_output_cursor = 0
	_slope_sum = 0.0
	_maximum_slope = 0.0
	_failure = ""
	_statistics = _new_statistics(mode)
	_vertices.clear()
	_directions.clear()
	_colors.clear()
	_uvs.clear()
	_indices.clear()
	_normals.clear()
	_accumulated.clear()


func _append_sample(cursor: int) -> void:
	if _mode == "global":
		var row: int = _global_segments + 1
		var ring_index: int = cursor / row
		var segment_index: int = cursor % row
		var ring_t: float = float(ring_index) / float(_global_rings)
		var latitude: float = ring_t * PI
		var y_value: float = cos(latitude)
		var horizontal: float = sin(latitude)
		var segment_t: float = float(segment_index) / float(_global_segments)
		var longitude: float = segment_t * TAU
		var direction := Vector3(
			horizontal * cos(longitude),
			y_value,
			horizontal * sin(longitude)
		).normalized()
		var state: Dictionary = _pipeline.sample(direction, 2)
		_accumulate_statistics(state)
		var elevation: float = float(state.get("elevation_m", 0.0)) + _global_offset_m
		_vertices.append(direction * (_planet_radius_m + elevation))
		_directions.append(direction)
		_colors.append(_display_color(state))
		_uvs.append(Vector2(segment_t, ring_t))
	else:
		if cursor == 0:
			var center_state: Dictionary = _pipeline.sample(_center, 0)
			_accumulate_statistics(center_state)
			_vertices.append(_surface_point(_center, center_state) - _anchor)
			_directions.append(_center)
			_colors.append(_display_color(center_state))
			_uvs.append(Vector2(0.5, 0.5))
			return
		var index: int = cursor - 1
		var ring_index: int = 1 + index / _local_segments
		var segment_index: int = index % _local_segments
		var ring_t: float = float(ring_index) / float(_local_rings)
		var radius_m: float = _local_radius_m * pow(ring_t, 1.55)
		var angle: float = float(segment_index) / float(_local_segments) * TAU
		var tangent_offset: Vector3 = (
			_east * cos(angle) + _north * sin(angle)
		) * radius_m
		var direction: Vector3 = (
			_center + tangent_offset / _planet_radius_m
		).normalized()
		var state: Dictionary = _pipeline.sample(direction, 0)
		_accumulate_statistics(state)
		_vertices.append(_surface_point(direction, state) - _anchor)
		_directions.append(direction)
		_colors.append(_display_color(state))
		_uvs.append(Vector2(
			0.5 + cos(angle) * ring_t * 0.5,
			0.5 + sin(angle) * ring_t * 0.5
		))


func _append_indices(cursor: int) -> void:
	if _mode == "global":
		var ring_index: int = cursor / _global_segments
		var segment_index: int = cursor % _global_segments
		var row: int = _global_segments + 1
		var i0: int = ring_index * row + segment_index
		var i1: int = i0 + 1
		var i2: int = i0 + row
		var i3: int = i2 + 1
		_indices.append_array(PackedInt32Array([i0, i2, i1, i1, i2, i3]))
	else:
		var segment_index: int = cursor % _local_segments
		if cursor < _local_segments:
			var current: int = 1 + segment_index
			var next: int = 1 + (segment_index + 1) % _local_segments
			_indices.append_array(PackedInt32Array([0, current, next]))
		else:
			var ring_index: int = 1 + (cursor - _local_segments) / _local_segments
			var current_start: int = 1 + (ring_index - 1) * _local_segments
			var next_start: int = current_start + _local_segments
			var next_segment: int = (segment_index + 1) % _local_segments
			var i0: int = current_start + segment_index
			var i1: int = current_start + next_segment
			var i2: int = next_start + segment_index
			var i3: int = next_start + next_segment
			_indices.append_array(PackedInt32Array([i0, i2, i1, i1, i2, i3]))


func _accumulate_triangle(triangle_start: int) -> void:
	var i0: int = _indices[triangle_start]
	var i1: int = _indices[triangle_start + 1]
	var i2: int = _indices[triangle_start + 2]
	var normal: Vector3 = (
		_vertices[i1] - _vertices[i0]
	).cross(_vertices[i2] - _vertices[i0])
	if normal.dot(_directions[i0]) < 0.0:
		normal = -normal
	_accumulated[i0] += normal
	_accumulated[i1] += normal
	_accumulated[i2] += normal


func _append_final_normal(index: int) -> void:
	var normal: Vector3 = _accumulated[index].normalized()
	if normal.length_squared() < 0.5:
		normal = _directions[index]
	_normals.append(normal)
	var dot_value: float = clampf(normal.dot(_directions[index]), -1.0, 1.0)
	var slope_deg: float = rad_to_deg(acos(dot_value))
	_slope_sum += slope_deg
	_maximum_slope = maxf(_maximum_slope, slope_deg)


func _finalize_statistics() -> void:
	var sample_count: int = maxi(1, int(_statistics.get("sample_count", 0)))
	var minimum_elevation: float = float(_statistics.get("minimum_elevation_m", 0.0))
	var maximum_elevation: float = float(_statistics.get("maximum_elevation_m", 0.0))
	_statistics["average_elevation_m"] = float(_statistics.get("elevation_sum_m", 0.0)) / sample_count
	_statistics["relief_range_m"] = maximum_elevation - minimum_elevation
	_statistics["average_mountain_mask"] = float(
		_statistics.get("mountain_mask_sum", 0.0)
	) / sample_count
	_statistics["water_fraction"] = float(
		_statistics.get("water_sample_count", 0)
	) / sample_count
	_statistics["snow_fraction"] = float(_statistics.get("snow_sample_count", 0)) / sample_count
	# The original _build_normals creates precisely one normal per vertex,
	# and the final legacy slope pass traverses them in this same order.
	var slope_count: int = mini(_normals.size(), _directions.size())
	_statistics["average_geometric_slope_deg"] = _slope_sum / maxi(1, slope_count)
	_statistics["maximum_geometric_slope_deg"] = _maximum_slope
	_statistics.erase("elevation_sum_m")
	_statistics.erase("mountain_mask_sum")


func _new_statistics(label: String) -> Dictionary:
	return {
		"label": label,
		"sample_count": 0,
		"minimum_elevation_m": INF,
		"maximum_elevation_m": -INF,
		"elevation_sum_m": 0.0,
		"mountain_mask_sum": 0.0,
		"water_sample_count": 0,
		"snow_sample_count": 0,
		"biome_counts": {},
	}


func _accumulate_statistics(state: Dictionary) -> void:
	var elevation: float = float(state.get("elevation_m", 0.0))
	_statistics["sample_count"] = int(_statistics["sample_count"]) + 1
	_statistics["minimum_elevation_m"] = minf(
		float(_statistics["minimum_elevation_m"]),
		elevation
	)
	_statistics["maximum_elevation_m"] = maxf(
		float(_statistics["maximum_elevation_m"]),
		elevation
	)
	_statistics["elevation_sum_m"] = float(_statistics["elevation_sum_m"]) + elevation
	_statistics["mountain_mask_sum"] = (
		float(_statistics["mountain_mask_sum"])
		+ float(state.get("mountain_mask", 0.0))
	)
	if int(state.get("water_kind", 0)) != 0:
		_statistics["water_sample_count"] = int(_statistics["water_sample_count"]) + 1
	if float(state.get("snow_mask", 0.0)) > 0.18:
		_statistics["snow_sample_count"] = int(_statistics["snow_sample_count"]) + 1
	var biome_key: String = str(int(state.get("biome_code", -1)))
	var biome_counts: Dictionary = _statistics["biome_counts"]
	biome_counts[biome_key] = int(biome_counts.get(biome_key, 0)) + 1


func _surface_point(direction: Vector3, state: Dictionary) -> Vector3:
	return direction * (_planet_radius_m + float(state.get("elevation_m", 0.0)))


func _display_color(state: Dictionary) -> Color:
	if _debug_view == 1:
		match int(state.get("biome_code", -1)):
			0:
				return Color(0.02, 0.16, 0.48)
			1:
				return Color(0.02, 0.55, 0.90)
			2:
				return Color(0.95, 0.62, 0.08)
			3:
				return Color(0.68, 0.88, 1.0)
			4:
				return Color(0.02, 0.48, 0.06)
			5:
				return Color(0.52, 0.78, 0.08)
			6:
				return Color(1.0, 1.0, 1.0)
			7:
				return Color(0.40, 0.36, 0.34)
	if _debug_view == 2:
		var elevation: float = float(state.get("elevation_m", 0.0))
		var normalized: float = clampf((elevation + 6500.0) / 14_000.0, 0.0, 1.0)
		return Color(normalized, normalized, normalized)
	if _debug_view == 3:
		return Color(
			float(state.get("tree_density", 0.0)),
			float(state.get("grass_density", 0.0)),
			float(state.get("rock_density", 0.0))
		)
	return state.get("surface_color", Color.MAGENTA)


func _ok() -> Dictionary:
	return {"success": true, "error_code": ""}


func _fail(error_code: String) -> Dictionary:
	_failure = error_code
	_phase = PHASE_FAILED
	return {"success": false, "error_code": error_code}
