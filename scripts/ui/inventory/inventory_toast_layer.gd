class_name InventoryToastLayer
extends MarginContainer

@onready var message_label: Label = %MessageLabel
@onready var timer: Timer = %Timer

var message_kind: String = "info"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer.timeout.connect(_hide_message)
	visible = false


func show_message(message: String, duration_seconds: float = 2.5) -> void:
	_show(message, "info", duration_seconds)


func show_success(message: String, duration_seconds: float = 2.2) -> void:
	_show(message, "success", duration_seconds)


func show_error(message: String, duration_seconds: float = 3.5) -> void:
	_show(message, "error", duration_seconds)


func _show(message: String, kind: String, duration_seconds: float) -> void:
	if message.is_empty():
		return
	message_kind = kind
	message_label.text = message
	match kind:
		"success":
			message_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.68))
		"error":
			message_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.48))
		_:
			message_label.add_theme_color_override("font_color", Color(0.78, 0.84, 0.92))
	visible = true
	timer.start(maxf(0.1, duration_seconds))


func _hide_message() -> void:
	visible = false
