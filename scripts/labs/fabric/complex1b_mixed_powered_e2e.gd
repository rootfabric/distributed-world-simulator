extends Node3D

const ObservationModel = preload("res://scripts/research/fabric_bake0/complex1b_mixed_powered_observation_v1.gd")

@export var auto_play := true
@export_range(0.5, 10.0, 0.25) var stage_interval_seconds := 2.25

const VIEW_WORLD := "WORLD"
const VIEW_PHYSICS := "PHYSICS"
const VIEW_CAUSAL := "CAUSAL"

var observation: Dictionary = {}
var _stage_index := 0
var _view_mode := VIEW_PHYSICS
var _groups: Dictionary = {}
var _materials: Dictionary = {}
var _lamp: MeshInstance3D
var _lamp_light: OmniLight3D
var _lamp_material: StandardMaterial3D
var _wire_nodes: Array[MeshInstance3D] = []
var _break_marker: MeshInstance3D
var _hud: Label
var _timer: Timer

func _ready() -> void:
	observation = ObservationModel.build()
	if not bool(observation.get("success", false)):
		push_error("COMPLEX1B visual observation failed: %s" % observation)
		return
	_build_materials()
	_build_representation_groups()
	_build_power_chain()
	_build_environment()
	_build_hud()
	_apply_stage(0)
	if auto_play:
		_timer = Timer.new()
		_timer.name = "Complex1BCausalTimer"
		_timer.wait_time = stage_interval_seconds
		_timer.timeout.connect(_advance_stage)
		add_child(_timer)
		_timer.start()
	set_meta("complex1b_ready", true)
	set_meta("complex1b_checksum", String(observation["checksum"]))
	set_meta("complex1b_mixed_full_delta", float(observation["mixed_full_max_state_delta"]))

func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
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
	var stage_name := String(stages[_stage_index])
	var after_break := _stage_index >= 2
	var power_state: Dictionary = observation["power"]["after"] if after_break else observation["power"]["before"]
	_set_lamp(bool(power_state["on"]))
	for wire in _wire_nodes:
		wire.visible = not after_break
	if is_instance_valid(_break_marker):
		_break_marker.visible = after_break
	_update_representation_materials(stage_name)
	_update_hud(stage_name, power_state)
	set_meta("complex1b_stage", stage_name)
	set_meta("complex1b_lamp_on", bool(power_state["on"]))

func _set_view_mode(mode: String) -> void:
	if mode not in [VIEW_WORLD, VIEW_PHYSICS, VIEW_CAUSAL]:
		return
	_view_mode = mode
	_update_representation_materials(String(observation["stages"][_stage_index]))
	var after_break := _stage_index >= 2
	var power_state: Dictionary = observation["power"]["after"] if after_break else observation["power"]["before"]
	_update_hud(String(observation["stages"][_stage_index]), power_state)

func _build_materials() -> void:
	_materials = {
		"WORLD": _material(Color(0.56, 0.59, 0.62), false),
		"FULL": _material(Color(1.00, 0.48, 0.10), true),
		"STRUCTURAL_BAKE": _material(Color(0.20, 0.52, 0.80), false),
		"CONTACT_BAKE": _material(Color(0.96, 0.72, 0.14), true),
		"DYNAMIC_ROM": _material(Color(0.25, 0.76, 0.50), false),
		"HYBRID_BAKE": _material(Color(0.70, 0.36, 0.88), false),
		"STALE": _material(Color(0.78, 0.10, 0.12), true),
		"WIRE": _material(Color(0.98, 0.75, 0.12), true),
		"BATTERY": _material(Color(0.12, 0.18, 0.26), false),
	}
	_lamp_material = _material(Color(0.18, 0.18, 0.16), false)

func _build_representation_groups() -> void:
	for kind in ["FULL", "STRUCTURAL_BAKE", "CONTACT_BAKE", "DYNAMIC_ROM", "HYBRID_BAKE"]:
		var parts: Array = []
		for raw_part in observation["visual_parts"]:
			var part: Dictionary = raw_part
			if String(part["representation_kind"]) == kind:
				parts.append(part)
		_groups[kind] = _make_multimesh(kind, parts)

func _make_multimesh(kind: String, parts: Array) -> MultiMeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = parts.size()
	var center := _vec3(observation["bounds"]["center"])
	for index in range(parts.size()):
		var part: Dictionary = parts[index]
		var basis := Basis(_quat(part["orientation"])).scaled(_vec3(part["size"]))
		mm.set_instance_transform(index, Transform3D(basis, _vec3(part["position"]) - center))
	var node := MultiMeshInstance3D.new()
	node.name = "Representation_%s" % kind
	node.multimesh = mm
	node.material_override = _materials[kind]
	add_child(node)
	return node

func _build_power_chain() -> void:
	var center := _vec3(observation["bounds"]["center"])
	var segment: Dictionary = observation["break_segment"]
	var support := (_vec3(segment["left_position"]) + _vec3(segment["right_position"])) * 0.5 - center
	var battery_pos := support + Vector3(-8.0, -4.5, 3.5)
	var lamp_pos := support + Vector3(8.0, 4.5, 3.5)

	var battery := MeshInstance3D.new()
	battery.name = "Battery"
	var battery_mesh := BoxMesh.new()
	battery_mesh.size = Vector3(1.8, 1.2, 1.0)
	battery.mesh = battery_mesh
	battery.position = battery_pos
	battery.material_override = _materials["BATTERY"]
	add_child(battery)

	_wire_nodes = [
		_segment_mesh("WireBatteryToSupport", battery_pos, support, _materials["WIRE"]),
		_segment_mesh("WireSupportToLamp", support, lamp_pos, _materials["WIRE"]),
	]
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.72
	lamp_mesh.height = 1.44
	_lamp = MeshInstance3D.new()
	_lamp.name = "Lamp"
	_lamp.mesh = lamp_mesh
	_lamp.position = lamp_pos
	_lamp.material_override = _lamp_material
	add_child(_lamp)
	_lamp_light = OmniLight3D.new()
	_lamp_light.name = "LampLight"
	_lamp_light.position = lamp_pos
	_lamp_light.omni_range = 8.0
	add_child(_lamp_light)

	_break_marker = MeshInstance3D.new()
	_break_marker.name = "CanonicalBreakMarker"
	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.35
	marker_mesh.height = 0.7
	_break_marker.mesh = marker_mesh
	_break_marker.position = support
	_break_marker.material_override = _materials["STALE"]
	add_child(_break_marker)

	_make_label("BatteryLabel", "BATTERY 12 V", battery_pos + Vector3(0, 1.2, 0))
	_make_label("LampLabel", "LAMP", lamp_pos + Vector3(0, 1.2, 0))

func _build_environment() -> void:
	var camera := Camera3D.new()
	camera.name = "ObservatoryCamera"
	camera.position = Vector3(30, 22, 36)
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -32, 0)
	key.light_energy = 1.35
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(35, 140, 0)
	fill.light_energy = 0.4
	add_child(fill)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.size = Vector2(760, 590)
	layer.add_child(panel)
	_hud = Label.new()
	_hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.add_theme_font_size_override("font_size", 16)
	panel.add_child(_hud)

func _update_representation_materials(stage_name: String) -> void:
	for kind in _groups.keys():
		var node: MultiMeshInstance3D = _groups[kind]
		if _view_mode == VIEW_WORLD:
			node.material_override = _materials["WORLD"]
		elif kind == "STRUCTURAL_BAKE" and stage_name == "STRUCTURAL_STALE":
			node.material_override = _materials["STALE"]
		else:
			node.material_override = _materials[kind]

func _update_hud(stage_name: String, power_state: Dictionary) -> void:
	var counts: Dictionary = observation["representation_part_counts"]
	var resolution: Dictionary = observation["ownership_resolution"]
	_hud.text = "\n".join(PackedStringArray([
		"COMPLEX1B — Mixed Representation Powered E2E",
		"Stage %d/%d: %s   view=%s" % [_stage_index + 1, observation["stages"].size(), stage_name, _view_mode],
		"",
		"canonical parts: 2000",
		"FULL impact: %d" % int(counts.get("FULL", 0)),
		"STRUCTURAL_BAKE: %d" % int(counts.get("STRUCTURAL_BAKE", 0)),
		"CONTACT_BAKE: %d" % int(counts.get("CONTACT_BAKE", 0)),
		"DYNAMIC_ROM: %d" % int(counts.get("DYNAMIC_ROM", 0)),
		"HYBRID_BAKE: %d" % int(counts.get("HYBRID_BAKE", 0)),
		"",
		"event: %s" % String(observation["event"]["event_id"]),
		"event evaluator: %s / %s" % [String(resolution["evaluator_representation_id"]), String(resolution["evaluator_representation_kind"])],
		"commit policy: %s" % String(resolution["event_commit_policy"]),
		"affected mixed regions: %s" % str(observation["affected_regions"]),
		"projection mutable sources: %d" % Array(observation["projection_mutable_source_ids"]).size(),
		"mixed/FULL max delta: %s" % String.num_scientific(float(observation["mixed_full_max_state_delta"])),
		"",
		"wire support: %s" % String(observation["break_bond_id"]),
		"lamp: %s" % ("ON" if bool(power_state["on"]) else "OFF"),
		"lamp power: %.3f W" % float(power_state["absorbed_power"]),
		"functional mutation: %s" % String(observation["power"]["functional_mutation_reason"]),
		"causal FULL == MIXED: %s" % str(bool(observation["causal_equal_to_full"])),
		"",
		"SPACE next frame | R reset | 1 world | 2 physics | 3 causal",
		_stage_explanation(stage_name),
	]))

func _stage_explanation(stage_name: String) -> String:
	match stage_name:
		"MIXED_BASELINE":
			return "Five derived representations execute simultaneously; canonical Construction/Matter remains the only truth."
		"IMPACT_FULL_OWNS_EVENT":
			return "B2-A resolves the impact break to the single active FULL evaluator. Baked views are observers."
		"CANONICAL_BREAK":
			return "The same canonical BOND_BREAK advances Construction once and removes the supported wire path; FABRIC re-solves lamp power."
		"STRUCTURAL_STALE":
			return "BRIDGE-2 source update makes the dependent structural artifact STALE; mixed execution is blocked fail-closed."
		"MIXED_REBUILT":
			return "FULL projection refresh and STRUCTURAL_BAKE rebuild complete with zero state handoff error; all regions execute again."
		"FULL_REFERENCE_EQUAL":
			return "Mixed executable state matches FULL reference within 1e-12 and causal result matches the FULL powered baseline."
		_:
			return ""

func _set_lamp(on: bool) -> void:
	_lamp_material.emission_enabled = on
	_lamp_material.emission = Color(1.0, 0.84, 0.28)
	_lamp_material.emission_energy_multiplier = 4.0 if on else 0.0
	_lamp_material.albedo_color = Color(1.0, 0.84, 0.28) if on else Color(0.18, 0.18, 0.16)
	if is_instance_valid(_lamp_light):
		_lamp_light.visible = on
		_lamp_light.light_energy = 2.2 if on else 0.0

func _segment_mesh(node_name: String, a: Vector3, b: Vector3, material: Material) -> MeshInstance3D:
	var delta := b - a
	var length := delta.length()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.07
	mesh.bottom_radius = 0.07
	mesh.height = maxf(length, 0.001)
	var y := delta.normalized() if length > 1.0e-9 else Vector3.UP
	var helper := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := helper.cross(y).normalized()
	var z := x.cross(y).normalized()
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	add_child(node)
	return node

func _make_label(node_name: String, value: String, position: Vector3) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.text = value
	label.position = position
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 28
	add_child(label)
	return label

func _material(color: Color, emission: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.68
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.6
	return material

func _vec3(value) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _quat(value) -> Quaternion:
	return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()
