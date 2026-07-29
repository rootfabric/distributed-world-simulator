extends SceneTree

const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const Gameplay = preload("res://scripts/items/presentation/item_gameplay_controller.gd")
const InventoryUI = preload("res://scripts/items/presentation/item_inventory_ui.gd")

const STORE_ROOT := "user://planet_simulator/item_graphs"
const STATE_KEY := "test-inventory-ui-i0"

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var store = Factory.create_json_state_store(STORE_ROOT)
	store.delete_state(STATE_KEY)
	var fixture := await _create_controller()
	var controller = fixture.controller
	var inventory_ui = controller.inventory_ui
	_assert(inventory_ui != null, "UI-I0 runtime must create inventory facade")
	_assert(inventory_ui.get_implementation_id() == "component", "Feature config must activate component inventory by default")
	_assert(inventory_ui.using_component_screen(), "Facade must report component implementation")
	_assert(inventory_ui.view_model != null and inventory_ui.command_facade != null, "Component UI must own ViewModel and CommandFacade")

	var initial_snapshot: Dictionary = inventory_ui.create_debug_snapshot()
	_assert(inventory_ui.persistent_hotbar != null and inventory_ui.persistent_hotbar.visible, "Persistent hotbar must exist outside the inventory window")
	_assert(inventory_ui.persistent_hotbar.grid.columns == 10, "Persistent hotbar must keep all slots in one row")
	_assert(is_equal_approx(inventory_ui.persistent_hotbar.custom_minimum_size.y, 72.0), "Persistent hotbar must remain a compact one-row strip")
	var persistent_style = inventory_ui.persistent_hotbar.get_theme_stylebox("panel")
	_assert(persistent_style is StyleBoxFlat and (persistent_style as StyleBoxFlat).bg_color.a < 0.7, "Persistent hotbar background must be translucent")
	controller.set_inventory_visible(false)
	_assert(inventory_ui.persistent_hotbar.visible, "Persistent hotbar must remain visible while inventory is closed")
	controller.set_inventory_visible(true)
	var player_model: Dictionary = Dictionary(initial_snapshot.get("player", {}))
	var hotbar_model: Dictionary = Dictionary(initial_snapshot.get("hotbar", {}))
	_assert(String(player_model.get("storage_mode", "")) == "BULK", "Player backpack must be projected as BULK")
	_assert(int(player_model.get("visual_capacity", 0)) == 18, "Backpack projection must preserve configured entry capacity")
	_assert(int(player_model.get("rendered_cell_count", 0)) == controller.get_container(controller.player_inventory_id).item_ids.size(), "BULK projection must render existing aggregates without fake empty slots")
	_assert(String(hotbar_model.get("storage_mode", "")) == "SLOTS", "Hotbar must be projected as SLOTS")
	_assert(int(hotbar_model.get("rendered_cell_count", 0)) == 10, "Fixed hotbar must render all ten real slots")
	_assert(inventory_ui.hotbar_grid.get_child_count() == 10, "Compatibility facade must expose component hotbar grid")
	var initial_boundaries: Dictionary = Dictionary(initial_snapshot.get("boundaries", {}))
	var player_boundary: Dictionary = Dictionary(initial_boundaries.get("player", {}))
	var hotbar_boundary: Dictionary = Dictionary(initial_boundaries.get("hotbar", {}))
	_assert(bool(player_boundary.get("visible", false)), "Player BULK area must have a persistent visible boundary")
	_assert(String(player_boundary.get("role", "")) == "player", "Player boundary must expose its visual role")
	_assert(String(player_boundary.get("drop_hint", "")).contains("свободную область"), "BULK boundary must explain that the whole area accepts drops")
	_assert(not inventory_ui.active_screen.hotbar_panel.visible and String(hotbar_boundary.get("role", "")) == "hotbar", "Compatibility hotbar inside inventory must stay hidden")

	var backpack = controller.get_container(controller.player_inventory_id)
	var original_order: Array = backpack.item_ids.duplicate()
	var original_revision := int(backpack.revision)
	inventory_ui.view_model.set_sort_mode("NAME")
	inventory_ui.view_model.set_search_query("Полевой")
	var filtered: Dictionary = inventory_ui.view_model.build_container(controller.player_inventory_id)
	_assert(int(filtered.get("rendered_cell_count", 0)) == 1, "ViewModel search must filter visible BULK aggregates")
	_assert(backpack.item_ids == original_order and int(backpack.revision) == original_revision, "View-only search and sorting must not mutate Item Graph")
	inventory_ui.view_model.set_search_query("")
	inventory_ui.view_model.set_sort_mode("CONTAINER_ORDER")

	var starter = _find_item(controller, "survey_beacon", controller.player_inventory_id)
	var starter_relation_before: Dictionary = starter.relation.duplicate(true)
	var preview: Dictionary = inventory_ui.command_facade.preview_transfer(
		starter.instance_id,
		1,
		controller.player_hotbar_id,
		0,
		""
	)
	_assert_success(preview, "Command facade must delegate transfer preview")
	_assert(starter.relation == starter_relation_before, "Preview through facade must not mutate item relation")
	var no_external: Dictionary = inventory_ui.command_facade.quick_transfer(
		starter.instance_id,
		controller.player_inventory_id,
		""
	)
	_assert(String(no_external.get("error_code", "")) == "NO_EXTERNAL_CONTAINER", "Quick transfer scaffold must reject missing active pair explicitly")
	_assert(starter.relation == starter_relation_before, "Rejected quick transfer must leave domain state unchanged")

	var crate = _find_item(controller, "portable_crate", "", Relations.WORLD)
	_assert(crate != null, "Playground UI fixture must contain BULK crate")
	_assert_success(controller.open_container(crate.get_owned_container_id()), "Component UI must open external BULK container through controller contract")
	_assert(inventory_ui.external_section.visible, "External component panel must be visible only in active interaction context")
	_assert(inventory_ui.get_external_visible_cell_count() == 12, "Compatibility API must report configured BULK capacity")
	_assert(inventory_ui.get_external_rendered_cell_count() == 2, "Component BULK panel must render two actual stacks instead of twelve placeholders")
	_assert(inventory_ui.external_title.text.contains("Универсальный ящик"), "Compatibility title bridge must expose component panel title")
	var external_snapshot: Dictionary = inventory_ui.create_debug_snapshot()
	_assert(String(external_snapshot.get("external", {}).get("storage_mode", "")) == "BULK", "External snapshot must identify BULK mode")
	var external_boundary: Dictionary = Dictionary(external_snapshot.get("boundaries", {}).get("external", {}))
	_assert(bool(external_boundary.get("visible", false)), "Opened external container must expose a visible drop boundary")
	_assert(String(external_boundary.get("role", "")) == "external", "External container boundary must be visually distinguishable from player inventory")

	var rack = _find_item(controller, "battery_rack", "", Relations.WORLD)
	_assert(rack != null, "Playground UI fixture must contain SLOTS rack")
	_assert_success(controller.open_container(rack.get_owned_container_id()), "Component UI must switch external context to SLOTS rack")
	_assert(inventory_ui.get_external_visible_cell_count() == 4, "SLOTS compatibility count must equal real slot count")
	_assert(inventory_ui.get_external_rendered_cell_count() == 4, "SLOTS component must render all fixed slots including empty ones")
	var rack_snapshot: Dictionary = inventory_ui.create_debug_snapshot()
	_assert(String(rack_snapshot.get("external", {}).get("storage_mode", "")) == "SLOTS", "External snapshot must identify SLOTS mode")

	controller.set_inventory_visible(false)
	_assert(inventory_ui.external_container_id.is_empty() and not inventory_ui.external_section.visible, "Closing inventory must clear component external context")

	var legacy_ui = InventoryUI.new()
	get_root().add_child(legacy_ui)
	legacy_ui.setup(controller, "legacy")
	_assert(legacy_ui.get_implementation_id() == "legacy" and not legacy_ui.using_component_screen(), "Feature facade must preserve explicit legacy fallback")
	legacy_ui.set_inventory_visible(true)
	_assert(legacy_ui.is_inventory_visible(), "Legacy fallback must preserve facade visibility contract")
	legacy_ui.set_inventory_visible(false)
	legacy_ui.queue_free()

	_assert_success(controller.domain.validator.validate_graph(), "UI-I0 presentation scaffold must leave item graph valid")
	store.delete_state(STATE_KEY)
	controller.queue_free()
	await process_frame
	_finish()


func _create_controller() -> Dictionary:
	var world_root := Node3D.new()
	world_root.name = "WorldRoot"
	get_root().add_child(world_root)
	var attachment_root := Node3D.new()
	attachment_root.name = "AttachmentRoot"
	get_root().add_child(attachment_root)
	var controller = Gameplay.new()
	controller.name = "ItemGameplayController"
	get_root().add_child(controller)
	var setup: Dictionary = controller.setup_runtime(
		null,
		world_root,
		attachment_root,
		null,
		"scenario/local",
		"",
		STATE_KEY,
		"playground",
		true
	)
	await process_frame
	return {"controller": controller, "setup": setup}


func _find_item(controller, definition_id: String, container_id: String = "", relation_kind: String = Relations.CONTAINER):
	for item in controller.domain.items.all_items():
		if item.definition_id != definition_id:
			continue
		if not relation_kind.is_empty() and Relations.kind_of(item.relation) != relation_kind:
			continue
		if not container_id.is_empty() and String(item.relation.get("container_id", "")) != container_id:
			continue
		return item
	return null


func _assert_success(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("Inventory UI-I0 architecture: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Inventory UI-I0 architecture: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
