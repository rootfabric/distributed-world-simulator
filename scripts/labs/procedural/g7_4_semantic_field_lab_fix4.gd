extends "res://scripts/labs/procedural/g7_4_semantic_field_lab.gd"

const Fix4Registry = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")

# Fix4 is derived presentation only. The semantic records, canonical height values,
# field/provenance checksums, FeatureId/FluidRegionId and LOD policy remain untouched.
#
# The base lab used a fixed +0.045 display offset. With negative terrain heights,
# some vertices (and especially coarse triangle chords) could fall behind the
# radius-8 debug sphere and appear as false black holes. Fix4 derives one uniform
# radial shell lift from the already-sampled height range and reserves a generous
# minimum vertex clearance so even LOD3 coarse chords stay outside the sphere.
const FIX4_DISPLAY_RADIUS := 8.0
const FIX4_HEIGHT_SCALE := 0.00010
const FIX4_LEGACY_SURFACE_OFFSET := 0.045
const FIX4_MIN_VERTEX_CLEARANCE := 0.075

# The river is a diagnostic visualization of the accepted canonical centerline,
# not a physical-width water mesh. A small triangle-strip ribbon is intentionally
# used instead of a one-pixel PRIMITIVE_LINE_STRIP so it stays visible at all LODs.
const FIX4_RIVER_CLEARANCE_ABOVE_PATCH := 0.035
const FIX4_RIVER_HALF_WIDTH := 0.022

const FIX4_FIELD_KEYS: Array[String] = [
	Fix4Registry.SURFACE_HEIGHT_M,
	Fix4Registry.VALLEY_INFLUENCE,
	Fix4Registry.RIVER_DISTANCE_M,
	Fix4Registry.RIVER_WIDTH_M,
	Fix4Registry.FLUID_SURFACE_DISTANCE_M,
]


func _fix4_surface_height_range() -> Dictionary:
	return field_ranges.get(Fix4Registry.SURFACE_HEIGHT_M, {"min": 0.0, "max": 0.0})


func _fix4_shell_offset() -> float:
	var height_range := _fix4_surface_height_range()
	var min_height_m := float(height_range.get("min", 0.0))
	var clearance_offset := FIX4_MIN_VERTEX_CLEARANCE - min_height_m * FIX4_HEIGHT_SCALE
	return maxf(FIX4_LEGACY_SURFACE_OFFSET, clearance_offset)


func _fix4_patch_max_radius() -> float:
	var height_range := _fix4_surface_height_range()
	var max_height_m := float(height_range.get("max", 0.0))
	return FIX4_DISPLAY_RADIUS + _fix4_shell_offset() + max_height_m * FIX4_HEIGHT_SCALE


func _fix4_river_radius() -> float:
	return _fix4_patch_max_radius() + FIX4_RIVER_CLEARANCE_ABOVE_PATCH


func _add_patch_vertex(surface: SurfaceTool, record: Dictionary) -> void:
	var direction: Vector3 = record["direction"]
	var height_m := float(record["values"][Fix4Registry.SURFACE_HEIGHT_M])
	var display_radius := FIX4_DISPLAY_RADIUS + _fix4_shell_offset() + height_m * FIX4_HEIGHT_SCALE
	surface.set_color(_field_color(record, FIX4_FIELD_KEYS[current_field_index]))
	surface.add_vertex(direction * display_radius)


func _rebuild_river_overlay() -> void:
	if river_node == null:
		river_node = MeshInstance3D.new()
		river_node.name = "CanonicalRiverCenterlineRibbon"
		add_child(river_node)

	var points: Array = compiled_river.get("details", {}).get("river_spline", {}).get("points_m", [])
	if points.size() < 2:
		river_node.mesh = null
		return

	var radius := _fix4_river_radius()
	var angular_half_width := FIX4_RIVER_HALF_WIDTH / radius
	var directions: Array[Vector3] = []
	for raw_point in points:
		directions.append(_fix4_vector3(raw_point).normalized())

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for index in range(directions.size()):
		var direction := directions[index]
		var previous := directions[maxi(index - 1, 0)]
		var following := directions[mini(index + 1, directions.size() - 1)]
		var tangent := following - previous
		tangent -= direction * tangent.dot(direction)
		if tangent.length_squared() <= 0.000000000001:
			tangent = Vector3.UP.cross(direction)
			if tangent.length_squared() <= 0.000000000001:
				tangent = Vector3.RIGHT.cross(direction)
		tangent = tangent.normalized()
		var side := direction.cross(tangent).normalized()
		var left_direction := (direction + side * angular_half_width).normalized()
		var right_direction := (direction - side * angular_half_width).normalized()
		surface.add_vertex(left_direction * radius)
		surface.add_vertex(right_direction * radius)

	var mesh := surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.92, 1.0, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	river_node.mesh = mesh


func _fix4_vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
