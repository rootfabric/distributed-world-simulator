extends Node3D

const Extension = preload("res://scripts/research/fabric_bake0/complex2b_modular_machine_extension_v1.gd")
const Compliance = preload("res://scripts/research/fabric_bake0/complex2_compliant_response_v1.gd")

const STAGES := ["BASELINE", "LOAD_80", "RELEASE", "REFINEMENT_GUARD"]

@export var auto_play := true
@export_range(0.5, 10.0, 0.25) var stage_interval_seconds := 2.5

var _built: Dictionary = {}
var _response: Dictionary = {}
var _stage := 0
var _carriage: MeshInstance3D
var _hud: Label
var _timer: Timer
var _base_carriage_position := Vector3(4.0, 1.5, 0.0)

func _ready() -> void:
	_built = Extension.build()
	if not bool(_built.get("success", false)):
		push_error("COMPLEX2-B visual extension build failed")
		return
	_response = Compliance.run_envelope(_built["parent_machine"])
	if not bool(_response.get("success", false)):
		push_error("COMPLEX2-B visual compliant response failed")
		return
	_build_world()
	_build_hud()
	_apply_stage(0)
	if auto_play:
		_timer = Timer.new()
		_timer.wait_time = stage_interval_seconds
		_timer.timeout.connect(_advance_stage)
		add_child(_timer)
		_timer.start()
	set_meta("complex2b_ready", true)
	set_meta("complex2b_experiment_hash", String(_response["experiment_hash"]))

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

func _advance_stage() -> void:
	_apply_stage((_stage + 1) % STAGES.size())

func _apply_stage(index: int) -> void:
	_stage = clampi(index, 0, STAGES.size() - 1)
	var q_m := 0.0
	if _stage == 1:
		q_m = _sample_q("HOLD_80")
	elif _stage == 2:
		q_m = _sample_q("RELEASE")
	elif _stage == 3:
		q_m = float(_response["peak_abs_deflection_m"])
	_carriage.position = _base_carriage_position + Vector3(q_m * 14.0, 0.0, 0.0)
	_update_hud(q_m)
	set_meta("complex2b_stage", STAGES[_stage])

func _build_world() -> void:
	_make_box("Anchor", Vector3(-4.0, 1.5, 0.0), Vector3(1.4, 3.0, 4.0), _material(Color(0.20, 0.52, 0.80)))
	_carriage = _make_box("CompliantCarriage", _base_carriage_position, Vector3(2.0, 2.0, 3.0), _material(Color(0.70, 0.36, 0.88)))
	for row in range(4):
		for col in range(5):
			var y := 0.5 + float(row) * 0.65
			var z := -1.4 + float(col) * 0.7
			_segment("Fiber_%02d" % (row * 5 + col), Vector3(-3.3, y, z), Vector3(3.0, y, z), _material(Color(0.82, 0.84, 0.90)))
	_make_world_label("AnchorLabel", "STRUCTURAL ANCHOR", Vector3(-4.0, 3.4, 0.0))
	_make_world_label("CarriageLabel", "MODULE 20 / HYBRID_BAKE", Vector3(4.0, 3.0, 0.0))
	_make_world_label("FiberLabel", "80 canonical spring/damper fibers → 1 reduced q", Vector3(0.0, 4.1, 0.0))

	var camera := Camera3D.new()
	camera.position = Vector3(13.0, 10.0, 15.0)
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.5, 0.0), Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 1.4
	add_child(light)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(18, 18)
	_hud.size = Vector2(820, 480)
	_hud.add_theme_font_size_override("font_size", 16)
	layer.add_child(_hud)

func _update_hud(q_m: float) -> void:
	_hud.text = "\n".join(PackedStringArray([
		"COMPLEX2-B — Compliant / Spring Response Envelope",
		"Stage %d/%d: %s" % [_stage + 1, STAGES.size(), STAGES[_stage]],
		"",
		"canonical compliant parts: 80",
		"reduced HYBRID states: 1",
		"reduction ratio: 80x",
		"K: %.3f N/m" % float(_response["total_stiffness_n_per_m"]),
		"C: %.3f N*s/m" % float(_response["total_damping_n_s_per_m"]),
		"shown q: %.6f m" % q_m,
		"peak q: %.6f m" % float(_response["peak_abs_deflection_m"]),
		"final q: %.6f m" % float(_response["final_abs_deflection_m"]),
		"",
		"FULL/HYBRID max delta: %s" % String.num_scientific(float(_response["max_full_reduced_delta_m"])),
		"reconstruction max error: %s" % String.num_scientific(float(_response["max_reconstruction_error_m"])),
		"energy residual: %s" % String.num_scientific(float(_response["max_energy_balance_residual_j"])),
		"release energy monotonic: %s" % str(_response["release_energy_monotonic"]),
		"",
		"guards: force=%s | deflection=%s | coherence=%s" % [
			_response["over_force_error"], _response["over_deflection_error"], _response["incoherent_projection_error"],
		],
		"SPACE next | R reset | 1..4 stage",
		"observer only — no canonical mutation from the scene",
	]))

func _sample_q(phase: String) -> float:
	for sample in _response["samples"]:
		if String(sample["phase"]) == phase:
			return float(sample["q_m"])
	return 0.0

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	return material

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
	mesh.top_radius = 0.035
	mesh.bottom_radius = 0.035
	mesh.height = maxf(length, 0.001)
	var y := delta.normalized() if length > 1.0e-9 else Vector3.UP
	var helper := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := helper.cross(y).normalized()
	var z := x.cross(y).normalized()
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = (a + b) * 0.5
	node.basis = Basis(x, y, z)
	node.material_override = material
	add_child(node)
	return node

func _make_world_label(node_name: String, text: String, position: Vector3) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.position = position
	label.font_size = 32
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	return label
