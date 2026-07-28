extends RefCounted

const ReplicationScript = preload("res://scripts/network/loopback/loopback_replication_transport.gd")
const SnapshotScript = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
const DeltaScript = preload("res://scripts/network/contracts/entity_delta_envelope.gd")

const SCHEMA: String = "planet_simulator.client_replica_store.v1"

var _replication
var _snapshot_deliveries: int = 0
var _delta_deliveries: int = 0
var _delta_replays: int = 0
var _mutation_count: int = 0


func setup() -> Dictionary:
	_replication = ReplicationScript.new()
	_replication.clear()
	_snapshot_deliveries = 0
	_delta_deliveries = 0
	_delta_replays = 0
	_mutation_count = 0
	return _success()


func accept_snapshot(snapshot_value: Dictionary) -> Dictionary:
	if _replication == null:
		return _failure("REPLICA_STORE_NOT_CONFIGURED")
	var validation: Dictionary = SnapshotScript.validate(snapshot_value)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_SNAPSHOT")))
	var result: Dictionary = _replication.send_snapshot(snapshot_value)
	if not bool(result.get("success", false)):
		return _failure(String(result.get("error_code", "SNAPSHOT_REJECTED")), result.get("details", {}))
	_snapshot_deliveries += 1
	return _success({
		"replay": bool(result.get("replay", false)),
		"snapshot": Dictionary(result.get("snapshot", {})).duplicate(true),
	})


func accept_delta(delta_value: Dictionary) -> Dictionary:
	if _replication == null:
		return _failure("REPLICA_STORE_NOT_CONFIGURED")
	var validation: Dictionary = DeltaScript.validate(delta_value)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_DELTA")))
	var result: Dictionary = _replication.send_delta(delta_value)
	if not bool(result.get("success", false)):
		return _failure(String(result.get("error_code", "DELTA_REJECTED")), result.get("details", {}))
	_delta_deliveries += 1
	if bool(result.get("replay", false)):
		_delta_replays += 1
	else:
		_mutation_count += 1
	return _success({
		"replay": bool(result.get("replay", false)),
		"snapshot": Dictionary(result.get("snapshot", {})).duplicate(true),
	})


func get_snapshot(entity_id: String) -> Dictionary:
	if _replication == null:
		return _failure("REPLICA_STORE_NOT_CONFIGURED")
	var result: Dictionary = _replication.get_snapshot(entity_id)
	if not bool(result.get("success", false)):
		return _failure(String(result.get("error_code", "SNAPSHOT_NOT_FOUND")))
	return _success({
		"replay": bool(result.get("replay", false)),
		"snapshot": Dictionary(result.get("snapshot", {})).duplicate(true),
	})


func get_snapshot_count() -> int:
	return _replication.get_snapshot_count() if _replication != null else 0


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


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
