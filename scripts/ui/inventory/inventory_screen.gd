class_name InventoryScreen
extends PanelContainer

@onready var columns: HBoxContainer = %Columns
@onready var player_panel: InventoryContainerPanel = %PlayerPanel
@onready var external_panel: InventoryContainerPanel = %ExternalPanel
@onready var hotbar_panel: InventoryHotbarPanel = %HotbarPanel
@onready var status_label: Label = %StatusLabel
@onready var split_dialog: InventoryStackSplitDialog = %StackSplitDialog
@onready var toast_layer: InventoryToastLayer = %ToastLayer
@onready var tooltip: InventoryItemTooltip = %ItemTooltip
@onready var context_menu: InventoryItemContextMenu = %ItemContextMenu

var gameplay_controller
var view_model: InventoryViewModel
var command_facade: InventoryCommandFacade
var visible_inventory: bool = false
var external_container_id: String = ""
var icon_cache: Dictionary = {}
var pending_item_id: String = ""
var pending_target_container_id: String = ""
var pending_target_slot_index: int = -1
var pending_target_item_id: String = ""
var pending_total_quantity: int = 0
var compatibility_external_title: Label


func setup(controller, model: InventoryViewModel, commands: InventoryCommandFacade) -> void:
	compatibility_external_title = Label.new()
	compatibility_external_title.name = "CompatibilityExternalTitle"
	compatibility_external_title.visible = false
	add_child(compatibility_external_title)
	gameplay_controller = controller
	view_model = model
	command_facade = commands
	view_model.setup(controller)
	command_facade.setup(controller)
	player_panel.drop_requested.connect(_on_drop_requested)
	player_panel.quantity_drop_requested.connect(_on_quantity_drop_requested)
	player_panel.activated.connect(_on_slot_activated)
	external_panel.drop_requested.connect(_on_drop_requested)
	external_panel.quantity_drop_requested.connect(_on_quantity_drop_requested)
	external_panel.activated.connect(_on_slot_activated)
	hotbar_panel.drop_requested.connect(_on_drop_requested)
	hotbar_panel.quantity_drop_requested.connect(_on_quantity_drop_requested)
	hotbar_panel.activated.connect(_on_slot_activated)
	split_dialog.transfer_confirmed.connect(_on_split_confirmed)
	split_dialog.transfer_cancelled.connect(_on_split_cancelled)
	set_inventory_visible(false)
	refresh()


func set_inventory_visible(value: bool) -> void:
	visible_inventory = value
	visible = value
	if value:
		_recenter_panel()
	else:
		split_dialog.hide()
		_clear_pending_quantity_drop()


func is_inventory_visible() -> bool:
	return visible_inventory


func _input(event: InputEvent) -> void:
	if not visible_inventory:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if split_dialog.visible:
			split_dialog.cancel()
		else:
			gameplay_controller.set_inventory_visible(false)
		get_viewport().set_input_as_handled()


func open_external_container(container_id: String) -> void:
	external_container_id = container_id
	set_inventory_visible(true)
	refresh()


func close_external_container(refresh_now: bool = true) -> void:
	external_container_id = ""
	external_panel.clear_panel()
	if refresh_now:
		refresh()


func refresh(message: String = "") -> void:
	if gameplay_controller == null or view_model == null:
		return
	var screen_model: Dictionary = view_model.build_screen(external_container_id)
	var player_model: Dictionary = Dictionary(screen_model.get("player", {}))
	var hotbar_model: Dictionary = Dictionary(screen_model.get("hotbar", {}))
	player_panel.render(player_model, Callable(self, "_icon_for_cell"), Callable(command_facade, "preview_transfer"))
	hotbar_panel.render_hotbar(hotbar_model, Callable(self, "_icon_for_cell"), Callable(command_facade, "preview_transfer"))
	var external_model: Dictionary = Dictionary(screen_model.get("external", {}))
	if external_container_id.is_empty() or external_model.is_empty():
		external_panel.clear_panel()
		compatibility_external_title.text = ""
		_apply_panel_size(false, 0)
	else:
		external_panel.render(external_model, Callable(self, "_icon_for_cell"), Callable(command_facade, "preview_transfer"))
		compatibility_external_title.text = "%s\n%s" % [external_panel.title_label.text, external_panel.metadata_label.text]
		_apply_panel_size(true, int(external_model.get("columns", 4)))
	if not message.is_empty():
		status_label.text = message
		toast_layer.show_message(message)
	set_meta("inventory_screen_model", screen_model.duplicate(true))


func get_external_visible_cell_count() -> int:
	return external_panel.get_visual_cell_count()


func get_external_rendered_cell_count() -> int:
	return external_panel.get_rendered_cell_count()


func create_debug_snapshot() -> Dictionary:
	return {
		"schema": "planet_simulator.inventory_screen_debug.v1",
		"implementation": "component",
		"visible": visible_inventory,
		"external_container_id": external_container_id,
		"player": player_panel.current_model.duplicate(true),
		"external": external_panel.current_model.duplicate(true),
		"hotbar": hotbar_panel.current_model.duplicate(true),
	}


func _on_quantity_drop_requested(
	item_id: String,
	target_container_id: String,
	target_slot_index: int,
	total_quantity: int,
	target_item_id: String
) -> void:
	var preview: Dictionary = command_facade.preview_transfer(
		item_id,
		total_quantity,
		target_container_id,
		target_slot_index,
		target_item_id
	)
	if not bool(preview.get("success", false)):
		refresh(command_facade.result_message(preview))
		return
	pending_item_id = item_id
	pending_target_container_id = target_container_id
	pending_target_slot_index = target_slot_index
	pending_target_item_id = target_item_id
	pending_total_quantity = mini(
		maxi(1, total_quantity),
		maxi(1, int(preview.get("maximum_quantity", total_quantity)))
	)
	var item = gameplay_controller.get_item(item_id)
	var definition = gameplay_controller.get_definition(item.definition_id) if item != null else null
	var display_name: String = String(item.display_name) if item != null and not String(item.display_name).is_empty() else (String(definition.display_name) if definition != null else "Предмет")
	split_dialog.open_request(
		item_id,
		pending_total_quantity,
		target_container_id,
		target_slot_index,
		target_item_id,
		display_name,
		gameplay_controller.get_container_display_name(target_container_id)
	)


func _on_drop_requested(
	item_id: String,
	target_container_id: String,
	target_slot_index: int,
	quantity: int = -1,
	target_item_id: String = ""
) -> void:
	var result: Dictionary = command_facade.transfer_quantity(
		item_id,
		quantity,
		target_container_id,
		target_slot_index,
		target_item_id
	)
	refresh(command_facade.result_message(result))


func _on_split_confirmed(
	item_id: String,
	quantity: int,
	target_container_id: String,
	target_slot_index: int,
	target_item_id: String
) -> void:
	var result: Dictionary = command_facade.transfer_quantity(
		item_id,
		quantity,
		target_container_id,
		target_slot_index,
		target_item_id
	)
	_clear_pending_quantity_drop()
	refresh(command_facade.result_message(result))
	call_deferred("_restore_inventory_focus")


func _on_split_cancelled() -> void:
	_clear_pending_quantity_drop()
	call_deferred("_restore_inventory_focus")


func _on_quantity_confirmed() -> void:
	if split_dialog == null:
		return
	var item_id := pending_item_id
	var quantity := int(split_dialog.quantity_spin.value)
	var target_container_id := pending_target_container_id
	var target_slot_index := pending_target_slot_index
	var target_item_id := pending_target_item_id
	split_dialog.hide()
	split_dialog.clear_request()
	_on_split_confirmed(item_id, quantity, target_container_id, target_slot_index, target_item_id)


func _on_slot_activated(item_id: String, container_id: String, slot_index: int) -> void:
	if container_id == gameplay_controller.player_hotbar_id and slot_index >= 0:
		var result: Dictionary = command_facade.select_hotbar(slot_index)
		refresh(command_facade.result_message(result))
	elif not item_id.is_empty() and container_id == external_container_id:
		var result: Dictionary = command_facade.transfer_stack(item_id, gameplay_controller.player_inventory_id)
		refresh(command_facade.result_message(result))


func _clear_pending_quantity_drop() -> void:
	pending_item_id = ""
	pending_target_container_id = ""
	pending_target_slot_index = -1
	pending_target_item_id = ""
	pending_total_quantity = 0


func _icon_for_cell(cell_data: Dictionary) -> Texture2D:
	var key := String(cell_data.get("definition_id", "empty"))
	if key.is_empty():
		key = "empty"
	if icon_cache.has(key):
		return icon_cache[key]
	var color := Color(0.16, 0.18, 0.22, 0.8)
	var values = cell_data.get("icon_color", [])
	if values is Array and values.size() >= 3:
		color = Color(float(values[0]), float(values[1]), float(values[2]), 1.0)
	var image := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	image.fill(color)
	for x in range(48):
		image.set_pixel(x, 0, Color.WHITE)
		image.set_pixel(x, 47, Color.WHITE)
	for y in range(48):
		image.set_pixel(0, y, Color.WHITE)
		image.set_pixel(47, y, Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	icon_cache[key] = texture
	return texture


func _apply_panel_size(has_external: bool, external_columns: int) -> void:
	var width := 800.0
	if has_external:
		width = minf(1240.0, 800.0 + maxf(310.0, external_columns * 76.0))
	var panel_size := Vector2(width, 600.0)
	custom_minimum_size = panel_size
	size = panel_size
	_recenter_panel()


func _recenter_panel() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	position = (viewport.get_visible_rect().size - size) * 0.5


func _restore_inventory_focus() -> void:
	if not visible_inventory:
		return
	focus_mode = Control.FOCUS_ALL
	grab_focus()
