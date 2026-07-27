class_name InventoryStackSplitDialog
extends PopupPanel

signal transfer_confirmed(item_id: String, quantity: int, target_container_id: String, target_slot_index: int, target_item_id: String)
signal transfer_cancelled()

@onready var prompt_label: Label = %PromptLabel
@onready var quantity_spin: SpinBox = %QuantitySpin
@onready var quantity_slider: HSlider = %QuantitySlider
@onready var one_button: Button = %OneButton
@onready var half_button: Button = %HalfButton
@onready var maximum_button: Button = %MaximumButton

var pending_item_id: String = ""
var pending_target_container_id: String = ""
var pending_target_slot_index: int = -1
var pending_target_item_id: String = ""
var pending_total_quantity: int = 0
var _syncing_quantity: bool = false


func _ready() -> void:
	%ConfirmButton.pressed.connect(_confirm)
	%CancelButton.pressed.connect(cancel)
	one_button.pressed.connect(func() -> void: set_quantity(1))
	half_button.pressed.connect(func() -> void: set_quantity(maxi(1, int(ceil(float(pending_total_quantity) * 0.5)))))
	maximum_button.pressed.connect(func() -> void: set_quantity(pending_total_quantity))
	quantity_spin.value_changed.connect(_on_spin_changed)
	quantity_slider.value_changed.connect(_on_slider_changed)


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
	quantity_slider.min_value = 1.0
	quantity_slider.max_value = float(pending_total_quantity)
	set_quantity(1)
	prompt_label.text = "%s · в стаке %d\nКуда: %s" % [item_name, pending_total_quantity, destination_name]
	popup_centered(Vector2i(470, 260))
	quantity_spin.focus_mode = Control.FOCUS_ALL
	quantity_spin.grab_focus()


func set_quantity(value: int) -> void:
	var clamped := clampi(value, 1, maxi(1, pending_total_quantity))
	_syncing_quantity = true
	quantity_spin.value = float(clamped)
	quantity_slider.value = float(clamped)
	_syncing_quantity = false


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


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_confirm()
		get_viewport().set_input_as_handled()


func _on_spin_changed(value: float) -> void:
	if _syncing_quantity:
		return
	_syncing_quantity = true
	quantity_slider.value = value
	_syncing_quantity = false


func _on_slider_changed(value: float) -> void:
	if _syncing_quantity:
		return
	_syncing_quantity = true
	quantity_spin.value = value
	_syncing_quantity = false


func _confirm() -> void:
	var item_id := pending_item_id
	var quantity := int(quantity_spin.value)
	var target_container_id := pending_target_container_id
	var target_slot_index := pending_target_slot_index
	var target_item_id := pending_target_item_id
	hide()
	clear_request()
	transfer_confirmed.emit(item_id, quantity, target_container_id, target_slot_index, target_item_id)
