extends CanvasLayer

const SCHEMA := "dws.user1.journey.v1"
const STATE_SCHEMA := "dws.user1.journey_state.v1"
const SAVE_ROOT := "user://v0-live/user1"
const REFRESH_INTERVAL_MSEC := 250
const MOVE_COMPLETE_DISTANCE_M := 1.0
const RESOURCE_NEAR_DISTANCE_M := 4.8

const STEP_DEFINITIONS: Array[Dictionary] = [
	{"id": "connected", "title": "Подключиться к миру"},
	{"id": "second_player", "title": "Увидеть второго игрока"},
	{"id": "move", "title": "Пройтись обычным WASD"},
	{"id": "seam", "title": "Пересечь seam / сменить region"},
	{"id": "resource_near", "title": "Найти ресурс"},
	{"id": "tool_equipped", "title": "Экипировать mining tool"},
	{"id": "mined", "title": "Добыть руду"},
	{"id": "material_received", "title": "Получить canonical material"},
	{"id": "pickup_drop", "title": "Подобрать и выбросить предмет"},
	{"id": "container_open", "title": "Открыть shared container"},
	{"id": "container_share", "title": "Перенести предмет в shared container"},
	{"id": "construction", "title": "Построить canonical объект"},
	{"id": "client_reconnect", "title": "Перезапустить этот client и продолжить"},
	{"id": "server_restart", "title": "Перезапустить server/world и продолжить"},
]

var _state_provider := Callable()
var _root: Control
var _panel: PanelContainer
var _progress_label: Label
var _next_label: Label
var _detail_label: Label
var _step_labels: Dictionary = {}
var _completed: Dictionary = {}
var _player_id := ""
var _save_path := ""
var _initialized := false
var _initial_position := Vector2.ZERO
var _initial_region_id := ""
var _initial_resource_generation := -1
var _initial_ore_quantity := -1
var _initial_world_item_count := -1
var _initial_container_item_count := -1
var _initial_construction_generation := -1
var _initial_ownership_epoch := -1
var _first_process_id := -1
var _last_process_id := -1
var _pickup_seen := false
var _outage_seen := false
var _previous_connection_state := ""
var _refresh_at_msec := 0
var _last_state: Dictionary = {}


func setup(state_provider: Callable) -> Dictionary:
	if not state_provider.is_valid():
		return {"success": false, "error_code": "USER1_STATE_PROVIDER_REQUIRED"}
	_state_provider = state_provider
	layer = 91
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	set_process(true)
	return {"success": true, "error_code": ""}


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"player_id": _player_id,
		"save_path": _save_path,
		"initialized": _initialized,
		"completed": _completed.duplicate(true),
		"completed_count": _completed_count(),
		"step_count": STEP_DEFINITIONS.size(),
		"next_step_id": _next_step_id(),
		"first_process_id": _first_process_id,
		"last_process_id": _last_process_id,
		"outage_seen": _outage_seen,
		"last_state": _last_state.duplicate(true),
	}


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now < _refresh_at_msec:
		return
	_refresh_at_msec = now + REFRESH_INTERVAL_MSEC
	var value = _state_provider.call()
	if not value is Dictionary:
		return
	var state: Dictionary = Dictionary(value).duplicate(true)
	if String(state.get("schema", "")) != STATE_SCHEMA:
		return
	_last_state = state
	_accept_state(state)
	_render(state)


func _accept_state(state: Dictionary) -> void:
	var player_id := String(state.get("player_id", "")).strip_edges().to_lower()
	if player_id.is_empty():
		return
	if player_id != _player_id:
		_player_id = player_id
		_save_path = _save_path_for_player(player_id)
		_initialized = false
	if not _initialized:
		if not _baseline_ready(state):
			return
		_load_or_initialize(state)
	if not _initialized:
		return

	var connection_state := String(state.get("connection_state", "")).strip_edges().to_upper()
	if connection_state == "CONNECTED":
		_complete("connected")
	if int(state.get("remote_player_count", 0)) > 0:
		_complete("second_player")

	var position: Dictionary = Dictionary(state.get("position", {}))
	var current_position := Vector2(
		float(position.get("x", 0.0)),
		float(position.get("z", 0.0))
	)
	if current_position.distance_to(_initial_position) >= MOVE_COMPLETE_DISTANCE_M:
		_complete("move")

	var region_id := String(state.get("region_id", "")).strip_edges()
	if (
		not _initial_region_id.is_empty()
		and not region_id.is_empty()
		and region_id != _initial_region_id
	):
		_complete("seam")

	var resource_distance := float(state.get("nearest_resource_distance_m", INF))
	if _finite(resource_distance) and resource_distance <= RESOURCE_NEAR_DISTANCE_M:
		_complete("resource_near")
	if bool(state.get("mining_tool_equipped", false)):
		_complete("tool_equipped")

	var resource_generation := int(state.get("resource_generation", -1))
	if (
		_initial_resource_generation >= 0
		and resource_generation > _initial_resource_generation
	):
		_complete("mined")

	var ore_quantity := int(state.get("inventory_ore_quantity", 0))
	if _initial_ore_quantity >= 0 and ore_quantity > _initial_ore_quantity:
		_complete("material_received")

	var world_item_count := int(state.get("world_item_count", -1))
	if _initial_world_item_count >= 0 and world_item_count >= 0:
		if world_item_count < _initial_world_item_count:
			_pickup_seen = true
		if _pickup_seen and world_item_count >= _initial_world_item_count:
			_complete("pickup_drop")

	if not String(state.get("open_container_id", "")).is_empty():
		_complete("container_open")
	var container_count := int(state.get("shared_container_item_count", -1))
	if (
		_initial_container_item_count >= 0
		and container_count > _initial_container_item_count
	):
		_complete("container_share")

	var construction_generation := int(state.get("construction_generation", -1))
	if (
		_initial_construction_generation >= 0
		and construction_generation > _initial_construction_generation
	):
		_complete("construction")

	var current_process_id := OS.get_process_id()
	if (
		_first_process_id > 0
		and current_process_id != _first_process_id
		and bool(_completed.get("construction", false))
		and connection_state == "CONNECTED"
	):
		_complete("client_reconnect")

	if (
		_previous_connection_state == "CONNECTED"
		and connection_state in ["RECONNECTING", "CONNECTING", "DISCONNECTED"]
	):
		_outage_seen = true
	if (
		_outage_seen
		and bool(_completed.get("client_reconnect", false))
		and connection_state == "CONNECTED"
	):
		_complete("server_restart")

	_previous_connection_state = connection_state
	_last_process_id = current_process_id
	_save_progress()


func _load_or_initialize(state: Dictionary) -> void:
	_completed.clear()
	_pickup_seen = false
	_outage_seen = false
	_previous_connection_state = ""
	var loaded := false
	if FileAccess.file_exists(_save_path):
		var file := FileAccess.open(_save_path, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				loaded = _restore_progress(Dictionary(parsed))
	if not loaded:
		var position: Dictionary = Dictionary(state.get("position", {}))
		_initial_position = Vector2(
			float(position.get("x", 0.0)),
			float(position.get("z", 0.0))
		)
		_initial_region_id = String(state.get("region_id", "")).strip_edges()
		_initial_resource_generation = int(state.get("resource_generation", -1))
		_initial_ore_quantity = int(state.get("inventory_ore_quantity", 0))
		_initial_world_item_count = int(state.get("world_item_count", -1))
		_initial_container_item_count = int(state.get("shared_container_item_count", -1))
		_initial_construction_generation = int(state.get("construction_generation", -1))
		_initial_ownership_epoch = int(state.get("ownership_epoch", -1))
		_first_process_id = OS.get_process_id()
		_last_process_id = _first_process_id
	_initialized = true
	_save_progress()


func _restore_progress(value: Dictionary) -> bool:
	if (
		String(value.get("schema", "")) != SCHEMA
		or String(value.get("player_id", "")) != _player_id
	):
		return false
	var baselines: Dictionary = Dictionary(value.get("baselines", {}))
	var initial_position: Array = Array(baselines.get("position", []))
	if initial_position.size() != 2:
		return false
	_initial_position = Vector2(float(initial_position[0]), float(initial_position[1]))
	_initial_region_id = String(baselines.get("region_id", ""))
	_initial_resource_generation = int(baselines.get("resource_generation", -1))
	_initial_ore_quantity = int(baselines.get("ore_quantity", 0))
	_initial_world_item_count = int(baselines.get("world_item_count", -1))
	_initial_container_item_count = int(baselines.get("container_item_count", -1))
	_initial_construction_generation = int(baselines.get("construction_generation", -1))
	_initial_ownership_epoch = int(baselines.get("ownership_epoch", -1))
	_first_process_id = int(value.get("first_process_id", -1))
	_last_process_id = int(value.get("last_process_id", _first_process_id))
	_completed = Dictionary(value.get("completed", {})).duplicate(true)
	_pickup_seen = bool(value.get("pickup_seen", false))
	_initialized = true
	return true


func _save_progress() -> void:
	if not _initialized or _save_path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_ROOT))
	var file := FileAccess.open(_save_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"schema": SCHEMA,
		"player_id": _player_id,
		"first_process_id": _first_process_id,
		"last_process_id": _last_process_id,
		"completed": _completed.duplicate(true),
		"pickup_seen": _pickup_seen,
		"baselines": {
			"position": [_initial_position.x, _initial_position.y],
			"region_id": _initial_region_id,
			"resource_generation": _initial_resource_generation,
			"ore_quantity": _initial_ore_quantity,
			"world_item_count": _initial_world_item_count,
			"container_item_count": _initial_container_item_count,
			"construction_generation": _initial_construction_generation,
			"ownership_epoch": _initial_ownership_epoch,
		},
	}, "  "))


func _complete(step_id: String) -> void:
	if bool(_completed.get(step_id, false)):
		return
	_completed[step_id] = true


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "USER1JourneyRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.name = "USER1JourneyPanel"
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.offset_left = 18.0
	_panel.offset_right = 455.0
	_panel.offset_top = 106.0
	_panel.offset_bottom = 580.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.028, 0.045, 0.90)
	style.border_color = Color(0.18, 0.48, 0.72, 0.75)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	_panel.add_theme_stylebox_override("panel", style)
	_root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)

	var title := Label.new()
	title.text = "USER1 · FIRST USABLE SESSION"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(0.82, 0.93, 1.0))
	column.add_child(title)

	_progress_label = Label.new()
	_progress_label.add_theme_color_override("font_color", Color(0.55, 0.80, 0.98))
	column.add_child(_progress_label)
	column.add_child(HSeparator.new())

	for definition in STEP_DEFINITIONS:
		var label := Label.new()
		label.text = String(definition.get("title", ""))
		label.add_theme_font_size_override("font_size", 13)
		label.clip_text = true
		column.add_child(label)
		_step_labels[String(definition.get("id", ""))] = label

	column.add_child(HSeparator.new())
	_next_label = Label.new()
	_next_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_next_label.add_theme_font_size_override("font_size", 14)
	_next_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.48))
	column.add_child(_next_label)

	_detail_label = Label.new()
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.add_theme_font_size_override("font_size", 12)
	_detail_label.add_theme_color_override("font_color", Color(0.67, 0.74, 0.83))
	column.add_child(_detail_label)


func _render(state: Dictionary) -> void:
	if _panel != null:
		_panel.visible = not bool(state.get("inventory_visible", false))
	var completed_count := _completed_count()
	_progress_label.text = "%d / %d шагов" % [completed_count, STEP_DEFINITIONS.size()]
	for definition in STEP_DEFINITIONS:
		var step_id := String(definition.get("id", ""))
		var label: Label = _step_labels.get(step_id)
		if label == null:
			continue
		var completed := bool(_completed.get(step_id, false))
		label.text = "%s %s" % [
			"✓" if completed else "○",
			String(definition.get("title", "")),
		]
		label.add_theme_color_override(
			"font_color",
			Color(0.48, 0.92, 0.58) if completed else Color(0.73, 0.79, 0.87)
		)
	var next_step := _next_step_id()
	_next_label.text = (
		"Готово: vertical slice пройден."
		if next_step.is_empty()
		else "Следующий шаг: %s" % _instruction_for(next_step, state)
	)
	_detail_label.text = _detail_for_state(state)


func _instruction_for(step_id: String, state: Dictionary) -> String:
	match step_id:
		"connected":
			return "дождитесь CONNECTED."
		"second_player":
			return "подключите второй client через Join World."
		"move":
			return "WASD + мышь; пройдите хотя бы метр."
		"seam":
			return "двигайтесь через границу region; текущий region: %s." % String(state.get("region_id", "?"))
		"resource_near":
			var distance := float(state.get("nearest_resource_distance_m", INF))
			return (
				"найдите ресурс; ближайший примерно %.1f м." % distance
				if is_finite(distance)
				else "найдите видимый ore resource."
			)
		"tool_equipped":
			return "нажмите Q или выберите Mining Tool."
		"mined":
			return "наведите прицел на ресурс и нажмите LMB/E."
		"material_received":
			return "дождитесь server confirmation: item/ore появится в inventory."
		"pickup_drop":
			return "подберите world item через E, затем выбросьте его через G."
		"container_open":
			return "подойдите к crate и нажмите E."
		"container_share":
			return "в открытом inventory перенесите item в shared crate."
		"construction":
			return "используйте B/LMB или кнопку Construction, чтобы создать объект."
		"client_reconnect":
			return "закройте этот client и снова Join с тем же player name."
		"server_restart":
			return "перезапустите Host/server с тем же persistence slot и дождитесь reconnect."
	return step_id


func _detail_for_state(state: Dictionary) -> String:
	var distance := float(state.get("nearest_resource_distance_m", INF))
	var resource_text := "%.1f m" % distance if is_finite(distance) else "—"
	return "player %s · region %s · ore %d · resource %s · construct gen %d" % [
		String(state.get("player_id", "—")),
		String(state.get("region_id", "—")),
		int(state.get("inventory_ore_quantity", 0)),
		resource_text,
		int(state.get("construction_generation", -1)),
	]


func _baseline_ready(state: Dictionary) -> bool:
	return (
		String(state.get("connection_state", "")).strip_edges().to_upper() == "CONNECTED"
		and not String(state.get("player_id", "")).strip_edges().is_empty()
		and int(state.get("ownership_epoch", 0)) > 0
		and not String(state.get("region_id", "")).strip_edges().is_empty()
		and int(state.get("resource_generation", -1)) >= 0
		and int(state.get("item_graph_revision", -1)) >= 0
		and int(state.get("world_item_count", -1)) >= 0
		and int(state.get("shared_container_item_count", -1)) >= 0
		and int(state.get("construction_generation", -1)) >= 0
	)


func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


func _completed_count() -> int:
	var count := 0
	for definition in STEP_DEFINITIONS:
		if bool(_completed.get(String(definition.get("id", "")), false)):
			count += 1
	return count


func _next_step_id() -> String:
	for definition in STEP_DEFINITIONS:
		var step_id := String(definition.get("id", ""))
		if not bool(_completed.get(step_id, false)):
			return step_id
	return ""


func _save_path_for_player(player_id: String) -> String:
	var key := player_id.sha256_text().left(20)
	return "%s/%s.json" % [SAVE_ROOT, key]
