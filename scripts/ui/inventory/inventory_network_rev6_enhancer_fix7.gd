extends "res://scripts/ui/inventory/inventory_network_rev6_enhancer_fix6.gd"

# Fix7 gives sort the same optimistic-presentation semantics as cursor carry.
# The user sees the final sorted/merged slot layout immediately on the click,
# while fix5/fix6 continue to execute the real authoritative item.transfer
# sequence in the background. The preview survives normal InventoryScreen
# refreshes and is removed only when the local replica matches it, or rolled
# back if authority rejects the sort.

const FIX7_SCHEMA: String = "planet_simulator.inventory_network_rev6_enhancer.fix7.v1"
const SORT_PREVIEW_RECONCILE_TIMEOUT_MS: int = 5000

var _sort_preview_expected_signatures: Dictionary = {}
var _sort_preview_deadlines_msec: Dictionary = {}
var _sort_preview_activations: int = 0
var _sort_preview_reconciliations: int = 0
var _sort_preview_rollbacks: int = 0
var _sort_preview_timeouts: int = 0


func setup(controller, network_bridge) -> Dictionary:
	var result: Dictionary = super.setup(controller, network_bridge)
	if not bool(result.get("success", false)):
		return result
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["schema"] = FIX7_SCHEMA
	details["sort_presentation"] = "OPTIMISTIC_FINAL_LAYOUT_UNTIL_REPLICA_MATCH"
	details["sort_preview_reconcile_timeout_ms"] = SORT_PREVIEW_RECONCILE_TIMEOUT_MS
	result["details"] = details
	return result


func _process(delta: float) -> void:
	super._process(delta)
	_reconcile_sort_presentation_overrides()


func _dispatch_sort_press(external: bool, activation_source: String) -> void:
	var container_id := (
		String(screen.get("external_container_id"))
		if external and screen != null
		else String(gameplay_controller.player_inventory_id)
	)

	# Build the presentation candidate before the parent starts the first
	# predicted transfer, so the user sees one stable final layout rather than a
	# sequence of intermediate server-confirmed permutations.
	var preview_model: Dictionary = {}
	if (
		not container_id.is_empty()
		and not _sort_in_progress
		and not _pickup_merge_in_progress
		and screen != null
		and not _session_is_active(screen.get("transfer_session"))
	):
		preview_model = _build_optimistic_sort_preview(container_id)

	super._dispatch_sort_press(external, activation_source)

	if not preview_model.is_empty() and _sort_in_progress:
		_activate_sort_presentation_override(container_id, preview_model)


func _run_sort_container(container_id: String, player_inventory: bool) -> void:
	var completed_before: int = _sort_operations
	await super._run_sort_container(container_id, player_inventory)

	if _sort_operations <= completed_before:
		# Parent reports any authority failure to the user. Presentation must
		# immediately return to the real replica state in that case.
		_clear_sort_presentation_override(container_id, true, "authority_failure")
		return

	# Successful authority completion may race the final projected snapshot by a
	# frame. Keep the optimistic layout until the replica has the same cells and
	# quantities; the process loop will then remove the overlay without a flicker.
	_try_reconcile_sort_presentation_override(container_id)


func _activate_sort_presentation_override(container_id: String, preview_model: Dictionary) -> void:
	if projection == null or not projection.has_method("set_container_presentation_override"):
		return
	projection.call("set_container_presentation_override", container_id, preview_model)
	_sort_preview_expected_signatures[container_id] = _model_signature(preview_model)
	_sort_preview_deadlines_msec[container_id] = Time.get_ticks_msec() + SORT_PREVIEW_RECONCILE_TIMEOUT_MS
	_sort_preview_activations += 1
	_refresh_screen()
	print("[inventory_sort] %s" % JSON.stringify({
		"event": "SORT_PRESENTATION_APPLIED",
		"container_id": container_id,
		"signature": String(_sort_preview_expected_signatures[container_id]),
	}, "", true, true))


func _clear_sort_presentation_override(container_id: String, refresh_after: bool, reason: String) -> void:
	if projection != null and projection.has_method("clear_container_presentation_override"):
		projection.call("clear_container_presentation_override", container_id)
	_sort_preview_expected_signatures.erase(container_id)
	_sort_preview_deadlines_msec.erase(container_id)
	if reason == "authority_failure":
		_sort_preview_rollbacks += 1
	elif reason == "timeout":
		_sort_preview_timeouts += 1
	if refresh_after:
		_refresh_screen()
	print("[inventory_sort] %s" % JSON.stringify({
		"event": "SORT_PRESENTATION_CLEARED",
		"container_id": container_id,
		"reason": reason,
	}, "", true, true))


func _reconcile_sort_presentation_overrides() -> void:
	if _sort_preview_expected_signatures.is_empty() or _sort_in_progress:
		return
	for container_id_value in _sort_preview_expected_signatures.keys().duplicate():
		var container_id := String(container_id_value)
		if _try_reconcile_sort_presentation_override(container_id):
			continue
		var deadline: int = int(_sort_preview_deadlines_msec.get(container_id, 0))
		if deadline > 0 and Time.get_ticks_msec() >= deadline:
			_clear_sort_presentation_override(container_id, true, "timeout")


func _try_reconcile_sort_presentation_override(container_id: String) -> bool:
	if not _sort_preview_expected_signatures.has(container_id):
		return true
	var actual_model: Dictionary = _build_physical_container_model(container_id)
	if actual_model.is_empty():
		return false
	var expected_signature: String = String(_sort_preview_expected_signatures[container_id])
	if _model_signature(actual_model) != expected_signature:
		return false
	_sort_preview_reconciliations += 1
	_clear_sort_presentation_override(container_id, true, "replica_match")
	return true


func _build_optimistic_sort_preview(container_id: String) -> Dictionary:
	if screen == null or projection == null:
		return {}
	var view_model = screen.get("view_model")
	if view_model == null or not view_model.has_method("build_container"):
		return {}

	# Remove any stale preview before reading the physical slot model.
	if projection.has_method("clear_container_presentation_override"):
		projection.call("clear_container_presentation_override", container_id)
	var raw_value = view_model.call("build_container", container_id)
	if not raw_value is Dictionary:
		return {}
	var projected_value = projection.call("project_container", Dictionary(raw_value))
	if not projected_value is Dictionary:
		return {}
	var model: Dictionary = Dictionary(projected_value).duplicate(true)
	if model.is_empty() or not bool(model.get("is_slot_container", false)):
		return {}

	var source_cells: Array = Array(model.get("cells", []))
	var entries: Array[Dictionary] = []
	for cell_value in source_cells:
		if not cell_value is Dictionary:
			continue
		var cell: Dictionary = Dictionary(cell_value).duplicate(true)
		if String(cell.get("item_id", "")).is_empty():
			continue
		entries.append(cell)

	# Match the authoritative merge policy: earlier physical stacks receive
	# compatible quantities first, respecting max_stack, then survivors sort by
	# display name.
	for target_index in range(entries.size()):
		if int(entries[target_index].get("quantity", 0)) <= 0:
			continue
		for source_index in range(target_index + 1, entries.size()):
			if int(entries[source_index].get("quantity", 0)) <= 0:
				continue
			if not _preview_cells_stack_compatible(entries[target_index], entries[source_index]):
				continue
			var max_stack: int = maxi(1, int(entries[target_index].get("max_stack", 1)))
			var headroom: int = maxi(0, max_stack - int(entries[target_index].get("quantity", 0)))
			if headroom <= 0:
				break
			var moved: int = mini(headroom, int(entries[source_index].get("quantity", 0)))
			if moved <= 0:
				continue
			entries[target_index]["quantity"] = int(entries[target_index].get("quantity", 0)) + moved
			entries[source_index]["quantity"] = int(entries[source_index].get("quantity", 0)) - moved

	var survivors: Array[Dictionary] = []
	for entry in entries:
		if int(entry.get("quantity", 0)) > 0:
			survivors.append(entry.duplicate(true))
	survivors.sort_custom(Callable(self, "_compare_preview_cells_by_name"))

	var capacity: int = maxi(
		int(model.get("visual_capacity", model.get("slot_count", 0))),
		source_cells.size()
	)
	capacity = maxi(1, capacity)
	var result_cells: Array[Dictionary] = []
	for slot_index in range(capacity):
		var template: Dictionary = (
			Dictionary(source_cells[slot_index]).duplicate(true)
			if slot_index < source_cells.size() and source_cells[slot_index] is Dictionary
			else {}
		)
		result_cells.append(_empty_preview_cell(template, container_id, slot_index))

	for slot_index in range(mini(survivors.size(), capacity)):
		var cell: Dictionary = survivors[slot_index].duplicate(true)
		cell["source_container_id"] = container_id
		cell["source_slot_index"] = slot_index
		cell["target_container_id"] = container_id
		cell["target_slot_index"] = slot_index
		cell["presentation_sort_preview"] = true
		cell.erase("carry_remainder")
		cell.erase("carried_quantity")
		cell.erase("carry_suppressed")
		result_cells[slot_index] = cell

	model["cells"] = result_cells
	model["used_entries"] = survivors.size()
	model["unfiltered_count"] = survivors.size()
	model["matched_count"] = survivors.size()
	model["projected_total_count"] = survivors.size()
	model["rendered_cell_count"] = result_cells.size()
	model["physical_cell_count"] = result_cells.size()
	model["presentation_sort_preview"] = true
	return model


func _build_physical_container_model(container_id: String) -> Dictionary:
	if screen == null:
		return {}
	var view_model = screen.get("view_model")
	if view_model == null or not view_model.has_method("build_container"):
		return {}
	var value = view_model.call("build_container", container_id)
	return Dictionary(value).duplicate(true) if value is Dictionary else {}


func _preview_cells_stack_compatible(a: Dictionary, b: Dictionary) -> bool:
	if String(a.get("definition_id", "")) != String(b.get("definition_id", "")):
		return false
	if bool(a.get("owns_container", false)) or bool(b.get("owns_container", false)):
		return false
	var item_a = gameplay_controller.get_item(String(a.get("item_id", "")))
	var item_b = gameplay_controller.get_item(String(b.get("item_id", "")))
	if item_a != null and item_b != null and item_a.has_method("is_stack_compatible"):
		return bool(item_a.call("is_stack_compatible", item_b))
	return true


func _compare_preview_cells_by_name(a: Dictionary, b: Dictionary) -> bool:
	var name_compare: int = String(a.get("display_name", "")).naturalnocasecmp_to(
		String(b.get("display_name", ""))
	)
	if name_compare != 0:
		return name_compare < 0
	var definition_a: String = String(a.get("definition_id", ""))
	var definition_b: String = String(b.get("definition_id", ""))
	if definition_a != definition_b:
		return definition_a < definition_b
	return String(a.get("item_id", "")) < String(b.get("item_id", ""))


func _empty_preview_cell(template: Dictionary, container_id: String, slot_index: int) -> Dictionary:
	var cell: Dictionary = template.duplicate(true)
	cell["item_id"] = ""
	cell["definition_id"] = ""
	cell["display_name"] = "Пусто"
	cell["quantity"] = 0
	cell["revision"] = -1
	cell["tags"] = []
	cell["icon_color"] = []
	cell["unit_mass_kg"] = 0.0
	cell["unit_volume_l"] = 0.0
	cell["total_mass_kg"] = 0.0
	cell["total_volume_l"] = 0.0
	cell["max_stack"] = 1
	cell["owns_container"] = false
	cell["relation_kind"] = ""
	cell["source_container_id"] = container_id
	cell["source_slot_index"] = slot_index
	cell["target_container_id"] = container_id
	cell["target_slot_index"] = slot_index
	cell["selected"] = false
	cell["inspected"] = false
	cell["projection_match"] = true
	cell["presentation_sort_preview"] = true
	cell.erase("carry_remainder")
	cell.erase("carried_quantity")
	cell.erase("carry_suppressed")
	return cell


func _model_signature(model: Dictionary) -> String:
	var capacity: int = maxi(
		int(model.get("visual_capacity", model.get("slot_count", 0))),
		Array(model.get("cells", [])).size()
	)
	capacity = maxi(1, capacity)
	var slots: Array = []
	slots.resize(capacity)
	for index in range(capacity):
		slots[index] = ""
	for cell_value in Array(model.get("cells", [])):
		if not cell_value is Dictionary:
			continue
		var cell: Dictionary = Dictionary(cell_value)
		var slot_index: int = int(cell.get("source_slot_index", cell.get("target_slot_index", -1)))
		if slot_index < 0 or slot_index >= capacity:
			continue
		var item_id: String = String(cell.get("item_id", ""))
		if item_id.is_empty():
			slots[slot_index] = ""
		else:
			slots[slot_index] = "%s:%d" % [item_id, int(cell.get("quantity", 0))]
	return JSON.stringify(slots)


func get_report() -> Dictionary:
	var result: Dictionary = super.get_report()
	result["schema"] = FIX7_SCHEMA
	result["sort_presentation"] = "OPTIMISTIC_FINAL_LAYOUT_UNTIL_REPLICA_MATCH"
	result["sort_preview_activations"] = _sort_preview_activations
	result["sort_preview_reconciliations"] = _sort_preview_reconciliations
	result["sort_preview_rollbacks"] = _sort_preview_rollbacks
	result["sort_preview_timeouts"] = _sort_preview_timeouts
	result["sort_preview_pending"] = _sort_preview_expected_signatures.size()
	result["sort_preview_reconcile_timeout_ms"] = SORT_PREVIEW_RECONCILE_TIMEOUT_MS
	return result
