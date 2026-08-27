extends Node3D

## ECO.EVO7 LS3.0/LS3.1 — read-only spatial physical patch workbench.
## It visualizes physical fields only; no population or evolutionary state lives here.

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const PlanetPatch = preload("res://scripts/ecology/shadow/eco_evo7_ls30_planet_patch_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")

const GRID_SIZE := 32
const CELL_SIZE_M := 16.0
const ENVIRONMENT_SEED := 20260831
const OVERLAYS := ["MOISTURE", "ELEVATION", "SOIL", "LIGHT", "WATER"]

var earth_world
var patch: Dictionary = {}
var field: Dictionary = {}
var recipe_ids: Array[String] = []
var recipe_index := 0
var overlay_index := 0
var terrain_mesh := MeshInstance3D.new()
var hud := Label.new()
var ready_success := false

func _ready() -> void:
	name = "EcoEvo7LS31SpatialPatchLab"
	_build_shell()
	ready_success = _initialize_patch()
	if ready_success:
		_rebuild_visual()
	if OS.get_environment("EVO7_LS31_PATCH_AUTOCAP") == "1":
		call_deferred("_autocap")

func _build_shell() -> void:
	terrain_mesh.name = "SpatialPatchMesh"
	add_child(terrain_mesh)
	var sun := DirectionalLight3D.new()
	sun.name = "PatchSun"
	sun.rotation_degrees = Vector3(-55.0, -28.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	var camera := Camera3D.new()
	camera.name = "PatchCamera"
	camera.position = Vector3(0.0, 310.0, 390.0)
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	var layer := CanvasLayer.new()
	layer.name = "PatchUI"
	add_child(layer)
	hud.name = "PatchHUD"
	hud.position = Vector2(16, 16)
	hud.size = Vector2(1240, 180)
	hud.add_theme_font_size_override("font_size", 17)
	layer.add_child(hud)

func _initialize_patch() -> bool:
	earth_world = EarthWorld.new()
	earth_world.name = "LiveEarthPhysicalSource"
	add_child(earth_world)
	if not earth_world.setup(null):
		hud.text = "LS3.0 FAIL: ProceduralEarthWorld setup failed"
		return false
	if earth_world is Node3D:
		earth_world.visible = false
		earth_world.process_mode = Node.PROCESS_MODE_DISABLED
	var builder = PlanetPatch.new()
	var center: Vector3 = earth_world.get("surface_center_direction")
	if center.length_squared() < 0.5 and earth_world.has_method("get_canonical_spawn_direction"):
		center = earth_world.call("get_canonical_spawn_direction")
	patch = builder.build(earth_world, center, GRID_SIZE, CELL_SIZE_M)
	if patch.is_empty():
		hud.text = "LS3.0 FAIL: physical patch build failed"
		return false
	var generator = EnvironmentField.new()
	recipe_ids = generator.recipe_ids()
	if recipe_ids.is_empty():
		hud.text = "LS3.1 FAIL: no physical recipes"
		return false
	field = generator.generate(patch, recipe_ids[recipe_index], ENVIRONMENT_SEED)
	if field.is_empty():
		hud.text = "LS3.1 FAIL: environment field build failed"
		return false
	return true

func _unhandled_key_input(event: InputEvent) -> void:
	if not ready_success or not event.pressed or event.echo:
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_5:
		overlay_index = int(event.keycode - KEY_1)
		_rebuild_visual()
	elif event.keycode == KEY_R:
		recipe_index = (recipe_index + 1) % recipe_ids.size()
		var generator = EnvironmentField.new()
		field = generator.generate(patch, recipe_ids[recipe_index], ENVIRONMENT_SEED)
		_rebuild_visual()

func _rebuild_visual() -> void:
	var cells: Array = field.get("cells", [])
	if cells.is_empty():
		return
	var min_elevation := INF
	var max_elevation := -INF
	var min_moisture := 1.0
	var max_moisture := 0.0
	for value in cells:
		var cell: Dictionary = value
		min_elevation = minf(min_elevation, float(cell["elevation_m"]))
		max_elevation = maxf(max_elevation, float(cell["elevation_m"]))
		min_moisture = minf(min_moisture, float(cell["soil_moisture"]))
		max_moisture = maxf(max_moisture, float(cell["soil_moisture"]))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.92
	st.set_material(material)
	var half := CELL_SIZE_M * 0.49
	var vertical_scale := 0.18
	for value in cells:
		var cell: Dictionary = value
		var x := float(cell["east_m"])
		var z := -float(cell["north_m"])
		var y := (float(cell["elevation_m"]) - min_elevation) * vertical_scale
		var color := _overlay_color(cell, min_elevation, max_elevation)
		_add_triangle(st, Vector3(x - half, y, z - half), Vector3(x + half, y, z - half), Vector3(x + half, y, z + half), color)
		_add_triangle(st, Vector3(x - half, y, z - half), Vector3(x + half, y, z + half), Vector3(x - half, y, z + half), color)
	terrain_mesh.mesh = st.commit()
	hud.text = "ECO.EVO7 LS3.0/LS3.1 — 32x32 contiguous planet patch\nRecipe: %s   Overlay: %s   keys 1..5 overlay, R recipe\nPatch %s   Field %s   moisture %.3f..%.3f   elevation %.1f..%.1f m" % [
		recipe_ids[recipe_index], OVERLAYS[overlay_index],
		String(patch.get("patch_hash", "")).substr(0, 16),
		String(field.get("field_hash", "")).substr(0, 16),
		min_moisture, max_moisture, min_elevation, max_elevation,
	]

func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for vertex in [a, b, c]:
		st.set_color(color)
		st.set_normal(Vector3.UP)
		st.add_vertex(vertex)

func _overlay_color(cell: Dictionary, min_elevation: float, max_elevation: float) -> Color:
	match OVERLAYS[overlay_index]:
		"MOISTURE":
			var v := float(cell["soil_moisture"])
			return Color(0.62 - v * 0.45, 0.30 + v * 0.55, 0.18 + v * 0.70)
		"ELEVATION":
			var span := maxf(1e-9, max_elevation - min_elevation)
			var v := clampf((float(cell["elevation_m"]) - min_elevation) / span, 0.0, 1.0)
			return Color(0.18 + v * 0.70, 0.28 + v * 0.55, 0.16 + v * 0.35)
		"SOIL":
			return Color(float(cell["soil_texture_sand"]), 0.34 + float(cell["soil_texture_loam"]) * 0.45, float(cell["soil_texture_clay"]) * 0.65)
		"LIGHT":
			var v := float(cell["incident_light"])
			return Color(v, v * 0.92, 0.18 + v * 0.45)
		"WATER":
			var v := float(cell["surface_water_fraction"])
			return Color(0.12, 0.24 + v * 0.45, 0.34 + v * 0.64)
	return Color.WHITE

func _autocap() -> void:
	await get_tree().process_frame
	if not ready_success:
		print("ECO.EVO7 LS3.0/LS3.1 Spatial Patch Lab: FAIL init")
		get_tree().quit(1)
		return
	var cell_count := Array(field.get("cells", [])).size()
	if cell_count != GRID_SIZE * GRID_SIZE or terrain_mesh.mesh == null or terrain_mesh.mesh.get_surface_count() < 1:
		print("ECO.EVO7 LS3.0/LS3.1 Spatial Patch Lab: FAIL materialization")
		get_tree().quit(1)
		return
	print("ECO.EVO7 LS3.0/LS3.1 Spatial Patch Lab: PASS cells=%d recipe=%s patch=%s field=%s" % [
		cell_count, recipe_ids[recipe_index], String(patch["patch_hash"]).substr(0, 16), String(field["field_hash"]).substr(0, 16)])
	get_tree().quit(0)
