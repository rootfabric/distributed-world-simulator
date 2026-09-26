extends Node3D
## A11 composition root. Workbench is the ONLY tick driver; Session transports
## its existing checkpoint. Meshes, controls and labels are derived views only.
const Session = preload("res://scripts/ecology/habitat/persistent_habitat_session_v1.gd")
const Preset = preload("res://scripts/ecology/habitat/habitat_preset_v1.gd")
const WorkbenchScene = preload("res://scenes/ecology/workbench/ecology_workbench.tscn")
const Inspector = preload("res://scripts/ecology/workbench/organism_inspector_v1.gd")

@export var auto_boot := true
@export var autosave_enabled := true
var save_directory := "user://eco-a11/checkpoints"
var session: Object = Session.new()
var workbench: Node = null
var last_receipt: Dictionary = {}
var last_error := ""
var _last_saved_tick := -1
var _saving := false
var _world: Node3D = null
var _info: Label = null
var _status: Label = null
var _inspector: Label = null
var _entities: OptionButton = null
var _path: LineEdit = null
var _anchor: LineEdit = null
var _panel: PanelContainer = null
var _advanced_toggle: CheckBox = null
var _selected_id := ""

func _ready() -> void:
	name = "PersistentEvolvingHabitat"
	_build_controls()
	if auto_boot:
		boot(OS.get_cmdline_user_args())

## No automatic fallback to new state when a requested restore is invalid.
func boot(arguments: PackedStringArray) -> Dictionary:
	var path := ""
	var anchor := ""
	var supplied := {}
	for argument in arguments:
		if argument.begins_with("--eco-habitat-save="):
			if supplied.has("path"):
				return _failure("HABITAT_DUPLICATE_RESTORE_PATH")
			supplied.path = true
			path = argument.trim_prefix("--eco-habitat-save=")
		elif argument.begins_with("--eco-habitat-sha="):
			if supplied.has("anchor"):
				return _failure("HABITAT_DUPLICATE_RESTORE_ANCHOR")
			supplied.anchor = true
			anchor = argument.trim_prefix("--eco-habitat-sha=")
	if not supplied.is_empty():
		if path.is_empty() or anchor.is_empty():
			return _failure("HABITAT_RESTORE_PATH_AND_EXTERNAL_SHA_REQUIRED")
		return restore_checkpoint(path, anchor)
	return new_habitat(Preset.create())

func new_habitat(manifest: Dictionary) -> Dictionary:
	_stop_playback()
	var result: Dictionary = session.start(manifest)
	if not bool(result.get("success", false)):
		return _failure(String(result.get("error", "HABITAT_START")))
	last_receipt = {}
	_last_saved_tick = -1
	_bind_workbench()
	_set_status("Новая сессия. Пауза. FREE; seed %d." % int(manifest.seed))
	return result

func save_checkpoint() -> Dictionary:
	if workbench == null or session.controller == null:
		return _failure("HABITAT_NOT_STARTED")
	# The Workbench may have explicitly forked or registered founder variants.
	var adopted: Dictionary = session.adopt(workbench.controller, workbench.founder_registry)
	if not bool(adopted.get("success", false)):
		return _failure(String(adopted.get("error", "HABITAT_ADOPT")))
	_saving = true
	var saved: Dictionary = session.save(save_directory)
	_saving = false
	if not bool(saved.get("success", false)):
		_stop_playback()
		return _failure(String(saved.get("error", "HABITAT_SAVE")))
	last_receipt = saved.duplicate(true)
	_last_saved_tick = int(saved.tick)
	_path.text = String(saved.path)
	_anchor.text = String(saved.sha256)
	_set_status("Сохранено: tick %d. SHA храните отдельно от файла." % int(saved.tick))
	print("ECO_A11_SAVE_RECEIPT " + JSON.stringify(saved))
	return saved

func restore_checkpoint(path: String, expected_sha256: String) -> Dictionary:
	_stop_playback()
	# The default visible research host is LAB. WORLD_COMPAT restore is exposed
	# by Session only with explicit fresh caller-owned world dependencies.
	var loaded: Dictionary = session.load_file(path, expected_sha256)
	if not bool(loaded.get("success", false)):
		return _failure(String(loaded.get("error", "HABITAT_RESTORE")))
	last_receipt = {"path": path, "sha256": expected_sha256, "tick": loaded.tick}
	_last_saved_tick = int(loaded.tick)
	_bind_workbench()
	_path.text = path
	_anchor.text = expected_sha256
	_set_status("Восстановлено: tick %d. Продолжение той же истории; пауза." % int(loaded.tick))
	return loaded

func _bind_workbench() -> void:
	if workbench == null:
		workbench = WorkbenchScene.instantiate()
		add_child(workbench)
		workbench.snapshot_updated.connect(_on_snapshot)
		# Keep the accepted advanced tools available without overlaying the
		# default habitat UI. They still operate on this same controller.
		var advanced := workbench.get_node("WorkbenchUI") as CanvasLayer
		advanced.visible = false
	workbench.setup({"controller": session.controller,
		"founder_registry": session.founder_registry, "zone_color_provider": zone_color})
	_build_world(session.controller.get_manifest())
	last_error = ""
	_on_snapshot(session.controller.get_snapshot())

func _on_snapshot(snapshot: Dictionary) -> void:
	if not bool(snapshot.get("success", false)) or workbench == null:
		return
	if workbench.controller != session.controller:
		var adopted: Dictionary = session.adopt(workbench.controller, workbench.founder_registry)
		if not bool(adopted.get("success", false)):
			_stop_playback()
			_show_error(String(adopted.get("error", "HABITAT_ADOPT")))
			return
		_last_saved_tick = -1
	var current_tick := int(snapshot.tick)
	if current_tick < _last_saved_tick:
		_last_saved_tick = -1
	var metrics: Dictionary = session.controller.get_metrics()
	var manifest: Dictionary = session.controller.get_manifest()
	var generation := 0
	_entities.clear()
	for view in snapshot.presentation:
		generation = maxi(generation, int(view.lineage_depth))
		_entities.add_item(String(view.individual_id))
		if String(view.individual_id) == _selected_id:
			_entities.select(_entities.item_count - 1)
	_info.text = "Такт %d / %d\nЖивых %d / всего %d · поколение %d\nSeed %d · %s · %s\nСостояние %s\nПределы модели: 128 особей / 128 останков.\nПредел — остановка с ошибкой, не скрытое удаление." % [
		current_tick, int(manifest.horizon_ticks), int(metrics.get("alive", 0)),
		int(metrics.get("population_size", 0)), generation, int(manifest.seed),
		String(manifest.organization_profile), String(manifest.mode),
		String(snapshot.canonical_state_hash).substr(0, 16)]
	_render_selection()
	if current_tick >= int(manifest.horizon_ticks):
		_stop_playback()
		_set_status("Достигнут объявленный горизонт. Сохраните результат или начните новый опыт.")
	var interval := int(manifest.checkpoint.interval_ticks)
	if autosave_enabled and not _saving and interval > 0 and current_tick > 0 \
			and current_tick % interval == 0 and current_tick != _last_saved_tick:
		save_checkpoint()

func _process(_delta: float) -> void:
	# Observation only: no simulation step or wall-clock -> biology conversion.
	if workbench != null and workbench.controller != null \
			and workbench.controller.status() == "FAILED":
		_stop_playback()
		var error: String = workbench.controller.last_error()
		if error != last_error:
			_show_error(error)

func _stop_playback() -> void:
	if workbench != null:
		workbench.running = false
		workbench.pending_target = {}

func _run() -> void:
	if workbench != null:
		workbench.command_run()

func _pause() -> void:
	if workbench != null:
		workbench.command_pause()

func _step() -> void:
	if workbench != null and not workbench.command_step():
		_show_error("Шаг отклонён: проверьте горизонт и статус canonical controller.")

func _fast() -> void:
	if workbench != null:
		workbench.command_fast()

func show_advanced_tools(visible: bool) -> bool:
	if workbench == null or _panel == null:
		if _advanced_toggle != null:
			_advanced_toggle.set_pressed_no_signal(false)
		return false
	var layer := workbench.get_node("WorkbenchUI") as CanvasLayer
	layer.visible = visible
	_panel.visible = not visible
	_advanced_toggle.set_pressed_no_signal(visible)
	return true

func _render_selection() -> void:
	if session.controller == null or _selected_id.is_empty():
		_inspector.text = "Выберите организм: геном, тело, ресурсы и lineage берутся из canonical state."
		return
	var inspected: Dictionary = Inspector.compile(session.controller, _selected_id)
	_inspector.text = Inspector.render_text(inspected.view) if bool(inspected.get("success", false)) else String(inspected.get("error", "?"))

func zone_color(position_mm: Array) -> Color:
	var colors := [Color(0.18, 0.55, 0.78), Color(0.78, 0.55, 0.21), Color(0.42, 0.31, 0.62)]
	if session.controller == null:
		return colors[0]
	var manifest: Dictionary = session.controller.get_manifest()
	var spatial: Dictionary = manifest.environment.spatial
	var x := int((int(position_mm[0]) - int(spatial.origin_mm[0])) / int(spatial.cell_size_mm))
	return colors[clampi(x, 0, colors.size() - 1)]

func _build_world(manifest: Dictionary) -> void:
	if _world != null:
		remove_child(_world)
		_world.queue_free()
	_world = Node3D.new()
	_world.name = "HabitatPresentation"
	add_child(_world)
	var spatial: Dictionary = manifest.environment.spatial
	var size := float(spatial.cell_size_mm) / 100.0
	var width := float(spatial.width) * size
	var depth := float(spatial.depth) * size
	var origin := Vector3(float(spatial.origin_mm[0]), float(spatial.origin_mm[1]), float(spatial.origin_mm[2])) / 100.0
	var camera := Camera3D.new()
	camera.position = origin + Vector3(width * 0.15, 23.0, depth + 30.0)
	_world.add_child(camera)
	camera.look_at(origin + Vector3(width * 0.15, 0.0, depth * 0.5))
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	light.light_energy = 1.4
	_world.add_child(light)
	var zones: Array = manifest.environment.zones
	var total := int(spatial.width) * int(spatial.depth)
	for index in total:
		var zone: Dictionary = zones[mini(zones.size() - 1, index * zones.size() / total)]
		var center := origin + Vector3((index % int(spatial.width) + 0.5) * size, -0.03, (int(index / int(spatial.width)) + 0.5) * size)
		var ground := MeshInstance3D.new()
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(size * 0.98, size * 0.98)
		ground.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = zone_color([int(center.x * 100.0), 0, int(center.z * 100.0)])
		ground.material_override = material
		ground.position = center
		_world.add_child(ground)
		var label := Label3D.new()
		label.text = String(zone.id).to_upper()
		label.font_size = 40
		label.position = center + Vector3(0, 0.5, size * 0.35)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_world.add_child(label)

func _build_controls() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HabitatUI"
	add_child(canvas)
	_panel = PanelContainer.new()
	_panel.name = "HabitatPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_panel.offset_left = 16
	_panel.offset_right = 376
	_panel.offset_top = 16
	_panel.offset_bottom = -16
	canvas.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	_label(box, "ECO A11 · ЖИВОЙ HABITAT", 20)
	_label(box, "Одна canonical ecology · persistent research scene", 13)
	_info = _label(box, "Сессия не запущена", 14)
	var controls := HFlowContainer.new()
	box.add_child(controls)
	_button(controls, "Пуск", _run)
	_button(controls, "Пауза", _pause)
	_button(controls, "Шаг", _step)
	_button(controls, "Быстро", _fast)
	_button(box, "Новый опыт FREE (явный сброс)", func(): new_habitat(Preset.create()))
	var morphology := CheckBox.new()
	morphology.text = "Generic morphology"
	morphology.button_pressed = true
	morphology.toggled.connect(func(value: bool):
		if workbench != null: workbench.set_morphology_enabled(value))
	box.add_child(morphology)
	var auto_save := CheckBox.new()
	auto_save.text = "Автосохранение по interval_ticks"
	auto_save.button_pressed = autosave_enabled
	auto_save.toggled.connect(func(value: bool): autosave_enabled = value)
	box.add_child(auto_save)
	_button(box, "Сохранить на диск", func(): save_checkpoint())
	_path = LineEdit.new()
	_path.placeholder_text = "Путь к .eco.json"
	box.add_child(_path)
	_anchor = LineEdit.new()
	_anchor.placeholder_text = "Внешний доверенный SHA-256"
	box.add_child(_anchor)
	_button(box, "Восстановить по пути + SHA", func(): restore_checkpoint(_path.text, _anchor.text))
	_status = _label(box, "Пауза. Сохранение не меняет biological state.", 13)
	_entities = OptionButton.new()
	_entities.item_selected.connect(func(index: int):
		_selected_id = _entities.get_item_text(index)
		if workbench != null: workbench.select_entity(_selected_id)
		_render_selection())
	box.add_child(_entities)
	_inspector = _label(box, "", 12)
	_advanced_toggle = CheckBox.new()
	_advanced_toggle.name = "AdvancedToolsToggle"
	_advanced_toggle.text = "Показать исходные инструменты Polygon"
	_advanced_toggle.toggled.connect(show_advanced_tools)
	box.add_child(_advanced_toggle)
	_label(box, "F2 — вернуться из Polygon.\nМодель ограничена, это не production ecology authority.", 12)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		show_advanced_tools(false)

func _button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)

func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _set_status(text: String) -> void:
	last_error = ""
	if _status != null: _status.text = text

func _show_error(error: String) -> void:
	last_error = error
	if _status != null: _status.text = "ОСТАНОВЛЕНО: " + error
	push_error("ECO_A11_HOST " + error)

func _failure(error: String) -> Dictionary:
	_show_error(error)
	return {"success": false, "error": error}
