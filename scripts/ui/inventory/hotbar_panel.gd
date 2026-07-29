class_name InventoryHotbarPanel
extends "res://scripts/ui/inventory/container_panel.gd"


func render_hotbar(model: Dictionary, new_icon_provider: Callable, new_drop_validator: Callable) -> void:
	var hotbar_model := model.duplicate(true)
	# The hotbar is a fixed 1–0 strip, not a capacity-adaptive inventory grid.
	# Ten slots must stay on one visible line.
	hotbar_model["columns"] = 10
	render(hotbar_model, new_icon_provider, new_drop_validator)
	grid.columns = 10
	title_label.text = "Быстрая панель 1–0"
