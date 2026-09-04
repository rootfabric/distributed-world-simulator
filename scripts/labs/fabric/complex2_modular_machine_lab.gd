extends Node3D

const Fixture = preload("res://scripts/research/fabric_bake0/complex2_modular_machine_fixture_v1.gd")

const STAGES := [
	"MIXED_BASELINE",
	"LOCAL_CONTACT",
	"DETACH_MODULE",
	"REPRESENTATION_SWAP",
	"SECOND_EVENT",
]

@export var auto_play := true
@export_range(0.5, 10.0, 0.25) var stage_interval_seconds := 2.5

var _subject: Dictionary = {}
var _result: Dictionary = {}
var _stage := 0
var _module_nodes: Dictionary = {}
var _base_positions: Dictionary = {}
var _materials: Dictionary = {}
var _branch_a: Array[MeshInstance3D] = []
var _branch_b: Array[MeshInstance3D] = []
var _hud: Label
var _timer: Timer

func _ready() -> void:
	_subject = Fixture.build()
	_result = Fixture.run_experiment()
	if not bool(_subject.get("success", false)) or not bool(_result.get("success", false)):
		push_error("COMPLEX2 visual observer could not build executable subject")
		return
	_build_materials()
	_build_modules()
	_build_power_paths()
	_build_labels()
	_build_environment()
	_build_hud()
	_apply_stage(0)
	if auto_play:
		_timer = Timer.new()
		_timer.wait_time = stage_interval_seconds
		_timer.timeout.connect(_advance_stage)
		add_child(_timer)
		_timer.start()
	set_meta("complex2_ready", true)
	set_meta("complex2_experiment_hash", String(_result["experiment_hash"]))

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
			_apply_stage(0)
		KEY_2:
			_apply_stage(1)
		KEY_3:
			_apply_stage(2)
		KEY_4:
			_apply_stage(3)
		KEY_5:
			_apply_stage(4)

func _advance_stage() -> void:
	_apply_stage((_stage + 1) % STAGES.size())

func _apply_stage(index: int) -> void:
	_stage = clampi(index, 0, STAGES.size() - 1)
	var detached := _stage >= 2
	var swapped := _stage >= 3
	var second_broken := _stage >= 4
	for module in _subject["modules"]:
		var module_id := String(module["module_id"])
		var node: MeshInstance3D = _module_nodes[module_id]
		node.position = _base_positions[module_id]
		var region_id := String(module["region_id"])
		var kind := _baseline_kind(region_id)
		if swapped:
			if region_id == Fixture.REGION_FULL:
				kind = "HYBRID_BAKE"
			elif region_id == Fixture.REGION_HYBRID:
				kind = "FULL"
		node.material_override = _materials[kind]
	if _stage == 1:
		for module_id in ["module/complex2-15", "module/complex2-16", "module/complex2-17"]:
			_module_nodes[module_id].material_override = _materials["CONTACT_ACTIVE"]
	if detached:
		_module_nodes[Fixture.DETACH_MODULE_ID].position = _base_positions[Fixture.DETACH_MODULE_ID] + Vector3(3.2, 2.2, 0.0)
	if second_broken:
		_module_nodes["module/complex2-10"].material_override = _materials["FAILED_SUPPORT"]
		_module_nodes["module/complex2-11"].material_override = _materials["FAILED_SUPPORT"]

	var power: Dictionary = _power_for_stage(_stage)
	var active_paths: Array = power["active_functional_bond_ids"]
	_set_path_visible(_branch_a, active_paths.has("wire/branch-a"))
	_set_path_visible(_branch_b, active_paths.has("wire/branch-b"))
	_update_hud(power)
	set_meta("complex2_stage", STAGES[_stage])

func _build_materials() -> void:
	_materials = {
		"STRUCTURAL_BAKE": _material(Color(0.20, 0.52, 0.80), false),
		"FULL": _material(Color(1.00, 0.48, 0.10), true),
		"CONTACT_BAKE": _material(Color(0.96, 0.72, 0.14), false),
		"DYNAMIC_ROM": _material(Color(0.25, 0.76, 0.50), false),
		"HYBRID_BAKE": _material(Color(0.70, 0.36, 0.88), false),
		"CONTACT_ACTIVE": _material(Color(1.00, 0.92, 0.20), true),
		"FAILED_SUPPORT": _material(Color(0.82, 0.10, 0.10), true),
		"POWER_A": _material(Color(0.98, 0.70, 0.10), true),
		"POWER_B": _material(Color(0.18, 0.86, 0.92), true),
		"DEVICE": _material(Color(0.15, 0.18, 0.24), false),
	}

func _build_modules() -> void:
	for module in _subject["modules"]:
		var index := int(module["index"])
		var x := float(index % 5) * 2.3 - 4.6
		var z := float(index / 5) * 2.3 - 4.6
		var y := 0.4 + float(index % 3) * 0.12
		var position := Vector3(x, y, z)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.75, 0.75, 1.75)
		var node := MeshInstance3D.new()
		node.name = "Module_%02d" % index
		node.mesh = mesh
		node.position = position
		node.material_override = _materials[_baseline_kind(String(module["region_id"]))]
		add_child(node)
		var module_id := String(module["module_id"])
		_module_nodes[module_id] = node
		_base_positions[module_id] = position

func _build_power_paths() -> void:
	var battery_pos := Vector3(-8.0, 1.8, -1.0)
	var load_a_pos := Vector3(8.0, 2.4, 3.2)
	var load_b_pos := Vector3(8.0, 2.4, -3.2)
	_make_box("Battery", battery_pos, Vector3(1.8, 1.2, 1.2), _materials["DEVICE"])
	_make_box("LoadA", load_a_pos, Vector3(1.4, 1.4, 1.4), _materials["DEVICE"])
	_make_box("LoadB", load_b_pos, Vector3(1.4, 1.4, 1.4), _materials["DEVICE"])
	var support_a: Vector3 = _base_positions[Fixture.DETACH_MODULE_ID] + Vector3(0, 1.3, 0)
	var support_b: Vector3 = (_base_positions["module/complex2-10"] + _base_positions["module/complex2-11"]) * 0.5 + Vector3(0, 1.3, 0)
	_branch_a = [
		_segment("PowerA_Source", battery_pos, support_a, _materials["POWER_A"]),
		_segment("PowerA_Load", support_a, load_a_pos, _materials["POWER_A"]),
	]
	_branch_b = [
		_segment("PowerB_Source", battery_pos, support_b, _materials["POWER_B"]),
		_segment("PowerB_Load", support_b, load_b_pos, _materials["POWER_B"]),
	]
	_make_world_label("BatteryLabel", "SOURCE", battery_pos + Vector3(0, 1.2, 0))
	_make_world_label("LoadALabel", "LOAD A", load_a_pos + Vector3(0, 1.2, 0))
	_make_world_label("LoadBLabel", "LOAD B", load_b_pos + Vector3(0, 1.2, 0))

func _build_labels() -> void:
	for mover in _subject["moving_subsystems"]:
		var module_id := String(mover["module_id"])
		var pos: Vector3 = _base_positions[module_id] + Vector3(0, 1.15, 0)
		_make_world_label(String(mover["subsystem_id"]).replace("/", "_"), String(mover["kind"]), pos)

func _build_environment() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(18, 18, 22)
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -32, 0)
	light.light_energy = 1.4
	light.shadow_enabled = true
	add_child(light)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(18, 18)
	_hud.size = Vector2(760, 560)
	_hud.add_theme_font_size_override("font_size", 16)
	layer.add_child(_hud)

func _update_hud(power: Dictionary) -> void:
	_hud.text = "\n".join(PackedStringArray([
		"COMPLEX2 — Modular Machine Lab",
		"Stage %d/%d: %s" % [_stage + 1, STAGES.size(), STAGES[_stage]],
		"",
		"canonical parts: 2000",
		"structural modules: 25",
		"moving subsystems: 6",
		"active contact zones: 3",
		"functional paths: 2",
		"execution partitions: 5 BRIDGE-2 kinds",
		"",
		"mixed/FULL max delta: %s" % String.num_scientific(float(_result["mixed_full_max_state_delta"])),
		"detach affected: %s" % str(_result["detach_affected_regions"]),
		"second affected: %s" % str(_result["second_affected_regions"]),
		"representation swap handoff error: %s" % String.num_scientific(float(_result["representation_swap_handoff_error"])),
		"",
		"active functional paths: %s" % str(power["active_functional_bond_ids"]),
		"load A: %s" % ("ON" if bool(power["load_a"]["on"]) else "OFF"),
		"load B: %s" % ("ON" if bool(power["load_b"]["on"]) else "OFF"),
		"",
		"SPACE next | R reset | 1..5 stage",
		"observer only — canonical truth remains in module/source contracts",
	]))

func _power_for_stage(stage: int) -> Dictionary:
	if stage < 2:
		return _result["power_before"]
	if stage < 4:
		return _result["power_after_detach"]
	return _result["power_after_second"]

func _baseline_kind(region_id: String) -> String:
	match region_id:
		Fixture.REGION_STRUCTURAL:
			return "STRUCTURAL_BAKE"
		Fixture.REGION_FULL:
			return "FULL"
		Fixture.REGION_CONTACT:
			return "CONTACT_BAKE"
		Fixture.REGION_DYNAMIC:
			return "DYNAMIC_ROM"
		_:
			return "HYBRID_BAKE"

func _set_path_visible(nodes: Array[MeshInstance3D], visible_value: bool) -> void:
	for node in nodes:
		node.visible = visible_value

func _make_box(node_name: String, position: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = position
	node.material_override = material
	add_child(node)
	return node

func _segment(node_name: String, a: Vector3, b: Vector3, material: Material) -> MeshInstance3D:
	var delta := b - a
	var length := delta.length()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.06
	mesh.bottom_radius = 0.06
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

func _make_world_label(node_name: String, text_value: String, position: Vector3) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.text = text_value
	label.position = position
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 22
	add_child(label)
	return label

func _material(color: Color, emission: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.62
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.7
	return material
