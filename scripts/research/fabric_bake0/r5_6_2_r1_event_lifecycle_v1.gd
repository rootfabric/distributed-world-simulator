extends RefCounted
## FABRIC R5.6.2 R1 — research-only unified derived lifecycle.
## ConstructionConstructStore remains the ONLY canonical mutation owner.
## The caller MUST durably persist the returned journal BEFORE applying an
## external owner mutation, and persist the acknowledged journal BEFORE adopt.
## This is process-restart reconciliation, NOT distributed exactly-once writes.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const BondDelta = preload("res://scripts/research/fabric_bake0/r5_6_1_canonical_delta_contract_v1.gd")
const PartDelta = preload("res://scripts/research/fabric_bake0/r5_6_1_r2_part_delta_contract_v1.gd")
const Index = preload("res://scripts/research/fabric_bake0/r5_6_1_r2_dynamic_aggregate_index_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_adapter_v1.gd")
const Store = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")

const SCHEMA := "planet_simulator.fabric_r56_2_r1_lifecycle_journal.v1"
const BOND := "BOND"
const PART := "PART"
const MAX_EVENTS := 16
const MAX_PARTS := 512
const JOURNAL_FIELDS: Array[String] = [
	"schema", "construct_id", "initial_snapshot", "initial_events",
	"matter_checksum", "authority_checksum", "committed", "pending", "checksum"]
const ENTRY_FIELDS: Array[String] = ["kind", "event_id", "proposal"]

var _store = null
var _store_id: int = 0
var _snapshot: Dictionary = {}
var _matter: Dictionary = {}
var _authority: Dictionary = {}
var _context: Dictionary = {}
var _events: Array = []
var _journal: Dictionary = {}
var _index = null
var _mode := "NEW"
var _intent_guard: Callable = Callable()

## A new history starts from a genuine, externally populated owner snapshot.
func bootstrap(store, construct_id: String, matter: Dictionary, authority: Dictionary,
		initial_events: Array = []) -> Dictionary:
	if _mode != "NEW":
		return U.failure("R562_ALREADY_STARTED")
	if not _valid_store(store):
		return U.failure("R562_CANONICAL_STORE_REQUIRED")
	var snapshot: Dictionary = store.get_snapshot(construct_id)
	if snapshot.get("construct_id", "") != construct_id:
		return U.failure("R562_OWNER_SOURCE_MISSING")
	if snapshot.get("parts", []).size() < 1 or snapshot.parts.size() > MAX_PARTS:
		return U.failure("R562_PART_BUDGET_EXCEEDED")
	var graph := Adapter.compile_authoritative(snapshot, matter, authority, initial_events)
	if not graph.success:
		return U.failure("R562_INITIAL_BINDING_INVALID", {"cause": graph.get("error_code", "")})
	var ix = Index.new()
	var built: Dictionary = ix.initialize(snapshot)
	if not built.success:
		return built
	var journal := {
		"schema": SCHEMA, "construct_id": construct_id,
		"initial_snapshot": snapshot.duplicate(true),
		"initial_events": initial_events.duplicate(),
		"matter_checksum": String(matter.get("checksum", "")),
		"authority_checksum": String(authority.get("checksum", "")),
		"committed": [], "pending": {}, "checksum": ""}
	journal.checksum = U.compute_checksum(journal)
	_store = store
	_store_id = store.get_instance_id()
	_snapshot = snapshot.duplicate(true)
	_matter = matter.duplicate(true)
	_authority = authority.duplicate(true)
	_context = graph.details.duplicate(true)
	_events = initial_events.duplicate()
	_journal = journal
	_index = ix
	_mode = "READY"
	return U.success({"status": status(), "journal": journal_copy()})

## Reconstruct every successor from the saved intent, never from a cached graph.
## pending + owner BEFORE => PENDING_OWNER; pending + owner AFTER =>
## OWNER_COMMITTED_PENDING_ACK. Neither state permits physical execution.
func recover(store, construct_id: String, matter: Dictionary, authority: Dictionary,
		journal: Dictionary) -> Dictionary:
	if _mode != "NEW":
		return U.failure("R562_ALREADY_STARTED")
	if not _valid_store(store):
		return U.failure("R562_CANONICAL_STORE_REQUIRED")
	var replayed := _replay(journal, matter, authority)
	if not replayed.success:
		return replayed
	var expected: Dictionary = replayed.details.snapshot
	if String(expected.get("construct_id", "")) != construct_id:
		return U.failure("R562_CONSTRUCT_ID_MISMATCH")
	var actual: Dictionary = store.get_snapshot(construct_id)
	var mode := "READY"
	if not journal.pending.is_empty():
		var pending_after: Dictionary = replayed.details.pending_after
		if U.canonical_hash(actual) == U.canonical_hash(expected):
			mode = "PENDING_OWNER"
		elif U.canonical_hash(actual) == U.canonical_hash(pending_after):
			mode = "OWNER_COMMITTED_PENDING_ACK"
		else:
			return U.failure("R562_OWNER_DIVERGED")
	elif U.canonical_hash(actual) != U.canonical_hash(expected):
		return U.failure("R562_OWNER_DIVERGED")
	var ix = Index.new()
	var built: Dictionary = ix.initialize(expected)
	if not built.success:
		return built
	_store = store
	_store_id = store.get_instance_id()
	_snapshot = expected.duplicate(true)
	_matter = matter.duplicate(true)
	_authority = authority.duplicate(true)
	_context = replayed.details.context.duplicate(true)
	_events = replayed.details.events.duplicate()
	_journal = journal.duplicate(true)
	_index = ix
	_mode = mode
	_seal_pending()
	return U.success({"status": status(), "journal": journal_copy()})

func prepare_bond(action: String, bond_id: String, event_id: String,
		strength_n: float = 0.0) -> Dictionary:
	return _prepare(BOND, action, bond_id, event_id, "", [], 0.0, strength_n)

func prepare_part(action: String, part_id: String, event_id: String,
		second_part_id: String = "", new_position: Array = [],
		delta_mass_kg: float = 0.0) -> Dictionary:
	return _prepare(PART, action, part_id, event_id, second_part_id,
		new_position, delta_mass_kg, 0.0)

func _prepare(kind: String, action: String, primary_id: String, event_id: String,
		secondary_id: String, position: Array, mass_delta: float,
		strength_n: float) -> Dictionary:
	var live := _ready_fence()
	if not live.success:
		return live
	if _events.size() >= MAX_EVENTS or not _journal.pending.is_empty():
		return U.failure("R562_EVENT_BUDGET_OR_PENDING")
	var proposed: Dictionary
	if kind == BOND:
		proposed = BondDelta.prepare(_snapshot, _matter, _authority,
			_events, event_id, action, primary_id, strength_n)
	elif kind == PART:
		proposed = PartDelta.prepare(_snapshot, _matter, _authority,
			_events, event_id, action, primary_id, secondary_id, position, mass_delta)
	else:
		return U.failure("R562_EVENT_KIND_UNSUPPORTED")
	if not proposed.success:
		return proposed
	var entry := {"kind": kind, "event_id": event_id, "proposal": proposed.details.duplicate(true)}
	_journal.pending = entry
	_journal.checksum = U.compute_checksum(_journal)
	_mode = "PREPARE_NOT_DURABLE"
	_seal_pending()
	return U.success({"journal": journal_copy(), "owner_mutation": proposed.details.mutation.duplicate(true),
		"status": status()})

## Call only after a durable journal write/flush performed by the owning caller.
## An in-memory checksum alone cannot prove the host persisted anything.
func mark_prepared_durable(journal_checksum: String) -> Dictionary:
	if _mode != "PREPARE_NOT_DURABLE" or not _pending_intact():
		return U.failure("R562_PREPARE_NOT_ADMISSIBLE")
	if journal_checksum != String(_journal.checksum):
		return U.failure("R562_PREPARE_RECEIPT_MISMATCH")
	_mode = "PENDING_OWNER"
	return U.success(status())

## After the EXTERNAL owner commit, validate exact successor, then return a
## candidate durable ACK. No canonical or derived publication occurs here.
func make_ack_journal() -> Dictionary:
	if not ["PENDING_OWNER", "OWNER_COMMITTED_PENDING_ACK"].has(_mode):
		return U.failure("R562_ACK_PHASE_INVALID")
	if not _pending_intact():
		return U.failure("R562_PENDING_PROVENANCE_MISMATCH")
	if not _same_store():
		return U.failure("R562_STORE_BINDING_DRIFT")
	var actual: Dictionary = _store.get_snapshot(String(_snapshot.construct_id))
	if U.canonical_hash(actual) == U.canonical_hash(_snapshot):
		return U.failure("R562_EXTERNAL_COMMIT_MISSING")
	var checked := _validate_entry(_journal.pending, _snapshot, _matter, _authority, _events)
	if not checked.success:
		return checked
	if U.canonical_hash(actual) != U.canonical_hash(checked.details.after):
		return U.failure("R562_OWNER_SUCCESSOR_MISMATCH")
	var graph := Adapter.compile_authoritative(actual, _matter, _authority, checked.details.events)
	if not graph.success:
		return U.failure("R562_ACK_GRAPH_INVALID", {"cause": graph.get("error_code", "")})
	var ix = Index.new()
	var initialized: Dictionary = ix.initialize(actual)
	if not initialized.success:
		return initialized
	var next_journal: Dictionary = _journal.duplicate(true)
	next_journal.committed.append(next_journal.pending.duplicate(true))
	next_journal.pending = {}
	next_journal.checksum = U.compute_checksum(next_journal)
	return U.success({"journal": next_journal, "event_id": String(_journal.pending.event_id)})

## Call only AFTER saving the exact ACK journal durably. Revalidates the live
## canonical source and fully replays the persisted candidate before exposing.
func adopt_persisted_ack(candidate: Dictionary) -> Dictionary:
	if not ["PENDING_OWNER", "OWNER_COMMITTED_PENDING_ACK"].has(_mode):
		return U.failure("R562_ACK_PHASE_INVALID")
	var preview := make_ack_journal()
	if not preview.success:
		return preview
	if U.canonical_hash(candidate) != U.canonical_hash(preview.details.journal):
		return U.failure("R562_ACK_RECEIPT_MISMATCH")
	var replayed := _replay(candidate, _matter, _authority)
	if not replayed.success:
		return replayed
	var actual: Dictionary = _store.get_snapshot(String(_snapshot.construct_id))
	if not _same_store() or U.canonical_hash(actual) != U.canonical_hash(replayed.details.snapshot):
		return U.failure("R562_OWNER_DIVERGED")
	var ix = Index.new()
	var initialized: Dictionary = ix.initialize(actual)
	if not initialized.success:
		return initialized
	_snapshot = actual.duplicate(true)
	_context = replayed.details.context.duplicate(true)
	_events = replayed.details.events.duplicate()
	_journal = candidate.duplicate(true)
	_index = ix
	_intent_guard = Callable()
	_mode = "READY"
	return U.success({"status": status(), "journal": journal_copy()})

func query_range(first: int, end_exclusive: int) -> Dictionary:
	var live := _ready_fence()
	if not live.success:
		return live
	return _index.query_range(first, end_exclusive)

func read_binding() -> Dictionary:
	var live := _ready_fence()
	if not live.success:
		return live
	return U.success({"binding": _context.binding.duplicate(true),
		"graph": _context.spec.duplicate(true), "events": _events.duplicate()})

func journal_copy() -> Dictionary:
	return _journal.duplicate(true)

func status() -> Dictionary:
	var stale := not _snapshot.is_empty() and (not _same_store() or \
		U.canonical_hash(_store.get_snapshot(String(_snapshot.construct_id))) != U.canonical_hash(_snapshot))
	return {"schema": SCHEMA, "mode": _mode, "started": _mode != "NEW",
		"canonical_writes": 0, "construct_id": String(_snapshot.get("construct_id", "")),
		"revision": int(_snapshot.get("state_revision", -1)),
		"source_checksum": String(_snapshot.get("checksum", "")),
		"graph_hash": String(_context.get("spec", {}).get("graph_hash", "")),
		"events": _events.duplicate(), "committed": int(_journal.get("committed", []).size()),
		"pending": not _journal.get("pending", {}).is_empty(),
		"stale": stale, "executable": _mode == "READY" and not stale}

func _ready_fence() -> Dictionary:
	if _mode != "READY":
		return U.failure("R562_PHYSICS_NOT_READY")
	if not _same_store():
		return U.failure("R562_STORE_BINDING_DRIFT")
	if U.canonical_hash(_store.get_snapshot(String(_snapshot.construct_id))) != U.canonical_hash(_snapshot):
		return U.failure("R562_STALE_CANONICAL_SOURCE")
	return U.success()

func _same_store() -> bool:
	return _valid_store(_store) and _store.get_instance_id() == _store_id

static func _valid_store(store) -> bool:
	return store != null and is_instance_valid(store) and (store is Store) and store.get_script() == Store

func _seal_pending() -> void:
	_intent_guard = Callable()
	if _journal.get("pending", {}).is_empty():
		return
	# Never capture self in a Callable stored ON self. This would leak a
	# RefCounted session through a reference cycle after simulated process kill.
	var original_hash: String = U.canonical_hash(_journal.pending)
	var original_store_id: int = _store_id
	var original_source: String = String(_snapshot.get("checksum", ""))
	_intent_guard = func(candidate: Dictionary, source_checksum: String, store_id: int) -> bool:
		return store_id == original_store_id and source_checksum == original_source \
			and U.canonical_hash(candidate) == original_hash

func _pending_intact() -> bool:
	return _intent_guard.is_valid() and bool(_intent_guard.call(_journal.get("pending", {}), \
		String(_snapshot.get("checksum", "")), _store_id)) and U.validate_checksum(_journal).success

static func _validate_entry(entry: Dictionary, before: Dictionary,
		matter: Dictionary, authority: Dictionary, events: Array) -> Dictionary:
	if not U.validate_exact_fields(entry, ENTRY_FIELDS).success:
		return U.failure("R562_ENTRY_FIELDS_INVALID")
	if typeof(entry.get("proposal")) != TYPE_DICTIONARY:
		return U.failure("R562_ENTRY_PROPOSAL_INVALID")
	var proposal: Dictionary = entry.proposal
	if String(entry.event_id) != String(proposal.get("event_id", "")):
		return U.failure("R562_ENTRY_ID_MISMATCH")
	if typeof(proposal.get("mutation")) != TYPE_DICTIONARY:
		return U.failure("R562_ENTRY_MUTATION_INVALID")
	var after = proposal.mutation.get("after_snapshot", null)
	if typeof(after) != TYPE_DICTIONARY:
		return U.failure("R562_ENTRY_SUCCESSOR_INVALID")
	var checked: Dictionary
	match String(entry.kind):
		BOND:
			if not U.is_finite_number(proposal.get("strength_n", null)):
				return U.failure("R562_ENTRY_STRENGTH_INVALID")
			checked = BondDelta.validate_external(before, after, matter, authority, events, proposal)
		PART:
			if not U.is_finite_number(proposal.get("delta_mass_kg", null)) or \
					typeof(proposal.get("new_position")) != TYPE_ARRAY:
				return U.failure("R562_ENTRY_PART_ARGUMENTS_INVALID")
			checked = PartDelta.validate_external(before, after, matter, authority, events, proposal)
		_:
			return U.failure("R562_ENTRY_KIND_UNSUPPORTED")
	if not checked.success:
		return U.failure("R562_ENTRY_REPLAY_INVALID", {"cause": checked.get("error_code", "")})
	return U.success({"after": after.duplicate(true), "events": proposal.next_events.duplicate()})

## A checksummed, append-only DERIVED record. It is not an authenticated owner
## receipt; owner truth is still checked against the exact terminal snapshot.
static func _replay(journal: Dictionary, matter: Dictionary, authority: Dictionary) -> Dictionary:
	if not U.validate_exact_fields(journal, JOURNAL_FIELDS).success or \
			String(journal.get("schema", "")) != SCHEMA:
		return U.failure("R562_JOURNAL_SCHEMA_INVALID")
	if not U.validate_checksum(journal).success:
		return U.failure("R562_JOURNAL_CHECKSUM_INVALID")
	if typeof(journal.get("initial_snapshot")) != TYPE_DICTIONARY or \
			typeof(journal.get("initial_events")) != TYPE_ARRAY or \
			typeof(journal.get("committed")) != TYPE_ARRAY or \
			typeof(journal.get("pending")) != TYPE_DICTIONARY:
		return U.failure("R562_JOURNAL_SHAPE_INVALID")
	if String(journal.get("matter_checksum", "")) != String(matter.get("checksum", "")) or \
			String(journal.get("authority_checksum", "")) != String(authority.get("checksum", "")):
		return U.failure("R562_OWNER_CONTEXT_DRIFT")
	var snapshot: Dictionary = journal.initial_snapshot.duplicate(true)
	if not Snapshot.validate(snapshot).success or \
			String(snapshot.construct_id) != String(journal.construct_id):
		return U.failure("R562_GENESIS_INVALID")
	if snapshot.parts.size() < 1 or snapshot.parts.size() > MAX_PARTS:
		return U.failure("R562_PART_BUDGET_EXCEEDED")
	var events: Array = journal.initial_events.duplicate()
	var graph := Adapter.compile_authoritative(snapshot, matter, authority, events)
	if not graph.success:
		return U.failure("R562_GENESIS_BINDING_INVALID", {"cause": graph.get("error_code", "")})
	if events.size() + journal.committed.size() + (0 if journal.pending.is_empty() else 1) > MAX_EVENTS:
		return U.failure("R562_EVENT_BUDGET_EXCEEDED")
	for raw_entry in journal.committed:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			return U.failure("R562_COMMITTED_ENTRY_INVALID")
		var checked := _validate_entry(raw_entry, snapshot, matter, authority, events)
		if not checked.success:
			return checked
		snapshot = checked.details.after.duplicate(true)
		events = checked.details.events.duplicate()
		graph = Adapter.compile_authoritative(snapshot, matter, authority, events)
		if not graph.success:
			return U.failure("R562_COMMITTED_REBIND_INVALID")
	var pending_after: Dictionary = {}
	if not journal.pending.is_empty():
		var check_pending := _validate_entry(journal.pending, snapshot, matter, authority, events)
		if not check_pending.success:
			return check_pending
		pending_after = check_pending.details.after.duplicate(true)
	return U.success({"snapshot": snapshot, "events": events,
		"context": graph.details, "pending_after": pending_after})
