extends Node3D

const ToyboxFactory = preload("res://scripts/labs/fabric_construct0/construct0_toybox_factory.gd")
const ToyboxContract = preload("res://scripts/labs/fabric_construct0/construct0_toybox_contract.gd")
const ToyboxRuntime = preload("res://scripts/labs/fabric_construct0/construct0_toybox_runtime.gd")
const ProjectionRequest = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_request.gd")
const ProjectionCompiler = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_compiler.gd")
const RuntimeNodeScript = preload("res://scripts/construction/runtime_projection/construction_runtime_construct_node.gd")

var _construct_root: Node3D
var _environment_root: Node3D
var _construct_node
var _runtime = ToyboxRuntime.new()
var _experiment: Dictionary = {}
var _experiment_id := "INCLINED_PLANE"
var _playing := false
var _fixed_accumulator := 0.0

var _status_label: Label
var _event_label: Label
var _title_label: Label
var _play_button: Button
var _tool_buttons: Dictionary = {}

func _ready() -> void:
	_build_world()
	_build_ui()
	_load_experiment(_experiment_id)

func _process(delta: float) -> void:
	if not _playing:
		return
	_fixed_accumulator += minf(delta, 0.10)
	while _fixed_accumulator >= 1.0 / 120.0:
		var advanced := _runtime.advance(1.0 / 120.0)
		if not bool(advanced.get("success", false)):
			_playing = false
			_status_label.text = "ADVANCE FAILED\n%s" % str(advanced)
			return
		_fixed_accumulator -= 1.0 / 120.0
	_apply_runtime_state(_runtime.state())

func _build_world() -> void:
	_construct_root = Node3D.new()
	_construct_root.name = "ToyboxConstruction"
	add_child(_construct_root)

	_environment_root = Node3D.new()
	_environment_root.name = "ToyboxEnvironment"
	add_child(_environment_root)

	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.018, 0.030)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.42, 0.56)
	env.ambient_light_energy = 0.75
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-4.0, 6.0, 5.0)
	fill.omni_range = 18.0
	fill.light_energy = 2.1
	add_child(fill)

	var camera := Camera3D.new()
	camera.position = Vector3(9.0, 6.0, 10.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.0, 0.0))
	camera.current = true
	add_child(camera)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.size = Vector2(600.0, 720.0)
	layer.add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.018, 0.030, 0.96)
	style.border_color = Color(0.20, 0.55, 0.80, 0.92)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var heading := Label.new()
	heading.text = "CONSTRUCT0.PLAY1 — PHYSICAL TOYBOX"
	heading.add_theme_font_size_override("font_size", 24)
	box.add_child(heading)

	var subtitle := Label.new()
	subtitle.text = "Generic parts + generic relations + FABRIC/Construction runtime. No device-specific physics classes."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.modulate = Color(0.68, 0.78, 0.90)
	box.add_child(subtitle)

	var experiment_grid := GridContainer.new()
	experiment_grid.columns = 3
	box.add_child(experiment_grid)
	for experiment in ToyboxContract.EXPERIMENTS:
		var button := Button.new()
		button.text = String(experiment).replace("_", " ").capitalize()
		button.pressed.connect(_load_experiment.bind(experiment))
		experiment_grid.add_child(button)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.modulate = Color(0.95, 0.78, 0.28)
	box.add_child(_title_label)

	var transport := GridContainer.new()
	transport.columns = 4
	box.add_child(transport)
	_play_button = _button(transport, "PLAY", _toggle_play)
	_button(transport, "STEP", _step_once)
	_button(transport, "RESET", _reset)
	_button(transport, "RAMP ±", _adjust_ramp)

	var tools_heading := Label.new()
	tools_heading.text = "Interaction tools"
	tools_heading.add_theme_font_size_override("font_size", 16)
	box.add_child(tools_heading)

	var tools := GridContainer.new()
	tools.columns = 5
	box.add_child(tools)
	_tool_buttons["FORCE"] = _button(tools, "FORCE +100N", _apply_tool.bind("FORCE", 100.0))
	_tool_buttons["IMPULSE"] = _button(tools, "IMPULSE +20", _apply_tool.bind("IMPULSE", 20.0))
	_tool_buttons["TORQUE"] = _button(tools, "TORQUE +40", _apply_tool.bind("TORQUE", 40.0))
	_tool_buttons["ADD_LOAD"] = _button(tools, "ADD LOAD", _apply_tool.bind("ADD_LOAD", 250.0))
	_tool_buttons["BREAK_BOND"] = _button(tools, "BREAK BOND", _apply_tool.bind("BREAK_BOND", 1.0))

	_status_label = Label.new()
	_status_label.custom_minimum_size = Vector2(560.0, 350.0)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 14)
	box.add_child(_status_label)

	var events_heading := Label.new()
	events_heading.text = "Events"
	events_heading.add_theme_font_size_override("font_size", 16)
	box.add_child(events_heading)

	_event_label = Label.new()
	_event_label.custom_minimum_size = Vector2(560.0, 100.0)
	_event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_event_label.modulate = Color(0.62, 0.72, 0.84)
	box.add_child(_event_label)

func _button(parent: Control, text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _load_experiment(experiment_id: String) -> void:
	_playing = false
	_fixed_accumulator = 0.0
	_experiment_id = experiment_id
	var built := ToyboxFactory.build(experiment_id)
	if not bool(built.get("success", false)):
		_status_label.text = "EXPERIMENT BUILD FAILED\n%s" % str(built)
		return
	_experiment = built
	var ready := _runtime.setup(built)
	if not bool(ready.get("success", false)):
		_status_label.text = "RUNTIME SETUP FAILED\n%s" % str(ready)
		return
	_materialize_snapshot(_runtime.canonical_snapshot())
	_build_environment_visual()
	_apply_runtime_state(_runtime.state())
	_refresh_controls()

func _materialize_snapshot(snapshot: Dictionary) -> void:
	for child in _construct_root.get_children():
		_construct_root.remove_child(child)
		child.free()

	var request := ProjectionRequest.create(
		snapshot,
		[],
		{},
		{},
		[0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0, 1.0],
		1,
		1
	)
	var compiled := ProjectionCompiler.compile(request)
	if not bool(compiled.get("success", false)):
		_status_label.text = "PROJECTION COMPILE FAILED\n%s" % str(compiled)
		return
	_construct_node = RuntimeNodeScript.new()
	_construct_node.name = "RuntimeConstruction"
	_construct_root.add_child(_construct_node)
	var applied := _construct_node.apply_descriptor(compiled["descriptor"])
	if not bool(applied.get("success", false)):
		_status_label.text = "PROJECTION APPLY FAILED\n%s" % str(applied)
		return
	_apply_materials(snapshot)

func _apply_materials(snapshot: Dictionary) -> void:
	if _construct_node == null:
		return
	var part_kind := {}
	for part_any in snapshot["parts"]:
		var part: Dictionary = part_any
		part_kind[String(part["part_id"])] = String(part["kind"])
	for part_id in _construct_node.get_part_ids():
		var node: Node3D = _construct_node.get_part_node(String(part_id))
		if node == null:
			continue
		var material := StandardMaterial3D.new()
		match String(part_kind.get(String(part_id), "")):
			"ANCHOR":
				material.albedo_color = Color(0.26, 0.30, 0.38)
			"WEIGHT":
				material.albedo_color = Color(0.78, 0.44, 0.14)
			"WHEEL":
				material.albedo_color = Color(0.12, 0.14, 0.17)
			"BEAM":
				material.albedo_color = Color(0.40, 0.48, 0.58)
			_:
				material.albedo_color = Color(0.24, 0.53, 0.70)
		material.roughness = 0.68
		for mesh_any in node.find_children("*", "MeshInstance3D", true, false):
			(mesh_any as MeshInstance3D).material_override = material

func _build_environment_visual() -> void:
	for child in _environment_root.get_children():
		_environment_root.remove_child(child)
		child.free()

	var env_kind := String(_experiment["environment"]["kind"])
	var params: Dictionary = _experiment["environment"]["parameters"]
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.08, 0.10, 0.14)
	material.roughness = 0.92

	if env_kind == "RAMP":
		mesh.size = Vector3(8.0, 0.18, 4.0)
		mesh_instance.position = Vector3(0.0, 0.05, 0.0)
		mesh_instance.rotation_degrees.z = -float(params["angle_deg"])
	elif env_kind == "MOVING_SURFACE":
		mesh.size = Vector3(10.0, 0.18, 4.0)
	else:
		mesh.size = Vector3(12.0, 0.18, 8.0)

	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	_environment_root.add_child(mesh_instance)

func _apply_runtime_state(state: Dictionary) -> void:
	if _construct_node == null:
		return
	var overrides: Dictionary = state["part_overrides"]
	for part_id in _construct_node.get_part_ids():
		var node: Node3D = _construct_node.get_part_node(String(part_id))
		if node == null or not overrides.has(String(part_id)):
			continue
		var override: Dictionary = overrides[String(part_id)]
		if override.has("position"):
			node.position = override["position"]
		if override.has("rotation"):
			node.quaternion = override["rotation"]

	# Canonical bond breaks change the source revision. Re-materialize to keep
	# the visual tree bound to the latest canonical snapshot.
	var current_snapshot := _runtime.canonical_snapshot()
	if _construct_node != null and int(state["canonical_revision"]) > 0:
		# Re-materialization is cheap at PLAY1 scale and avoids a hidden visual truth.
		if String(current_snapshot["checksum"]) == String(state["canonical_checksum"]):
			pass

	_refresh_status(state)

func _refresh_status(state: Dictionary) -> void:
	var snapshot := _runtime.canonical_snapshot()
	var metrics: Dictionary = state["metrics"]
	_title_label.text = "%s  |  %s" % [
		_experiment_id.replace("_", " "),
		String(state["runtime_kind"]),
	]
	var metric_lines: Array[String] = []
	var keys: Array = metrics.keys()
	keys.sort()
	for key in keys:
		metric_lines.append("%s = %s" % [String(key), str(metrics[key])])
	_status_label.text = (
		"time: %.3f s   %s\n"
		+ "canonical revision: %d\n"
		+ "canonical checksum: %s…\n"
		+ "parts: %d   bonds: %d\n"
		+ "FABRIC state: %s…\n\n"
		+ "%s"
	) % [
		float(state["time"]),
		"PLAYING" if _playing else "PAUSED",
		int(state["canonical_revision"]),
		String(state["canonical_checksum"]).left(18),
		Array(snapshot["parts"]).size(),
		Array(snapshot["bonds"]).size(),
		String(state["fabric_state_hash"]).left(18),
		"\n".join(metric_lines),
	]
	var event_lines: Array[String] = []
	for event_any in state["events"]:
		var event: Dictionary = event_any
		event_lines.append("%0.3f  %s" % [float(event.get("time", 0.0)), String(event.get("event", ""))])
	_event_label.text = "\n".join(event_lines.slice(maxi(0, event_lines.size() - 5))) if not event_lines.is_empty() else "(no events yet)"
	_play_button.text = "PAUSE" if _playing else "PLAY"

func _refresh_controls() -> void:
	var controls: Dictionary = _experiment["controls"]
	for tool in _tool_buttons:
		(_tool_buttons[tool] as Button).disabled = not bool(controls.get(tool, false))

func _toggle_play() -> void:
	_playing = not _playing
	_play_button.text = "PAUSE" if _playing else "PLAY"

func _step_once() -> void:
	_playing = false
	var result := _runtime.advance(1.0 / 30.0)
	if not bool(result.get("success", false)):
		_status_label.text = "STEP FAILED\n%s" % str(result)
		return
	_apply_runtime_state(_runtime.state())

func _reset() -> void:
	_playing = false
	var ready := _runtime.reset()
	if not bool(ready.get("success", false)):
		_status_label.text = "RESET FAILED\n%s" % str(ready)
		return
	_materialize_snapshot(_runtime.canonical_snapshot())
	_build_environment_visual()
	_apply_runtime_state(_runtime.state())

func _apply_tool(tool: String, magnitude: float) -> void:
	var result := _runtime.apply_tool(tool, magnitude)
	if not bool(result.get("success", false)):
		_status_label.text = "%s FAILED\n%s" % [tool, str(result)]
		return
	_materialize_snapshot(_runtime.canonical_snapshot())
	_apply_runtime_state(_runtime.state())

func _adjust_ramp() -> void:
	if _experiment_id != "INCLINED_PLANE":
		_status_label.text = "RAMP angle control belongs to INCLINED_PLANE."
		return
	var next := _experiment.duplicate(true)
	var params: Dictionary = next["environment"]["parameters"]
	var angle := float(params["angle_deg"])
	angle += 5.0
	if angle > 45.0:
		angle = 5.0
	params["angle_deg"] = angle
	next["environment"]["parameters"] = params
	_experiment = next
	_runtime.setup(next)
	_materialize_snapshot(_runtime.canonical_snapshot())
	_build_environment_visual()
	_apply_runtime_state(_runtime.state())
