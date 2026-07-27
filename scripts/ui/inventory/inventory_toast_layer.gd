class_name InventoryToastLayer
extends MarginContainer

@onready var message_label: Label = %MessageLabel
@onready var timer: Timer = %Timer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer.timeout.connect(_hide_message)
	visible = false


func show_message(message: String, duration_seconds: float = 2.5) -> void:
	if message.is_empty():
		return
	message_label.text = message
	visible = true
	timer.start(maxf(0.1, duration_seconds))


func _hide_message() -> void:
	visible = false
