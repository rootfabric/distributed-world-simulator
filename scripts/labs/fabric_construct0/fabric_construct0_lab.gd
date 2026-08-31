extends Node3D

const Factory = preload("res://scripts/labs/fabric_construct0/construct0_preset_factory.gd")
const PlaybackScript = preload("res://scripts/labs/fabric_construct0/construct0_fabric_playback.gd")
const ConstructEditorScript = preload("res://scripts/labs/fabric_construct0/construct0_editor.gd")
const RuntimeNodeScript = preload("res://scripts/construction/runtime_projection/construction_runtime_construct_node.gd")

var _construct_root: Node3D
var _contact_root: Node3D
var _construct_node: Node3D
var _full_contacts: MultiMeshInstance3D
var _baked_contacts: MultiMeshInstance3D

var _see_status_label: Label
var _mode_label: Label
var _move_status_label: Label
var _timeline_label: Label
var _build_status_label: Label

var _current: Dictionary = {}
var _preset := "TABLE"
var _view_mode := "AUTO"

var _playback = PlaybackScript.new()
var _playing := false
var _playback_time := 0.0
var _playback_speed := 1.0

var _editor = ConstructEditorScript.new()
var _editor_active := false
var _selected_part_index := 0

func _ready() -> void:
	_build_environment()
	_build_ui()
	_load_preset(_preset)

func _process(delta: float) -> void:
	if not _playing:
		return
	_playback_time += delta * _playback_speed
	if _playback_time >= _playback.get_final_time():
		_playback_time = _playback.get_final_time()
		_playing = false
	_apply_playback_sample(_playback.sample(_playback_time))

func _build_environment() -> void:
	_construct_root = Node3D.new()
	_construct_root.name = "ConstructRoot"
	add_child(_construct_root)

	_contact_root = Node3D.new()
	_contact_root.name = "ContactObservatory"
	add_child(_contact_root)

	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.position = Vector3(0.0, -0.11, 0.0)
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(16.0, 0.2, 12.0)
	var floor_collision := CollisionShape3D.new()
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	var floor_mesh_instance := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = floor_shape.size
	floor_mesh_instance.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.08, 0.09, 0.12)
	floor_material.roughness = 0.92
	floor_mesh_instance.material_override = floor_material
	floor_body.add_child(floor_mesh_instance)
	add_child(floor_body)

	var grid := GridMap.new()
	grid.name = "ReferenceGrid"
	add_child(grid)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -32.0, 0.0)
	light.light_energy = 1.35
	light.shadow_enabled = true
	add_child(light)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-3.0, 5.0, 4.0)
	fill.omni_range = 16.0
	fill.light_energy = 2.2
	add_child(fill)

	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.016, 0.026)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.30, 0.36, 0.48)
	environment.ambient_light_energy = 0.75
	environment_node.environment = environment
	add_child(environment_node)

	var camera := Camera3D.new()
	camera.name = "ConstructCamera"
	camera.position = Vector3(8.2, 5.8, 9.2)
	camera.look_at_from_position(camera.position, Vector3(0.7, 0.8, 0.0))
	camera.current = true
	add_child(camera)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Construct0UI"
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.size = Vector2(570.0, 680.0)
	layer.add_child(panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.015, 0.020, 0.032, 0.96)
	panel_style.border_color = Color(0.20, 0.50, 0.72, 0.9)
	panel_style.set_border_width_all(1)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vertical := VBoxContainer.new()
	vertical.add_theme_constant_override("separation", 8)
	margin.add_child(vertical)

	var title := Label.new()
	title.text = "FABRIC CONSTRUCT0"
	title.add_theme_font_size_override("font_size", 24)
	vertical.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Construction is canonical. FABRIC moves it. Godot only lets us see and edit it."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.modulate = Color(0.72, 0.80, 0.92)
	vertical.add_child(subtitle)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(535.0, 590.0)
	vertical.add_child(tabs)

	_build_see_tab(tabs)
	_build_move_tab(tabs)
	_build_build_tab(tabs)

func _tab_vbox(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(500.0, 540.0)
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	return box

func _build_see_tab(tabs: TabContainer) -> void:
	var box := _tab_vbox(tabs, "SEE THE MODEL")
	var heading := Label.new()
	heading.text = "C0.1 — canonical compound object + real B0.3 reduction"
	heading.add_theme_font_size_override("font_size", 17)
	box.add_child(heading)

	var preset_grid := GridContainer.new()
	preset_grid.columns = 4
	box.add_child(preset_grid)
	for preset in Factory.PRESETS:
		var button := Button.new()
		button.text = preset.capitalize()
		button.pressed.connect(_load_preset.bind(preset))
		preset_grid.add_child(button)

	var view_grid := GridContainer.new()
	view_grid.columns = 3
	box.add_child(view_grid)
	for mode in ["AUTO", "FULL", "BAKED"]:
		var button := Button.new()
		button.text = mode
		button.pressed.connect(_set_view_mode.bind(mode))
		view_grid.add_child(button)

	_mode_label = Label.new()
	_mode_label.modulate = Color(0.95, 0.78, 0.28)
	box.add_child(_mode_label)

	_see_status_label = Label.new()
	_see_status_label.custom_minimum_size = Vector2(500.0, 380.0)
	_see_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_see_status_label.add_theme_font_size_override("font_size", 14)
	box.add_child(_see_status_label)

	var note := Label.new()
	note.text = "Blue = FULL controlled support members. Orange = B0.3 extreme generators. Unsupported domains stay NO_SAFE_BAKE."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.56, 0.66, 0.76)
	box.add_child(note)

func _build_move_tab(tabs: TabContainer) -> void:
	var box := _tab_vbox(tabs, "SEE FABRIC MOVE IT")
	var heading := Label.new()
	heading.text = "C0.2 — closed FABRIC0.18 trajectory drives the Godot projection"
	heading.add_theme_font_size_override("font_size", 17)
	box.add_child(heading)

	var controls := GridContainer.new()
	controls.columns = 4
	box.add_child(controls)
	_add_button(controls, "PLAY", _play)
	_add_button(controls, "PAUSE", _pause)
	_add_button(controls, "STEP EVENT", _step_event)
	_add_button(controls, "RESET", _reset_playback)

	var speeds := GridContainer.new()
	speeds.columns = 3
	box.add_child(speeds)
	_add_button(speeds, "0.5×", _set_playback_speed.bind(0.5))
	_add_button(speeds, "1×", _set_playback_speed.bind(1.0))
	_add_button(speeds, "2×", _set_playback_speed.bind(2.0))

	_move_status_label = Label.new()
	_move_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_move_status_label.add_theme_font_size_override("font_size", 14)
	box.add_child(_move_status_label)

	var timeline_heading := Label.new()
	timeline_heading.text = "FABRIC event timeline"
	timeline_heading.add_theme_font_size_override("font_size", 16)
	box.add_child(timeline_heading)

	_timeline_label = Label.new()
	_timeline_label.custom_minimum_size = Vector2(500.0, 260.0)
	_timeline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_timeline_label.add_theme_font_size_override("font_size", 13)
	box.add_child(_timeline_label)

	var note := Label.new()
	note.text = "Display pose is a deterministic projection of FABRIC event times and body velocities. Godot RigidBody state is never fed back as physical truth."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.56, 0.66, 0.76)
	box.add_child(note)

func _build_build_tab(tabs: TabContainer) -> void:
	var box := _tab_vbox(tabs, "BUILD IT")
	var heading := Label.new()
	heading.text = "C0.3 — minimal canonical Construction editor"
	heading.add_theme_font_size_override("font_size", 17)
	box.add_child(heading)

	var row := GridContainer.new()
	row.columns = 4
	box.add_child(row)
	_add_button(row, "NEW", _editor_new)
	_add_button(row, "+ BLOCK", _editor_add.bind("BLOCK"))
	_add_button(row, "+ PLATE", _editor_add.bind("PLATE"))
	_add_button(row, "+ BEAM", _editor_add.bind("BEAM"))

	var selection := GridContainer.new()
	selection.columns = 2
	box.add_child(selection)
	_add_button(selection, "◀ PART", _select_part.bind(-1))
	_add_button(selection, "PART ▶", _select_part.bind(1))

	var move := GridContainer.new()
	move.columns = 6
	box.add_child(move)
	_add_button(move, "X−", _editor_move.bind(Vector3(-0.25, 0.0, 0.0)))
	_add_button(move, "X+", _editor_move.bind(Vector3(0.25, 0.0, 0.0)))
	_add_button(move, "Y−", _editor_move.bind(Vector3(0.0, -0.25, 0.0)))
	_add_button(move, "Y+", _editor_move.bind(Vector3(0.0, 0.25, 0.0)))
	_add_button(move, "Z−", _editor_move.bind(Vector3(0.0, 0.0, -0.25)))
	_add_button(move, "Z+", _editor_move.bind(Vector3(0.0, 0.0, 0.25)))

	var rotation := GridContainer.new()
	rotation.columns = 4
	box.add_child(rotation)
	_add_button(rotation, "ROT −15°", _editor_rotate.bind(deg_to_rad(-15.0)))
	_add_button(rotation, "ROT +15°", _editor_rotate.bind(deg_to_rad(15.0)))
	_add_button(rotation, "BOND → ROOT", _editor_bond_to_root)
	_add_button(rotation, "BREAK LAST", _editor_break_last_bond)

	_build_status_label = Label.new()
	_build_status_label.custom_minimum_size = Vector2(500.0, 360.0)
	_build_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_status_label.add_theme_font_size_override("font_size", 14)
	box.add_child(_build_status_label)

	var note := Label.new()
	note.text = "Every add/move/rotate/bond/break operation mutates canonical Construction first, advances its revision, then rebuilds the runtime projection."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.56, 0.66, 0.76)
	box.add_child(note)

func _add_button(parent: Control, text_value: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text_value
	button.pressed.connect(callback)
	parent.add_child(button)

func _load_preset(preset: String) -> void:
	_playing = false
	_editor_active = false
	_preset = preset
	_playback_time = 0.0
	_construct_root.transform = Transform3D.IDENTITY
	_clear_scene()
	var built := Factory.build(preset)
	_current = built
	if not bool(built.get("success", false)):
		_see_status_label.text = "PRESET LOAD FAILED\n%s\n%s" % [
			String(built.get("error_code", "UNKNOWN")),
			str(built.get("details", {})),
		]
		return
	var applied := _materialize_descriptor(built["runtime_descriptor"])
	if not bool(applied.get("success", false)):
		_see_status_label.text = "RUNTIME PROJECTION FAILED\n%s" % str(applied)
		return
	_build_contact_views()
	_apply_view_visibility()
	_refresh_see_inspector()
	_refresh_move_status()

func _materialize_descriptor(descriptor: Dictionary) -> Dictionary:
	for child in _construct_root.get_children():
		_construct_root.remove_child(child)
		child.free()
	_construct_node = RuntimeNodeScript.new()
	_construct_node.name = "RuntimeConstruction"
	_construct_root.add_child(_construct_node)
	var applied: Dictionary = _construct_node.apply_descriptor(descriptor)
	if bool(applied.get("success", false)):
		_apply_construct_materials()
		_highlight_selected_part()
	return applied

func _clear_scene() -> void:
	for child in _construct_root.get_children():
		_construct_root.remove_child(child)
		child.free()
	for child in _contact_root.get_children():
		_contact_root.remove_child(child)
		child.free()
	_construct_node = null
	_full_contacts = null
	_baked_contacts = null

func _clear_contacts() -> void:
	for child in _contact_root.get_children():
		_contact_root.remove_child(child)
		child.free()
	_full_contacts = null
	_baked_contacts = null

func _build_contact_views() -> void:
	_clear_contacts()
	_full_contacts = _make_point_cloud(
		Array(_current["contact_points"]),
		0.026,
		Color(0.20, 0.76, 1.0, 0.72),
		false
	)
	_full_contacts.name = "FullContactMembers"
	_contact_root.add_child(_full_contacts)

	var generator_points: Array = []
	for generator_any in _current["contact_model"]["generators"]:
		var generator: Dictionary = generator_any
		var r: Array = generator["r"]
		generator_points.append({"position": Vector3(float(r[0]), float(r[1]), float(r[2]))})
	_baked_contacts = _make_point_cloud(
		generator_points,
		0.095,
		Color(1.0, 0.45, 0.12, 0.95),
		true
	)
	_baked_contacts.name = "BakedExtremeGenerators"
	_contact_root.add_child(_baked_contacts)

func _make_point_cloud(points: Array, radius: float, color: Color, lift: bool) -> MultiMeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.35
	mesh.material = material

	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = points.size()
	for index in range(points.size()):
		var point: Dictionary = points[index]
		var position: Vector3 = point["position"]
		position.y += 0.055 if lift else 0.018
		multi.set_instance_transform(index, Transform3D(Basis.IDENTITY, position))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	return instance

func _apply_construct_materials() -> void:
	if _construct_node == null:
		return
	var material := StandardMaterial3D.new()
	match _preset:
		"TABLE":
			material.albedo_color = Color(0.50, 0.35, 0.20)
		"BRIDGE":
			material.albedo_color = Color(0.38, 0.43, 0.50)
		"CART":
			material.albedo_color = Color(0.22, 0.48, 0.34)
		"PLANK":
			material.albedo_color = Color(0.58, 0.42, 0.22)
		_:
			material.albedo_color = Color(0.34, 0.48, 0.64)
	material.metallic = 0.08
	material.roughness = 0.68
	for node in _construct_node.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = material

func _set_view_mode(mode: String) -> void:
	_view_mode = mode
	_apply_view_visibility()
	_refresh_see_inspector()

func _apply_view_visibility() -> void:
	if _full_contacts == null or _baked_contacts == null:
		_mode_label.text = "Contact view unavailable for the current editor construction."
		return
	var effective := _view_mode
	if effective == "AUTO":
		effective = "BAKED"
	_full_contacts.visible = effective == "FULL"
	_baked_contacts.visible = effective == "BAKED"
	_mode_label.text = "Requested: %s   Effective contact view: %s" % [_view_mode, effective]

func _refresh_see_inspector() -> void:
	if not bool(_current.get("success", false)):
		return
	var snapshot: Dictionary = _current["snapshot"]
	var model: Dictionary = _current["contact_model"]
	var slide: Dictionary = _current["maximum_dissipation"]
	var tip: Dictionary = _current["tip_support"]
	var guard: Dictionary = _current["support_guard"]
	_see_status_label.text = (
		"Preset: %s\n"
		+ "Canonical construct: %s\n"
		+ "Revision: %d   build_state: %s\n"
		+ "Parts: %d   bonds: %d\n"
		+ "Canonical checksum: %s…\n\n"
		+ "B0.3 accepted domain:\n%s\n"
		+ "FULL contact members: %d\n"
		+ "BAKED extreme generators: %d\n"
		+ "Reduction: %.2fx\n"
		+ "Reverse-input model identity: %s\n\n"
		+ "Normal support limit: %.3f\n"
		+ "Representative tipping support: %.6f\n"
		+ "Max-dissipation contact power: %.6f\n"
		+ "Dissipation: %.6f\n"
		+ "Selected generator: %s\n"
		+ "75%% support guard margin: %.6f"
	) % [
		_preset,
		String(snapshot["construct_id"]),
		int(snapshot["state_revision"]),
		String(snapshot["build_state"]),
		Array(snapshot["parts"]).size(),
		Array(snapshot["bonds"]).size(),
		String(snapshot["checksum"]).left(16),
		String(model["accepted_domain"]),
		int(model["full_member_count"]),
		int(model["generator_count"]),
		float(model["reduction_ratio"]),
		str(bool(_current["reverse_model_hash_equal"])),
		float(model["normal_support_limit"]),
		float(tip["support"]),
		float(slide["contact_power"]),
		float(slide["dissipation"]),
		String(slide["selected_generator"]),
		float(guard["capacity_margin"]),
	]

func _ensure_playback() -> Dictionary:
	if _playback.is_ready():
		return {"success": true}
	var ready := _playback.setup(1.0e-9)
	if bool(ready.get("success", false)):
		_timeline_label.text = _playback.timeline_text()
	return ready

func _play() -> void:
	if _preset != "PLANK" or _editor_active:
		_load_preset("PLANK")
	var ready := _ensure_playback()
	if not bool(ready.get("success", false)):
		_move_status_label.text = "FABRIC trajectory failed: %s" % str(ready)
		return
	_clear_contacts()
	_mode_label.text = "C0.2 playback active — B0.3 observatory markers hidden."
	_playing = true
	_apply_playback_sample(_playback.sample(_playback_time))

func _pause() -> void:
	_playing = false
	_refresh_move_status()

func _step_event() -> void:
	if _preset != "PLANK" or _editor_active:
		_load_preset("PLANK")
	var ready := _ensure_playback()
	if not bool(ready.get("success", false)):
		_move_status_label.text = "FABRIC trajectory failed: %s" % str(ready)
		return
	_clear_contacts()
	_mode_label.text = "C0.2 playback active — B0.3 observatory markers hidden."
	_playing = false
	_playback_time = _playback.next_event_time(_playback_time)
	_apply_playback_sample(_playback.sample(_playback_time))

func _reset_playback() -> void:
	if _preset != "PLANK" or _editor_active:
		_load_preset("PLANK")
	var ready := _ensure_playback()
	if not bool(ready.get("success", false)):
		_move_status_label.text = "FABRIC trajectory failed: %s" % str(ready)
		return
	_clear_contacts()
	_mode_label.text = "C0.2 playback active — B0.3 observatory markers hidden."
	_playing = false
	_playback_time = 0.0
	_apply_playback_sample(_playback.reset())

func _set_playback_speed(value: float) -> void:
	_playback_speed = value
	_refresh_move_status()

func _apply_playback_sample(sample: Dictionary) -> void:
	if not bool(sample.get("success", false)):
		_move_status_label.text = "PLAYBACK SAMPLE FAILED\n%s" % str(sample)
		return
	var position: Vector3 = sample["position"]
	var orientation: Quaternion = sample["orientation"]
	_construct_root.position = position
	_construct_root.quaternion = orientation
	_refresh_move_status(sample)

func _refresh_move_status(sample: Dictionary = {}) -> void:
	if _move_status_label == null:
		return
	if not _playback.is_ready():
		_move_status_label.text = "Press PLAY/STEP to execute the closed FABRIC0.18 persistent-contact trajectory."
		if _timeline_label != null:
			_timeline_label.text = "Timeline will appear after the first exact trajectory solve."
		return
	if sample.is_empty():
		sample = _playback.sample(_playback_time)
	var v: Vector3 = sample["linear_velocity"]
	var w: Vector3 = sample["angular_velocity"]
	_move_status_label.text = (
		"time: %.6f / %.6f s   speed: %.1fx   %s\n"
		+ "event: %s\nphase: %s\n"
		+ "v = [%.5f, %.5f, %.5f] m/s\n"
		+ "w = [%.5f, %.5f, %.5f] rad/s\n"
		+ "trajectory signature: %s…"
	) % [
		float(sample["time"]),
		_playback.get_final_time(),
		_playback_speed,
		"PLAYING" if _playing else "PAUSED",
		String(sample["event_id"]),
		String(sample["phase"]),
		v.x, v.y, v.z,
		w.x, w.y, w.z,
		_playback.get_signature().left(24),
	]
	_timeline_label.text = _playback.timeline_text()

func _editor_new() -> void:
	_playing = false
	_editor_active = true
	_preset = "EDITOR"
	_selected_part_index = 0
	_construct_root.transform = Transform3D.IDENTITY
	_clear_scene()
	var ready := _editor.setup()
	if not bool(ready.get("success", false)):
		_build_status_label.text = "EDITOR SETUP FAILED\n%s" % str(ready)
		return
	_build_status_label.text = "Empty canonical Construction ready. Add BLOCK / PLATE / BEAM."

func _editor_add(kind: String) -> void:
	if not _editor_active:
		_editor_new()
	var ids := _editor.get_part_ids()
	var position := Vector3(float(ids.size()) * 0.85, 0.55 + 0.15 * float(ids.size() % 2), 0.0)
	var result := _editor.add_part(kind, position)
	if not bool(result.get("success", false)):
		_build_status_label.text = "ADD %s FAILED\n%s" % [kind, str(result)]
		return
	var next_ids := _editor.get_part_ids()
	_selected_part_index = maxi(0, next_ids.find(String(result["part_id"])))
	_refresh_editor_scene()

func _select_part(delta: int) -> void:
	var ids := _editor.get_part_ids()
	if ids.is_empty():
		_build_status_label.text = "No parts. Add BLOCK / PLATE / BEAM first."
		return
	_selected_part_index = posmod(_selected_part_index + delta, ids.size())
	_refresh_editor_status()
	_highlight_selected_part()

func _editor_move(delta: Vector3) -> void:
	var part_id := _selected_part_id()
	if part_id.is_empty():
		_build_status_label.text = "No selected part."
		return
	var result := _editor.move_part(part_id, delta)
	if not bool(result.get("success", false)):
		_build_status_label.text = "MOVE FAILED\n%s" % str(result)
		return
	_refresh_editor_scene()

func _editor_rotate(delta_rad: float) -> void:
	var part_id := _selected_part_id()
	if part_id.is_empty():
		_build_status_label.text = "No selected part."
		return
	var result := _editor.rotate_part_y(part_id, delta_rad)
	if not bool(result.get("success", false)):
		_build_status_label.text = "ROTATE FAILED\n%s" % str(result)
		return
	_refresh_editor_scene()

func _editor_bond_to_root() -> void:
	var ids := _editor.get_part_ids()
	if ids.size() < 2:
		_build_status_label.text = "Need at least two parts before creating a bond."
		return
	var selected := _selected_part_id()
	var root := String(ids[0])
	if selected == root:
		root = String(ids[1])
	var result := _editor.add_rigid_bond(root, selected)
	if not bool(result.get("success", false)):
		_build_status_label.text = "BOND FAILED\n%s" % str(result)
		return
	_refresh_editor_scene()

func _editor_break_last_bond() -> void:
	var ids := _editor.get_bond_ids(false)
	if ids.is_empty():
		_build_status_label.text = "No intact bond to break."
		return
	var result := _editor.break_bond(String(ids[-1]))
	if not bool(result.get("success", false)):
		_build_status_label.text = "BREAK FAILED\n%s" % str(result)
		return
	_refresh_editor_scene()

func _selected_part_id() -> String:
	var ids := _editor.get_part_ids()
	if ids.is_empty():
		return ""
	_selected_part_index = clampi(_selected_part_index, 0, ids.size() - 1)
	return String(ids[_selected_part_index])

func _refresh_editor_scene() -> void:
	_editor_active = true
	_clear_contacts()
	_construct_root.transform = Transform3D.IDENTITY
	var compiled := _editor.compile_runtime_descriptor()
	if not bool(compiled.get("success", false)):
		_build_status_label.text = "EDITOR PROJECTION FAILED\n%s" % str(compiled)
		return
	var applied := _materialize_descriptor(compiled["descriptor"])
	if not bool(applied.get("success", false)):
		_build_status_label.text = "EDITOR MATERIALIZATION FAILED\n%s" % str(applied)
		return
	_refresh_editor_status()
	_highlight_selected_part()
	_apply_view_visibility()

func _refresh_editor_status() -> void:
	if not _editor_active:
		return
	var snapshot := _editor.get_snapshot()
	var selected := _selected_part_id()
	var intact := _editor.get_bond_ids(false)
	var all_bonds := _editor.get_bond_ids(true)
	var selected_part: Dictionary = {}
	for part_any in snapshot["parts"]:
		var part: Dictionary = part_any
		if String(part["part_id"]) == selected:
			selected_part = part
			break
	var pose_text := "-"
	if not selected_part.is_empty():
		var p: Array = selected_part["local_position_m"]
		var q: Array = Dictionary(selected_part["metadata"]).get("local_rotation_quaternion", [0.0,0.0,0.0,1.0])
		pose_text = "p=[%.2f, %.2f, %.2f] q=[%.3f, %.3f, %.3f, %.3f]" % [
			float(p[0]), float(p[1]), float(p[2]),
			float(q[0]), float(q[1]), float(q[2]), float(q[3]),
		]
	var bond_lines: Array[String] = []
	for bond_any in snapshot["bonds"]:
		var bond: Dictionary = bond_any
		bond_lines.append("%s : %s" % [String(bond["bond_id"]).get_file(), String(bond["state"])])
	_build_status_label.text = (
		"Canonical: %s\n"
		+ "Revision: %d   build_state: %s\n"
		+ "Checksum: %s…\n"
		+ "Parts: %d   bonds: %d (%d intact)\n\n"
		+ "Selected: %s\n%s\n\n"
		+ "Bonds:\n%s\n\n"
		+ "C0.3 rule: edit → Construction revision++ → runtime projection rebuild."
	) % [
		String(snapshot["construct_id"]),
		int(snapshot["state_revision"]),
		String(snapshot["build_state"]),
		String(snapshot["checksum"]).left(20),
		Array(snapshot["parts"]).size(),
		all_bonds.size(),
		intact.size(),
		selected if not selected.is_empty() else "-",
		pose_text,
		"\n".join(bond_lines) if not bond_lines.is_empty() else "(none)",
	]

func _highlight_selected_part() -> void:
	if not _editor_active or _construct_node == null:
		return
	var selected := _selected_part_id()
	for part_id in _construct_node.get_part_ids():
		var node: Node3D = _construct_node.get_part_node(String(part_id))
		if node == null:
			continue
		for mesh_any in node.find_children("*", "MeshInstance3D", true, false):
			var mesh := mesh_any as MeshInstance3D
			var material := StandardMaterial3D.new()
			material.roughness = 0.65
			if String(part_id) == selected:
				material.albedo_color = Color(0.95, 0.68, 0.18)
				material.emission_enabled = true
				material.emission = Color(0.20, 0.08, 0.01)
			else:
				material.albedo_color = Color(0.34, 0.48, 0.64)
			mesh.material_override = material
