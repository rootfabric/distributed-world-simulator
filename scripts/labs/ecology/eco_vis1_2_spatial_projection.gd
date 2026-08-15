extends "res://scripts/labs/ecology/eco_vis1_1_environment_proving_ground.gd"

const SpatialDemoTimeline = preload("res://scripts/research/ecology/eco_obs1_spatial_demo_timeline_v1.gd")
const VIS1_2_STAGE := "ECO.VIS1.2"
const ACTIVE_FRAME_INDEX := 5
const PATCH_LAYOUT_RADIUS_M := 135.0
const PATCH_DISC_RADIUS_M := 24.0

var _spatial_timeline: Dictionary = {}
var _spatial_snapshot: Dictionary = {}
var _projection_hash := ""
var _timeline_valid := false
var _patch_world_positions: Dictionary = {}
var _projection_root: Node3D


func _ready() -> void:
	_spatial_timeline = SpatialDemoTimeline.build()
	var timeline_validation: Dictionary = SpatialDemoTimeline.validate(_spatial_timeline)
	_timeline_valid = bool(timeline_validation.get("success", false))
	if _timeline_valid:
		var frames: Array = _spatial_timeline.get("frames", [])
		if ACTIVE_FRAME_INDEX >= 0 and ACTIVE_FRAME_INDEX < frames.size() and typeof(frames[ACTIVE_FRAME_INDEX]) == TYPE_DICTIONARY:
			_spatial_snapshot = Dictionary(frames[ACTIVE_FRAME_INDEX]).duplicate(true)
	super._ready()
	$HUD/Margin/Panel/VBox/Title.text = "ECO.VIS1.2 — Spatial Ecology Projection"
	if not _spatial_snapshot.is_empty():
		_build_spatial_projection()
	_controls_label.text = "WASD move | Q/E down/up | Shift boost | mouse look | Esc capture | Home reset\nColored discs/columns are derived population diagnostics, not PH5 plant geometry"
	_update_status()


func get_spatial_snapshot() -> Dictionary:
	return _spatial_snapshot.duplicate(true)


func get_projection_hash() -> String:
	return _projection_hash


func get_patch_world_position(patch_id: String) -> Vector3:
	return Vector3(_patch_world_positions.get(patch_id, Vector3.ZERO))


func rebuild_spatial_projection() -> void:
	_build_spatial_projection()
	_update_status()


func _build_spatial_projection() -> void:
	if is_instance_valid(_projection_root):
		_projection_root.free()
	_projection_root = Node3D.new()
	_projection_root.name = "SpatialEcologyProjection"
	add_child(_projection_root)
	_patch_world_positions.clear()

	var patch_order := PackedStringArray(_spatial_snapshot.get("patch_order", PackedStringArray()))
	if patch_order.is_empty():
		_projection_hash = ""
		return

	for index in range(patch_order.size()):
		var patch_id := String(patch_order[index])
		var angle := -PI * 0.5 + TAU * float(index) / float(patch_order.size())
		var x := cos(angle) * PATCH_LAYOUT_RADIUS_M
		var z := sin(angle) * PATCH_LAYOUT_RADIUS_M
		var y := sample_terrain_height(x, z)
		_patch_world_positions[patch_id] = Vector3(x, y, z)

	_build_dispersal_links()
	var patches: Array = _spatial_snapshot.get("patches", [])
	for patch_variant in patches:
		if typeof(patch_variant) != TYPE_DICTIONARY:
			continue
		_build_patch_glyph(Dictionary(patch_variant), patch_order)
	_projection_hash = _compute_projection_hash(patch_order)


func _build_dispersal_links() -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.78, 0.87, 0.96, 0.72)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for edge_variant in Array(_spatial_snapshot.get("edges", [])):
		if typeof(edge_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_variant
		var from_id := String(edge.get("from", ""))
		var to_id := String(edge.get("to", ""))
		if not _patch_world_positions.has(from_id) or not _patch_world_positions.has(to_id):
			continue
		var a: Vector3 = _patch_world_positions[from_id]
		var b: Vector3 = _patch_world_positions[to_id]
		mesh.surface_add_vertex(a + Vector3.UP * 2.0)
		mesh.surface_add_vertex(b + Vector3.UP * 2.0)
	mesh.surface_end()
	var links := MeshInstance3D.new()
	links.name = "DispersalLinks"
	links.mesh = mesh
	_projection_root.add_child(links)


func _build_patch_glyph(patch: Dictionary, patch_order: PackedStringArray) -> void:
	var patch_id := String(patch.get("id", ""))
	if not _patch_world_positions.has(patch_id):
		return
	var patch_index := patch_order.find(patch_id)
	var center: Vector3 = _patch_world_positions[patch_id]
	var patch_root := Node3D.new()
	patch_root.name = "Patch_%s" % patch_id
	patch_root.position = center
	_projection_root.add_child(patch_root)

	var disc := MeshInstance3D.new()
	disc.name = "PatchDisc"
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = PATCH_DISC_RADIUS_M
	disc_mesh.bottom_radius = PATCH_DISC_RADIUS_M
	disc_mesh.height = 0.24
	disc_mesh.radial_segments = 48
	var disc_material := StandardMaterial3D.new()
	disc_material.albedo_color = _patch_color(patch_index, 0.30)
	disc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_material.roughness = 0.85
	disc_mesh.material = disc_material
	disc.mesh = disc_mesh
	disc.position.y = 0.22
	patch_root.add_child(disc)

	var plants: Array = patch.get("plants", [])
	var plant_order := PackedStringArray(patch.get("plant_order", PackedStringArray()))
	for plant_index in range(plants.size()):
		if typeof(plants[plant_index]) != TYPE_DICTIONARY:
			continue
		var plant: Dictionary = plants[plant_index]
		var plant_id := String(plant.get("id", ""))
		var biomass := maxf(0.0, float(plant.get("final_biomass_kg", 0.0)))
		if biomass <= 0.000001:
			continue
		var angle := TAU * float(plant_index) / maxf(1.0, float(plants.size())) + 0.35
		var radial_offset := 8.0 if plants.size() > 1 else 0.0
		var local_x := cos(angle) * radial_offset
		var local_z := sin(angle) * radial_offset
		var world_x := center.x + local_x
		var world_z := center.z + local_z
		var local_ground := sample_terrain_height(world_x, world_z) - center.y
		var height := 2.5 + sqrt(biomass) * 4.0
		var radius := 1.0 + sqrt(biomass) * 0.55
		var glyph := MeshInstance3D.new()
		glyph.name = "Population_%s" % plant_id
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = radius * 0.78
		cylinder.bottom_radius = radius
		cylinder.height = height
		cylinder.radial_segments = 20
		var material := StandardMaterial3D.new()
		material.albedo_color = _plant_color(plant_order.find(plant_id))
		material.roughness = 0.72
		cylinder.material = material
		glyph.mesh = cylinder
		glyph.position = Vector3(local_x, local_ground + height * 0.5 + 0.32, local_z)
		patch_root.add_child(glyph)

	var label := Label3D.new()
	label.name = "PatchLabel"
	label.text = "Patch %s\n%.2f kg" % [patch_id, float(patch.get("final_total_biomass_kg", 0.0))]
	label.font_size = 34
	label.pixel_size = 0.06
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 16.0, 0.0)
	patch_root.add_child(label)


func _patch_color(index: int, alpha: float) -> Color:
	var palette: Array[Color] = [
		Color(0.16, 0.66, 0.52, alpha),
		Color(0.83, 0.58, 0.16, alpha),
		Color(0.48, 0.42, 0.82, alpha),
		Color(0.72, 0.32, 0.42, alpha),
	]
	return palette[posmod(index, palette.size())]


func _plant_color(index: int) -> Color:
	var palette: Array[Color] = [
		Color(0.35, 0.92, 0.38),
		Color(0.96, 0.68, 0.20),
		Color(0.38, 0.72, 0.96),
		Color(0.86, 0.40, 0.82),
	]
	return palette[posmod(maxi(index, 0), palette.size())]


func _compute_projection_hash(patch_order: PackedStringArray) -> String:
	var tokens := PackedStringArray([
		VIS1_2_STAGE,
		String(_spatial_snapshot.get("snapshot_hash", "")),
	])
	for patch_id in patch_order:
		var position: Vector3 = _patch_world_positions.get(String(patch_id), Vector3.ZERO)
		tokens.append("%s|%.6f|%.6f|%.6f" % [String(patch_id), position.x, position.y, position.z])
	return "\n".join(tokens).sha256_text()


func _update_status() -> void:
	if not is_instance_valid(_camera) or not is_instance_valid(_status_label) or _environment_provider == null:
		return
	var position := _camera.position
	var ground_y := sample_terrain_height(position.x, position.z)
	var context := sample_environment_context_at(position.x, position.z)
	var sample: Dictionary = context["environment"]
	var environment_validation: Dictionary = EnvironmentSample.validate(sample)
	var ecology_line := "ecology snapshot unavailable"
	var patch_lines := PackedStringArray()
	if not _spatial_snapshot.is_empty():
		ecology_line = "Ecology year=%.1f step=%d dispersal=%.2f | patches=%d | biomass=%.3fkg | snapshot=%s | projection=%s" % [
			float(_spatial_snapshot.get("year", 0.0)),
			int(_spatial_snapshot.get("step_index", -1)),
			float(_spatial_snapshot.get("dispersal_fraction", 0.0)),
			PackedStringArray(_spatial_snapshot.get("patch_order", PackedStringArray())).size(),
			float(_spatial_snapshot.get("total_final_biomass_kg", 0.0)),
			"VALID" if _timeline_valid else "INVALID",
			_projection_hash.substr(0, 12) if _projection_hash.length() == 64 else "pending",
		]
		for patch_variant in Array(_spatial_snapshot.get("patches", [])):
			if typeof(patch_variant) != TYPE_DICTIONARY:
				continue
			var patch: Dictionary = patch_variant
			var plant_tokens := PackedStringArray()
			for plant_variant in Array(patch.get("plants", [])):
				if typeof(plant_variant) == TYPE_DICTIONARY:
					var plant: Dictionary = plant_variant
					plant_tokens.append("%s=%.2f" % [String(plant.get("id", "")), float(plant.get("final_biomass_kg", 0.0))])
			patch_lines.append("%s %.2fkg [%s]" % [String(patch.get("id", "?")), float(patch.get("final_total_biomass_kg", 0.0)), ", ".join(plant_tokens)])
	_status_label.text = "%s | polygon %.0f x %.0f m | seed=%d | environment=%s\nCamera x=%7.1f y=%6.1f z=%7.1f | ground=%6.1f slope=%4.1f° water_dist=%5.1fm\nT=%5.1f°C | moisture=%.3f | light=%.3f | nutrients=%.3f | flood=%.3f | water=%.3f\n%s\nPatches: %s" % [
		VIS1_2_STAGE,
		TERRAIN_SIZE_M,
		TERRAIN_SIZE_M,
		int(_environment_provider.call("get_seed")),
		"VALID" if bool(environment_validation.get("success", false)) else "INVALID",
		position.x,
		position.y,
		position.z,
		ground_y,
		float(context["slope_degrees"]),
		float(context["water_distance_m"]),
		float(sample["temperature_c"]),
		float(sample["soil_moisture"]),
		float(sample["sunlight"]),
		float(sample["nutrients"]),
		float(sample["flood_frequency"]),
		float(context["water_availability"]),
		ecology_line,
		" | ".join(patch_lines),
	]
