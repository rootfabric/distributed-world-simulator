extends Node3D

const CasualRiverProvider = preload("res://scripts/simulation/procedural/hydrology/casual_river_provider_v1.gd")
const WaterSurfaceQuery = preload("res://scripts/simulation/procedural/contracts/water_surface_query.gd")
const WaterSurfaceResolver = preload("res://scripts/simulation/procedural/hydrology/water_surface_resolver_v1.gd")
const FluidType = preload("res://scripts/simulation/procedural/contracts/fluid_type.gd")
const PlanetDefinition = preload("res://scripts/simulation/procedural/contracts/planet_definition.gd")
const BodyFixedPosition = preload("res://scripts/simulation/procedural/contracts/body_fixed_position.gd")
const SurfaceLodPolicy = preload("res://scripts/simulation/procedural/contracts/surface_lod_policy.gd")
const CubeSphereAddressing = preload("res://scripts/simulation/procedural/surface/cube_sphere_addressing.gd")
const SurfaceLodSelector = preload("res://scripts/simulation/procedural/surface/surface_lod_selector.gd")
const Fixture = preload("res://tests/procedural/fixtures/g6_2_cross_cell_river_fixture.gd")

const DISPLAY_RADIUS: float = 8.0
const WATER_OFFSET: float = 0.035
const GRID_OFFSET: float = 0.022
const WIDTH_EXAGGERATION: float = 5200.0
const BANK_EXAGGERATION: float = 3600.0
const QUERY_DISTANCE_M: float = 5.0
const EPSILON_SQ: float = 0.000000000001
const LOD_UPDATE_INTERVAL_S: float = 0.16
const LOD_MIN: int = 0
const LOD_MAX: int = 12
const LOD_REFINE_RATIO: float = 0.45
const LOD_COARSEN_RATIO: float = 0.30
const LOD_MIN_DISTANCE_M: float = 50.0
const LOD_LEAF_BUDGET: int = 1536
const RECIPE_ID: String = "planet-recipe/g6-4-visual-lab"
const SHAPE_ID: String = "body-shape/sphere-v1"
const MANIFEST_VERSION: String = "1.0.0"
const CAMERA_MIN_DISTANCE: float = DISPLAY_RADIUS + 0.006
const CAMERA_MAX_DISTANCE: float = 34.0

@onready var camera: Camera3D = $Camera3D
@onready var planet: MeshInstance3D = $Planet
@onready var hud: Label = $HUD/Panel/Margin/VBox/Status

var addressing = CubeSphereAddressing.new()
var selector = SurfaceLodSelector.new()
var compiled: Dictionary = {}
var visual_samples: Array = []
var face_sequence: Array[String] = []
var seam_transition_count: int = 0
var query_probe_count: int = 0

var current_leaves: Array = []
var current_leaf_tokens: Dictionary = {}
var current_selection_hash: String = ""
var current_max_lod: int = 0
var current_min_river_lod: int = 0
var current_max_river_lod: int = 0
var current_virtual_altitude_m: float = 0.0
var lod_update_accumulator: float = LOD_UPDATE_INTERVAL_S

var ribbon_node: MeshInstance3D
var centerline_node: MeshInstance3D
var bank_node: MeshInstance3D
var probe_node: MeshInstance3D
var seam_node: MeshInstance3D
var lod_grid_node: MeshInstance3D

var yaw_deg: float = 46.0
var pitch_deg: float = 6.0
var camera_distance: float = 19.5
var auto_orbit: bool = false


func _ready() -> void:
	compiled = CasualRiverProvider.compile(Fixture.river())
	if not bool(compiled.get("success", false)):
		_fail("provider compile", compiled)
		return

	var definition: Dictionary = PlanetDefinition.create(
		Fixture.BODY_ID,
		Fixture.SEED,
		RECIPE_ID,
		SHAPE_ID,
		Fixture.RADIUS_M,
		MANIFEST_VERSION
	)
	var policy: Dictionary = SurfaceLodPolicy.create(
		LOD_MIN,
		LOD_MAX,
		LOD_REFINE_RATIO,
		LOD_COARSEN_RATIO,
		LOD_MIN_DISTANCE_M,
		LOD_LEAF_BUDGET
	)
	var configured: Dictionary = selector.configure(definition, policy)
	if not bool(configured.get("success", false)):
		_fail("LOD selector configure", configured)
		return

	_setup_planet_material()
	_update_camera()
	var refreshed: Dictionary = _refresh_lod_presentation(true)
	if not bool(refreshed.get("success", false)):
		_fail("LOD presentation", refreshed)
		return
	_update_hud()

	if DisplayServer.get_name() == "headless":
		var smoke: Dictionary = _headless_smoke()
		if not bool(smoke.get("success", false)):
			_fail("headless smoke", smoke)
			return
		print("G6.4 Casual Visual River Lab: PASS (samples=%d probes=%d seams=%d faces=%s leaves=%d max_lod=%d river_lod=%d..%d)" % [
			visual_samples.size(),
			query_probe_count,
			seam_transition_count,
			",".join(face_sequence),
			current_leaves.size(),
			current_max_lod,
			current_min_river_lod,
			current_max_river_lod,
		])
		get_tree().quit(0)


func _process(delta: float) -> void:
	if auto_orbit:
		yaw_deg = fposmod(yaw_deg + 8.0 * delta, 360.0)
	_update_camera_from_input(delta)
	_update_camera()
	lod_update_accumulator += delta
	if lod_update_accumulator >= LOD_UPDATE_INTERVAL_S:
		lod_update_accumulator = 0.0
		var refreshed: Dictionary = _refresh_lod_presentation(false)
		if not bool(refreshed.get("success", false)):
			push_error("G6.4 LOD refresh failed: %s" % String(refreshed.get("error_code", "")))
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				if ribbon_node != null:
					ribbon_node.visible = not ribbon_node.visible
			KEY_2:
				if centerline_node != null:
					centerline_node.visible = not centerline_node.visible
			KEY_3:
				if bank_node != null:
					bank_node.visible = not bank_node.visible
			KEY_4:
				if probe_node != null:
					probe_node.visible = not probe_node.visible
			KEY_5:
				if seam_node != null:
					seam_node.visible = not seam_node.visible
			KEY_6:
				if lod_grid_node != null:
					lod_grid_node.visible = not lod_grid_node.visible
			KEY_SPACE:
				auto_orbit = not auto_orbit
			KEY_R:
				yaw_deg = 46.0
				pitch_deg = 6.0
				camera_distance = 19.5
				current_leaves = []
				current_selection_hash = ""
		_update_hud()


func _update_camera_from_input(delta: float) -> void:
	var orbit_speed: float = 32.0 * delta
	if Input.is_key_pressed(KEY_A):
		yaw_deg += orbit_speed
	if Input.is_key_pressed(KEY_D):
		yaw_deg -= orbit_speed
	if Input.is_key_pressed(KEY_Q):
		pitch_deg = clampf(pitch_deg + orbit_speed, -75.0, 75.0)
	if Input.is_key_pressed(KEY_E):
		pitch_deg = clampf(pitch_deg - orbit_speed, -75.0, 75.0)
	var altitude_display: float = maxf(camera_distance - DISPLAY_RADIUS, 0.0)
	var zoom_speed: float = clampf(altitude_display * 2.4 + 0.08, 0.08, 10.0) * delta
	if Input.is_key_pressed(KEY_W):
		camera_distance = maxf(CAMERA_MIN_DISTANCE, camera_distance - zoom_speed)
	if Input.is_key_pressed(KEY_S):
		camera_distance = minf(CAMERA_MAX_DISTANCE, camera_distance + zoom_speed)


func _update_camera() -> void:
	var yaw: float = deg_to_rad(yaw_deg)
	var pitch: float = deg_to_rad(pitch_deg)
	var cos_pitch: float = cos(pitch)
	camera.position = Vector3(
		cos_pitch * cos(yaw),
		sin(pitch),
		cos_pitch * sin(yaw)
	) * camera_distance
	camera.look_at(Vector3.ZERO, Vector3.UP)


func _setup_planet_material() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.34, 0.35, 0.37, 1.0)
	material.roughness = 0.96
	planet.material_override = material


func _refresh_lod_presentation(force_rebuild: bool) -> Dictionary:
	var observer: Dictionary = _virtual_observer_for_distance(camera_distance)
	var selected: Dictionary = selector.select_cells(observer, current_leaves)
	if not bool(selected.get("success", false)):
		return selected

	var details: Dictionary = selected["details"]
	var selection_hash: String = String(details["selection_hash"])
	current_virtual_altitude_m = _virtual_altitude_for_distance(camera_distance)
	if not force_rebuild and selection_hash == current_selection_hash:
		return {"success": true, "details": {"changed": false}}

	current_leaves = Array(details["leaves"]).duplicate(true)
	current_selection_hash = selection_hash
	current_max_lod = int(details["max_selected_lod"])
	current_leaf_tokens = _build_leaf_token_index(current_leaves)

	var built: Dictionary = _build_visual_samples()
	if not bool(built.get("success", false)):
		return built
	_rebuild_visual_nodes()
	return {
		"success": true,
		"details": {
			"changed": true,
			"leaf_count": current_leaves.size(),
			"max_lod": current_max_lod,
			"river_samples": visual_samples.size(),
		},
	}


func _virtual_observer_for_distance(display_distance: float) -> Dictionary:
	var direction: Vector3 = camera.position.normalized()
	var radius_m: float = Fixture.RADIUS_M + _virtual_altitude_for_distance(display_distance)
	var position: Vector3 = direction * radius_m
	return BodyFixedPosition.create(Fixture.BODY_ID, _array3(position))


func _virtual_altitude_for_distance(display_distance: float) -> float:
	var radial_scale: float = maxf(display_distance / DISPLAY_RADIUS, 1.0)
	return (radial_scale - 1.0) * Fixture.RADIUS_M


func _build_leaf_token_index(leaves: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_cell in leaves:
		var cell: Dictionary = Dictionary(raw_cell)
		result[_cell_token(cell)] = true
	return result


func _cell_token(cell: Dictionary) -> String:
	return "%s|%s|%d|%d|%d" % [
		String(cell["body_id"]),
		String(cell["face"]),
		int(cell["lod"]),
		int(cell["x"]),
		int(cell["y"]),
	]


func _selected_lod_for_direction(direction: Vector3, leaf_tokens: Dictionary, max_lod: int) -> int:
	for lod in range(max_lod, -1, -1):
		var addressed: Dictionary = addressing.direction_to_cell(Fixture.BODY_ID, _array3(direction), lod)
		if not bool(addressed.get("success", false)):
			continue
		var cell: Dictionary = Dictionary(addressed["details"]["cell"])
		if leaf_tokens.has(_cell_token(cell)):
			return lod
	return 0


func _subdivisions_for_lod(lod: int) -> int:
	var exponent: int = clampi(int(floor(float(lod) * 0.5)), 0, 5)
	return 1 << exponent


func _build_visual_samples() -> Dictionary:
	visual_samples.clear()
	face_sequence.clear()
	seam_transition_count = 0
	current_min_river_lod = LOD_MAX
	current_max_river_lod = 0

	var details: Dictionary = compiled["details"]
	var spline: Dictionary = details["river_spline"]
	var points: Array = spline["points_m"]
	var last_face: String = ""
	var seen_faces: Dictionary = {}

	for segment_index in range(points.size() - 1):
		var p0: Vector3 = _vector3(points[segment_index])
		var p1: Vector3 = _vector3(points[segment_index + 1])
		var midpoint: Vector3 = _sample_radial_segment(p0, p1, 0.5)
		var lod0: int = _selected_lod_for_direction(p0.normalized(), current_leaf_tokens, current_max_lod)
		var lodm: int = _selected_lod_for_direction(midpoint.normalized(), current_leaf_tokens, current_max_lod)
		var lod1: int = _selected_lod_for_direction(p1.normalized(), current_leaf_tokens, current_max_lod)
		var representation_lod: int = maxi(lod0, maxi(lodm, lod1))
		current_min_river_lod = mini(current_min_river_lod, representation_lod)
		current_max_river_lod = maxi(current_max_river_lod, representation_lod)
		var subdivisions: int = _subdivisions_for_lod(representation_lod)
		for subdivision in range(subdivisions):
			var local_t: float = float(subdivision) / float(subdivisions)
			var point: Vector3 = _sample_radial_segment(p0, p1, local_t)
			var global_t: float = (float(segment_index) + local_t) / float(points.size() - 1)
			var appended: Dictionary = _append_visual_sample(point, global_t, representation_lod, last_face, seen_faces)
			if not bool(appended.get("success", false)):
				return appended
			last_face = String(appended["details"]["face"])

	var final_point: Vector3 = _vector3(points[points.size() - 1])
	var final_lod: int = _selected_lod_for_direction(final_point.normalized(), current_leaf_tokens, current_max_lod)
	current_min_river_lod = mini(current_min_river_lod, final_lod)
	current_max_river_lod = maxi(current_max_river_lod, final_lod)
	var final_append: Dictionary = _append_visual_sample(final_point, 1.0, final_lod, last_face, seen_faces)
	if not bool(final_append.get("success", false)):
		return final_append

	for raw_sample in visual_samples:
		var sample: Dictionary = Dictionary(raw_sample)
		var face: String = String(sample["face"])
		if not face_sequence.has(face):
			face_sequence.append(face)

	if visual_samples.size() < 7:
		return {"success": false, "error_code": "G6_4_TOO_FEW_VISUAL_SAMPLES"}
	if not seen_faces.has("PX") or not seen_faces.has("PZ"):
		return {"success": false, "error_code": "G6_4_EXPECTED_PX_PZ_SEAM_NOT_OBSERVED", "details": {"faces": seen_faces.keys()}}
	if seam_transition_count < 1:
		return {"success": false, "error_code": "G6_4_SEAM_TRANSITION_NOT_OBSERVED"}
	return {"success": true}


func _append_visual_sample(
	point: Vector3,
	global_t: float,
	representation_lod: int,
	previous_face: String,
	seen_faces: Dictionary
) -> Dictionary:
	var query: Dictionary = WaterSurfaceQuery.create(
		Fixture.BODY_ID,
		Fixture.FRAME_ID,
		_array3(point),
		QUERY_DISTANCE_M,
		[FluidType.WATER]
	)
	var resolved: Dictionary = WaterSurfaceResolver.resolve(query, [compiled])
	if not bool(resolved.get("success", false)):
		return resolved
	if not bool(resolved["details"].get("matched", false)):
		return {"success": false, "error_code": "G6_4_QUERY_SAMPLE_NOT_MATCHED", "details": {"t": global_t}}
	var sample: Dictionary = Dictionary(resolved["details"]["sample"]).duplicate(true)
	var face_uv: Dictionary = addressing.direction_to_face_uv(sample["surface_position_m"])
	if not bool(face_uv.get("success", false)):
		return face_uv
	var face: String = String(face_uv["details"]["face"])
	seen_faces[face] = true
	if not previous_face.is_empty() and previous_face != face:
		seam_transition_count += 1
	sample["face"] = face
	sample["visual_t"] = global_t
	sample["representation_lod"] = representation_lod
	visual_samples.append(sample)
	return {"success": true, "details": {"face": face}}


func _rebuild_visual_nodes() -> void:
	ribbon_node = _set_mesh_node(ribbon_node, "RiverRibbon", _build_ribbon_mesh())
	centerline_node = _set_mesh_node(centerline_node, "CanonicalCenterline", _build_centerline_mesh())
	bank_node = _set_mesh_node(bank_node, "BankGuides", _build_bank_mesh())
	probe_node = _set_mesh_node(probe_node, "QueryProbes", _build_probe_mesh())
	seam_node = _set_mesh_node(seam_node, "CubeFaceSeamMarkers", _build_seam_mesh())
	lod_grid_node = _set_mesh_node(lod_grid_node, "SurfaceLodGrid", _build_lod_grid_mesh())


func _set_mesh_node(existing: MeshInstance3D, node_name: String, mesh: ImmediateMesh) -> MeshInstance3D:
	var node: MeshInstance3D = existing
	if node == null:
		node = MeshInstance3D.new()
		node.name = node_name
		add_child(node)
	node.mesh = mesh
	return node


func _build_ribbon_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, material)
	for raw_sample in visual_samples:
		var sample: Dictionary = Dictionary(raw_sample)
		var frame: Dictionary = _display_frame(sample)
		var center: Vector3 = frame["center"]
		var lateral: Vector3 = frame["lateral"]
		var half_width: float = _display_distance(float(sample["channel_width_m"]) * 0.5, WIDTH_EXAGGERATION)
		var representation_lod: int = int(sample["representation_lod"])
		var brightness: float = clampf(0.58 + float(representation_lod) * 0.035, 0.58, 1.0)
		var color: Color = Color(0.02, 0.42 * brightness, 0.95 * brightness, 0.84)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(center - lateral * half_width)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(center + lateral * half_width)
	mesh.surface_end()
	return mesh


func _build_centerline_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var material := _line_material()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for index in range(visual_samples.size() - 1):
		var a: Dictionary = Dictionary(visual_samples[index])
		var b: Dictionary = Dictionary(visual_samples[index + 1])
		var fa: Dictionary = _display_frame(a)
		var fb: Dictionary = _display_frame(b)
		var fa_center: Vector3 = fa["center"]
		var fb_center: Vector3 = fb["center"]
		mesh.surface_set_color(Color(1.0, 0.92, 0.18, 1.0))
		mesh.surface_add_vertex(fa_center + _normal_display(a) * 0.018)
		mesh.surface_set_color(Color(1.0, 0.92, 0.18, 1.0))
		mesh.surface_add_vertex(fb_center + _normal_display(b) * 0.018)
	mesh.surface_end()
	return mesh


func _build_bank_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var material := _line_material()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for index in range(visual_samples.size() - 1):
		for side_value in [-1.0, 1.0]:
			var side: float = float(side_value)
			var a: Dictionary = Dictionary(visual_samples[index])
			var b: Dictionary = Dictionary(visual_samples[index + 1])
			var fa: Dictionary = _display_frame(a)
			var fb: Dictionary = _display_frame(b)
			var da: float = _display_distance(float(a["channel_width_m"]) * 0.5 + float(a["bank_width_m"]), BANK_EXAGGERATION)
			var db: float = _display_distance(float(b["channel_width_m"]) * 0.5 + float(b["bank_width_m"]), BANK_EXAGGERATION)
			var fa_center: Vector3 = fa["center"]
			var fb_center: Vector3 = fb["center"]
			var fa_lateral: Vector3 = fa["lateral"]
			var fb_lateral: Vector3 = fb["lateral"]
			mesh.surface_set_color(Color(0.72, 0.48, 0.18, 0.9))
			mesh.surface_add_vertex(fa_center + fa_lateral * da * side + _normal_display(a) * 0.012)
			mesh.surface_set_color(Color(0.72, 0.48, 0.18, 0.9))
			mesh.surface_add_vertex(fb_center + fb_lateral * db * side + _normal_display(b) * 0.012)
	mesh.surface_end()
	return mesh


func _build_probe_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var material := _line_material()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	query_probe_count = 0
	var stride: int = maxi(1, int(floor(float(visual_samples.size() - 1) / 6.0)))
	for index in range(0, visual_samples.size(), stride):
		var sample: Dictionary = Dictionary(visual_samples[index])
		var frame: Dictionary = _display_frame(sample)
		var center: Vector3 = frame["center"]
		var normal: Vector3 = _normal_display(sample)
		var flow: Vector3 = _vector3(sample["flow_direction"]).normalized()
		mesh.surface_set_color(Color(1.0, 0.24, 0.16, 1.0))
		mesh.surface_add_vertex(center)
		mesh.surface_set_color(Color(1.0, 0.24, 0.16, 1.0))
		mesh.surface_add_vertex(center + normal * 0.42)
		mesh.surface_set_color(Color(0.35, 1.0, 0.32, 1.0))
		mesh.surface_add_vertex(center + normal * 0.03)
		mesh.surface_set_color(Color(0.35, 1.0, 0.32, 1.0))
		mesh.surface_add_vertex(center + normal * 0.03 + flow * 0.55)
		query_probe_count += 1
	mesh.surface_end()
	return mesh


func _build_seam_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var material := _line_material()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var previous_face: String = String(visual_samples[0]["face"])
	for index in range(1, visual_samples.size()):
		var sample: Dictionary = Dictionary(visual_samples[index])
		var face: String = String(sample["face"])
		if face != previous_face:
			var frame: Dictionary = _display_frame(sample)
			var center: Vector3 = frame["center"]
			var normal: Vector3 = _normal_display(sample)
			mesh.surface_set_color(Color(1.0, 0.1, 0.85, 1.0))
			mesh.surface_add_vertex(center - normal * 0.25)
			mesh.surface_set_color(Color(1.0, 0.1, 0.85, 1.0))
			mesh.surface_add_vertex(center + normal * 1.2)
		previous_face = face
	mesh.surface_end()
	return mesh


func _build_lod_grid_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var material := _line_material()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for raw_cell in current_leaves:
		var cell: Dictionary = Dictionary(raw_cell)
		var corners_result: Dictionary = addressing.cell_corner_directions(cell)
		if not bool(corners_result.get("success", false)):
			continue
		var corners: Array = corners_result["details"]["corners"]
		var lod: int = int(cell["lod"])
		var color: Color = Color.from_hsv(fposmod(float(lod) * 0.091, 1.0), 0.72, 1.0, 0.70)
		for edge in [[0, 1], [1, 2], [2, 3], [3, 0]]:
			var a: Vector3 = _vector3(corners[int(edge[0])]).normalized() * (DISPLAY_RADIUS + GRID_OFFSET)
			var b: Vector3 = _vector3(corners[int(edge[1])]).normalized() * (DISPLAY_RADIUS + GRID_OFFSET)
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(a)
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(b)
	mesh.surface_end()
	return mesh


func _display_frame(sample: Dictionary) -> Dictionary:
	var surface: Vector3 = _vector3(sample["surface_position_m"])
	var normal: Vector3 = surface.normalized()
	var flow: Vector3 = _vector3(sample["flow_direction"])
	flow = (flow - normal * flow.dot(normal)).normalized()
	var lateral: Vector3 = normal.cross(flow)
	if lateral.length_squared() <= EPSILON_SQ:
		lateral = normal.cross(Vector3.UP)
	if lateral.length_squared() <= EPSILON_SQ:
		lateral = normal.cross(Vector3.RIGHT)
	lateral = lateral.normalized()
	var altitude_display: float = (surface.length() - Fixture.RADIUS_M) / Fixture.RADIUS_M * DISPLAY_RADIUS
	return {
		"center": normal * (DISPLAY_RADIUS + WATER_OFFSET + altitude_display),
		"normal": normal,
		"flow": flow,
		"lateral": lateral,
	}


func _normal_display(sample: Dictionary) -> Vector3:
	return _vector3(sample["surface_normal"]).normalized()


func _display_distance(distance_m: float, exaggeration: float) -> float:
	return distance_m / Fixture.RADIUS_M * DISPLAY_RADIUS * exaggeration


func _line_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _update_hud() -> void:
	if hud == null or compiled.is_empty() or visual_samples.is_empty():
		return
	var details: Dictionary = compiled["details"]
	var midpoint: Dictionary = Dictionary(visual_samples[int(visual_samples.size() / 2)])
	hud.text = "G6.4 — Casual Visual River Lab + G2 adaptive LOD\n\nFeature: %s\nFluidRegion: %s\nFaces: %s   seam transitions: %d\nVirtual altitude: %.1f km   Leaves: %d / %d   Max LOD: %d\nRiver samples: %d   River representation LOD: %d..%d\nMid width/depth/bank: %.1f / %.1f / %.1f m\n\nBlue: derived water ribbon   Rainbow grid: active SurfaceCellKey LOD\nYellow: canonical centerline   Brown: bank guides   Magenta: cube-face seam\nRed/green: query normal / flow\n\nW/S zoom => refine/coarsen   A/D orbit   Q/E pitch   Space auto-orbit   R reset\n1 water   2 centerline   3 banks   4 probes   5 seam   6 LOD grid" % [
		String(details["source_feature_id"]).substr(0, 30),
		String(details["fluid_region_id"]).substr(0, 30),
		" / ".join(face_sequence),
		seam_transition_count,
		current_virtual_altitude_m / 1000.0,
		current_leaves.size(),
		LOD_LEAF_BUDGET,
		current_max_lod,
		visual_samples.size(),
		current_min_river_lod,
		current_max_river_lod,
		float(midpoint["channel_width_m"]),
		float(midpoint["channel_depth_m"]),
		float(midpoint["bank_width_m"]),
	]


func _headless_smoke() -> Dictionary:
	if visual_samples.size() < 7:
		return {"success": false, "error_code": "G6_4_HEADLESS_SAMPLE_COUNT_TOO_SMALL"}
	if query_probe_count < 5:
		return {"success": false, "error_code": "G6_4_HEADLESS_QUERY_PROBES_MISSING"}
	if seam_transition_count < 1:
		return {"success": false, "error_code": "G6_4_HEADLESS_SEAM_MISSING"}
	if not face_sequence.has("PX") or not face_sequence.has("PZ"):
		return {"success": false, "error_code": "G6_4_HEADLESS_FACE_COVERAGE_MISSING"}
	if ribbon_node == null or ribbon_node.mesh == null:
		return {"success": false, "error_code": "G6_4_HEADLESS_RIBBON_MISSING"}
	if centerline_node == null or bank_node == null or probe_node == null or seam_node == null or lod_grid_node == null:
		return {"success": false, "error_code": "G6_4_HEADLESS_DEBUG_PRESENTATION_MISSING"}

	var far_profile: Dictionary = _lod_profile_for_distance(28.0)
	if not bool(far_profile.get("success", false)):
		return far_profile
	var near_profile: Dictionary = _lod_profile_for_distance(DISPLAY_RADIUS + 0.008)
	if not bool(near_profile.get("success", false)):
		return near_profile
	var far: Dictionary = far_profile["details"]
	var near: Dictionary = near_profile["details"]
	if int(near["max_lod"]) <= int(far["max_lod"]):
		return {"success": false, "error_code": "G6_4_HEADLESS_LOD_DID_NOT_REFINE", "details": {"far": far, "near": near}}
	if int(near["planned_river_samples"]) <= int(far["planned_river_samples"]):
		return {"success": false, "error_code": "G6_4_HEADLESS_RIVER_REPRESENTATION_DID_NOT_REFINE", "details": {"far": far, "near": near}}
	if String(near["selection_hash"]) == String(far["selection_hash"]):
		return {"success": false, "error_code": "G6_4_HEADLESS_LOD_SELECTION_HASH_STATIC"}
	return {"success": true}


func _lod_profile_for_distance(display_distance: float) -> Dictionary:
	var direction: Vector3 = _direction_from_lat_lon(5.0, 46.0)
	var altitude_m: float = _virtual_altitude_for_distance(display_distance)
	var observer_position: Vector3 = direction * (Fixture.RADIUS_M + altitude_m)
	var observer: Dictionary = BodyFixedPosition.create(Fixture.BODY_ID, _array3(observer_position))
	var selected: Dictionary = selector.select_cells(observer, [])
	if not bool(selected.get("success", false)):
		return selected
	var details: Dictionary = selected["details"]
	var leaves: Array = details["leaves"]
	var max_lod: int = int(details["max_selected_lod"])
	var leaf_tokens: Dictionary = _build_leaf_token_index(leaves)
	var planned_samples: int = _planned_river_sample_count(leaf_tokens, max_lod)
	return {
		"success": true,
		"details": {
			"altitude_m": altitude_m,
			"leaf_count": leaves.size(),
			"max_lod": max_lod,
			"selection_hash": String(details["selection_hash"]),
			"planned_river_samples": planned_samples,
		},
	}


func _planned_river_sample_count(leaf_tokens: Dictionary, max_lod: int) -> int:
	var details: Dictionary = compiled["details"]
	var spline: Dictionary = details["river_spline"]
	var points: Array = spline["points_m"]
	var count: int = 1
	for segment_index in range(points.size() - 1):
		var p0: Vector3 = _vector3(points[segment_index])
		var p1: Vector3 = _vector3(points[segment_index + 1])
		var midpoint: Vector3 = _sample_radial_segment(p0, p1, 0.5)
		var lod0: int = _selected_lod_for_direction(p0.normalized(), leaf_tokens, max_lod)
		var lodm: int = _selected_lod_for_direction(midpoint.normalized(), leaf_tokens, max_lod)
		var lod1: int = _selected_lod_for_direction(p1.normalized(), leaf_tokens, max_lod)
		var representation_lod: int = maxi(lod0, maxi(lodm, lod1))
		count += _subdivisions_for_lod(representation_lod)
	return count


func _sample_radial_segment(a: Vector3, b: Vector3, t: float) -> Vector3:
	if a.length_squared() <= EPSILON_SQ or b.length_squared() <= EPSILON_SQ:
		return a.lerp(b, t)
	var a_dir: Vector3 = a.normalized()
	var b_dir: Vector3 = b.normalized()
	if a_dir.dot(b_dir) < -0.999:
		return a.lerp(b, t)
	var direction: Vector3 = a_dir.slerp(b_dir, t)
	if direction.length_squared() <= EPSILON_SQ:
		return a.lerp(b, t)
	return direction.normalized() * lerpf(a.length(), b.length(), t)


func _direction_from_lat_lon(latitude_deg: float, longitude_deg: float) -> Vector3:
	var lat: float = deg_to_rad(latitude_deg)
	var lon: float = deg_to_rad(longitude_deg)
	var cos_lat: float = cos(lat)
	return Vector3(cos_lat * cos(lon), sin(lat), cos_lat * sin(lon)).normalized()


func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _fail(stage: String, result: Dictionary) -> void:
	push_error("G6.4 lab %s failed: %s %s" % [stage, result.get("error_code", ""), result.get("details", {})])
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
