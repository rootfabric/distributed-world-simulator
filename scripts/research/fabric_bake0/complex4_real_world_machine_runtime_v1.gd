extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Bridge = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_runtime_v1.gd")
const FunctionalPlane = preload("res://scripts/research/fabric_bake0/complex4_real_world_machine_projection_v1.gd")

const CAPSULE_SCHEMA := "planet_simulator.fabric_complex4_runtime_capsule.v1"

var _bridge := Bridge.new()
var _snapshot: Dictionary = {}
var _matter: Dictionary = {}
var _functional: Dictionary = {}
var _functional_events: Array = []

func start(snapshot: Dictionary, matter_batch: Dictionary, execution_owner: String, authority_epoch: int, tick: int = 0) -> Dictionary:
	if not _snapshot.is_empty():
		return Utils.failure("COMPLEX4_ALREADY_STARTED")
	var functional := FunctionalPlane.solve(snapshot)
	if not bool(functional.get("success", false)):
		return functional
	var started := _bridge.start(snapshot, matter_batch, execution_owner, authority_epoch, tick)
	if not bool(started.get("success", false)):
		return started
	_snapshot = snapshot.duplicate(true)
	_matter = matter_batch.duplicate(true)
	_functional = functional["details"].duplicate(true)
	return Utils.success(status())

func execute(snapshot: Dictionary, matter_batch: Dictionary, excitation: Array) -> Dictionary:
	var physical := _bridge.execute(snapshot, matter_batch, excitation)
	if not bool(physical.get("success", false)):
		return physical
	var functional := FunctionalPlane.solve(snapshot)
	if not bool(functional.get("success", false)):
		return functional
	if not _functional.is_empty() and String(functional["details"]["projection_hash"]) != String(_functional.get("projection_hash", "")):
		return Utils.failure("COMPLEX4_FUNCTIONAL_BINDING_STALE")
	return Utils.success({
		"physical": physical["details"],
		"functional": functional["details"],
		"machine_state": functional["details"]["machine_state"],
	})

func observe_load(snapshot: Dictionary, matter_batch: Dictionary, support_bond_id: String, load_n: float, tick: int) -> Dictionary:
	return _bridge.observe_load(snapshot, matter_batch, support_bond_id, load_n, tick)

func observe_canonical_successor(successor_snapshot: Dictionary, matter_batch: Dictionary, event_id: String, tick: int) -> Dictionary:
	if _snapshot.is_empty():
		return Utils.failure("COMPLEX4_NOT_STARTED")
	var before := FunctionalPlane.solve(_snapshot)
	if not bool(before.get("success", false)):
		return before
	var observed := _bridge.observe_canonical_successor(successor_snapshot, matter_batch, event_id, tick)
	if not bool(observed.get("success", false)):
		return observed
	var after := FunctionalPlane.solve(successor_snapshot)
	if not bool(after.get("success", false)):
		return after
	var row := {
		"event_id": event_id,
		"from_revision": _snapshot["state_revision"],
		"to_revision": successor_snapshot["state_revision"],
		"before_state": before["details"]["machine_state"],
		"after_state": after["details"]["machine_state"],
		"before_active_power_link_ids": before["details"]["active_power_link_ids"].duplicate(),
		"after_active_power_link_ids": after["details"]["active_power_link_ids"].duplicate(),
		"functional_changed": String(before["details"]["projection_hash"]) != String(after["details"]["projection_hash"]),
	}
	_functional_events.append(row)
	_snapshot = successor_snapshot.duplicate(true)
	_matter = matter_batch.duplicate(true)
	_functional = after["details"].duplicate(true)
	return Utils.success({
		"stale_error": observed["details"]["stale_error"],
		"functional_event": row,
		"status": status(),
	})

func rebake(tick: int) -> Dictionary:
	var result := _bridge.rebake(tick)
	if not bool(result.get("success", false)):
		return result
	return Utils.success(status())

func capture_capsule() -> Dictionary:
	if _snapshot.is_empty() or _functional.is_empty():
		return Utils.failure("COMPLEX4_CAPSULE_UNAVAILABLE")
	var inner := _bridge.capture_capsule()
	if not bool(inner.get("success", false)):
		return inner
	var capsule := {
		"schema": CAPSULE_SCHEMA,
		"canonical": false,
		"derived": true,
		"discardable": true,
		"construct_id": _snapshot["construct_id"],
		"construct_revision": _snapshot["state_revision"],
		"construct_checksum": _snapshot["checksum"],
		"matter_checksum": _matter["checksum"],
		"functional_projection_hash": _functional["projection_hash"],
		"functional_events": _functional_events.duplicate(true),
		"bridge_capsule": inner["details"]["capsule"].duplicate(true),
		"checksum": "",
	}
	capsule["checksum"] = Utils.compute_checksum(capsule)
	return Utils.success({"capsule": capsule})

func restore(authoritative_snapshot: Dictionary, matter_batch: Dictionary, capsule: Dictionary) -> Dictionary:
	if not _snapshot.is_empty():
		return Utils.failure("COMPLEX4_RESTORE_REQUIRES_NEW_RUNTIME")
	if capsule.get("schema") != CAPSULE_SCHEMA or capsule.get("canonical") != false or capsule.get("derived") != true or capsule.get("discardable") != true:
		return Utils.failure("COMPLEX4_CAPSULE_INVALID")
	if not bool(Utils.validate_checksum(capsule).get("success", false)):
		return Utils.failure("COMPLEX4_CAPSULE_CHECKSUM_INVALID")
	if String(authoritative_snapshot.get("construct_id", "")) != String(capsule.get("construct_id", "")) or int(authoritative_snapshot.get("state_revision", -1)) != int(capsule.get("construct_revision", -2)) or String(authoritative_snapshot.get("checksum", "")) != String(capsule.get("construct_checksum", "")) or String(matter_batch.get("checksum", "")) != String(capsule.get("matter_checksum", "")):
		return Utils.failure("COMPLEX4_CAPSULE_STALE")
	var functional := FunctionalPlane.solve(authoritative_snapshot)
	if not bool(functional.get("success", false)):
		return functional
	if String(functional["details"]["projection_hash"]) != String(capsule.get("functional_projection_hash", "")):
		return Utils.failure("COMPLEX4_FUNCTIONAL_RESTART_MISMATCH")
	var restored := _bridge.restore(authoritative_snapshot, matter_batch, capsule["bridge_capsule"])
	if not bool(restored.get("success", false)):
		return restored
	_snapshot = authoritative_snapshot.duplicate(true)
	_matter = matter_batch.duplicate(true)
	_functional = functional["details"].duplicate(true)
	_functional_events = capsule.get("functional_events", []).duplicate(true)
	return Utils.success(status())

func status() -> Dictionary:
	if _snapshot.is_empty():
		return {"mode": "UNINITIALIZED", "canonical_writes": 0}
	return {
		"construct_id": _snapshot["construct_id"],
		"construct_revision": _snapshot["state_revision"],
		"construct_checksum": _snapshot["checksum"],
		"matter_checksum": _matter["checksum"],
		"mode": _bridge.status().get("mode", ""),
		"machine_state": _functional.get("machine_state", ""),
		"active_power_link_ids": _functional.get("active_power_link_ids", []).duplicate(),
		"disabled_power_link_ids": _functional.get("disabled_power_link_ids", []).duplicate(),
		"load_absorbed_power": _functional.get("load_absorbed_power", 0.0),
		"functional_projection_hash": _functional.get("projection_hash", ""),
		"functional_events": _functional_events.duplicate(true),
		"canonical_writes": 0,
		"bridge": _bridge.status(),
	}
