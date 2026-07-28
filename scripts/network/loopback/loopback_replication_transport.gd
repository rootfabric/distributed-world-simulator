extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
const DeltaScript = preload("res://scripts/network/contracts/entity_delta_envelope.gd")

var snapshots_by_entity: Dictionary = {}
var completed_deltas: Dictionary = {}


func clear() -> void:
	snapshots_by_entity.clear()
	completed_deltas.clear()


func send_snapshot(snapshot_value: Dictionary) -> Dictionary:
	var outbound: Dictionary = UtilsScript.json_round_trip(snapshot_value)
	if not bool(outbound.get("success", false)):
		return _failure("SERIALIZATION_FAILED")
	var snapshot: Dictionary = outbound.get("value", {})
	var validation: Dictionary = SnapshotScript.validate(snapshot)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_SNAPSHOT")), {
			"validation_error_code": String(validation.get("error_code", "")),
		})
	var normalized: Dictionary = SnapshotScript.normalize(snapshot)
	var entity_id: String = String(normalized["entity_id"])
	if snapshots_by_entity.has(entity_id):
		var current: Dictionary = snapshots_by_entity[entity_id]
		var incoming_epoch: int = int(normalized["authority_epoch"])
		var current_epoch: int = int(current["authority_epoch"])
		if incoming_epoch < current_epoch:
			return _failure("STALE_AUTHORITY_EPOCH")
		if incoming_epoch == current_epoch:
			var incoming_revision: int = int(normalized["state_revision"])
			var current_revision: int = int(current["state_revision"])
			if incoming_revision < current_revision:
				return _failure("STALE_SNAPSHOT_REVISION")
			if incoming_revision == current_revision:
				if String(normalized["checksum"]) == String(current["checksum"]):
					return _success(current, true)
				return _failure("SNAPSHOT_REVISION_CONFLICT")
	snapshots_by_entity[entity_id] = normalized.duplicate(true)
	return _success(normalized, false)


func send_delta(delta_value: Dictionary) -> Dictionary:
	var outbound: Dictionary = UtilsScript.json_round_trip(delta_value)
	if not bool(outbound.get("success", false)):
		return _failure("SERIALIZATION_FAILED")
	var delta: Dictionary = outbound.get("value", {})
	var validation: Dictionary = DeltaScript.validate(delta)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_DELTA")), {
			"validation_error_code": String(validation.get("error_code", "")),
		})
	var delta_id: String = String(delta["delta_id"])
	var delta_checksum: String = String(delta["checksum"])
	if completed_deltas.has(delta_id):
		var completed: Dictionary = completed_deltas[delta_id]
		if String(completed["delta_checksum"]) != delta_checksum:
			return _failure("DELTA_ID_CONFLICT")
		return _success(completed["snapshot"], true)
	var entity_id: String = String(delta["entity_id"])
	if not snapshots_by_entity.has(entity_id):
		return _failure("SNAPSHOT_REQUIRED")
	var applied: Dictionary = DeltaScript.apply_to_snapshot(snapshots_by_entity[entity_id], delta)
	if not bool(applied.get("success", false)):
		return _failure(String(applied.get("error_code", "DELTA_APPLY_FAILED")), {
			"validation_error_code": String(applied.get("validation_error_code", "")),
		})
	var result_snapshot: Dictionary = applied["snapshot"]
	var result_validation: Dictionary = SnapshotScript.validate(result_snapshot)
	if not bool(result_validation.get("success", false)):
		return _failure("INVALID_RESULT_SNAPSHOT", {
			"validation_error_code": String(result_validation.get("error_code", "")),
		})
	snapshots_by_entity[entity_id] = result_snapshot.duplicate(true)
	completed_deltas[delta_id] = {
		"delta_checksum": delta_checksum,
		"snapshot": result_snapshot.duplicate(true),
	}
	return _success(result_snapshot, false)


func get_snapshot(entity_id: String) -> Dictionary:
	if entity_id.strip_edges().is_empty():
		return _failure("INVALID_ENTITY_ID")
	if not snapshots_by_entity.has(entity_id):
		return _failure("SNAPSHOT_NOT_FOUND")
	return _success(snapshots_by_entity[entity_id], true)


func get_snapshot_count() -> int:
	return snapshots_by_entity.size()


func _success(snapshot: Dictionary, replay: bool) -> Dictionary:
	return {
		"success": true,
		"error_code": "",
		"replay": replay,
		"snapshot": snapshot.duplicate(true),
	}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"replay": false,
		"snapshot": {},
		"details": details.duplicate(true),
	}
