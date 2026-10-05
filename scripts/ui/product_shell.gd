extends CanvasLayer

const PREFS_PATH := "user://v0-live/product-shell.json"
const PREFS_SCHEMA := "dws.ux0.product_shell_prefs.v1"
const DEFAULT_PORT := 24580
const DEFAULT_PLAYER := "player"
const DEFAULT_WORLD := "earth"
const DEFAULT_SLOT := "world-01"

var _prefs: Dictionary = {}
var _root: Control
var _views: Dictionary = {}
var _status_label: Label
var _continue_button: Button
var _home_summary: Label

var _host_player: LineEdit
var _host_port: SpinBox
var _host_slot: LineEdit
var _host_start: Button

var _join_address: LineEdit
var _join_port: SpinBox
var _join_player: LineEdit
var _join_start: Button

var _settings_player: LineEdit
var _settings_port: SpinBox

var _host_server_pid := -1
var _host_client_pid := -1
var _join_client_pids: Array[int] = []
var _busy := false


static func should_open_shell(arguments) -> bool:
	var args := PackedStringArray(arguments)
	if args.is_empty():
		return true
	for raw in args:
		var argument := String(raw).strip_edges()
		if (
			argument == "--product-shell"
			or argument.begins_with("--product-shell=")
			or argument.begins_with("--product-shell-smoke=")
		):
			return true
	return false


static func product_shell_smoke_path(arguments) -> String:
	for raw in PackedStringArray(arguments):
		var argument := String(raw).strip_edges()
		if argument.begins_with("--product-shell-smoke="):
			return argument.trim_prefix("--product-shell-smoke=").strip_edges()
	return ""


static func default_preferences() -> Dictionary:
	return {
		"schema": PREFS_SCHEMA,
		"default_player_name": DEFAULT_PLAYER,
		"default_port": DEFAULT_PORT,
		"last_server_address": "127.0.0.1",
		"last_hosted_world": DEFAULT_WORLD,
		"last_persistence_slot": DEFAULT_SLOT,
		"has_host_history": false,
		"last_mode": "",
	}


static func normalize_preferences(value: Dictionary) -> Dictionary:
	var result := default_preferences()
	var player := String(value.get("default_player_name", DEFAULT_PLAYER)).strip_edges()
	if not player.is_empty():
		result["default_player_name"] = player.left(48)
	var port := int(value.get("default_port", DEFAULT_PORT))
	if port >= 1 and port <= 65535:
		result["default_port"] = port
	var address := String(value.get("last_server_address", "127.0.0.1")).strip_edges()
	if not address.is_empty():
		result["last_server_address"] = address.left(255)
	var world := String(value.get("last_hosted_world", DEFAULT_WORLD)).strip_edges().to_lower()
	result["last_hosted_world"] = DEFAULT_WORLD if world != DEFAULT_WORLD else world
	var slot := normalize_slug(String(value.get("last_persistence_slot", DEFAULT_SLOT)), DEFAULT_SLOT)
	result["last_persistence_slot"] = slot
	result["has_host_history"] = bool(value.get("has_host_history", false))
	result["last_mode"] = String(value.get("last_mode", "")).strip_edges().to_lower()
	return result


static func normalize_slug(value: String, fallback: String) -> String:
	var source := value.strip_edges().to_lower()
	var output := ""
	for index in range(source.length()):
		var character := source.substr(index, 1)
		var code := character.unicode_at(0)
		var allowed := (
			(code >= 97 and code <= 122)
			or (code >= 48 and code <= 57)
			or character in ["-", "_"]
		)
		if allowed:
			output += character
		elif character in [" ", ".", "/", "\\"]:
			if not output.ends_with("-"):
				output += "-"
	output = output.strip_edges().trim_prefix("-").trim_suffix("-").left(48)
	return fallback if output.is_empty() else output


static func build_host_user_args(
	world_id: String,
	port: int,
	persistence_slot: String
) -> PackedStringArray:
	var world := world_id.strip_edges().to_lower()
	if world != DEFAULT_WORLD:
		world = DEFAULT_WORLD
	var slot := normalize_slug(persistence_slot, DEFAULT_SLOT)
	return PackedStringArray([
		"--role=dedicated-server",
		"--network-mvp",
		"--world=%s" % world,
		"--server-address=127.0.0.1",
		"--server-port=%d" % clampi(port, 1, 65535),
		"--instance-id=%s" % slot,
		"--node-id=ux0-server-%s" % slot,
	])


static func build_join_user_args(
	server_address: String,
	port: int,
	player_name: String
) -> PackedStringArray:
	var address := server_address.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var player_id := normalize_slug(player_name, DEFAULT_PLAYER)
	return PackedStringArray([
		"--role=game-client",
		"--network-mvp",
		"--world=earth",
		"--server-address=%s" % address,
		"--server-port=%d" % clampi(port, 1, 65535),
		"--player-identity=%s" % player_id,
		"--node-id=ux0-client-%s" % player_id,
	])


static func build_child_process_args(
	user_args: PackedStringArray,
	editor_runtime: bool,
	project_path: String,
	headless: bool = false
) -> PackedStringArray:
	var result := PackedStringArray()
	if headless:
		result.append("--headless")
	if editor_runtime:
		result.append("--path")
		result.append(project_path)
	result.append("--")
	result.append_array(user_args)
	return result


func setup() -> void:
	name = "UX0ProductShell"
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_prefs = _load_preferences()
	_build_ui()
	_show_view("home")
	set_process(true)
	var smoke_path := product_shell_smoke_path(OS.get_cmdline_user_args())
	if not smoke_path.is_empty():
		call_deferred("_write_smoke_report_and_quit", smoke_path)


func get_report() -> Dictionary:
	return {
		"schema": "dws.ux0.product_shell_report.v1",
		"prefs": _prefs.duplicate(true),
		"view_ids": _views.keys(),
		"host_server_pid": _host_server_pid,
		"host_client_pid": _host_client_pid,
		"join_client_pids": _join_client_pids.duplicate(),
		"busy": _busy,
	}


func _write_smoke_report_and_quit(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var report := get_report()
	report["smoke"] = true
	report["root_present"] = _root != null and is_instance_valid(_root)
	report["continue_enabled"] = _continue_button != null and not _continue_button.disabled
	report["root_size"] = [_root.size.x, _root.size.y]
	var view_sizes := {}
	for key in _views:
		var view: Control = _views[key]
		view_sizes[String(key)] = [view.size.x, view.size.y]
	report["view_sizes"] = view_sizes
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("UX0_PRODUCT_SHELL_SMOKE_WRITE_FAILED:%s" % path)
		get_tree().quit(3)
		return
	file.store_string(JSON.stringify(report, "  "))
	get_tree().quit(0)


func _process(_delta: float) -> void:
	if _host_server_pid > 0 and not OS.is_process_running(_host_server_pid):
		_host_server_pid = -1
		if not _busy:
			_set_status("Локальный dedicated server завершён. Клиент продолжит штатный reconnect.", false)
	if _host_client_pid > 0 and not OS.is_process_running(_host_client_pid):
		_host_client_pid = -1
	for index in range(_join_client_pids.size() - 1, -1, -1):
		if not OS.is_process_running(_join_client_pids[index]):
			_join_client_pids.remove_at(index)


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "ProductShellRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var background := ColorRect.new()
	background.color = Color(0.012, 0.018, 0.030, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(background)

	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 42)
	outer.add_theme_constant_override("margin_right", 42)
	outer.add_theme_constant_override("margin_top", 36)
	outer.add_theme_constant_override("margin_bottom", 36)
	_root.add_child(outer)

	var shell_row := HBoxContainer.new()
	shell_row.add_theme_constant_override("separation", 24)
	outer.add_child(shell_row)

	var nav_panel := PanelContainer.new()
	nav_panel.custom_minimum_size = Vector2(270, 0)
	nav_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.030, 0.045, 0.070, 0.98)))
	shell_row.add_child(nav_panel)

	var nav_margin := MarginContainer.new()
	nav_margin.add_theme_constant_override("margin_left", 20)
	nav_margin.add_theme_constant_override("margin_right", 20)
	nav_margin.add_theme_constant_override("margin_top", 22)
	nav_margin.add_theme_constant_override("margin_bottom", 22)
	nav_panel.add_child(nav_margin)

	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	nav_margin.add_child(nav)

	var title := Label.new()
	title.text = "DISTRIBUTED\nWORLD SIMULATOR"
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color(0.84, 0.93, 1.0))
	nav.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "UX0 Product Shell"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.44, 0.72, 0.92))
	nav.add_child(subtitle)

	nav.add_child(HSeparator.new())
	nav.add_child(_nav_button("Continue", Callable(self, "_on_continue_pressed")))
	nav.add_child(_nav_button("Host World", Callable(self, "_show_view").bind("host")))
	nav.add_child(_nav_button("Join World", Callable(self, "_show_view").bind("join")))
	nav.add_child(_nav_button("Settings", Callable(self, "_show_view").bind("settings")))
	nav.add_child(_nav_button("Developer", Callable(self, "_on_developer_pressed")))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	nav.add_child(_nav_button("Exit", Callable(get_tree(), "quit")))

	var content_panel := PanelContainer.new()
	content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.018, 0.026, 0.043, 0.97)))
	shell_row.add_child(content_panel)

	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 34)
	content_margin.add_theme_constant_override("margin_right", 34)
	content_margin.add_theme_constant_override("margin_top", 30)
	content_margin.add_theme_constant_override("margin_bottom", 24)
	content_panel.add_child(content_margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	content_margin.add_child(column)

	var header := Label.new()
	header.text = "Product launcher"
	header.add_theme_font_size_override("font_size", 28)
	column.add_child(header)

	var description := Label.new()
	description.text = "Запуск обычного client/server продукта без ручного CLI.\nCanonical gameplay и persistence остаются в существующих LIVE.2/LIVE.3 runtime."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color(0.68, 0.75, 0.84))
	column.add_child(description)

	column.add_child(HSeparator.new())

	var view_host := Control.new()
	view_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(view_host)
	_views = {
		"home": _build_home_view(view_host),
		"host": _build_host_view(view_host),
		"join": _build_join_view(view_host),
		"settings": _build_settings_view(view_host),
	}

	_status_label = Label.new()
	_status_label.text = "Готово"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color(0.55, 0.88, 0.68))
	column.add_child(HSeparator.new())
	column.add_child(_status_label)
	_refresh_from_preferences()


func _build_home_view(parent: Control) -> Control:
	var view := _new_view(parent, "HomeView")
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 14)
	view.add_child(column)

	var title := _view_title("Ready to play")
	column.add_child(title)
	_home_summary = Label.new()
	_home_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_home_summary)

	_continue_button = Button.new()
	_continue_button.text = "Continue last hosted world"
	_continue_button.custom_minimum_size = Vector2(0, 52)
	_continue_button.pressed.connect(_on_continue_pressed)
	column.add_child(_continue_button)

	var hint := Label.new()
	hint.text = "Host запускает отдельный dedicated-server process и обычный game-client process.\nJoin запускает только client. Launcher не владеет world state."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.62, 0.70, 0.80))
	column.add_child(hint)
	return view


func _build_host_view(parent: Control) -> Control:
	var view := _new_view(parent, "HostView")
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 12)
	view.add_child(column)
	column.add_child(_view_title("Host World"))
	column.add_child(_field_label("World"))
	var world := OptionButton.new()
	world.add_item("Earth")
	world.disabled = true
	column.add_child(world)
	column.add_child(_field_label("Player name"))
	_host_player = LineEdit.new()
	_host_player.placeholder_text = "player"
	column.add_child(_host_player)
	column.add_child(_field_label("Port"))
	_host_port = _port_spinbox()
	column.add_child(_host_port)
	column.add_child(_field_label("Persistence slot"))
	_host_slot = LineEdit.new()
	_host_slot.placeholder_text = DEFAULT_SLOT
	column.add_child(_host_slot)

	var explanation := Label.new()
	explanation.text = "Persistence slot maps to the existing LIVE.3 server recovery namespace. Клиент persistence root не получает."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.add_theme_color_override("font_color", Color(0.62, 0.70, 0.80))
	column.add_child(explanation)

	_host_start = Button.new()
	_host_start.text = "Host World"
	_host_start.custom_minimum_size = Vector2(0, 48)
	_host_start.pressed.connect(_on_host_pressed)
	column.add_child(_host_start)
	return view


func _build_join_view(parent: Control) -> Control:
	var view := _new_view(parent, "JoinView")
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 12)
	view.add_child(column)
	column.add_child(_view_title("Join World"))
	column.add_child(_field_label("Server address"))
	_join_address = LineEdit.new()
	_join_address.placeholder_text = "127.0.0.1"
	column.add_child(_join_address)
	column.add_child(_field_label("Port"))
	_join_port = _port_spinbox()
	column.add_child(_join_port)
	column.add_child(_field_label("Player name"))
	_join_player = LineEdit.new()
	_join_player.placeholder_text = "player"
	column.add_child(_join_player)

	_join_start = Button.new()
	_join_start.text = "Join"
	_join_start.custom_minimum_size = Vector2(0, 48)
	_join_start.pressed.connect(_on_join_pressed)
	column.add_child(_join_start)
	return view


func _build_settings_view(parent: Control) -> Control:
	var view := _new_view(parent, "SettingsView")
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 12)
	view.add_child(column)
	column.add_child(_view_title("Settings"))
	column.add_child(_field_label("Default player name"))
	_settings_player = LineEdit.new()
	column.add_child(_settings_player)
	column.add_child(_field_label("Default network port"))
	_settings_port = _port_spinbox()
	column.add_child(_settings_port)

	var note := Label.new()
	note.text = "UX0 R1 хранит только локальные launcher preferences. Gameplay state здесь не сохраняется."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color(0.62, 0.70, 0.80))
	column.add_child(note)

	var save := Button.new()
	save.text = "Save settings"
	save.pressed.connect(_on_settings_save_pressed)
	column.add_child(save)
	return view


func _new_view(parent: Control, node_name: String) -> Control:
	var view := Control.new()
	view.name = node_name
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(view)
	return view


func _nav_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 42)
	button.pressed.connect(callback)
	return button


func _view_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 23)
	return label


func _field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.76, 0.82, 0.90))
	return label


func _port_spinbox() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 65535
	spin.step = 1
	spin.value = DEFAULT_PORT
	return spin


func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.14, 0.31, 0.48, 0.85)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style


func _show_view(view_id: String) -> void:
	for key in _views:
		var view: Control = _views[key]
		view.visible = String(key) == view_id
	if view_id == "home":
		_refresh_from_preferences()


func _refresh_from_preferences() -> void:
	if _prefs.is_empty():
		return
	var player := String(_prefs.get("default_player_name", DEFAULT_PLAYER))
	var port := int(_prefs.get("default_port", DEFAULT_PORT))
	var address := String(_prefs.get("last_server_address", "127.0.0.1"))
	var slot := String(_prefs.get("last_persistence_slot", DEFAULT_SLOT))
	if _host_player != null:
		_host_player.text = player
		_host_port.value = port
		_host_slot.text = slot
	if _join_address != null:
		_join_address.text = address
		_join_port.value = port
		_join_player.text = player
	if _settings_player != null:
		_settings_player.text = player
		_settings_port.value = port
	if _continue_button != null:
		_continue_button.disabled = not bool(_prefs.get("has_host_history", false))
	if _home_summary != null:
		_home_summary.text = (
			"Последний hosted world: Earth · slot %s · port %d · player %s"
			% [slot, port, player]
			if bool(_prefs.get("has_host_history", false))
			else "Hosted world ещё не запускался. Выберите Host World."
		)


func _on_host_pressed() -> void:
	if _busy:
		return
	var port := int(_host_port.value)
	if not _udp_port_available(port):
		_set_status("Port %d уже занят. Host World не запущен." % port, false)
		return
	var slot := normalize_slug(_host_slot.text, DEFAULT_SLOT)
	var player := _host_player.text.strip_edges()
	if player.is_empty():
		player = DEFAULT_PLAYER
	_prefs["default_player_name"] = player.left(48)
	_prefs["default_port"] = port
	_prefs["last_server_address"] = "127.0.0.1"
	_prefs["last_hosted_world"] = DEFAULT_WORLD
	_prefs["last_persistence_slot"] = slot
	_prefs["has_host_history"] = true
	_prefs["last_mode"] = "host"
	_save_preferences()
	await _launch_host(DEFAULT_WORLD, port, slot, player, false)


func _on_continue_pressed() -> void:
	if _busy or not bool(_prefs.get("has_host_history", false)):
		return
	var port := int(_prefs.get("default_port", DEFAULT_PORT))
	var slot := String(_prefs.get("last_persistence_slot", DEFAULT_SLOT))
	var player := String(_prefs.get("default_player_name", DEFAULT_PLAYER))
	await _launch_host(DEFAULT_WORLD, port, slot, player, true)


func _launch_host(
	world_id: String,
	port: int,
	slot: String,
	player_name: String,
	allow_existing_server: bool
) -> void:
	_set_busy(true)
	var server_already_running := not _udp_port_available(port)
	if server_already_running and not allow_existing_server:
		_set_status("Port %d уже занят. Dedicated server не запущен." % port, false)
		_set_busy(false)
		return

	if not server_already_running:
		var server_result := _spawn_runtime(build_host_user_args(world_id, port, slot), true)
		if not bool(server_result.get("success", false)):
			_set_status("Не удалось запустить dedicated server: %s" % String(server_result.get("error_code", "UNKNOWN")), false)
			_set_busy(false)
			return
		_host_server_pid = int(server_result.get("pid", -1))
		_set_status("Dedicated server PID %d запускается…" % _host_server_pid, true)
		await get_tree().create_timer(0.65).timeout
	else:
		_set_status("Port %d уже занят: Continue подключается к существующему local server." % port, true)

	var client_result := _spawn_runtime(
		build_join_user_args("127.0.0.1", port, player_name),
		false
	)
	if not bool(client_result.get("success", false)):
		_set_status("Server запущен, но client не стартовал: %s" % String(client_result.get("error_code", "UNKNOWN")), false)
		_set_busy(false)
		return
	_host_client_pid = int(client_result.get("pid", -1))
	_set_status(
		"World запущен · server %s · client PID %d · slot %s"
		% [("existing" if server_already_running else str(_host_server_pid)), _host_client_pid, slot],
		true
	)
	_set_busy(false)
	_refresh_from_preferences()


func _on_join_pressed() -> void:
	if _busy:
		return
	var address := _join_address.text.strip_edges()
	if address.is_empty():
		_set_status("Укажите server address.", false)
		return
	var port := int(_join_port.value)
	var player := _join_player.text.strip_edges()
	if player.is_empty():
		player = DEFAULT_PLAYER
	_prefs["default_player_name"] = player.left(48)
	_prefs["default_port"] = port
	_prefs["last_server_address"] = address.left(255)
	_prefs["last_mode"] = "join"
	_save_preferences()

	var result := _spawn_runtime(build_join_user_args(address, port, player), false)
	if not bool(result.get("success", false)):
		_set_status("Не удалось запустить client: %s" % String(result.get("error_code", "UNKNOWN")), false)
		return
	var pid := int(result.get("pid", -1))
	_join_client_pids.append(pid)
	_set_status("Game client PID %d подключается к %s:%d" % [pid, address, port], true)
	_refresh_from_preferences()


func _on_settings_save_pressed() -> void:
	var player := _settings_player.text.strip_edges()
	if player.is_empty():
		player = DEFAULT_PLAYER
	_prefs["default_player_name"] = player.left(48)
	_prefs["default_port"] = int(_settings_port.value)
	_save_preferences()
	_refresh_from_preferences()
	_set_status("Launcher settings сохранены.", true)


func _on_developer_pressed() -> void:
	if _busy:
		return
	var result := _spawn_runtime(PackedStringArray([
		"--role=listen-host",
		"--world=earth_moon",
		"--node-id=ux0-developer",
	]), false)
	if bool(result.get("success", false)):
		_set_status("Developer runtime PID %d запущен." % int(result.get("pid", -1)), true)
	else:
		_set_status("Developer runtime не запущен.", false)


func _spawn_runtime(user_args: PackedStringArray, headless: bool) -> Dictionary:
	var executable := OS.get_executable_path()
	if executable.strip_edges().is_empty():
		return {"success": false, "error_code": "UX0_EXECUTABLE_PATH_MISSING"}
	var editor_runtime := OS.has_feature("editor")
	var project_path := ProjectSettings.globalize_path("res://")
	var arguments := build_child_process_args(user_args, editor_runtime, project_path, headless)
	var pid := OS.create_process(executable, arguments, false)
	if pid <= 0:
		return {
			"success": false,
			"error_code": "UX0_PROCESS_CREATE_FAILED",
			"details": {"executable": executable, "arguments": Array(arguments)},
		}
	return {
		"success": true,
		"error_code": "",
		"pid": pid,
		"details": {"executable": executable, "arguments": Array(arguments)},
	}


func _udp_port_available(port: int) -> bool:
	var probe := PacketPeerUDP.new()
	var error := probe.bind(port, "127.0.0.1")
	probe.close()
	return error == OK


func _load_preferences() -> Dictionary:
	if not FileAccess.file_exists(PREFS_PATH):
		return default_preferences()
	var file := FileAccess.open(PREFS_PATH, FileAccess.READ)
	if file == null:
		return default_preferences()
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return default_preferences()
	return normalize_preferences(Dictionary(parsed))


func _save_preferences() -> void:
	_prefs = normalize_preferences(_prefs)
	var file := FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if file == null:
		_set_status("Не удалось сохранить launcher preferences.", false)
		return
	file.store_string(JSON.stringify(_prefs, "  "))


func _set_busy(value: bool) -> void:
	_busy = value
	if _host_start != null:
		_host_start.disabled = value
	if _join_start != null:
		_join_start.disabled = value


func _set_status(text: String, success: bool) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.add_theme_color_override(
		"font_color",
		Color(0.55, 0.88, 0.68) if success else Color(1.0, 0.50, 0.42)
	)
