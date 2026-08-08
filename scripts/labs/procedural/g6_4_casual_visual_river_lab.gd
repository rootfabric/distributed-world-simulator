extends Node3D

const CasualRiverProvider = preload("res://scripts/simulation/procedural/hydrology/casual_river_provider_v1.gd")
const WaterSurfaceQuery = preload("res://scripts/simulation/procedural/contracts/water_surface_query.gd")
const WaterSurfaceResolver = preload("res://scripts/simulation/procedural/hydrology/water_surface_resolver_v1.gd")
const FluidType = preload("res://scripts/simulation/procedural/contracts/fluid_type.gd")
const CubeSphereAddressing = preload("res://scripts/simulation/procedural/surface/cube_sphere_addressing.gd")
const Fixture = preload("res://tests/procedural/fixtures/g6_2_cross_cell_river_fixture.gd")

const DISPLAY_RADIUS: float = 8.0
const WATER_OFFSET: float = 0.035
const WIDTH_EXAGGERATION: float = 5200.0
const BANK_EXAGGERATION: float = 3600.0
const SAMPLES_PER_SEGMENT: int = 16
const QUERY_DISTANCE_M: float = 5.0
const EPSILON_SQ: float = 0.000000000001

@onready var camera: Camera3D = $Camera3D
@onready var planet: MeshInstance3D = $Planet
@onready var hud: Label = $HUD/Panel/Margin/VBox/Status

var addressing = CubeSphereAddressing.new()
var compiled: Dictionary = {}
var visual_samples: Array = []
var face_sequence: Array[String] = []
var seam_transition_count: int = 0
var query_probe_count: int = 0

var ribbon_node: MeshInstance3D
var centerline_node: MeshInstance3D
var bank_node: MeshInstance3D
var probe_node: MeshInstance3D
var seam_node: MeshInstance3D

var yaw_deg: float = 46.0
var pitch_deg: float = 18.0
var camera_distance: float = 19.5
var auto_orbit: bool = false


func _ready() -> void:
	compiled = CasualRiverProvider.compile(Fixture.river())
	if not bool(compiled.get("success", false)):
		_fail("provider compile", compiled)
		return
	var built: Dictionary = _build_visual_samples()
	if not bool(built.get("success", false)):
		_fail("visual samples", built)
		return
	_build_visual_nodes()
	_update_camera()
	_update_hud()

	if DisplayServer.get_name() == "headless":
		var smoke := _headless_smoke()
		if not bool(smoke.get("success", false)):
			_fail("headless smoke", smoke)
			return
		print("G6.4 Casual Visual River Lab: PASS (samples=%d probes=%d seams=%d faces=%s)" % [
			visual_samples.size(), query_probe_count, seam_transition_count, ",".join(face_sequence)
		])
		get_tree().quit(0)


func _process(delta: float) -> void:
	if auto_orbit:
		yaw_deg = fposmod(yaw_deg + 8.0 * delta, 360.0)
	_update_camera_from_input(delta)
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				ribbon_node.visible = not ribbon_node.visible
			KEY_2:
				centerline_node.visible = not centerline_node.visible
			KEY_3:
				bank_node.visible = not bank_node.visible
			KEY_4:
				probe_node.visible = not probe_node.visible
			KEY_5:
				seam_node.visible = not seam_node.visible
			KEY_SPACE:
				auto_orbit = not auto_orbit
			KEY_R:
				yaw_deg = 46.0
				pitch_deg = 18.0
				camera_distance = 19.5
		_update_hud()


func _update_camera_from_input(delta: float) -> void:
	var orbit_speed := 32.0 * delta
	if Input.is_key_pressed(KEY_A):
		yaw_deg += orbit_speed
	if Input.is_key_pressed(KEY_D):
		yaw_deg -= orbit_speed
	if Input.is_key_pressed(KEY_Q):
		pitch_deg = clampf(pitch_deg + orbit_speed, -75.0, 75.0)
	if Input.is_key_pressed(KEY_E):
		pitch_deg = clampf(pitch_deg - orbit_speed, -75.0, 75.0)
	var zoom_speed := 8.0 * delta
	if Input.is_key_pressed(KEY_W):
		camera_distance = maxf(10.0, camera_distance - zoom_speed)
	if Input.is_key_pressed(KEY_S):
		camera_distance = minf(34.0, camera_distance + zoom_speed)


func _update_camera() -> void:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	var cos_pitch := cos(pitch)
	camera.position = Vector3(
		cos_pitch * cos(yaw),
		sin(pitch),
		cos_pitch * sin(yaw)
	) * camera_distance
	camera.look_at(Vector3.ZERO, Vector3.UP)


func _build_visual_samples() -> Dictionary:
	var details: Dictionary = compiled["details"]
	var spline: Dictionary = details["river_spline"]
	var points: Array = spline["points_m"]
	var last_face := ""
	var seen_faces: Dictionary = {}

	for segment_index in range(points.size() - 1):
		var p0 := _vector3(points[segment_index])
		var p1 := _vector3(points[segment_index + 1])
		for subdivision in range(SAMPLES_PER_SEGMENT):
			var local_t := float(subdivision) / float(SAMPLES_PER_SEGMENT)
			var point := _sample_radial_segment(p0, p1, local_t)
			var global_t := (float(segment_index) + local_t) / float(points.size() - 1)
			var appended := _append_visual_sample(point, global_t, last_face, seen_faces)
			if not bool(appended.get("success", false)):
				return appended
			last_face = String(appended["details"]["face"])

	var final_point := _vector3(points[points.size() - 1])
	var final_append := _append_visual_sample(final_point, 1.0, last_face, seen_faces)
	if not bool(final_append.get("success", false)):
		return final_append

	face_sequence.clear()
	for sample in visual_samples:
		var face := String(sample["face"])
		if not face_sequence.has(face):
			face_sequence.append(face)

	if visual_samples.size() < 16:
		return {"success": false, "error_code": "G6_4_TOO_FEW_VISUAL_SAMPLES"}
	if not seen_faces.has("PX") or not seen_faces.has("PZ"):
		return {"success": false, "error_code": "G6_4_EXPECTED_PX_PZ_SEAM_NOT_OBSERVED", "details": {"faces": seen_faces.keys()}}
	if seam_transition_count < 1:
		return {"success": false, "error_code": "G6_4_SEAM_TRANSITION_NOT_OBSERVED"}
	return {"success": true}


func _append_visual_sample(point: Vector3, global_t: float, previous_face: String, seen_faces: Dictionary) -> Dictionary:
	var query := WaterSurfaceQuery.create(
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
	var face := String(face_uv["details"]["face"])
	seen_faces[face] = true
	if not previous_face.is_empty() and previous_face != face:
		seam_transition_count += 1
	sample["face"] = face
	sample["visual_t"] = global_t
	visual_samples.append(sample)
	return {"success": true, "details": {"face": face}}


func _build_visual_nodes() -> void:
	ribbon_node = _new_mesh_node("RiverRibbon", _build_ribbon_mesh())
	centerline_node = _new_mesh_node("CanonicalCenterline", _build_centerline_mesh())
	bank_node = _new_mesh_node("BankGuides", _build_bank_mesh())
	probe_node = _new_mesh_node("QueryProbes", _build_probe_mesh())
	seam_node = _new_mesh_node("CubeFaceSeamMarkers", _build_seam_mesh())


func _new_mesh_node(node_name: String, mesh: ImmediateMesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	add_child(node)
	return node


func _build_ribbon_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, material)
	for sample in visual_samples:
		var frame := _display_frame(sample)
		var center: Vector3 = frame["center"]
		var lateral: Vector3 = frame["lateral"]
		var half_width := _display_distance(float(sample["channel_width_m"]) * 0.5, WIDTH_EXAGGERATION)
		var color := Color(0.03, 0.34, 0.88, 0.82) if String(sample["face"]) == "PX" else Color(0.05, 0.62, 0.95, 0.82)
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
		mesh.surface_set_color(Color(1.0, 0.92, 0.18, 1.0))
		mesh.surface_add_vertex(_display_frame(visual_samples[index])["center"] + _normal_display(visual_samples[index]) * 0.018)
		mesh.surface_set_color(Color(1.0, 0.92, 0.18, 1.0))
		mesh.surface_add_vertex(_display_frame(visual_samples[index + 1])["center"] + _normal_display(visual_samples[index + 1]) * 0.018)
	mesh.surface_end()
	return mesh


func _build_bank_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var material := _line_material()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for index in range(visual_samples.size() - 1):
		for side in [-1.0, 1.0]:
			var a: Dictionary = visual_samples[index]
			var b: Dictionary = visual_samples[index + 1]
			var fa := _display_frame(a)
			var fb := _display_frame(b)
			var da := _display_distance(float(a["channel_width_m"]) * 0.5 + float(a["bank_width_m"]), BANK_EXAGGERATION)
			var db := _display_distance(float(b["channel_width_m"]) * 0.5 + float(b["bank_width_m"]), BANK_EXAGGERATION)
			mesh.surface_set_color(Color(0.72, 0.48, 0.18, 0.9))
			mesh.surface_add_vertex(fa["center"] + fa["lateral"] * da * side + _normal_display(a) * 0.012)
			mesh.surface_set_color(Color(0.72, 0.48, 0.18, 0.9))
			mesh.surface_add_vertex(fb["center"] + fb["lateral"] * db * side + _normal_display(b) * 0.012)
	mesh.surface_end()
	return mesh


func _build_probe_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var material := _line_material()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	query_probe_count = 0
	var stride: int = maxi(1, int(floor(float(visual_samples.size() - 1) / 6.0)))
	for index in range(0, visual_samples.size(), stride):
		var sample: Dictionary = visual_samples[index]
		var frame := _display_frame(sample)
		var center: Vector3 = frame["center"]
		var normal := _normal_display(sample)
		var flow := _vector3(sample["flow_direction"]).normalized()
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
	var previous_face := String(visual_samples[0]["face"])
	for index in range(1, visual_samples.size()):
		var sample: Dictionary = visual_samples[index]
		var face := String(sample["face"])
		if face != previous_face:
			var frame: Dictionary = _display_frame(sample)
			var center: Vector3 = frame["center"]
			var normal := _normal_display(sample)
			mesh.surface_set_color(Color(1.0, 0.1, 0.85, 1.0))
			mesh.surface_add_vertex(center - normal * 0.25)
			mesh.surface_set_color(Color(1.0, 0.1, 0.85, 1.0))
			mesh.surface_add_vertex(center + normal * 1.2)
		previous_face = face
	mesh.surface_end()
	return mesh


func _display_frame(sample: Dictionary) -> Dictionary:
	var surface := _vector3(sample["surface_position_m"])
	var normal := surface.normalized()
	var flow := _vector3(sample["flow_direction"])
	flow = (flow - normal * flow.dot(normal)).normalized()
	var lateral := normal.cross(flow)
	if lateral.length_squared() <= EPSILON_SQ:
		lateral = normal.cross(Vector3.UP)
	if lateral.length_squared() <= EPSILON_SQ:
		lateral = normal.cross(Vector3.RIGHT)
	lateral = lateral.normalized()
	var altitude_display := (surface.length() - Fixture.RADIUS_M) / Fixture.RADIUS_M * DISPLAY_RADIUS
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
	return material


func _update_hud() -> void:
	if hud == null or compiled.is_empty():
		return
	var details: Dictionary = compiled["details"]
	var midpoint: Dictionary = visual_samples[int(visual_samples.size() / 2)]
	hud.text = "G6.4 — Casual Visual River Lab\n\nFeature: %s\nFluidRegion: %s\nFaces: %s   seam transitions: %d\nSamples: %d   query probes: %d\nMid width/depth/bank: %.1f / %.1f / %.1f m\n\nBlue: derived water ribbon (width x%.0f)\nYellow: canonical centerline\nBrown: bank guides   Magenta: cube-face seam\nRed/green: query normal / flow\n\nA/D orbit   Q/E pitch   W/S zoom   Space auto-orbit   R reset\n1 water   2 centerline   3 banks   4 probes   5 seam" % [
		String(details["source_feature_id"]).substr(0, 30),
		String(details["fluid_region_id"]).substr(0, 30),
		" / ".join(face_sequence),
		seam_transition_count,
		visual_samples.size(),
		query_probe_count,
		float(midpoint["channel_width_m"]),
		float(midpoint["channel_depth_m"]),
		float(midpoint["bank_width_m"]),
		WIDTH_EXAGGERATION,
	]


func _headless_smoke() -> Dictionary:
	if visual_samples.size() < 80:
		return {"success": false, "error_code": "G6_4_HEADLESS_SAMPLE_COUNT_TOO_SMALL"}
	if query_probe_count < 5:
		return {"success": false, "error_code": "G6_4_HEADLESS_QUERY_PROBES_MISSING"}
	if seam_transition_count < 1:
		return {"success": false, "error_code": "G6_4_HEADLESS_SEAM_MISSING"}
	if not face_sequence.has("PX") or not face_sequence.has("PZ"):
		return {"success": false, "error_code": "G6_4_HEADLESS_FACE_COVERAGE_MISSING"}
	if ribbon_node == null or ribbon_node.mesh == null:
		return {"success": false, "error_code": "G6_4_HEADLESS_RIBBON_MISSING"}
	if centerline_node == null or bank_node == null or probe_node == null or seam_node == null:
		return {"success": false, "error_code": "G6_4_HEADLESS_DEBUG_PRESENTATION_MISSING"}
	return {"success": true}


func _sample_radial_segment(a: Vector3, b: Vector3, t: float) -> Vector3:
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


func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _fail(stage: String, result: Dictionary) -> void:
	push_error("G6.4 lab %s failed: %s %s" % [stage, result.get("error_code", ""), result.get("details", {})])
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)