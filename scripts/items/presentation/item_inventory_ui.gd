extends CanvasLayer

const CONFIG_PATH: String = "res://config/ui/inventory_ui.json"
const COMPONENT_IMPLEMENTATION: String = "component"
const LEGACY_IMPLEMENTATION: String = "legacy"
const ComponentScreenScene = preload("res://scenes/ui/inventory/inventory_screen.tscn")
const LegacyScreen = preload("res://scripts/items/presentation/legacy_item_inventory_screen.gd")
const ViewModel = preload("res://scripts/ui/inventory/inventory_view_model.gd")
const CommandFacade = preload("res://scripts/ui/inventory/inventory_command_facade.gd")
const HotbarPanelScene = preload("res://scenes/ui/inventory/hotbar_panel.tscn")

var gameplay_controller
var active_screen
var implementation_id: String = COMPONENT_IMPLEMENTATION
var view_model
var command_facade
var persistent_hotbar

var external_container_id: String:
	get:
		return String(active_screen.external_container_id) if active_screen != null else ""

var external_section: Control:
	get:
		if active_screen == null:
			return null
		if implementation_id == COMPONENT_IMPLEMENTATION:
			return active_screen.external_panel
		return active_screen.external_section

var external_title: Label:
	get:
		if active_screen == null:
			return null
		if implementation_id == COMPONENT_IMPLEMENTATION:
			return active_screen.compatibility_external_title
		return active_screen.external_title

var hotbar_grid: GridContainer:
	get:
		if active_screen == null:
			return null
		if implementation_id == COMPONENT_IMPLEMENTATION:
			return active_screen.hotbar_panel.grid
		return active_screen.hotbar_grid

var quantity_popup: PopupPanel:
	get:
		if active_screen == null:
			return null
		if implementation_id == COMPONENT_IMPLEMENTATION:
			return active_screen.split_dialog
		return active_screen.quantity_popup

var quantity_spin: SpinBox:
	get:
		if active_screen == null:
			return null
		if implementation_id == COMPONENT_IMPLEMENTATION:
			return active_screen.split_dialog.quantity_spin
		return active_screen.quantity_spin

var pending_item_id: String:
	get:
		return String(active_screen.pending_item_id) if active_screen != null else ""

var pending_target_container_id: String:
	get:
		return String(active_screen.pending_target_container_id) if active_screen != null else ""

var pending_target_slot_index: int:
	get:
		return int(active_screen.pending_target_slot_index) if active_screen != null else -1

var pending_target_item_id: String:
	get:
		return String(active_screen.pending_target_item_id) if active_screen != null else ""

var pending_total_quantity: int:
	get:
		return int(active_screen.pending_total_quantity) if active_screen != null else 0


func setup(controller, implementation_override: String = "") -> void:
	gameplay_controller = controller
	implementation_id = _resolve_implementation(implementation_override)
	if implementation_id == COMPONENT_IMPLEMENTATION:
		view_model = ViewModel.new()
		command_facade = CommandFacade.new()
		active_screen = ComponentScreenScene.instantiate()
		add_child(active_screen)
		active_screen.setup(controller, view_model, command_facade)
		_setup_persistent_hotbar()
		return
	active_screen = LegacyScreen.new()
	add_child(active_screen)
	active_screen.setup(controller)


func set_inventory_visible(value: bool) -> void:
	if active_screen != null:
		active_screen.set_inventory_visible(value)
	_refresh_persistent_hotbar()


func is_inventory_visible() -> bool:
	return bool(active_screen.is_inventory_visible()) if active_screen != null else false


func open_external_container(container_id: String) -> void:
	if active_screen != null:
		active_screen.open_external_container(container_id)
	_refresh_persistent_hotbar()


func close_external_container(refresh_now: bool = true) -> void:
	if active_screen != null:
		active_screen.close_external_container(refresh_now)
	_refresh_persistent_hotbar()


func refresh(message: String = "") -> void:
	if active_screen != null:
		active_screen.refresh(message)
	_refresh_persistent_hotbar()


func _setup_persistent_hotbar() -> void:
	if implementation_id != COMPONENT_IMPLEMENTATION or active_screen == null:
		return
	persistent_hotbar = HotbarPanelScene.instantiate()
	persistent_hotbar.name = "PersistentHotbar"
	persistent_hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	persistent_hotbar.offset_left = -390.0
	persistent_hotbar.offset_top = -94.0
	persistent_hotbar.offset_right = 390.0
	persistent_hotbar.offset_bottom = -16.0
	persistent_hotbar.custom_minimum_size = Vector2(780.0, 72.0)
	persistent_hotbar.set_visual_role("hotbar")
	persistent_hotbar.drop_requested.connect(_on_drop_requested)
	persistent_hotbar.quantity_drop_requested.connect(_on_quantity_drop_requested)
	persistent_hotbar.activated.connect(func(item_id: String, container_id: String, slot_index: int) -> void:
		if active_screen != null:
			active_screen._on_slot_activated(item_id, container_id, slot_index)
	)
	add_child(persistent_hotbar)
	_refresh_persistent_hotbar()


func _refresh_persistent_hotbar() -> void:
	if persistent_hotbar != null and active_screen != null and active_screen.has_method("render_persistent_hotbar"):
		active_screen.render_persistent_hotbar(persistent_hotbar)


func get_external_visible_cell_count() -> int:
	return int(active_screen.get_external_visible_cell_count()) if active_screen != null else 0


func get_external_rendered_cell_count() -> int:
	if active_screen == null:
		return 0
	if active_screen.has_method("get_external_rendered_cell_count"):
		return int(active_screen.get_external_rendered_cell_count())
	return get_external_visible_cell_count()


func get_implementation_id() -> String:
	return implementation_id


func using_component_screen() -> bool:
	return implementation_id == COMPONENT_IMPLEMENTATION


func create_debug_snapshot() -> Dictionary:
	if active_screen != null and active_screen.has_method("create_debug_snapshot"):
		return active_screen.create_debug_snapshot()
	return {
		"schema": "planet_simulator.inventory_screen_debug.v1",
		"implementation": implementation_id,
		"visible": is_inventory_visible(),
		"external_container_id": external_container_id,
	}


func _on_drop_requested(
	item_id: String,
	target_container_id: String,
	target_slot_index: int,
	quantity: int = -1,
	target_item_id: String = ""
) -> void:
	if active_screen != null:
		active_screen._on_drop_requested(
			item_id,
			target_container_id,
			target_slot_index,
			quantity,
			target_item_id
		)


func _on_quantity_drop_requested(
	item_id: String,
	target_container_id: String,
	target_slot_index: int,
	total_quantity: int,
	target_item_id: String
) -> void:
	if active_screen != null:
		active_screen._on_quantity_drop_requested(
			item_id,
			target_container_id,
			target_slot_index,
			total_quantity,
			target_item_id
		)


func _on_quantity_confirmed() -> void:
	if active_screen != null:
		active_screen._on_quantity_confirmed()


func _on_quantity_cancelled() -> void:
	if active_screen == null:
		return
	if active_screen.has_method("_on_quantity_cancelled"):
		active_screen._on_quantity_cancelled()
	elif active_screen.has_method("_on_split_cancelled"):
		active_screen._on_split_cancelled()


func _resolve_implementation(implementation_override: String) -> String:
	var requested := implementation_override.strip_edges().to_lower()
	if requested.is_empty():
		requested = OS.get_environment("PLANET_SIMULATOR_INVENTORY_UI").strip_edges().to_lower()
	if requested.is_empty():
		requested = _implementation_from_config()
	if requested not in [COMPONENT_IMPLEMENTATION, LEGACY_IMPLEMENTATION]:
		requested = COMPONENT_IMPLEMENTATION
	return requested


func _implementation_from_config() -> String:
	if not FileAccess.file_exists(CONFIG_PATH):
		return COMPONENT_IMPLEMENTATION
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return COMPONENT_IMPLEMENTATION
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return COMPONENT_IMPLEMENTATION
	return String(parsed.get("implementation", COMPONENT_IMPLEMENTATION)).strip_edges().to_lower()
