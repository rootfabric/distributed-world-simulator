class_name InventoryCursorController
extends RefCounted

const SCHEMA: String = "planet_simulator.inventory_cursor_controller.v1"

var gameplay_controller
var command_facade: InventoryCommandFacade
var session: InventoryTransferSession
var slot_projection: InventorySlotProjection
var icon_provider: Callable
var cursor_container_id: String = ""
var _network_virtual: bool = false


func setup(
	controller,
	commands: InventoryCommandFacade,
	transfer_session: InventoryTransferSession,
	projection: InventorySlotProjection,
	icons: Callable
) -> void:
	gameplay_controller = controller
	command_facade = commands
	session = transfer_session
	slot_projection = projection
	icon_provider = icons
	cursor_container_id = "ui_cursor/%s/seven_days" % String(controller.profile_id)
	_network_virtual = false


func begin(origin_payload: Dictionary, requested_quantity: int) -> Dictionary:
	if gameplay_controller == null or command_facade == null or session == null:
		return _fail("CURSOR_CONTROLLER_NOT_READY")
	if session.is_active():
		return _fail("CURSOR_ALREADY_OCCUPIED")
	var source_item_id := String(origin_payload.get("item_id", ""))
	var available_quantity := int(origin_payload.get("quantity", 0))
	if source_item_id.is_empty() or available_quantity <= 0:
		return _fail("CARRY_SOURCE_EMPTY")
	var quantity := clampi(requested_quantity, 1, available_quantity)
	var source_item = gameplay_controller.get_item(source_item_id)
	if source_item == null:
		return _fail("CURSOR_ITEM_NOT_FOUND")
	var texture := _icon_for_payload(origin_payload)

	# A network replica must never manufacture authoritative-looking item IDs by
	# splitting/moving its local replica domain into a transient cursor container.
	# Keep the 7DTD carry as presentation state only; place/drop later use the
	# original replica ID, which the M7 adapter can map back to the canonical ID.
	if _uses_network_replica_commands():
		_network_virtual = true
		var started := session.begin_domain_backed(
			origin_payload,
			source_item_id,
			quantity,
			texture,
			int(source_item.revision),
			cursor_container_id
		)
		if not bool(started.get("success", false)):
			_network_virtual = false
			return started
		return {
			"success": true,
			"network_virtual": true,
			"carried_item_id": source_item_id,
			"cursor_container_id": cursor_container_id,
			"moved_quantity": quantity,
			"session": session.snapshot(),
		}

	_network_virtual = false
	var result: Dictionary = gameplay_controller.begin_inventory_cursor_carry(
		source_item_id,
		quantity,
		cursor_container_id
	)
	if not bool(result.get("success", false)):
		return result
	var carried_item_id := String(result.get("carried_item_id", ""))
	var carried = gameplay_controller.get_item(carried_item_id)
	if carried == null:
		return _fail("CURSOR_ITEM_NOT_FOUND")
	var started := session.begin_domain_backed(
		origin_payload,
		carried_item_id,
		int(carried.quantity),
		texture,
		int(carried.revision),
		cursor_container_id
	)
	if not bool(started.get("success", false)):
		return started
	if carried_item_id == source_item_id:
		slot_projection.remove_item(
			String(origin_payload.get("source_container_id", "")),
			source_item_id
		)
	result["session"] = session.snapshot()
	return result


func place(target_payload: Dictionary, requested_quantity: int) -> Dictionary:
	if not session.is_active() or not session.domain_backed:
		return _fail("CURSOR_NOT_ACTIVE")
	if _network_virtual:
		return _place_network_virtual(target_payload, requested_quantity)
	var carried_item_id := session.item_id
	var carried = gameplay_controller.get_item(carried_item_id)
	if carried == null:
		return _fail("CURSOR_ITEM_NOT_FOUND")
	var target_container_id := String(target_payload.get("target_container_id", target_payload.get("source_container_id", "")))
	var target_slot_index := int(target_payload.get("target_slot_index", target_payload.get("source_slot_index", -1)))
	var target_item_id := String(target_payload.get("target_item_id", target_payload.get("item_id", "")))
	if target_container_id.is_empty():
		return _fail("TARGET_CONTAINER_REQUIRED")
	if target_item_id == carried_item_id:
		return {"success": true, "no_change": true, "session_active": true}
	var quantity := clampi(requested_quantity, 1, int(carried.quantity))
	if not target_item_id.is_empty():
		var target = gameplay_controller.get_item(target_item_id)
		if target == null:
			return _fail("STACK_TARGET_NOT_FOUND")
		if not carried.is_stack_compatible(target):
			if quantity < int(carried.quantity):
				return _fail("SWAP_REQUIRES_FULL_STACK", {
					"requested_quantity": quantity,
					"carried_quantity": int(carried.quantity),
				})
			return _swap_with_target(target_payload, carried, target)

	var result := command_facade.transfer_quantity(
		carried_item_id,
		quantity,
		target_container_id,
		target_slot_index,
		target_item_id
	)
	if not bool(result.get("success", false)):
		return result
	var placed_item_id := _placed_item_id(result, carried_item_id, target_item_id)
	if target_item_id.is_empty() and not placed_item_id.is_empty() and target_slot_index >= 0:
		slot_projection.place_item(target_container_id, placed_item_id, target_slot_index)
	_sync_or_finalize()
	result["session_active"] = session.is_active()
	result["session"] = session.snapshot()
	return result


func drop_to_world(requested_quantity: int) -> Dictionary:
	if not session.is_active() or not session.domain_backed:
		return _fail("CURSOR_NOT_ACTIVE")
	if _network_virtual:
		var quantity := clampi(requested_quantity, 1, session.remaining_quantity)
		var network_result := command_facade.drop_quantity(session.item_id, quantity)
		if not bool(network_result.get("success", false)):
			return network_result
		var consumed := session.consume(quantity)
		if not session.is_active():
			_network_virtual = false
		network_result["dropped_quantity"] = consumed
		network_result["network_virtual"] = true
		network_result["session_active"] = session.is_active()
		network_result["session"] = session.snapshot()
		return network_result
	var carried = gameplay_controller.get_item(session.item_id)
	if carried == null:
		return _fail("CURSOR_ITEM_NOT_FOUND")
	var quantity := clampi(requested_quantity, 1, int(carried.quantity))
	var result := command_facade.drop_quantity(session.item_id, quantity)
	if not bool(result.get("success", false)):
		return result
	_sync_or_finalize()
	result["dropped_quantity"] = quantity
	result["session_active"] = session.is_active()
	result["session"] = session.snapshot()
	return result


func cancel() -> Dictionary:
	if not session.is_active():
		_network_virtual = false
		return {"success": true, "no_change": true}
	if _network_virtual:
		session.clear()
		_network_virtual = false
		return {"success": true, "network_virtual": true, "virtual_only": true}
	if not session.domain_backed:
		session.clear()
		return {"success": true, "virtual_only": true}
	var unwind_result := _unwind_swaps()
	if not bool(unwind_result.get("success", false)):
		return unwind_result
	var carried_item_id := session.item_id
	var origin_container_id := session.source_container_id
	var origin_slot_index := session.source_slot_index
	var target_item_id := _item_at_visual_or_domain_slot(origin_container_id, origin_slot_index)
	if target_item_id == carried_item_id:
		target_item_id = ""
	var carried = gameplay_controller.get_item(carried_item_id)
	if carried == null:
		session.clear()
		return _finalize_cursor()
	if not target_item_id.is_empty():
		var target = gameplay_controller.get_item(target_item_id)
		if target == null:
			return _fail("CANCEL_TARGET_NOT_FOUND")
		if not carried.is_stack_compatible(target):
			return _fail("CANCEL_ORIGIN_OCCUPIED", {
				"origin_container_id": origin_container_id,
				"origin_slot_index": origin_slot_index,
				"target_item_id": target_item_id,
			})
	var result := command_facade.transfer_quantity(
		carried_item_id,
		int(carried.quantity),
		origin_container_id,
		origin_slot_index,
		target_item_id
	)
	if not bool(result.get("success", false)):
		return result
	var restored_item_id := _placed_item_id(result, carried_item_id, target_item_id)
	if not restored_item_id.is_empty() and origin_slot_index >= 0:
		slot_projection.place_item(origin_container_id, restored_item_id, origin_slot_index)
	session.clear()
	var finalized := _finalize_cursor()
	if not bool(finalized.get("success", false)):
		return finalized
	result["cancelled"] = true
	result["restored_item_id"] = restored_item_id
	return result


func _place_network_virtual(target_payload: Dictionary, requested_quantity: int) -> Dictionary:
	var target_container_id := String(target_payload.get("target_container_id", target_payload.get("source_container_id", "")))
	var target_slot_index := int(target_payload.get("target_slot_index", target_payload.get("source_slot_index", -1)))
	var target_item_id := String(target_payload.get("target_item_id", target_payload.get("item_id", "")))
	if target_container_id.is_empty():
		return _fail("TARGET_CONTAINER_REQUIRED")
	if (
		target_item_id == session.origin_item_id
		and target_container_id == session.source_container_id
		and target_slot_index == session.source_slot_index
	):
		session.clear()
		_network_virtual = false
		return {"success": true, "no_change": true, "cancelled": true, "network_virtual": true}
	var quantity := clampi(requested_quantity, 1, session.remaining_quantity)
	var result := command_facade.transfer_quantity(
		session.item_id,
		quantity,
		target_container_id,
		target_slot_index,
		target_item_id
	)
	if not bool(result.get("success", false)):
		return result
	var consumed := session.consume(quantity)
	if not session.is_active():
		_network_virtual = false
	result["moved_quantity"] = int(result.get("moved_quantity", consumed))
	result["network_virtual"] = true
	result["session_active"] = session.is_active()
	result["session"] = session.snapshot()
	return result


func _uses_network_replica_commands() -> bool:
	if gameplay_controller == null:
		return false
	return (
		String(gameplay_controller.get("runtime_mode")) == "replica"
		and gameplay_controller.get("network_command_bridge") != null
	)


func _unwind_swaps() -> Dictionary:
	if session.swap_history.is_empty():
		return {"success": true, "no_change": true}
	for history_index in range(session.swap_history.size() - 1, -1, -1):
		var record := Dictionary(session.swap_history[history_index])
		var current_item_id := session.item_id
		var placed_item_id := String(record.get("placed_item_id", ""))
		var target_container_id := String(record.get("target_container_id", ""))
		var target_slot_index := int(record.get("target_slot_index", -1))
		if current_item_id.is_empty() or placed_item_id.is_empty():
			return _fail("SWAP_HISTORY_INVALID", {"history_index": history_index})
		var slot_item_id := _item_at_visual_or_domain_slot(target_container_id, target_slot_index)
		if slot_item_id != placed_item_id:
			return _fail("SWAP_HISTORY_TARGET_CHANGED", {
				"history_index": history_index,
				"expected_item_id": placed_item_id,
				"actual_item_id": slot_item_id,
			})
		var result := command_facade.swap_items(current_item_id, placed_item_id)
		if not bool(result.get("success", false)):
			return result
		if target_slot_index >= 0:
			slot_projection.swap_item_at_slot(target_container_id, target_slot_index, current_item_id)
		var restored = gameplay_controller.get_item(placed_item_id)
		if restored == null:
			return _fail("SWAP_HISTORY_RESTORED_ITEM_NOT_FOUND")
		var restored_payload := _item_payload(placed_item_id, cursor_container_id, 0)
		session.set_domain_carried_item(
			restored_payload,
			_icon_for_payload(restored_payload),
			int(restored.revision)
		)
	session.swap_history.clear()
	return {"success": true, "unwound": true}


func _item_at_visual_or_domain_slot(container_id: String, slot_index: int) -> String:
	var projected_item_id := slot_projection.item_at_slot(container_id, slot_index)
	if not projected_item_id.is_empty():
		return projected_item_id
	var container = gameplay_controller.get_container(container_id)
	if container != null and container.is_slot_container() and slot_index >= 0:
		return String(container.get_item_at_slot(slot_index))
	return ""


func debug_snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"cursor_container_id": cursor_container_id,
		"network_virtual": _network_virtual,
		"session": session.snapshot() if session != null else {},
		"projection": slot_projection.debug_snapshot() if slot_projection != null else {},
	}


func _swap_with_target(target_payload: Dictionary, carried, target) -> Dictionary:
	var target_container_id := String(target_payload.get("target_container_id", target_payload.get("source_container_id", "")))
	var target_slot_index := int(target_payload.get("target_slot_index", target_payload.get("source_slot_index", -1)))
	var carried_item_id := String(carried.instance_id)
	var target_item_id := String(target.instance_id)
	var result := command_facade.swap_items(carried_item_id, target_item_id)
	if not bool(result.get("success", false)):
		return result
	if target_slot_index >= 0:
		slot_projection.swap_item_at_slot(target_container_id, target_slot_index, carried_item_id)
	var replacement_payload := _item_payload(target_item_id, target_container_id, target_slot_index)
	session.record_domain_swap(
		target_container_id,
		target_slot_index,
		carried_item_id,
		replacement_payload,
		_icon_for_payload(replacement_payload),
		int(target.revision)
	)
	result["carried_item_id"] = target_item_id
	result["placed_item_id"] = carried_item_id
	result["session_active"] = true
	result["session"] = session.snapshot()
	return result


func _sync_or_finalize() -> void:
	if _network_virtual:
		if not session.is_active():
			_network_virtual = false
		return
	var carried = gameplay_controller.get_item(session.item_id)
	if carried != null and String(carried.relation.get("container_id", "")) == cursor_container_id:
		session.sync_domain_item(carried)
		return
	session.clear()
	_finalize_cursor()


func _finalize_cursor() -> Dictionary:
	if _network_virtual:
		return {"success": true, "network_virtual": true, "skipped": true}
	return gameplay_controller.finalize_inventory_cursor(cursor_container_id)


func _placed_item_id(result: Dictionary, carried_item_id: String, target_item_id: String) -> String:
	if bool(result.get("merged", false)) and bool(result.get("source_removed", false)):
		return String(result.get("target_item_id", target_item_id))
	var new_item_id := String(result.get("new_item_id", ""))
	if not new_item_id.is_empty():
		return new_item_id
	var result_item_id := String(result.get("result_item_id", ""))
	if not result_item_id.is_empty():
		return result_item_id
	return carried_item_id


func _item_payload(item_id: String, container_id: String, slot_index: int) -> Dictionary:
	var item = gameplay_controller.get_item(item_id)
	if item == null:
		return {}
	var definition = gameplay_controller.get_definition(item.definition_id)
	var resolved_display_name := String(item.display_name)
	if resolved_display_name.is_empty() and definition != null:
		resolved_display_name = String(definition.display_name)
	return {
		"item_id": item_id,
		"definition_id": String(item.definition_id),
		"display_name": resolved_display_name,
		"quantity": int(item.quantity),
		"revision": int(item.revision),
		"source_container_id": container_id,
		"source_slot_index": slot_index,
		"target_container_id": container_id,
		"target_slot_index": slot_index,
		"target_item_id": item_id,
	}


func _icon_for_payload(payload: Dictionary) -> Texture2D:
	if payload.get("icon_texture") is Texture2D:
		return payload.get("icon_texture") as Texture2D
	if icon_provider.is_valid():
		return icon_provider.call(payload) as Texture2D
	return null


func _fail(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
