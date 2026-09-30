extends SceneTree

const ModernApp = preload("res://scripts/app/earth_p1_modern_inventory_app.gd")
const ModernShell = preload("res://scripts/ui/inventory/networked/m5_v0_modern_inventory_shell_r5.gd")

class AppProbe:
	extends ModernApp
	var neutral_inputs := 0
	var primary_actions := 0
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func _submit_mvp_neutral_input() -> void:
		neutral_inputs += 1
	func execute_runtime_command(_command_line: String) -> Dictionary:
		primary_actions += 1
		return {"success": true, "output": "probe"}

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var old_mouse_mode := Input.mouse_mode
	var app = AppProbe.new()
	root.add_child(app)
	app.set_process(false)
	app.local_input_enabled = true
	var shell = ModernShell.new()
	app.add_child(shell)
	shell.set_process(false)
	shell.inventory_window = PanelContainer.new()
	shell.add_child(shell.inventory_window)
	shell.status_label = Label.new()
	shell.add_child(shell.status_label)
	app._mvp_inventory_shell = shell
	app._bind_mvp_inventory_visibility()
	shell.set_inventory_visible(false)

	for cycle in range(30):
		var opened: Dictionary = app._command_mvp_inventory_toggle([])
		_check(bool(opened.get("success", false)), "app opens inventory")
		_check(app.is_mvp_inventory_visible() and app._mvp_inventory_visible, "open state reaches app")
		_check(app._mvp_input_owner == "INVENTORY", "inventory owns input while open")
		_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "open inventory keeps cursor visible")
		var blocked: Dictionary = app._command_live2_primary([])
		_check(not bool(blocked.get("success", false)), "primary blocked only while inventory is open")
		_press(shell, KEY_G)
		_check(shell.is_inventory_visible(), "G does not close inventory")
		_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "G does not capture cursor")
		_press(shell, KEY_ESCAPE if cycle % 2 == 0 else KEY_TAB)
		_check(not shell.is_inventory_visible(), "Esc/Tab closes shell")
		_check(not app._mvp_inventory_visible, "Esc/Tab releases inherited movement gate")
		_check(not app.is_mvp_inventory_visible(), "public visibility agrees")
		_check(app._mvp_input_owner == "GAMEPLAY", "Esc/Tab restores gameplay owner")
		var resumed: Dictionary = app._command_live2_primary([])
		_check(bool(resumed.get("success", false)), "primary works immediately without F3")
	_check(app.neutral_inputs == 30, "exactly one neutral input on each opening")
	_check(app.primary_actions == 30, "all post-close primary actions execute")

	# Programmatic/button close and direct shell toggle share the same setter.
	shell.toggle_inventory()
	_check(app._mvp_inventory_visible, "shell toggle notifies app")
	shell.set_inventory_visible(false)
	_check(not app._mvp_inventory_visible, "programmatic close releases gate")

	# JOIN reuse must not accumulate handlers or preserve a stale app cache.
	app._mvp_inventory_visible = true
	for _index in range(3):
		var reused: Dictionary = app._ensure_mvp_inventory_shell(null)
		_check(bool(reused.get("success", false)), "existing shell reused")
	_check(not app._mvp_inventory_visible, "reuse reconciles stale cache")
	_check(shell.inventory_visibility_changed.get_connections().size() == 1, "one visibility observer after repeated attach")

	# Key-repeat/release do not double-toggle; actual key press still closes.
	app._set_mvp_inventory_visible(true)
	_press(shell, KEY_TAB, true)
	_check(shell.is_inventory_visible(), "repeat does not close")
	_press(shell, KEY_TAB, false, false)
	_check(shell.is_inventory_visible(), "release does not close")
	_press(shell, KEY_TAB)
	_check(not app._mvp_inventory_visible, "physical press closes once")

	# Closing inventory must not steal mouse ownership from console/system UI.
	app.local_input_enabled = false
	app._set_mvp_inventory_visible(true)
	_press(shell, KEY_ESCAPE)
	_check(app._mvp_input_owner == "EXTERNAL_UI", "external UI retains ownership")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "external UI cursor is not captured")
	app.local_input_enabled = true
	app._mvp_spectator_enabled = true
	app._set_mvp_inventory_visible(true)
	_press(shell, KEY_ESCAPE)
	_check(app._mvp_input_owner == "SPECTATOR", "closing inventory restores spectator, not gameplay")
	app._mvp_spectator_enabled = false
	app._set_mvp_inventory_visible(false)

	app.free()
	Input.mouse_mode = old_mouse_mode
	for failure in failures:
		push_error(failure)
	print("LIVE2 R3 inventory ownership: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _press(shell, key: int, echo: bool = false, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	event.echo = echo
	# Exercise the real shell handler, including its input-consumption branch.
	shell._input(event)


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
