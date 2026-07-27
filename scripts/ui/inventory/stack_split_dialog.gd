class_name InventoryStackSplitDialog
extends PopupPanel

signal transfer_confirmed(item_id: String, quantity: int, target_container_id: String, target_slot_index: int, target_item_id: String)
signal transfer_cancelled()

@onready var prompt_label: Label = %PromptLabel
@onready var quantity_spin: SpinBox = %QuantitySpin

var pending_item_id: String = ""
var pending_target_container_id: String = ""
var pending_target_slot_index: int = -1
var pending_target_item_id: String = ""
var pending_total_quantity: int = 0


func _ready() -> void:
	%ConfirmButton.pressed.connect(_confirm)
	%CancelButton.pressed.connect(cancel)


func open_request(
	item_id: String,
	total_quantity: int,
	target_container_id: String,
	target_slot_index: int,
	target_item_id: String,
	item_name: String,
	destination_name: String
) -> void:
	pending_item_id = item_id
	pending_total_quantity = maxi(1, total_quantity)
	pending_target_container_id = target_container_id
	pending_target_slot_index = target_slot_index
	pending_target_item_id = target_item_id
	quantity_spin.min_value = 1.0
	quantity_spin.max_value = float(pending_total_quantity)
	quantity_spin.value = 1.0
	prompt_label.text = "%s · в стаке %d\nКуда: %s" % [item_name, pending_total_quantity, destination_name]
	popup_centered(Vector2i(440, 190))
	quantity_spin.focus_mode = Control.FOCUS_ALL
	quantity_spin.grab_focus()


func cancel() -> void:
	hide()
	clear_request()
	transfer_cancelled.emit()


func clear_request() -> void:
	pending_item_id = ""
	pending_target_container_id = ""
	pending_target_slot_index = -1
	pending_target_item_id = ""
	pending_total_quantity = 0


func _confirm() -> void:
	var item_id := pending_item_id
	var quantity := int(quantity_spin.value)
	var target_container_id := pending_target_container_id
	var target_slot_index := pending_target_slot_index
	var target_item_id := pending_target_item_id
	hide()
	clear_request()
	transfer_confirmed.emit(item_id, quantity, target_container_id, target_slot_index, target_item_id)
