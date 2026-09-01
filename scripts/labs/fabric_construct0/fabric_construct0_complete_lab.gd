extends Node3D

const STAGES: Array[Dictionary] = [
	{
		"id": "C0.1-C0.3",
		"title": "SEE / MOVE / BUILD",
		"scene": "res://scenes/labs/fabric_construct0_lab.tscn",
	},
	{
		"id": "PLAY1",
		"title": "PHYSICAL TOYBOX",
		"scene": "res://scenes/labs/fabric_construct0_play1_lab.tscn",
	},
	{
		"id": "C0.4-C0.6",
		"title": "FULL / BAKE / REBUILD / SPLIT",
		"scene": "res://scenes/labs/fabric_construct0_c0_4_c0_6_lab.tscn",
	},
]

var _lab_root: Node
var _status: Label
var _active_index := -1

func _ready() -> void:
	_lab_root = Node.new()
	_lab_root.name = "ActiveConstruct0Lab"
	add_child(_lab_root)
	_build_navigation()
	_load_stage(0)

func _build_navigation() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(670.0, 18.0)
	panel.size = Vector2(500.0, 190.0)
	layer.add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.018, 0.030, 0.97)
	style.border_color = Color(0.28, 0.72, 0.46, 0.95)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	var title := Label.new()
	title.text = "CONSTRUCT0 COMPLETE LAB"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)

	var row := GridContainer.new()
	row.columns = 3
	box.add_child(row)
	for index in range(STAGES.size()):
		var button := Button.new()
		button.text = String(STAGES[index]["id"])
		button.pressed.connect(_load_stage.bind(index))
		row.add_child(button)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(0.72, 0.84, 0.76)
	box.add_child(_status)

	var guide := Label.new()
	guide.text = "End-to-end: build → run → FULL/BAKED → mutate/rebuild → local unbake → break/split/re-bake."
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide.modulate = Color(0.60, 0.70, 0.82)
	box.add_child(guide)

func _load_stage(index: int) -> void:
	if index < 0 or index >= STAGES.size():
		return
	for child in _lab_root.get_children():
		_lab_root.remove_child(child)
		child.queue_free()
	var packed = load(String(STAGES[index]["scene"]))
	if not (packed is PackedScene):
		_status.text = "FAILED TO LOAD %s" % String(STAGES[index]["scene"])
		return
	var instance = packed.instantiate()
	_lab_root.add_child(instance)
	_active_index = index
	_status.text = "Active: %s — %s" % [
		String(STAGES[index]["id"]),
		String(STAGES[index]["title"]),
	]

func active_stage_id() -> String:
	if _active_index < 0:
		return ""
	return String(STAGES[_active_index]["id"])

func stage_count() -> int:
	return STAGES.size()
