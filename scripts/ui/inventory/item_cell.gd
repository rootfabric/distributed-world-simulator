class_name InventoryItemCell
extends "res://scripts/items/presentation/item_slot_control.gd"

var view_data: Dictionary = {}


func render_cell(data: Dictionary, texture: Texture2D, validator: Callable) -> void:
	view_data = data.duplicate(true)
	setup_slot({
		"item_id": String(data.get("item_id", "")),
		"source_container_id": String(data.get("source_container_id", "")),
		"source_slot_index": int(data.get("source_slot_index", -1)),
		"target_container_id": String(data.get("target_container_id", "")),
		"target_slot_index": int(data.get("target_slot_index", -1)),
		"icon_texture": texture,
		"title": String(data.get("display_name", "Пусто")),
		"quantity": int(data.get("quantity", 0)),
		"selected": bool(data.get("selected", false)),
		"drop_validator": validator,
	})
	set_meta("inventory_view_data", view_data.duplicate(true))
