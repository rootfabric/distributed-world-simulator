class_name InventoryHotbarPanel
extends "res://scripts/ui/inventory/container_panel.gd"


func _ready() -> void:
	super._ready()
	# The persistent hotbar is deliberately a compact control strip. Its item
	# cells already carry the slot numbers, so repeating a title, capacity and
	# drag hint above them only obscures the gameplay view.
	role_label.visible = false
	title_label.visible = false
	metadata_label.visible = false
	drop_hint_label.visible = false
	feedback_label.visible = false
	get_node("Content/Separator").visible = false
	_apply_compact_hotbar_style()


func set_interaction_profile(profile: InventoryInteractionProfile) -> void:
	super.set_interaction_profile(profile)
	_apply_compact_hotbar_style()


func render_hotbar(model: Dictionary, new_icon_provider: Callable, new_drop_validator: Callable) -> void:
	var hotbar_model := model.duplicate(true)
	# The hotbar is a fixed 1–0 strip, not a capacity-adaptive inventory grid.
	# Ten slots must stay on one visible line.
	hotbar_model["columns"] = 10
	render(hotbar_model, new_icon_provider, new_drop_validator)
	grid.columns = 10
	_apply_compact_hotbar_style()


func _apply_compact_hotbar_style() -> void:
	if role_label != null:
		role_label.visible = false
	if title_label != null:
		title_label.visible = false
	if metadata_label != null:
		metadata_label.visible = false
	if drop_hint_label != null:
		drop_hint_label.visible = false
	if feedback_label != null:
		feedback_label.visible = false
	var separator := get_node_or_null("Content/Separator")
	if separator != null:
		separator.visible = false
	custom_minimum_size = Vector2(custom_minimum_size.x, 72.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.008, 0.014, 0.022, 0.58)
	style.border_color = Color(0.26, 0.72, 0.68, 0.62)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8.0
	style.content_margin_top = 6.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 6.0
	add_theme_stylebox_override("panel", style)
	title_label.text = "Быстрая панель 1–0"
