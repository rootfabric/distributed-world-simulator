extends Node3D

const Fixture = preload("res://tests/research/fabric1/complex4_real_world_machine_fixture_v1.gd")
const Session = preload("res://scripts/labs/fabric/complex4_vis1_session_v1.gd")
const VIS_SCHEMA := "planet_simulator.fabric_complex4_vis1_playable_lab.v1"
const SCALE_X := 0.16

var _session := Session.new()
var _proof_step := 0
var _materials: Dictionary = {}
var _supports: Dictionary = {}
var _paths: Dictionary = {}
var _lamp_material: StandardMaterial3D
var _lamp_light: OmniLight3D
var _hud: Label
var _events: Label

func _ready() -> void:
	_build_materials()
	_build_world()
	_build_hud()
	reset_lab()
	set_meta("complex4_vis1_ready", true)
	set_meta("complex4_vis1_schema", VIS_SCHEMA)

func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE: advance_demo()
		KEY_1: break_primary()
		KEY_2: break_backup()
		KEY_N: restart_from_authority()
		KEY_R: reset_lab()

func reset_lab() -> bool:
	_proof_step = 0
	return _consume(_session.reset(), "Baseline BAKED state")

func propose_support_failure(support_id: String, event_id: String) -> bool:
	return _consume(_session.propose(support_id, event_id), "Physical proposal only — canonical world unchanged")

func apply_pending_canonical_failure() -> bool:
	return _consume(_session.apply_pending(), "External canonical mutation committed")

func break_primary() -> bool:
	return _consume(_session.break_now(Fixture.SUPPORT_A, "event/complex4-vis1/support-primary-broken"), "Primary support canonical failure")

func break_backup() -> bool:
	return _consume(_session.break_now(Fixture.SUPPORT_B, "event/complex4-vis1/support-backup-broken"), "Backup support canonical failure")

func restart_from_authority() -> bool:
	return _consume(_session.restart(), "Restart from authoritative revision")

func advance_demo() -> bool:
	var ok := false
	match _proof_step:
		0: ok = propose_support_failure(Fixture.SUPPORT_A, "event/complex4-vis1/support-primary-broken")
		1: ok = apply_pending_canonical_failure()
		2: ok = propose_support_failure(Fixture.SUPPORT_B, "event/complex4-vis1/support-backup-broken")
		3: ok = apply_pending_canonical_failure()
		4: ok = restart_from_authority()
		_: return reset_lab()
	if ok:
		_proof_step += 1
	return ok

func visual_state() -> Dictionary:
	return _session.state()

func _consume(result: Dictionary, reason: String) -> bool:
	if not bool(result.get("success", false)):
		push_error("COMPLEX4-VIS1: %s" % result)
		return false
	_update_visuals(reason)
	return true

func _build_materials() -> void:
	_materials = {
		"frame": _mat(Color(0.30, 0.38, 0.48), false),
		"support": _mat(Color(0.22, 0.80, 0.42), true),
		"broken": _mat(Color(0.92, 0.12, 0.10), true),
		"path_a": _mat(Color(1.00, 0.72, 0.12), true),
		"path_b": _mat(Color(0.18, 0.82, 0.98), true),
		"path_off": _mat(Color(0.56, 0.12, 0.12), true),
		"source": _mat(Color(0.16, 0.26, 0.48), false),
		"floor": _mat(Color(0.10, 0.12, 0.15), false),
	}
	_lamp_material = _mat(Color(0.20, 0.20, 0.18), false)

func _build_world() -> void:
	var center_x := float(Fixture.PART_COUNT - 1) * SCALE_X * 0.5
	_make_box("Floor", Vector3(center_x, -0.85, 0), Vector3(31, 0.25, 9), _materials.floor)
	for i in range(Fixture.PART_COUNT - 1):
		var id := "bond/complex4/frame-%03d-%03d" % [i, i + 1]
		var special := id == Fixture.SUPPORT_A or id == Fixture.SUPPORT_B
		var node := _segment("Frame_%03d" % i, _pos(i), _pos(i + 1), 0.11 if special else 0.035, _materials.support if special else _materials.frame)
		if special: _supports[id] = node
	_bypass(53, 56); _bypass(107, 110)
	var source := _pos(0) + Vector3(-1, 1.3, 0)
	var load := _pos(Fixture.PART_COUNT - 1) + Vector3(1, 1.3, 0)
	_make_box("PowerSource", source, Vector3(1.4, 1, 1.4), _materials.source)
	_label3d("SOURCE 12 V", source + Vector3(0, 1, 0))
	var sphere := SphereMesh.new(); sphere.radius = 0.62; sphere.height = 1.24
	var lamp := MeshInstance3D.new(); lamp.name = "MachineLoad"; lamp.mesh = sphere; lamp.position = load; lamp.material_override = _lamp_material; add_child(lamp)
	_lamp_light = OmniLight3D.new(); _lamp_light.name = "MachineLoadLight"; _lamp_light.position = load; _lamp_light.omni_range = 7.5; add_child(_lamp_light)
	_label3d("FUNCTIONAL LOAD", load + Vector3(0, 1.1, 0))
	var a := _support_mid(Fixture.SUPPORT_A) + Vector3(0, 3, 2)
	var b := _support_mid(Fixture.SUPPORT_B) + Vector3(0, 3, -2)
	_paths[Fixture.POWER_A] = [_segment("PathA1", source, a, 0.075, _materials.path_a), _segment("PathA2", a, load, 0.075, _materials.path_a)]
	_paths[Fixture.POWER_B] = [_segment("PathB1", source, b, 0.075, _materials.path_b), _segment("PathB2", b, load, 0.075, _materials.path_b)]
	_label3d("PRIMARY PATH", a + Vector3(0, 0.7, 0)); _label3d("BACKUP PATH", b + Vector3(0, 0.7, 0))
	var env_node := WorldEnvironment.new(); var env := Environment.new(); env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.025, 0.035, 0.055); env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_energy = 0.8; env_node.environment = env; add_child(env_node)
	var camera := Camera3D.new(); camera.position = Vector3(center_x, 17.5, 30); camera.current = true; camera.fov = 58; add_child(camera); camera.look_at_from_position(camera.position, Vector3(center_x, 0.9, 0), Vector3.UP)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-48, -28, 0); sun.light_energy = 1.5; sun.shadow_enabled = true; add_child(sun)

func _build_hud() -> void:
	var layer := CanvasLayer.new(); add_child(layer)
	_hud = Label.new(); _hud.position = Vector2(18, 18); _hud.size = Vector2(860, 350); _hud.add_theme_font_size_override("font_size", 16); layer.add_child(_hud)
	_events = Label.new(); _events.position = Vector2(18, 360); _events.size = Vector2(860, 220); _events.add_theme_font_size_override("font_size", 14); layer.add_child(_events)

func _update_visuals(reason: String) -> void:
	var s := visual_state()
	_set_support(Fixture.SUPPORT_A, s.support_a_state != "BROKEN")
	_set_support(Fixture.SUPPORT_B, s.support_b_state != "BROKEN")
	_set_path(Fixture.POWER_A, s.active_power_link_ids.has(Fixture.POWER_A), _materials.path_a)
	_set_path(Fixture.POWER_B, s.active_power_link_ids.has(Fixture.POWER_B), _materials.path_b)
	_set_lamp(s.machine_state == "ON")
	_hud.text = "\n".join(PackedStringArray([
		"COMPLEX4-VIS1 — Playable Physical Lab", reason, "",
		"canonical revision: %d   build: %s" % [s.revision, s.build_state],
		"FABRIC mode: %s   canonical writes: %d" % [s.mode, s.canonical_writes],
		"machine: %s   load: %.3f W   active paths: %s" % [s.machine_state, s.load_power_w, str(s.active_power_link_ids)],
		"support A: %s   support B: %s   pending: %s" % [s.support_a_state, s.support_b_state, "none" if String(s.pending_support_id).is_empty() else String(s.pending_support_id)],
		"", "SPACE next proof step | 1 primary now | 2 backup now | N restart | R reset",
		"Proof: proposal != canonical write; first break keeps ON; second break turns OFF.",
	]))
	_events.text = "Recent events:\n- " + "\n- ".join(PackedStringArray(_session.event_log))
	set_meta("complex4_vis1_revision", s.revision); set_meta("complex4_vis1_mode", s.mode); set_meta("complex4_vis1_machine_state", s.machine_state); set_meta("complex4_vis1_load_power_w", s.load_power_w); set_meta("complex4_vis1_active_paths", Array(s.active_power_link_ids).duplicate()); set_meta("complex4_vis1_canonical_writes", s.canonical_writes)

func _set_support(id: String, intact: bool) -> void:
	var n: MeshInstance3D = _supports[id]; n.material_override = _materials.support if intact else _materials.broken; n.scale = Vector3.ONE if intact else Vector3(1, 0.55, 1)
func _set_path(id: String, active: bool, mat: Material) -> void:
	for n in _paths[id]: n.material_override = mat if active else _materials.path_off
func _set_lamp(on: bool) -> void:
	_lamp_material.emission_enabled = on; _lamp_material.emission = Color(1, 0.83, 0.24); _lamp_material.emission_energy_multiplier = 4.5 if on else 0.0; _lamp_material.albedo_color = Color(1, 0.76, 0.16) if on else Color(0.20, 0.20, 0.18); _lamp_light.visible = on; _lamp_light.light_energy = 2.2 if on else 0.0
func _pos(i: int) -> Vector3: return Vector3(float(i) * SCALE_X, 0, 0)
func _support_mid(id: String) -> Vector3:
	var b := Fixture.bond(Fixture.initial_snapshot(), id); return (_pos(int(String(b.part_a_id).get_slice("/", 2))) + _pos(int(String(b.part_b_id).get_slice("/", 2)))) * 0.5
func _bypass(a: int, b: int) -> void:
	var m := (_pos(a) + _pos(b)) * 0.5 + Vector3(0, 1, 0); _segment("BypassL", _pos(a), m, 0.045, _materials.frame); _segment("BypassR", m, _pos(b), 0.045, _materials.frame)
func _mat(c: Color, e: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.roughness = 0.55; m.emission_enabled = e; m.emission = c; m.emission_energy_multiplier = 1.8 if e else 0.0; return m
func _make_box(name_value: String, p: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new(); mesh.size = size; var n := MeshInstance3D.new(); n.name = name_value; n.mesh = mesh; n.position = p; n.material_override = mat; add_child(n); return n
func _label3d(text_value: String, p: Vector3) -> void:
	var l := Label3D.new(); l.text = text_value; l.position = p; l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.font_size = 24; l.outline_size = 5; add_child(l)
func _segment(name_value: String, a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var d := b - a; var mesh := CylinderMesh.new(); mesh.top_radius = r; mesh.bottom_radius = r; mesh.height = maxf(d.length(), 0.001); var y := d.normalized() if d.length() > 1.0e-9 else Vector3.UP; var h := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT; var x := h.cross(y).normalized(); var z := x.cross(y).normalized(); var n := MeshInstance3D.new(); n.name = name_value; n.mesh = mesh; n.material_override = mat; n.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5); add_child(n); return n
