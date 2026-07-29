extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/network/contracts/aggregate_snapshot_envelope.gd")
const DeltaScript = preload("res://scripts/network/contracts/aggregate_delta_envelope.gd")

const SCHEMA: String = "planet_simulator.generic_aggregate_store.v1"

var _snapshots_by_id: Dictionary = {}
var _completed_deltas: Dictionary = {}
var _configured: bool = false
var _adapter_registry
var _snapshot_deliveries: int = 0
var _delta_deliveries: int = 0
var _delta_replays: int = 0
var _mutation_count: int = 0


func setup(adapter_registry = null) -> Dictionary:
	if adapter_registry == null or not adapter_registry.has_method("validate_snapshot") or not adapter_registry.has_method("validate_delta"):
		return _failure("AGGREGATE_ADAPTER_REGISTRY_REQUIRED")
	_adapter_registry = adapter_registry
	_snapshots_by_id.clear()
	_completed_deltas.clear()
	_snapshot_deliveries = 0
	_delta_deliveries = 0
	_delta_replays = 0
	_mutation_count = 0
	_configured = true
	return _success()


func accept_snapshot(snapshot_value: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("GENERIC_AGGREGATE_STORE_NOT_CONFIGURED")
	var round_trip: Dictionary = UtilsScript.json_round_trip(snapshot_value)
	if not bool(round_trip.get("success", false)):
		return _failure("AGGREGATE_SNAPSHOT_SERIALIZATION_FAILED")
	var snapshot: Dictionary = round_trip["value"]
	var validation: Dictionary = _adapter_registry.validate_snapshot(snapshot)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_AGGREGATE_SNAPSHOT")), validation.get("details", {}))
	var normalized: Dictionary = SnapshotScript.normalize(snapshot)
	var aggregate_id: String = SnapshotScript.aggregate_id(normalized)
	if _snapshots_by_id.has(aggregate_id):
		var current: Dictionary = _snapshots_by_id[aggregate_id]
		var current_identity: Dictionary = current["descriptor"]["identity"]
		var incoming_identity: Dictionary = normalized["descriptor"]["identity"]
		if incoming_identity != current_identity:
			return _failure("AGGREGATE_IDENTITY_CONFLICT")
		var current_authority: Dictionary = current["descriptor"]["authority"]
		var incoming_authority: Dictionary = normalized["descriptor"]["authority"]
		if int(incoming_authority["authority_epoch"]) < int(current_authority["authority_epoch"]):
			return _failure("STALE_AGGREGATE_AUTHORITY_EPOCH")
		if int(incoming_authority["authority_epoch"]) == int(current_authority["authority_epoch"]) and String(incoming_authority["authority_owner_id"]) != String(current_authority["authority_owner_id"]):
			return _failure("AGGREGATE_AUTHORITY_OWNER_EPOCH_CONFLICT")
		if int(incoming_authority["state_revision"]) < int(current_authority["state_revision"]):
			return _failure("STALE_AGGREGATE_SNAPSHOT_REVISION")
		if int(incoming_authority["server_tick"]) < int(current_authority["server_tick"]):
			return _failure("STALE_AGGREGATE_SERVER_TICK")
		if int(incoming_authority["state_revision"]) == int(current_authority["state_revision"]):
			if int(incoming_authority["authority_epoch"]) > int(current_authority["authority_epoch"]):
				if normalized["state"] != current["state"]:
					return _failure("AGGREGATE_SNAPSHOT_REVISION_CONFLICT")
				if normalized["descriptor"]["spatial_scope"] != current["descriptor"]["spatial_scope"]:
					return _failure("AGGREGATE_SNAPSHOT_REVISION_CONFLICT")
				if normalized["descriptor"]["partition_address"] != current["descriptor"]["partition_address"]:
					return _failure("AGGREGATE_SNAPSHOT_REVISION_CONFLICT")
				_snapshots_by_id[aggregate_id] = normalized.duplicate(true)
				_snapshot_deliveries += 1
				return _success({"replay": false, "authority_transfer": true, "snapshot": normalized.duplicate(true)})
			if String(normalized["checksum"]) == String(current["checksum"]):
				_snapshot_deliveries += 1
				return _success({"replay": true, "snapshot": current.duplicate(true)})
			return _failure("AGGREGATE_SNAPSHOT_REVISION_CONFLICT")
	_snapshots_by_id[aggregate_id] = normalized.duplicate(true)
	_snapshot_deliveries += 1
	return _success({"replay": false, "snapshot": normalized.duplicate(true)})


func accept_delta(delta_value: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("GENERIC_AGGREGATE_STORE_NOT_CONFIGURED")
	var round_trip: Dictionary = UtilsScript.json_round_trip(delta_value)
	if not bool(round_trip.get("success", false)):
		return _failure("AGGREGATE_DELTA_SERIALIZATION_FAILED")
	var delta: Dictionary = round_trip["value"]
	var validation: Dictionary = _adapter_registry.validate_delta(delta)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_AGGREGATE_DELTA")), validation.get("details", {}))
	var delta_id: String = String(delta["delta_id"])
	if _completed_deltas.has(delta_id):
		var completed: Dictionary = _completed_deltas[delta_id]
		if String(completed["delta_checksum"]) != String(delta["checksum"]):
			return _failure("AGGREGATE_DELTA_ID_CONFLICT")
		_delta_deliveries += 1
		_delta_replays += 1
		return _success({"replay": true, "snapshot": Dictionary(completed["snapshot"]).duplicate(true)})
	var aggregate_id: String = String(delta["aggregate_id"])
	if not _snapshots_by_id.has(aggregate_id):
		return _failure("AGGREGATE_SNAPSHOT_REQUIRED")
	var applied: Dictionary = DeltaScript.apply_to_snapshot(_snapshots_by_id[aggregate_id], delta)
	if not bool(applied.get("success", false)):
		return _failure(String(applied.get("error_code", "AGGREGATE_DELTA_APPLY_FAILED")))
	var snapshot: Dictionary = applied["snapshot"]
	var result_validation: Dictionary = _adapter_registry.validate_snapshot(snapshot)
	if not bool(result_validation.get("success", false)):
		return _failure("AGGREGATE_RESULT_SNAPSHOT_REJECTED", {"cause": result_validation})
	_snapshots_by_id[aggregate_id] = snapshot.duplicate(true)
	_completed_deltas[delta_id] = {
		"delta_checksum": String(delta["checksum"]),
		"snapshot": snapshot.duplicate(true),
	}
	_delta_deliveries += 1
	_mutation_count += 1
	return _success({"replay": false, "snapshot": snapshot.duplicate(true)})


func get_snapshot(aggregate_id: String) -> Dictionary:
	if not _configured:
		return _failure("GENERIC_AGGREGATE_STORE_NOT_CONFIGURED")
	if aggregate_id.strip_edges().is_empty():
		return _failure("INVALID_AGGREGATE_ID")
	if not _snapshots_by_id.has(aggregate_id):
		return _failure("AGGREGATE_SNAPSHOT_NOT_FOUND")
	return _success({"snapshot": Dictionary(_snapshots_by_id[aggregate_id]).duplicate(true)})


func get_snapshot_count() -> int:
	return _snapshots_by_id.size()


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"snapshot_count": get_snapshot_count(),
		"snapshot_deliveries": _snapshot_deliveries,
		"delta_deliveries": _delta_deliveries,
		"delta_replays": _delta_replays,
		"mutation_count": _mutation_count,
		"direct_authority_references": 0,
		"direct_domain_references": 0,
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
