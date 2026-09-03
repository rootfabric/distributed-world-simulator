extends Node3D

const ObservationModel = preload("res://scripts/research/fabric_bake0/cx_vis_observation_model_v1.gd")

@export var powered_chain_enabled := false
@export var auto_play := true
@export_range(0.25, 10.0, 0.25) var stage_interval_seconds := 1.75

const VIEW_WORLD := "WORLD"
const VIEW_PHYSICS := "PHYSICS"
const VIEW_CAUSAL := "CAUSAL"

var observation: Dictionary = {}
var _stage_index := 0
var _view_mode := VIEW_PHYSICS
var _part_lookup: Dictionary = {}

var _stable_node: MultiMeshInstance3D
var _target_baked_node: MultiMeshInstance3D
var _target_full_node: MultiMeshInstance3D
var _component_a_node: MultiMeshInstance3D
var _component_b_node: MultiMeshInstance3D
var _weak_bond_node: MeshInstance3D
var _break_marker_node: MeshInstance3D
var _wire_nodes: Array[MeshInstance3D] = []
var _lamp_node: MeshInstance3D
var _lamp_light: OmniLight3D
var _lamp_material: StandardMaterial3D
var _timer: Timer

var _title_label: Label
var _stage_label: Label
var _stats_label: Label
var _causal_label: Label
var _help_label: Label

var _neutral_material: StandardMaterial3D
var _baked_material: StandardMaterial3D
var _full_material: StandardMaterial3D
var _component_a_material: StandardMaterial3D
var _component_b_material: StandardMaterial3D
var _critical_material: StandardMaterial3D
var _wire_material: StandardMaterial3D

func _ready() -> void:
	observation = ObservationModel.build(powered_chain_enabled)
	if not bool(observation.get("success", false)):
		push_error("CX-VIS observatory failed to build exact observation: %s" % observation)
		return
	for raw_part in observation["parts"]:
		var part: Dictionary = raw_part
		_part_lookup[String(part["part_id"])] = part

	_build_materials()
	_build_environment()
	_build_structure()
	if powered_chain_enabled:
		_build_power_chain()
	_build_hud()
	_apply_stage(0)
	if auto_play:
		_timer = Timer.new()
		_timer.name = "CausalInspectionTimer"
		_timer.wait_time = stage_interval_seconds
		_timer.timeout.connect(_advance_stage)
		add_child(_timer)
		_timer.start()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_SPACE:
			_advance_stage()
		KEY_R:
			_apply_stage(0)
		KEY_1:
			_set_view_mode(VIEW_WORLD)
		KEY_2:
			_set_view_mode(VIEW_PHYSICS)
		KEY_3:
			_set_view_mode(VIEW_CAUSAL)

func _advance_stage() -> void:
	if observation.is_empty():
		return
	var stages: Array = observation["stages"]
	if _stage_index >= stages.size() - 1:
		if _timer != null:
			_timer.stop()
		return
	_apply_stage(_stage_index + 1)

func _apply_stage(index: int) -> void:
	var stages: Array = observation["stages"]
	_stage_index = clampi(index, 0, stages.size() - 1)
	var split := _stage_index >= 5
	if is_instance_valid(_stable_node):
		_stable_node.visible = not split
	if is_instance_valid(_target_baked_node):
		_target_baked_node.visible = not split and _stage_index == 0
	if is_instance_valid(_target_full_node):
		_target_full_node.visible = not split and _stage_index >= 1
	if is_instance_valid(_component_a_node):
		_component_a_node.visible = split
	if is_instance_valid(_component_b_node):
		_component_b_node.visible = split
	if is_instance_valid(_weak_bond_node):
		_weak_bond_node.visible = _stage_index < 3
	if is_instance_valid(_break_marker_node):
		_break_marker_node.visible = _stage_index >= 3

	if powered_chain_enabled:
		var connected := _stage_index < 3
		for wire in _wire_nodes:
			wire.visible = connected
		_set_lamp_on(connected)

	_update_material_overrides()
	_update_hud()

func _set_view_mode(mode: String) -> void:
	if mode not in [VIEW_WORLD, VIEW_PHYSICS, VIEW_CAUSAL]:
		return
	_view_mode = mode
	_update_material_overrides()
	_update_hud()

func _build_materials() -> void:
	_neutral_material = _material(Color(0.62, 0.65, 0.68))
	_baked_material = _material(Color(0.23, 0.50, 0.78))
	_full_material = _material(Color(1.00, 0.52, 0.12))
	_component_a_material = _material(Color(0.24, 0.76, 0.52))
	_component_b_material = _material(Color(0.72, 0.38, 0.88))
	_critical_material = _material(Color(0.95, 0.16, 0.14))
	_wire_material = _material(Color(0.96, 0.76, 0.12))

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	return material

func _build_environment() -> void:
	var light := DirectionalLight3D.new()
	light.name = "KeyLight"
	light.rotation_degrees = Vector3(-50.0, -32.0, 0.0)
	light.light_energy = 1.25
	light.shadow_enabled = true
	add_child(light)

	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation_degrees = Vector3(38.0, 145.0, 0.0)
	fill.light_energy = 0.45
	add_child(fill)

	var camera := Camera3D.new()
	camera.name = "ObservatoryCamera"
	var size := _vec3(observation["bounds"]["size"])
	var radius := maxf(maxf(size.x, size.y), size.z)
	camera.position = Vector3(radius * 1.20, radius * 0.90, radius * 1.45)
	add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)

func _build_structure() -> void:
	var target_set := {}
	for part_id in observation["target_part_ids"]:
		target_set[String(part_id)] = true
	var stable_ids: Array = []
	for raw_part in observation["parts"]:
		var part: Dictionary = raw_part
		var part_id := String(part["part_id"])
		if not target_set.has(part_id):
			stable_ids.append(part_id)

	_stable_node = _make_multimesh("StableBakedParts", stable_ids)
	_target_baked_node = _make_multimesh("TargetBakedRegion", observation["target_part_ids"])
	_target_full_node = _make_multimesh("TargetLocalFullRegion", observation["target_part_ids"])

	var components: Array = observation["components"]
	_component_a_node = _make_multimesh("RebakedComponentA", components[0]["part_ids"])
	_component_b_node = _make_multimesh("RebakedComponentB", components[1]["part_ids"])

	var center := _vec3(observation["bounds"]["center"])
	var segment: Dictionary = observation["break_segment"]
	var left := _vec3(segment["left_position"]) - center
	var right := _vec3(segment["right_position"]) - center
	_weak_bond_node = _segment_mesh("WeakBond", left, right, 0.10, _critical_material)
	add_child(_weak_bond_node)

	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.28
	marker_mesh.height = 0.56
	_break_marker_node = MeshInstance3D.new()
	_break_marker_node.name = "CanonicalBreakMarker"
	_break_marker_node.mesh = marker_mesh
	_break_marker_node.material_override = _critical_material
	_break_marker_node.position = (left + right) * 0.5
	add_child(_break_marker_node)

func _make_multimesh(node_name: String, part_ids: Array) -> MultiMeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3.ONE

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	multimesh.instance_count = part_ids.size()

	var center := _vec3(observation["bounds"]["center"])
	for index in range(part_ids.size()):
		var part: Dictionary = _part_lookup[String(part_ids[index])]
		var position := _vec3(part["position"]) - center
		var size := _vec3(part["size"])
		var orientation := _quat(part["orientation"])
		var basis := Basis(orientation).scaled(size)
		multimesh.set_instance_transform(index, Transform3D(basis, position))

	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multimesh
	add_child(node)
	return node

func _build_power_chain() -> void:
	var center := _vec3(observation["bounds"]["center"])
	var segment: Dictionary = observation["break_segment"]
	var support_point := (_vec3(segment["left_position"]) + _vec3(segment["right_position"])) * 0.5 - center
	var battery_position := support_point + Vector3(-7.0, -4.2, 3.0)
	var lamp_position := support_point + Vector3(7.0, 4.2, 3.0)

	var battery := MeshInstance3D.new()
	battery.name = "Battery"
	var battery_mesh := BoxMesh.new()
	battery_mesh.size = Vector3(1.8, 1.2, 1.0)
	battery.mesh = battery_mesh
	battery.material_override = _material(Color(0.18, 0.22, 0.26))
	battery.position = battery_position
	add_child(battery)

	_lamp_material = StandardMaterial3D.new()
	_lamp_material.albedo_color = Color(0.20, 0.20, 0.16)
	_lamp_material.roughness = 0.35
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.72
	lamp_mesh.height = 1.44
	_lamp_node = MeshInstance3D.new()
	_lamp_node.name = "Lamp"
	_lamp_node.mesh = lamp_mesh
	_lamp_node.material_override = _lamp_material
	_lamp_node.position = lamp_position
	add_child(_lamp_node)

	_lamp_light = OmniLight3D.new()
	_lamp_light.name = "LampLight"
	_lamp_light.position = lamp_position
	_lamp_light.omni_range = 9.0
	_lamp_light.light_energy = 2.2
	add_child(_lamp_light)

	var wire_a := _segment_mesh("WireBatteryToSupport", battery_position, support_point, 0.075, _wire_material)
	var wire_b := _segment_mesh("WireSupportToLamp", support_point, lamp_position, 0.075, _wire_material)
	_wire_nodes = [wire_a, wire_b]
	for wire in _wire_nodes:
		add_child(wire)

func _segment_mesh(node_name: String, a: Vector3, b: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var delta := b - a
	var length := delta.length()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = maxf(length, 0.001)

	var y_axis := delta.normalized() if length > 1.0e-9 else Vector3.UP
	var x_axis := y_axis.cross(Vector3.FORWARD)
	if x_axis.length_squared() < 1.0e-8:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()

	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.transform = Transform3D(Basis(x_axis, y_axis, z_axis), (a + b) * 0.5)
	return node

func _set_lamp_on(is_on: bool) -> void:
	if _lamp_material == null:
		return
	_lamp_material.emission_enabled = is_on
	_lamp_material.emission = Color(1.0, 0.82, 0.32)
	_lamp_material.emission_energy_multiplier = 4.0 if is_on else 0.0
	_lamp_material.albedo_color = Color(1.0, 0.82, 0.32) if is_on else Color(0.16, 0.16, 0.15)
	if is_instance_valid(_lamp_light):
		_lamp_light.visible = is_on

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ObservatoryHUD"
	add_child(layer)

	var panel := PanelContainer.new()
	panel.name = "InfoPanel"
	panel.position = Vector2(18.0, 18.0)
	panel.size = Vector2(650.0, 520.0)
	layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	_title_label = Label.new()
	_title_label.text = "CX-VIS1 — Powered Break Observatory" if powered_chain_enabled else "CX-VIS0 — 2000-Part Break Observatory"
	_title_label.add_theme_font_size_override("font_size", 21)
	box.add_child(_title_label)

	_stage_label = Label.new()
	_stage_label.add_theme_font_size_override("font_size", 17)
	box.add_child(_stage_label)

	_stats_label = Label.new()
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_stats_label)

	_causal_label = Label.new()
	_causal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_causal_label)

	_help_label = Label.new()
	_help_label.text = "Space: next causal frame   R: reset   1: world   2: physics   3: causal"
	box.add_child(_help_label)

func _update_material_overrides() -> void:
	if not is_instance_valid(_stable_node):
		return
	if _view_mode == VIEW_WORLD:
		_stable_node.material_override = _neutral_material
		_target_baked_node.material_override = _neutral_material
		_target_full_node.material_override = _neutral_material
		_component_a_node.material_override = _neutral_material
		_component_b_node.material_override = _neutral_material
	else:
		_stable_node.material_override = _baked_material
		_target_baked_node.material_override = _baked_material
		_target_full_node.material_override = _full_material
		_component_a_node.material_override = _component_a_material
		_component_b_node.material_override = _component_b_material

func _update_hud() -> void:
	if _stage_label == null:
		return
	var stages: Array = observation["stages"]
	var stage_id := String(stages[_stage_index])
	_stage_label.text = "Frame %d/%d — %s   |   view=%s" % [_stage_index + 1, stages.size(), stage_id, _view_mode]

	var component_counts: Array = []
	for component in observation["components"]:
		component_counts.append(int(component["part_count"]))
	var stats := [
		"canonical parts: %d" % int(observation["scale"]),
		"active FULL at event: %d" % int(observation["active_full_part_count"]),
		"target region: %s" % String(observation["target_region_id"]),
		"weak bond: %s" % String(observation["break_bond_id"]),
		"event: %s / %s" % [String(observation["event"]["event_type"]), String(observation["event_commit"]["state"])],
		"old artifact after mutation: %s" % String(observation["parent_artifact_state_after_break"]),
		"split components: %s" % str(component_counts),
		"rebaked artifacts: %d" % int(observation["executable_rebake_count"]),
		"post-split reduction ratio: %.1f" % float(observation["post_split_reduction_ratio"]),
	]
	if powered_chain_enabled:
		var power: Dictionary = observation["power"]
		stats.append("wire: %s → inactive (%s)" % [String(power["functional_bond_id"]), String(power["functional_mutation_reason"])])
		stats.append("lamp power: %.3f → %.3f" % [float(power["before"]["absorbed_power"]), float(power["after"]["absorbed_power"])])
		stats.append("lamp state: ON → OFF")
	_stats_label.text = "\n".join(PackedStringArray(stats))

	_causal_label.visible = _view_mode == VIEW_CAUSAL or _view_mode == VIEW_PHYSICS
	_causal_label.text = _stage_explanation(stage_id)
	_help_label.text = "%s\n%s" % [
		"Space: next causal frame   R: reset   1: world   2: physics   3: causal",
		String(observation["inspection_note"]),
	]

func _stage_explanation(stage_id: String) -> String:
	match stage_id:
		"BASELINE_BAKED":
			return "Canonical Construction/Matter remains the only truth. The 2000-part subject is executable through its parent STRUCTURAL_BAKE artifact."
		"IMPACT_GUARD":
			return "The real COMPLEX0 refinement guard returns STRUCTURAL_REFINEMENT_REQUIRED and identifies the weak bond inside one mapped source region."
		"LOCAL_FULL":
			return "Only %d parts are exposed as local FULL detail; the rest remains reduced." % int(observation["active_full_part_count"])
		"CANONICAL_BREAK":
			return "The authoritative BOND_BREAK is committed exactly once as event %s." % String(observation["event"]["event_id"])
		"STALE_REJECTED":
			return "The old PhysicalBakeArtifact is STALE. Re-execution fails closed with %s." % String(observation["stale_rejection_error"])
		"SPLIT_REBAKED":
			return "Canonical topology now has two components. Each surviving component owns a fresh executable bake artifact."
		"WIRE_TOPOLOGY_LOST":
			return "The same structural bond ID supports the functional wire. Its loss removes %s; no device-specific fence→lamp shortcut is used." % String(observation["power"]["functional_bond_id"])
		"LAMP_OFF":
			return "FABRIC re-solves the electrical-like graph. Lamp absorbed power falls from %.3f to %.3f, therefore the lamp is OFF." % [
				float(observation["power"]["before"]["absorbed_power"]),
				float(observation["power"]["after"]["absorbed_power"]),
			]
		_:
			return ""

func _vec3(value) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _quat(value) -> Quaternion:
	return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()
