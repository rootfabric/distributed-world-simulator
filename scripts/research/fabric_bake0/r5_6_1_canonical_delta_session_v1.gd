extends RefCounted
## R5.6.1 R1 — read-only consumer of an EXTERNAL ConstructionConstructStore.
## This session never mutates Construction/Matter; external state changes are
## observed only after exact source/proposal validation. No second world owner.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Delta = preload("res://scripts/research/fabric_bake0/r5_6_1_canonical_delta_contract_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_adapter_v1.gd")

const SCHEMA := "planet_simulator.fabric_r5_6_1_delta_session.v1"
var _store
var _snapshot: Dictionary = {}
var _matter: Dictionary = {}
var _authority: Dictionary = {}
var _context: Dictionary = {}
var _events: Array = []
var _pending: Dictionary = {}
var _observed := 0

func start(store, construct_id: String, matter: Dictionary, authority: Dictionary, events: Array = []) -> Dictionary:
	if not _snapshot.is_empty():
		return U.failure("R56_ALREADY_STARTED")
	if store == null or not store.has_method("get_snapshot"):
		return U.failure("R56_CANONICAL_STORE_REQUIRED")
	var current: Dictionary = store.get_snapshot(construct_id)
	var compiled := Adapter.compile_authoritative(current, matter, authority, events)
	if not compiled.success:
		return U.failure("R56_CANONICAL_START_INVALID", {"cause": compiled.get("error_code", "")})
	_store = store # only borrow! No writes, no store replacement, no epoch minting.
	_snapshot = current.duplicate(true)
	_matter = matter.duplicate(true)
	_authority = authority.duplicate(true)
	_context = compiled.details.duplicate(true)
	_events = events.duplicate()
	return U.success(status())

func prepare(action: String, bond_id: String, event_id: String, strength_n: float = 0.0) -> Dictionary:
	if _snapshot.is_empty():
		return U.failure("R56_NOT_STARTED")
	if not _pending.is_empty():
		return U.failure("R56_PENDING_PROPOSAL_EXISTS")
	var live := _fence()
	if not live.success:
		return live
	var result := Delta.prepare(_snapshot, _matter, _authority, _events, event_id, action, bond_id, strength_n)
	if not result.success:
		return result
	_pending = result.details.duplicate(true)
	return U.success({"proposal": _pending.duplicate(true), "status": status()})

func observe_external_commit(event_id: String, current_matter: Dictionary, current_authority: Dictionary) -> Dictionary:
	if _pending.is_empty() or event_id != String(_pending.get("event_id", "")):
		return U.failure("R56_NO_MATCHING_PROPOSAL")
	if U.canonical_hash(current_matter) != U.canonical_hash(_matter):
		return U.failure("R56_MATTER_CHANGED_REBIND_REQUIRED")
	if U.canonical_hash(current_authority) != U.canonical_hash(_authority):
		return U.failure("R56_AUTHORITY_CHANGED_REBIND_REQUIRED")
	# This is the ONLY actual snapshot read at the publication boundary. An
	# external Construction owner must commit the proposal before observe().
	var actual: Dictionary = _store.get_snapshot(String(_snapshot.construct_id))
	if U.canonical_hash(actual) == U.canonical_hash(_snapshot):
		return U.failure("R56_EXTERNAL_COMMIT_NOT_OBSERVED")
	var verified := Delta.validate_external(_snapshot, actual, _matter, _authority, _events, _pending)
	if not verified.success:
		return verified
	# Build and authenticate the new graph BEFORE derived publication.
	var next_context := Adapter.compile_authoritative(actual, _matter, _authority, _pending.next_events)
	if not next_context.success:
		return U.failure("R56_GRAPH_REBIND_FAILED")
	if String(next_context.details.binding.checksum) != String(_pending.binding_checksum) or String(next_context.details.spec.graph_hash) != String(_pending.graph_hash):
		return U.failure("R56_DERIVED_GRAPH_MISMATCH")
	_snapshot = actual.duplicate(true)
	_context = next_context.details.duplicate(true)
	_events = _pending.next_events.duplicate()
	_pending = {}
	_observed += 1
	return U.success(status())

func abandon_proposal() -> Dictionary:
	if _pending.is_empty():
		return U.failure("R56_NO_PENDING_PROPOSAL")
	var live := _fence()
	if not live.success:
		return live # canonical commit could already exist; do not hide stale state
	_pending = {}
	return U.success(status())

func read_binding() -> Dictionary:
	var live := _fence()
	if not live.success:
		return live
	return U.success({"binding": _context.binding.duplicate(true),
		"graph": _context.spec.duplicate(true), "events": _events.duplicate()})

func status() -> Dictionary:
	var stale := false
	if not _snapshot.is_empty() and _store != null:
		stale = U.canonical_hash(_store.get_snapshot(String(_snapshot.construct_id))) != U.canonical_hash(_snapshot)
	return {"schema": SCHEMA, "canonical_writes": 0, "started": not _snapshot.is_empty(),
		"construct_id": String(_snapshot.get("construct_id", "")),
		"revision": int(_snapshot.get("state_revision", -1)),
		"source_checksum": String(_snapshot.get("checksum", "")),
		"graph_hash": String(_context.get("spec", {}).get("graph_hash", "")),
		"binding_checksum": String(_context.get("binding", {}).get("checksum", "")),
		"events": _events.duplicate(), "observed_changes": _observed,
		"pending": not _pending.is_empty(), "stale": stale}

func _fence() -> Dictionary:
	if _snapshot.is_empty() or _store == null:
		return U.failure("R56_NOT_STARTED")
	if U.canonical_hash(_store.get_snapshot(String(_snapshot.construct_id))) != U.canonical_hash(_snapshot):
		return U.failure("R56_STALE_CANONICAL_SOURCE")
	return U.success()
