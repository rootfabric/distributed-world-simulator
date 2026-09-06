extends Control
const Model = preload("res://scripts/labs/ecology/evo_morphology_lab_v2_model.gd")
const Renderer = preload("res://scripts/labs/ecology/evo_morphology_lab_v2_renderer.gd")
const Fixtures = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")
var model := Model.new()
var status: Label
var renderer: Control
var editor: TextEdit

func _ready() -> void:
	var root := VBoxContainer.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(root)
	var toolbar := HBoxContainer.new(); root.add_child(toolbar)
	for i in Fixtures.NAMES.size():
		var b := Button.new(); b.text = str(i + 1); b.tooltip_text = Fixtures.NAMES[i]; b.pressed.connect(func(): model.reset(i); _refresh()); toolbar.add_child(b)
	for spec in [["STEP", "step"], ["SMALL", "small"], ["STRUCT", "insert"], ["DUP", "duplicate"], ["GENERATE 100", "gallery"]]:
		var b := Button.new(); b.text = spec[0]; b.pressed.connect(_action.bind(spec[1])); toolbar.add_child(b)
	status = Label.new(); root.add_child(status)
	var split := HSplitContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; root.add_child(split)
	renderer = Renderer.new(); renderer.custom_minimum_size = Vector2(620, 420); renderer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; split.add_child(renderer)
	editor = TextEdit.new(); editor.custom_minimum_size = Vector2(420, 420); editor.text = model.export_genome(); split.add_child(editor)
	var apply := Button.new(); apply.text = "IMPORT EDITED GENOME"; apply.pressed.connect(func(): status.text = "IMPORT=" + str(model.import_genome(editor.text)); _refresh()); root.add_child(apply)
	_refresh()

func _action(kind: String) -> void:
	match kind:
		"step": model.step()
		"gallery": model.generate(100, 20260906)
		_: model.mutate(kind, 20260906 + model.generation)
	_refresh()

func _refresh() -> void:
	var p := model.phenotype(); renderer.set_phenotype(p)
	var h := model.hashes(); var dry := model.environment_preview(250, 800); var dark := model.environment_preview(650, 180)
	var family_label: String = "IMPORTED" if model.family == Model.IMPORTED_FAMILY else String(Fixtures.NAMES[model.family])
	var block_label: String = "" if model.last_block_reason.is_empty() else " block=" + model.last_block_reason
	status.text = "family=%s generation=%d status=%s%s modules=%d topology=%s dry=%s dark=%s gallery=%d" % [family_label, model.generation, model.last_status, block_label, int(p.get("statistics", {}).get("module_count", 0)), String(h.topology).substr(0, 12), String(dry.get("phenotype_hash", "")).substr(0, 8), String(dark.get("phenotype_hash", "")).substr(0, 8), model.gallery.size()]
	editor.text = model.export_genome()
