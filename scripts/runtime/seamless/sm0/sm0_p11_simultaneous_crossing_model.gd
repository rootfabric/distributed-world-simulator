extends RefCounted

const Contract = preload("res://scripts/runtime/seamless/sm0/sm0_p11_fault_contract.gd")

var _topology_revision := 1
var _records: Dictionary = {}
var _identity_to_aggregate: Dictionary = {}
var _authority_available: Dictionary = {}
var _pending: Dictionary = {}
var _completed: Dictionary = {}
var _interaction_ledger: Dictionary = {}
var _projections: Dictionary = {}
var _projection_available: Dictionary = {}

func setup(topology_revision: int = 1) -> Dictionary:
	if topology_revision < 1:
		return Contract.failure("SM0_P11_TOPOLOGY_REVISION_INVALID")
	_topology_revision = topology_revision
	_records.clear()
	_identity_to_aggregate.clear()
	_pending.clear()
	_completed.clear()
	_interaction_ledger.clear()
	_projections.clear()
	_projection_available.clear()
	_authority_available.clear()
	for authority_id in Contract.AUTHORITIES:
		_authority_available[authority_id] = true
	return Contract.success({"topology_revision": _topology_revision})

func seed_aggregate(aggregate_id: String, identity_id: String, kind: String, owner_authority_id: String, authority_epoch: int) -> Dictionary:
	if aggregate_id.strip_edges().is_empty() or identity_id.strip_edges().is_empty():
		return Contract.failure("SM0_P11_ID_REQUIRED")
	if kind not in Contract.AGGREGATE_KINDS:
		return Contract.failure("SM0_P11_KIND_INVALID")
	if not Contract.valid_authority(owner_authority_id) or authority_epoch < 1:
		return Contract.failure("SM0_P11_OWNER_INVALID")
	if _records.has(aggregate_id):
		return Contract.failure("SM0_P11_AGGREGATE_DUPLICATE", {"aggregate_id": aggregate_id})
	if _identity_to_aggregate.has(identity_id):
		return Contract.failure("SM0_P11_IDENTITY_DUPLICATE", {"identity_id": identity_id})
	_records[aggregate_id] = {
		"aggregate_id": aggregate_id,
		"identity_id": identity_id,
		"kind": kind,
		"owner_authority_id": owner_authority_id,
		"authority_epoch": authority_epoch,
		"state_revision": 1,
		"frozen": false,
		"active_writer_count": 1,
	}
	_identity_to_aggregate[identity_id] = aggregate_id
	return Contract.success()

func begin_transfer(operation_id: String, aggregate_id: String, source_authority_id: String, target_authority_id: String, expected_source_epoch: int, topology_revision: int) -> Dictionary:
	if operation_id.strip_edges().is_empty():
		return Contract.failure("SM0_P11_OPERATION_ID_REQUIRED")
	if not _records.has(aggregate_id):
		return Contract.failure("SM0_P11_AGGREGATE_UNKNOWN")
	var record: Dictionary = Dictionary(_records[aggregate_id])
	var signature := Contract.transfer_signature(operation_id, aggregate_id, String(record.get("identity_id", "")), source_authority_id, target_authority_id, expected_source_epoch, topology_revision)
	if _completed.has(operation_id):
		var completed: Dictionary = Dictionary(_completed[operation_id])
		if String(completed.get("signature", "")) != signature:
			return Contract.failure("SM0_P11_OPERATION_REUSE_CONFLICT")
		var replay_result: Dictionary = Dictionary(completed.get("result", {})).duplicate(true)
		replay_result["details"] = Dictionary(replay_result.get("details", {})).duplicate(true)
		Dictionary(replay_result["details"])["replay"] = true
		return replay_result
	if _pending.has(operation_id):
		var existing: Dictionary = Dictionary(_pending[operation_id])
		if String(existing.get("signature", "")) != signature:
			return Contract.failure("SM0_P11_OPERATION_REUSE_CONFLICT")
		return Contract.success({"replay": true, "phase": "PREPARED"})
	if topology_revision != _topology_revision:
		return Contract.failure("SM0_P11_STALE_TOPOLOGY_REVISION", {"current_topology_revision": _topology_revision})
	if not Contract.valid_authority(source_authority_id) or not Contract.valid_authority(target_authority_id) or source_authority_id == target_authority_id:
		return Contract.failure("SM0_P11_TRANSFER_ROUTE_INVALID")
	if not bool(_authority_available.get(target_authority_id, false)):
		return Contract.failure("SM0_P11_TARGET_UNAVAILABLE")
	if String(record.get("owner_authority_id", "")) != source_authority_id:
		return Contract.failure("SM0_P11_SOURCE_NOT_OWNER")
	if int(record.get("authority_epoch", 0)) != expected_source_epoch:
		return Contract.failure("SM0_P11_SOURCE_EPOCH_MISMATCH")
	if bool(record.get("frozen", false)):
		return Contract.failure("SM0_P11_SOURCE_ALREADY_FROZEN")
	if int(record.get("active_writer_count", 0)) != 1:
		return Contract.failure("SM0_P11_WRITER_INVARIANT_BROKEN")
	record["frozen"] = true
	_records[aggregate_id] = record
	_pending[operation_id] = {
		"signature": signature,
		"operation_id": operation_id,
		"aggregate_id": aggregate_id,
		"identity_id": String(record.get("identity_id", "")),
		"source_authority_id": source_authority_id,
		"target_authority_id": target_authority_id,
		"source_epoch": expected_source_epoch,
		"target_epoch": expected_source_epoch + 1,
		"topology_revision": topology_revision,
	}
	return Contract.success({"replay": false, "phase": "PREPARED"})

func commit_transfer(operation_id: String, inject_target_failure: bool = false) -> Dictionary:
	if _completed.has(operation_id):
		var completed: Dictionary = Dictionary(_completed[operation_id])
		var replay_result: Dictionary = Dictionary(completed.get("result", {})).duplicate(true)
		replay_result["details"] = Dictionary(replay_result.get("details", {})).duplicate(true)
		Dictionary(replay_result["details"])["replay"] = true
		return replay_result
	if not _pending.has(operation_id):
		return Contract.failure("SM0_P11_TRANSFER_NOT_PREPARED")
	var pending: Dictionary = Dictionary(_pending[operation_id])
	var aggregate_id := String(pending.get("aggregate_id", ""))
	if not _records.has(aggregate_id):
		return Contract.failure("SM0_P11_AGGREGATE_UNKNOWN")
	var record: Dictionary = Dictionary(_records[aggregate_id])
	if not bool(record.get("frozen", false)):
		return Contract.failure("SM0_P11_SOURCE_NOT_FROZEN")
	var result: Dictionary
	if inject_target_failure:
		record["frozen"] = false
		_records[aggregate_id] = record
		result = Contract.failure("SM0_P11_INJECTED_TARGET_COMMIT_FAILURE", {
			"rolled_back": true,
			"owner_authority_id": String(record.get("owner_authority_id", "")),
			"authority_epoch": int(record.get("authority_epoch", 0)),
			"replay": false,
		})
	else:
		record["owner_authority_id"] = String(pending.get("target_authority_id", ""))
		record["authority_epoch"] = int(pending.get("target_epoch", 0))
		record["state_revision"] = int(record.get("state_revision", 0)) + 1
		record["frozen"] = false
		record["active_writer_count"] = 1
		_records[aggregate_id] = record
		result = Contract.success({
			"owner_authority_id": String(record.get("owner_authority_id", "")),
			"authority_epoch": int(record.get("authority_epoch", 0)),
			"identity_id": String(record.get("identity_id", "")),
			"replay": false,
		})
	_completed[operation_id] = {"signature": String(pending.get("signature", "")), "result": result.duplicate(true)}
	_pending.erase(operation_id)
	return result

func cancel_transfer(operation_id: String) -> Dictionary:
	if not _pending.has(operation_id):
		return Contract.failure("SM0_P11_TRANSFER_NOT_PREPARED")
	var pending: Dictionary = Dictionary(_pending[operation_id])
	var aggregate_id := String(pending.get("aggregate_id", ""))
	var record: Dictionary = Dictionary(_records.get(aggregate_id, {}))
	record["frozen"] = false
	_records[aggregate_id] = record
	_pending.erase(operation_id)
	return Contract.success()

func interact(operation_id: String, aggregate_id: String, authority_id: String, expected_epoch: int) -> Dictionary:
	if _interaction_ledger.has(operation_id):
		var existing: Dictionary = Dictionary(_interaction_ledger[operation_id])
		if String(existing.get("aggregate_id", "")) != aggregate_id or String(existing.get("authority_id", "")) != authority_id or int(existing.get("expected_epoch", 0)) != expected_epoch:
			return Contract.failure("SM0_P11_INTERACTION_REPLAY_CONFLICT")
		var replay: Dictionary = Dictionary(existing.get("result", {})).duplicate(true)
		replay["details"] = Dictionary(replay.get("details", {})).duplicate(true)
		Dictionary(replay["details"])["replay"] = true
		return replay
	if not _records.has(aggregate_id):
		return Contract.failure("SM0_P11_AGGREGATE_UNKNOWN")
	var record: Dictionary = Dictionary(_records[aggregate_id])
	var result: Dictionary
	if String(record.get("owner_authority_id", "")) != authority_id:
		result = Contract.failure("SM0_P11_INTERACTION_NOT_OWNER")
	elif int(record.get("authority_epoch", 0)) != expected_epoch:
		result = Contract.failure("SM0_P11_INTERACTION_EPOCH_STALE")
	elif bool(record.get("frozen", false)):
		result = Contract.failure("SM0_P11_INTERACTION_SOURCE_FROZEN")
	elif not bool(_authority_available.get(authority_id, false)):
		result = Contract.failure("SM0_P11_INTERACTION_AUTHORITY_UNAVAILABLE")
	else:
		record["state_revision"] = int(record.get("state_revision", 0)) + 1
		_records[aggregate_id] = record
		result = Contract.success({
			"state_revision": int(record.get("state_revision", 0)),
			"authority_epoch": int(record.get("authority_epoch", 0)),
			"replay": false,
		})
	_interaction_ledger[operation_id] = {
		"aggregate_id": aggregate_id,
		"authority_id": authority_id,
		"expected_epoch": expected_epoch,
		"result": result.duplicate(true),
	}
	return result


func accept_projection(source_authority_id: String, source_epoch: int, sequence: int, checksum: String, entity_id: String) -> Dictionary:
	if not Contract.valid_authority(source_authority_id) or source_epoch < 1 or sequence < 1 or checksum.strip_edges().is_empty() or entity_id.strip_edges().is_empty():
		return Contract.failure("SM0_P11_PROJECTION_INVALID")
	if _projections.has(source_authority_id):
		var current: Dictionary = Dictionary(_projections[source_authority_id])
		var current_epoch := int(current.get("source_epoch", 0))
		if source_epoch < current_epoch:
			return Contract.failure("SM0_P11_PROJECTION_EPOCH_ROLLBACK")
		if source_epoch == current_epoch:
			var current_sequence := int(current.get("sequence", 0))
			if sequence < current_sequence:
				return Contract.failure("SM0_P11_PROJECTION_SEQUENCE_STALE")
			if sequence == current_sequence:
				if checksum == String(current.get("checksum", "")):
					_projection_available[source_authority_id] = true
					return Contract.success({"replay": true})
				return Contract.failure("SM0_P11_PROJECTION_SAME_SEQUENCE_MUTATION")
	_projections[source_authority_id] = {
		"source_authority_id": source_authority_id,
		"source_epoch": source_epoch,
		"sequence": sequence,
		"checksum": checksum,
		"entity_id": entity_id,
		"read_only": true,
		"canonical_write_allowed": false,
	}
	_projection_available[source_authority_id] = true
	return Contract.success({"replay": false})

func mark_projection_unavailable(source_authority_id: String, source_epoch: int) -> Dictionary:
	if not _projections.has(source_authority_id):
		return Contract.failure("SM0_P11_PROJECTION_SOURCE_UNKNOWN")
	var current: Dictionary = Dictionary(_projections[source_authority_id])
	if int(current.get("source_epoch", 0)) != source_epoch:
		return Contract.failure("SM0_P11_PROJECTION_DROPOUT_EPOCH_MISMATCH")
	_projection_available[source_authority_id] = false
	return Contract.success()

func compose_projection_view() -> Dictionary:
	var entities: Array = []
	var degraded_sources: Array = []
	for source_raw in _projections.keys():
		var source_id := String(source_raw)
		if bool(_projection_available.get(source_id, false)):
			entities.append(Dictionary(_projections[source_id]).duplicate(true))
		else:
			degraded_sources.append(source_id)
	degraded_sources.sort()
	return Contract.success({
		"entities": entities,
		"degraded_sources": degraded_sources,
		"presentation_only": true,
		"canonical_state_generated": false,
	})

func project_foreign(observer_authority_id: String, aggregate_id: String) -> Dictionary:
	if not Contract.valid_authority(observer_authority_id) or not _records.has(aggregate_id):
		return Contract.failure("SM0_P11_PROJECTION_INVALID")
	var record: Dictionary = Dictionary(_records[aggregate_id])
	return Contract.success({
		"aggregate_id": aggregate_id,
		"identity_id": String(record.get("identity_id", "")),
		"source_authority_id": String(record.get("owner_authority_id", "")),
		"source_authority_epoch": int(record.get("authority_epoch", 0)),
		"observer_authority_id": observer_authority_id,
		"read_only": true,
		"canonical_write_allowed": false,
	})

func attempt_projection_mutation(_projection: Dictionary) -> Dictionary:
	return Contract.failure("SM0_P11_FOREIGN_REPLICA_READ_ONLY")

func set_authority_available(authority_id: String, available: bool) -> Dictionary:
	if not Contract.valid_authority(authority_id):
		return Contract.failure("SM0_P11_AUTHORITY_INVALID")
	_authority_available[authority_id] = available
	return Contract.success()

func set_topology_revision(next_revision: int) -> Dictionary:
	if next_revision <= _topology_revision:
		return Contract.failure("SM0_P11_TOPOLOGY_REVISION_NOT_MONOTONIC")
	_topology_revision = next_revision
	return Contract.success({"topology_revision": _topology_revision})

func snapshot(aggregate_id: String) -> Dictionary:
	return Dictionary(_records.get(aggregate_id, {})).duplicate(true)

func active_writer_count(aggregate_id: String) -> int:
	if not _records.has(aggregate_id):
		return 0
	return int(Dictionary(_records[aggregate_id]).get("active_writer_count", 0))

func topology_revision() -> int:
	return _topology_revision

func pending_count() -> int:
	return _pending.size()
