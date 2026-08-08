extends MeshInstance3D

const PlanetDefinition = preload("res://scripts/simulation/procedural/contracts/planet_definition.gd")
const BodyFixedPosition = preload("res://scripts/simulation/procedural/contracts/body_fixed_position.gd")
const SurfaceLodPolicy = preload("res://scripts/simulation/procedural/contracts/surface_lod_policy.gd")
const CubeSphereAddressing = preload("res://scripts/simulation/procedural/surface/cube_sphere_addressing.gd")
const SurfaceLodSelector = preload("res://scripts/simulation/procedural/surface/surface_lod_selector.gd")
const MacroProvider = preload("res://scripts/simulation/procedural/providers/casual_macro_terrain_provider_v1.gd")
const Fixture = preload("res://tests/procedural/fixtures/g6_2_cross_cell_river_fixture.gd")

const DISPLAY_RADIUS: float = 8.0
const TERRAIN_BASE_RADIUS: float = 7.985
const HEIGHT_DISPLAY_EXAGGERATION: float = 40.0
const MACRO_AMPLITUDE_M: float = 900.0
const MACRO_WAVELENGTH_M: float = 600000.0
# Fix4 visual recipe: use the accepted G3 provider's full configurable octave
# range so observer-driven LOD reveals new height-field frequencies instead of
# merely adding triangles over a four-octave (~75 km minimum wavelength) field.
# This changes only the lab recipe; the accepted G3 provider is untouched.
const MACRO_OCTAVES: int = 8
const MACRO_PERSISTENCE: float = 0.58
const MIN_SIGNAL_WAVELENGTH_M: float = 4687.5
const CELL_SEGMENTS: int = 2
const UPDATE_INTERVAL_S: float = 0.18

const LOD_MIN: int = 0
const LOD_MAX: int = 12
const LOD_REFINE_RATIO: float = 0.45
const LOD_COARSEN_RATIO: float = 0.30
const LOD_MIN_DISTANCE_M: float = 50.0
const LOD_LEAF_BUDGET: int = 1536

const RECIPE_ID: String = "planet-recipe/g6-4-adaptive-macro-surface"
const SHAPE_ID: String = "body-shape/sphere-v1"
const MANIFEST_VERSION: String = "1.0.0"

@onready var camera: Camera3D = get_node("../Camera3D") as Camera3D

var addressing = CubeSphereAddressing.new()
var selector = SurfaceLodSelector.new()
var provider = MacroProvider.new(
	Fixture.SEED,
	Fixture.RADIUS_M,
	MACRO_AMPLITUDE_M,
	MACRO_WAVELENGTH_M,
	MACRO_OCTAVES,
	MACRO_PERSISTENCE,
	0.0
)

var current_leaves: Array = []
var current_selection_hash: String = ""
var update_accumulator: float = UPDATE_INTERVAL_S

var last_leaf_count: int = 0
var last_max_lod: int = 0
var last_triangle_count: int = 0
var last_vertex_count: int = 0
var last_height_min_m: float = 0.0
var last_height_max_m: float = 0.0

var terrain_material: StandardMaterial3D


func _ready() -> void:
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
		push_error("G6.4 adaptive macro surface selector configure failed: %s" % String(configured.get("error_code", "")))
		set_process(false)
		return

	terrain_material = StandardMaterial3D.new()
	terrain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.cull_mode = BaseMaterial3D.CULL_BACK

	var refreshed: Dictionary = _refresh_surface(true)
	if not bool(refreshed.get("success", false)):
		push_error("G6.4 adaptive macro surface initial rebuild failed: %s" % String(refreshed.get("error_code", "")))
		set_process(false)
		return

	if DisplayServer.get_name() == "headless":
		var smoke: Dictionary = _headless_detail_smoke()
		if not bool(smoke.get("success", false)):
			push_error("G6.4 adaptive macro surface headless proof failed: %s" % String(smoke.get("error_code", "")))
			return
		var details: Dictionary = smoke["details"]
		print("G6.4 Adaptive Macro Surface: PASS (far_lod=%d near_lod=%d far_triangles=%d near_triangles=%d current_triangles=%d octaves=%d min_signal_km=%.3f)" % [
			int(details["far_max_lod"]),
			int(details["near_max_lod"]),
			int(details["far_triangles"]),
			int(details["near_triangles"]),
			last_triangle_count,
			MACRO_OCTAVES,
			MIN_SIGNAL_WAVELENGTH_M / 1000.0,
		])


func _process(delta: float) -> void:
	update_accumulator += delta
	if update_accumulator < UPDATE_INTERVAL_S:
		return
	update_accumulator = 0.0
	var refreshed: Dictionary = _refresh_surface(false)
	if not bool(refreshed.get("success", false)):
		push_error("G6.4 adaptive macro surface refresh failed: %s" % String(refreshed.get("error_code", "")))


func _refresh_surface(force_rebuild: bool) -> Dictionary:
	if camera == null:
		return {"success": false, "error_code": "G6_4_ADAPTIVE_SURFACE_CAMERA_MISSING"}
	var observer: Dictionary = _virtual_observer(camera.position)
	var selected: Dictionary = selector.select_cells(observer, current_leaves)
	if not bool(selected.get("success", false)):
		return selected
	var details: Dictionary = selected["details"]
	var selection_hash: String = String(details["selection_hash"])
	if not force_rebuild and selection_hash == current_selection_hash:
		return {"success": true, "details": {"changed": false}}

	current_leaves = Array(details["leaves"]).duplicate(true)
	current_selection_hash = selection_hash
	last_leaf_count = current_leaves.size()
	last_max_lod = int(details["max_selected_lod"])
	_rebuild_mesh(current_leaves)
	return {
		"success": true,
		"details": {
			"changed": true,
			"leaf_count": last_leaf_count,
			"max_lod": last_max_lod,
			"triangles": last_triangle_count,
			"vertices": last_vertex_count,
		},
	}


func _rebuild_mesh(leaves: Array) -> void:
	var terrain := ImmediateMesh.new()
	terrain.surface_begin(Mesh.PRIMITIVE_TRIANGLES, terrain_material)
	last_triangle_count = 0
	last_vertex_count = 0
	last_height_min_m = INF
	last_height_max_m = -INF

	for raw_cell in leaves:
		var cell: Dictionary = Dictionary(raw_cell)
		var bounds_result: Dictionary = addressing.cell_uv_bounds(cell)
		if not bool(bounds_result.get("success", false)):
			continue
		var bounds: Dictionary = bounds_result["details"]
		var face: String = String(cell["face"])
		for iy in range(CELL_SEGMENTS):
			var v0: float = lerpf(float(bounds["v_min"]), float(bounds["v_max"]), float(iy) / float(CELL_SEGMENTS))
			var v1: float = lerpf(float(bounds["v_min"]), float(bounds["v_max"]), float(iy + 1) / float(CELL_SEGMENTS))
			for ix in range(CELL_SEGMENTS):
				var u0: float = lerpf(float(bounds["u_min"]), float(bounds["u_max"]), float(ix) / float(CELL_SEGMENTS))
				var u1: float = lerpf(float(bounds["u_min"]), float(bounds["u_max"]), float(ix + 1) / float(CELL_SEGMENTS))
				var p00: Dictionary = _surface_point(face, u0, v0)
				var p10: Dictionary = _surface_point(face, u1, v0)
				var p11: Dictionary = _surface_point(face, u1, v1)
				var p01: Dictionary = _surface_point(face, u0, v1)
				_add_triangle(terrain, p00, p10, p11)
				_add_triangle(terrain, p00, p11, p01)

	terrain.surface_end()
	mesh = terrain
	if last_height_min_m == INF:
		last_height_min_m = 0.0
		last_height_max_m = 0.0


func _add_triangle(target: ImmediateMesh, a: Dictionary, b: Dictionary, c: Dictionary) -> void:
	for vertex_data in [a, b, c]:
		target.surface_set_color(vertex_data["color"])
		target.surface_add_vertex(vertex_data["point"])
		last_vertex_count += 1
	last_triangle_count += 1


func _surface_point(face: String, u: float, v: float) -> Dictionary:
	var direction_result: Dictionary = addressing.face_uv_to_direction(face, u, v)
	if not bool(direction_result.get("success", false)):
		return {
			"point": Vector3.ZERO,
			"color": Color.MAGENTA,
		}
	var raw_direction: Array = direction_result["details"]["direction"]
	var direction := Vector3(
		float(raw_direction[0]),
		float(raw_direction[1]),
		float(raw_direction[2])
	).normalized()
	var height_m: float = _height_for_direction(direction)
	last_height_min_m = minf(last_height_min_m, height_m)
	last_height_max_m = maxf(last_height_max_m, height_m)
	var display_height: float = height_m / Fixture.RADIUS_M * DISPLAY_RADIUS * HEIGHT_DISPLAY_EXAGGERATION
	return {
		"point": direction * (TERRAIN_BASE_RADIUS + display_height),
		"color": _height_color(height_m),
	}


func _height_for_direction(direction: Vector3) -> float:
	var body_position: Vector3 = direction * Fixture.RADIUS_M
	var sampled: Dictionary = provider.sample_surface(
		{},
		{"body_fixed_position_m": [body_position.x, body_position.y, body_position.z]},
		{}
	)
	if not bool(sampled.get("success", false)):
		return 0.0
	return float(sampled["details"]["values"][MacroProvider.FIELD_SURFACE_HEIGHT_M])


func _height_color(height_m: float) -> Color:
	var normalized: float = clampf((height_m + MACRO_AMPLITUDE_M) / (MACRO_AMPLITUDE_M * 2.0), 0.0, 1.0)
	if normalized < 0.35:
		return Color(0.16, 0.17, 0.19).lerp(Color(0.27, 0.29, 0.30), normalized / 0.35)
	if normalized < 0.70:
		return Color(0.27, 0.29, 0.30).lerp(Color(0.43, 0.40, 0.35), (normalized - 0.35) / 0.35)
	return Color(0.43, 0.40, 0.35).lerp(Color(0.72, 0.70, 0.65), (normalized - 0.70) / 0.30)


func _virtual_observer(display_position: Vector3) -> Dictionary:
	var direction: Vector3 = display_position.normalized()
	var altitude_m: float = _virtual_altitude(display_position.length())
	var body_position: Vector3 = direction * (Fixture.RADIUS_M + altitude_m)
	return BodyFixedPosition.create(Fixture.BODY_ID, [body_position.x, body_position.y, body_position.z])


func _virtual_altitude(display_distance: float) -> float:
	var radial_scale: float = maxf(display_distance / DISPLAY_RADIUS, 1.0)
	return (radial_scale - 1.0) * Fixture.RADIUS_M


func _profile_for_distance(display_distance: float) -> Dictionary:
	var local_selector = SurfaceLodSelector.new()
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
	var configured: Dictionary = local_selector.configure(definition, policy)
	if not bool(configured.get("success", false)):
		return configured
	var direction: Vector3 = camera.position.normalized() if camera != null else Vector3(1.0, 0.0, 0.0)
	var altitude_m: float = _virtual_altitude(display_distance)
	var observer_position: Vector3 = direction * (Fixture.RADIUS_M + altitude_m)
	var observer: Dictionary = BodyFixedPosition.create(Fixture.BODY_ID, [observer_position.x, observer_position.y, observer_position.z])
	var selected: Dictionary = local_selector.select_cells(observer, [])
	if not bool(selected.get("success", false)):
		return selected
	var details: Dictionary = selected["details"]
	var leaf_count: int = int(details["leaf_count"])
	var triangles: int = leaf_count * CELL_SEGMENTS * CELL_SEGMENTS * 2
	return {
		"success": true,
		"details": {
			"leaf_count": leaf_count,
			"max_lod": int(details["max_selected_lod"]),
			"selection_hash": String(details["selection_hash"]),
			"planned_triangles": triangles,
			"planned_vertices": triangles * 3,
		},
	}


func _headless_detail_smoke() -> Dictionary:
	var far_profile: Dictionary = _profile_for_distance(28.0)
	if not bool(far_profile.get("success", false)):
		return far_profile
	var near_profile: Dictionary = _profile_for_distance(DISPLAY_RADIUS + 0.08)
	if not bool(near_profile.get("success", false)):
		return near_profile
	var far: Dictionary = far_profile["details"]
	var near: Dictionary = near_profile["details"]
	if int(near["max_lod"]) <= int(far["max_lod"]):
		return {"success": false, "error_code": "G6_4_MACRO_SURFACE_LOD_DID_NOT_REFINE"}
	if int(near["planned_triangles"]) <= int(far["planned_triangles"]):
		return {"success": false, "error_code": "G6_4_MACRO_SURFACE_GEOMETRY_DID_NOT_REFINE"}
	if String(near["selection_hash"]) == String(far["selection_hash"]):
		return {"success": false, "error_code": "G6_4_MACRO_SURFACE_SELECTION_DID_NOT_CHANGE"}
	return {
		"success": true,
		"details": {
			"far_max_lod": int(far["max_lod"]),
			"near_max_lod": int(near["max_lod"]),
			"far_triangles": int(far["planned_triangles"]),
			"near_triangles": int(near["planned_triangles"]),
		},
	}