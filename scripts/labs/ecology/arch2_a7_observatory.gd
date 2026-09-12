extends Control
## Presentation-only controller. No RNG or ecological transitions inside the renderer.
const Model = preload("res://scripts/research/ecology/v2/observatory_session_v1.gd")
const Protocol = preload("res://scripts/research/ecology/v2/observatory_protocol_v1.gd")
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const BodyView = preload("res://scripts/labs/ecology/arch2_a7_body_view.gd")
var model := Model.new()
var running := false
var speed := 1.0
var elapsed := 0.0
var selected_site := "wet"
var selected_id := "study"
var report: Dictionary = {}
var status: Label
var inspector: TextEdit
var seed_choice: OptionButton
var common: CheckButton
var effects: CheckButton
var mutations: CheckButton
var play: Button
var panels: Dictionary = {}
var summaries: Dictionary = {}
const STORAGE := "res://artifacts/a7/observatory"

func _ready() -> void:
	name = "A7Observatory"
	get_window().min_size = Vector2i(1160, 820)
	get_window().size = Vector2i(1440, 960)
	get_window().content_scale_size = Vector2i(1440, 960)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var protocol := Protocol.manifest()
	if protocol.is_empty():
		status = Label.new()
		status.name = "Status"
		status.text = "PROTOCOL REJECTED: canonical A7-R1 digest/encoding mismatch"
		add_child(status)
		return
	var backdrop := ColorRect.new(); backdrop.color = Color("0b1420"); backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(backdrop)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 18)
	add_child(margin)
	var root := VBoxContainer.new(); root.add_theme_constant_override("separation", 10); margin.add_child(root)
	var title := Label.new(); title.text = "A7  /  ECOLOGY OBSERVATORY"; title.add_theme_font_size_override("font_size", 26); root.add_child(title)
	var subtitle := Label.new(); subtitle.text = "Три настоящих A6-эксперимента • одно начальное наследуемое правило • research only"; root.add_child(subtitle)
	var treatments := HBoxContainer.new(); root.add_child(treatments)
	seed_choice = OptionButton.new(); seed_choice.name = "SeedChoice"
	for seed in protocol.seeds: seed_choice.add_item("Seed " + str(seed))
	treatments.add_child(seed_choice)
	common = _toggle(treatments, "Common garden", false, "CommonGarden")
	effects = _toggle(treatments, "Feedback ON", true, "Effects")
	mutations = _toggle(treatments, "A3 founder mutation ON", true, "Mutations")
	_button(treatments, "Применить / RESET", "Reset", reset_experiment)
	var controls := HBoxContainer.new(); root.add_child(controls)
	play = _button(controls, "▶ Пуск", "Play", toggle_play)
	_button(controls, "+1 tick", "Step", step_once)
	var speeds := OptionButton.new(); speeds.name = "Speed"
	for value in ["1×", "2×", "4×"]: speeds.add_item(value)
	speeds.item_selected.connect(func(i: int): speed = float([1, 2, 4][i])); controls.add_child(speeds)
	_button(controls, "Сохранить", "Save", save_checkpoint)
	_button(controls, "Восстановить", "Load", load_checkpoint)
	_button(controls, "Экспорт JSON", "Export", export_current)
	var site_choice := OptionButton.new(); site_choice.name = "SiteChoice"
	for site in Protocol.SITES: site_choice.add_item(site)
	site_choice.item_selected.connect(func(i: int): select(Protocol.SITES[i], selected_id)); controls.add_child(site_choice)
	var individual_choice := OptionButton.new(); individual_choice.name = "IndividualChoice"
	individual_choice.add_item("study"); individual_choice.add_item("litter-donor")
	individual_choice.item_selected.connect(func(i: int): select(selected_site, ["study", "litter-donor"][i])); controls.add_child(individual_choice)
	status = Label.new(); status.name = "Status"; status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; root.add_child(status)
	var row := HBoxContainer.new(); row.size_flags_vertical = Control.SIZE_EXPAND_FILL; root.add_child(row)
	for site in Protocol.SITES:
		var card := VBoxContainer.new(); card.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(card)
		var heading := Label.new(); heading.text = site.to_upper(); heading.add_theme_font_size_override("font_size", 20); card.add_child(heading)
		var view := BodyView.new(); view.name = site + "Body"; view.custom_minimum_size = Vector2(340, 325); view.clip_contents = true
		view.size_flags_horizontal = Control.SIZE_EXPAND_FILL; view.size_flags_vertical = Control.SIZE_EXPAND_FILL; card.add_child(view); panels[site] = view
		view.resized.connect(sync_projection)
		var summary := Label.new(); summary.name = site + "Summary"; summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; summary.custom_minimum_size.y = 100; card.add_child(summary); summaries[site] = summary
	var legend := Label.new(); legend.text = "Общий масштаб: сетка 10 mm. Круг collector = площадь; absorber = reach. Серое тело — архив, не расходуемый остаток."; legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; root.add_child(legend)
	inspector = TextEdit.new(); inspector.name = "Inspector"; inspector.editable = false; inspector.custom_minimum_size.y = 210; inspector.add_theme_font_size_override("font_size", 13); inspector.add_theme_color_override("font_readonly_color", Color("d2dde8")); root.add_child(inspector)
	reset_experiment()

func _button(parent: Node, text: String, node_name: String, action: Callable) -> Button:
	var button := Button.new(); button.text = text; button.name = node_name; button.pressed.connect(action); parent.add_child(button); return button

func _toggle(parent: Node, text: String, on: bool, node_name: String) -> CheckButton:
	var b := CheckButton.new(); b.text = text; b.name = node_name; b.button_pressed = on; parent.add_child(b); return b

func _process(delta: float) -> void:
	if not running: return
	elapsed += delta * speed
	if elapsed >= 1.0:
		elapsed = 0.0 # No catch-up bursts and no altered ecological tick size.
		_step()

func toggle_play() -> void:
	running = not running
	elapsed = 0.0
	play.text = "⏸ Пауза" if running else "▶ Пуск"

func step_once() -> void:
	running = false
	play.text = "▶ Пуск"
	_step()

func _step() -> void:
	if not model.advance():
		running = false; play.text = "▶ Пуск"
		status.text = "STOP: " + model.last_error + " — состояние сохранено; это не биологическая смерть."
		return
	refresh()

func reset_experiment() -> void:
	running = false; elapsed = 0; play.text = "▶ Пуск"
	var protocol := Protocol.manifest()
	if protocol.is_empty():
		status.text = "PROTOCOL REJECTED: reset did not change the experiment"
		return
	var seeds: Array = protocol.seeds
	if not model.start(Protocol.treatment(seeds[seed_choice.selected], common.button_pressed, effects.button_pressed, mutations.button_pressed)):
		status.text = "RESET FAILED: " + model.last_error; return
	refresh()

func select(site: String, individual: String) -> void:
	if not site in Protocol.SITES or not individual in ["study", "litter-donor"]: return
	selected_site = site; selected_id = individual; refresh()

func sync_projection() -> void:
	if panels.is_empty(): return
	var canvas: Vector2 = panels.wet.size
	for site in Protocol.SITES:
		canvas.x = minf(canvas.x, panels[site].size.x)
		canvas.y = minf(canvas.y, panels[site].size.y)
	for site in Protocol.SITES:
		panels[site].common_canvas_size = canvas
		panels[site].queue_redraw()

func refresh() -> void:
	report = model.observe()
	if not report.success: status.text = "OBSERVATION FAILED: " + str(report.get("error")); return
	var t: Dictionary = report.treatment
	status.text = "Tick %d / %d | seed %d | common-garden=%s  feedback=%s  founder-mutation=%s | experiment %s" % [report.step, report.horizon, t.seed, t.common_garden, t.effects_enabled, t.mutations_enabled, report.experiment_hash.substr(0, 12)]
	sync_projection()
	for site in report.sites:
		panels[site.id].present(site, selected_id, panels[site.id].common_canvas_size)
		var selected: Dictionary = {}
		for entry in site.entries:
			if entry.id == selected_id: selected = entry
		var cell: Dictionary = site.field.cells[0]
		summaries[site.id].text = "%s | alive=%s | modules=%d | births=%d\nWater %d  Organic %d  Nutrient %d mg | light %d/1000\nReturned organic %d mg | outbox %d | source %s" % [selected.id, selected.alive, selected.phenotype.statistics.module_count, selected.reproduction_count, cell.stocks.water_mg, cell.stocks.organic_mg, cell.stocks.nutrient_mg, cell.signals.light, site.returned.organic_mg, site.pending_propagules, site.source_hash.substr(0, 10)]
		if site.id == selected_site:
			inspector.text = "INSPECTOR %s / %s | genotype %s | body %s\nFounder mutation only; paid births remain in A6 outbox.\n\n" % [site.id, selected.id, selected.phenotype.genome_hash, selected.phenotype.body_hash] + JSON.stringify({"site": site.id, "individual": selected, "balance": site.balance, "corpses": site.corpses, "founder_mutation": report.founder_mutation, "scope": report.scope}, "  ")

func save_checkpoint() -> void:
	var text := model.save_text()
	if text.is_empty(): status.text = "SAVE FAILED: invalid source"; return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STORAGE))
	var digest := text.sha256_text()
	var file := FileAccess.open(STORAGE + "/" + digest + ".json", FileAccess.WRITE)
	if file == null: status.text = "SAVE FAILED: file open"; return
	file.store_string(text); file.flush()
	if file.get_error() != OK: status.text = "SAVE FAILED: write"; return
	file.close()
	var anchor := {"schema": "dws.ecology.a7-local-manifest.v1", "experiment_hash": model.experiment_hash(), "step": model.step_index(), "snapshot_sha256": digest}
	file = FileAccess.open(STORAGE + "/manifest.json", FileAccess.WRITE)
	if file == null: status.text = "SAVE FAILED: manifest"; return
	file.store_string(C.encode(anchor)); file.flush()
	if file.get_error() != OK: status.text = "SAVE FAILED: manifest write"; return
	file.close()
	status.text = "SAVED tick %d → artifacts/a7/observatory (caller-owned manifest)" % model.step_index()

func load_checkpoint() -> void:
	running = false; play.text = "▶ Пуск"
	var path := STORAGE + "/manifest.json"
	if not FileAccess.file_exists(path): status.text = "LOAD FAILED: no external manifest"; return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 1024: status.text = "LOAD FAILED: manifest bound"; return
	var parsed := C.decode(file.get_as_text()); file.close()
	if not parsed.success or not C.keys(parsed.value, ["schema", "experiment_hash", "step", "snapshot_sha256"]): status.text = "LOAD FAILED: manifest"; return
	var a: Dictionary = parsed.value
	if a.schema != "dws.ecology.a7-local-manifest.v1" or a.experiment_hash != model.experiment_hash() or not Model.F.valid_hash(a.snapshot_sha256):
		status.text = "LOAD FAILED: select the saved treatment, then RESET first"; return
	path = STORAGE + "/" + a.snapshot_sha256 + ".json"
	if not FileAccess.file_exists(path): status.text = "LOAD FAILED: snapshot missing"; return
	file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > C.MAX_BYTES: status.text = "LOAD FAILED: snapshot bound"; return
	var text := file.get_as_text(); file.close()
	if text.sha256_text() != a.snapshot_sha256 or not C.integer(a.step, 0, 16): status.text = "LOAD FAILED: snapshot hash/step"; return
	if not model.load_text(text, a.experiment_hash, a.step): status.text = "LOAD FAILED: " + model.last_error; return
	refresh()

func export_current() -> void:
	var text := model.export_report()
	if text.is_empty(): status.text = "EXPORT FAILED"; return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/a7"))
	var file := FileAccess.open("res://artifacts/a7/observatory-report.json", FileAccess.WRITE)
	if file == null: status.text = "EXPORT FAILED: open"; return
	file.store_string(text); file.flush()
	status.text = "EXPORTED source-bound report → artifacts/a7/observatory-report.json" if file.get_error() == OK else "EXPORT FAILED: write"
	file.close()
