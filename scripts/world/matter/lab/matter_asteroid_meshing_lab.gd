extends Node3D

const MaterialCatalogScript = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const GeneratorScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_generator.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const StreamerScript = preload("res://scripts/world/matter/lab/matter_local_mesh_streamer.gd")

@export_range(1, 5, 1) var cell_level: int = 5
@export_range(0, 3, 1) var load_radius_cells: int = 1
@export_range(1, 8, 1) var max_builds_per_frame: int = 1
@export var build_collision: bool = true

var _status_label: Label
var _streamer: Node3D


func _ready() -> void:
	_build_environment()
	_build_interface()
	_start_streamer()


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.002, 0.003, 0.007, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.12, 0.14, 0.18, 1.0)
	environment.ambient_light_energy = 0.7
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28.0, -52.0, 0.0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)


func _build_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	panel.custom_minimum_size = Vector2(560.0, 0.0)
	layer.add_child(panel)
	_status_label = Label.new()
	_status_label.text = "MW3: configuring camera-local asteroid meshing..."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_status_label)


func _start_streamer() -> void:
	var material_catalog: Dictionary = MaterialCatalogScript.default_catalog()
	var generator_profile: Dictionary = GeneratorScript.default_profile()
	var feature_catalog: Dictionary = GeneratorScript.default_feature_catalog(generator_profile)
	var body: Dictionary = GeneratorScript.default_body_definition(
		generator_profile, material_catalog, feature_catalog
	)
	var grid_profile: Dictionary = GridProfileScript.create({
		"body_id": body["body_id"],
		"body_frame_id": body["body_frame_id"],
		"root_half_extent_m": float(generator_profile["reference_radius_m"]) \
			* float(generator_profile["root_bounds_radius_ratio"]),
	})
	var camera := get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		_status_label.text = "MW3 lab failed: Camera3D is missing."
		return
	camera.look_at(Vector3(1000.0, 0.0, 0.0), Vector3.UP)
	_streamer = StreamerScript.new()
	_streamer.name = "MatterLocalMeshStreamer"
	_streamer.cell_level = cell_level
	_streamer.load_radius_cells = load_radius_cells
	_streamer.max_builds_per_frame = max_builds_per_frame
	_streamer.build_collision = build_collision
	add_child(_streamer)
	_streamer.stats_changed.connect(_on_streamer_stats_changed)
	var configuration: Dictionary = _streamer.configure(
		body,
		material_catalog,
		generator_profile,
		feature_catalog,
		grid_profile,
		camera
	)
	if not bool(configuration.get("success", false)):
		_status_label.text = "MW3 lab failed: %s" % String(configuration.get("error_code", "UNKNOWN"))
		return
	_on_streamer_stats_changed(_streamer.stats())


func _on_streamer_stats_changed(stats: Dictionary) -> void:
	_status_label.text = (
		"MW3 local asteroid meshing laboratory\n"
		+ "Body: body/asteroid-mw0 | radius: 1000 m | seed: 2026073101\n"
		+ "Level: %d | radius: %d cells | generation: %d\n" % [
			int(stats.get("cell_level", 0)),
			int(stats.get("load_radius_cells", 0)),
			int(stats.get("request_generation", 0)),
		]
		+ "Desired: %d | pending: %d | surface: %d | empty: %d | failed: %d\n" % [
			int(stats.get("desired_count", 0)),
			int(stats.get("pending_count", 0)),
			int(stats.get("surface_brick_count", 0)),
			int(stats.get("empty_brick_count", 0)),
			int(stats.get("failed_brick_count", 0)),
		]
		+ "Triangles: %d | last brick build: %.2f ms | collision: %s\n" % [
			int(stats.get("triangle_count", 0)),
			float(stats.get("last_build_ms", 0.0)),
			str(build_collision),
		]
		+ "Controls: WASD — move, Q/E — down/up, Shift — boost, Esc — mouse, F — look at +X surface."
	)
