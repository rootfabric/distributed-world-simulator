extends CanvasLayer

signal console_visibility_changed(opened: bool)

var command_registry
var simulator
var panel: PanelContainer
var output_view: RichTextLabel
var input_line: LineEdit
var context_label: Label
var opened: bool = false
var history: Array[String] = []
var history_index: int = 0
var maximum_history: int = 100
var completion_provider: Callable


func setup(command_registry_reference, simulator_reference) -> void:
	command_registry = command_registry_reference
	simulator = simulator_reference
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	set_open(false)
	_print_line("PlanetSimulator Console. Введите help для списка команд.")


func set_completion_provider(provider: Callable) -> void:
	completion_provider = provider


func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.name = "DeveloperConsolePanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -430.0
	panel.offset_bottom = 0.0
	add_child(panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.01, 0.012, 0.018, 0.97)
	panel_style.border_color = Color(0.28, 0.34, 0.44, 0.95)
	panel_style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)

	var title := Label.new()
	title.text = "PLANETSIMULATOR CONSOLE"
	title.add_theme_font_size_override("font_size", 17)
	header.add_child(title)

	context_label = Label.new()
	context_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	context_label.text = "world: -"
	context_label.modulate = Color(0.72, 0.78, 0.88)
	header.add_child(context_label)

	output_view = RichTextLabel.new()
	output_view.name = "ConsoleOutput"
	output_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output_view.fit_content = false
	output_view.scroll_active = true
	output_view.scroll_following = true
	output_view.selection_enabled = true
	output_view.add_theme_font_size_override("normal_font_size", 14)
	column.add_child(output_view)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	column.add_child(input_row)

	var prompt := Label.new()
	prompt.text = ">"
	prompt.add_theme_font_size_override("font_size", 17)
	input_row.add_child(prompt)

	input_line = LineEdit.new()
	input_line.name = "ConsoleInput"
	input_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_line.placeholder_text = "help | world.list | world.load moon | test.run all"
	input_line.clear_button_enabled = true
	input_line.text_submitted.connect(_on_text_submitted)
	input_line.gui_input.connect(_on_input_gui_event)
	input_row.add_child(input_line)

	var hint := Label.new()
	hint.text = "~ открыть/закрыть | ↑↓ история | Tab автодополнение | Esc закрыть"
	hint.modulate = Color(0.64, 0.70, 0.80)
	column.add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_QUOTELEFT:
		set_open(not opened)
		get_viewport().set_input_as_handled()
		return
	if opened and event.keycode == KEY_ESCAPE:
		set_open(false)
		get_viewport().set_input_as_handled()


func _on_input_gui_event(event: InputEvent) -> void:
	if not opened or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_QUOTELEFT or event.keycode == KEY_ESCAPE:
		set_open(false)
		input_line.accept_event()
		return
	match event.keycode:
		KEY_UP:
			_show_history(-1)
			input_line.accept_event()
		KEY_DOWN:
			_show_history(1)
			input_line.accept_event()
		KEY_TAB:
			_complete_command()
			input_line.accept_event()


func set_open(value: bool) -> void:
	var state_changed: bool = opened != value
	opened = value
	if panel != null:
		panel.visible = opened
	if opened and input_line != null:
		input_line.grab_focus()
		input_line.caret_column = input_line.text.length()
	elif input_line != null:
		input_line.release_focus()
	if state_changed:
		console_visibility_changed.emit(opened)


func is_open() -> bool:
	return opened


func set_world_context(world_id: String, display_name: String) -> void:
	if context_label != null:
		context_label.text = "world: %s — %s" % [world_id, display_name]


func execute_line(command_line: String) -> Dictionary:
	var normalized: String = command_line.strip_edges()
	if normalized.is_empty():
		return {"success": true, "output": ""}
	_push_history(normalized)
	_print_line("> %s" % normalized)
	var result: Dictionary = command_registry.execute_line(normalized)
	var output: String = String(result.get("output", result.get("message", "")))
	if not output.is_empty():
		_print_line(output)
	return result


func clear_output() -> void:
	if output_view != null:
		output_view.clear()


func print_system(message: String) -> void:
	_print_line(message)


func _on_text_submitted(command_line: String) -> void:
	input_line.clear()
	execute_line(command_line)
	if opened:
		input_line.grab_focus()


func _push_history(command_line: String) -> void:
	if not history.is_empty() and history[-1] == command_line:
		history_index = history.size()
		return
	history.append(command_line)
	if history.size() > maximum_history:
		history.pop_front()
	history_index = history.size()


func _show_history(direction: int) -> void:
	if history.is_empty():
		return
	history_index = clampi(history_index + direction, 0, history.size())
	input_line.text = "" if history_index == history.size() else history[history_index]
	_restore_input_focus.call_deferred()


func _restore_input_focus(target_caret: int = -1) -> void:
	if input_line == null or not opened:
		return
	input_line.grab_focus()
	input_line.deselect()
	input_line.caret_column = input_line.text.length() if target_caret < 0 else clampi(target_caret, 0, input_line.text.length())


func _complete_command() -> void:
	var current_text: String = input_line.text
	var caret: int = input_line.caret_column
	var before := current_text.left(caret)
	var token_start := maxi(before.rfind(" "), before.rfind("\t")) + 1
	var prefix := before.substr(token_start)
	var completions: Array[String] = []
	if completion_provider.is_valid():
		completions = completion_provider.call(current_text, caret)
	else:
		completions = command_registry.find_completions(prefix)
	if completions.is_empty():
		return
	var replacement := ""
	if completions.size() == 1:
		replacement = completions[0]
	else:
		replacement = _common_prefix(completions)
		_print_line("Варианты: %s" % ", ".join(PackedStringArray(completions)))
	if replacement.is_empty() or replacement.length() <= prefix.length():
		_restore_input_focus.call_deferred(caret)
		return
	input_line.text = current_text.left(token_start) + replacement + current_text.substr(caret)
	input_line.caret_column = token_start + replacement.length()
	if completions.size() == 1 and input_line.caret_column == input_line.text.length():
		input_line.text += " "
		input_line.caret_column = input_line.text.length()
	_restore_input_focus.call_deferred(input_line.caret_column)


func _common_prefix(values: Array[String]) -> String:
	if values.is_empty():
		return ""
	var prefix := values[0]
	for value in values:
		while not String(value).begins_with(prefix) and not prefix.is_empty():
			prefix = prefix.left(prefix.length() - 1)
	return prefix


func _print_line(message: String) -> void:
	if output_view == null:
		return
	output_view.append_text(message + "\n")
