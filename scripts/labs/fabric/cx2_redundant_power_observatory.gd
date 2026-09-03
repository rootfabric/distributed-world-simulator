extends Node3D

const ObservationModel = preload("res://scripts/research/fabric_bake0/cx2_vis_redundant_power_observation_v1.gd")

@export var auto_play := true
@export_range(0.5, 10.0, 0.25) var stage_interval_seconds := 2.25

var observation: Dictionary = {}
var _stage_index := 0
var _part_lookup: Dictionary = {}
var _structure: MultiMeshInstance3D
var _path_a_nodes: Array[MeshInstance3D] = []
var _path_b_nodes: Array[MeshInstance3D] = []
var _lamp: MeshInstance3D
var _lamp_light: OmniLight3D
var _lamp_material: StandardMaterial3D
var _hud: Label
var _timer: Timer
var _wire_active: StandardMaterial3D
var _wire_broken: StandardMaterial3D
var _structure_material: StandardMaterial3D

func _ready() -> void:
	observation = ObservationModel.build()
	if not bool(observation.get("success", false)):
		push_error("CX2-VIS observation failed: %s" % observation)
		return
	for raw_part in observation["parts"]:
		var part: Dictionary = raw_part
		_part_lookup[String(part["part_id"])] = part
	_build_materials()
	_build_structure()
	_build_power_paths()
	_build_hud()
	_build_camera_and_light()
	_apply_stage(0)
	if auto_play:
		_timer = Timer.new()
		_timer.wait_time = stage_interval_seconds
		_timer.timeout.connect(_advance_stage)
		add_child(_timer)
		_timer.start()
	set_meta("cx2_vis_ready", true)
	set_meta("cx2_vis_checksum", String(observation["checksum"]))

func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
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
			_apply_stage(0)
		KEY_2:
			_apply_stage(1)
		KEY_3:
			_apply_stage(2)
		KEY_4:
			_apply_stage(3)

func _advance_stage() -> void:
	if observation.is_empty():
		return
	_apply_stage((_stage_index + 1) % observation["stages"].size())

func _apply_stage(index: int) -> void:
	var stages: Array = observation["stages"]
	_stage_index = clampi(index, 0, stages.size() - 1)
	var stage: Dictionary = stages[_stage_index]
	var active: Array = stage["active_functional_bond_ids"]
	var a_active := active.has("wire/path-a")
	var b_active := active.has("wire/path-b")
	_set_path_state(_path_a_nodes, a_active)
	_set_path_state(_path_b_nodes, b_active)
	_set_lamp(bool(stage["lamp"]["on"]))
	_update_hud(stage)
	set_meta("cx2_vis_stage", String(stage["name"]))
	set_meta("cx2_vis_lamp_on", bool(stage["lamp"]["on"]))
	set_meta("cx2_vis_active_paths", active.duplicate())

func _build_materials() -> void:
	_structure_material = _material(Color(0.43, 0.48, 0.54), false)
	_wire_active = _material(Color(0.98, 0.72, 0.12), true)
	_wire_broken = _material(Color(0.72, 0.10, 0.10), true)
	_lamp_material = _material(Color(0.18, 0.18, 0.16), false)

func _build_structure() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = observation["parts"].size()
	var center := _vec3(observation["bounds"]["center"])
	for index in range(observation["parts"].size()):
		var part: Dictionary = observation["parts"][index]
		var basis := Basis(_quat(part["orientation"])).scaled(_vec3(part["size"]))
		mm.set_instance_transform(index, Transform3D(basis, _vec3(part["position"]) - center))
	_structure = MultiMeshInstance3D.new()
	_structure.name = "Structure2000"
	_structure.multimesh = mm
	_structure.material_override = _structure_material
	add_child(_structure)

func _build_power_paths() -> void:
	var center := _vec3(observation["bounds"]["center"])
	var a_mid := _segment_mid(observation["support_a_segment"]) - center
	var b_mid := _segment_mid(observation["support_b_segment"]) - center
	var shared_mid := (a_mid + b_mid) * 0.5
	var battery_pos := shared_mid + Vector3(-9.0, -5.0, 4.0)
	var lamp_pos := shared_mid + Vector3(9.0, 5.0, 4.0)
	_make_box("Battery", battery_pos, Vector3(2.0, 1.3, 1.1), _material(Color(0.12, 0.18, 0.26), false))
	_make_label("BatteryLabel", "BATTERY 12 V", battery_pos + Vector3(0, 1.3, 0))

	var a_route := a_mid + Vector3(0.0, 0.0, 2.0)
	var b_route := b_mid + Vector3(0.0, 0.0, -2.0)
	_path_a_nodes = [
		_segment("PathA_Battery", battery_pos, a_route, 0.075, _wire_active),
		_segment("PathA_Lamp", a_route, lamp_pos, 0.075, _wire_active),
	]
	_path_b_nodes = [
		_segment("PathB_Battery", battery_pos, b_route, 0.075, _wire_active),
		_segment("PathB_Lamp", b_route, lamp_pos, 0.075, _wire_active),
	]
	_make_label("PathALabel", "PATH A", a_route + Vector3(0, 0.8, 0))
	_make_label("PathBLabel", "PATH B", b_route + Vector3(0, 0.8, 0))

	var sphere := SphereMesh.new()
	sphere.radius = 0.72
	sphere.height = 1.44
	_lamp = MeshInstance3D.new()
	_lamp.name = "Lamp"
	_lamp.mesh = sphere
	_lamp.material_override = _lamp_material
	_lamp.position = lamp_pos
	add_child(_lamp)
	_lamp_light = OmniLight3D.new()
	_lamp_light.name = "LampLight"
	_lamp_light.position = lamp_pos
	_lamp_light.omni_range = 8.0
	add_child(_lamp_light)
	_make_label("LampLabel", "LAMP", lamp_pos + Vector3(0, 1.3, 0))

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(18, 18)
	_hud.size = Vector2(720, 430)
	_hud.add_theme_font_size_override("font_size", 17)
	layer.add_child(_hud)

func _build_camera_and_light() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(28, 22, 34)
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 1.4
	add_child(light)

func _set_path_state(nodes: Array[MeshInstance3D], active: bool) -> void:
	for node in nodes:
		node.material_override = _wire_active if active else _wire_broken

func _set_lamp(on: bool) -> void:
	_lamp_material.emission_enabled = on
	_lamp_material.emission = Color(1.0, 0.84, 0.28)
	_lamp_material.emission_energy_multiplier = 4.0 if on else 0.0
	_lamp_material.albedo_color = Color(1.0, 0.84, 0.28) if on else Color(0.18, 0.18, 0.16)
	if is_instance_valid(_lamp_light):
		_lamp_light.visible = on
		_lamp_light.light_energy = 2.0 if on else 0.0

func _update_hud(stage: Dictionary) -> void:
	var active: Array = stage["active_functional_bond_ids"]
	_hud.text = "\n".join(PackedStringArray([
		"CX2-VIS — Redundant Power Paths",
		"Stage %d/%d: %s" % [_stage_index + 1, observation["stages"].size(), String(stage["name"])],
		"",
		"support A: %s" % String(observation["support_a"]),
		"support B: %s" % String(observation["support_b"]),
		"event A: %s" % String(observation["event_a"]),
		"event B: %s" % String(observation["event_b"]),
		"active functional paths: %s" % str(active),
		"lamp: %s" % ("ON" if bool(stage["lamp"]["on"]) else "OFF"),
		"lamp voltage: %.3f V" % float(stage["lamp"]["voltage"]),
		"lamp power: %.3f W" % float(stage["lamp"]["absorbed_power"]),
		"",
		"Acceptance:",
		"break A -> lamp ON",
		"break B -> lamp ON",
		"break A+B -> lamp OFF",
		"",
		"Controls: SPACE cycle | R/1 intact | 2 break A | 3 break B | 4 break A+B",
	]))

func _make_box(node_name: String, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = pos
	node.material_override = material
	add_child(node)
	return node

func _make_label(node_name: String, value: String, pos: Vector3) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.text = value
	label.position = pos
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 28
	add_child(label)
	return label

func _segment(node_name: String, a: Vector3, b: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var delta := b - a
	var length := delta.length()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
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

func _segment_mid(segment: Dictionary) -> Vector3:
	return (_vec3(segment["left_position"]) + _vec3(segment["right_position"])) * 0.5

func _material(color: Color, emission: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.5
	return material

func _vec3(value) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _quat(value) -> Quaternion:
	return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()
