extends RefCounted
## R5.6.1 R2: derived point-mass index session over an EXTERNAL canonical
## ConstructionConstructStore. No canonical writer, no gameplay physical owner.
## All source/proposal and matter validation stays on the authoritative path.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Delta = preload("res://scripts/research/fabric_bake0/r5_6_1_r2_part_delta_contract_v1.gd")
const Index = preload("res://scripts/research/fabric_bake0/r5_6_1_r2_dynamic_aggregate_index_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_adapter_v1.gd")
const CanonicalStore = preload("res://scripts/construction/authoritative/construction_construct_store.gd")

const SCHEMA := "planet_simulator.fabric_r56_r2_aggregate_session.v1"
var _store
var _store_instance_id := 0
var _snapshot: Dictionary = {}
var _matter: Dictionary = {}
var _authority: Dictionary = {}
var _context: Dictionary = {}
var _events: Array = []
var _pending: Dictionary = {}
var _initial_intent_guard: Callable = Callable()
var _index
var _committed_count := 0

func start(store, construct_id: String, matter: Dictionary, authority: Dictionary, events: Array = []) -> Dictionary:
	if not _snapshot.is_empty():
		return U.failure("R56_R2_ALREADY_STARTED")
	if store == null or not (store is CanonicalStore) or store.get_script() != CanonicalStore:
		return U.failure("R56_R2_CANONICAL_STORE_REQUIRED")
	var current: Dictionary = store.get_snapshot(construct_id)
	var graph := Adapter.compile_authoritative(current, matter, authority, events)
	if not graph.success:
		return U.failure("R56_R2_SOURCE_BINDING_INVALID", {"cause": graph.get("error_code", "")})
	var index := Index.new()
	var initialized: Dictionary = index.initialize(current)
	if not initialized.success:
		return initialized
	_store = store
	_store_instance_id = store.get_instance_id()
	_snapshot = current.duplicate(true)
	_matter = matter.duplicate(true)
	_authority = authority.duplicate(true)
	_context = graph.details.duplicate(true)
	_events = events.duplicate()
	_index = index
	return U.success(status())

func prepare(action: String, first_part_id: String, event_id: String,
		second_part_id: String = "", new_position: Array = [], delta_mass_kg: float = 0.0) -> Dictionary:
	if _snapshot.is_empty():
		return U.failure("R56_R2_NOT_STARTED")
	if not _pending.is_empty() or _initial_intent_guard.is_valid():
		return U.failure("R56_R2_PENDING_EXISTS")
	var valid := _fence()
	if not valid.success:
		return valid
	var prepared := Delta.prepare(_snapshot, _matter, _authority, _events,
		event_id, action, first_part_id, second_part_id, new_position, delta_mass_kg)
	if not prepared.success:
		return prepared
	var initial_hash: String = U.canonical_hash(prepared.details)
	var initial_event_id: String = event_id
	var initial_source_checksum: String = String(_snapshot.checksum)
	var initial_store_id: int = _store_instance_id
	_initial_intent_guard = func(candidate: Dictionary, source_checksum: String, store_id: int) -> bool:
		return store_id == initial_store_id and source_checksum == initial_source_checksum \
			and String(candidate.get("event_id", "")) == initial_event_id \
			and U.canonical_hash(candidate) == initial_hash
	_pending = prepared.details.duplicate(true)
	return U.success({"proposal": _pending.duplicate(true), "status": status()})

func observe_external_commit(event_id: String, current_matter: Dictionary, current_authority: Dictionary) -> Dictionary:
	if _pending.is_empty() or event_id != String(_pending.get("event_id", "")):
		return U.failure("R56_R2_NO_MATCHING_PROPOSAL")
	if not _store_is_authoritative():
		return U.failure("R56_R2_STORE_BINDING_DRIFT")
	if not _pending_matches_original():
		return U.failure("R56_R2_PENDING_PROVENANCE_MISMATCH")
	if U.canonical_hash(current_matter) != U.canonical_hash(_matter):
		return U.failure("R56_R2_MATTER_REBIND_REQUIRED")
	if U.canonical_hash(current_authority) != U.canonical_hash(_authority):
		return U.failure("R56_R2_AUTHORITY_REBIND_REQUIRED")
	var actual: Dictionary = _store.get_snapshot(String(_snapshot.construct_id))
	if U.canonical_hash(actual) == U.canonical_hash(_snapshot):
		return U.failure("R56_R2_EXTERNAL_COMMIT_MISSING")
	var checked := Delta.validate_external(_snapshot, actual, _matter, _authority, _events, _pending)
	if not checked.success:
		return checked
	var compiled := Adapter.compile_authoritative(actual, _matter, _authority, _pending.next_events)
	if not compiled.success:
		return U.failure("R56_R2_REBIND_INVALID")
	if String(compiled.details.binding.checksum) != String(_pending.expected_binding_checksum) \
			or String(compiled.details.spec.graph_hash) != String(_pending.expected_graph_hash):
		return U.failure("R56_R2_REBIND_MISMATCH")
	# The index stages and validates ALL modified Fenwick nodes first, then
	# mutates them atomically. No fallible work follows a successful commit.
	var changed: Dictionary = _index.apply_owner_verified(_pending.changed_rows,
		String(_snapshot.checksum), String(actual.checksum), int(actual.state_revision),
		float(_matter.total_mass_kg))
	if not changed.success:
		return changed
	_snapshot = actual.duplicate(true)
	_context = compiled.details.duplicate(true)
	_events = _pending.next_events.duplicate()
	_pending = {}
	_initial_intent_guard = Callable()
	_committed_count += 1
	return U.success({"status": status(), "index_work": changed.details})

func abandon_proposal() -> Dictionary:
	if _pending.is_empty():
		return U.failure("R56_R2_NO_PENDING")
	if not _pending_matches_original():
		return U.failure("R56_R2_PENDING_PROVENANCE_MISMATCH")
	var valid := _fence()
	if not valid.success:
		return valid
	_pending = {}
	_initial_intent_guard = Callable()
	return U.success(status())

func query_range(first: int, end_exclusive: int) -> Dictionary:
	var valid := _fence()
	if not valid.success:
		return valid
	return _index.query_range(first, end_exclusive)

func read_binding() -> Dictionary:
	var valid := _fence()
	if not valid.success:
		return valid
	return U.success({"binding": _context.binding.duplicate(true),
		"graph": _context.spec.duplicate(true), "events": _events.duplicate()})

func status() -> Dictionary:
	var stale := false
	if not _snapshot.is_empty():
		stale = not _store_is_authoritative()
		if not stale:
			stale = U.canonical_hash(_store.get_snapshot(String(_snapshot.construct_id))) != U.canonical_hash(_snapshot)
	return {"schema": SCHEMA, "started": not _snapshot.is_empty(),
		"canonical_writes": 0, "construct_id": String(_snapshot.get("construct_id", "")),
		"revision": int(_snapshot.get("state_revision", -1)),
		"checksum": String(_snapshot.get("checksum", "")),
		"graph_hash": String(_context.get("spec", {}).get("graph_hash", "")),
		"pending": not _pending.is_empty() or _initial_intent_guard.is_valid(),
		"events": _events.duplicate(), "stale": stale, "commits": _committed_count,
		"index": _index.status() if _index != null else {}}

func _pending_matches_original() -> bool:
	return _initial_intent_guard.is_valid() and bool(_initial_intent_guard.call(
		_pending, String(_snapshot.get("checksum", "")), _store_instance_id))

func _store_is_authoritative() -> bool:
	return _store != null and is_instance_valid(_store) and (_store is CanonicalStore) \
		and _store.get_script() == CanonicalStore and _store.get_instance_id() == _store_instance_id

func _fence() -> Dictionary:
	if _snapshot.is_empty() or _store == null:
		return U.failure("R56_R2_NOT_STARTED")
	if not _store_is_authoritative():
		return U.failure("R56_R2_STORE_BINDING_DRIFT")
	if U.canonical_hash(_store.get_snapshot(String(_snapshot.construct_id))) != U.canonical_hash(_snapshot):
		return U.failure("R56_R2_STALE_CANONICAL_SOURCE")
	return U.success()
