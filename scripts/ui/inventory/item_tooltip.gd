class_name InventoryItemTooltip
extends PanelContainer

@onready var text_label: Label = %TextLabel


func show_item(cell_data: Dictionary) -> void:
	text_label.text = "%s\nКоличество: %d" % [
		String(cell_data.get("display_name", "Предмет")),
		int(cell_data.get("quantity", 0)),
	]
	visible = true


func clear_item() -> void:
	visible = false
	text_label.text = ""
