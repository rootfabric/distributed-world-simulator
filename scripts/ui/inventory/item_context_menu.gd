class_name InventoryItemContextMenu
extends PopupMenu

signal action_requested(action_id: int, context: Dictionary)

const ACTION_INSPECT: int = 1
const ACTION_TRANSFER_ALL: int = 10
const ACTION_TRANSFER_ONE: int = 11
const ACTION_TRANSFER_HALF: int = 12
const ACTION_TRANSFER_EXACT: int = 13
const ACTION_DROP_ONE: int = 20
const ACTION_DROP_ALL: int = 21
const ACTION_HOTBAR_FIRST_FREE: int = 30
const ACTION_HOTBAR_SLOT_BASE: int = 100

var context: Dictionary = {}
var hotbar_submenu: PopupMenu


func _ready() -> void:
	id_pressed.connect(_on_action_pressed)
	hotbar_submenu = PopupMenu.new()
	hotbar_submenu.name = "HotbarSubmenu"
	hotbar_submenu.id_pressed.connect(_on_hotbar_slot_pressed)
	add_child(hotbar_submenu)


func open_for_item(cell_data: Dictionary, screen_position: Vector2i, options: Dictionary = {}) -> void:
	context = {
		"item_id": String(cell_data.get("item_id", "")),
		"source_container_id": String(cell_data.get("source_container_id", "")),
		"source_slot_index": int(cell_data.get("source_slot_index", -1)),
		"quantity": int(cell_data.get("quantity", 0)),
		"display_name": String(cell_data.get("display_name", "Предмет")),
		"cell_data": cell_data.duplicate(true),
	}
	clear()
	hotbar_submenu.clear()
	add_item("Осмотреть", ACTION_INSPECT)
	if bool(options.get("can_quick_transfer", false)):
		add_separator()
		add_item("Перенести весь стак", ACTION_TRANSFER_ALL)
		add_item("Перенести 1", ACTION_TRANSFER_ONE)
		if int(context.quantity) > 1:
			add_item("Перенести половину", ACTION_TRANSFER_HALF)
			add_item("Перенести количество…", ACTION_TRANSFER_EXACT)
	var hotbar_slots: Array = Array(options.get("hotbar_slots", []))
	if not hotbar_slots.is_empty():
		add_separator()
		add_item("В первый свободный слот hotbar", ACTION_HOTBAR_FIRST_FREE)
		for slot_value in hotbar_slots:
			var slot: Dictionary = Dictionary(slot_value)
			var slot_index := int(slot.get("slot_index", -1))
			var key_name := "0" if slot_index == 9 else str(slot_index + 1)
			var label := "Слот %s" % key_name
			if bool(slot.get("occupied", false)):
				label += " · занят"
			hotbar_submenu.add_item(label, ACTION_HOTBAR_SLOT_BASE + slot_index)
			hotbar_submenu.set_item_disabled(
				hotbar_submenu.item_count - 1,
				not bool(slot.get("enabled", false))
			)
		add_submenu_item("Назначить в hotbar…", hotbar_submenu.name)
	if bool(options.get("can_drop", true)):
		add_separator()
		add_item("Выбросить 1", ACTION_DROP_ONE)
		add_item("Выбросить весь стак", ACTION_DROP_ALL)
	position = screen_position
	popup()


func close_menu() -> void:
	hide()
	context = {}


func _on_action_pressed(action_id: int) -> void:
	hide()
	var payload := context.duplicate(true)
	payload["hotbar_slot_index"] = -1
	action_requested.emit(action_id, payload)


func _on_hotbar_slot_pressed(action_id: int) -> void:
	hide()
	var payload := context.duplicate(true)
	payload["hotbar_slot_index"] = action_id - ACTION_HOTBAR_SLOT_BASE
	action_requested.emit(action_id, payload)
