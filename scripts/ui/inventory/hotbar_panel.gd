class_name InventoryHotbarPanel
extends "res://scripts/ui/inventory/container_panel.gd"


func render_hotbar(model: Dictionary, new_icon_provider: Callable, new_drop_validator: Callable) -> void:
	render(model, new_icon_provider, new_drop_validator)
	title_label.text = "Быстрая панель 1–0"
