extends Node2D

const Bridge = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_canonical_bridge_v1.gd")
const Fixture = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_fixture_v1.gd")
const STEP_S := 0.005
var paused := true
var bridge = Bridge.new()
var authority: Dictionary = {}
var last_result: Dictionary = {}
var _snapshot: Dictionary = {}
var _inspector: Label
var _play: Button
var _accumulator := 0.0

func _ready() -> void:
	var sources := Fixture.create()
	authority = Fixture.authority(sources)
	last_result = bridge.initialize(sources, authority)
	var title := Label.new()
	title.text = "COMPOSITION-R3 · Связанный физический механизм"
	title.position = Vector2(24, 16)
	title.add_theme_font_size_override("font_size", 24)
	add_child(title)
	var help := Label.new()
	help.text = "Space — пауза/пуск · N — один шаг · B — FULL/BAKE\nРазрыв выбирает solver. ConstructionStore подтверждает только полученный proposal."
	help.position = Vector2(24, 52)
	add_child(help)
	_play = _button("Пуск", Vector2(24, 112), toggle_pause)
	_button("Шаг", Vector2(136, 112), single_step)
	_button("FULL / BAKE", Vector2(248, 112), toggle_fidelity)
	_slider("Источник, V", Vector2(24, 174), -12.0, 12.0, 12.0, 0.25, func(value: float): set_input("source_voltage_v", value))
	_slider("Внешняя сила, N", Vector2(24, 224), -8.0, 8.0, 0.0, 0.25, func(value: float): set_input("external_force_n", value))
	_slider("Нагрузка, Ohm", Vector2(24, 274), 0.5, 15.0, 3.0, 0.25, set_load)
	_inspector = Label.new()
	_inspector.position = Vector2(660, 104)
	_inspector.add_theme_font_size_override("font_size", 15)
	add_child(_inspector)
	_refresh()

func _button(text: String, at: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = Vector2(104, 38)
	button.pressed.connect(callback)
	add_child(button)
	return button

func _slider(text: String, at: Vector2, low: float, high: float, initial: float, increment: float, callback: Callable) -> void:
	var label := Label.new()
	label.text = "%s: %.2f" % [text, initial]
	label.position = at
	add_child(label)
	var slider := HSlider.new()
	slider.position = at + Vector2(230, 4)
	slider.size = Vector2(340, 24)
	slider.min_value = low
	slider.max_value = high
	slider.step = increment
	slider.value = initial
	slider.value_changed.connect(func(value: float):
		callback.call(value)
		if last_result.get("success", false):
			label.text = "%s: %.2f" % [text, value]
		else:
			var canonical := bridge.sources()
			var accepted: float = initial
			if text == "Источник, V": accepted = canonical.mechanical.compiled_facets.composition_r3.source_voltage_v
			elif text == "Внешняя сила, N": accepted = canonical.mechanical.compiled_facets.composition_r3.external_force_n
			else:
				var result := Fixture.C.R2.compile_electrical(canonical.electrical, canonical.electrical_matter)
				for i in range(canonical.electrical.bonds.size()):
					if canonical.electrical.bonds[i].metadata.composition_r3_role == "LOAD_RESISTANCE": accepted = result.details.model.elements[i].resistance_ohm
			slider.set_value_no_signal(accepted)
	)
	add_child(slider)

func _process(delta: float) -> void:
	if paused: return
	_accumulator += minf(delta, 0.04)
	var ticks := 0
	while _accumulator >= STEP_S and ticks < 8:
		single_step()
		_accumulator -= STEP_S
		ticks += 1
		if not last_result.get("success", false):
			paused = true
			_play.text = "Пуск"
			_accumulator = 0.0
			break

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: toggle_pause()
			KEY_N: single_step()
			KEY_B: toggle_fidelity()

func toggle_pause() -> void:
	paused = not paused
	_accumulator = 0.0
	_play.text = "Пуск" if paused else "Пауза"

func single_step() -> void:
	var snapshot: Dictionary = bridge.inspect()
	if not snapshot.pending_proposal.is_empty():
		_issue("commit_failure", {"event_id": snapshot.pending_proposal.event_id})
	else:
		_issue("advance", {"dt_s": minf(STEP_S, snapshot.max_step_s)})

func toggle_fidelity() -> void:
	_issue("fidelity", {"target": "BAKE" if bridge.inspect().fidelity == "FULL" else "FULL", "certificate": {}})

func set_input(field: String, value: float) -> void:
	_issue("input", {"field": field, "value": value})

func set_load(resistance: float) -> void:
	_issue("load", {"resistance_ohm": resistance})

func _issue(action: String, payload: Dictionary) -> void:
	last_result = bridge.execute(bridge.make_command(action, payload, authority), authority)
	_refresh()

func _refresh() -> void:
	_snapshot = bridge.inspect()
	if _snapshot.is_empty(): return
	var s: Dictionary = _snapshot
	_inspector.text = ("t = %.6f s\nx = %.6f m\nv = %.6f m/s\nI = %.6f A\nF = %.6f N\nBack EMF = %.6f V\n\nKinetic = %.9f J\nElastic = %.9f J\nSource work = %.9f J\nExternal work = %.9f J\nJoule heat = %.9f J\nDamper heat = %.9f J\nFracture heat = %.9f J\nEnergy residual = %.12f J\nDAE constraint = %.12f V\n\nFidelity = %s / %s\nConstruction revisions = %d / %d\nOwner = %s, epoch = %d\nPending proposal = %s\nCommand = %s" % [s.time_s, s.displacement_m, s.velocity_m_per_s, s.current_a, s.actuator_force_n, s.back_emf_v, s.kinetic_j, s.elastic_j, s.source_work_j, s.external_work_j, s.joule_heat_j, s.damper_heat_j, s.fracture_heat_j, s.energy_residual_j, s.constraint_residual_v, s.fidelity, s.mode, s.mechanical_revision, s.electrical_revision, authority.execution_owner, Fixture.C.A.authority_epoch_for(authority, "CONSTRUCTION", bridge.sources().mechanical.construct_id), "YES" if not s.pending_proposal.is_empty() else "NO", "OK" if last_result.get("success", false) else last_result.get("error_code", "")])
	for support in s.supports:
		_inspector.text += "\n%s: %.3f / %.1f N%s" % [str(support.bond_id).get_file(), support.effort_n, support.capacity_n, " · BROKEN" if not support.active else ""]
	queue_redraw()

func observed_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)

func _draw() -> void:
	if _snapshot.is_empty(): return
	var x := 400.0 + float(_snapshot.displacement_m) * 500.0
	draw_line(Vector2(50, 505), Vector2(620, 505), Color(0.5, 0.6, 0.7), 3)
	draw_rect(Rect2(Vector2(x - 24, 365), Vector2(48, 138)), Color(0.35, 0.75, 0.85))
	for i in range(_snapshot.supports.size()):
		var y := 390.0 + i * 65.0
		var active: bool = _snapshot.supports[i].active
		draw_rect(Rect2(64, y - 18, 20, 36), Color(0.6, 0.65, 0.7))
		var points := PackedVector2Array()
		for j in range(15): points.append(Vector2(84 + (x - 108) * j / 14.0, y + (8.0 if j % 2 else -8.0)))
		if active: draw_polyline(points, Color(0.5, 0.9, 0.55), 3, true)
		else:
			draw_line(Vector2(84, y), Vector2(130, y), Color(0.95, 0.45, 0.35), 3)
			draw_line(Vector2(x - 64, y), Vector2(x - 24, y), Color(0.95, 0.45, 0.35), 3)
	draw_string(ThemeDB.fallback_font, Vector2(64, 552), "Пружины → ползун ↔ преобразователь ↔ электрическая цепь", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	draw_string(ThemeDB.fallback_font, Vector2(64, 579), "BAKE исключает I; динамические x/v сохраняются.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	draw_string(ThemeDB.fallback_font, Vector2(64, 606), "RESEARCH ONLY · Не production physics и не доказательство ускорения.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
