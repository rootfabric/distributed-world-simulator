extends RefCounted

const GravityMath = preload(
	"res://scripts/simulation/gravity/gravity_math.gd"
)

const SCHEMA: String = "planet_simulator.gravity_field.v1"

var root_frame_id: String = "simulation/root"
var sources: Dictionary = {}
var source_order: Array[String] = []
var celestial_system
var initialized: bool = false
var source_center_cache_valid: bool = false
var source_center_cache_time_s: float = 0.0
var source_center_cache: Dictionary = {}


func setup_static_sources(
	source_rows: Array,
	root_frame_id_value: String = "simulation/root"
) -> bool:
	_reset()
	root_frame_id = root_frame_id_value
	for source_value in source_rows:
		if not source_value is Dictionary:
			return false
		var normalized: Dictionary = _normalize_source(source_value)
		if normalized.is_empty():
			return false
		var source_id: String = String(normalized.get("id", ""))
		if sources.has(source_id):
			return false
		sources[source_id] = normalized
		source_order.append(source_id)
	initialized = not sources.is_empty()
	return initialized


func setup_celestial_system(
	system_reference,
	source_filter: Array[String] = []
) -> bool:
	_reset()
	if system_reference == null:
		return false
	celestial_system = system_reference
	root_frame_id = String(celestial_system.get_root_frame_id())
	var body_ids: Array[String] = []
	if celestial_system.has_method("get_gravity_body_ids"):
		body_ids = celestial_system.get_gravity_body_ids()
	else:
		body_ids = celestial_system.get_body_ids()
	for body_id in body_ids:
		if not source_filter.is_empty() and not source_filter.has(body_id):
			continue
		var body_config: Dictionary = celestial_system.get_body_config(body_id)
		body_config["id"] = body_id
		var normalized: Dictionary = _normalize_source(body_config)
		if normalized.is_empty():
			return false
		sources[body_id] = normalized
		source_order.append(body_id)
	initialized = not sources.is_empty()
	return initialized


func is_initialized() -> bool:
	return initialized


func get_root_frame_id() -> String:
	return root_frame_id


func get_source_ids() -> Array[String]:
	return source_order.duplicate()


func get_source(source_id: String) -> Dictionary:
	return Dictionary(sources.get(source_id, {})).duplicate(true)


func get_gravitational_parameter(source_id: String) -> float:
	return float(
		Dictionary(sources.get(source_id, {})).get(
			"gravitational_parameter_m3_s2",
			0.0
		)
	)


func get_circular_orbit_speed_mps(
	source_id: String,
	orbital_radius_m: float
) -> float:
	return GravityMath.circular_orbit_speed_mps(
		orbital_radius_m,
		get_gravitational_parameter(source_id)
	)


func get_escape_speed_mps(
	source_id: String,
	distance_from_center_m: float
) -> float:
	return GravityMath.escape_speed_mps(
		distance_from_center_m,
		get_gravitational_parameter(source_id)
	)


func get_acceleration_at_spatial_ref(spatial_ref: Dictionary) -> Vector3:
	return get_acceleration_at_position(
		_array_to_vector(spatial_ref.get("position_m", [])),
		String(spatial_ref.get("frame_id", root_frame_id)),
		float(spatial_ref.get("sample_time_s", _current_time_s())),
		String(spatial_ref.get("gravity_reference_body_id", ""))
	)


func get_acceleration_at_position(
	position_m: Vector3,
	frame_id: String = "",
	sample_time_s: float = INF,
	reference_body_id: String = ""
) -> Vector3:
	if not initialized:
		return Vector3.ZERO
	var resolved_frame_id: String = root_frame_id if frame_id.is_empty() else frame_id
	var resolved_time_s: float = _resolve_time(sample_time_s)
	var root_position_m: Vector3 = _to_root_position(
		position_m,
		resolved_frame_id,
		resolved_time_s
	)
	var acceleration_root_mps2: Vector3 = _sum_root_acceleration(
		root_position_m,
		resolved_time_s
	)
	var resolved_reference_body_id: String = _resolve_reference_body_id(
		reference_body_id,
		resolved_frame_id
	)
	if not resolved_reference_body_id.is_empty() and sources.has(resolved_reference_body_id):
		var reference_center_root_m: Vector3 = _source_center_root(
			resolved_reference_body_id,
			resolved_time_s
		)
		acceleration_root_mps2 -= _sum_root_acceleration(
			reference_center_root_m,
			resolved_time_s,
			resolved_reference_body_id
		)
	return _from_root_direction(
		acceleration_root_mps2,
		resolved_frame_id,
		resolved_time_s
	)


func get_contributions_at_position(
	position_m: Vector3,
	frame_id: String = "",
	sample_time_s: float = INF,
	reference_body_id: String = ""
) -> Array:
	var result: Array = []
	if not initialized:
		return result
	var resolved_frame_id: String = root_frame_id if frame_id.is_empty() else frame_id
	var resolved_time_s: float = _resolve_time(sample_time_s)
	var root_position_m: Vector3 = _to_root_position(
		position_m,
		resolved_frame_id,
		resolved_time_s
	)
	var resolved_reference_body_id: String = _resolve_reference_body_id(
		reference_body_id,
		resolved_frame_id
	)
	var reference_center_root_m: Vector3 = Vector3.ZERO
	if not resolved_reference_body_id.is_empty() and sources.has(resolved_reference_body_id):
		reference_center_root_m = _source_center_root(
			resolved_reference_body_id,
			resolved_time_s
		)
	for source_id in source_order:
		var acceleration_root_mps2: Vector3 = _source_acceleration_root(
			source_id,
			root_position_m,
			resolved_time_s
		)
		if (
			not resolved_reference_body_id.is_empty()
			and source_id != resolved_reference_body_id
		):
			acceleration_root_mps2 -= _source_acceleration_root(
				source_id,
				reference_center_root_m,
				resolved_time_s
			)
		var acceleration_frame_mps2: Vector3 = _from_root_direction(
			acceleration_root_mps2,
			resolved_frame_id,
			resolved_time_s
		)
		result.append({
			"source_id": source_id,
			"acceleration_mps2": _vector_to_array(acceleration_frame_mps2),
			"magnitude_mps2": acceleration_frame_mps2.length(),
			"distance_to_center_m": (
				root_position_m - _source_center_root(source_id, resolved_time_s)
			).length(),
		})
	return result


func get_dominant_source_id_at_position(
	position_m: Vector3,
	frame_id: String = "",
	sample_time_s: float = INF,
	reference_body_id: String = ""
) -> String:
	var dominant_id: String = ""
	var dominant_magnitude: float = -1.0
	for contribution_value in get_contributions_at_position(
		position_m,
		frame_id,
		sample_time_s,
		reference_body_id
	):
		var contribution: Dictionary = contribution_value
		var magnitude: float = float(contribution.get("magnitude_mps2", 0.0))
		if magnitude > dominant_magnitude:
			dominant_magnitude = magnitude
			dominant_id = String(contribution.get("source_id", ""))
	return dominant_id


func create_snapshot(sample_time_s: float = INF) -> Dictionary:
	var resolved_time_s: float = _resolve_time(sample_time_s)
	var rows: Array = []
	for source_id in source_order:
		var source: Dictionary = sources[source_id]
		rows.append({
			"id": source_id,
			"radius_m": float(source.get("radius_m", 0.0)),
			"gravitational_parameter_m3_s2": float(
				source.get("gravitational_parameter_m3_s2", 0.0)
			),
			"center_root_m": _vector_to_array(
				_source_center_root(source_id, resolved_time_s)
			),
			"interior_model": String(source.get("interior_model", "uniform_sphere")),
		})
	return {
		"schema": SCHEMA,
		"root_frame_id": root_frame_id,
		"sample_time_s": resolved_time_s,
		"source_count": rows.size(),
		"sources": rows,
		"superposition": true,
		"reference_frame_compensation": "external_acceleration_at_reference_body_center",
		"rotating_frame_pseudo_forces_included": false,
	}


func _sum_root_acceleration(
	root_position_m: Vector3,
	sample_time_s: float,
	excluded_source_id: String = ""
) -> Vector3:
	var total_mps2: Vector3 = Vector3.ZERO
	for source_id in source_order:
		if source_id == excluded_source_id:
			continue
		total_mps2 += _source_acceleration_root(
			source_id,
			root_position_m,
			sample_time_s
		)
	return total_mps2


func _source_acceleration_root(
	source_id: String,
	root_position_m: Vector3,
	sample_time_s: float
) -> Vector3:
	var source: Dictionary = sources.get(source_id, {})
	if source.is_empty() or not bool(source.get("enabled", true)):
		return Vector3.ZERO
	return GravityMath.acceleration_from_source(
		root_position_m,
		_source_center_root(source_id, sample_time_s),
		float(source.get("radius_m", 0.0)),
		float(source.get("gravitational_parameter_m3_s2", 0.0)),
		String(source.get("interior_model", GravityMath.DEFAULT_INTERIOR_MODEL))
	)


func _source_center_root(source_id: String, sample_time_s: float) -> Vector3:
	if celestial_system != null:
		if (
			not source_center_cache_valid
			or source_center_cache_time_s != sample_time_s
		):
			source_center_cache_valid = true
			source_center_cache_time_s = sample_time_s
			source_center_cache.clear()
		if not source_center_cache.has(source_id):
			source_center_cache[source_id] = celestial_system.get_body_center(
				source_id,
				sample_time_s
			)
		return source_center_cache.get(source_id, Vector3.ZERO)
	return _array_to_vector(
		Dictionary(sources.get(source_id, {})).get("center_m", [])
	)


func _to_root_position(
	position_m: Vector3,
	frame_id: String,
	sample_time_s: float
) -> Vector3:
	if frame_id == root_frame_id:
		return position_m
	if celestial_system == null:
		return position_m
	return celestial_system.transform_point(
		position_m,
		frame_id,
		root_frame_id,
		sample_time_s
	)


func _from_root_direction(
	direction: Vector3,
	frame_id: String,
	sample_time_s: float
) -> Vector3:
	if frame_id == root_frame_id or celestial_system == null:
		return direction
	return celestial_system.transform_direction(
		direction,
		root_frame_id,
		frame_id,
		sample_time_s
	)


func _resolve_reference_body_id(
	explicit_reference_body_id: String,
	frame_id: String
) -> String:
	if not explicit_reference_body_id.is_empty():
		return explicit_reference_body_id
	if celestial_system != null and celestial_system.has_method("get_reference_body_for_frame"):
		return String(celestial_system.get_reference_body_for_frame(frame_id))
	return ""


func _normalize_source(source_value: Dictionary) -> Dictionary:
	var source_id: String = String(source_value.get("id", "")).strip_edges()
	var radius_m: float = float(source_value.get("radius_m", 0.0))
	var gravitational_parameter_m3_s2: float = GravityMath.resolve_gravitational_parameter(
		source_value
	)
	if source_id.is_empty() or radius_m <= 0.0 or gravitational_parameter_m3_s2 <= 0.0:
		return {}
	return {
		"id": source_id,
		"radius_m": radius_m,
		"gravitational_parameter_m3_s2": gravitational_parameter_m3_s2,
		"interior_model": String(
			source_value.get("interior_model", GravityMath.DEFAULT_INTERIOR_MODEL)
		),
		"center_m": _vector_to_array(
			_array_to_vector(source_value.get("center_m", source_value.get("position_m", [])))
		),
		"enabled": bool(source_value.get("gravity_enabled", source_value.get("enabled", true))),
	}


func _resolve_time(sample_time_s: float) -> float:
	return _current_time_s() if sample_time_s == INF else sample_time_s


func _current_time_s() -> float:
	if celestial_system != null:
		return float(celestial_system.get_current_time_s())
	return 0.0


func _reset() -> void:
	root_frame_id = "simulation/root"
	sources.clear()
	source_order.clear()
	celestial_system = null
	initialized = false
	source_center_cache_valid = false
	source_center_cache_time_s = 0.0
	source_center_cache.clear()


func _array_to_vector(value) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _vector_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
