class_name InventoryItemContextMenu
extends PopupMenu

var item_id: String = ""


func open_for_item(new_item_id: String, screen_position: Vector2i) -> void:
	item_id = new_item_id
	clear()
	add_item("Осмотреть", 1)
	position = screen_position
	popup()
