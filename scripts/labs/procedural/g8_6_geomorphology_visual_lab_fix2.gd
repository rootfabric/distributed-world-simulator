extends "res://scripts/labs/procedural/g8_6_geomorphology_visual_lab.gd"

# G8.6 FIX2 — presentation-only corridor alignment.
#
# The accepted G6 river centerline carries real radial elevation above the body
# reference radius. The original G8.6 lab projected its local corridor back to
# Fixture.RADIUS_M, which placed every sample tens of metres below the river in
# the PX/PZ seam area. G6 correctly measures full 3D distance to centerline, so
# the channel component was invisible. This wrapper preserves the real G6
# centerline radius. It changes presentation sampling only; canonical G8
# geomorphology contracts/formulas remain untouched.

const SEAM_BISECTION_STEPS := 56
const SEAM_TANGENT_EPSILON := 0.000001
const EPSILON_SQ := 0.000000000001


func _prepare_seam_frame() -> Dictionary:
	var points: Array = compiled_river.get("details", {}).get("river_spline", {}).get("points_m", [])
	if points.size() < 2:
		return {"success": false, "error_code": "G8_6_RIVER_POINTS_MISSING"}

	for index in range(points.size() - 1):
		var a := _vector3(points[index])
		var b := _vector3(points[index + 1])
		var addressed_a: Dictionary = addressing.direction_to_cell(Fixture.BODY_ID, _array3(a), ADDRESSING_LOD)
		var addressed_b: Dictionary = addressing.direction_to_cell(Fixture.BODY_ID, _array3(b), ADDRESSING_LOD)
		if not bool(addressed_a.get("success", false)) or not bool(addressed_b.get("success", false)):
			continue
		var face_a := String(addressed_a["details"]["cell"]["face"])
		var face_b := String(addressed_b["details"]["cell"]["face"])
		if not ((face_a == "PX" and face_b == "PZ") or (face_a == "PZ" and face_b == "PX")):
			continue

		var low := 0.0
		var high := 1.0
		var low_value := a.x - a.z
		var high_value := b.x - b.z
		if low_value * high_value > 0.0:
			continue
		for _step in range(SEAM_BISECTION_STEPS):
			var mid := (low + high) * 0.5
			var candidate := _sample_g6_radial_segment(a, b, mid)
			var value := candidate.x - candidate.z
			if absf(value) <= 0.000000001:
				low = mid
				high = mid
				break
			if (low_value <= 0.0 and value <= 0.0) or (low_value >= 0.0 and value >= 0.0):
				low = mid
				low_value = value
			else:
				high = mid
				high_value = value

		var t := (low + high) * 0.5
		seam_center_world = _sample_g6_radial_segment(a, b, t)
		if seam_center_world.length_squared() <= EPSILON_SQ:
			continue
		var radial := seam_center_world.normalized()
		var before := _sample_g6_radial_segment(a, b, clampf(t - SEAM_TANGENT_EPSILON, 0.0, 1.0))
		var after := _sample_g6_radial_segment(a, b, clampf(t + SEAM_TANGENT_EPSILON, 0.0, 1.0))
		var segment_tangent := after - before
		segment_tangent -= radial * segment_tangent.dot(radial)
		if segment_tangent.length_squared() <= EPSILON_SQ:
			continue
		tangent_along = segment_tangent.normalized()
		tangent_cross = radial.cross(tangent_along).normalized()
		return {
			"success": true,
			"details": {
				"segment": index,
				"t": t,
				"centerline_radius_m": seam_center_world.length(),
				"reference_radius_m": Fixture.RADIUS_M,
				"radial_offset_m": seam_center_world.length() - Fixture.RADIUS_M,
			},
		}
	return {"success": false, "error_code": "G8_6_PX_PZ_SEAM_SEGMENT_NOT_FOUND"}


func _sample_corridor() -> Dictionary:
	records.clear()
	value_ranges.clear()
	observed_faces.clear()
	var corridor_radius_m := seam_center_world.length()
	if corridor_radius_m <= 0.0:
		return {"success": false, "error_code": "G8_6_INVALID_CORRIDOR_RADIUS"}

	for y in range(GRID_HEIGHT):
		var along_t := float(y) / float(ALONG_SEGMENTS)
		var along_m := lerpf(ALONG_MIN_M, ALONG_MAX_M, along_t)
		for x in range(GRID_WIDTH):
			var cross_t := float(x) / float(CROSS_SEGMENTS)
			var cross_m := lerpf(CROSS_MIN_M, CROSS_MAX_M, cross_t)
			var raw_position := seam_center_world + tangent_along * along_m + tangent_cross * cross_m
			var world_position := raw_position.normalized() * corridor_radius_m
			var query := SemanticQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, _array3(world_position), INPUT_FIELDS)
			var g3: Dictionary = G3Adapter.sample(query, macro_provider)
			var g5: Dictionary = G5Adapter.sample(query, feature_graph)
			var g6: Dictionary = G6Adapter.sample(query, [compiled_river])
			var composed: Dictionary = Composer.compose(query, [g3, g5, g6])
			if not bool(composed.get("success", false)):
				return {"success": false, "error_code": "G8_6_SEMANTIC_COMPOSITION_FAILED", "details": {"x": x, "y": y, "result": composed}}
			var bundle: Dictionary = composed["details"]["bundle"]
			var geomorph: Dictionary = ErosionDeposition.apply(bundle, profile)
			if not bool(geomorph.get("success", false)):
				return {"success": false, "error_code": "G8_6_GEOMORPHOLOGY_FAILED", "details": {"x": x, "y": y, "result": geomorph}}
			var deformation: Dictionary = geomorph["details"]["deformation"]
			var deformation_validation: Dictionary = Deformation.validate_against_profile(deformation, profile)
			if not bool(deformation_validation.get("success", false)):
				return {"success": false, "error_code": "G8_6_DEFORMATION_INVALID", "details": {"x": x, "y": y, "cause": deformation_validation}}
			var addressed: Dictionary = addressing.direction_to_cell(Fixture.BODY_ID, _array3(world_position), ADDRESSING_LOD)
			if not bool(addressed.get("success", false)):
				return addressed
			var face := String(addressed["details"]["cell"]["face"])
			observed_faces[face] = true
			var record: Dictionary = {
				"grid_x": x,
				"grid_y": y,
				"cross_m": cross_m,
				"along_m": along_m,
				"world_position_m": _array3(world_position),
				"face": face,
				"bundle_checksum": String(bundle["checksum"]),
				"river_distance_m": float(bundle["samples"][Registry.RIVER_DISTANCE_M]["value"]),
				"river_width_m": float(bundle["samples"][Registry.RIVER_WIDTH_M]["value"]),
				"source_surface_height_m": float(deformation["source_surface_height_m"]),
				"deformation": deformation,
			}
			records.append(record)
			_update_range(VIEW_RESOLVED_HEIGHT, float(deformation["resolved_surface_height_m"]))
			_update_range(VIEW_TOTAL_DELTA, float(deformation["total_delta_height_m"]))
			for component in Deformation.COMPONENT_FIELDS:
				_update_range(component, float(deformation["component_deltas_m"][component]))
	return {"success": true}


func _sample_g6_radial_segment(a: Vector3, b: Vector3, t: float) -> Vector3:
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
