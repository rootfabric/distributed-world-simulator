extends Node3D

const LifecycleRuntime = preload("res://scripts/labs/fabric_construct0/construct0_lifecycle_runtime.gd")

var _runtime = LifecycleRuntime.new()
var _subject_root: Node3D
var _part_cloud: MultiMeshInstance3D
var _full_cloud: MultiMeshInstance3D
var _reduced_marker: MeshInstance3D
var _status_label: Label
var _events_label: Label
var _mode_label: Label

func _ready() -> void:
	_build_world()
	_build_ui()
	var ready: Dictionary = _runtime.setup()
	if not bool(ready.get("success", false)):
		_status_label.text = "SETUP FAILED\n%s" % str(ready)
		return
	_build_subject()
	_apply_state(_runtime.state())

func _build_world() -> void:
	_subject_root = Node3D.new()
	_subject_root.name = "LifecycleSubject"
	add_child(_subject_root)

	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.010, 0.015, 0.026)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.42, 0.55)
	env.ambient_light_energy = 0.72
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-7.0, 8.0, 7.0)
	fill.omni_range = 25.0
	fill.light_energy = 2.0
	add_child(fill)

	var camera := Camera3D.new()
	camera.position = Vector3(12.0, 10.0, 15.0)
	camera.look_at_from_position(camera.position, Vector3.ZERO)
	camera.current = true
	add_child(camera)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.size = Vector2(640.0, 760.0)
	layer.add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.018, 0.030, 0.965)
	style.border_color = Color(0.22, 0.56, 0.82, 0.95)
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
	heading.text = "CONSTRUCT0 C0.4 → C0.6 — PHYSICAL LIFECYCLE LAB"
	heading.add_theme_font_size_override("font_size", 23)
	box.add_child(heading)

	var subtitle := Label.new()
	subtitle.text = "Exact 500-part BRIDGE-1 / B0.2-D / B0.2-E subject. Godot visualizes the existing bake lifecycle; it does not implement it."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.modulate = Color(0.68, 0.78, 0.90)
	box.add_child(subtitle)

	var c04 := Label.new()
	c04.text = "C0.4 — FULL ↔ BAKED"
	c04.add_theme_font_size_override("font_size", 17)
	box.add_child(c04)
	var rep := GridContainer.new()
	rep.columns = 4
	box.add_child(rep)
	_button(rep, "AUTO", _switch_mode.bind("AUTO"))
	_button(rep, "FORCE FULL", _switch_mode.bind("FULL"))
	_button(rep, "FORCE BAKED", _switch_mode.bind("BAKED"))
	_button(rep, "NO_SAFE_BAKE", _probe_no_safe)

	var c05 := Label.new()
	c05.text = "C0.5 — MUTATION / INVALIDATION / REBUILD"
	c05.add_theme_font_size_override("font_size", 17)
	box.add_child(c05)
	var mutation := GridContainer.new()
	mutation.columns = 3
	box.add_child(mutation)
	_button(mutation, "MUTATE MASS → REBUILD", _mutate_rebuild.bind(false))
	_button(mutation, "MUTATE → FULL FALLBACK", _mutate_rebuild.bind(true))
	_button(mutation, "RESET SUBJECT", _reset)

	var c06 := Label.new()
	c06.text = "C0.6 — LOCAL UNBAKE / TOPOLOGY SPLIT"
	c06.add_theme_font_size_override("font_size", 17)
	box.add_child(c06)
	var topology := GridContainer.new()
	topology.columns = 2
	box.add_child(topology)
	_button(topology, "TRIGGER LOCAL UNBAKE", _local_unbake)
	_button(topology, "BREAK → SPLIT → REBAKE", _split_rebake)

	_mode_label = Label.new()
	_mode_label.add_theme_font_size_override("font_size", 16)
	_mode_label.modulate = Color(0.95, 0.76, 0.24)
	box.add_child(_mode_label)

	_status_label = Label.new()
	_status_label.custom_minimum_size = Vector2(600.0, 340.0)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 14)
	box.add_child(_status_label)

	var events_heading := Label.new()
	events_heading.text = "Lifecycle events"
	events_heading.add_theme_font_size_override("font_size", 16)
	box.add_child(events_heading)

	_events_label = Label.new()
	_events_label.custom_minimum_size = Vector2(600.0, 90.0)
	_events_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_events_label.modulate = Color(0.62, 0.74, 0.86)
	box.add_child(_events_label)

func _button(parent: Control, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _build_subject() -> void:
	for child in _subject_root.get_children():
		_subject_root.remove_child(child)
		child.free()

	var subject := _runtime.visual_subject()
	var parts: Array = subject.get("parts", [])
	_part_cloud = _make_part_cloud(parts, Color(0.20, 0.48, 0.72, 0.48), 1.0)
	_part_cloud.name = "Canonical500PartSubject"
	_subject_root.add_child(_part_cloud)

	_full_cloud = _make_part_cloud([], Color(1.0, 0.40, 0.12, 0.95), 1.08)
	_full_cloud.name = "FullRegionHighlight"
	_subject_root.add_child(_full_cloud)

	_reduced_marker = MeshInstance3D.new()
	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.72
	marker_mesh.height = 1.44
	marker_mesh.radial_segments = 16
	marker_mesh.rings = 8
	_reduced_marker.mesh = marker_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.94, 0.72, 0.18, 0.92)
	material.emission_enabled = true
	material.emission = Color(0.20, 0.10, 0.01)
	_reduced_marker.material_override = material
	_subject_root.add_child(_reduced_marker)

func _make_part_cloud(parts: Array, color: Color, scale_boost: float) -> MultiMeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	mesh.material = material

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = parts.size()
	for index in range(parts.size()):
		var part: Dictionary = parts[index]
		var p := _vec3(part["position"])
		var q := _quat(part["orientation"])
		var size := _part_size(part) * scale_boost
		var basis := Basis(q).scaled(size)
		mm.set_instance_transform(index, Transform3D(basis, p))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = mm
	return instance

func _refresh_full_highlight(part_ids: Array) -> void:
	if _full_cloud != null:
		_subject_root.remove_child(_full_cloud)
		_full_cloud.free()
	var subject := _runtime.visual_subject()
	var wanted := {}
	for raw in part_ids:
		wanted[String(raw)] = true
	var selected: Array = []
	for part_any in subject.get("parts", []):
		var part: Dictionary = part_any
		if wanted.has(String(part["part_id"])):
			selected.append(part)
	_full_cloud = _make_part_cloud(selected, Color(1.0, 0.34, 0.10, 0.98), 1.08)
	_subject_root.add_child(_full_cloud)

func _switch_mode(mode: String) -> void:
	var result: Dictionary = _runtime.switch_representation(mode)
	if not bool(result.get("success", false)):
		_status_label.text = "%s FAILED\n%s" % [mode, str(result)]
		return
	_apply_state(_runtime.state())

func _probe_no_safe() -> void:
	var result: Dictionary = _runtime.probe_no_safe_bake()
	if not bool(result.get("success", false)):
		_status_label.text = "NO_SAFE_BAKE PROBE FAILED\n%s" % str(result)
		return
	_apply_state(_runtime.state())

func _mutate_rebuild(force_full: bool) -> void:
	var result: Dictionary = _runtime.mutate_and_rebuild(force_full)
	if not bool(result.get("success", false)):
		_status_label.text = "C0.5 FAILED\n%s" % str(result)
		return
	_apply_state(_runtime.state())

func _local_unbake() -> void:
	var result: Dictionary = _runtime.trigger_local_unbake(30.0)
	if not bool(result.get("success", false)):
		_status_label.text = "C0.6 LOCAL UNBAKE FAILED\n%s" % str(result)
		return
	_apply_state(_runtime.state())

func _split_rebake() -> void:
	var result: Dictionary = _runtime.break_split_and_rebake()
	if not bool(result.get("success", false)):
		_status_label.text = "C0.6 SPLIT/REBAKE FAILED\n%s" % str(result)
		return
	_apply_state(_runtime.state())

func _reset() -> void:
	var result: Dictionary = _runtime.reset()
	if not bool(result.get("success", false)):
		_status_label.text = "RESET FAILED\n%s" % str(result)
		return
	_build_subject()
	_apply_state(_runtime.state())

func _apply_state(state: Dictionary) -> void:
	var effective := String(state.get("effective_representation", "UNKNOWN"))
	_mode_label.text = "%s  |  requested=%s  effective=%s" % [
		String(state.get("stage", "")),
		String(state.get("requested_representation", "-")),
		effective,
	]

	var metrics: Dictionary = state.get("metrics", {})
	var keys: Array = metrics.keys()
	keys.sort()
	var lines: Array[String] = []
	for key in keys:
		lines.append("%s = %s" % [String(key), str(metrics[key])])
	_status_label.text = "status: %s\n\n%s" % [
		String(state.get("status", "")),
		"\n".join(lines),
	]

	var events: Array = state.get("events", [])
	var event_lines: Array[String] = []
	for event_any in events:
		var event: Dictionary = event_any
		event_lines.append("%s  %s  %s" % [
			String(event.get("stage", "")),
			String(event.get("event", "")),
			String(event.get("detail", event.get("event_id", ""))),
		])
	_events_label.text = "\n".join(event_lines.slice(maxi(0, event_lines.size() - 5))) if not event_lines.is_empty() else "(none)"

	if effective == "FULL":
		_part_cloud.visible = true
		_part_cloud.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_reduced_marker.visible = false
		_refresh_full_highlight([])
	elif effective == "BAKED":
		_part_cloud.visible = true
		_part_cloud.modulate = Color(1.0, 1.0, 1.0, 0.22)
		_reduced_marker.visible = true
		_refresh_full_highlight([])
	elif effective == "MIXED_FULL_BAKED":
		_part_cloud.visible = true
		_part_cloud.modulate = Color(1.0, 1.0, 1.0, 0.28)
		_reduced_marker.visible = false
		_refresh_full_highlight(Array(state.get("full_part_ids", [])))
	elif effective == "REBAKED_COMPONENTS":
		_part_cloud.visible = true
		_part_cloud.modulate = Color(1.0, 1.0, 1.0, 0.45)
		_reduced_marker.visible = true
		_refresh_full_highlight([])
	else:
		_part_cloud.visible = true
		_reduced_marker.visible = false
		_refresh_full_highlight([])

func _part_size(part: Dictionary) -> Vector3:
	var max_abs := Vector3.ZERO
	for point_any in part.get("support_points", []):
		var p := _vec3(point_any)
		max_abs.x = maxf(max_abs.x, absf(p.x))
		max_abs.y = maxf(max_abs.y, absf(p.y))
		max_abs.z = maxf(max_abs.z, absf(p.z))
	return max_abs * 2.0

func _vec3(value) -> Vector3:
	if value is Vector3:
		return value
	var a: Array = value
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _quat(value) -> Quaternion:
	if value is Quaternion:
		return value.normalized()
	var a: Array = value
	return Quaternion(float(a[0]), float(a[1]), float(a[2]), float(a[3])).normalized()
