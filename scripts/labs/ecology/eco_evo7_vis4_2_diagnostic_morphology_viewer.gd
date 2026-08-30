extends Node

## ECO.EVO7 VIS4.2 — Honest Diagnostic Morphology Viewer.
##
## This is a diagnostic-only presentation surface. It reads public Workbench
## snapshots, asks VIS4.1 Descriptor V2 for a sealed morphology view, then passes
## that result through the pure VIS4.2 mapper/overlay. It never calls biology.

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")
const DescriptorV2 = preload("res://scripts/labs/ecology/eco_evo7_vis4_morphology_render_adapter.gd")
const DiagnosticMapper = preload("res://scripts/labs/ecology/eco_evo7_vis4_2_diagnostic_morphology_mapper.gd")
const DiagnosticOverlay = preload("res://scripts/labs/ecology/eco_evo7_vis4_2_diagnostic_morphology_overlay.gd")

const VIEWER_TITLE := "ECO EVO7 — VIS4.2 Honest Diagnostic Morphology"
const RUNTIME_REVISION := "ECO.EVO7-VIS4.2.R1"

@export var auto_initialize := true

var workbench = null
var world_source = null
var owns_world_source := false
var descriptor_adapter = DescriptorV2.new()
var diagnostic_mapper = DiagnosticMapper.new()
var source_descriptor_snapshot: Dictionary = {}
var diagnostic_snapshot: Dictionary = {}

var ui_root: Control
var overlay = null
var status_label: Label
var details_label: RichTextLabel
var neutral_toggle: CheckButton
var step_button: Button

func _ready() -> void:
	ensure_ui_built()
	DisplayServer.window_set_title(VIEWER_TITLE)
	if auto_initialize:
		initialize_runtime()

func ensure_ui_built() -> void:
	if ui_root != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "VIS42UI"
	add_child(layer)

	ui_root = Control.new()
	ui_root.name = "Root"
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui_root)
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.name = "Background"
	background.color = Color(0.055, 0.065, 0.055, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root_box := VBoxContainer.new()
	root_box.name = "Layout"
	root_box.add_theme_constant_override("separation", 8)
	margin.add_child(root_box)

	var top := HBoxContainer.new()
	top.name = "Top"
	top.add_theme_constant_override("separation", 12)
	root_box.add_child(top)

	var title := Label.new()
	title.name = "Title"
	title.text = VIEWER_TITLE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	top.add_child(title)

	step_button = Button.new()
	step_button.name = "Step"
	step_button.text = "+1 generation"
	step_button.pressed.connect(_on_step_pressed)
	top.add_child(step_button)

	neutral_toggle = CheckButton.new()
	neutral_toggle.name = "NeutralColor"
	neutral_toggle.text = "Neutral color"
	neutral_toggle.button_pressed = true
	neutral_toggle.toggled.connect(_on_neutral_toggled)
	top.add_child(neutral_toggle)

	var body := HSplitContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.split_offset = 780
	root_box.add_child(body)

	var viewport_panel := PanelContainer.new()
	viewport_panel.name = "MorphologyViewport"
	viewport_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(viewport_panel)

	overlay = DiagnosticOverlay.new()
	overlay.name = "DiagnosticMorphologyOverlay"
	overlay.custom_minimum_size = Vector2(720.0, 640.0)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_panel.add_child(overlay)

	details_label = RichTextLabel.new()
	details_label.name = "Details"
	details_label.bbcode_enabled = true
	details_label.fit_content = false
	details_label.custom_minimum_size = Vector2(330.0, 320.0)
	details_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(details_label)

	status_label = Label.new()
	status_label.name = "Status"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(status_label)

func initialize_runtime(source = null) -> bool:
	ensure_ui_built()
	_release_owned_world()
	world_source = source
	if world_source == null:
		world_source = EarthWorld.new()
		owns_world_source = true
		add_child(world_source)
		if not world_source.setup(null):
			_release_owned_world()
			return false
	workbench = Workbench.new()
	if not workbench.setup(world_source):
		workbench = null
		_release_owned_world()
		return false
	return _refresh()

func manual_step(count: int = 1) -> bool:
	if workbench == null or count < 1:
		return false
	var advanced: Dictionary = workbench.advance_generations(count)
	if advanced.is_empty():
		return false
	return _refresh()

func set_neutral_color(value: bool) -> bool:
	if overlay == null:
		return false
	overlay.set_neutral_color(value)
	if neutral_toggle != null:
		neutral_toggle.set_pressed_no_signal(value)
	_refresh_details()
	return true

func set_camera_state(zoom_value: float, pan_value: Vector2) -> bool:
	return overlay != null and overlay.set_camera_state(zoom_value, pan_value)

func select_record(record_id: String) -> bool:
	if overlay == null or not overlay.set_selected_record(record_id):
		return false
	_refresh_details(record_id)
	return true

func get_runtime_identity() -> Dictionary:
	return {
		"scene_name": String(name),
		"viewer_title": VIEWER_TITLE,
		"revision": RUNTIME_REVISION,
	}

func get_ui_contract() -> Dictionary:
	return {
		"descriptor_v2_only": true,
		"honest_realized_crown": true,
		"honest_realized_density": true,
		"branch_silhouette": true,
		"neutral_color_mode": neutral_toggle != null,
		"diagnostic_only": true,
		"primary_play0_replacement": false,
		"presentation_only": true,
	}

func get_source_descriptor_snapshot() -> Dictionary:
	return source_descriptor_snapshot.duplicate(true)

func get_diagnostic_snapshot() -> Dictionary:
	return diagnostic_snapshot.duplicate(true)

func get_diagnostic_descriptors() -> Array[Dictionary]:
	return Array(diagnostic_snapshot.get("descriptors", [])).duplicate(true)

func get_view_state() -> Dictionary:
	if workbench == null:
		return {}
	var ecology: Dictionary = workbench.get_ecology_snapshot()
	return {
		"generation": int(ecology.get("generation", -1)),
		"ecology_state_hash": String(ecology.get("state_hash", "")),
		"morphology_evidence_hash": String(workbench.get_morphology_evidence().get("evidence_hash", "")),
		"descriptor_v2_hash": String(source_descriptor_snapshot.get("adapter_hash", "")),
		"diagnostic_render_hash": String(diagnostic_snapshot.get("render_hash", "")),
		"diagnostic_descriptor_count": int(diagnostic_snapshot.get("descriptor_count", 0)),
		"neutral_color": bool(overlay.neutral_color) if overlay != null else true,
	}

func _refresh() -> bool:
	if workbench == null or overlay == null:
		return false
	var ecology: Dictionary = workbench.get_ecology_snapshot()
	if ecology.is_empty():
		return false
	var generation := int(ecology.get("generation", -1))
	var evidence: Dictionary = workbench.get_morphology_evidence()
	if generation > 0:
		if evidence.is_empty() or not workbench.validate_morphology_evidence(evidence):
			source_descriptor_snapshot = {}
			diagnostic_snapshot = {}
			overlay.set_descriptors([])
			_set_status("VIS4.2 source morphology evidence unavailable / fail-closed")
			_refresh_details()
			return false
	source_descriptor_snapshot = descriptor_adapter.build(ecology, evidence)
	if source_descriptor_snapshot.is_empty():
		diagnostic_snapshot = {}
		overlay.set_descriptors([])
		_set_status("VIS4.2 Descriptor V2 source binding failed")
		_refresh_details()
		return false
	if generation == 0:
		diagnostic_snapshot = {}
		overlay.set_descriptors([])
		_set_status("Generation 0 — founder potential only. Press +1 generation for realized diagnostic morphology.")
		_refresh_details()
		return true

	diagnostic_snapshot = diagnostic_mapper.build(source_descriptor_snapshot)
	if diagnostic_snapshot.is_empty() or not diagnostic_mapper.validate_result(diagnostic_snapshot):
		diagnostic_snapshot = {}
		overlay.set_descriptors([])
		_set_status("VIS4.2 diagnostic morphology mapping failed closed")
		_refresh_details()
		return false
	if not overlay.set_descriptors(Array(diagnostic_snapshot.get("descriptors", []))):
		diagnostic_snapshot = {}
		_set_status("VIS4.2 renderer rejected diagnostic descriptors")
		_refresh_details()
		return false
	_set_status("Generation %d — honest diagnostic morphology: %d source-bound plants. Neutral color=%s" % [
		generation,
		int(diagnostic_snapshot.get("descriptor_count", 0)),
		str(bool(overlay.neutral_color)),
	])
	_refresh_details()
	return true

func _refresh_details(preferred_record_id: String = "") -> void:
	if details_label == null:
		return
	var descriptors: Array = Array(diagnostic_snapshot.get("descriptors", []))
	if descriptors.is_empty():
		details_label.text = "[b]VIS4.2[/b]\nNo realized morphology descriptors.\nGeneration 0 remains potential-only."
		return
	var sample: Dictionary = {}
	if not preferred_record_id.is_empty():
		for value in descriptors:
			if value is Dictionary and String(Dictionary(value).get("record_id", "")) == preferred_record_id:
				sample = Dictionary(value)
				break
	if sample.is_empty() and descriptors[0] is Dictionary:
		sample = Dictionary(descriptors[0])
	details_label.text = "[b]VIS4.2 morphology sample[/b]\nRecord: %s\nHeight: %.3f m\nCrown radius: %.3f m\nCrown density: %.3f\nApical dominance: %.3f\nBranch probability: %.3f\nBranch angle: %.2f deg\nBranch length ratio: %.3f\nBranching depth: %d\nStructural investment: %.3f\nLeaf conservative strategy: %.3f\n\nShape hash:\n%s\n\nGrowthGraph seal:\n%s" % [
		String(sample.get("record_id", "")),
		float(sample.get("realized_height_m", 0.0)),
		float(sample.get("realized_crown_radius_m", 0.0)),
		float(sample.get("realized_crown_density", 0.0)),
		float(sample.get("apical_dominance", 0.0)),
		float(sample.get("branch_probability", 0.0)),
		float(sample.get("branch_angle_deg", 0.0)),
		float(sample.get("branch_length_ratio", 0.0)),
		int(sample.get("branching_depth", 0)),
		float(sample.get("structural_investment", 0.0)),
		float(sample.get("leaf_conservative_strategy", 0.0)),
		String(sample.get("silhouette_hash", "")),
		String(sample.get("source_growth_graph_hash", "")),
	]

func _set_status(value: String) -> void:
	if status_label != null:
		status_label.text = value

func _on_step_pressed() -> void:
	manual_step(1)

func _on_neutral_toggled(value: bool) -> void:
	set_neutral_color(value)

func _release_owned_world() -> void:
	if owns_world_source and is_instance_valid(world_source):
		world_source.queue_free()
	world_source = null
	owns_world_source = false
