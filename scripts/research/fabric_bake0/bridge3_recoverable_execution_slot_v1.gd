extends "res://scripts/research/fabric_bake0/bridge3_execution_slot_v1.gd"
## Recovery extension for the closed BRIDGE-3-A single-writer cell.
## A checkpoint is derived/discardable and may only restore against the exact live binding.

func checkpoint() -> Dictionary:
	if _cell.is_empty() or _halted or not _pending.is_empty():
		return U.failure("BRIDGE3_CHECKPOINT_NOT_COMMITTED")
	return U.success({"cell": _cell.duplicate(true), "receipts": _receipts.duplicate(true),
		"tickets": _tickets.duplicate(true)})

func restore(value: Dictionary, live_frontier: Dictionary, live_authority: Dictionary) -> Dictionary:
	if not _cell.is_empty() or not _pending.is_empty() or not _receipts.is_empty() or not _tickets.is_empty():
		return U.failure("BRIDGE3_RESTORE_REQUIRES_EMPTY_SLOT")
	if typeof(value.get("cell")) != TYPE_DICTIONARY or typeof(value.get("receipts")) != TYPE_DICTIONARY or typeof(value.get("tickets")) != TYPE_DICTIONARY:
		return U.failure("BRIDGE3_INVALID_CHECKPOINT")
	var cell: Dictionary = value.cell
	var fields := ["frontier", "authority", "mode", "payload", "tick", "transition_epoch", "transition_count", "transition_hash"]
	if cell.keys().size() != fields.size():
		return U.failure("BRIDGE3_INVALID_CHECKPOINT_CELL")
	for field in fields:
		if not cell.has(field):
			return U.failure("BRIDGE3_INVALID_CHECKPOINT_CELL")
	if not _binding_ok(live_frontier, live_authority) or cell.frontier.get("checksum", "") != live_frontier.get("checksum", "") or cell.authority.get("checksum", "") != live_authority.get("checksum", ""):
		return U.failure("BRIDGE3_STALE_CHECKPOINT_BINDING")
	if not MODES.has(cell.get("mode")) or not json_safe(cell.get("payload")) or not U.is_json_integer(cell.get("tick")) or not U.is_json_integer(cell.get("transition_epoch")) or not U.is_json_integer(cell.get("transition_count")):
		return U.failure("BRIDGE3_INVALID_CHECKPOINT_CELL")
	if int(cell.tick) < 0 or int(cell.transition_epoch) < 0 or int(cell.transition_count) < 0 or not U.is_lower_hex_64(cell.get("transition_hash")):
		return U.failure("BRIDGE3_INVALID_CHECKPOINT_CELL")
	if not json_safe(value.receipts) or not json_safe(value.tickets):
		return U.failure("BRIDGE3_INVALID_CHECKPOINT_RECEIPTS")
	for operation_id in value.receipts:
		if not U.is_canonical_id(operation_id, 2):
			return U.failure("BRIDGE3_INVALID_CHECKPOINT_RECEIPT_ID")
		var receipt = value.receipts[operation_id]
		if typeof(receipt) != TYPE_DICTIONARY or receipt.get("operation_id") != operation_id:
			return U.failure("BRIDGE3_INVALID_CHECKPOINT_RECEIPT")
		if not value.tickets.has(receipt.get("ticket")) or value.tickets[receipt.ticket] != receipt:
			return U.failure("BRIDGE3_CHECKPOINT_RECEIPT_INDEX_MISMATCH")
	_cell = cell.duplicate(true)
	_receipts = value.receipts.duplicate(true)
	_tickets = value.tickets.duplicate(true)
	_halted = false
	return U.success({"writer": writer()})

func rebind(previous: Dictionary, receipts: Dictionary, tickets: Dictionary,
	new_frontier: Dictionary, new_authority: Dictionary, mode: String, payload: Dictionary,
	tick: int, event_id: String) -> Dictionary:
	if not _cell.is_empty() or not _binding_ok(new_frontier, new_authority) or not MODES.has(mode) or not json_safe(payload):
		return U.failure("BRIDGE3_REBIND_INVALID")
	if not U.is_canonical_id(event_id, 2) or not U.is_json_integer(tick) or tick <= int(previous.get("tick", -1)):
		return U.failure("BRIDGE3_REBIND_ORDER_INVALID")
	if not U.is_json_integer(previous.get("transition_count")) or not U.is_lower_hex_64(previous.get("transition_hash")) or not MODES.has(previous.get("mode")):
		return U.failure("BRIDGE3_REBIND_PREDECESSOR_INVALID")
	var receipt := {"operation_id": event_id,
		"ticket": U.canonical_hash({"event": event_id, "previous": previous.transition_hash, "frontier": new_frontier.frontier_hash}),
		"request_hash": U.canonical_hash({"event": event_id, "from_frontier": previous.frontier.frontier_hash,
			"to_frontier": new_frontier.frontier_hash, "to": mode, "tick": tick}),
		"from": previous.mode, "to": mode, "transition_epoch": tick,
		"frontier_hash": new_frontier.frontier_hash, "reason": "CANONICAL_MUTATION_REBIND"}
	_cell = {"frontier": new_frontier.duplicate(true), "authority": new_authority.duplicate(true), "mode": mode,
		"payload": payload.duplicate(true), "tick": tick, "transition_epoch": tick,
		"transition_count": int(previous.transition_count) + 1,
		"transition_hash": U.canonical_hash({"previous": previous.transition_hash, "receipt": receipt})}
	_receipts = receipts.duplicate(true)
	_tickets = tickets.duplicate(true)
	_receipts[event_id] = receipt
	_tickets[receipt.ticket] = receipt
	_halted = false
	return U.success({"applied": true, "receipt": receipt.duplicate(true), "writer": writer()})
