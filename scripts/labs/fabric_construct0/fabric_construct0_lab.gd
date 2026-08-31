extends Node3D

const Factory = preload("res://scripts/labs/fabric_construct0/construct0_preset_factory.gd")
const RuntimeNodeScript = preload("res://scripts/construction/runtime_projection/construction_runtime_construct_node.gd")

var _construct_root: Node3D
var _contact_root: Node3D
var _construct_node: Node3D
var _full_contacts: MultiMeshInstance3D
var _baked_contacts: MultiMeshInstance3D
var _status_label: Label
var _mode_label: Label
var _current: Dictionary = {}
var _preset := "TABLE"
var _view_mode := "AUTO"

func _ready() -> void:
	_build_environment()
	_build_ui()
	_load_preset(_preset)

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
	camera.position = Vector3(7.5, 5.4, 8.5)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.8, 0.0))
	camera.current = true
	add_child(camera)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Construct0UI"
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.size = Vector2(510.0, 650.0)
	layer.add_child(panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.015, 0.020, 0.032, 0.95)
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
	title.text = "FABRIC CONSTRUCT0 — Tangible Sandbox"
	title.add_theme_font_size_override("font_size", 22)
	vertical.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "C0.1: canonical Construction + real B0.3 contact/wrench bake\nGodot is visualization only; time integration arrives in C0.2."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.modulate = Color(0.72, 0.80, 0.92)
	vertical.add_child(subtitle)

	var preset_label := Label.new()
	preset_label.text = "Compound preset"
	preset_label.add_theme_font_size_override("font_size", 16)
	vertical.add_child(preset_label)
	var preset_grid := GridContainer.new()
	preset_grid.columns = 3
	vertical.add_child(preset_grid)
	for preset in Factory.PRESETS:
		var button := Button.new()
		button.text = preset.capitalize()
		button.pressed.connect(_load_preset.bind(preset))
		preset_grid.add_child(button)

	var view_label := Label.new()
	view_label.text = "Contact representation"
	view_label.add_theme_font_size_override("font_size", 16)
	vertical.add_child(view_label)
	var view_grid := GridContainer.new()
	view_grid.columns = 3
	vertical.add_child(view_grid)
	for mode in ["AUTO", "FULL", "BAKED"]:
		var button := Button.new()
		button.text = mode
		button.pressed.connect(_set_view_mode.bind(mode))
		view_grid.add_child(button)

	_mode_label = Label.new()
	_mode_label.modulate = Color(0.95, 0.78, 0.28)
	vertical.add_child(_mode_label)

	var separator := HSeparator.new()
	vertical.add_child(separator)

	_status_label = Label.new()
	_status_label.custom_minimum_size = Vector2(470.0, 410.0)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 14)
	vertical.add_child(_status_label)

	var help := Label.new()
	help.text = "FULL markers = all manifold members.\nBAKED markers = B0.3 extreme generators preserving the accepted 6D wrench support function."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(0.56, 0.66, 0.76)
	vertical.add_child(help)

func _load_preset(preset: String) -> void:
	_preset = preset
	_clear_current()
	var built := Factory.build(preset)
	_current = built
	if not bool(built.get("success", false)):
		_status_label.text = "PRESET LOAD FAILED\n%s\n%s" % [
			String(built.get("error_code", "UNKNOWN")),
			str(built.get("details", {})),
		]
		return
	_construct_node = RuntimeNodeScript.new()
	_construct_node.name = "RuntimeConstruction"
	_construct_root.add_child(_construct_node)
	var applied: Dictionary = _construct_node.apply_descriptor(built["runtime_descriptor"])
	if not bool(applied.get("success", false)):
		_status_label.text = "RUNTIME PROJECTION FAILED\n%s" % str(applied)
		return
	_apply_construct_materials()
	_build_contact_views()
	_apply_view_visibility()
	_refresh_inspector()

func _clear_current() -> void:
	for child in _construct_root.get_children():
		_construct_root.remove_child(child)
		child.free()
	for child in _contact_root.get_children():
		_contact_root.remove_child(child)
		child.free()
	_construct_node = null
	_full_contacts = null
	_baked_contacts = null

func _build_contact_views() -> void:
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
		_:
			material.albedo_color = Color(0.45, 0.45, 0.45)
	material.metallic = 0.08
	material.roughness = 0.68
	for node in _construct_node.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = material

func _set_view_mode(mode: String) -> void:
	_view_mode = mode
	_apply_view_visibility()
	_refresh_inspector()

func _apply_view_visibility() -> void:
	if _full_contacts == null or _baked_contacts == null:
		return
	var effective := _view_mode
	if effective == "AUTO":
		effective = "BAKED"
	_full_contacts.visible = effective == "FULL"
	_baked_contacts.visible = effective == "BAKED"
	_mode_label.text = "Requested: %s   Effective contact view: %s" % [_view_mode, effective]

func _refresh_inspector() -> void:
	if not bool(_current.get("success", false)):
		return
	var snapshot: Dictionary = _current["snapshot"]
	var model: Dictionary = _current["contact_model"]
	var slide: Dictionary = _current["maximum_dissipation"]
	var tip: Dictionary = _current["tip_support"]
	var guard: Dictionary = _current["support_guard"]
	_status_label.text = (
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
		+ "Normal support limit: %.3f N·s\n"
		+ "Representative tipping support: %.6f\n"
		+ "Max-dissipation contact power: %.6f\n"
		+ "Dissipation: %.6f\n"
		+ "Selected generator: %s\n"
		+ "75%% support guard margin: %.6f\n\n"
		+ "C0.1 boundary: contact reduction is executable;\n"
		+ "FABRIC0.18 time-driven rigid-body playback is intentionally C0.2."
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
