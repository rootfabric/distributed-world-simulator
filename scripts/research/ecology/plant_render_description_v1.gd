extends RefCounted

const RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.plant_render_description.v1"
const MATERIALIZATION_SCHEMA := "distributed_world_simulator.ecology.plant_render_materialization.v1"
const VERSION := "1.0.0"

static func build(growth_graph: Dictionary) -> Dictionary:
	var graph_hash := String(growth_graph.get("graph_hash", ""))
	var segments: Array = growth_graph.get("segments", [])
	if graph_hash.length() != 64 or segments.is_empty():
		return {}
	var metrics: Dictionary = growth_graph.get("metrics", {})
	var height := maxf(0.001, float(metrics.get("height_m", _estimate_height(segments))))
	var radius := maxf(0.01, float(metrics.get("horizontal_radius_m", _estimate_radius(segments))))
	var branches: Array = []
	var foliage: Array = []
	for index in range(segments.size()):
		var segment: Dictionary = segments[index]
		if not _valid_segment(segment):
			return {}
		var a := _vec3(Array(segment["start"]))
		var b := _vec3(Array(segment["end"]))
		var midpoint_y := 0.5 * (a.y + b.y)
		var normalized_height := clampf(midpoint_y / height, 0.0, 1.0)
		var main_axis := bool(segment.get("main_axis", false))
		var base_radius := 0.035 if main_axis else 0.014
		var order_scale := 1.0 / (1.0 + 0.22 * float(maxi(0, int(segment.get("axis_order", 0)))))
		var taper_scale := lerpf(1.0, 0.34, normalized_height)
		var radius_start := maxf(0.0025, base_radius * order_scale * taper_scale)
		var radius_end := maxf(0.0015, radius_start * (0.78 if main_axis else 0.68))
		branches.append({
			"segment_id": String(segment["segment_id"]),
			"parent_segment_id": String(segment.get("parent_segment_id", "")),
			"main_axis": main_axis,
			"axis_order": int(segment.get("axis_order", 0)),
			"start": _vec_array(a),
			"end": _vec_array(b),
			"radius_start_m": radius_start,
			"radius_end_m": radius_end,
			"length_m": float(segment["length_m"]),
		})
		var leaf_count := 0 if index == 0 else (1 if main_axis else 2)
		for leaf_index in range(leaf_count):
			var t := 0.62 + 0.25 * _unit(graph_hash, "%s/leaf_t/%d" % [String(segment["segment_id"]), leaf_index])
			var p := a.lerp(b, t)
			var azimuth := 360.0 * _unit(graph_hash, "%s/leaf_rot/%d" % [String(segment["segment_id"]), leaf_index])
			var size := lerpf(0.045, 0.11, _unit(graph_hash, "%s/leaf_size/%d" % [String(segment["segment_id"]), leaf_index]))
			foliage.append({
				"anchor_id": "%s/l%02d" % [String(segment["segment_id"]), leaf_index],
				"segment_id": String(segment["segment_id"]),
				"position": _vec_array(p),
				"size_m": size,
				"azimuth_deg": azimuth,
				"bud": leaf_index == leaf_count - 1 and not main_axis,
			})
	var canopy_center := Vector3(0.0, height * 0.62, 0.0)
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"derived_representation": true,
		"source_graph_hash": graph_hash,
		"individual_seed": int(growth_graph.get("individual_seed", -1)),
		"development_traits_checksum": String(growth_graph.get("development_traits_checksum", "")),
		"branches": branches,
		"foliage_anchors": foliage,
		"canopy": {
			"center": _vec_array(canopy_center),
			"radius_xz_m": maxf(0.12, radius * 1.12),
			"height_m": maxf(0.20, height * 0.62),
			"base_y_m": maxf(0.0, height * 0.28),
		},
		"bounds": {
			"height_m": height,
			"radius_xz_m": maxf(radius, 0.01),
		},
	}
	result["render_description_hash"] = compute_hash(result)
	return result

static func materialize(description: Dictionary, profile: Dictionary) -> Dictionary:
	if not bool(validate(description).get("success", false)) or not bool(RendererProfile.validate(profile).get("success", false)):
		return {}
	var branches: Array = description["branches"]
	var foliage: Array = description["foliage_anchors"]
	var branch_fraction := float(profile["branch_fraction"])
	var foliage_fraction := float(profile["foliage_fraction"])
	var active_branch_count := clampi(int(ceil(float(branches.size()) * branch_fraction)), 0, branches.size())
	var active_foliage_count := clampi(int(ceil(float(foliage.size()) * foliage_fraction)), 0, foliage.size())
	if String(profile["branch_mode"]) == "TRUNK_ONLY":
		active_branch_count = 0
		for branch in branches:
			if bool(branch.get("main_axis", false)):
				active_branch_count += 1
	var materialization := {
		"schema": MATERIALIZATION_SCHEMA,
		"version": VERSION,
		"source_graph_hash": String(description["source_graph_hash"]),
		"render_description_hash": String(description["render_description_hash"]),
		"profile_id": String(profile["profile_id"]),
		"profile_hash": String(profile["profile_hash"]),
		"branch_primitive_count": active_branch_count,
		"foliage_instance_count": active_foliage_count,
		"canopy_primitive_count": 0 if String(profile["canopy_mode"]) == "NONE" else 1,
		"impostor_count": 1 if int(profile["impostor_resolution"]) > 0 else 0,
		"branch_sides": int(profile["branch_sides"]),
		"lod_class": int(profile["lod_class"]),
	}
	materialization["materialization_hash"] = compute_materialization_hash(materialization)
	return materialization

static func validate(description: Dictionary) -> Dictionary:
	if String(description.get("schema", "")) != SCHEMA or String(description.get("version", "")) != VERSION:
		return _failure("ECO_PH5_RENDER_DESCRIPTION_SCHEMA_VERSION_MISMATCH")
	if not bool(description.get("derived_representation", false)):
		return _failure("ECO_PH5_RENDER_DESCRIPTION_NOT_DERIVED")
	if String(description.get("source_graph_hash", "")).length() != 64:
		return _failure("ECO_PH5_RENDER_DESCRIPTION_INVALID_SOURCE_HASH")
	if not description.get("branches", []) is Array or not description.get("foliage_anchors", []) is Array:
		return _failure("ECO_PH5_RENDER_DESCRIPTION_INVALID_ARRAYS")
	var value := String(description.get("render_description_hash", ""))
	if value.length() != 64 or value != compute_hash(description):
		return _failure("ECO_PH5_RENDER_DESCRIPTION_HASH_MISMATCH")
	return _success()

static func compute_hash(description: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		String(description.get("source_graph_hash", "")),
		str(int(description.get("individual_seed", -1))),
		String(description.get("development_traits_checksum", "")),
	])
	for branch in Array(description.get("branches", [])):
		tokens.append("B|%s|%s|%d|%d|%s|%s|%.9f|%.9f|%.9f" % [
			String(branch.get("segment_id", "")),
			String(branch.get("parent_segment_id", "")),
			int(branch.get("main_axis", false)),
			int(branch.get("axis_order", 0)),
			_vec_token(Array(branch.get("start", []))),
			_vec_token(Array(branch.get("end", []))),
			float(branch.get("radius_start_m", 0.0)),
			float(branch.get("radius_end_m", 0.0)),
			float(branch.get("length_m", 0.0)),
		])
	for anchor in Array(description.get("foliage_anchors", [])):
		tokens.append("F|%s|%s|%s|%.9f|%.9f|%d" % [
			String(anchor.get("anchor_id", "")),
			String(anchor.get("segment_id", "")),
			_vec_token(Array(anchor.get("position", []))),
			float(anchor.get("size_m", 0.0)),
			float(anchor.get("azimuth_deg", 0.0)),
			int(anchor.get("bud", false)),
		])
	var canopy: Dictionary = description.get("canopy", {})
	tokens.append("C|%s|%.9f|%.9f|%.9f" % [
		_vec_token(Array(canopy.get("center", []))),
		float(canopy.get("radius_xz_m", 0.0)),
		float(canopy.get("height_m", 0.0)),
		float(canopy.get("base_y_m", 0.0)),
	])
	return "\n".join(tokens).sha256_text()

static func compute_materialization_hash(materialization: Dictionary) -> String:
	return "|".join(PackedStringArray([
		MATERIALIZATION_SCHEMA,
		VERSION,
		String(materialization.get("source_graph_hash", "")),
		String(materialization.get("render_description_hash", "")),
		String(materialization.get("profile_id", "")),
		String(materialization.get("profile_hash", "")),
		str(int(materialization.get("branch_primitive_count", 0))),
		str(int(materialization.get("foliage_instance_count", 0))),
		str(int(materialization.get("canopy_primitive_count", 0))),
		str(int(materialization.get("impostor_count", 0))),
		str(int(materialization.get("branch_sides", 0))),
		str(int(materialization.get("lod_class", 0))),
	])).sha256_text()

static func _valid_segment(segment: Dictionary) -> bool:
	if String(segment.get("segment_id", "")).is_empty():
		return false
	var start: Array = segment.get("start", [])
	var end: Array = segment.get("end", [])
	if start.size() != 3 or end.size() != 3:
		return false
	var length := float(segment.get("length_m", -1.0))
	return is_finite(length) and length > 0.0

static func _estimate_height(segments: Array) -> float:
	var value := 0.0
	for segment in segments:
		var s: Dictionary = segment
		var a := _vec3(Array(s.get("start", [0.0, 0.0, 0.0])))
		var b := _vec3(Array(s.get("end", [0.0, 0.0, 0.0])))
		value = maxf(value, maxf(a.y, b.y))
	return value

static func _estimate_radius(segments: Array) -> float:
	var value := 0.0
	for segment in segments:
		var s: Dictionary = segment
		for key in ["start", "end"]:
			var p := _vec3(Array(s.get(key, [0.0, 0.0, 0.0])))
			value = maxf(value, Vector2(p.x, p.z).length())
	return value

static func _unit(seed_text: String, key: String) -> float:
	var digest := (seed_text + "|" + key).sha256_text()
	return float(digest.substr(0, 12).hex_to_int()) / 281474976710655.0

static func _vec3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

static func _vec_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func _vec_token(values: Array) -> String:
	if values.size() != 3:
		return "INVALID"
	return "%.9f,%.9f,%.9f" % [float(values[0]), float(values[1]), float(values[2])]

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
