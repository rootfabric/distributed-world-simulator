class_name InventoryViewModel
extends RefCounted

const SORT_CONTAINER_ORDER: String = "CONTAINER_ORDER"
const SORT_NAME: String = "NAME"
const SORT_TYPE: String = "TYPE"
const SORT_QUANTITY: String = "QUANTITY"
const SORT_MASS: String = "MASS"
const SORT_VOLUME: String = "VOLUME"
const SORT_RECENT: String = "RECENT"

const FILTER_ALL: String = "ALL"
const FILTER_RESOURCE: String = "RESOURCE"
const FILTER_TOOL: String = "TOOL"
const FILTER_CONTAINER: String = "CONTAINER"
const FILTER_BATTERY: String = "BATTERY"
const FILTER_MOUNTABLE: String = "MOUNTABLE"
const FILTER_CONSTRUCTION: String = "CONSTRUCTION"

const VIRTUAL_PAGE_SIZE: int = 96
const VIRTUALIZATION_THRESHOLD: int = VIRTUAL_PAGE_SIZE

const FILTER_TAGS := {
	FILTER_RESOURCE: ["resource", "rock", "ore", "material"],
	FILTER_TOOL: ["tool", "sensor", "beacon", "electronic"],
	FILTER_CONTAINER: ["container", "rack"],
	FILTER_BATTERY: ["battery", "power"],
	FILTER_MOUNTABLE: ["mountable", "mount_socket"],
	FILTER_CONSTRUCTION: ["construction", "placeable", "assembly_root", "mount_socket"],
}

var gameplay_controller
var search_query: String = ""
var active_filters: PackedStringArray = PackedStringArray()
var active_filter: String = FILTER_ALL
var sort_mode: String = SORT_CONTAINER_ORDER
var selected_item_id: String = ""
var pending_operation: Dictionary = {}
var container_pages: Dictionary = {}
var _activity_sequences: Dictionary = {}
var _activity_ledger_next_sequence: int = -1
var _activity_ledger_generation: int = -1
var _activity_ledger_instance_id: int = 0


func setup(controller) -> void:
	gameplay_controller = controller


func set_search_query(value: String) -> void:
	var normalized := value.strip_edges()
	if normalized == search_query:
		return
	search_query = normalized
	reset_projection_pages()


func set_active_filter(value: String) -> void:
	var normalized := value.strip_edges().to_upper()
	if normalized not in [FILTER_ALL, FILTER_RESOURCE, FILTER_TOOL, FILTER_CONTAINER, FILTER_BATTERY, FILTER_MOUNTABLE, FILTER_CONSTRUCTION]:
		normalized = FILTER_ALL
	active_filter = normalized
	active_filters = PackedStringArray() if normalized == FILTER_ALL else PackedStringArray([normalized])
	reset_projection_pages()


func set_active_filters(values: PackedStringArray) -> void:
	active_filters = values.duplicate()
	active_filter = FILTER_ALL if values.is_empty() else String(values[0]).to_upper()
	reset_projection_pages()


func set_sort_mode(value: String) -> void:
	var normalized: String = value.to_upper()
	if normalized not in [SORT_CONTAINER_ORDER, SORT_NAME, SORT_TYPE, SORT_QUANTITY, SORT_MASS, SORT_VOLUME, SORT_RECENT]:
		normalized = SORT_CONTAINER_ORDER
	if normalized == sort_mode:
		return
	sort_mode = normalized
	reset_projection_pages()


func set_selected_item(item_id: String) -> void:
	selected_item_id = item_id


func clear_selected_item() -> void:
	selected_item_id = ""


func set_container_page(container_id: String, page_index: int) -> void:
	if container_id.is_empty():
		return
	container_pages[container_id] = maxi(0, page_index)


func reset_projection_pages() -> void:
	container_pages.clear()


func apply_preferences(preferences: Dictionary) -> void:
	set_search_query(String(preferences.get("search_query", "")))
	set_active_filter(String(preferences.get("active_filter", FILTER_ALL)))
	set_sort_mode(String(preferences.get("sort_mode", SORT_CONTAINER_ORDER)))


func preferences_snapshot(inspector_visible: bool = true) -> Dictionary:
	return {
		"search_query": search_query,
		"active_filter": active_filter,
		"sort_mode": sort_mode,
		"inspector_visible": inspector_visible,
	}


func build_screen(external_container_id: String = "") -> Dictionary:
	if gameplay_controller == null:
		return {
			"schema": "planet_simulator.inventory_view.v2",
			"success": false,
			"error_code": "CONTROLLER_NOT_READY",
		}
	var player_model: Dictionary = build_container(gameplay_controller.player_inventory_id)
	var hotbar_model: Dictionary = build_container(
		gameplay_controller.player_hotbar_id,
		int(gameplay_controller.selected_hotbar_index)
	)
	var external_model: Dictionary = {}
	if not external_container_id.is_empty():
		external_model = build_container(external_container_id)
	return {
		"schema": "planet_simulator.inventory_view.v2",
		"success": true,
		"player": player_model,
		"hotbar": hotbar_model,
		"external": external_model,
		"external_container_id": external_container_id,
		"search_query": search_query,
		"active_filter": active_filter,
		"active_filters": Array(active_filters),
		"sort_mode": sort_mode,
		"selected_item_id": selected_item_id,
		"selected_item": build_item_inspector(selected_item_id),
		"pending_operation": pending_operation.duplicate(true),
	}


func build_container(container_id: String, selected_slot_index: int = -1) -> Dictionary:
	if gameplay_controller == null:
		return {}
	var container = gameplay_controller.get_container(container_id)
	if container == null:
		return {}
	_refresh_activity_sequences()
	var all_cells: Array[Dictionary] = []
	var matched_count := 0
	if container.is_slot_container():
		for slot_index in range(int(container.slot_count)):
			var item_id: String = String(container.get_item_at_slot(slot_index))
			var cell := _build_cell(
				item_id,
				container_id,
				slot_index,
				slot_index == selected_slot_index,
				container.get_slot_rule(slot_index)
			)
			cell["projection_match"] = _matches_projection(cell)
			if not item_id.is_empty() and bool(cell.projection_match):
				matched_count += 1
			all_cells.append(cell)
	else:
		for item_id_value in container.item_ids:
			var cell: Dictionary = _build_cell(String(item_id_value), container_id, -1, false, {})
			if _matches_projection(cell):
				cell["projection_match"] = true
				all_cells.append(cell)
		_sort_cells(all_cells)
		matched_count = all_cells.size()

	var projected_total := matched_count if container.is_slot_container() else all_cells.size()
	var virtualized: bool = not container.is_slot_container() and projected_total > VIRTUALIZATION_THRESHOLD
	var page_count := maxi(1, ceili(float(projected_total) / float(VIRTUAL_PAGE_SIZE)))
	var requested_page := int(container_pages.get(container_id, 0))
	var page_index := clampi(requested_page, 0, page_count - 1)
	container_pages[container_id] = page_index
	var cells: Array[Dictionary] = all_cells
	if virtualized:
		var start_index := page_index * VIRTUAL_PAGE_SIZE
		var end_index := mini(projected_total, start_index + VIRTUAL_PAGE_SIZE)
		cells = []
		for index in range(start_index, end_index):
			cells.append(all_cells[index])

	var used_entries: int = int(container.item_ids.size())
	var visual_capacity: int = _visual_capacity(container)
	var maximum_mass: float = float(container.maximum_mass_kg)
	var maximum_volume: float = float(container.maximum_volume_l)
	var current_mass: float = 0.0
	var current_volume: float = 0.0
	if gameplay_controller.domain.has("mass"):
		current_mass = float(gameplay_controller.domain.mass.container_mass_kg(container_id))
		current_volume = float(gameplay_controller.domain.mass.container_direct_volume_l(container_id))
	return {
		"schema": "planet_simulator.container_view.v2",
		"container_id": container_id,
		"display_name": gameplay_controller.get_container_display_name(container_id),
		"storage_mode": String(container.storage_mode),
		"is_slot_container": bool(container.is_slot_container()),
		"slot_count": int(container.slot_count),
		"used_entries": used_entries,
		"visual_capacity": visual_capacity,
		"columns": _columns_for_capacity(visual_capacity),
		"cells": cells,
		"rendered_cell_count": cells.size(),
		"physical_cell_count": all_cells.size(),
		"projected_total_count": projected_total,
		"matched_count": matched_count,
		"unfiltered_count": used_entries,
		"virtualized": virtualized,
		"page_index": page_index,
		"page_count": page_count,
		"page_size": VIRTUAL_PAGE_SIZE,
		"pooling_enabled": true,
		"current_mass_kg": current_mass,
		"maximum_mass_kg": maximum_mass,
		"current_volume_l": current_volume,
		"maximum_volume_l": maximum_volume,
		"allow_nested_containers": bool(container.allow_nested_containers),
		"revision": int(container.revision),
	}


func build_item_inspector(item_id: String) -> Dictionary:
	if gameplay_controller == null or item_id.is_empty():
		return {}
	var item = gameplay_controller.get_item(item_id)
	if item == null:
		return {}
	var cell := _build_cell(item_id, String(item.relation.get("container_id", "")), int(item.relation.get("slot_index", -1)), false, {})
	cell["relation"] = Dictionary(item.relation).duplicate(true)
	cell["components"] = Dictionary(item.components).duplicate(true)
	cell["owned_container_id"] = String(item.get_owned_container_id()) if item.owns_container() else ""
	var definition = gameplay_controller.get_definition(item.definition_id)
	cell["definition_metadata"] = Dictionary(definition.metadata).duplicate(true) if definition != null else {}
	return cell


func _build_cell(
	item_id: String,
	container_id: String,
	slot_index: int,
	selected: bool,
	slot_rule: Dictionary
) -> Dictionary:
	var item = gameplay_controller.get_item(item_id) if not item_id.is_empty() else null
	var definition = gameplay_controller.get_definition(item.definition_id) if item != null else null
	var display_name: String = "Пусто"
	var definition_id: String = ""
	var quantity: int = 0
	var tags: Array = []
	var icon_color: Array = []
	var revision: int = -1
	var unit_mass_kg: float = 0.0
	var unit_volume_l: float = 0.0
	var max_stack: int = 1
	var owns_container: bool = false
	var relation_kind: String = ""
	if item != null:
		definition_id = String(item.definition_id)
		quantity = int(item.quantity)
		revision = int(item.revision)
		owns_container = bool(item.owns_container())
		relation_kind = String(item.relation.get("kind", ""))
		if not String(item.display_name).is_empty():
			display_name = String(item.display_name)
		elif definition != null:
			display_name = String(definition.display_name)
	if definition != null:
		tags = Array(definition.tags).duplicate()
		icon_color = Array(definition.metadata.get("icon_color", [])).duplicate()
		unit_mass_kg = float(definition.unit_mass_kg)
		unit_volume_l = float(definition.external_volume_l)
		max_stack = int(definition.max_stack)
	return {
		"item_id": item_id,
		"definition_id": definition_id,
		"display_name": display_name,
		"quantity": quantity,
		"revision": revision,
		"activity_sequence": int(_activity_sequences.get(item_id, 0)),
		"tags": tags,
		"icon_color": icon_color,
		"unit_mass_kg": unit_mass_kg,
		"unit_volume_l": unit_volume_l,
		"total_mass_kg": unit_mass_kg * quantity,
		"total_volume_l": unit_volume_l * quantity,
		"max_stack": max_stack,
		"owns_container": owns_container,
		"relation_kind": relation_kind,
		"source_container_id": container_id,
		"source_slot_index": slot_index,
		"target_container_id": container_id,
		"target_slot_index": slot_index,
		"selected": selected,
		"inspected": not item_id.is_empty() and item_id == selected_item_id,
		"slot_rule": slot_rule.duplicate(true),
		"projection_match": true,
	}


func _matches_projection(cell: Dictionary) -> bool:
	if String(cell.get("item_id", "")).is_empty():
		return true
	if not search_query.is_empty():
		var query: String = search_query.to_lower()
		var haystack: String = "%s %s %s %s" % [
			String(cell.get("display_name", "")),
			String(cell.get("definition_id", "")),
			" ".join(PackedStringArray(cell.get("tags", []))),
			String(cell.get("relation_kind", "")),
		]
		if not haystack.to_lower().contains(query):
			return false
	if active_filter != FILTER_ALL:
		var accepted_tags: Array = Array(FILTER_TAGS.get(active_filter, []))
		var tags := PackedStringArray(cell.get("tags", []))
		var matched := false
		for accepted_tag_value in accepted_tags:
			if tags.has(String(accepted_tag_value)):
				matched = true
				break
		if not matched:
			return false
	return true


func _sort_cells(cells: Array[Dictionary]) -> void:
	match sort_mode:
		SORT_NAME:
			cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return String(a.get("display_name", "")).naturalnocasecmp_to(String(b.get("display_name", ""))) < 0
			)
		SORT_TYPE:
			cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return String(a.get("definition_id", "")).naturalnocasecmp_to(String(b.get("definition_id", ""))) < 0
			)
		SORT_QUANTITY:
			cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a.get("quantity", 0)) > int(b.get("quantity", 0))
			)
		SORT_MASS:
			cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return float(a.get("total_mass_kg", 0.0)) > float(b.get("total_mass_kg", 0.0))
			)
		SORT_VOLUME:
			cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return float(a.get("total_volume_l", 0.0)) > float(b.get("total_volume_l", 0.0))
			)
		SORT_RECENT:
			cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var sequence_a := int(a.get("activity_sequence", 0))
				var sequence_b := int(b.get("activity_sequence", 0))
				if sequence_a == sequence_b:
					return String(a.get("item_id", "")) < String(b.get("item_id", ""))
				return sequence_a > sequence_b
			)
		_:
			pass


func _refresh_activity_sequences() -> void:
	if gameplay_controller == null or not gameplay_controller.domain.has("operations"):
		_activity_sequences.clear()
		_activity_ledger_next_sequence = -1
		_activity_ledger_generation = -1
		_activity_ledger_instance_id = 0
		return
	var ledger = gameplay_controller.domain.operations
	var next_sequence := int(ledger.next_sequence)
	var generation := int(ledger.get_content_generation()) if ledger.has_method("get_content_generation") else -1
	var instance_id := int(ledger.get_instance_id())
	if (
		next_sequence == _activity_ledger_next_sequence
		and generation == _activity_ledger_generation
		and instance_id == _activity_ledger_instance_id
	):
		return
	_activity_ledger_next_sequence = next_sequence
	_activity_ledger_generation = generation
	_activity_ledger_instance_id = instance_id
	_activity_sequences.clear()
	var snapshot: Dictionary = ledger.to_dict()
	for record_value in Array(snapshot.get("records", [])):
		var record := Dictionary(record_value)
		if String(record.get("status", "")) != "SUCCEEDED":
			continue
		var sequence := int(record.get("sequence", 0))
		var related_ids := PackedStringArray()
		_append_activity_id(related_ids, String(record.get("aggregate_id", "")))
		var result := Dictionary(record.get("result", {}))
		for key in ["item_id", "source_item_id", "target_item_id", "result_item_id", "new_item_id", "merged_into_item_id"]:
			_append_activity_id(related_ids, String(result.get(key, "")))
		for merged_id_value in Array(result.get("merged_into_item_ids", [])):
			_append_activity_id(related_ids, String(merged_id_value))
		for item_id in related_ids:
			_activity_sequences[item_id] = maxi(int(_activity_sequences.get(item_id, 0)), sequence)


func _append_activity_id(target: PackedStringArray, item_id: String) -> void:
	if item_id.is_empty() or target.has(item_id):
		return
	target.append(item_id)


func _visual_capacity(container) -> int:
	if container.is_slot_container():
		return maxi(1, int(container.slot_count))
	if int(container.slot_count) > 0:
		return maxi(int(container.slot_count), int(container.item_ids.size()))
	return maxi(1, int(container.item_ids.size()))


func _columns_for_capacity(capacity: int) -> int:
	if capacity <= 4:
		return maxi(1, capacity)
	if capacity <= 8:
		return 4
	if capacity <= 18:
		return 6
	return 8
