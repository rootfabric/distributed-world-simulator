class_name InventoryItemTooltip
extends PanelContainer

@onready var text_label: Label = %TextLabel

var pinned: bool = false
var current_item_id: String = ""


func show_item(cell_data: Dictionary, pin: bool = false) -> void:
	custom_minimum_size = Vector2(300.0, 0.0)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	reset_size()


func show_name_only(cell_data: Dictionary) -> void:
	current_item_id = String(cell_data.get("item_id", ""))
	pinned = false
	var display_name := String(cell_data.get("display_name", "Предмет"))
	var font := text_label.get_theme_font("font")
	var font_size := text_label.get_theme_font_size("font_size")
	var measured_width := font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	custom_minimum_size = Vector2(clampf(measured_width + 24.0, 96.0, 260.0), 0.0)
	text_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	text_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_label.clip_text = true
	text_label.text = display_name
	visible = not current_item_id.is_empty()
	reset_size()


func clear_item(force: bool = false) -> void:
	if pinned and not force:
		return
	pinned = false
	current_item_id = ""
	visible = false
	text_label.text = ""
