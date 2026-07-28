class_name InventoryItemTooltip
extends PanelContainer

@onready var text_label: Label = %TextLabel

var pinned: bool = false
var current_item_id: String = ""


func show_item(cell_data: Dictionary, pin: bool = false) -> void:
	current_item_id = String(cell_data.get("item_id", ""))
	pinned = pin
	var quantity := maxi(1, int(cell_data.get("quantity", 1)))
	var unit_mass := float(cell_data.get("unit_mass_kg", 0.0))
	var unit_volume := float(cell_data.get("unit_volume_l", 0.0))
	var tags := PackedStringArray(cell_data.get("tags", []))
	var lines := PackedStringArray([
		String(cell_data.get("display_name", "Предмет")),
		"Количество: %d" % quantity,
		"Масса: %.2f кг / всего %.2f кг" % [unit_mass, unit_mass * quantity],
		"Объём: %.2f л / всего %.2f л" % [unit_volume, unit_volume * quantity],
	])
	if not tags.is_empty():
		lines.append("Категории: %s" % ", ".join(tags))
	if pin:
		lines.append("ЛКМ drag — весь стак · Shift+ЛКМ — быстрый перенос")
		lines.append("ПКМ — действия и разделение")
		if OS.is_debug_build():
			lines.append("UUID: %s" % current_item_id)
	text_label.text = "\n".join(lines)
	visible = true


func clear_item(force: bool = false) -> void:
	if pinned and not force:
		return
	pinned = false
	current_item_id = ""
	visible = false
	text_label.text = ""
