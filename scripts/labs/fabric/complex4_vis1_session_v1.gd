extends RefCounted

const Fixture = preload("res://tests/research/fabric1/complex4_real_world_machine_fixture_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/complex4_real_world_machine_runtime_v1.gd")
const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_adapter_v1.gd")
const FAILURE_LOAD_N := 90.0

var runtime = null
var store = null
var matter: Dictionary = {}
var snapshot: Dictionary = {}
var pending_support_id := ""
var pending_event_id := ""
var tick := 10
var event_log: Array[String] = []
var authoritative_events: Array = []

func reset() -> Dictionary:
	matter = Fixture.matter_batch()
	var created := Fixture.create_store(Fixture.initial_snapshot())
	if not bool(created.result.get("success", false)):
		return {"success": false, "error": created.result}
	store = created.store
	snapshot = store.get_snapshot(Fixture.CONSTRUCT_ID)
	runtime = Runtime.new()
	var started: Dictionary = runtime.start(snapshot, matter, Fixture.AUTHORITY_OWNER, Fixture.AUTHORITY_EPOCH, _next_tick())
	if not bool(started.get("success", false)):
		return {"success": false, "error": started}
	pending_support_id = ""
	pending_event_id = ""
	authoritative_events = []
	event_log = ["RESET: revision 0 / two power paths / machine ON"]
	return {"success": true, "state": state()}

func propose(support_id: String, event_id: String) -> Dictionary:
	if runtime == null or not pending_support_id.is_empty():
		return {"success": false, "error": "VIS1_PROPOSAL_ORDER"}
	var bond := Fixture.bond(snapshot, support_id)
	if bond.is_empty() or String(bond.get("state", "")) == "BROKEN":
		return {"success": false, "error": "VIS1_SUPPORT_UNAVAILABLE"}
	var canonical_before := String(store.to_dict().checksum)
	var result: Dictionary = runtime.observe_load(snapshot, matter, support_id, FAILURE_LOAD_N, _next_tick())
	if not bool(result.get("success", false)):
		return {"success": false, "error": result}
	if String(store.to_dict().checksum) != canonical_before:
		return {"success": false, "error": "VIS1_PROPOSAL_MUTATED_CANONICAL"}
	pending_support_id = support_id
	pending_event_id = event_id
	_log("PROPOSAL: %s -> FULL; canonical revision stays %d" % [_short(support_id), int(snapshot.state_revision)])
	return {"success": true, "state": state()}

func apply_pending() -> Dictionary:
	if runtime == null or pending_support_id.is_empty():
		return {"success": false, "error": "VIS1_NO_PENDING_FAILURE"}
	var before := snapshot.duplicate(true)
	var desired := Fixture.successor_with_broken_support(before, pending_support_id)
	if desired.is_empty():
		return {"success": false, "error": "VIS1_SUCCESSOR_BUILD_FAILED"}
	var applied := Fixture.apply_successor(store, before, desired)
	if not bool(applied.result.get("success", false)):
		return {"success": false, "error": applied.result}
	snapshot = store.get_snapshot(Fixture.CONSTRUCT_ID)
	var next_events := authoritative_events.duplicate()
	next_events.append(pending_event_id)
	authoritative_events = Utils.sorted_strings(next_events)
	var observed: Dictionary = runtime.observe_canonical_successor(snapshot, matter, pending_event_id, _next_tick())
	if not bool(observed.get("success", false)):
		return {"success": false, "error": observed}
	var rebaked: Dictionary = runtime.rebake(_next_tick())
	if not bool(rebaked.get("success", false)):
		return {"success": false, "error": rebaked}
	_log("CANONICAL: %s BROKEN -> revision %d -> REBAKED" % [_short(pending_support_id), int(snapshot.state_revision)])
	pending_support_id = ""
	pending_event_id = ""
	return {"success": true, "state": state()}

func break_now(support_id: String, event_id: String) -> Dictionary:
	if pending_support_id == support_id:
		return apply_pending()
	if not pending_support_id.is_empty():
		return {"success": false, "error": "VIS1_OTHER_PROPOSAL_PENDING"}
	var proposed := propose(support_id, event_id)
	if not bool(proposed.get("success", false)):
		return proposed
	return apply_pending()

func restart() -> Dictionary:
	if runtime == null or not pending_support_id.is_empty():
		return {"success": false, "error": "VIS1_RESTART_ORDER"}
	var captured: Dictionary = runtime.capture_capsule()
	if not bool(captured.get("success", false)):
		return {"success": false, "error": captured}
	var restart_authority := Adapter.authority_for(snapshot, matter, Fixture.AUTHORITY_OWNER, Fixture.AUTHORITY_EPOCH)
	var next_runtime := Runtime.new()
	var restored: Dictionary = next_runtime.restore(snapshot, matter, captured.details.capsule, restart_authority, authoritative_events)
	if not bool(restored.get("success", false)):
		return {"success": false, "error": restored}
	runtime = next_runtime
	_log("RESTART: rebound to authoritative revision %d" % int(snapshot.state_revision))
	return {"success": true, "state": state()}

func state() -> Dictionary:
	if runtime == null:
		return {}
	var status: Dictionary = runtime.status()
	return {
		"revision": int(snapshot.get("state_revision", -1)),
		"build_state": String(snapshot.get("build_state", "")),
		"mode": String(status.get("mode", "")),
		"machine_state": String(status.get("machine_state", "")),
		"load_power_w": float(status.get("load_absorbed_power", 0.0)),
		"active_power_link_ids": Array(status.get("active_power_link_ids", [])).duplicate(),
		"support_a_state": String(Fixture.bond(snapshot, Fixture.SUPPORT_A).get("state", "")),
		"support_b_state": String(Fixture.bond(snapshot, Fixture.SUPPORT_B).get("state", "")),
		"canonical_writes": int(status.get("canonical_writes", -1)),
		"pending_support_id": pending_support_id,
		"functional_event_count": Array(status.get("functional_events", [])).size(),
	}

func _next_tick() -> int:
	tick += 1
	return tick

func _log(value: String) -> void:
	event_log.push_front(value)
	while event_log.size() > 5:
		event_log.pop_back()

func _short(support_id: String) -> String:
	return "PRIMARY SUPPORT" if support_id == Fixture.SUPPORT_A else "BACKUP SUPPORT"
