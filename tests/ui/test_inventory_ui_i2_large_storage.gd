extends SceneTree

const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const Gameplay = preload("res://scripts/items/presentation/item_gameplay_controller.gd")
const ContainerState = preload("res://scripts/containers/container_state.gd")
const PreferencesStore = preload("res://scripts/ui/inventory/inventory_preferences_store.gd")

const STORE_ROOT := "user://planet_simulator/item_graphs"
const STATE_KEY := "test-inventory-ui-i2"
const LARGE_CONTAINER_ID := "ui_i2_large_storage"
const RECENT_CONTAINER_ID := "ui_i2_recent_sort"

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
	var screen = inventory_ui.active_screen
	var view_model = inventory_ui.view_model
	_assert(screen != null and view_model != null, "UI-I2 fixture must expose component screen and ViewModel")

	var backpack = controller.get_container(controller.player_inventory_id)
	var original_order: Array = backpack.item_ids.duplicate()
	var original_revision := int(backpack.revision)

	# Search, category filter and visual sorting must remain presentation-only.
	view_model.set_search_query("Аккумулятор")
	var search_model: Dictionary = view_model.build_container(controller.player_inventory_id)
	_assert(int(search_model.get("projected_total_count", 0)) == 1, "Search must find the battery aggregate by localized display name")
	_assert(String(search_model.get("cells", [])[0].get("definition_id", "")) == "battery_pack", "Search result must be the battery definition")
	view_model.set_search_query("")
	view_model.set_active_filter(view_model.FILTER_CONSTRUCTION)
	var construction_model: Dictionary = view_model.build_container(controller.player_inventory_id)
	_assert(int(construction_model.get("projected_total_count", 0)) == 1, "Construction filter must project only the mount stack")
	_assert(String(construction_model.get("cells", [])[0].get("definition_id", "")) == "beacon_mount_base", "Construction filter must use item tags")
	view_model.set_active_filter(view_model.FILTER_ALL)
	view_model.set_sort_mode(view_model.SORT_MASS)
	var mass_model: Dictionary = view_model.build_container(controller.player_inventory_id)
	_assert(String(mass_model.get("cells", [])[0].get("definition_id", "")) == "beacon_mount_base", "Mass sorting must use total stack mass descending")
	_assert(backpack.item_ids == original_order and int(backpack.revision) == original_revision, "Search/filter/sort must not mutate container order or revision")

	# Recent sorting uses globally comparable successful operation sequence, not item-local revision.
	var recent_container := ContainerState.new({
		"container_id": RECENT_CONTAINER_ID,
		"owner_kind": "SYSTEM",
		"owner_id": "ui-i2-recent-test",
		"storage_mode": ContainerState.STORAGE_BULK,
		"slot_count": 8,
		"maximum_mass_kg": -1.0,
		"maximum_volume_l": -1.0,
	})
	_assert(controller.domain.containers.add_container(recent_container), "Recent-sort test container must register")
	var old_high_revision = controller.domain.items.create_item("lunar_rock", 1, {}, Relations.container(RECENT_CONTAINER_ID))
	var newly_changed = controller.domain.items.create_item("battery_pack", 1, {}, Relations.container(RECENT_CONTAINER_ID))
	recent_container.assign_item(old_high_revision.instance_id)
	recent_container.assign_item(newly_changed.instance_id)
	old_high_revision.revision = 10
	newly_changed.revision = 1
	controller.domain.operations.remember_terminal(
		"ui-i2-recent-old",
		"ui_i2_test_touch",
		"hash-old",
		old_high_revision.instance_id,
		9,
		10,
		"SUCCEEDED",
		{"success": true, "item_id": old_high_revision.instance_id}
	)
	controller.domain.operations.remember_terminal(
		"ui-i2-recent-new",
		"ui_i2_test_touch",
		"hash-new",
		newly_changed.instance_id,
		0,
		1,
		"SUCCEEDED",
		{"success": true, "item_id": newly_changed.instance_id}
	)
	view_model.set_sort_mode(view_model.SORT_RECENT)
	var recent_model: Dictionary = view_model.build_container(RECENT_CONTAINER_ID)
	_assert(String(recent_model.get("cells", [])[0].get("item_id", "")) == newly_changed.instance_id, "Recent sorting must prefer the later ledger sequence even when its local revision is lower")
	_assert(int(recent_model.get("cells", [])[0].get("activity_sequence", 0)) > int(recent_model.get("cells", [])[1].get("activity_sequence", 0)), "Recent sorting must expose globally comparable operation activity sequence")
	view_model.set_sort_mode(view_model.SORT_CONTAINER_ORDER)

	# SLOTS search keeps physical slots and dims nonmatching occupants instead of reordering them.
	var rack = _find_item(controller, "battery_rack", "", Relations.WORLD)
	_assert_success(controller.open_container(rack.get_owned_container_id()), "UI-I2 fixture must open rack")
	view_model.set_search_query("Полевой")
	screen.refresh()
	var slot_model: Dictionary = screen.external_panel.current_model
	_assert(int(slot_model.get("rendered_cell_count", 0)) == 4, "Filtered SLOTS container must preserve all four physical slots")
	_assert(int(slot_model.get("physical_cell_count", 0)) == 4, "SLOTS projection must report physical slots separately from matches")
	_assert(int(slot_model.get("used_entries", 0)) == 1, "Rack fixture must contain one occupied slot")
	_assert(int(slot_model.get("matched_count", -1)) == 0, "Empty physical slots must not count as search matches")
	_assert(int(slot_model.get("projected_total_count", -1)) == 0, "SLOTS projected total must count matching occupied slots only")
	var occupied_slot := Dictionary(slot_model.get("cells", [])[0])
	_assert(not bool(occupied_slot.get("projection_match", true)), "Nonmatching occupied slot must be marked dim rather than removed")
	screen._update_projection_summary({}, slot_model)
	_assert(screen.projection_summary.text.begins_with("Показано 0 из 1 агрегатов"), "SLOTS summary must use matched occupied count instead of physical slot count")
	view_model.set_search_query("")

	# Persistent inspector is driven by selected item and exposes canonical read-only state.
	controller.set_inventory_visible(true)
	screen.refresh()
	var battery = _find_item(controller, "battery_pack", controller.player_inventory_id)
	var battery_cell = screen.player_panel.find_cell_by_item_id(battery.instance_id)
	_assert(battery_cell != null, "Battery cell must be visible for inspector test")
	var select_event := InputEventMouseButton.new()
	select_event.button_index = MOUSE_BUTTON_LEFT
	select_event.pressed = true
	battery_cell._gui_input(select_event)
	_assert(screen.inspector.current_item_id == battery.instance_id, "Single LMB press must select item in persistent inspector")
	var inspector_snapshot: Dictionary = screen.inspector.create_debug_snapshot()
	_assert(bool(inspector_snapshot.get("has_content", false)), "Inspector snapshot must expose selected item")
	_assert(String(inspector_snapshot.get("model", {}).get("relation", {}).get("kind", "")) == Relations.CONTAINER, "Inspector must expose canonical relation")
	_assert(int(inspector_snapshot.get("model", {}).get("revision", -1)) == int(battery.revision), "Inspector must expose item revision")

	# Preferences store is isolated from Item Graph and round-trips UI-only settings.
	var preferences := PreferencesStore.new()
	preferences.setup("ui_i2_test_profile")
	preferences.delete_preferences()
	_assert(preferences.save_preferences({
		"search_query": "камень",
		"active_filter": view_model.FILTER_RESOURCE,
		"sort_mode": view_model.SORT_VOLUME,
		"inspector_visible": false,
	}), "Preferences store must save UI-only settings")
	var loaded_preferences := preferences.load_preferences()
	_assert(String(loaded_preferences.get("search_query", "")) == "камень", "Preferences must restore search query")
	_assert(String(loaded_preferences.get("active_filter", "")) == view_model.FILTER_RESOURCE, "Preferences must restore category filter")
	_assert(String(loaded_preferences.get("sort_mode", "")) == view_model.SORT_VOLUME, "Preferences must restore sort mode")
	_assert(not bool(loaded_preferences.get("inspector_visible", true)), "Preferences must restore inspector visibility")
	_assert(backpack.item_ids == original_order and int(backpack.revision) == original_revision, "Saving UI preferences must not mutate Item Graph")
	preferences.delete_preferences()

	# Large BULK storage uses a bounded page window and reuses pooled cell nodes.
	var large_container := ContainerState.new({
		"container_id": LARGE_CONTAINER_ID,
		"owner_kind": "SYSTEM",
		"owner_id": "ui-i2-test",
		"storage_mode": ContainerState.STORAGE_BULK,
		"slot_count": 200,
		"maximum_mass_kg": -1.0,
		"maximum_volume_l": -1.0,
	})
	_assert(controller.domain.containers.add_container(large_container), "Large test container must register")
	for index in range(100):
		var rock = controller.domain.items.create_item("lunar_rock", 1, {"ui_i2_index": index}, Relations.container(LARGE_CONTAINER_ID))
		large_container.assign_item(rock.instance_id)
	for index in range(30):
		var pack = controller.domain.items.create_item("battery_pack", 1, {"ui_i2_index": 1000 + index}, Relations.container(LARGE_CONTAINER_ID))
		large_container.assign_item(pack.instance_id)
	view_model.set_search_query("")
	view_model.set_active_filter(view_model.FILTER_ALL)
	view_model.set_sort_mode(view_model.SORT_NAME)
	screen.open_external_container(LARGE_CONTAINER_ID)
	var large_model: Dictionary = screen.external_panel.current_model
	_assert(bool(large_model.get("virtualized", false)), "130 projected aggregates must activate large-storage virtualization")
	_assert(int(large_model.get("projected_total_count", 0)) == 130, "Virtual model must preserve total projected count")
	_assert(int(large_model.get("rendered_cell_count", 0)) == view_model.VIRTUAL_PAGE_SIZE, "First virtual page must render bounded page size only")
	_assert(screen.external_panel.get_pool_size() == view_model.VIRTUAL_PAGE_SIZE, "Cell pool must be bounded to first virtual page size")
	_assert(int(large_model.get("page_count", 0)) == 2, "130 items must produce two virtual pages")
	screen._on_page_requested(LARGE_CONTAINER_ID, 1)
	var second_page: Dictionary = screen.external_panel.current_model
	_assert(int(second_page.get("page_index", -1)) == 1, "Next page request must update projection page")
	_assert(int(second_page.get("rendered_cell_count", 0)) == 34, "Second page must render only remaining aggregates")
	_assert(screen.external_panel.get_pool_size() == view_model.VIRTUAL_PAGE_SIZE, "Page change must reuse existing pooled cells")
	view_model.set_active_filter(view_model.FILTER_RESOURCE)
	screen.refresh()
	var hundred_results: Dictionary = screen.external_panel.current_model
	_assert(bool(hundred_results.get("virtualized", false)), "100 BULK results must activate the 96-cell page window")
	_assert(int(hundred_results.get("projected_total_count", 0)) == 100, "100-result projection must preserve matched aggregate count")
	_assert(int(hundred_results.get("rendered_cell_count", 0)) == view_model.VIRTUAL_PAGE_SIZE, "100-result first page must render exactly 96 cards")
	_assert(screen.external_panel.get_pool_size() == view_model.VIRTUAL_PAGE_SIZE, "BULK card pool must never exceed 96 for the 97-120 range")
	_assert(int(hundred_results.get("page_count", 0)) == 2, "100 results must produce a second page")
	screen._on_page_requested(LARGE_CONTAINER_ID, 1)
	var hundred_second_page: Dictionary = screen.external_panel.current_model
	_assert(int(hundred_second_page.get("rendered_cell_count", 0)) == 4, "Second page of 100 results must contain four cards")
	_assert(screen.external_panel.get_pool_size() == view_model.VIRTUAL_PAGE_SIZE, "Second page must reuse the bounded 96-card pool")
	view_model.set_active_filter(view_model.FILTER_BATTERY)
	screen.refresh()
	var filtered_large: Dictionary = screen.external_panel.current_model
	_assert(not bool(filtered_large.get("virtualized", true)), "Filtering to 30 batteries must disable virtualization")
	_assert(int(filtered_large.get("rendered_cell_count", 0)) == 30, "Filtered large storage must render all matching aggregates")
	_assert(screen.external_panel.get_pool_size() == view_model.VIRTUAL_PAGE_SIZE, "Filtering down must retain, but never exceed, the bounded 96-card pool")

	_assert_success(controller.domain.validator.validate_graph(), "UI-I2 projection and pooling must preserve graph validity")
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
		print("Inventory UI-I2 large storage: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Inventory UI-I2 large storage: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
