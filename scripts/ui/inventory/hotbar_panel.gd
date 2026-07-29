class_name InventoryHotbarPanel
extends "res://scripts/ui/inventory/container_panel.gd"


func _ready() -> void:
	super._ready()
	role_label.visible = false
	title_label.visible = false
	metadata_label.visible = false
	drop_hint_label.visible = false
	feedback_label.visible = false
	get_node("Content/Separator").visible = false
	_apply_compact_hotbar_style()


func render_hotbar(model: Dictionary, new_icon_provider: Callable, new_drop_validator: Callable) -> void:
	var hotbar_model := model.duplicate(true)
	hotbar_model["columns"] = 10
	render(hotbar_model, new_icon_provider, new_drop_validator)
	grid.columns = 10
	title_label.text = "Быстрая панель 1–0"


func _apply_compact_hotbar_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.008, 0.014, 0.022, 0.58)
	style.border_color = Color(0.26, 0.72, 0.68, 0.62)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8.0
	style.content_margin_top = 6.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 6.0
	add_theme_stylebox_override("panel", style)
