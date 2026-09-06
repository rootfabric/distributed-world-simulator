extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_adapter_v1.gd")
const Fabric1Runtime = preload("res://scripts/research/fabric_bake0/fabric1_generalized_runtime_v1.gd")

const CAPSULE_SCHEMA := "planet_simulator.fabric_bridge4_runtime_capsule.v1"
const PROPOSAL_SCHEMA := "planet_simulator.fabric_bridge4_canonical_failure_proposal.v1"
const TRIGGER_RATIO := 0.80

var _fabric := Fabric1Runtime.new()
var _snapshot: Dictionary = {}
var _matter: Dictionary = {}
var _binding: Dictionary = {}
var _execution_owner := ""
var _authority_epoch := 0
var _event_ledger: Array = []
var _pending_proposal: Dictionary = {}
var _canonical_mutations_observed := 0

func start(snapshot: Dictionary, matter_batch: Dictionary, execution_owner: String, authority_epoch: int, tick: int = 0) -> Dictionary:
	if not _snapshot.is_empty():
		return Utils.failure("BRIDGE4_ALREADY_STARTED")
	var context := Adapter.compile(snapshot, matter_batch, execution_owner, authority_epoch, [])
	if not bool(context.get("success", false)):
		return context
	var started := _fabric.start_baked(context["details"]["spec"], tick)
	if not bool(started.get("success", false)):
		return started
	_snapshot = snapshot.duplicate(true)
	_matter = matter_batch.duplicate(true)
	_binding = context["details"]["binding"].duplicate(true)
	_execution_owner = execution_owner
	_authority_epoch = authority_epoch
	return Utils.success(status())

func execute(snapshot: Dictionary, matter_batch: Dictionary, excitation: Array) -> Dictionary:
	var live := _live_binding(snapshot, matter_batch)
	if not bool(live.get("success", false)):
		return live
	return _fabric.execute(excitation)

func observe_load(snapshot: Dictionary, matter_batch: Dictionary, bond_id: String, load_n: float, tick: int) -> Dictionary:
	if not _pending_proposal.is_empty() or not is_finite(load_n) or load_n < 0.0:
		return Utils.failure("BRIDGE4_LOAD_OBSERVATION_INVALID")
	var live := _live_binding(snapshot, matter_batch)
	if not bool(live.get("success", false)):
		return live
	var bond := Adapter.bond_by_id(snapshot, bond_id)
	if bond.is_empty() or String(bond.get("state", "")) == "BROKEN":
		return Utils.failure("BRIDGE4_LOAD_BOND_INVALID")
	var ratio := load_n / float(bond["strength_n"])
	if ratio < TRIGGER_RATIO:
		return Utils.success({"refined": false, "failure_proposed": false, "ratio": ratio, "status": status()})
	var refined := _fabric.refine_to_full("CANONICAL_BOND_OVERLOAD", tick)
	if not bool(refined.get("success", false)):
		return refined
	var proposal := {
		"schema": PROPOSAL_SCHEMA,
		"canonical": false,
		"write_authorized": false,
		"construct_id": snapshot["construct_id"],
		"expected_construct_revision": snapshot["state_revision"],
		"bond_id": bond_id,
		"load_n": load_n,
		"strength_n": float(bond["strength_n"]),
		"ratio": ratio,
		"cause": "OVERLOAD",
		"proposal_hash": "",
	}
	proposal["proposal_hash"] = Utils.canonical_hash(proposal)
	_pending_proposal = proposal.duplicate(true)
	return Utils.success({"refined": true, "failure_proposed": true, "proposal": proposal, "status": status()})

func observe_canonical_successor(successor_snapshot: Dictionary, matter_batch: Dictionary, event_id: String, tick: int) -> Dictionary:
	if _pending_proposal.is_empty() or _event_ledger.has(event_id) or not Utils.is_canonical_id(event_id, 2):
		return Utils.failure("BRIDGE4_CANONICAL_SUCCESSOR_ORDER_INVALID")
	var failed_bond_id := String(_pending_proposal["bond_id"])
	var checked := Adapter.validate_successor(_snapshot, successor_snapshot, _matter, matter_batch, failed_bond_id)
	if not bool(checked.get("success", false)):
		return checked
	var next_events := _event_ledger.duplicate()
	next_events.append(event_id)
	next_events.sort()
	var next_context := Adapter.compile(successor_snapshot, matter_batch, _execution_owner, _authority_epoch, next_events)
	if not bool(next_context.get("success", false)):
		return next_context
	var observed := _fabric.apply_canonical_failure(next_context["details"]["spec"], event_id, [failed_bond_id], tick)
	if not bool(observed.get("success", false)):
		return observed
	_snapshot = successor_snapshot.duplicate(true)
	_matter = matter_batch.duplicate(true)
	_binding = next_context["details"]["binding"].duplicate(true)
	_event_ledger = next_events
	_pending_proposal = {}
	_canonical_mutations_observed += 1
	return Utils.success({"failed_bond_id": failed_bond_id, "stale_error": observed["details"]["stale_error"], "status": status()})

func rebake(tick: int) -> Dictionary:
	if not _pending_proposal.is_empty():
		return Utils.failure("BRIDGE4_REBAKE_BLOCKED_BY_PENDING_PROPOSAL")
	var result := _fabric.rebake(tick)
	if not bool(result.get("success", false)):
		return result
	return Utils.success(status())

func capture_capsule() -> Dictionary:
	if not _pending_proposal.is_empty() or _binding.is_empty():
		return Utils.failure("BRIDGE4_CAPSULE_UNAVAILABLE")
	var inner := _fabric.capture_capsule()
	if not bool(inner.get("success", false)):
		return inner
	var capsule := {
		"schema": CAPSULE_SCHEMA,
		"canonical": false,
		"derived": true,
		"discardable": true,
		"binding_checksum": _binding["checksum"],
		"construct_id": _snapshot["construct_id"],
		"construct_revision": _snapshot["state_revision"],
		"matter_batch_id": _matter["batch_id"],
		"matter_checksum": _matter["checksum"],
		"execution_owner": _execution_owner,
		"authority_epoch": _authority_epoch,
		"event_ledger": _event_ledger.duplicate(),
		"canonical_mutations_observed": _canonical_mutations_observed,
		"fabric1_capsule": inner["details"]["capsule"].duplicate(true),
		"checksum": "",
	}
	capsule["checksum"] = Utils.compute_checksum(capsule)
	return Utils.success({"capsule": capsule})

func restore(authoritative_snapshot: Dictionary, matter_batch: Dictionary, capsule: Dictionary) -> Dictionary:
	if not _snapshot.is_empty():
		return Utils.failure("BRIDGE4_RESTORE_REQUIRES_NEW_RUNTIME")
	if capsule.get("schema") != CAPSULE_SCHEMA or capsule.get("canonical") != false or capsule.get("derived") != true or capsule.get("discardable") != true:
		return Utils.failure("BRIDGE4_CAPSULE_INVALID")
	var checked := Utils.validate_checksum(capsule)
	if not bool(checked.get("success", false)):
		return Utils.failure("BRIDGE4_CAPSULE_CHECKSUM_INVALID")
	var event_ledger: Array = capsule.get("event_ledger", []).duplicate()
	var context := Adapter.compile(authoritative_snapshot, matter_batch, String(capsule.get("execution_owner", "")), int(capsule.get("authority_epoch", 0)), event_ledger)
	if not bool(context.get("success", false)):
		return context
	if String(context["details"]["binding"]["checksum"]) != String(capsule.get("binding_checksum", "")):
		return Utils.failure("BRIDGE4_CAPSULE_STALE")
	if String(authoritative_snapshot["construct_id"]) != String(capsule.get("construct_id", "")) or int(authoritative_snapshot["state_revision"]) != int(capsule.get("construct_revision", -1)) or String(matter_batch["batch_id"]) != String(capsule.get("matter_batch_id", "")) or String(matter_batch["checksum"]) != String(capsule.get("matter_checksum", "")):
		return Utils.failure("BRIDGE4_CAPSULE_CANONICAL_BINDING_MISMATCH")
	var restored := _fabric.restore(context["details"]["spec"], capsule["fabric1_capsule"])
	if not bool(restored.get("success", false)):
		return restored
	_snapshot = authoritative_snapshot.duplicate(true)
	_matter = matter_batch.duplicate(true)
	_binding = context["details"]["binding"].duplicate(true)
	_execution_owner = String(capsule["execution_owner"])
	_authority_epoch = int(capsule["authority_epoch"])
	_event_ledger = event_ledger
	_canonical_mutations_observed = int(capsule.get("canonical_mutations_observed", 0))
	return Utils.success(status())

func status() -> Dictionary:
	if _binding.is_empty():
		return {"mode": "UNINITIALIZED", "canonical_writes": 0}
	var inner: Dictionary = _fabric.status()
	return {
		"construct_id": _snapshot["construct_id"],
		"construct_revision": _snapshot["state_revision"],
		"construct_checksum": _snapshot["checksum"],
		"matter_batch_id": _matter["batch_id"],
		"matter_checksum": _matter["checksum"],
		"frontier_hash": _binding["frontier_hash"],
		"binding_checksum": _binding["checksum"],
		"mode": inner.get("mode", ""),
		"event_ledger": _event_ledger.duplicate(),
		"pending_proposal": _pending_proposal.duplicate(true),
		"canonical_mutations_observed": _canonical_mutations_observed,
		"canonical_writes": 0,
		"fabric1": inner,
	}

func _live_binding(snapshot: Dictionary, matter_batch: Dictionary) -> Dictionary:
	if _binding.is_empty():
		return Utils.failure("BRIDGE4_NOT_STARTED")
	return Adapter.binding_matches(_binding, snapshot, matter_batch, _execution_owner, _authority_epoch, _event_ledger)
