extends Node3D

## ECO.EVO7 LS2/LS2.1 — live ecology polygon with read-only observatory.
## Presentation-only shell over the LS1 RAM session. The real ProceduralEarthWorld
## supplies environment observations; only copied in-memory populations evolve.

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Session = preload("res://scripts/ecology/shadow/eco_evo7_live_shadow_evolution_session_v1.gd")
const Observatory = preload("res://scripts/ecology/shadow/eco_evo7_evolution_observatory_v1.gd")

const SESSION_SEED := 20260826
const ZONE_ORIGINS := [Vector3(-11.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0), Vector3(11.0, 0.0, 0.0)]
const AUTO_INTERVAL_SECONDS := 0.35
const MAX_PENDING_GENERATIONS := 10000

var earth_world
var session
var observatory
var snapshot: Dictionary = {}
var ready_success := false
var auto_running := false
var pending_generations := 0
var auto_accumulator := 0.0
var visual_plant_count := 0

var plots := Node3D.new()
var hud := Label.new()
var observatory_hud := Label.new()
var status := Label.new()
var controls := HBoxContainer.new()
var start_pause_button := Button.new()
var evolution_button := Button.new()

func _ready() -> void:
	name = "EcoEvo7LiveEcologyPolygon"
	_build_world_shell()
	ready_success = _initialize_live_session()
	_refresh_all()
	if OS.get_environment("EVO7_LS2_POLYGON_AUTOCAP") == "1":
		call_deferred("_autocap")

func _process(delta: float) -> void:
	if not ready_success:
		return
	if pending_generations > 0:
		pending_generations -= 1
		_advance_generations(1)
		return
	if auto_running:
		auto_accumulator += delta
		if auto_accumulator >= AUTO_INTERVAL_SECONDS:
			auto_accumulator = 0.0
			_advance_generations(1)

func _autocap() -> void:
	await get_tree().process_frame
	if not ready_success:
		print("ECO.EVO7 LS2.1 Live Ecology Polygon: FAIL init")
		get_tree().quit(1)
		return
	var before_generation := int(snapshot.get("generation", -1))
	if not step_now(1):
		print("ECO.EVO7 LS2.1 Live Ecology Polygon: FAIL step")
		get_tree().quit(1)
		return
	print("ECO.EVO7 LS2.1 Live Ecology Polygon: PASS generation=%d->%d plants=%d history=%d state=%s" % [
		before_generation, int(snapshot.get("generation", -1)), visual_plant_count,
		get_observatory_history_size(), String(snapshot.get("state_hash", "")).substr(0, 16)])
	get_tree().quit(0)

func _initialize_live_session() -> bool:
	earth_world = EarthWorld.new()
	earth_world.name = "LiveEarthDataSource"
	earth_world.visible = false
	earth_world.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(earth_world)
	if not earth_world.setup(null):
		status.text = "Failed to initialize real ProceduralEarthWorld."
		return false
	session = Session.new()
	if not session.setup(earth_world, SESSION_SEED):
		status.text = "Failed to initialize LS1 live shadow session."
		return false
	snapshot = session.get_snapshot()
	if snapshot.is_empty():
		return false
	observatory = Observatory.new()
	if not observatory.setup(snapshot):
		status.text = "Failed to initialize LS2.1 observatory."
		return false
	return true

func _build_world_shell() -> void:
	plots.name = "Plots"
	add_child(plots)

	var sun := DirectionalLight3D.new()
	sun.name = "PolygonSun"
	sun.rotation_degrees = Vector3(-52.0, 28.0, 0.0)
	sun.light_energy = 1.25
	add_child(sun)

	var camera := Camera3D.new()
	camera.name = "PolygonCamera"
	camera.position = Vector3(0.0, 15.0, 26.0)
	camera.rotation_degrees = Vector3(-26.0, 0.0, 0.0)
	camera.current = true
	add_child(camera)

	var layer := CanvasLayer.new()
	layer.name = "PolygonUI"
	add_child(layer)

	hud.name = "PolygonHUD"
	hud.position = Vector2(18, 16)
	hud.size = Vector2(1510, 220)
	hud.add_theme_font_size_override("font_size", 16)
	layer.add_child(hud)

	observatory_hud.name = "EvolutionObservatoryHUD"
	observatory_hud.position = Vector2(18, 228)
	observatory_hud.size = Vector2(1510, 350)
	observatory_hud.add_theme_font_size_override("font_size", 13)
	layer.add_child(observatory_hud)

	status.name = "PolygonStatus"
	status.position = Vector2(18, 618)
	status.size = Vector2(1510, 74)
	status.add_theme_font_size_override("font_size", 15)
	layer.add_child(status)

	controls.name = "PolygonControls"
	controls.position = Vector2(18, 710)
	controls.size = Vector2(1510, 54)
	controls.add_theme_constant_override("separation", 10)
	layer.add_child(controls)

	start_pause_button.name = "StartPauseButton"
	start_pause_button.text = "Start"
	start_pause_button.pressed.connect(_on_start_pause_pressed)
	controls.add_child(start_pause_button)
	_add_step_button("Step1Button", "+1 generation", 1)
	_add_step_button("Step10Button", "+10 generations", 10)
	_add_step_button("Step100Button", "+100 generations", 100)

	var reset_button := Button.new()
	reset_button.name = "ResetSameSeedButton"
	reset_button.text = "Reset same seed"
	reset_button.pressed.connect(reset_same_seed)
	controls.add_child(reset_button)

	evolution_button.name = "EvolutionToggleButton"
	evolution_button.text = "Evolution: ON"
	evolution_button.pressed.connect(_on_evolution_pressed)
	controls.add_child(evolution_button)

func _add_step_button(node_name: String, label: String, amount: int) -> void:
	var button := Button.new()
	button.name = node_name
	button.text = label
	button.pressed.connect(func() -> void: queue_generations(amount))
	controls.add_child(button)

func _on_start_pause_pressed() -> void:
	set_running(not auto_running)

func _on_evolution_pressed() -> void:
	set_evolution_enabled(not session.is_evolution_enabled())

func set_running(value: bool) -> void:
	auto_running = value
	auto_accumulator = 0.0
	start_pause_button.text = "Pause" if auto_running else "Start"
	_refresh_status()

func is_running() -> bool:
	return auto_running

func set_evolution_enabled(value: bool) -> void:
	if session == null:
		return
	session.set_evolution_enabled(value)
	evolution_button.text = "Evolution: ON" if value else "Evolution: OFF"
	snapshot = session.get_snapshot()
	_refresh_all()

func queue_generations(count: int) -> void:
	if not ready_success or count <= 0:
		return
	pending_generations = mini(pending_generations + count, MAX_PENDING_GENERATIONS)
	_refresh_status()

func clear_pending_generations() -> void:
	pending_generations = 0
	_refresh_status()

func get_pending_generations() -> int:
	return pending_generations

func step_now(count: int = 1) -> bool:
	if not ready_success or count <= 0:
		return false
	return _advance_generations(count)

func _advance_generations(count: int) -> bool:
	for _i in count:
		var next_snapshot: Dictionary = session.step_generations(1)
		if next_snapshot.is_empty():
			status.text = "LS1 step failed; polygon paused fail-closed."
			set_running(false)
			return false
		snapshot = next_snapshot
		if observatory != null and not observatory.record_snapshot(snapshot):
			status.text = "LS2.1 observatory rejected snapshot; polygon paused fail-closed."
			set_running(false)
			return false
	_refresh_all()
	return true

func reset_same_seed() -> void:
	if session == null:
		return
	set_running(false)
	pending_generations = 0
	var reset_snapshot: Dictionary = session.reset_same_seed()
	if reset_snapshot.is_empty():
		ready_success = false
		status.text = "Reset failed."
		return
	snapshot = reset_snapshot
	if observatory == null:
		observatory = Observatory.new()
	if not observatory.setup(snapshot):
		ready_success = false
		status.text = "Observatory reset failed."
		return
	evolution_button.text = "Evolution: ON"
	_refresh_all()

func get_snapshot() -> Dictionary:
	return snapshot.duplicate(true)

func get_observatory_snapshot() -> Dictionary:
	return {} if observatory == null else observatory.get_latest()

func get_observatory_history_size() -> int:
	return 0 if observatory == null else observatory.get_history_size()

func get_fixation_generation(zone_index: int) -> int:
	return -1 if observatory == null else observatory.get_fixation_generation(zone_index)

func get_visual_plant_count() -> int:
	return visual_plant_count

func get_live_earth_sample() -> Dictionary:
	if earth_world == null or earth_world.get("pipeline") == null:
		return {}
	var direction: Vector3 = earth_world.get("surface_center_direction")
	if direction.length_squared() < 0.5 and earth_world.has_method("get_canonical_spawn_direction"):
		direction = earth_world.call("get_canonical_spawn_direction")
	return earth_world.pipeline.sample(direction.normalized(), 0).duplicate(true)

func request_authoritative_write(surface: String, payload: Dictionary = {}) -> Dictionary:
	if session == null:
		return {"success": false, "error_code": "ECO_LS2_SESSION_UNAVAILABLE", "details": {}}
	return session.request_authoritative_write(surface, payload)

func _refresh_all() -> void:
	if not ready_success or snapshot.is_empty():
		return
	_rebuild_plots()
	_refresh_hud()
	_refresh_observatory_hud()
	_refresh_status()

func _rebuild_plots() -> void:
	for child in plots.get_children():
		child.free()
	visual_plant_count = 0
	var zone_values: Array = snapshot.get("zones", [])
	for zone_index in mini(zone_values.size(), 3):
		_build_zone_plot(Dictionary(zone_values[zone_index]), ZONE_ORIGINS[zone_index], zone_index)

func _build_zone_plot(zone: Dictionary, origin: Vector3, zone_index: int) -> void:
	var moisture := clampf(float(zone.get("moisture", 0.5)), 0.0, 1.0)
	var ground := MeshInstance3D.new()
	ground.name = "ZoneGround%d" % zone_index
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(9.0, 0.26, 8.0)
	ground.mesh = ground_mesh
	ground.position = origin + Vector3(0.0, -0.15, 0.0)
	ground.material_override = _material(Color(0.35 - 0.12 * moisture, 0.27 + 0.20 * moisture, 0.16 + 0.16 * moisture))
	plots.add_child(ground)
	var members: Array = zone.get("members", [])
	for member_index in members.size():
		var col := member_index % 4
		var row := int(member_index / 4)
		var local_position := Vector3(float(col) * 1.85 - 2.78, 0.0, float(row) * 1.85 - 1.85)
		_build_plant(origin + local_position, Dictionary(members[member_index]), zone_index, member_index)
	var label := Label3D.new()
	label.name = "ZoneLabel%d" % zone_index
	label.text = String(zone.get("label", "ZONE"))
	label.position = origin + Vector3(0.0, 5.6, -3.35)
	label.font_size = 48
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plots.add_child(label)

func _build_plant(position: Vector3, member: Dictionary, zone_index: int, member_index: int) -> void:
	var plant := Node3D.new()
	plant.name = "Plant_%d_%02d" % [zone_index, member_index]
	plant.position = position
	plots.add_child(plant)
	visual_plant_count += 1
	var height := clampf(float(member.get("realized_height_m", 1.0)), 0.35, 6.0)
	var crown_radius := clampf(float(member.get("realized_crown_radius_m", 0.45)), 0.18, 1.45)
	var crown_density := clampf(float(member.get("realized_crown_density", 0.5)), 0.15, 1.0)
	var root_depth := clampf(float(member.get("realized_root_depth_m", 0.7)), 0.25, 3.0)
	var structural := clampf(float(member.get("structural_investment", 0.5)), 0.0, 1.0)
	var lineage_color := _lineage_color(String(member.get("lineage_id", "")))
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.height = height
	trunk_mesh.top_radius = 0.05 + structural * 0.08
	trunk_mesh.bottom_radius = trunk_mesh.top_radius * 1.35
	trunk.mesh = trunk_mesh
	trunk.position = Vector3(0.0, height * 0.5, 0.0)
	trunk.material_override = _material(Color(0.30, 0.19, 0.10))
	plant.add_child(trunk)
	var crown := MeshInstance3D.new()
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = crown_radius
	crown_mesh.height = crown_radius * 2.0
	crown.mesh = crown_mesh
	crown.scale = Vector3(1.0, 0.65 + crown_density * 0.45, 1.0)
	crown.position = Vector3(0.0, height, 0.0)
	crown.material_override = _material(lineage_color)
	plant.add_child(crown)
	var root_visual := MeshInstance3D.new()
	var root_mesh := CylinderMesh.new()
	root_mesh.height = root_depth
	root_mesh.top_radius = 0.028
	root_mesh.bottom_radius = 0.055
	root_visual.mesh = root_mesh
	root_visual.position = Vector3(0.0, -root_depth * 0.5, 0.0)
	root_visual.material_override = _material(Color(0.24, 0.14, 0.07))
	plant.add_child(root_visual)

func _lineage_color(lineage_id: String) -> Color:
	var normalized := float(abs(lineage_id.hash()) % 10000) / 10000.0
	return Color.from_hsv(normalized, 0.58, 0.78)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material

func _refresh_hud() -> void:
	var generation := int(snapshot.get("generation", -1))
	var evolution_text := "ON" if bool(snapshot.get("evolution_enabled", false)) else "OFF"
	var lines := PackedStringArray([
		"ECO.EVO7 LS2.1 — LIVE EARTH ECOLOGY POLYGON / SHADOW ONLY / NO WORLD WRITES",
		"generation=%d   evolution=%s   3 live zones x 12 plants   seed=%d" % [generation, evolution_text, int(snapshot.get("session_seed", 0))],
		"",
		"ZONE       moisture sunlight water_sat fitness     LAI  root_m dominant_lineage",
	])
	for zone_value in Array(snapshot.get("zones", [])):
		var zone: Dictionary = zone_value
		var lineage := String(zone.get("dominant_lineage", ""))
		var short_lineage := lineage.substr(maxi(0, lineage.length() - 16), 16)
		lines.append("%-10s %7.3f  %7.3f  %8.3f %8.3f %7.3f %7.3f  %s (%d/12)" % [
			String(zone.get("label", "ZONE")), float(zone.get("moisture", 0.0)), float(zone.get("sunlight", 0.0)),
			float(zone.get("mean_water_satisfaction", 0.0)), float(zone.get("mean_fitness", 0.0)),
			float(zone.get("mean_lai", 0.0)), float(zone.get("mean_root_depth_m", 0.0)),
			short_lineage, int(zone.get("dominant_lineage_count", 0)),
		])
	hud.text = "\n".join(lines)

func _refresh_observatory_hud() -> void:
	if observatory == null:
		observatory_hud.text = ""
		return
	var latest: Dictionary = observatory.get_latest()
	var lines := PackedStringArray([
		"EVOLUTION OBSERVATORY  history=%d   richness / Shannon H / fixation / trait variance / fitness contributions" % observatory.get_history_size(),
		"ZONE       rich     H   fix@      var(LAI) var(root) var(r/s) var(height)     Rsrc    Est  Wmatch  Shade -Drought  balance_err",
	])
	for zone_value in Array(latest.get("zones", [])):
		var zone: Dictionary = zone_value
		var moments: Dictionary = zone.get("trait_moments", {})
		var parts: Dictionary = zone.get("fitness_components_mean", {})
		var fix_text := "-" if int(zone.get("fixation_generation", -1)) < 0 else str(int(zone.get("fixation_generation", -1)))
		lines.append("%-10s %4d %6.3f %6s   %8.4f %8.4f %8.4f %10.4f   %7.3f %6.3f %7.3f %6.3f %8.3f %11.6f" % [
			String(zone.get("label", "ZONE")), int(zone.get("lineage_richness", 0)), float(zone.get("shannon_entropy", 0.0)), fix_text,
			float(Dictionary(moments.get("leaf_area_index_proxy", {})).get("variance", 0.0)),
			float(Dictionary(moments.get("realized_root_depth_m", {})).get("variance", 0.0)),
			float(Dictionary(moments.get("root_shoot_ratio", {})).get("variance", 0.0)),
			float(Dictionary(moments.get("realized_height_m", {})).get("variance", 0.0)),
			float(parts.get("water_limited_resource", 0.0)), float(parts.get("fitness_establishment_term", 0.0)),
			float(parts.get("fitness_water_match_term", 0.0)), float(parts.get("fitness_shade_term", 0.0)),
			float(parts.get("fitness_drought_cost", 0.0)), float(zone.get("fitness_balance_error", 0.0)),
		])
	observatory_hud.text = "\n".join(lines)

func _refresh_status() -> void:
	if not ready_success:
		return
	status.text = "runtime=%s | pending=%d | observatory=READ_ONLY | source=real ProceduralEarthWorld | mutation=canonical LineageExtension only | persistence/network/XFER=OFF" % [
		"RUNNING" if auto_running else "PAUSED", pending_generations]
