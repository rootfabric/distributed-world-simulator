extends Node3D

const PlanetDefinition = preload("res://scripts/simulation/procedural/contracts/planet_definition.gd")
const PlanetEnvironment = preload("res://scripts/simulation/procedural/contracts/planet_environment.gd")
const PlanetRecipe = preload("res://scripts/simulation/procedural/contracts/planet_recipe.gd")
const BodyFixedPosition = preload("res://scripts/simulation/procedural/contracts/body_fixed_position.gd")
const SurfaceLodPolicy = preload("res://scripts/simulation/procedural/contracts/surface_lod_policy.gd")
const Context = preload("res://scripts/simulation/procedural/contracts/geo_generation_context.gd")
const SurfaceQuery = preload("res://scripts/simulation/procedural/contracts/geo_surface_query.gd")
const GeoSample = preload("res://scripts/simulation/procedural/contracts/geo_sample.gd")
const CubeSphereAddressing = preload("res://scripts/simulation/procedural/surface/cube_sphere_addressing.gd")
const SurfaceLodSelector = preload("res://scripts/simulation/procedural/surface/surface_lod_selector.gd")
const GeoKernel = preload("res://scripts/simulation/procedural/geo_kernel.gd")
const Composer = preload("res://scripts/simulation/procedural/composition/geo_recipe_composer.gd")
const Catalog = preload("res://scripts/simulation/procedural/composition/g4_surface_provider_catalog.gd")

const BODY_ID := "body/procedural-g4-lab"
const RECIPE_ID := "world-recipe/g4-lab"
const SHAPE_ID := "body-shape/sphere-v1"
const MANIFEST_VERSION := "1.0.0"
const RADIUS_M := 6000000.0
const SEED := 2026080801
const AMPLITUDE_M := 900.0
const FINAL_FIELD := "geo/surface-height-m"
const CELL_SEGMENTS := 2
const UPDATE_INTERVAL_S := 0.18
const SURFACE_OFFSET_M := 4.0

@onready var camera: Camera3D = $Camera3D
@onready var terrain_mesh_instance: MeshInstance3D = $Terrain
@onready var grid_mesh_instance: MeshInstance3D = $Grid
@onready var hud: Label = $HUD/Panel/Margin/VBox/Status

var addressing = CubeSphereAddressing.new()
var selector = SurfaceLodSelector.new()
var composer = Composer.new()
var registry
var kernel
var definition: Dictionary
var environment: Dictionary
var recipe_mode: String = "CASUAL"
var manifest_hash: String = ""
var previous_leaves: Array = []
var update_accumulator: float = UPDATE_INTERVAL_S
var terrain_material: StandardMaterial3D
var line_material: StandardMaterial3D


func _ready() -> void:
	definition = PlanetDefinition.create(BODY_ID, SEED, RECIPE_ID, SHAPE_ID, RADIUS_M, MANIFEST_VERSION)
	environment = PlanetEnvironment.create("planet-environment/g4-lab", "gravity-model/unspecified", "atmosphere-model/unspecified", "temperature-model/unspecified", "fluid-catalog/none", "weathering-model/none", "material-catalog/unspecified", {})
	var catalog_result: Dictionary = Catalog.create_registry()
	if not bool(catalog_result.get("success", false)):
		push_error("G4 lab registry failed: %s" % catalog_result.get("error_code", ""))
		set_process(false)
		return
	registry = catalog_result["details"]["registry"]
	var policy := SurfaceLodPolicy.create(0, 8, 0.45, 0.30, 10.0, 1024)
	var selected_config: Dictionary = selector.configure(definition, policy)
	if not bool(selected_config.get("success", false)):
		push_error("G4 lab selector configure failed: %s" % selected_config.get("error_code", ""))
		set_process(false)
		return
	if not _apply_recipe("CASUAL"):
		set_process(false)
		return

	camera.position = _direction_from_lat_lon(24.0, -35.0) * (RADIUS_M + 3500000.0)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.near = 1.0
	camera.far = 50000000.0

	terrain_material = StandardMaterial3D.new()
	terrain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.cull_mode = BaseMaterial3D.CULL_BACK
	line_material = StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	_refresh_surface()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		var next_mode: String = "ALTERNATIVE" if recipe_mode == "CASUAL" else "CASUAL"
		if _apply_recipe(next_mode):
			_refresh_surface()


func _apply_recipe(mode: String) -> bool:
	var descriptors: Array
	var version: String
	if mode == "ALTERNATIVE":
		descriptors = Catalog.alternative_descriptors(SEED, RADIUS_M)
		version = "2.0.0"
	else:
		descriptors = Catalog.casual_descriptors(SEED, RADIUS_M)
		version = "1.0.0"
	var recipe := PlanetRecipe.create(RECIPE_ID, version, environment, descriptors)
	var next_kernel = GeoKernel.new()
	var configured: Dictionary = composer.configure_kernel(next_kernel, definition, recipe, registry)
	if not bool(configured.get("success", false)):
		push_error("G4 recipe composition failed: %s %s" % [configured.get("error_code", ""), configured.get("details", {})])
		return false
	kernel = next_kernel
	recipe_mode = mode
	manifest_hash = String(configured["details"]["provider_manifest_hash"])
	return true


func _process(delta: float) -> void:
	_update_camera(delta)
	update_accumulator += delta
	if update_accumulator >= UPDATE_INTERVAL_S:
		update_accumulator = 0.0
		_refresh_surface()


func _update_camera(delta: float) -> void:
	var position: Vector3 = camera.position
	var radial: Vector3 = position.normalized()
	var ground_height: float = _height_for_direction(radial)
	var altitude_m: float = maxf(position.length() - (RADIUS_M + ground_height), 0.0)
	var radial_speed: float = clampf(maxf(100.0, altitude_m * 0.7), 100.0, 5000000.0)
	if Input.is_key_pressed(KEY_W): position -= radial * radial_speed * delta
	if Input.is_key_pressed(KEY_S): position += radial * radial_speed * delta
	var orbit_speed: float = deg_to_rad(18.0) * delta
	if Input.is_key_pressed(KEY_A): position = Basis(Vector3.UP, orbit_speed) * position
	if Input.is_key_pressed(KEY_D): position = Basis(Vector3.UP, -orbit_speed) * position
	var east: Vector3 = Vector3.UP.cross(radial)
	if east.length_squared() > 0.000000001:
		east = east.normalized()
		if Input.is_key_pressed(KEY_Q): position = Basis(east, -orbit_speed) * position
		if Input.is_key_pressed(KEY_E): position = Basis(east, orbit_speed) * position
	var final_radial: Vector3 = position.normalized()
	var minimum_radius: float = RADIUS_M + _height_for_direction(final_radial) + 5.0
	if position.length() < minimum_radius: position = final_radial * minimum_radius
	camera.position = position
	camera.look_at(Vector3.ZERO, Vector3.UP)


func _refresh_surface() -> void:
	var observer := BodyFixedPosition.create(BODY_ID, [camera.position.x, camera.position.y, camera.position.z])
	var selected: Dictionary = selector.select_cells(observer, previous_leaves)
	if not bool(selected.get("success", false)):
		push_error("G4 lab selection failed: %s" % selected.get("error_code", ""))
		return
	var leaves: Array = selected["details"]["leaves"]
	previous_leaves = leaves
	_rebuild_terrain(leaves)
	var radial: Vector3 = camera.position.normalized()
	var ground_height: float = _height_for_direction(radial)
	var altitude_m: float = camera.position.length() - (RADIUS_M + ground_height)
	hud.text = "Recipe: %s  [M toggles]\nAltitude AGL: %.0f m\nSurface height: %.1f m\nLeaves: %d / 1024\nMax LOD: %d\nManifest: %s..." % [recipe_mode, altitude_m, ground_height, int(selected["details"]["leaf_count"]), int(selected["details"]["max_selected_lod"]), manifest_hash.left(12)]


func _rebuild_terrain(leaves: Array) -> void:
	var terrain := ImmediateMesh.new()
	terrain.surface_begin(Mesh.PRIMITIVE_TRIANGLES, terrain_material)
	var grid := ImmediateMesh.new()
	grid.surface_begin(Mesh.PRIMITIVE_LINES, line_material)
	for cell in leaves:
		var bounds_result: Dictionary = addressing.cell_uv_bounds(cell)
		if not bool(bounds_result.get("success", false)): continue
		var bounds: Dictionary = bounds_result["details"]
		var face: String = String(cell["face"])
		var lod: int = int(cell["lod"])
		for iy in range(CELL_SEGMENTS):
			var v0: float = lerpf(float(bounds["v_min"]), float(bounds["v_max"]), float(iy) / float(CELL_SEGMENTS))
			var v1: float = lerpf(float(bounds["v_min"]), float(bounds["v_max"]), float(iy + 1) / float(CELL_SEGMENTS))
			for ix in range(CELL_SEGMENTS):
				var u0: float = lerpf(float(bounds["u_min"]), float(bounds["u_max"]), float(ix) / float(CELL_SEGMENTS))
				var u1: float = lerpf(float(bounds["u_min"]), float(bounds["u_max"]), float(ix + 1) / float(CELL_SEGMENTS))
				var p00 := _surface_point(face, u0, v0); var p10 := _surface_point(face, u1, v0); var p11 := _surface_point(face, u1, v1); var p01 := _surface_point(face, u0, v1)
				_add_triangle(terrain, p00, p10, p11); _add_triangle(terrain, p00, p11, p01)
		var line_color := Color.from_hsv(fposmod(float(lod) * 0.115, 1.0), 0.55, 1.0, 1.0)
		_add_grid_edge(grid, face, float(bounds["u_min"]), float(bounds["v_min"]), float(bounds["u_max"]), float(bounds["v_min"]), line_color)
		_add_grid_edge(grid, face, float(bounds["u_max"]), float(bounds["v_min"]), float(bounds["u_max"]), float(bounds["v_max"]), line_color)
		_add_grid_edge(grid, face, float(bounds["u_max"]), float(bounds["v_max"]), float(bounds["u_min"]), float(bounds["v_max"]), line_color)
		_add_grid_edge(grid, face, float(bounds["u_min"]), float(bounds["v_max"]), float(bounds["u_min"]), float(bounds["v_min"]), line_color)
	terrain.surface_end(); grid.surface_end()
	terrain_mesh_instance.mesh = terrain; grid_mesh_instance.mesh = grid


func _add_triangle(mesh: ImmediateMesh, a: Dictionary, b: Dictionary, c: Dictionary) -> void:
	for vertex_data in [a, b, c]:
		mesh.surface_set_color(vertex_data["color"]); mesh.surface_add_vertex(vertex_data["point"])


func _add_grid_edge(mesh: ImmediateMesh, face: String, u0: float, v0: float, u1: float, v1: float, color: Color) -> void:
	var previous: Vector3
	for index in range(CELL_SEGMENTS + 1):
		var t: float = float(index) / float(CELL_SEGMENTS)
		var sample := _surface_point(face, lerpf(u0, u1, t), lerpf(v0, v1, t))
		var point: Vector3 = sample["point"] + sample["direction"] * SURFACE_OFFSET_M
		if index > 0:
			mesh.surface_set_color(color); mesh.surface_add_vertex(previous)
			mesh.surface_set_color(color); mesh.surface_add_vertex(point)
		previous = point


func _surface_point(face: String, u: float, v: float) -> Dictionary:
	var direction_result: Dictionary = addressing.face_uv_to_direction(face, u, v)
	if not bool(direction_result.get("success", false)):
		return {"point": Vector3.ZERO, "direction": Vector3.UP, "color": Color.MAGENTA}
	var raw: Array = direction_result["details"]["direction"]
	var direction := Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	var height_m: float = _height_for_direction(direction)
	return {"point": direction * (RADIUS_M + height_m), "direction": direction, "color": _height_color(height_m)}


func _height_for_direction(direction: Vector3) -> float:
	if kernel == null: return 0.0
	var position: Vector3 = direction.normalized() * RADIUS_M
	var context := Context.create(BODY_ID, "geo-scope/g4-lab", 1000.0, 100.0, 0.0, 0.0, 0.0, false, false, MANIFEST_VERSION)
	var query := SurfaceQuery.create(BODY_ID, [position.x, position.y, position.z], [FINAL_FIELD])
	var response: Dictionary = kernel.sample_surface(context, query)
	if not bool(response.get("success", false)): return 0.0
	return float(GeoSample.field_value(response["details"]["sample"], FINAL_FIELD, 0.0))


func _height_color(height_m: float) -> Color:
	var normalized: float = clampf((height_m + AMPLITUDE_M) / (AMPLITUDE_M * 2.0), 0.0, 1.0)
	if normalized < 0.38: return Color(0.08, 0.18, 0.32).lerp(Color(0.16, 0.42, 0.28), normalized / 0.38)
	if normalized < 0.70: return Color(0.16, 0.42, 0.28).lerp(Color(0.50, 0.37, 0.22), (normalized - 0.38) / 0.32)
	return Color(0.50, 0.37, 0.22).lerp(Color(0.86, 0.86, 0.82), (normalized - 0.70) / 0.30)


func _direction_from_lat_lon(latitude_deg: float, longitude_deg: float) -> Vector3:
	var lat: float = deg_to_rad(latitude_deg); var lon: float = deg_to_rad(longitude_deg); var cos_lat: float = cos(lat)
	return Vector3(cos_lat * cos(lon), sin(lat), cos_lat * sin(lon)).normalized()
