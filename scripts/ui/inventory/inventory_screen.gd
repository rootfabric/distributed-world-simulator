class_name InventoryScreen
extends PanelContainer

const InteractionProfileLoader = preload("res://scripts/ui/inventory/interactions/inventory_interaction_profile_loader.gd")
const TransferSession = preload("res://scripts/ui/inventory/interactions/inventory_transfer_session.gd")
const SlotProjection = preload("res://scripts/ui/inventory/interactions/inventory_slot_projection.gd")
const CursorController = preload("res://scripts/ui/inventory/interactions/inventory_cursor_controller.gd")
const SlotModeAdapter = preload("res://scripts/ui/inventory/interactions/inventory_slot_mode_adapter.gd")

@onready var columns: HBoxContainer = %Columns
@onready var player_panel: InventoryContainerPanel = %PlayerPanel
@onready var external_panel: InventoryContainerPanel = %ExternalPanel
@onready var hotbar_panel: InventoryHotbarPanel = %HotbarPanel
@onready var status_label: Label = %StatusLabel
@onready var split_dialog: InventoryStackSplitDialog = %StackSplitDialog
@onready var toast_layer: InventoryToastLayer = %ToastLayer
@onready var tooltip: InventoryItemTooltip = %ItemTooltip
@onready var context_menu: InventoryItemContextMenu = %ItemContextMenu
@onready var search_edit: LineEdit = %SearchEdit
@onready var filter_option: OptionButton = %FilterOption
@onready var sort_option: OptionButton = %SortOption
@onready var interaction_profile_option: OptionButton = %InteractionProfileOption
@onready var reset_projection_button: Button = %ResetProjectionButton
@onready var inspector_toggle: CheckButton = %InspectorToggle
@onready var projection_summary: Label = %ProjectionSummary
@onready var inspector: InventoryInspector = %Inspector

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
var pending_quantity_operation: String = "TRANSFER_TO_TARGET"
var compatibility_external_title: Label
var _context_screen_position: Vector2 = Vector2.ZERO
var preferences_store: InventoryPreferencesStore
var _syncing_projection_controls: bool = false
var interaction_profile_loader := InteractionProfileLoader.new()
var active_interaction_profile: InventoryInteractionProfile
var interaction_profile_override: String = ""
var transfer_session := TransferSession.new()
var slot_projection := SlotProjection.new()
var cursor_controller := CursorController.new()
var slot_mode_adapter := SlotModeAdapter.new()
var carry_preview: PanelContainer
var carry_preview_icon: TextureRect
var carry_preview_label: Label


func setup(
	controller,
	model: InventoryViewModel,
	commands: InventoryCommandFacade,
	profile_override: String = ""
) -> void:
	compatibility_external_title = Label.new()
	compatibility_external_title.name = "CompatibilityExternalTitle"
	compatibility_external_title.visible = false
	add_child(compatibility_external_title)
	gameplay_controller = controller
	view_model = model
	command_facade = commands
	interaction_profile_override = profile_override.strip_edges().to_lower()
	view_model.setup(controller)
	command_facade.setup(controller)
	slot_mode_adapter.setup(controller)
	preferences_store = InventoryPreferencesStore.new()
	preferences_store.setup(String(controller.profile_id))
	var preferences := preferences_store.load_preferences()
	_setup_projection_toolbar()
	cursor_controller.setup(gameplay_controller, command_facade, transfer_session, slot_projection, Callable(self, "_icon_for_cell"))
	_setup_interaction_profiles(preferences)
	_setup_carry_preview()
	view_model.apply_preferences(preferences)
	_sync_projection_controls()
	player_panel.set_visual_role("player")
	external_panel.set_visual_role("external")
	hotbar_panel.set_visual_role("hotbar")
	_wire_panel(player_panel)
	_wire_panel(external_panel)
	_wire_panel(hotbar_panel)
	split_dialog.transfer_confirmed.connect(_on_split_confirmed)
	split_dialog.transfer_cancelled.connect(_on_split_cancelled)
	context_menu.action_requested.connect(_on_context_action_requested)
	search_edit.text_changed.connect(_on_search_changed)
	filter_option.item_selected.connect(_on_filter_selected)
	sort_option.item_selected.connect(_on_sort_selected)
	interaction_profile_option.item_selected.connect(_on_interaction_profile_selected)
	reset_projection_button.pressed.connect(_on_projection_reset)
	inspector_toggle.toggled.connect(_on_inspector_toggled)
	inspector.close_requested.connect(func() -> void: inspector_toggle.button_pressed = false)
	set_process(true)
	set_inventory_visible(false)
	refresh()


func _wire_panel(panel: InventoryContainerPanel) -> void:
	panel.drop_requested.connect(_on_drop_requested)
	panel.quantity_drop_requested.connect(_on_quantity_drop_requested)
	panel.drop_outside_requested.connect(_on_drop_outside_requested)
	panel.activated.connect(_on_slot_activated)
	panel.quick_transfer_requested.connect(_on_quick_transfer_requested)
	panel.context_requested.connect(_on_context_requested)
	panel.item_hovered.connect(_on_item_hovered)
	panel.item_unhovered.connect(_on_item_unhovered)
	panel.item_selected.connect(_on_item_selected)
	panel.page_requested.connect(_on_page_requested)
	panel.drop_preview_rejected.connect(_on_drop_preview_rejected)
	panel.interaction_requested.connect(_on_interaction_requested)


func set_inventory_visible(value: bool) -> void:
	visible_inventory = value
	visible = value
	if value:
		_recenter_panel()
		_update_profile_status()
	else:
		split_dialog.hide()
		context_menu.close_menu()
		tooltip.clear_item(true)
		_clear_pending_quantity_drop()
		_cancel_transfer_session(false)


func is_inventory_visible() -> bool:
	return visible_inventory


func _input(event: InputEvent) -> void:
	if not visible_inventory:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode == KEY_F:
		search_edit.grab_focus()
		search_edit.select_all()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if transfer_session.is_active():
			_cancel_transfer_session(true)
		elif not inspector.current_item_id.is_empty():
			view_model.clear_selected_item()
			inspector.clear_item()
			refresh()
		elif context_menu.visible:
			context_menu.close_menu()
		elif tooltip.visible and tooltip.pinned:
			tooltip.clear_item(true)
		elif split_dialog.visible:
			split_dialog.cancel()
		else:
			gameplay_controller.set_inventory_visible(false)
		get_viewport().set_input_as_handled()


func open_external_container(container_id: String) -> void:
	external_container_id = container_id
	if _is_seven_days_profile():
		var migration := _ensure_slot_container(container_id)
		if not bool(migration.get("success", false)):
			_present_carry_error(migration, container_id)
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
	var player_model: Dictionary = slot_projection.project_container(Dictionary(screen_model.get("player", {})))
	var hotbar_model: Dictionary = Dictionary(screen_model.get("hotbar", {}))
	player_panel.render(player_model, Callable(self, "_icon_for_cell"), Callable(command_facade, "preview_transfer"))
	hotbar_panel.render_hotbar(hotbar_model, Callable(self, "_icon_for_cell"), Callable(command_facade, "preview_transfer"))
	# The interactive hotbar lives in a persistent overlay outside this window.
	hotbar_panel.visible = false
	var external_model: Dictionary = slot_projection.project_container(Dictionary(screen_model.get("external", {})))
	if external_container_id.is_empty() or external_model.is_empty():
		external_panel.clear_panel()
		compatibility_external_title.text = ""
		_apply_panel_size(false, 0)
	else:
		external_panel.render(external_model, Callable(self, "_icon_for_cell"), Callable(command_facade, "preview_transfer"))
		compatibility_external_title.text = "%s\n%s" % [external_panel.title_label.text, external_panel.metadata_label.text]
		_apply_panel_size(true, int(external_model.get("columns", 4)))
	var inspector_model: Dictionary = Dictionary(screen_model.get("selected_item", {}))
	if inspector_model.is_empty():
		inspector.clear_item()
	else:
		inspector.show_item(inspector_model)
	screen_model["player"] = player_model.duplicate(true)
	screen_model["external"] = external_model.duplicate(true)
	_update_projection_summary(player_model, external_model)
	if not message.is_empty():
		status_label.text = message
		toast_layer.show_message(message)
	set_meta("inventory_screen_model", screen_model.duplicate(true))


func get_external_visible_cell_count() -> int:
	return external_panel.get_visual_cell_count()


func get_external_rendered_cell_count() -> int:
	return external_panel.get_rendered_cell_count()


func render_persistent_hotbar(panel: InventoryHotbarPanel) -> void:
	if panel == null or gameplay_controller == null or view_model == null or command_facade == null:
		return
	var model := view_model.build_container(
		gameplay_controller.player_hotbar_id,
		int(gameplay_controller.selected_hotbar_index)
	)
	panel.set_interaction_profile(active_interaction_profile)
	panel.render_hotbar(model, Callable(self, "_icon_for_cell"), Callable(command_facade, "preview_transfer"))


func create_debug_snapshot() -> Dictionary:
	return {
		"schema": "planet_simulator.inventory_screen_debug.v1",
		"implementation": "component",
		"visible": visible_inventory,
		"external_container_id": external_container_id,
		"player": player_panel.current_model.duplicate(true),
		"external": external_panel.current_model.duplicate(true),
		"hotbar": hotbar_panel.current_model.duplicate(true),
		"boundaries": {
			"player": player_panel.get_boundary_snapshot(),
			"external": external_panel.get_boundary_snapshot(),
			"hotbar": hotbar_panel.get_boundary_snapshot(),
		},
		"ui_i1": {
			"context_menu_visible": context_menu.visible,
			"split_dialog_visible": split_dialog.visible,
			"tooltip_visible": tooltip.visible,
			"tooltip_pinned": tooltip.pinned,
			"toast_visible": toast_layer.visible,
			"toast_kind": toast_layer.message_kind,
		},
		"ui_i2": {
			"search_query": view_model.search_query,
			"active_filter": view_model.active_filter,
			"sort_mode": view_model.sort_mode,
			"inspector": inspector.create_debug_snapshot(),
			"preferences_path": preferences_store.file_path if preferences_store != null else "",
			"player_pool_size": player_panel.get_pool_size(),
			"external_pool_size": external_panel.get_pool_size(),
		},
		"cursor_controller": cursor_controller.debug_snapshot(),
		"interaction_profiles": {
			"active_profile_id": active_interaction_profile.profile_id if active_interaction_profile != null else "",
			"active_profile_name": active_interaction_profile.display_name if active_interaction_profile != null else "",
			"loader": interaction_profile_loader.create_debug_snapshot(),
			"transfer_session": transfer_session.snapshot(),
		},
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
		_present_result(preview, target_container_id)
		return
	_open_split_for_target(
		item_id,
		mini(maxi(1, total_quantity), maxi(1, int(preview.get("maximum_quantity", total_quantity)))),
		target_container_id,
		target_slot_index,
		target_item_id
	)


func _on_drop_requested(
	item_id: String,
	target_container_id: String,
	target_slot_index: int,
	quantity: int = -1,
	target_item_id: String = ""
) -> void:
	var cell_data := _cell_data_for_item(item_id)
	var result: Dictionary = command_facade.transfer_quantity(
		item_id,
		quantity,
		target_container_id,
		target_slot_index,
		target_item_id
	)
	var requested_quantity := int(cell_data.get("quantity", 1)) if quantity < 0 else quantity
	var moved_quantity := int(result.get("moved_quantity", requested_quantity))
	var success_message := "" if moved_quantity <= 0 else "Перенесено: %s ×%d" % [String(cell_data.get("display_name", "Предмет")), moved_quantity]
	_present_result(result, target_container_id, success_message)


func _on_drop_outside_requested(item_id: String, requested_quantity: int) -> void:
	var cell_data := _cell_data_for_item(item_id)
	var quantity := maxi(1, requested_quantity)
	if item_id.is_empty():
		return
	var result: Dictionary = command_facade.drop_quantity(item_id, quantity)
	_present_result(
		result,
		String(cell_data.get("source_container_id", "")),
		"Выброшено: %s ×%d" % [String(cell_data.get("display_name", "Предмет")), quantity]
	)


func _on_split_confirmed(
	item_id: String,
	quantity: int,
	target_container_id: String,
	target_slot_index: int,
	target_item_id: String
) -> void:
	var cell_data := _cell_data_for_item(item_id)
	if pending_quantity_operation == "BEGIN_VIRTUAL_CARRY":
		_clear_pending_quantity_drop()
		_begin_transfer_session(cell_data, quantity)
		call_deferred("_restore_inventory_focus")
		return
	var result: Dictionary = command_facade.transfer_quantity(
		item_id,
		quantity,
		target_container_id,
		target_slot_index,
		target_item_id
	)
	_clear_pending_quantity_drop()
	var moved_quantity := int(result.get("moved_quantity", quantity))
	var success_message := "" if moved_quantity <= 0 else "Перенесено: %s ×%d" % [String(cell_data.get("display_name", "Предмет")), moved_quantity]
	_present_result(result, target_container_id, success_message)
	call_deferred("_restore_inventory_focus")


func _on_split_cancelled() -> void:
	_clear_pending_quantity_drop()
	status_label.text = "Перенос отменён"
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


func _on_quick_transfer_requested(item_id: String, source_container_id: String, _source_slot_index: int) -> void:
	if transfer_session.is_active():
		toast_layer.show_error("Сначала положите предмет с курсора")
		return
	var cell_data := _cell_data_for_item(item_id)
	if external_container_id.is_empty() and active_interaction_profile != null and active_interaction_profile.profile_id == "seven_days_like":
		var local_result: Dictionary
		var target_container_id := ""
		if source_container_id == gameplay_controller.player_inventory_id:
			local_result = command_facade.assign_hotbar_first_free(item_id)
			target_container_id = gameplay_controller.player_hotbar_id
		elif source_container_id == gameplay_controller.player_hotbar_id:
			local_result = command_facade.transfer_stack(item_id, gameplay_controller.player_inventory_id)
			target_container_id = gameplay_controller.player_inventory_id
		else:
			local_result = {
				"success": false,
				"error_code": "QUICK_TRANSFER_SOURCE_UNSUPPORTED",
				"message": "Быстрый перенос без открытого контейнера работает между рюкзаком и быстрой панелью",
			}
		_present_result(
			local_result,
			target_container_id,
			"Быстро перенесено: %s" % String(cell_data.get("display_name", "Предмет"))
		)
		return
	var preview := command_facade.preview_quick_transfer(item_id, source_container_id, external_container_id)
	var target_container_id := String(preview.get("target_container_id", source_container_id))
	if not bool(preview.get("success", false)):
		_present_result(preview, target_container_id)
		return
	var result := command_facade.quick_transfer(item_id, source_container_id, external_container_id)
	var moved_quantity := int(result.get("moved_quantity", 0))
	var success_message := "" if moved_quantity <= 0 else "Быстро перенесено: %s ×%d" % [String(cell_data.get("display_name", "Предмет")), moved_quantity]
	_present_result(result, target_container_id, success_message)


func _on_context_requested(
	item_id: String,
	source_container_id: String,
	source_slot_index: int,
	screen_position: Vector2
) -> void:
	var cell_data := _cell_data_for_item(item_id)
	if cell_data.is_empty():
		return
	_context_screen_position = screen_position
	var can_quick := (
		not external_container_id.is_empty()
		and source_container_id in [gameplay_controller.player_inventory_id, external_container_id]
	)
	var hotbar_slots: Array[Dictionary] = []
	if source_container_id != gameplay_controller.player_hotbar_id:
		hotbar_slots = command_facade.hotbar_slot_options(item_id)
	context_menu.open_for_item(cell_data, Vector2i(screen_position), {
		"can_quick_transfer": can_quick,
		"can_drop": true,
		"hotbar_slots": hotbar_slots,
		"source_slot_index": source_slot_index,
	})


func _on_context_action_requested(action_id: int, context: Dictionary) -> void:
	var item_id := String(context.get("item_id", ""))
	var source_container_id := String(context.get("source_container_id", ""))
	var quantity := int(context.get("quantity", 1))
	match action_id:
		InventoryItemContextMenu.ACTION_INSPECT:
			_on_item_selected(item_id)
			inspector_toggle.button_pressed = true
		InventoryItemContextMenu.ACTION_TRANSFER_ALL:
			_perform_context_quick_transfer(item_id, source_container_id, -1)
		InventoryItemContextMenu.ACTION_TRANSFER_ONE:
			_perform_context_quick_transfer(item_id, source_container_id, 1)
		InventoryItemContextMenu.ACTION_TRANSFER_HALF:
			_perform_context_quick_transfer(item_id, source_container_id, maxi(1, int(ceil(float(quantity) * 0.5))))
		InventoryItemContextMenu.ACTION_TRANSFER_EXACT:
			_open_context_split(item_id, source_container_id, quantity)
		InventoryItemContextMenu.ACTION_DROP_ONE:
			var drop_one_result := command_facade.drop_one(item_id)
			_present_result(drop_one_result, source_container_id, "Выброшено: %s ×1" % String(context.get("display_name", "Предмет")))
		InventoryItemContextMenu.ACTION_DROP_ALL:
			var drop_all_result := command_facade.drop_stack(item_id)
			_present_result(drop_all_result, source_container_id, "Выброшен стак: %s ×%d" % [String(context.get("display_name", "Предмет")), quantity])
		InventoryItemContextMenu.ACTION_HOTBAR_FIRST_FREE:
			var first_result := command_facade.assign_hotbar_first_free(item_id)
			_present_result(first_result, gameplay_controller.player_hotbar_id, "Предмет назначен в первый свободный слот hotbar")
		_:
			if action_id >= InventoryItemContextMenu.ACTION_HOTBAR_SLOT_BASE:
				var slot_index := int(context.get("hotbar_slot_index", -1))
				var hotbar_result := command_facade.assign_hotbar(item_id, slot_index)
				var key_name := "0" if slot_index == 9 else str(slot_index + 1)
				_present_result(hotbar_result, gameplay_controller.player_hotbar_id, "Предмет назначен в hotbar %s" % key_name)


func _perform_context_quick_transfer(item_id: String, source_container_id: String, quantity: int) -> void:
	var cell_data := _cell_data_for_item(item_id)
	var preview := command_facade.preview_quick_transfer(item_id, source_container_id, external_container_id, quantity)
	var target_container_id := String(preview.get("target_container_id", source_container_id))
	if not bool(preview.get("success", false)):
		_present_result(preview, target_container_id)
		return
	var result := command_facade.quick_transfer_quantity(item_id, source_container_id, external_container_id, quantity)
	var moved_quantity := int(result.get("moved_quantity", 0))
	var success_message := "" if moved_quantity <= 0 else "Перенесено: %s ×%d" % [String(cell_data.get("display_name", "Предмет")), moved_quantity]
	_present_result(result, target_container_id, success_message)


func _open_context_split(item_id: String, source_container_id: String, total_quantity: int) -> void:
	var preview := command_facade.preview_quick_transfer(item_id, source_container_id, external_container_id, total_quantity)
	var target_container_id := String(preview.get("target_container_id", source_container_id))
	if not bool(preview.get("success", false)):
		_present_result(preview, target_container_id)
		return
	_open_split_for_target(
		item_id,
		mini(total_quantity, maxi(1, int(preview.get("maximum_quantity", total_quantity)))),
		target_container_id,
		int(preview.get("target_slot_index", -1)),
		String(preview.get("target_item_id", ""))
	)


func _open_split_for_target(
	item_id: String,
	maximum_quantity: int,
	target_container_id: String,
	target_slot_index: int,
	target_item_id: String
) -> void:
	pending_item_id = item_id
	pending_target_container_id = target_container_id
	pending_target_slot_index = target_slot_index
	pending_target_item_id = target_item_id
	pending_total_quantity = maxi(1, maximum_quantity)
	pending_quantity_operation = "TRANSFER_TO_TARGET"
	var cell_data := _cell_data_for_item(item_id)
	split_dialog.open_request(
		item_id,
		pending_total_quantity,
		target_container_id,
		target_slot_index,
		target_item_id,
		String(cell_data.get("display_name", "Предмет")),
		gameplay_controller.get_container_display_name(target_container_id)
	)


func _on_item_hovered(cell_data: Dictionary, _screen_position: Vector2) -> void:
	if context_menu.visible or split_dialog.visible:
		return
	var item_id := String(cell_data.get("item_id", ""))
	if item_id.is_empty() or view_model == null:
		return
	# The inspector is the only detailed presentation surface; it must still
	# follow the hovered cell to preserve the established inventory contract.
	if not inspector_toggle.button_pressed:
		inspector_toggle.set_pressed_no_signal(true)
		inspector.visible = true
	inspector.show_item(view_model.build_item_inspector(item_id))


func _on_item_unhovered(_item_id: String) -> void:
	if view_model == null:
		return
	var selected_model := view_model.build_item_inspector(view_model.selected_item_id)
	if selected_model.is_empty():
		inspector.clear_item()
	else:
		inspector.show_item(selected_model)


func _on_drop_preview_rejected(target_container_id: String, _target_slot_index: int, error_code: String) -> void:
	var message: String = command_facade.result_message({"success": false, "error_code": error_code})
	var panel: InventoryContainerPanel = _panel_for_container(target_container_id)
	if panel != null:
		panel.show_feedback(message, false, 1.4)


func _on_slot_activated(item_id: String, container_id: String, slot_index: int) -> void:
	if container_id == gameplay_controller.player_hotbar_id and slot_index >= 0:
		var result: Dictionary = command_facade.select_hotbar(slot_index)
		_present_result(result, container_id, "Выбран слот hotbar")
	elif not item_id.is_empty() and container_id == external_container_id:
		var result: Dictionary = command_facade.transfer_stack(item_id, gameplay_controller.player_inventory_id)
		_present_result(result, gameplay_controller.player_inventory_id, "Предмет перенесён в рюкзак")


func _present_result(result: Dictionary, target_container_id: String = "", success_message: String = "") -> void:
	var success := bool(result.get("success", false))
	var message: String = success_message if success and not success_message.is_empty() else command_facade.result_message(result)
	refresh()
	status_label.text = message
	var panel: InventoryContainerPanel = _panel_for_container(target_container_id)
	if success:
		toast_layer.show_success(message)
		if panel != null:
			panel.show_feedback("Готово", true, 1.2)
	else:
		toast_layer.show_error(message)
		if panel != null:
			panel.show_feedback(message, false)


func _panel_for_container(container_id: String) -> InventoryContainerPanel:
	if container_id == gameplay_controller.player_inventory_id:
		return player_panel
	if container_id == gameplay_controller.player_hotbar_id:
		return hotbar_panel
	if not external_container_id.is_empty() and container_id == external_container_id:
		return external_panel
	return null


func _cell_data_for_item(item_id: String) -> Dictionary:
	for panel in [player_panel, external_panel, hotbar_panel]:
		for value in panel.current_model.get("cells", []):
			var cell: Dictionary = Dictionary(value)
			if String(cell.get("item_id", "")) == item_id:
				return cell.duplicate(true)
	var item = gameplay_controller.get_item(item_id)
	if item == null:
		return {}
	var definition = gameplay_controller.get_definition(item.definition_id)
	return {
		"item_id": item_id,
		"definition_id": String(item.definition_id),
		"display_name": String(item.display_name) if not String(item.display_name).is_empty() else String(definition.display_name),
		"quantity": int(item.quantity),
		"tags": Array(definition.tags),
		"unit_mass_kg": float(definition.unit_mass_kg),
		"unit_volume_l": float(definition.external_volume_l),
	}


func _position_tooltip(screen_position: Vector2) -> void:
	var local_position := screen_position - global_position + Vector2(10.0, 8.0)
	var expected_size := Vector2(maxf(300.0, tooltip.custom_minimum_size.x), maxf(150.0, tooltip.size.y))
	local_position.x = clampf(local_position.x, 8.0, maxf(8.0, size.x - expected_size.x - 8.0))
	local_position.y = clampf(local_position.y, 8.0, maxf(8.0, size.y - expected_size.y - 8.0))
	tooltip.position = local_position


func _clear_pending_quantity_drop() -> void:
	pending_item_id = ""
	pending_target_container_id = ""
	pending_target_slot_index = -1
	pending_target_item_id = ""
	pending_total_quantity = 0
	pending_quantity_operation = "TRANSFER_TO_TARGET"


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
	var seven_days_style := _is_seven_days_profile()
	var desired_width := 1180.0 if seven_days_style else 1060.0
	if has_external:
		desired_width = (1280.0 + maxf(180.0, external_columns * 28.0)) if seven_days_style else (1120.0 + maxf(260.0, external_columns * 44.0))
	var viewport_size := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1280.0, 720.0)
	var width := minf(desired_width, maxf(760.0, viewport_size.x - 32.0))
	var desired_height := 720.0 if seven_days_style else 680.0
	var height := minf(desired_height, maxf(600.0, viewport_size.y - 32.0))
	var panel_size := Vector2(width, height)
	custom_minimum_size = panel_size
	size = panel_size
	_recenter_panel()


func _recenter_panel() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	position = (viewport.get_visible_rect().size - size) * 0.5


func _setup_projection_toolbar() -> void:
	filter_option.clear()
	for entry in [
		["Все", InventoryViewModel.FILTER_ALL],
		["Ресурсы", InventoryViewModel.FILTER_RESOURCE],
		["Инструменты", InventoryViewModel.FILTER_TOOL],
		["Контейнеры", InventoryViewModel.FILTER_CONTAINER],
		["Аккумуляторы", InventoryViewModel.FILTER_BATTERY],
		["Монтируемые", InventoryViewModel.FILTER_MOUNTABLE],
		["Строительство", InventoryViewModel.FILTER_CONSTRUCTION],
	]:
		filter_option.add_item(String(entry[0]))
		filter_option.set_item_metadata(filter_option.item_count - 1, String(entry[1]))
	sort_option.clear()
	for entry in [
		["Порядок контейнера", InventoryViewModel.SORT_CONTAINER_ORDER],
		["По имени", InventoryViewModel.SORT_NAME],
		["По типу", InventoryViewModel.SORT_TYPE],
		["По количеству", InventoryViewModel.SORT_QUANTITY],
		["По массе", InventoryViewModel.SORT_MASS],
		["По объёму", InventoryViewModel.SORT_VOLUME],
		["Недавние операции", InventoryViewModel.SORT_RECENT],
	]:
		sort_option.add_item(String(entry[0]))
		sort_option.set_item_metadata(sort_option.item_count - 1, String(entry[1]))


func _sync_projection_controls() -> void:
	_syncing_projection_controls = true
	search_edit.text = view_model.search_query
	_select_option_metadata(filter_option, view_model.active_filter)
	_select_option_metadata(sort_option, view_model.sort_mode)
	var preferences := preferences_store.load_preferences() if preferences_store != null else {}
	inspector_toggle.button_pressed = bool(preferences.get("inspector_visible", true))
	inspector.visible = inspector_toggle.button_pressed
	if active_interaction_profile != null:
		_select_option_metadata(interaction_profile_option, active_interaction_profile.profile_id)
	_syncing_projection_controls = false


func _select_option_metadata(option: OptionButton, value: String) -> void:
	for index in range(option.item_count):
		if String(option.get_item_metadata(index)) == value:
			option.select(index)
			return


func _on_search_changed(value: String) -> void:
	if _syncing_projection_controls:
		return
	view_model.set_search_query(value)
	_save_preferences()
	refresh()


func _on_filter_selected(index: int) -> void:
	if _syncing_projection_controls:
		return
	view_model.set_active_filter(String(filter_option.get_item_metadata(index)))
	_save_preferences()
	refresh()


func _on_sort_selected(index: int) -> void:
	if _syncing_projection_controls:
		return
	view_model.set_sort_mode(String(sort_option.get_item_metadata(index)))
	_save_preferences()
	refresh()


func _on_projection_reset() -> void:
	view_model.set_search_query("")
	view_model.set_active_filter(InventoryViewModel.FILTER_ALL)
	view_model.set_sort_mode(InventoryViewModel.SORT_CONTAINER_ORDER)
	_sync_projection_controls()
	_save_preferences()
	refresh("Поиск, фильтр и сортировка сброшены")


func _on_inspector_toggled(value: bool) -> void:
	if inspector != null:
		inspector.visible = value
	if not _syncing_projection_controls:
		_save_preferences()
		_apply_panel_size(not external_container_id.is_empty(), int(external_panel.current_model.get("columns", 4)))


func _on_item_selected(item_id: String) -> void:
	if item_id.is_empty():
		return
	view_model.set_selected_item(item_id)
	if not inspector_toggle.button_pressed:
		inspector_toggle.button_pressed = true
	# Godot requests drag data from this same Control after the LMB press.
	# Rebuilding the grid here destroys the source cell before drag can start.
	inspector.show_item(view_model.build_item_inspector(item_id))


func _on_page_requested(container_id: String, page_index: int) -> void:
	view_model.set_container_page(container_id, page_index)
	refresh()


func _save_preferences() -> void:
	if preferences_store == null:
		return
	var preferences := view_model.preferences_snapshot(inspector_toggle.button_pressed)
	preferences["interaction_profile_id"] = active_interaction_profile.profile_id if active_interaction_profile != null else "planet_default"
	preferences_store.save_preferences(preferences)


func _update_projection_summary(player_model: Dictionary, external_model: Dictionary) -> void:
	var total := int(player_model.get("matched_count", player_model.get("projected_total_count", 0)))
	var source_total := int(player_model.get("unfiltered_count", player_model.get("used_entries", 0)))
	if not external_model.is_empty():
		total += int(external_model.get("matched_count", external_model.get("projected_total_count", 0)))
		source_total += int(external_model.get("unfiltered_count", external_model.get("used_entries", 0)))
	var parts := PackedStringArray()
	parts.append("Показано %d из %d агрегатов" % [total, source_total])
	if not view_model.search_query.is_empty():
		parts.append("поиск: «%s»" % view_model.search_query)
	if view_model.active_filter != InventoryViewModel.FILTER_ALL:
		parts.append("фильтр: %s" % filter_option.get_item_text(filter_option.selected))
	if view_model.sort_mode != InventoryViewModel.SORT_CONTAINER_ORDER:
		parts.append("сортировка: %s" % sort_option.get_item_text(sort_option.selected))
	projection_summary.text = " · ".join(parts)


func _process(_delta: float) -> void:
	if carry_preview == null or not carry_preview.visible:
		return
	carry_preview.position = get_global_mouse_position() - global_position + Vector2(18.0, 18.0)


func _setup_interaction_profiles(preferences: Dictionary) -> void:
	interaction_profile_loader.load_catalog()
	interaction_profile_option.clear()
	for option in interaction_profile_loader.profile_options():
		var option_data := Dictionary(option)
		interaction_profile_option.add_item(String(option_data.get("display_name", option_data.get("profile_id", "Профиль"))))
		var index := interaction_profile_option.item_count - 1
		interaction_profile_option.set_item_metadata(index, String(option_data.get("profile_id", "")))
		interaction_profile_option.set_item_tooltip(index, String(option_data.get("description", "")))
	var requested_profile_id := interaction_profile_override
	var environment_profile_id := interaction_profile_loader.environment_profile_id()
	if requested_profile_id.is_empty() and not environment_profile_id.is_empty():
		requested_profile_id = environment_profile_id
	if requested_profile_id.is_empty() and interaction_profile_loader.allow_user_profile_override:
		requested_profile_id = String(preferences.get("interaction_profile_id", "")).strip_edges().to_lower()
	var resolved := interaction_profile_loader.resolve_profile(requested_profile_id)
	if not bool(resolved.get("success", false)):
		push_error("Inventory interaction profiles unavailable: %s" % resolved)
		return
	_apply_interaction_profile(resolved.get("profile") as InventoryInteractionProfile, false, false)


func _apply_interaction_profile(
	profile: InventoryInteractionProfile,
	persist: bool = true,
	refresh_now: bool = true
) -> void:
	if profile == null:
		return
	_cancel_transfer_session(false)
	if split_dialog != null and split_dialog.visible:
		split_dialog.hide()
		split_dialog.clear_request()
	_clear_pending_quantity_drop()
	active_interaction_profile = profile
	slot_projection.configure(profile)
	if _is_seven_days_profile():
		var player_migration := _ensure_slot_container(gameplay_controller.player_inventory_id)
		if not bool(player_migration.get("success", false)):
			toast_layer.show_error("Не удалось включить слотовый рюкзак")
		if not external_container_id.is_empty():
			var external_migration := _ensure_slot_container(external_container_id)
			if not bool(external_migration.get("success", false)):
				toast_layer.show_error("Не удалось включить слоты внешнего контейнера")
	for panel in [player_panel, external_panel, hotbar_panel]:
		panel.set_interaction_profile(profile)
	_sync_interaction_profile_option()
	_apply_profile_visual_style()
	_update_profile_status()
	if persist:
		_save_preferences()
	if refresh_now and gameplay_controller != null:
		refresh()
	var parent := get_parent()
	if parent != null and parent.has_method("_refresh_persistent_hotbar"):
		parent.call_deferred("_refresh_persistent_hotbar")


func _is_seven_days_profile() -> bool:
	return active_interaction_profile != null and active_interaction_profile.profile_id == "seven_days_like"


func _ensure_slot_container(container_id: String) -> Dictionary:
	if container_id.is_empty():
		return {"success": true, "no_change": true}
	var preferred_layout: Array = Array(slot_projection.export_layouts().get(container_id, []))
	var result: Dictionary = slot_mode_adapter.ensure_container_slots(container_id, preferred_layout)
	if bool(result.get("success", false)):
		slot_projection.clear_container(container_id)
	return result


func _sync_interaction_profile_option() -> void:
	if interaction_profile_option == null or active_interaction_profile == null:
		return
	_syncing_projection_controls = true
	_select_option_metadata(interaction_profile_option, active_interaction_profile.profile_id)
	_syncing_projection_controls = false


func _on_interaction_profile_selected(index: int) -> void:
	if _syncing_projection_controls:
		return
	var profile_id := String(interaction_profile_option.get_item_metadata(index))
	var profile := interaction_profile_loader.get_profile(profile_id)
	if profile == null:
		var resolved := interaction_profile_loader.resolve_profile(profile_id)
		profile = resolved.get("profile") as InventoryInteractionProfile if bool(resolved.get("success", false)) else null
	if profile == null:
		toast_layer.show_error("Профиль управления недоступен")
		_sync_interaction_profile_option()
		return
	_apply_interaction_profile(profile, true, true)
	toast_layer.show_success("Профиль управления: %s" % profile.display_name)


func _update_profile_status() -> void:
	if status_label == null:
		return
	if active_interaction_profile == null:
		status_label.text = "Профиль управления недоступен · Tab — закрыть"
		return
	var legend := active_interaction_profile.status_text()
	status_label.text = "%s: %s · Tab — закрыть" % [active_interaction_profile.display_name, legend]


func _apply_profile_visual_style() -> void:
	if active_interaction_profile == null:
		return
	var seven_days_style := active_interaction_profile.ui_style == "SEVEN_DAYS"
	$Margin/Main/Header.visible = not seven_days_style
	search_edit.visible = not seven_days_style
	filter_option.visible = not seven_days_style
	sort_option.visible = not seven_days_style
	reset_projection_button.visible = not seven_days_style
	inspector_toggle.visible = not seven_days_style
	projection_summary.visible = not seven_days_style
	$Margin/Main/ProjectionToolbar.alignment = BoxContainer.ALIGNMENT_END if seven_days_style else BoxContainer.ALIGNMENT_BEGIN
	columns.add_theme_constant_override("separation", 4 if seven_days_style else 14)
	if seven_days_style:
		columns.move_child(external_panel, 0)
		columns.move_child(player_panel, 1)
		columns.move_child(inspector, 2)
		inspector.visible = false
	else:
		columns.move_child(player_panel, 0)
		columns.move_child(external_panel, 1)
		columns.move_child(inspector, 2)
		inspector.visible = inspector_toggle.button_pressed
	custom_minimum_size = Vector2(1240.0, 720.0) if seven_days_style else Vector2(1060.0, 680.0)
	var style := StyleBoxFlat.new()
	if seven_days_style:
		style.bg_color = Color(0.035, 0.035, 0.03, 0.82)
		style.border_color = Color(0.92, 0.75, 0.18, 1.0)
		style.set_border_width_all(2)
		style.set_corner_radius_all(0)
	else:
		style.bg_color = Color(0.035, 0.045, 0.065, 0.97)
		style.border_color = Color(0.22, 0.5, 0.72, 1.0)
		style.set_border_width_all(2)
		style.set_corner_radius_all(10)
	add_theme_stylebox_override("panel", style)
	if carry_preview != null:
		var carry_style := StyleBoxFlat.new()
		carry_style.bg_color = Color(0.08, 0.08, 0.07, 0.92)
		carry_style.border_color = Color(0.95, 0.82, 0.24, 1.0) if seven_days_style else Color(0.45, 0.82, 1.0, 1.0)
		carry_style.set_border_width_all(2)
		carry_style.set_corner_radius_all(2 if seven_days_style else 6)
		carry_style.content_margin_left = 6.0
		carry_style.content_margin_top = 5.0
		carry_style.content_margin_right = 6.0
		carry_style.content_margin_bottom = 5.0
		carry_preview.add_theme_stylebox_override("panel", carry_style)


func _setup_carry_preview() -> void:
	carry_preview = PanelContainer.new()
	carry_preview.name = "CarryPreview"
	carry_preview.visible = false
	carry_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carry_preview.top_level = true
	carry_preview.z_as_relative = false
	carry_preview.z_index = 4095
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.06, 0.94)
	style.border_color = Color(0.45, 0.82, 1.0, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 6.0
	style.content_margin_top = 5.0
	style.content_margin_right = 6.0
	style.content_margin_bottom = 5.0
	carry_preview.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carry_preview.add_child(row)
	carry_preview_icon = TextureRect.new()
	carry_preview_icon.custom_minimum_size = Vector2(42.0, 42.0)
	carry_preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	carry_preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	carry_preview_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(carry_preview_icon)
	carry_preview_label = Label.new()
	carry_preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	carry_preview_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(carry_preview_label)
	add_child(carry_preview)
	_apply_profile_visual_style()


func _on_interaction_requested(action_id: String, payload: Dictionary) -> void:
	if not visible_inventory:
		return
	match action_id:
		"CARRY_ALL_OR_PLACE_ALL":
			_handle_carry_interaction(payload, false)
		"CARRY_HALF_OR_PLACE_ONE":
			_handle_carry_interaction(payload, true)
		"CARRY_EXACT_OR_PLACE_ONE":
			if transfer_session.is_active():
				_place_carried_quantity(payload, 1)
			else:
				_open_virtual_carry_quantity_dialog(payload)
		"PLACE_ALL_OR_SELECT":
			if transfer_session.is_active():
				_place_carried_quantity(payload, transfer_session.remaining_quantity)
			else:
				_on_item_selected(String(payload.get("item_id", "")))


func _handle_carry_interaction(payload: Dictionary, place_one: bool) -> void:
	if transfer_session.is_active():
		_place_carried_quantity(payload, 1 if place_one else transfer_session.remaining_quantity)
		return
	var available_quantity := maxi(1, int(payload.get("quantity", 1)))
	var carry_quantity := maxi(1, int(ceil(float(available_quantity) * 0.5))) if place_one else available_quantity
	_begin_transfer_session(payload, carry_quantity)


func _open_virtual_carry_quantity_dialog(payload: Dictionary) -> void:
	var item_id := String(payload.get("item_id", ""))
	var available_quantity := int(payload.get("quantity", 0))
	if item_id.is_empty() or available_quantity <= 0:
		return
	pending_item_id = item_id
	pending_target_container_id = ""
	pending_target_slot_index = -1
	pending_target_item_id = ""
	pending_total_quantity = available_quantity
	pending_quantity_operation = "BEGIN_VIRTUAL_CARRY"
	split_dialog.open_request(
		item_id,
		available_quantity,
		"",
		-1,
		"",
		String(payload.get("display_name", "Предмет")),
		"виртуальный стак на курсоре"
	)


func _begin_transfer_session(payload: Dictionary, carry_quantity: int) -> void:
	var source_item_id := String(payload.get("item_id", ""))
	if source_item_id.is_empty():
		return
	var item = gameplay_controller.get_item(source_item_id)
	if item == null:
		toast_layer.show_error("Исходный предмет больше не существует")
		return
	var session_payload := payload.duplicate(true)
	if not session_payload.has("icon_texture"):
		session_payload["icon_texture"] = _icon_for_cell(session_payload)
	var result: Dictionary
	if active_interaction_profile != null and active_interaction_profile.profile_id == "seven_days_like":
		result = cursor_controller.begin(session_payload, carry_quantity)
	else:
		result = transfer_session.begin(
			session_payload,
			carry_quantity,
			session_payload.get("icon_texture") as Texture2D,
			int(item.revision)
		)
	if not bool(result.get("success", false)):
		_present_carry_error(result, String(payload.get("source_container_id", "")))
		return
	_on_item_selected(source_item_id)
	refresh()
	_update_carry_preview()
	status_label.text = "На курсоре: %s ×%d · выберите слот · Esc — вернуть" % [
		transfer_session.display_name,
		transfer_session.remaining_quantity,
	]


func _place_carried_quantity(target_payload: Dictionary, requested_quantity: int) -> void:
	if not transfer_session.is_active():
		return
	var target_container_id := String(target_payload.get("target_container_id", target_payload.get("source_container_id", "")))
	var target_slot_index := int(target_payload.get("target_slot_index", target_payload.get("source_slot_index", -1)))
	var target_item_id := String(target_payload.get("target_item_id", target_payload.get("item_id", "")))
	if target_container_id.is_empty():
		toast_layer.show_error("Не выбрана цель переноса")
		return
	var requested := clampi(requested_quantity, 1, transfer_session.remaining_quantity)
	if transfer_session.domain_backed:
		var cursor_result := cursor_controller.place(target_payload, requested)
		if not bool(cursor_result.get("success", false)):
			_present_carry_error(cursor_result, target_container_id)
			return
		refresh()
		_update_carry_preview()
		if bool(cursor_result.get("swapped", false)):
			status_label.text = "В слоте оставлен предмет; на курсоре теперь: %s ×%d" % [
				transfer_session.display_name,
				transfer_session.remaining_quantity,
			]
			toast_layer.show_message("Предметы поменяны местами")
		elif transfer_session.is_active():
			status_label.text = "Осталось на курсоре: %s ×%d" % [transfer_session.display_name, transfer_session.remaining_quantity]
			var active_panel := _panel_for_container(target_container_id)
			if active_panel != null:
				active_panel.show_feedback("Положено ×%d" % int(cursor_result.get("moved_quantity", requested)), true, 1.2)
		else:
			status_label.text = "Предмет помещён в слот"
			toast_layer.show_success("Предмет перенесён")
		return
	if (
		target_item_id == transfer_session.item_id
		and target_container_id == transfer_session.source_container_id
		and target_slot_index == transfer_session.source_slot_index
	):
		_cancel_transfer_session(true)
		return
	var preview := command_facade.preview_transfer(
		transfer_session.item_id,
		requested,
		target_container_id,
		target_slot_index,
		target_item_id
	)
	if not bool(preview.get("success", false)):
		_present_carry_error(preview, target_container_id)
		return
	var maximum_quantity := maxi(0, int(preview.get("maximum_quantity", requested)))
	var move_quantity := mini(requested, maximum_quantity)
	if move_quantity <= 0:
		_present_carry_error({"success": false, "error_code": "DROP_REJECTED"}, target_container_id)
		return
	var result := command_facade.transfer_quantity(
		transfer_session.item_id,
		move_quantity,
		target_container_id,
		target_slot_index,
		target_item_id
	)
	if not bool(result.get("success", false)):
		_present_carry_error(result, target_container_id)
		return
	var moved_quantity := maxi(0, int(result.get("moved_quantity", move_quantity)))
	transfer_session.consume(moved_quantity)
	refresh()
	if transfer_session.is_active():
		_update_carry_preview()
		status_label.text = "Осталось на курсоре: %s ×%d" % [transfer_session.display_name, transfer_session.remaining_quantity]
		var panel := _panel_for_container(target_container_id)
		if panel != null:
			panel.show_feedback("Положено ×%d" % moved_quantity, true, 1.2)
	else:
		_update_carry_preview()
		status_label.text = "Перенесено ×%d" % moved_quantity
		toast_layer.show_success("Предмет перенесён")


func _present_carry_error(result: Dictionary, target_container_id: String) -> void:
	var message := command_facade.result_message(result)
	status_label.text = message
	toast_layer.show_error(message)
	var panel := _panel_for_container(target_container_id)
	if panel != null:
		panel.show_feedback(message, false)


func _cancel_transfer_session(show_message: bool) -> bool:
	var was_active := transfer_session.is_active()
	if was_active and transfer_session.domain_backed:
		var result := cursor_controller.cancel()
		if not bool(result.get("success", false)):
			_present_carry_error(result, transfer_session.source_container_id)
			return false
	else:
		transfer_session.clear()
	refresh()
	_update_carry_preview()
	if show_message and was_active:
		status_label.text = "Предмет возвращён в исходный слот"
		toast_layer.show_message("Перенос отменён")
	return true


func _update_carry_preview() -> void:
	if carry_preview == null:
		return
	carry_preview.visible = transfer_session.is_active() and visible_inventory
	if not carry_preview.visible:
		return
	carry_preview_icon.texture = transfer_session.icon_texture
	carry_preview_label.text = "%s
×%d" % [transfer_session.display_name, transfer_session.remaining_quantity]
	carry_preview.position = get_global_mouse_position() - global_position + Vector2(18.0, 18.0)


func _restore_inventory_focus() -> void:
	if not visible_inventory:
		return
	focus_mode = Control.FOCUS_ALL
	grab_focus()
