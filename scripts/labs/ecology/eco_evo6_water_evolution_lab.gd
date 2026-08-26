extends Node3D

## ECO.EVO6-WATER visual observatory.
## Four controlled water regimes evolve from the same ancestor/mutation stream.
## Crown color encodes water_preference; visible root rods encode root_depth_m.

const WaterEvolution = preload("res://scripts/research/ecology/evo6_water_evolution_bridge_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")

const SCENARIO_ORDER := ["flooded", "riparian", "mesic", "dry"]
const PLOT_SPACING := 17.0
const PLANT_SPACING := 2.0
const CAMERA_SPEED := 14.0
const MOUSE_SENSITIVITY := 0.003

var _cam: Camera3D
var _yaw := 0.0
var _pitch := -0.42
var _result: Dictionary = {}
var _dynamic_root: Node3D
var _view_final := true
var _hud: Label
var _rendered_plants := 0


func _ready() -> void:
	_result = WaterEvolution.run_all()
	if _result.is_empty():
		push_error("ECO.EVO6-WATER-VIS: evolution bridge returned empty result")
		get_tree().quit(1)
		return
	_build_world()
	_render_populations()
	_setup_camera()
	_setup_hud()
	print("ECO.EVO6-WATER-VIS: READY plants=%d result_hash=%s" % [
		_rendered_plants,
		String(_result.get("result_hash", "")),
	])
	if OS.get_environment("EVO6_WATER_LAB_AUTOCAP") == "1":
		call_deferred("_autocap")


func _build_world() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	sun.light_energy = 1.25
	add_child(sun)

	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.50, 0.57, 0.66)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.82)
	env.ambient_light_energy = 0.85
	world_env.environment = env
	add_child(world_env)

	for index in range(SCENARIO_ORDER.size()):
		_build_plot(String(SCENARIO_ORDER[index]), _plot_origin(index))

	_dynamic_root = Node3D.new()
	_dynamic_root.name = "EvolvedPopulations"
	add_child(_dynamic_root)


func _build_plot(scenario_id: String, origin: Vector3) -> void:
	var ground := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(14.0, 0.35, 8.0)
	ground.mesh = ground_mesh
	ground.position = origin + Vector3(0.0, 1.8, 0.0)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = _plot_color(scenario_id)
	ground.material_override = ground_mat
	add_child(ground)

	if scenario_id == "flooded":
		var water := MeshInstance3D.new()
		var water_mesh := BoxMesh.new()
		water_mesh.size = Vector3(14.2, 0.16, 8.2)
		water.mesh = water_mesh
		water.position = origin + Vector3(0.0, 2.08, 0.0)
		var water_mat := StandardMaterial3D.new()
		water_mat.albedo_color = Color(0.18, 0.48, 0.72)
		water.material_override = water_mat
		add_child(water)
	elif scenario_id == "riparian":
		var channel := MeshInstance3D.new()
		var channel_mesh := BoxMesh.new()
		channel_mesh.size = Vector3(2.8, 0.18, 8.2)
		channel.mesh = channel_mesh
		channel.position = origin + Vector3(-5.5, 2.06, 0.0)
		var channel_mat := StandardMaterial3D.new()
		channel_mat.albedo_color = Color(0.20, 0.51, 0.75)
		channel.material_override = channel_mat
		add_child(channel)

	var title := Label3D.new()
	title.name = "PlotTitle_%s" % scenario_id
	title.text = scenario_id.to_upper()
	title.font_size = 44
	title.outline_size = 8
	title.position = origin + Vector3(0.0, 7.3, -3.7)
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(title)


func _render_populations() -> void:
	if _dynamic_root == null:
		return
	for child in _dynamic_root.get_children():
		child.free()
	_rendered_plants = 0

	var scenarios: Dictionary = _result.get("scenarios", {})
	for plot_index in range(SCENARIO_ORDER.size()):
		var scenario_id := String(SCENARIO_ORDER[plot_index])
		var scenario: Dictionary = scenarios.get(scenario_id, {})
		if scenario.is_empty():
			continue
		var genomes: Array = []
		if _view_final:
			genomes = Array(scenario.get("final_genomes", []))
		else:
			for _index in range(int(_result.get("population_size", 0))):
				genomes.append(PlantGenome.create_default())
		var origin := _plot_origin(plot_index)
		for index in range(genomes.size()):
			var genome: Dictionary = genomes[index]
			var row := index / 6
			var col := index % 6
			var pos := origin + Vector3(
				(float(col) - 2.5) * PLANT_SPACING,
				2.15,
				(float(row) - 1.0) * PLANT_SPACING
			)
			_make_encoded_plant(pos, genome, scenario_id, index)
			_rendered_plants += 1
		_make_stats_label(origin, scenario_id, scenario)

	_update_hud()


func _make_encoded_plant(pos: Vector3, genome: Dictionary, scenario_id: String, index: int) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.name = "%s_%02d" % [scenario_id, index]
	_dynamic_root.add_child(holder)

	var preference := clampf(float(genome.get("water_preference", 0.5)), 0.0, 1.0)
	var root_depth := maxf(0.05, float(genome.get("root_depth_m", 0.85)))
	var checksum := String(genome.get("checksum", ""))
	var variation := _unit("plant|%s|%d" % [checksum, index])

	# Root-depth encoder: the laboratory plots float above empty space so the
	# downward rod is visible from the side. Length is proportional to root_depth_m.
	var root_rod := MeshInstance3D.new()
	var root_mesh := CylinderMesh.new()
	root_mesh.top_radius = 0.055
	root_mesh.bottom_radius = 0.085
	root_mesh.height = clampf(root_depth * 0.72, 0.20, 3.8)
	root_rod.mesh = root_mesh
	root_rod.position.y = -root_mesh.height * 0.5
	var root_mat := StandardMaterial3D.new()
	root_mat.albedo_color = Color(0.27, 0.16, 0.09)
	root_rod.material_override = root_mat
	holder.add_child(root_rod)

	var trunk_h := 1.15 + variation * 0.35
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.07
	trunk_mesh.bottom_radius = 0.12
	trunk_mesh.height = trunk_h
	trunk.mesh = trunk_mesh
	trunk.position.y = trunk_h * 0.5
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.34, 0.22, 0.12)
	trunk.material_override = trunk_mat
	holder.add_child(trunk)

	var dry_leaf := Color(0.66, 0.61, 0.18)
	var wet_leaf := Color(0.08, 0.50, 0.45)
	var leaf_color := dry_leaf.lerp(wet_leaf, preference)
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = leaf_color

	for crown_index in range(3):
		var crown := MeshInstance3D.new()
		var crown_mesh := SphereMesh.new()
		var radius := 0.38 + 0.10 * _unit("radius|%s|%d" % [checksum, crown_index])
		crown_mesh.radius = radius
		crown_mesh.height = radius * 2.0
		crown.mesh = crown_mesh
		var angle := TAU * float(crown_index) / 3.0 + variation * 0.7
		crown.position = Vector3(
			cos(angle) * 0.30,
			trunk_h + 0.18 + 0.18 * float(crown_index % 2),
			sin(angle) * 0.30
		)
		crown.material_override = leaf_mat
		holder.add_child(crown)


func _make_stats_label(origin: Vector3, scenario_id: String, scenario: Dictionary) -> void:
	var stats := Label3D.new()
	stats.font_size = 28
	stats.outline_size = 6
	stats.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	stats.position = origin + Vector3(0.0, 5.9, -3.7)
	var summary: Dictionary = scenario["final"] if _view_final else scenario["initial"]
	stats.text = "water=%.2f  pref=%.3f  roots=%.2fm  unique=%d" % [
		float(scenario.get("surface_water", 0.0)),
		float(summary.get("mean_water_preference", 0.0)),
		float(summary.get("mean_root_depth_m", 0.0)),
		int(summary.get("unique_genomes", 0)),
	]
	_dynamic_root.add_child(stats)


func _setup_camera() -> void:
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	_cam.position = Vector3(0.0, 20.0, 30.0)
	_apply_look()


func _setup_hud() -> void:
	_hud = Label.new()
	_hud.position = Vector2(14, 12)
	_hud.add_theme_font_size_override("font_size", 17)
	add_child(_hud)
	_update_hud()


func _update_hud() -> void:
	if _hud == null:
		return
	var phase := "FINAL generation %d" % int(_result.get("generations", 0)) if _view_final else "INITIAL generation 0"
	_hud.text = (
		"EVO6-WATER | %s | SPACE=initial/final | click=capture | WASD move | Q/E down/up | Esc=release\n"
		+ "leaf color: yellow=dry preference, teal=wet preference | visible brown rod below plot = root depth"
	) % phase


func _plot_origin(index: int) -> Vector3:
	return Vector3((float(index) - 1.5) * PLOT_SPACING, 0.0, 0.0)


func _plot_color(scenario_id: String) -> Color:
	match scenario_id:
		"flooded": return Color(0.25, 0.37, 0.43)
		"riparian": return Color(0.35, 0.48, 0.30)
		"mesic": return Color(0.44, 0.43, 0.26)
		"dry": return Color(0.61, 0.49, 0.25)
		_: return Color(0.42, 0.42, 0.42)


func _unit(text: String) -> float:
	return float(text.sha256_text().substr(0, 12).hex_to_int()) / 281474976710655.0


func _apply_look() -> void:
	if _cam == null:
		return
	_cam.rotation = Vector3(_pitch, _yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.45, 1.45)
		_apply_look()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_SPACE:
			_view_final = not _view_final
			_render_populations()


func _process(delta: float) -> void:
	if _cam == null:
		return
	var move := Vector3.ZERO
	var basis := _cam.global_transform.basis
	if Input.is_key_pressed(KEY_W): move -= basis.z
	if Input.is_key_pressed(KEY_S): move += basis.z
	if Input.is_key_pressed(KEY_A): move -= basis.x
	if Input.is_key_pressed(KEY_D): move += basis.x
	if Input.is_key_pressed(KEY_Q): move -= Vector3.UP
	if Input.is_key_pressed(KEY_E): move += Vector3.UP
	if move.length_squared() > 0.0:
		_cam.global_position += move.normalized() * CAMERA_SPEED * delta


func _autocap() -> void:
	var scenarios: Dictionary = _result.get("scenarios", {})
	var flooded: Dictionary = scenarios.get("flooded", {})
	var dry: Dictionary = scenarios.get("dry", {})
	var pref_span := 0.0
	var root_span := 0.0
	if not flooded.is_empty() and not dry.is_empty():
		pref_span = float(flooded["final"]["mean_water_preference"]) - float(dry["final"]["mean_water_preference"])
		root_span = float(dry["final"]["mean_root_depth_m"]) - float(flooded["final"]["mean_root_depth_m"])
	var expected := int(_result.get("population_size", 0)) * SCENARIO_ORDER.size()
	var ok := (
		_rendered_plants == expected
		and pref_span > 0.20
		and root_span > 0.35
		and int(_result.get("metrics", {}).get("distinct_final_populations", 0)) >= 3
	)
	print("ECO.EVO6-WATER-VIS: %s plants=%d pref_span=%.3f root_span=%.3f" % [
		"PASS" if ok else "FAIL",
		_rendered_plants,
		pref_span,
		root_span,
	])
	get_tree().quit(0 if ok else 1)
