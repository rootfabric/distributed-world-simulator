extends RefCounted
## Derived single-writer cell. Physics safety belongs to the calling FABRIC backend.
## Preparation never publishes a second owner; commit is an atomic local CAS.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const MODES := ["FULL", "STRUCTURAL_BAKE", "LOCAL_FULL", "REBAKED"]
var _cell: Dictionary = {}
var _pending: Dictionary = {}
var _receipts: Dictionary = {}
var _tickets: Dictionary = {}
var _halted := false

func start(frontier: Dictionary, authority: Dictionary, mode: String, payload: Dictionary, tick = 0) -> Dictionary:
	if not _cell.is_empty():
		return U.failure("BRIDGE3_ALREADY_STARTED")
	if not _binding_ok(frontier, authority) or not MODES.has(mode) or not U.is_json_integer(tick) or tick < 0 or not json_safe(payload):
		return U.failure("BRIDGE3_INVALID_START")
	_cell = {"frontier": frontier.duplicate(true), "authority": authority.duplicate(true),
		"mode": mode, "payload": payload.duplicate(true), "tick": tick,
		"transition_epoch": tick, "transition_count": 0, "transition_hash": U.canonical_hash([])}
	return U.success({"writer": writer()})

func prepare(operation_id: String, mode: String, payload: Dictionary, tick, live_frontier: Dictionary) -> Dictionary:
	if not can_execute(live_frontier) or not U.is_canonical_id(operation_id, 2) or not MODES.has(mode):
		return U.failure("BRIDGE3_PREPARE_FORBIDDEN")
	if not U.is_json_integer(tick) or not json_safe(payload):
		return U.failure("BRIDGE3_TICK_OR_PAYLOAD_INVALID")
	var request_hash := U.canonical_hash({"id": operation_id, "to": mode, "payload": payload,
		"tick": tick, "frontier": live_frontier["frontier_hash"]})
	if _receipts.has(operation_id):
		if _receipts[operation_id]["request_hash"] == request_hash:
			return U.success({"ticket": _receipts[operation_id]["ticket"], "already_committed": true})
		return U.failure("BRIDGE3_OPERATION_ID_CONFLICT")
	if tick <= int(_cell["tick"]):
		return U.failure("BRIDGE3_TICK_REGRESSION")
	if not _pending.is_empty():
		if _pending["request_hash"] == request_hash:
			return U.success({"ticket": _pending["ticket"], "already_committed": false})
		return U.failure("BRIDGE3_PREPARATION_IN_PROGRESS")
	var ticket := U.canonical_hash({"request": request_hash, "base": writer()})
	_pending = {"ticket": ticket, "base": writer(), "operation_id": operation_id,
		"request_hash": request_hash, "mode": mode, "payload": payload.duplicate(true), "tick": tick}
	return U.success({"ticket": ticket, "already_committed": false})

func commit(ticket: String, live_frontier: Dictionary) -> Dictionary:
	if not can_execute(live_frontier):
		return U.failure("BRIDGE3_STALE_COMMIT")
	if _tickets.has(ticket):
		return U.success({"applied": false, "receipt": _tickets[ticket].duplicate(true)})
	if _pending.is_empty() or _pending["ticket"] != ticket or _pending["base"] != writer():
		return U.failure("BRIDGE3_UNKNOWN_OR_STALE_TICKET")
	var receipt := {"operation_id": _pending["operation_id"], "ticket": ticket,
		"request_hash": _pending["request_hash"], "from": _cell["mode"], "to": _pending["mode"],
		"transition_epoch": _pending["tick"], "frontier_hash": live_frontier["frontier_hash"]}
	var next := _cell.duplicate(false)
	next["mode"] = _pending["mode"]
	next["payload"] = _pending["payload"]
	next["tick"] = _pending["tick"]
	next["transition_epoch"] = _pending["tick"]
	next["transition_count"] += 1
	next["transition_hash"] = U.canonical_hash({"previous": _cell["transition_hash"], "receipt": receipt})
	_cell = next
	_receipts[receipt["operation_id"]] = receipt
	_tickets[ticket] = receipt
	_pending = {}
	return U.success({"applied": true, "receipt": receipt.duplicate(true), "writer": writer()})

func accept_physical_state(expected_writer: String, payload: Dictionary, tick, live_frontier: Dictionary) -> Dictionary:
	if not can_execute(live_frontier) or expected_writer != writer() or not U.is_json_integer(tick) or tick <= int(_cell["tick"]) or not json_safe(payload):
		return U.failure("BRIDGE3_STALE_PHYSICAL_WRITER")
	_cell["payload"] = payload.duplicate(true)
	_cell["tick"] = tick
	_pending = {}
	return U.success({"writer": writer()})

func invalidate() -> void:
	_halted = true
	_pending = {}

func abort() -> void:
	_pending = {}

func can_execute(live_frontier: Dictionary) -> bool:
	return not _cell.is_empty() and not _halted and Frontier.validate(live_frontier).get("success", false) and live_frontier["checksum"] == _cell["frontier"]["checksum"]

func writer() -> String:
	return U.canonical_hash(_cell) if not _cell.is_empty() and not _halted else ""

func snapshot() -> Dictionary:
	return _cell.duplicate(true)

func _binding_ok(frontier: Dictionary, authority: Dictionary) -> bool:
	if not Frontier.validate(frontier).get("success", false) or not Authority.validate_b0_safety(authority).get("success", false):
		return false
	var records: Dictionary = {}
	for record in authority["source_authority_frontier"]:
		records[U.source_key(record["source_domain"], record["source_id"])] = record["authority_epoch"]
	for source in frontier["sources"]:
		if records.get(U.source_key(source["source_domain"], source["source_id"]), -1) != source["authority_epoch"]:
			return false
	return records.size() == frontier["sources"].size()

static func json_safe(value, depth: int = 0) -> bool:
	if depth > 48:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for item in value:
				if not json_safe(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if typeof(key) != TYPE_STRING or not json_safe(value[key], depth + 1):
					return false
			return true
	return false
