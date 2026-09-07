extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_adapter_v1.gd")
const Fabric1Runtime = preload("res://scripts/research/fabric_bake0/fabric1_generalized_runtime_v1.gd")

const CAPSULE_SCHEMA := "planet_simulator.fabric_bridge4_runtime_capsule.v2"
const PROPOSAL_SCHEMA := "planet_simulator.fabric_bridge4_canonical_failure_proposal.v1"
const TRIGGER_RATIO := 0.80
const CAPSULE_FIELDS: Array[String] = ["schema", "canonical", "derived", "discardable",
	"binding_checksum", "authority_checksum", "construct_id", "construct_revision", "matter_batch_id",
	"matter_checksum", "event_ledger", "canonical_mutations_observed", "last_tick",
	"pending_proposal", "fabric1_capsule", "checksum"]

var _fabric := Fabric1Runtime.new()
var _snapshot: Dictionary = {}
var _matter: Dictionary = {}
var _binding: Dictionary = {}
var _authority: Dictionary = {}
var _event_ledger: Array = []
var _pending_proposal: Dictionary = {}
var _canonical_mutations_observed := 0
var _last_tick := -1

func start(snapshot: Dictionary, matter_batch: Dictionary, execution_owner: String, authority_epoch: int, tick: int = 0, applied_event_ids: Array = []) -> Dictionary:
	return start_authoritative(snapshot, matter_batch,
		Adapter.authority_for(snapshot, matter_batch, execution_owner, authority_epoch), applied_event_ids, tick)

func start_authoritative(snapshot: Dictionary, matter_batch: Dictionary, authority: Dictionary, applied_event_ids: Array, tick: int = 0) -> Dictionary:
	if not _snapshot.is_empty():
		return Utils.failure("BRIDGE4_ALREADY_STARTED")
	var context := Adapter.compile_authoritative(snapshot, matter_batch, authority, applied_event_ids)
	if not context.success:
		return context
	var next := Fabric1Runtime.new()
	var started := next.start(context.details.spec, tick, context.details.source_context)
	if not started.success:
		return started
	_fabric = next
	_adopt_source(snapshot, matter_batch, context.details, applied_event_ids)
	_last_tick = tick
	return Utils.success(status())

func execute(snapshot: Dictionary, matter_batch: Dictionary, excitation: Array, authority: Dictionary = {}) -> Dictionary:
	var live := _live_binding(snapshot, matter_batch, authority)
	if not live.success:
		return live
	return _fabric.execute(excitation, live.details.source_context)

func observe_load(snapshot: Dictionary, matter_batch: Dictionary, bond_id: String, load_n: float, tick: int, authority: Dictionary = {}) -> Dictionary:
	if not _pending_proposal.is_empty() or not is_finite(load_n) or load_n < 0.0 or not _next_tick(tick):
		return Utils.failure("BRIDGE4_LOAD_OBSERVATION_INVALID")
	var live := _live_binding(snapshot, matter_batch, authority)
	if not live.success:
		return live
	var bond := Adapter.bond_by_id(snapshot, bond_id)
	if bond.is_empty() or bond.get("state") == "BROKEN":
		return Utils.failure("BRIDGE4_LOAD_BOND_INVALID")
	var ratio := load_n / float(bond["strength_n"])
	if not is_finite(ratio):
		return Utils.failure("BRIDGE4_LOAD_OBSERVATION_INVALID")
	if ratio < TRIGGER_RATIO:
		_last_tick = tick
		return Utils.success({"refined": false, "failure_proposed": false, "ratio": ratio, "status": status()})
	var refined := _fabric.refine_to_full("CANONICAL_BOND_OVERLOAD", tick, live.details.source_context)
	if not refined.success:
		return refined
	# Surrogate early-refinement experiment; it does not prove a material failure law (R2).
	_pending_proposal = _proposal(snapshot, bond, load_n)
	_last_tick = tick
	return Utils.success({"refined": true, "failure_proposed": true, "proposal": _pending_proposal, "status": status()})

func observe_canonical_successor(successor_snapshot: Dictionary, matter_batch: Dictionary, event_id: String, tick: int, authority: Dictionary = {}) -> Dictionary:
	if _pending_proposal.is_empty() or _event_ledger.has(event_id) or not Utils.is_canonical_id(event_id, 2) or not _next_tick(tick):
		return Utils.failure("BRIDGE4_CANONICAL_SUCCESSOR_ORDER_INVALID")
	# Live operations may omit authority only after an externally-authorized start/restore.
	# The stored authority came from canonical context, never from the artifact/capsule.
	var current_authority: Dictionary = _authority if authority.is_empty() else authority
	if not Adapter.AuthorityEnvelope.validate_b0_safety(current_authority).success or current_authority.get("checksum") != _authority.get("checksum"):
		return Utils.failure("BRIDGE4_AUTHORITY_CHANGED_RESTART_REQUIRED")
	var failed_bond_id: String = _pending_proposal["bond_id"]
	var checked := Adapter.validate_successor(_snapshot, successor_snapshot, _matter, matter_batch, failed_bond_id)
	if not checked.success:
		return checked
	var next_events := _event_ledger.duplicate()
	next_events.append(event_id)
	next_events.sort()
	var context := Adapter.compile_authoritative(successor_snapshot, matter_batch, current_authority, next_events)
	if not context.success:
		return context
	var observed := _fabric.apply_canonical_failure(context.details.spec, event_id, [failed_bond_id], tick, context.details.source_context)
	if not observed.success:
		return observed
	_adopt_source(successor_snapshot, matter_batch, context.details, next_events)
	_pending_proposal = {}
	_canonical_mutations_observed += 1
	_last_tick = tick
	return Utils.success({"failed_bond_id": failed_bond_id, "stale_error": observed.details.stale_error, "status": status()})

func rebake(tick: int, snapshot: Dictionary = {}, matter_batch: Dictionary = {}, authority: Dictionary = {}) -> Dictionary:
	if not _pending_proposal.is_empty() or not _next_tick(tick):
		return Utils.failure("BRIDGE4_REBAKE_BLOCKED_BY_PENDING_PROPOSAL")
	var live := _live_binding(snapshot, matter_batch, authority)
	if not live.success:
		return live
	var result := _fabric.rebake(tick, live.details.source_context)
	if not result.success:
		return result
	_last_tick = tick
	return Utils.success(status())

func capture_capsule() -> Dictionary:
	if _binding.is_empty():
		return Utils.failure("BRIDGE4_CAPSULE_UNAVAILABLE")
	var inner := _fabric.capture_capsule()
	if not inner.success:
		return inner
	var capsule := {
		"schema": CAPSULE_SCHEMA, "canonical": false, "derived": true, "discardable": true,
		"binding_checksum": _binding["checksum"], "authority_checksum": _authority["checksum"],
		"construct_id": _snapshot["construct_id"], "construct_revision": _snapshot["state_revision"],
		"matter_batch_id": _matter["batch_id"], "matter_checksum": _matter["checksum"],
		"event_ledger": _event_ledger.duplicate(), "canonical_mutations_observed": _canonical_mutations_observed,
		"last_tick": _last_tick, "pending_proposal": _pending_proposal.duplicate(true),
		"fabric1_capsule": inner.details.capsule, "checksum": "",
	}
	capsule["checksum"] = Utils.compute_checksum(capsule)
	return Utils.success({"capsule": capsule})

func restore(snapshot: Dictionary, matter_batch: Dictionary, capsule: Dictionary, authority: Dictionary = {}, authoritative_events: Array = []) -> Dictionary:
	if not _snapshot.is_empty():
		return Utils.failure("BRIDGE4_RESTORE_REQUIRES_NEW_RUNTIME")
	var context := Adapter.compile_authoritative(snapshot, matter_batch, authority, authoritative_events)
	if not context.success:
		return context
	var checked := _validate_capsule(capsule, context.details, authoritative_events)
	if not checked.success:
		return checked
	var pending: Dictionary = capsule.pending_proposal
	if not pending.is_empty():
		if typeof(pending.get("bond_id")) != TYPE_STRING or not Utils.is_non_negative_number(pending.get("load_n")):
			return Utils.failure("BRIDGE4_CAPSULE_PROPOSAL_INVALID")
		var bond := Adapter.bond_by_id(snapshot, pending.bond_id)
		if bond.is_empty() or bond.state == "BROKEN":
			return Utils.failure("BRIDGE4_CAPSULE_PROPOSAL_INVALID")
		if float(pending.load_n) / float(bond.strength_n) < TRIGGER_RATIO:
			return Utils.failure("BRIDGE4_CAPSULE_PROPOSAL_INVALID")
		if Utils.canonical_hash(pending) != Utils.canonical_hash(_proposal(snapshot, bond, float(pending.load_n))):
			return Utils.failure("BRIDGE4_CAPSULE_PROPOSAL_INVALID")
		if capsule.fabric1_capsule.get("mode") != "FULL":
			return Utils.failure("BRIDGE4_CAPSULE_PROPOSAL_INVALID")
	var next := Fabric1Runtime.new()
	var restored := next.restore(context.details.spec, capsule.fabric1_capsule, context.details.source_context)
	if not restored.success:
		return restored
	if int(capsule.last_tick) < int(next.status().last_tick) or int(capsule.canonical_mutations_observed) != int(next.status().canonical_mutations_observed):
		return Utils.failure("BRIDGE4_CAPSULE_STATE_INVALID")
	_fabric = next
	_adopt_source(snapshot, matter_batch, context.details, authoritative_events)
	_pending_proposal = pending.duplicate(true)
	_canonical_mutations_observed = int(capsule.canonical_mutations_observed)
	_last_tick = int(capsule.last_tick)
	return Utils.success(status())

func recover(snapshot: Dictionary, matter_batch: Dictionary, authority: Dictionary, authoritative_events: Array, capsule: Dictionary = {}, tick: int = 0) -> Dictionary:
	if not _snapshot.is_empty():
		return Utils.failure("BRIDGE4_RESTORE_REQUIRES_NEW_RUNTIME")
	var restored := restore(snapshot, matter_batch, capsule, authority, authoritative_events)
	if restored.success:
		return Utils.success({"recovery_kind": "WARM", "status": status()})
	var started := start_authoritative(snapshot, matter_batch, authority, authoritative_events, tick)
	if not started.success:
		return started
	return Utils.success({"recovery_kind": "COLD", "discard_error": restored.error_code, "status": status()})

func status() -> Dictionary:
	if _binding.is_empty():
		return {"mode": "UNINITIALIZED", "canonical_writes": 0}
	var inner := _fabric.status()
	return {
		"construct_id": _snapshot["construct_id"], "construct_revision": _snapshot["state_revision"],
		"construct_checksum": _snapshot["checksum"], "matter_batch_id": _matter["batch_id"],
		"matter_checksum": _matter["checksum"], "frontier_hash": _binding["frontier_hash"],
		"binding_checksum": _binding["checksum"], "authority": _authority.duplicate(true), "mode": inner["mode"],
		"event_ledger": _event_ledger.duplicate(), "pending_proposal": _pending_proposal.duplicate(true),
		"canonical_mutations_observed": _canonical_mutations_observed, "last_tick": _last_tick,
		"canonical_writes": 0, "fabric1": inner,
	}

func _live_binding(snapshot: Dictionary, matter_batch: Dictionary, authority: Dictionary) -> Dictionary:
	if _binding.is_empty():
		return Utils.failure("BRIDGE4_NOT_STARTED")
	var current_snapshot: Dictionary = _snapshot if snapshot.is_empty() else snapshot
	var current_matter: Dictionary = _matter if matter_batch.is_empty() else matter_batch
	var current_authority: Dictionary = _authority if authority.is_empty() else authority
	var context := Adapter.compile_authoritative(current_snapshot, current_matter, current_authority, _event_ledger)
	if not context.success:
		return context
	if context.details.binding.checksum != _binding.checksum:
		return Utils.failure("BRIDGE4_CANONICAL_BINDING_STALE")
	return context

func _adopt_source(snapshot: Dictionary, matter_batch: Dictionary, context: Dictionary, events: Array) -> void:
	_snapshot = snapshot.duplicate(true)
	_matter = matter_batch.duplicate(true)
	_binding = context.binding.duplicate(true)
	_authority = context.authority.duplicate(true)
	_event_ledger = events.duplicate()

func _next_tick(tick: int) -> bool:
	return Utils.is_json_integer(tick) and tick > _last_tick

static func _proposal(snapshot: Dictionary, bond: Dictionary, load_n: float) -> Dictionary:
	var value := {"schema": PROPOSAL_SCHEMA, "canonical": false, "write_authorized": false,
		"construct_id": snapshot["construct_id"], "expected_construct_revision": snapshot["state_revision"],
		"bond_id": bond["bond_id"], "load_n": load_n, "strength_n": float(bond["strength_n"]),
		"ratio": load_n / float(bond["strength_n"]), "cause": "OVERLOAD", "proposal_hash": ""}
	value["proposal_hash"] = Utils.canonical_hash(value)
	return value

static func _validate_capsule(capsule: Dictionary, context: Dictionary, events: Array) -> Dictionary:
	if not Utils.validate_exact_fields(capsule, CAPSULE_FIELDS).success:
		return Utils.failure("BRIDGE4_CAPSULE_FIELDS_INVALID")
	for field in ["schema", "binding_checksum", "authority_checksum", "construct_id", "matter_batch_id", "matter_checksum", "checksum"]:
		if typeof(capsule[field]) != TYPE_STRING:
			return Utils.failure("BRIDGE4_CAPSULE_INVALID")
	for field in ["canonical", "derived", "discardable"]:
		if typeof(capsule[field]) != TYPE_BOOL:
			return Utils.failure("BRIDGE4_CAPSULE_INVALID")
	for field in ["construct_revision", "canonical_mutations_observed", "last_tick"]:
		if not Utils.is_json_integer(capsule[field]) or int(capsule[field]) < 0:
			return Utils.failure("BRIDGE4_CAPSULE_STATE_INVALID")
	if typeof(capsule.event_ledger) != TYPE_ARRAY or typeof(capsule.pending_proposal) != TYPE_DICTIONARY or typeof(capsule.fabric1_capsule) != TYPE_DICTIONARY:
		return Utils.failure("BRIDGE4_CAPSULE_INVALID")
	if capsule.schema != CAPSULE_SCHEMA or capsule.canonical or not capsule.derived or not capsule.discardable:
		return Utils.failure("BRIDGE4_CAPSULE_INVALID")
	if not Utils.validate_checksum(capsule).success:
		return Utils.failure("BRIDGE4_CAPSULE_CHECKSUM_INVALID")
	if capsule.event_ledger != events:
		return Utils.failure("BRIDGE4_CAPSULE_EVENT_HISTORY_MISMATCH")
	var binding: Dictionary = context.binding
	if capsule.binding_checksum != binding.checksum or capsule.authority_checksum != context.authority.checksum:
		return Utils.failure("BRIDGE4_CAPSULE_STALE")
	for field in ["construct_id", "construct_revision", "matter_batch_id", "matter_checksum"]:
		if Utils.canonical_hash(capsule[field]) != Utils.canonical_hash(binding[field]):
			return Utils.failure("BRIDGE4_CAPSULE_CANONICAL_BINDING_MISMATCH")
	if int(capsule.canonical_mutations_observed) > events.size():
		return Utils.failure("BRIDGE4_CAPSULE_STATE_INVALID")
	return Utils.success()
