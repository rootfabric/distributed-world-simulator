extends RefCounted
## A8 research partition consumer. This is NOT a new global authority.
## apply() updates a local proposal; only a successful durable CAS publishes it.
## Preserve complete A7 biology and logical field ownership across executor handoff.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const A7 = preload("res://scripts/research/ecology/v2/observatory_session_v1.gd")
const Ticket = preload("res://scripts/network/contracts/handoff_ticket.gd")
const Machine = preload("res://scripts/network/handoff/handoff_state_machine.gd")
const Net = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "dws.ecology.snapshot-seam.v1"
const MAX_COMMANDS := 96
const MAX_TICKETS := 8
const MAX_COMMAND_BYTES := 8192
const COMMAND_FIELDS := ["op_id", "kind", "actor", "epoch", "revision", "clock", "args"]
const ORIGIN_FIELDS := ["entity_id", "region_id", "owner_id", "owner_epoch", "treatment", "experiment_hash"]
var _origin: Dictionary = {}
var _cut: Dictionary = {}
var _commands: Array = []
var _receipts: Dictionary = {}
var _ticket_ids: Dictionary = {}
var _text := ""
var _hash := ""
var last_error := "A8_NOT_STARTED"

func start(treatment: Dictionary, entity_id: String, region_id: String, owner_id: String, owner_epoch: int = 1) -> bool:
	if not C.identifier(entity_id) or not C.identifier(region_id) or not C.identifier(owner_id) or not C.integer(owner_epoch, 1, C.MAX_INT):
		return _fail_bool("A8_ORIGIN")
	var model = A7.new()
	if not model.start(treatment): return _fail_bool("A8_GENESIS:" + model.last_error)
	var payload: String = model.save_text()
	if payload.is_empty(): return _fail_bool("A8_GENESIS_PAYLOAD")
	var origin := {"entity_id": entity_id, "region_id": region_id, "owner_id": owner_id,
		"owner_epoch": owner_epoch, "treatment": treatment.duplicate(true), "experiment_hash": model.experiment_hash()}
	var cut := {"owner_id": owner_id, "owner_epoch": owner_epoch, "revision": 0, "clock": 0,
		"ecology_step": 0, "ecology_payload": payload, "ticket": {}}
	var text := _encode(origin, [], cut)
	if text.is_empty(): return _fail_bool("A8_SNAPSHOT_BUDGET")
	_origin = origin
	_cut = cut
	_commands = []
	_receipts = {}
	_ticket_ids = {}
	_publish(text)
	return true

func snapshot_text() -> String:
	return _text

func snapshot_hash() -> String:
	return _hash

func origin_hash() -> String:
	return "" if _origin.is_empty() else C.digest(_origin)

func ecology_text() -> String:
	return String(_cut.get("ecology_payload", ""))

func ticket_snapshot() -> Dictionary:
	return Dictionary(_cut.get("ticket", {})).duplicate(true)

func cursor() -> Dictionary:
	if _cut.is_empty(): return {}
	return {"entity_id": _origin.entity_id, "region_id": _origin.region_id, "owner_id": _cut.owner_id,
		"owner_epoch": _cut.owner_epoch, "revision": _cut.revision, "clock": _cut.clock, "ecology_step": _cut.ecology_step}

func _active_ticket() -> bool:
	return not _cut.ticket.is_empty() and not Ticket.is_terminal(_cut.ticket)

func apply(command: Dictionary, expected_snapshot_hash: String, received_payload: String = "") -> Dictionary:
	if _cut.is_empty(): return _fail("A8_NOT_STARTED")
	var error := _command_error(command)
	if not error.is_empty(): return _fail(error)
	var command_hash := C.digest(command)
	# A retry carries its original revision/actor. It may return only a prior receipt,
	# never another write, even after owner change. Conflicting retries fail closed.
	if _receipts.has(command.op_id):
		var old: Dictionary = _receipts[command.op_id]
		if old.command_hash != command_hash: return _fail("A8_OPERATION_ID_CONFLICT")
		if not received_payload.is_empty() and received_payload.sha256_text() != command.args.get("payload_hash", ""):
			return _fail("A8_RETRY_PAYLOAD_MISMATCH")
		last_error = ""
		return {"success": true, "replay": true, "receipt": old.duplicate(true), "snapshot_hash": _hash}
	if expected_snapshot_hash != _hash: return _fail("A8_STALE_SNAPSHOT")
	if command.revision != _cut.revision: return _fail("A8_STALE_REVISION")
	if command.clock < _cut.clock: return _fail("A8_STALE_CLOCK")
	if _commands.size() >= MAX_COMMANDS: return _fail("A8_COMMAND_BUDGET")
	if _cut.revision >= C.MAX_INT: return _fail("A8_REVISION_BUDGET")
	var target_ack: bool = command.kind == "TRANSITION" and command.args.get("state") == "TARGET_PREPARED"
	var actor: String = String(_cut.ticket.get("target_node_id", "")) if target_ack else _cut.owner_id
	var epoch: int = int(_cut.ticket.get("target_authority_epoch", -1)) if target_ack else _cut.owner_epoch
	if command.actor != actor: return _fail("A8_STALE_OWNER")
	if command.epoch != epoch: return _fail("A8_STALE_EPOCH")
	var candidate: Dictionary = _cut.duplicate(true)
	var new_ticket := ""
	match command.kind:
		"ADVANCE":
			if not C.keys(command.args, []) or not received_payload.is_empty(): return _fail("A8_ADVANCE_ARGS")
			if _active_ticket(): return _fail("A8_HANDOFF_FROZEN")
			var model = A7.new()
			if not model.load_text(_cut.ecology_payload, _origin.experiment_hash, _cut.ecology_step): return _fail("A8_SOURCE_PAYLOAD")
			if not model.advance(): return _fail("A8_ADVANCE:" + model.last_error)
			candidate.ecology_payload = model.save_text()
			if candidate.ecology_payload.is_empty(): return _fail("A8_PAYLOAD_BUDGET")
			candidate.ecology_step = model.step_index()
		"BEGIN":
			if not C.keys(command.args, ["ticket"]) or not command.args.ticket is Dictionary or not received_payload.is_empty(): return _fail("A8_BEGIN_ARGS")
			if _active_ticket(): return _fail("A8_HANDOFF_ACTIVE")
			if _ticket_ids.size() >= MAX_TICKETS: return _fail("A8_TICKET_BUDGET")
			var t: Dictionary = command.args.ticket
			var check: Dictionary = Ticket.validate(t)
			if not check.success: return _fail("A8_TICKET:" + String(check.error_code))
			if not C.identifier(t.ticket_id) or not C.identifier(t.target_node_id): return _fail("A8_TICKET_ID")
			if _ticket_ids.has(t.ticket_id): return _fail("A8_TICKET_ID_REUSED")
			if t.state != "REQUESTED" or t.entity_id != _origin.entity_id or t.region_id != _origin.region_id: return _fail("A8_TICKET_BINDING")
			if t.source_node_id != _cut.owner_id or t.source_authority_epoch != _cut.owner_epoch: return _fail("A8_TICKET_OWNER")
			if t.expected_state_revision != _cut.revision or t.created_at_tick != command.clock: return _fail("A8_TICKET_CURSOR")
			if not t.snapshot_id.is_empty() or not t.snapshot_hash.is_empty() or not t.reason.is_empty(): return _fail("A8_DIRTY_REQUEST")
			candidate.ticket = Net.canonicalize(Ticket.normalize(t)).value
			new_ticket = t.ticket_id
		"TRANSITION":
			if not C.keys(command.args, ["ticket_id", "state", "payload_hash"]): return _fail("A8_TRANSITION_ARGS")
			for key in ["ticket_id", "state", "payload_hash"]:
				if not command.args[key] is String: return _fail("A8_TRANSITION_TYPE")
			if _cut.ticket.is_empty() or command.args.ticket_id != _cut.ticket.ticket_id: return _fail("A8_TICKET_MISMATCH")
			if not _active_ticket(): return _fail("A8_HANDOFF_TERMINAL")
			var next: String = command.args.state
			if next == _cut.ticket.state: return _fail("A8_RETRY_REQUIRES_ORIGINAL_OPERATION_ID")
			if next != "TARGET_PREPARED" and (not command.args.payload_hash.is_empty() or not received_payload.is_empty()): return _fail("A8_UNEXPECTED_PAYLOAD")
			var context := {"expected_transition_revision": int(_cut.ticket.transition_revision), "tick": command.clock}
			if next == "SNAPSHOT_READY":
				context["snapshot_hash"] = String(_cut.ecology_payload).sha256_text()
				context["snapshot_id"] = "a8." + String(context["snapshot_hash"])
			if next == "TARGET_PREPARED":
				if not F.valid_hash(command.args.payload_hash) or command.args.payload_hash != _cut.ticket.snapshot_hash:
					return _fail("A8_TARGET_HASH")
				if received_payload.to_utf8_buffer().size() > C.MAX_BYTES or received_payload != _cut.ecology_payload:
					return _fail("A8_TARGET_PAYLOAD")
				var target = A7.new()
				if not target.load_text(received_payload, _origin.experiment_hash, _cut.ecology_step): return _fail("A8_TARGET_ADMISSION")
			var machine = Machine.new()
			var setup: Dictionary = machine.setup(_cut.ticket)
			if not setup.success: return _fail("A8_MACHINE_SETUP")
			var result: Dictionary = machine.transition(next, context)
			if not result.success: return _fail("A8_HANDOFF:" + String(result.error_code))
			candidate.ticket = Net.canonicalize(result.ticket).value
			if next == "COMMITTED":
				candidate.owner_id = candidate.ticket.target_node_id
				candidate.owner_epoch = candidate.ticket.target_authority_epoch
		_:
			return _fail("A8_COMMAND_KIND")
	candidate.revision += 1
	candidate.clock = command.clock
	var commands: Array = _commands.duplicate(true)
	commands.append(command.duplicate(true))
	var text := _encode(_origin, commands, candidate)
	if text.is_empty(): return _fail("A8_SNAPSHOT_BUDGET")
	var receipt := {"op_id": command.op_id, "command_hash": command_hash, "snapshot_hash": text.sha256_text(),
		"revision": candidate.revision, "ecology_step": candidate.ecology_step,
		"owner_id": candidate.owner_id, "owner_epoch": candidate.owner_epoch,
		"ticket_hash": "" if candidate.ticket.is_empty() else Ticket.ticket_hash(candidate.ticket)}
	# Commit local state only after every guard, replay, and byte budget succeeds.
	_cut = candidate
	_commands = commands
	_receipts[command.op_id] = receipt
	if not new_ticket.is_empty(): _ticket_ids[new_ticket] = true
	_publish(text)
	return {"success": true, "replay": false, "receipt": receipt.duplicate(true), "snapshot_hash": _hash}

func load_text(text: String, expected_snapshot_hash: String, expected_origin_hash: String) -> bool:
	if not F.valid_hash(expected_snapshot_hash) or not F.valid_hash(expected_origin_hash): return _fail_bool("A8_EXTERNAL_ANCHOR")
	if text.to_utf8_buffer().size() > C.MAX_BYTES or text.sha256_text() != expected_snapshot_hash: return _fail_bool("A8_SNAPSHOT_HASH")
	var decoded := C.decode(text)
	if not decoded.success: return _fail_bool("A8_SNAPSHOT_ENCODING")
	var v: Variant = decoded.value
	if not C.keys(v, ["schema", "origin", "commands", "cut"]) or v.schema != SCHEMA: return _fail_bool("A8_SNAPSHOT_SCHEMA")
	if not C.keys(v.origin, ORIGIN_FIELDS) or C.digest(v.origin) != expected_origin_hash: return _fail_bool("A8_ORIGIN_ANCHOR")
	if not v.origin.treatment is Dictionary or not C.integer(v.origin.owner_epoch, 1, C.MAX_INT): return _fail_bool("A8_ORIGIN_TYPE")
	for key in ["entity_id", "region_id", "owner_id"]:
		if not C.identifier(v.origin[key]): return _fail_bool("A8_ORIGIN_TYPE")
	if not v.commands is Array or v.commands.size() > MAX_COMMANDS or not v.cut is Dictionary: return _fail_bool("A8_JOURNAL_BUDGET")
	var candidate = get_script().new()
	if not candidate.start(v.origin.treatment, v.origin.entity_id, v.origin.region_id, v.origin.owner_id, v.origin.owner_epoch):
		return _fail_bool("A8_RESTORE_GENESIS")
	if candidate.origin_hash() != expected_origin_hash: return _fail_bool("A8_RESTORE_EXPERIMENT")
	for command in v.commands:
		if not command is Dictionary: return _fail_bool("A8_RESTORE_COMMAND")
		var payload := ""
		if command.get("kind") == "TRANSITION" and command.get("args") is Dictionary and command.args.get("state") == "TARGET_PREPARED":
			payload = candidate.ecology_text()
		var result: Dictionary = candidate.apply(command, candidate.snapshot_hash(), payload)
		if not result.success or result.replay: return _fail_bool("A8_JOURNAL_REPLAY:" + String(result.get("error", "DUPLICATE_EVENT")))
	if candidate.snapshot_text() != text: return _fail_bool("A8_CUT_REPLAY_MISMATCH")
	_origin = candidate._origin.duplicate(true)
	_cut = candidate._cut.duplicate(true)
	_commands = candidate._commands.duplicate(true)
	_receipts = candidate._receipts.duplicate(true)
	_ticket_ids = candidate._ticket_ids.duplicate(true)
	_publish(text)
	return true

func observe() -> Dictionary:
	if _cut.is_empty(): return _fail("A8_NOT_STARTED")
	var model = A7.new()
	if not model.load_text(_cut.ecology_payload, _origin.experiment_hash, _cut.ecology_step): return _fail("A8_OBSERVATION_ADMISSION")
	return {"success": true, "cursor": cursor(), "snapshot_hash": _hash, "ecology": model.observe(),
		"scope": "BOUNDED_RESEARCH_PARTITION_HANDOFF_NOT_PRODUCTION_NETWORK"}

func _command_error(command: Dictionary) -> String:
	if not C.keys(command, COMMAND_FIELDS): return "A8_COMMAND_SCHEMA"
	if not C.identifier(command.op_id) or not C.identifier(command.actor): return "A8_COMMAND_ID"
	if not command.kind is String or not command.args is Dictionary: return "A8_COMMAND_TYPE"
	for key in ["epoch", "revision", "clock"]:
		if not C.integer(command[key], 0 if key != "epoch" else 1, C.MAX_INT): return "A8_COMMAND_INTEGER"
	var text := C.encode(command)
	if text.is_empty() or text.to_utf8_buffer().size() > MAX_COMMAND_BYTES: return "A8_COMMAND_BUDGET"
	return ""

func _encode(origin: Dictionary, commands: Array, cut: Dictionary) -> String:
	var text := C.encode({"schema": SCHEMA, "origin": origin, "commands": commands, "cut": cut})
	return text if text.to_utf8_buffer().size() <= C.MAX_BYTES else ""

func _publish(text: String) -> void:
	_text = text
	_hash = text.sha256_text()
	last_error = ""

func _fail(error: String) -> Dictionary:
	last_error = error
	return {"success": false, "error": error}

func _fail_bool(error: String) -> bool:
	last_error = error
	return false