extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Bridge = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_runtime_v1.gd")
const FunctionalPlane = preload("res://scripts/research/fabric_bake0/complex4_real_world_machine_projection_v1.gd")

const CAPSULE_SCHEMA := "planet_simulator.fabric_complex4_runtime_capsule.v2"
const CAPSULE_FIELDS: Array[String] = ["schema", "canonical", "derived", "discardable",
	"construct_id", "construct_revision", "construct_checksum", "matter_checksum",
	"functional_projection_hash", "functional_events", "bridge_capsule", "checksum"]
const EVENT_FIELDS: Array[String] = ["event_id", "from_revision", "to_revision", "before_state", "after_state",
	"before_active_power_link_ids", "after_active_power_link_ids", "functional_changed"]

var _bridge := Bridge.new()
var _snapshot: Dictionary = {}
var _matter: Dictionary = {}
var _functional: Dictionary = {}
var _functional_events: Array = []

func start(snapshot: Dictionary, matter_batch: Dictionary, execution_owner: String, authority_epoch: int, tick: int = 0) -> Dictionary:
	return start_authoritative(snapshot, matter_batch,
		Bridge.Adapter.authority_for(snapshot, matter_batch, execution_owner, authority_epoch), [], tick)

func start_authoritative(snapshot: Dictionary, matter_batch: Dictionary, authority: Dictionary, authoritative_events: Array, tick: int = 0) -> Dictionary:
	if not _snapshot.is_empty():
		return Utils.failure("COMPLEX4_ALREADY_STARTED")
	var functional := FunctionalPlane.solve(snapshot)
	if not functional.success:
		return functional
	var next := Bridge.new()
	var started := next.start_authoritative(snapshot, matter_batch, authority, authoritative_events, tick)
	if not started.success:
		return started
	_bridge = next
	_adopt(snapshot, matter_batch, functional.details)
	return Utils.success(status())

func execute(snapshot: Dictionary, matter_batch: Dictionary, excitation: Array, authority: Dictionary = {}) -> Dictionary:
	var physical := _bridge.execute(snapshot, matter_batch, excitation, authority)
	if not physical.success:
		return physical
	var functional := FunctionalPlane.solve(snapshot)
	if not functional.success:
		return functional
	if functional.details.projection_hash != _functional.get("projection_hash", ""):
		return Utils.failure("COMPLEX4_FUNCTIONAL_BINDING_STALE")
	return Utils.success({"physical": physical.details, "functional": functional.details, "machine_state": functional.details.machine_state})

func observe_load(snapshot: Dictionary, matter_batch: Dictionary, support_bond_id: String, load_n: float, tick: int, authority: Dictionary = {}) -> Dictionary:
	return _bridge.observe_load(snapshot, matter_batch, support_bond_id, load_n, tick, authority)

func observe_canonical_successor(successor_snapshot: Dictionary, matter_batch: Dictionary, event_id: String, tick: int, authority: Dictionary = {}) -> Dictionary:
	if _snapshot.is_empty():
		return Utils.failure("COMPLEX4_NOT_STARTED")
	# Prepare the entire functional successor before the nested physical commit.
	# A failed projection must never advance only one of the two views.
	var after := FunctionalPlane.solve(successor_snapshot)
	if not after.success:
		return after
	var row := {
		"event_id": event_id, "from_revision": _snapshot["state_revision"], "to_revision": successor_snapshot["state_revision"],
		"before_state": _functional["machine_state"], "after_state": after.details.machine_state,
		"before_active_power_link_ids": _functional["active_power_link_ids"].duplicate(),
		"after_active_power_link_ids": after.details.active_power_link_ids.duplicate(),
		"functional_changed": Utils.canonical_hash(_observables(_functional)) != Utils.canonical_hash(_observables(after.details)),
	}
	var observed := _bridge.observe_canonical_successor(successor_snapshot, matter_batch, event_id, tick, authority)
	if not observed.success:
		return observed
	_functional_events.append(row)
	_adopt(successor_snapshot, matter_batch, after.details)
	return Utils.success({"stale_error": observed.details.stale_error, "functional_event": row, "status": status()})

func rebake(tick: int, snapshot: Dictionary = {}, matter_batch: Dictionary = {}, authority: Dictionary = {}) -> Dictionary:
	var result := _bridge.rebake(tick, snapshot, matter_batch, authority)
	if not result.success:
		return result
	return Utils.success(status())

func capture_capsule() -> Dictionary:
	if _snapshot.is_empty():
		return Utils.failure("COMPLEX4_CAPSULE_UNAVAILABLE")
	var inner := _bridge.capture_capsule()
	if not inner.success:
		return inner
	var capsule := {
		"schema": CAPSULE_SCHEMA, "canonical": false, "derived": true, "discardable": true,
		"construct_id": _snapshot["construct_id"], "construct_revision": _snapshot["state_revision"],
		"construct_checksum": _snapshot["checksum"], "matter_checksum": _matter["checksum"],
		"functional_projection_hash": _functional["projection_hash"], "functional_events": _functional_events.duplicate(true),
		"bridge_capsule": inner.details.capsule, "checksum": "",
	}
	capsule["checksum"] = Utils.compute_checksum(capsule)
	return Utils.success({"capsule": capsule})

func restore(snapshot: Dictionary, matter_batch: Dictionary, capsule: Dictionary, authority: Dictionary = {}, authoritative_events: Array = []) -> Dictionary:
	if not _snapshot.is_empty():
		return Utils.failure("COMPLEX4_RESTORE_REQUIRES_NEW_RUNTIME")
	var functional := FunctionalPlane.solve(snapshot)
	if not functional.success:
		return functional
	var checked := _validate_capsule(snapshot, matter_batch, capsule, functional.details, authoritative_events)
	if not checked.success:
		return checked
	var next := Bridge.new()
	var restored := next.restore(snapshot, matter_batch, capsule.bridge_capsule, authority, authoritative_events)
	if not restored.success:
		return restored
	if int(next.status().canonical_mutations_observed) != capsule.functional_events.size():
		return Utils.failure("COMPLEX4_CAPSULE_EVENT_HISTORY_INVALID")
	_bridge = next
	_adopt(snapshot, matter_batch, functional.details)
	_functional_events = capsule.functional_events.duplicate(true)
	return Utils.success(status())

func recover(snapshot: Dictionary, matter_batch: Dictionary, authority: Dictionary, authoritative_events: Array, capsule: Dictionary = {}, tick: int = 0) -> Dictionary:
	if not _snapshot.is_empty():
		return Utils.failure("COMPLEX4_RESTORE_REQUIRES_NEW_RUNTIME")
	var restored := restore(snapshot, matter_batch, capsule, authority, authoritative_events)
	if restored.success:
		return Utils.success({"recovery_kind": "WARM", "status": status()})
	var started := start_authoritative(snapshot, matter_batch, authority, authoritative_events, tick)
	if not started.success:
		return started
	return Utils.success({"recovery_kind": "COLD", "discard_error": restored.error_code, "status": status()})

func status() -> Dictionary:
	if _snapshot.is_empty():
		return {"mode": "UNINITIALIZED", "canonical_writes": 0}
	var bridge := _bridge.status()
	return {
		"construct_id": _snapshot["construct_id"], "construct_revision": _snapshot["state_revision"],
		"construct_checksum": _snapshot["checksum"], "matter_checksum": _matter["checksum"], "mode": bridge["mode"],
		"machine_state": _functional["machine_state"], "active_power_link_ids": _functional["active_power_link_ids"].duplicate(),
		"disabled_power_link_ids": _functional["disabled_power_link_ids"].duplicate(), "load_absorbed_power": _functional["load_absorbed_power"],
		"functional_projection_hash": _functional["projection_hash"], "functional_events": _functional_events.duplicate(true),
		"canonical_writes": 0, "bridge": bridge,
	}

func _adopt(snapshot: Dictionary, matter_batch: Dictionary, functional: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_matter = matter_batch.duplicate(true)
	_functional = functional.duplicate(true)

static func _observables(value: Dictionary) -> Dictionary:
	return {"state": value.machine_state, "paths": value.active_power_link_ids,
		"power": value.load_absorbed_power, "effort": value.load_common, "flow": value.load_balance}

static func _validate_capsule(snapshot: Dictionary, matter_batch: Dictionary, capsule: Dictionary, functional: Dictionary, authoritative_events: Array) -> Dictionary:
	if not Utils.validate_exact_fields(capsule, CAPSULE_FIELDS).success:
		return Utils.failure("COMPLEX4_CAPSULE_FIELDS_INVALID")
	for field in ["schema", "construct_id", "construct_checksum", "matter_checksum", "functional_projection_hash", "checksum"]:
		if typeof(capsule[field]) != TYPE_STRING:
			return Utils.failure("COMPLEX4_CAPSULE_INVALID")
	for field in ["canonical", "derived", "discardable"]:
		if typeof(capsule[field]) != TYPE_BOOL:
			return Utils.failure("COMPLEX4_CAPSULE_INVALID")
	if not Utils.is_json_integer(capsule.construct_revision) or typeof(capsule.bridge_capsule) != TYPE_DICTIONARY or typeof(capsule.functional_events) != TYPE_ARRAY:
		return Utils.failure("COMPLEX4_CAPSULE_INVALID")
	if capsule.schema != CAPSULE_SCHEMA or capsule.canonical or not capsule.derived or not capsule.discardable:
		return Utils.failure("COMPLEX4_CAPSULE_INVALID")
	if not Utils.validate_checksum(capsule).success:
		return Utils.failure("COMPLEX4_CAPSULE_CHECKSUM_INVALID")
	if capsule.construct_id != snapshot.get("construct_id") or int(capsule.construct_revision) != int(snapshot.get("state_revision", -1)) or capsule.construct_checksum != snapshot.get("checksum") or capsule.matter_checksum != matter_batch.get("checksum"):
		return Utils.failure("COMPLEX4_CAPSULE_STALE")
	if capsule.functional_projection_hash != functional.projection_hash:
		return Utils.failure("COMPLEX4_FUNCTIONAL_RESTART_MISMATCH")
	var seen := {}
	var previous_revision := -1
	for row in capsule.functional_events:
		if typeof(row) != TYPE_DICTIONARY or not Utils.validate_exact_fields(row, EVENT_FIELDS).success:
			return Utils.failure("COMPLEX4_CAPSULE_EVENT_HISTORY_INVALID")
		if not Utils.is_canonical_id(row.event_id, 2) or not authoritative_events.has(row.event_id) or seen.has(row.event_id):
			return Utils.failure("COMPLEX4_CAPSULE_EVENT_HISTORY_INVALID")
		if not Utils.is_json_integer(row.from_revision) or not Utils.is_json_integer(row.to_revision) or int(row.from_revision) < 0 or int(row.to_revision) != int(row.from_revision) + 1:
			return Utils.failure("COMPLEX4_CAPSULE_EVENT_HISTORY_INVALID")
		if previous_revision >= 0 and int(row.from_revision) != previous_revision:
			return Utils.failure("COMPLEX4_CAPSULE_EVENT_HISTORY_INVALID")
		if not ["ON", "OFF"].has(row.before_state) or not ["ON", "OFF"].has(row.after_state) or typeof(row.functional_changed) != TYPE_BOOL:
			return Utils.failure("COMPLEX4_CAPSULE_EVENT_HISTORY_INVALID")
		for field in ["before_active_power_link_ids", "after_active_power_link_ids"]:
			if not Utils.validate_sorted_unique_strings(row[field], true).success:
				return Utils.failure("COMPLEX4_CAPSULE_EVENT_HISTORY_INVALID")
		previous_revision = int(row.to_revision)
		seen[row.event_id] = true
	if not capsule.functional_events.is_empty():
		var last: Dictionary = capsule.functional_events.back()
		if previous_revision != int(snapshot.state_revision) or last.after_state != functional.machine_state or last.after_active_power_link_ids != functional.active_power_link_ids:
			return Utils.failure("COMPLEX4_CAPSULE_EVENT_HISTORY_INVALID")
	return Utils.success()
