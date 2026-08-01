extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const NetworkCommandScript = preload("res://scripts/network/contracts/network_command_envelope.gd")
const NetworkCommandResultScript = preload("res://scripts/network/contracts/network_command_result_envelope.gd")
const ReplicationEnvelopeScript = preload("res://scripts/network/bus/replication_envelope.gd")
const BodyScript = preload("res://scripts/simulation/matter/contracts/matter_body_definition.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const RequestScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const SnapshotStoreScript = preload("res://scripts/simulation/matter/storage/matter_sparse_brick_store.gd")
const JournalScript = preload("res://scripts/simulation/matter/mutation/matter_mutation_journal.gd")
const DeltaScript = preload("res://scripts/simulation/matter/network/matter_replication_delta.gd")
const StateSnapshotScript = preload("res://scripts/simulation/matter/network/matter_replication_snapshot.gd")
const FrameScript = preload("res://scripts/simulation/matter/network/matter_replication_frame.gd")
const SyncRequestScript = preload("res://scripts/simulation/matter/network/matter_replication_sync_request.gd")
const AckScript = preload("res://scripts/simulation/matter/network/matter_replication_ack.gd")

const COMMAND_TYPE: String = "MATTER_MUTATION"
const COMMAND_RESULT_PAYLOAD_SCHEMA: String = "planet_simulator.matter_authority_command_result.v1"

var _configured: bool = false
var _body: Dictionary = {}
var _grid_profile: Dictionary = {}
var _authority_owner_id: String = ""
var _authority_epoch: int = 0
var _client_id: String = ""
var _peer_id: String = ""
var _session_id: String = ""
var _stream_sequence: int = 0
var _store = null
var _journal = null
var _presenter = null
var _requires_resync: bool = false
var _command_results: Dictionary = {}
var _applied_delta_count: int = 0
var _applied_snapshot_count: int = 0
var _duplicate_frame_count: int = 0


func configure(
	body: Dictionary,
	grid_profile: Dictionary,
	authority_owner_id: String,
	authority_epoch: int,
	client_id: String,
	presenter = null
) -> Dictionary:
	if _configured:
		return MatterUtilsScript.failure("MATTER_REPLICA_ALREADY_CONFIGURED")
	if not bool(BodyScript.validate(body).get("success", false)) \
			or not bool(GridProfileScript.validate(grid_profile).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_REPLICA_WORLD")
	if String(body["body_id"]) != String(grid_profile["body_id"]) \
			or String(body["body_frame_id"]) != String(grid_profile["body_frame_id"]):
		return MatterUtilsScript.failure("MATTER_REPLICA_BODY_GRID_MISMATCH")
	if not MatterUtilsScript.is_canonical_id(authority_owner_id, 2) \
			or authority_epoch < 1 or not MatterUtilsScript.is_canonical_id(client_id, 2):
		return MatterUtilsScript.failure("INVALID_MATTER_REPLICA_CONFIGURATION")
	if presenter != null and not presenter.has_method("invalidate_brick_addresses"):
		return MatterUtilsScript.failure("INVALID_MATTER_REPLICA_PRESENTER")
	_store = SnapshotStoreScript.new()
	var store_setup: Dictionary = _store.configure(body, grid_profile)
	if not bool(store_setup.get("success", false)):
		return store_setup
	_journal = JournalScript.new()
	_body = body.duplicate(true)
	_grid_profile = grid_profile.duplicate(true)
	_authority_owner_id = authority_owner_id.strip_edges().to_lower()
	_authority_epoch = authority_epoch
	_client_id = client_id.strip_edges().to_lower()
	_presenter = presenter
	_stream_sequence = 0
	_requires_resync = false
	_command_results.clear()
	_configured = true
	return MatterUtilsScript.success({"state_hash": state_hash()})


func activate_session(peer_id: String, session_id: String) -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("MATTER_REPLICA_NOT_CONFIGURED")
	if not MatterUtilsScript.is_canonical_id(peer_id, 2) \
			or not MatterUtilsScript.is_canonical_id(session_id, 2):
		return MatterUtilsScript.failure("INVALID_MATTER_REPLICA_SESSION")
	_peer_id = peer_id.strip_edges().to_lower()
	_session_id = session_id.strip_edges().to_lower()
	return MatterUtilsScript.success({"peer_id": _peer_id, "session_id": _session_id})


func create_sync_request() -> Dictionary:
	if not _configured or _session_id.is_empty():
		return {}
	return SyncRequestScript.create(
		_client_id,
		_session_id,
		_authority_epoch,
		_stream_sequence,
		state_hash()
	)


func create_mutation_command(request: Dictionary, message_id: String) -> Dictionary:
	if not _configured or _session_id.is_empty() \
			or not bool(RequestScript.validate(request).get("success", false)) \
			or not MatterUtilsScript.is_canonical_id(message_id, 2):
		return {}
	var request_transport: String = PersistenceCodecScript.encode_persistence_json(request)
	if request_transport.is_empty():
		return {}
	var command: Dictionary = NetworkCommandScript.create(
		message_id,
		String(request["operation_id"]),
		String(_body["body_id"]),
		COMMAND_TYPE,
		{
			"peer_id": _peer_id,
			"session_id": _session_id,
			"request_transport": request_transport,
		},
		-1,
		_authority_epoch,
		int(request["client_tick"]),
		0
	)
	return command if bool(NetworkCommandScript.validate(command).get("success", false)) else {}


func accept_command_result(result_envelope: Dictionary) -> Dictionary:
	var validation: Dictionary = NetworkCommandResultScript.validate(result_envelope)
	if not bool(validation.get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_COMMAND_RESULT_ENVELOPE")
	if int(result_envelope["authority_epoch"]) != _authority_epoch:
		return MatterUtilsScript.failure("STALE_MATTER_COMMAND_RESULT_EPOCH")
	if String(result_envelope["status"]) != "SUCCEEDED":
		return MatterUtilsScript.failure(String(result_envelope["error_code"]), {
			"status": result_envelope["status"],
		})
	var payload: Dictionary = result_envelope["payload"]
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(payload, [
		"schema", "matter_result_transport", "stream_sequence", "state_hash",
		"replay", "replication_published",
	])
	if not bool(exact.get("success", false)) \
			or String(payload.get("schema", "")) != COMMAND_RESULT_PAYLOAD_SCHEMA \
			or typeof(payload.get("matter_result_transport")) != TYPE_STRING \
			or not MatterUtilsScript.is_json_integer(payload.get("stream_sequence")) \
			or not MatterUtilsScript.is_lower_hex_64(payload.get("state_hash")) \
			or typeof(payload.get("replay")) != TYPE_BOOL \
			or typeof(payload.get("replication_published")) != TYPE_BOOL:
		return MatterUtilsScript.failure("INVALID_MATTER_COMMAND_RESULT_PAYLOAD")
	var result_raw: Dictionary = PersistenceCodecScript.decode_persistence_json(
		String(payload["matter_result_transport"])
	)
	var result: Dictionary = PersistenceCodecScript.rehydrate_result(result_raw)
	if result.is_empty() or String(result["operation_id"]) != String(result_envelope["operation_id"]):
		return MatterUtilsScript.failure("INVALID_MATTER_COMMAND_DOMAIN_RESULT")
	_command_results[String(result["operation_id"])] = result.duplicate(true)
	return MatterUtilsScript.success({
		"result": result,
		"replay": payload["replay"],
		"replication_published": payload["replication_published"],
		"server_stream_sequence": int(payload["stream_sequence"]),
	})


func poll_replication(replication_adapter, max_count: int = 64) -> Dictionary:
	if not _configured or _peer_id.is_empty() or replication_adapter == null \
			or not replication_adapter.has_method("poll"):
		return MatterUtilsScript.failure("INVALID_MATTER_REPLICA_POLL")
	var polled: Dictionary = replication_adapter.poll(_peer_id, max_count)
	if not bool(polled.get("success", false)):
		return MatterUtilsScript.failure(String(polled.get("error_code", "MATTER_REPLICATION_POLL_FAILED")))
	var applied: int = 0
	for message_value in polled.get("details", {}).get("messages", []):
		if typeof(message_value) != TYPE_DICTIONARY:
			return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_MESSAGE")
		var message: Dictionary = message_value
		var envelope_validation: Dictionary = ReplicationEnvelopeScript.validate(message)
		if not bool(envelope_validation.get("success", false)):
			return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_ENVELOPE")
		if String(message["target_peer_id"]) != _peer_id \
				or String(message["payload_schema"]) != FrameScript.SCHEMA:
			return MatterUtilsScript.failure("MATTER_REPLICATION_ENVELOPE_ROUTE_MISMATCH")
		var frame_result: Dictionary = apply_frame(Dictionary(message["payload"]))
		if not bool(frame_result.get("success", false)):
			return frame_result
		applied += 1
	return MatterUtilsScript.success({
		"applied": applied,
		"remaining": int(polled.get("details", {}).get("remaining", 0)),
	})


func apply_frame(frame: Dictionary) -> Dictionary:
	var validation: Dictionary = FrameScript.validate(frame)
	if not bool(validation.get("success", false)):
		return validation
	if String(frame["body_id"]) != String(_body["body_id"]) \
			or String(frame["authority_owner_id"]) != _authority_owner_id \
			or int(frame["authority_epoch"]) != _authority_epoch:
		return MatterUtilsScript.failure("MATTER_REPLICATION_FRAME_AUTHORITY_MISMATCH")
	if String(frame["session_id"]) != _session_id:
		return MatterUtilsScript.failure("STALE_MATTER_REPLICATION_SESSION")
	var payload: Dictionary = FrameScript.decode_payload(frame)
	if payload.is_empty():
		return MatterUtilsScript.failure("MATTER_REPLICATION_FRAME_DECODE_FAILED")
	if String(frame["frame_kind"]) == "STATE_SNAPSHOT":
		return _apply_snapshot(payload)
	return _apply_delta(payload)


func create_ack() -> Dictionary:
	if not _configured or _session_id.is_empty():
		return {}
	return AckScript.create(
		_client_id,
		_session_id,
		_authority_epoch,
		_stream_sequence,
		state_hash()
	)


func state_hash() -> String:
	if not _configured:
		return ""
	return _compute_state_hash(_stream_sequence)


func stream_sequence() -> int:
	return _stream_sequence


func snapshot_store():
	return _store


func mutation_journal():
	return _journal


func requires_resync() -> bool:
	return _requires_resync


func command_result(operation_id: String) -> Dictionary:
	return Dictionary(_command_results.get(operation_id, {})).duplicate(true)


func report() -> Dictionary:
	return {
		"schema": "planet_simulator.matter_replica_report.v1",
		"client_id": _client_id,
		"peer_id": _peer_id,
		"session_id": _session_id,
		"stream_sequence": _stream_sequence,
		"state_hash": state_hash(),
		"requires_resync": _requires_resync,
		"applied_deltas": _applied_delta_count,
		"applied_snapshots": _applied_snapshot_count,
		"duplicate_frames": _duplicate_frame_count,
		"persistent_snapshots": _store.size(),
		"journal_records": _journal.size(),
	}


func _apply_delta(delta: Dictionary) -> Dictionary:
	var validation: Dictionary = DeltaScript.validate(delta)
	if not bool(validation.get("success", false)):
		return validation
	var sequence: int = int(delta["stream_sequence"])
	if sequence == _stream_sequence:
		if String(delta["target_state_hash"]) == state_hash():
			_duplicate_frame_count += 1
			return MatterUtilsScript.success({"replay": true})
		_requires_resync = true
		return MatterUtilsScript.failure("SAME_SEQUENCE_MATTER_REPLICATION_CONFLICT")
	if sequence <= _stream_sequence:
		return MatterUtilsScript.failure("STALE_MATTER_REPLICATION_DELTA")
	if int(delta["previous_stream_sequence"]) != _stream_sequence \
			or sequence != _stream_sequence + 1:
		_requires_resync = true
		return MatterUtilsScript.failure("MATTER_REPLICATION_SEQUENCE_GAP")
	if String(delta["base_state_hash"]) != state_hash():
		_requires_resync = true
		return MatterUtilsScript.failure("MATTER_REPLICATION_BASE_STATE_MISMATCH")
	var request_raw: Dictionary = PersistenceCodecScript.decode_persistence_json(
		String(delta["request_transport"])
	)
	var result_raw: Dictionary = PersistenceCodecScript.decode_persistence_json(
		String(delta["result_transport"])
	)
	var request: Dictionary = PersistenceCodecScript.rehydrate_request(request_raw)
	var result: Dictionary = PersistenceCodecScript.rehydrate_result(result_raw)
	if request.is_empty() or result.is_empty():
		return MatterUtilsScript.failure("MATTER_REPLICATION_OPERATION_DECODE_FAILED")
	var store_backup: Dictionary = _store.export_persistence_state()
	var journal_backup: Dictionary = _journal.export_persistence_state()
	var snapshots: Array = []
	var expected_by_address: Dictionary = {}
	var changed_address_ids: Array = []
	for transport_value in delta["snapshot_transports"]:
		var snapshot_raw: Dictionary = PersistenceCodecScript.decode_persistence_json(
			String(transport_value)
		)
		var snapshot: Dictionary = PersistenceCodecScript.rehydrate_snapshot(snapshot_raw)
		if snapshot.is_empty():
			return MatterUtilsScript.failure("MATTER_REPLICATION_SNAPSHOT_DECODE_FAILED")
		var address_id: String = String(snapshot["address"]["address_id"])
		expected_by_address[address_id] = _store.revision_for_address_id(address_id)
		snapshots.append(snapshot)
		changed_address_ids.append(address_id)
	if not snapshots.is_empty():
		var store_commit: Dictionary = _store.put_many_atomic(snapshots, expected_by_address)
		if not bool(store_commit.get("success", false)):
			_requires_resync = true
			return MatterUtilsScript.failure("MATTER_REPLICA_STORE_COMMIT_FAILED", {"cause": store_commit})
	var journal_commit: Dictionary = _journal.record(request, result)
	if not bool(journal_commit.get("success", false)):
		_restore_components(store_backup, journal_backup)
		_requires_resync = true
		return MatterUtilsScript.failure("MATTER_REPLICA_JOURNAL_COMMIT_FAILED", {"cause": journal_commit})
	var target_hash: String = _compute_state_hash(sequence)
	if target_hash != String(delta["target_state_hash"]):
		_restore_components(store_backup, journal_backup)
		_requires_resync = true
		return MatterUtilsScript.failure("MATTER_REPLICATION_TARGET_STATE_MISMATCH")
	_stream_sequence = sequence
	_requires_resync = false
	_applied_delta_count += 1
	if _presenter != null and not changed_address_ids.is_empty():
		changed_address_ids.sort()
		_presenter.invalidate_brick_addresses(changed_address_ids)
	return MatterUtilsScript.success({
		"stream_sequence": _stream_sequence,
		"changed_address_ids": changed_address_ids,
		"status": result["status"],
	})


func _apply_snapshot(snapshot: Dictionary) -> Dictionary:
	var validation: Dictionary = StateSnapshotScript.validate(snapshot)
	if not bool(validation.get("success", false)):
		return validation
	var sequence: int = int(snapshot["stream_sequence"])
	if sequence < _stream_sequence:
		return MatterUtilsScript.failure("STALE_MATTER_REPLICATION_SNAPSHOT")
	if sequence == _stream_sequence:
		if String(snapshot["state_hash"]) == state_hash():
			_duplicate_frame_count += 1
			return MatterUtilsScript.success({"replay": true})
		_requires_resync = true
		return MatterUtilsScript.failure("SAME_SEQUENCE_MATTER_SNAPSHOT_CONFLICT")
	var store_state: Dictionary = PersistenceCodecScript.decode_persistence_json(
		String(snapshot["store_state_transport"])
	)
	var journal_state: Dictionary = PersistenceCodecScript.decode_persistence_json(
		String(snapshot["journal_state_transport"])
	)
	var store_backup: Dictionary = _store.export_persistence_state()
	var journal_backup: Dictionary = _journal.export_persistence_state()
	var old_address_ids: Array = _store.address_ids()
	var store_restore: Dictionary = _store.restore_persistence_state(store_state)
	if not bool(store_restore.get("success", false)):
		return MatterUtilsScript.failure("MATTER_REPLICA_SNAPSHOT_STORE_RESTORE_FAILED", {"cause": store_restore})
	var journal_restore: Dictionary = _journal.restore_persistence_state(journal_state)
	if not bool(journal_restore.get("success", false)):
		_restore_components(store_backup, journal_backup)
		return MatterUtilsScript.failure("MATTER_REPLICA_SNAPSHOT_JOURNAL_RESTORE_FAILED", {"cause": journal_restore})
	var target_hash: String = _compute_state_hash(sequence)
	if target_hash != String(snapshot["state_hash"]):
		_restore_components(store_backup, journal_backup)
		_requires_resync = true
		return MatterUtilsScript.failure("MATTER_REPLICA_SNAPSHOT_STATE_MISMATCH")
	_stream_sequence = sequence
	_requires_resync = false
	_applied_snapshot_count += 1
	if _presenter != null:
		var invalidated: Array = MatterUtilsScript.sorted_unique_ids(
			old_address_ids + _store.address_ids()
		)
		if not invalidated.is_empty():
			_presenter.invalidate_brick_addresses(invalidated)
	return MatterUtilsScript.success({
		"stream_sequence": _stream_sequence,
		"persistent_snapshot_count": _store.size(),
		"operation_count": _journal.size(),
	})


func _restore_components(store_state: Dictionary, journal_state: Dictionary) -> bool:
	var store_restore: Dictionary = _store.restore_persistence_state(store_state)
	var journal_restore: Dictionary = _journal.restore_persistence_state(journal_state)
	return bool(store_restore.get("success", false)) and bool(journal_restore.get("success", false))


func _compute_state_hash(sequence: int) -> String:
	return MatterUtilsScript.payload_hash({
		"body_id": _body.get("body_id", ""),
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"stream_sequence": sequence,
		"store_hash": _store.content_hash(),
		"journal_hash": _journal.content_hash(),
	})
