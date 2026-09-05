extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Envelope = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_envelope_v1.gd")
const Selector = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_selector_v1.gd")
const Controller = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_controller_v1.gd")
const Recovery = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_recovery_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Slice = preload("res://scripts/research/fabric_bake0/bridge2_source_slice_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge2_region_adapter_v1.gd")
const ExecutionGate = preload("res://scripts/research/fabric_bake0/bake_execution_gate_v1.gd")
const SPEC_FIELDS: Array[String] = ["state_id", "storage", "damping", "initial_value", "backend_contract_hash"]
const COUNTERS: Array[String] = ["subjects_evaluated", "envelopes_compiled", "selector_decisions",
	"transition_requests", "actual_transitions", "promotions", "demotions", "blocked_demotions",
	"reconstructions", "local_rebuilds", "global_rebuilds", "duplicate_ownership_count",
	"unsafe_selection_count", "failed_closed"]
var _entries: Dictionary = {}
var _work: Dictionary = {}

func _init() -> void:
	for counter in COUNTERS:
		_work[counter] = 0

func register(source: Dictionary, authority: Dictionary, spec: Dictionary, candidates: Array,
	current: String = "FULL_FABRIC", config: Dictionary = Controller.DEFAULT_CONFIG) -> Dictionary:
	var checked := Controller.create(source, current, config)
	if not checked.get("success", false):
		return checked
	var key := Utils.source_key(source["source_domain"], source["source_id"])
	if _entries.has(key):
		return Utils.failure("ADAPTIVE_FIDELITY_DUPLICATE_SUBJECT")
	var state: Dictionary = checked["details"]["state"]
	_work["subjects_evaluated"] += 1
	_work["envelopes_compiled"] += 1
	checked = Envelope.compile(current, candidates)
	if not checked.get("success", false):
		return checked
	var envelope: Dictionary = checked["details"]["envelope"]
	_work["selector_decisions"] += 1
	checked = Selector.select(envelope, current, "HOLD_IF_SAFE")
	if not checked.get("success", false) or not envelope["admissible_fidelities"].has(current):
		return Utils.failure("UNSAFE_ADAPTIVE_FIDELITY_INITIAL_OWNER")
	checked = _prepare(state, authority, spec, {})
	if not checked.get("success", false):
		return checked
	_entries[key] = {"state": state, "authority": authority.duplicate(true), "spec": spec.duplicate(true),
		"slot": checked["details"]["slot"],
		"halted": false, "last_request_hash": "", "last_recovery_hash": ""}
	return Utils.success({"source_key": key})

# Only the addressed object is touched. There is deliberately no all-world rebuild
# path; the authoritative caller supplies changed subjects in deterministic order.
func evaluate(key: String, source: Dictionary, candidates: Array, policy: String, tick,
	authority: Dictionary = {}, spec: Dictionary = {}) -> Dictionary:
	if not _entries.has(key):
		return Utils.failure("UNKNOWN_ADAPTIVE_FIDELITY_SUBJECT")
	var entry: Dictionary = _entries[key]
	var fingerprint := Utils.canonical_hash({"source": source, "candidates": candidates,
		"policy": policy, "tick": tick, "authority": authority, "spec": spec})
	if not fingerprint.is_empty() and fingerprint == entry["last_request_hash"]:
		return Utils.success({"applied": false, "transition": {}})
	_work["subjects_evaluated"] += 1
	_work["envelopes_compiled"] += 1
	var checked := Envelope.compile(entry["state"]["current_fidelity"], candidates)
	if not checked.get("success", false):
		return _halt(key, checked)
	var envelope: Dictionary = checked["details"]["envelope"]
	_work["selector_decisions"] += 1
	checked = Selector.select(envelope, entry["state"]["current_fidelity"], policy)
	if not checked.get("success", false):
		return _halt(key, checked)
	var decision: Dictionary = checked["details"]["decision"]
	if not envelope["admissible_fidelities"].has(decision["target_fidelity"]):
		_work["unsafe_selection_count"] += 1
		return _halt(key, Utils.failure("UNSAFE_ADAPTIVE_FIDELITY_SELECTION"))
	checked = Controller.evaluate(entry["state"], envelope, decision, tick, source)
	if not checked.get("success", false):
		return _halt(key, checked)
	var output: Dictionary = checked["details"]
	if not output["applied"]:
		return Utils.success(output)
	var next: Dictionary = entry.duplicate(false)
	var next_authority: Dictionary = entry["authority"] if authority.is_empty() else authority
	var next_spec: Dictionary = entry["spec"] if spec.is_empty() else spec
	# Physical inputs cannot silently change behind an unchanged source binding.
	if not output["source_rebound"] and (next_authority != entry["authority"] or next_spec != entry["spec"]):
		return _halt(key, Utils.failure("ADAPTIVE_FIDELITY_INPUT_CHANGE_REQUIRES_SOURCE_BINDING"))
	var transition: Dictionary = output["transition"]
	var rebuild: bool = not transition.is_empty() or output["source_rebound"] or entry["halted"]
	if decision["target_fidelity"] != entry["state"]["current_fidelity"] or output["source_rebound"]:
		_work["transition_requests"] += 1
	if output["blocked_demotion"]:
		_work["blocked_demotions"] += 1
	if rebuild:
		var previous: Dictionary = entry["slot"]
		checked = _prepare(output["state"], next_authority, next_spec, previous, not output["source_rebound"])
		if not checked.get("success", false):
			return _halt(key, checked)
		next["slot"] = checked["details"]["slot"]
	if not transition.is_empty():
		_work["actual_transitions"] += 1
		_work["promotions" if Envelope.LEVELS.find(transition["to"]) < Envelope.LEVELS.find(transition["from"]) else "demotions"] += 1
	next["state"] = output["state"]
	next["authority"] = next_authority.duplicate(true)
	next["spec"] = next_spec.duplicate(true)
	next["last_request_hash"] = fingerprint
	next["halted"] = false
	# Single atomic publication: old and reconstructed owners never coexist in
	# the executable registry. Preparation has no canonical or physical writes.
	_entries[key] = next
	return Utils.success(output)

func restore(key: String, source: Dictionary, candidates: Array, policy: String, tick, capsule: Dictionary, authority: Dictionary = {}, spec: Dictionary = {}) -> Dictionary:
	if not _entries.has(key):
		return Utils.failure("UNKNOWN_ADAPTIVE_FIDELITY_SUBJECT")
	var entry: Dictionary = _entries[key]
	var source_check := Utils.validate_source_revision(source)
	if not source_check.get("success", false):
		return _halt(key, source_check)
	if Utils.source_key(source["source_domain"], source["source_id"]) != key:
		return _halt(key, Utils.failure("ADAPTIVE_FIDELITY_FOREIGN_SOURCE"))
	var old_source: Dictionary = entry["state"]["source_revision"]
	if source["source_revision"] < old_source["source_revision"] or source["authority_epoch"] < old_source["authority_epoch"]:
		return _halt(key, Utils.failure("ADAPTIVE_FIDELITY_SOURCE_REGRESSION"))
	var live_authority: Dictionary = entry["authority"] if authority.is_empty() else authority
	var live_spec: Dictionary = entry["spec"] if spec.is_empty() else spec
	if source["checksum"] == old_source["checksum"] and (live_authority != entry["authority"] or live_spec != entry["spec"]):
		return _halt(key, Utils.failure("ADAPTIVE_FIDELITY_INPUT_CHANGE_REQUIRES_SOURCE_BINDING"))
	# A cache is a hint, never the identity of an authoritative recovery operation.
	var fingerprint := Utils.canonical_hash({"source": source, "candidates": candidates,
		"policy": policy, "tick": tick, "authority": live_authority, "spec": live_spec})
	if not fingerprint.is_empty() and fingerprint == entry["last_recovery_hash"]:
		return Utils.success({"applied": false})
	if not Utils.is_json_integer(tick) or tick <= entry["state"]["last_evaluation_tick"]:
		return _halt(key, Utils.failure("ADAPTIVE_FIDELITY_RECOVERY_TICK_REGRESSION"))
	var checked := Recovery.recover(source, candidates, policy, entry["state"]["configuration"], tick, capsule)
	if not checked.get("success", false):
		return _halt(key, checked)
	var recovered: Dictionary = checked["details"]
	if Utils.source_key(source["source_domain"], source["source_id"]) != key:
		return _halt(key, Utils.failure("ADAPTIVE_FIDELITY_FOREIGN_SOURCE"))
	_work["subjects_evaluated"] += 1
	_work["envelopes_compiled"] += 2
	_work["selector_decisions"] += 1
	checked = _prepare(recovered["state"], live_authority, live_spec, {})
	if not checked.get("success", false):
		return _halt(key, checked)
	var next := entry.duplicate(false)
	next["state"] = recovered["state"]
	next["authority"] = live_authority.duplicate(true)
	next["spec"] = live_spec.duplicate(true)
	next["slot"] = checked["details"]["slot"]
	next["last_recovery_hash"] = fingerprint
	next["last_request_hash"] = ""
	next["halted"] = false
	_entries[key] = next
	return Utils.success({"applied": true, "recovery_hash": recovered["recovery_hash"]})

# B0.6 dispatches a validated descriptor to FABRIC; it does not implement or
# invoke a second solver. BRIDGE-2's five-region falsifier is kept unchanged.
func execution_descriptor(key: String) -> Dictionary:
	if not can_execute(key):
		return Utils.failure("ADAPTIVE_FIDELITY_EXECUTION_DISABLED")
	var checked := _adapter_gate(_entries[key]["slot"]["adapter"])
	if not checked.get("success", false):
		return _halt(key, checked)
	return Utils.success({"adapter": _entries[key]["slot"]["adapter"],
		"state_values": _entries[key]["slot"]["state_values"]})

func can_execute(key: String) -> bool:
	return _entries.has(key) and not _entries[key]["halted"] and _entries[key]["state"]["current_fidelity"] != "DORMANT"

func state(key: String) -> Dictionary:
	return _entries[key]["state"].duplicate(true) if _entries.has(key) else {}

func physical_state(key: String) -> Dictionary:
	return _entries[key]["slot"]["state_values"].duplicate(true) if _entries.has(key) else {}

func ownership(key: String) -> Dictionary:
	return _entries[key]["slot"]["ownership_contract"].duplicate(true) if _entries.has(key) else {}

func counters() -> Dictionary:
	return _work.duplicate()

func snapshot() -> Dictionary:
	# Diagnostic only: sorting never participates in simulation decisions.
	var keys: Array = _entries.keys()
	keys.sort()
	var states: Array = []
	var transitions: Array = []
	for key in keys:
		var entry: Dictionary = _entries[key]
		states.append([key, entry["state"]["checksum"], entry["slot"]["adapter"]["checksum"], entry["slot"]["checksum"], entry["halted"]])
		transitions.append([key, entry["state"]["transition_hash"]])
	return {"subjects": keys.size(), "state_hash": Utils.canonical_hash(states),
		"transition_hash": Utils.canonical_hash(transitions), "work_counters": counters()}

func _prepare(state_value: Dictionary, authority: Dictionary, spec: Dictionary, previous_session: Dictionary, keep_values: bool = true) -> Dictionary:
	var checked := Utils.validate_exact_fields(spec, SPEC_FIELDS)
	if not checked.get("success", false):
		return checked
	if not Utils.is_canonical_id(spec.get("state_id"), 2) or not Utils.is_finite_number(spec.get("initial_value")) or not Utils.is_positive_number(spec.get("storage")) or not Utils.is_non_negative_number(spec.get("damping")) or not Utils.is_lower_hex_64(spec.get("backend_contract_hash")):
		return Utils.failure("INVALID_ADAPTIVE_FIDELITY_PHYSICAL_SPEC")
	checked = Controller.bind_ownership(state_value, authority)
	if not checked.get("success", false):
		return checked
	var source: Dictionary = state_value["source_revision"]
	var frontier := Frontier.create([source])
	var key := Utils.source_key(source["source_domain"], source["source_id"])
	var region: String = source["source_id"] + "/region"
	var slice := Slice.create(region, frontier, authority, [key])
	var kind: String = checked["details"]["contract"]["representations"][0]["representation_kind"]
	var adapter := Adapter.create(region, kind, spec["state_id"], slice,
		spec["backend_contract_hash"], float(spec["storage"]), float(spec["damping"]), int(state_value["transition_count"]) + 1)
	if adapter.is_empty():
		return Utils.failure("ADAPTIVE_FIDELITY_RECONSTRUCTION_FAILED")
	checked = _adapter_gate(adapter)
	if not checked.get("success", false):
		return checked
	var owner := Controller.bind_ownership(state_value, authority)
	if not owner.get("success", false):
		return owner
	var contract: Dictionary = owner["details"]["contract"]
	if contract["region_bindings"].size() != 1:
		_work["duplicate_ownership_count"] += 1
		return Utils.failure("ADAPTIVE_FIDELITY_DUPLICATE_PHYSICAL_OWNER")
	# BRIDGE2_IDENTITY_SCALAR_HANDOFF_R1: the certified adapter's full/reduced
	# state schemas are identical. Reconstruct its declared state, not world truth.
	var values: Dictionary = {spec["state_id"]: float(spec["initial_value"])}
	if keep_values and not previous_session.is_empty():
		values = previous_session["state_values"].duplicate(true)
	var slot := {"adapter": adapter, "ownership_contract": contract, "state_values": values}
	slot["checksum"] = Utils.compute_checksum(slot)
	_work["reconstructions"] += 1
	_work["local_rebuilds"] += 1
	return Utils.success({"slot": slot})

static func _adapter_gate(adapter: Dictionary) -> Dictionary:
	var checked := Adapter.validate(adapter)
	if not checked.get("success", false):
		return checked
	if adapter["representation_kind"] == "FULL":
		return Utils.success()
	var artifact: Dictionary = adapter["artifact"]
	var slice: Dictionary = adapter["source_slice"]
	return ExecutionGate.can_execute(artifact, {
		"artifact_state": "READY", "canonical_source_frontier": slice["frontier"],
		"authority_envelope": slice["authority_envelope"],
		"dependency_set": artifact["source_binding"]["dependency_set"],
		"fabric_graph_hash": artifact["source_binding"]["fabric_graph_hash"],
		"fabric_compiler_version": artifact["source_binding"]["fabric_compiler_version"],
		"boundary_contract_hash": artifact["boundary_contract"]["contract_hash"],
		"bake_policy_hash": artifact["source_binding"]["bake_policy_hash"],
		"runtime_domain": {"source_frontier_hash": slice["frontier"]["frontier_hash"],
			"fabric_graph_hash": artifact["source_binding"]["fabric_graph_hash"],
			"elapsed_s": 0.0, "mode": adapter["representation_kind"], "quantities": {}},
		"runtime_error_estimator": {}, "guard_values": {}, "invalidations": []})

func _halt(key: String, failure: Dictionary) -> Dictionary:
	_entries[key]["halted"] = true
	_work["failed_closed"] += 1
	return failure
