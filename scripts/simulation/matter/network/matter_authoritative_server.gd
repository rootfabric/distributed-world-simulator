extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const NetworkCommandScript = preload("res://scripts/network/contracts/network_command_envelope.gd")
const ReplicationEnvelopeScript = preload("res://scripts/network/bus/replication_envelope.gd")
const BodyScript = preload("res://scripts/simulation/matter/contracts/matter_body_definition.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const RequestScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const ResultScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_result.gd")
const DeltaScript = preload("res://scripts/simulation/matter/network/matter_replication_delta.gd")
const SnapshotScript = preload("res://scripts/simulation/matter/network/matter_replication_snapshot.gd")
const FrameScript = preload("res://scripts/simulation/matter/network/matter_replication_frame.gd")
const SyncRequestScript = preload("res://scripts/simulation/matter/network/matter_replication_sync_request.gd")
const AckScript = preload("res://scripts/simulation/matter/network/matter_replication_ack.gd")

const COMMAND_TYPE: String = "MATTER_MUTATION"
const COMMAND_PAYLOAD_FIELDS: Array[String] = ["peer_id", "session_id", "request_transport"]
const COMMAND_RESULT_PAYLOAD_SCHEMA: String = "planet_simulator.matter_authority_command_result.v1"
const SOURCE_ID: String = "source/mw6-matter-authority"

var _configured: bool = false
var _body: Dictionary = {}
var _grid_profile: Dictionary = {}
var _service = null
var _authority_owner_id: String = ""
var _authority_epoch: int = 0
var _stream_sequence: int = 0
var _max_replay_deltas: int = 64
var _replay_log: Array[Dictionary] = []
var _state_hash_by_sequence: Dictionary = {}
var _peers: Dictionary = {}
var _active_peer_by_client_id: Dictionary = {}
var _outbound_by_peer_id: Dictionary = {}
var _frame_serial: int = 0


func configure(
	body: Dictionary,
	grid_profile: Dictionary,
	excavation_service,
	authority_owner_id: String,
	authority_epoch: int,
	max_replay_deltas: int = 64
) -> Dictionary:
	if _configured:
		return MatterUtilsScript.failure("MATTER_AUTHORITY_ALREADY_CONFIGURED")
	if not bool(BodyScript.validate(body).get("success", false)) \
			or not bool(GridProfileScript.validate(grid_profile).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_AUTHORITY_WORLD")
	if String(body["body_id"]) != String(grid_profile["body_id"]) \
			or String(body["body_frame_id"]) != String(grid_profile["body_frame_id"]):
		return MatterUtilsScript.failure("MATTER_AUTHORITY_BODY_GRID_MISMATCH")
	if excavation_service == null \
			or not excavation_service.has_method("execute") \
			or not excavation_service.has_method("snapshot_store") \
			or not excavation_service.has_method("mutation_journal"):
		return MatterUtilsScript.failure("INVALID_MATTER_AUTHORITY_SERVICE")
	var existing_store = excavation_service.snapshot_store()
	var existing_journal = excavation_service.mutation_journal()
	if existing_store == null or existing_journal == null \
			or not existing_store.has_method("content_hash") \
			or not existing_store.has_method("export_persistence_state") \
			or not existing_journal.has_method("content_hash") \
			or not existing_journal.has_method("export_persistence_state") \
			or not existing_journal.has_method("size"):
		return MatterUtilsScript.failure("INVALID_MATTER_AUTHORITY_STATE")
	if not MatterUtilsScript.is_canonical_id(authority_owner_id, 2) \
			or authority_epoch < 1 or max_replay_deltas < 0 or max_replay_deltas > 4096:
		return MatterUtilsScript.failure("INVALID_MATTER_AUTHORITY_CONFIGURATION")
	_body = body.duplicate(true)
	_grid_profile = grid_profile.duplicate(true)
	_service = excavation_service
	_authority_owner_id = authority_owner_id.strip_edges().to_lower()
	_authority_epoch = authority_epoch
	_max_replay_deltas = max_replay_deltas
	_stream_sequence = int(existing_journal.size())
	_replay_log.clear()
	_peers.clear()
	_active_peer_by_client_id.clear()
	_outbound_by_peer_id.clear()
	_state_hash_by_sequence.clear()
	_state_hash_by_sequence[_stream_sequence] = _compute_state_hash(_stream_sequence)
	_configured = true
	return MatterUtilsScript.success({
		"stream_sequence": _stream_sequence,
		"state_hash": current_state_hash(),
	})


func register_gateway(gateway) -> Dictionary:
	if not _configured or gateway == null or not gateway.has_method("register_handler"):
		return MatterUtilsScript.failure("INVALID_MATTER_AUTHORITY_GATEWAY")
	if not bool(gateway.register_handler(COMMAND_TYPE, Callable(self, "handle_gateway_command"))):
		return MatterUtilsScript.failure("MATTER_AUTHORITY_HANDLER_REGISTRATION_FAILED")
	return MatterUtilsScript.success()


func connect_peer(
	peer_id: String,
	client_id: String,
	session_id: String,
	actor_id: String,
	sync_request: Dictionary
) -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("MATTER_AUTHORITY_NOT_CONFIGURED")
	for value in [peer_id, client_id, session_id, actor_id]:
		if not MatterUtilsScript.is_canonical_id(value, 2):
			return MatterUtilsScript.failure("INVALID_MATTER_AUTHORITY_PEER_ID")
	var sync_validation: Dictionary = SyncRequestScript.validate(sync_request)
	if not bool(sync_validation.get("success", false)):
		return sync_validation
	if String(sync_request["client_id"]) != client_id \
			or String(sync_request["session_id"]) != session_id \
			or int(sync_request["authority_epoch"]) != _authority_epoch:
		return MatterUtilsScript.failure("MATTER_SYNC_BINDING_MISMATCH")
	var normalized_peer_id: String = peer_id.strip_edges().to_lower()
	var normalized_client_id: String = client_id.strip_edges().to_lower()
	var normalized_session_id: String = session_id.strip_edges().to_lower()
	var normalized_actor_id: String = actor_id.strip_edges().to_lower()
	if _active_peer_by_client_id.has(normalized_client_id):
		var old_peer_id: String = String(_active_peer_by_client_id[normalized_client_id])
		if old_peer_id != normalized_peer_id:
			_disconnect_peer_internal(old_peer_id)
	_peers[normalized_peer_id] = {
		"peer_id": normalized_peer_id,
		"client_id": normalized_client_id,
		"session_id": normalized_session_id,
		"actor_id": normalized_actor_id,
		"transport_sequence": 0,
		"acknowledged_stream_sequence": -1,
		"acknowledged_state_hash": "",
		"active": true,
	}
	_active_peer_by_client_id[normalized_client_id] = normalized_peer_id
	_outbound_by_peer_id[normalized_peer_id] = []
	var synchronized: Dictionary = _queue_sync(normalized_peer_id, sync_request)
	if not bool(synchronized.get("success", false)):
		_disconnect_peer_internal(normalized_peer_id)
		return synchronized
	return MatterUtilsScript.success({
		"peer_id": normalized_peer_id,
		"mode": synchronized["details"].get("mode", ""),
		"queued_frames": outbound_count(normalized_peer_id),
	})


func disconnect_peer(peer_id: String) -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("MATTER_AUTHORITY_NOT_CONFIGURED")
	if not _peers.has(peer_id):
		return MatterUtilsScript.success({"replay": true})
	_disconnect_peer_internal(peer_id)
	return MatterUtilsScript.success({"replay": false})


func handle_gateway_command(payload: Dictionary, envelope: Dictionary) -> Dictionary:
	if not _configured:
		return _handler_failure("MATTER_AUTHORITY_NOT_CONFIGURED")
	var envelope_validation: Dictionary = NetworkCommandScript.validate(envelope)
	if not bool(envelope_validation.get("success", false)):
		return _handler_failure(String(envelope_validation.get("error_code", "INVALID_NETWORK_COMMAND")))
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(payload, COMMAND_PAYLOAD_FIELDS)
	if not bool(exact.get("success", false)):
		return _handler_failure("INVALID_MATTER_COMMAND_PAYLOAD")
	for field in ["peer_id", "session_id"]:
		if not MatterUtilsScript.is_canonical_id(payload.get(field), 2):
			return _handler_failure("INVALID_MATTER_COMMAND_BINDING")
	if typeof(payload.get("request_transport")) != TYPE_STRING \
			or String(payload["request_transport"]).is_empty():
		return _handler_failure("INVALID_MATTER_COMMAND_TRANSPORT")
	var peer_id: String = String(payload["peer_id"])
	if not _peers.has(peer_id) or not bool(_peers[peer_id].get("active", false)):
		return _handler_failure("UNKNOWN_MATTER_COMMAND_PEER")
	var peer: Dictionary = _peers[peer_id]
	if String(peer["session_id"]) != String(payload["session_id"]):
		return _handler_failure("STALE_MATTER_COMMAND_SESSION")
	if int(envelope["authority_epoch"]) != _authority_epoch:
		return _handler_failure("STALE_AUTHORITY_EPOCH")
	if String(envelope["entity_id"]) != String(_body["body_id"]) \
			or String(envelope["command_type"]) != COMMAND_TYPE:
		return _handler_failure("MATTER_COMMAND_ROUTE_MISMATCH")
	var request_raw: Dictionary = PersistenceCodecScript.decode_persistence_json(
		String(payload["request_transport"])
	)
	var request: Dictionary = PersistenceCodecScript.rehydrate_request(request_raw)
	if request.is_empty():
		return _handler_failure("INVALID_MATTER_COMMAND_REQUEST")
	if String(request["operation_id"]) != String(envelope["operation_id"]):
		return _handler_failure("MATTER_COMMAND_OPERATION_MISMATCH")
	if String(request["body_id"]) != String(_body["body_id"]):
		return _handler_failure("MATTER_COMMAND_BODY_MISMATCH")
	if String(request["actor_id"]) != String(peer["actor_id"]):
		return _handler_failure("MATTER_COMMAND_ACTOR_NOT_OWNED")
	var journal = _service.mutation_journal()
	var existed_before: bool = journal.has_operation(String(request["operation_id"]))
	var result: Dictionary = _service.execute(request)
	if result.is_empty() or not bool(ResultScript.validate(result).get("success", false)):
		return _handler_failure("MATTER_AUTHORITY_EXECUTION_FAILED")
	var recorded_after: bool = journal.has_operation(String(request["operation_id"]))
	var published_sequence: int = _stream_sequence
	if not existed_before and recorded_after:
		var published: Dictionary = _publish_delta(request, result)
		if not bool(published.get("success", false)):
			return _handler_failure(String(published.get("error_code", "MATTER_REPLICATION_PUBLISH_FAILED")))
		published_sequence = int(published["details"]["stream_sequence"])
	var result_transport: String = PersistenceCodecScript.encode_persistence_json(result)
	if result_transport.is_empty():
		return _handler_failure("MATTER_COMMAND_RESULT_ENCODING_FAILED")
	return {
		"success": true,
		"retryable": false,
		"error_code": "",
		"result_revision": published_sequence,
		"payload": {
			"schema": COMMAND_RESULT_PAYLOAD_SCHEMA,
			"matter_result_transport": result_transport,
			"stream_sequence": _stream_sequence,
			"state_hash": current_state_hash(),
			"replay": existed_before,
			"replication_published": not existed_before and recorded_after,
		},
	}


func acknowledge(peer_id: String, ack: Dictionary) -> Dictionary:
	if not _configured or not _peers.has(peer_id):
		return MatterUtilsScript.failure("UNKNOWN_MATTER_REPLICATION_PEER")
	var validation: Dictionary = AckScript.validate(ack)
	if not bool(validation.get("success", false)):
		return validation
	var peer: Dictionary = _peers[peer_id]
	if String(ack["client_id"]) != String(peer["client_id"]) \
			or String(ack["session_id"]) != String(peer["session_id"]) \
			or int(ack["authority_epoch"]) != _authority_epoch:
		return MatterUtilsScript.failure("MATTER_REPLICATION_ACK_BINDING_MISMATCH")
	var sequence: int = int(ack["acknowledged_stream_sequence"])
	if not _state_hash_by_sequence.has(sequence) \
			or String(_state_hash_by_sequence[sequence]) != String(ack["state_hash"]):
		return MatterUtilsScript.failure("MATTER_REPLICATION_ACK_STATE_MISMATCH")
	if sequence < int(peer.get("acknowledged_stream_sequence", -1)):
		return MatterUtilsScript.failure("STALE_MATTER_REPLICATION_ACK")
	peer["acknowledged_stream_sequence"] = sequence
	peer["acknowledged_state_hash"] = String(ack["state_hash"])
	_peers[peer_id] = peer
	return MatterUtilsScript.success({"acknowledged_stream_sequence": sequence})


func dispatch_peer(peer_id: String, replication_adapter, max_frames: int = 64) -> Dictionary:
	if not _configured or not _peers.has(peer_id):
		return MatterUtilsScript.failure("UNKNOWN_MATTER_REPLICATION_PEER")
	if replication_adapter == null or not replication_adapter.has_method("send") \
			or max_frames < 1 or max_frames > 1024:
		return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_DISPATCH")
	var queue: Array = _outbound_by_peer_id.get(peer_id, [])
	var peer: Dictionary = _peers[peer_id]
	var dispatched: int = 0
	while not queue.is_empty() and dispatched < max_frames:
		var frame: Dictionary = queue[0]
		var transport_sequence: int = int(peer.get("transport_sequence", 0)) + 1
		var envelope: Dictionary = ReplicationEnvelopeScript.create(
			"replication/mw6/%s/%d" % [peer_id.sha256_text(), transport_sequence],
			SOURCE_ID,
			peer_id,
			"SNAPSHOT" if String(frame["frame_kind"]) == "STATE_SNAPSHOT" else "DELTA",
			transport_sequence,
			FrameScript.SCHEMA,
			frame
		)
		var sent: Dictionary = replication_adapter.send(envelope)
		if not bool(sent.get("success", false)):
			_outbound_by_peer_id[peer_id] = queue
			_peers[peer_id] = peer
			return MatterUtilsScript.failure(String(sent.get("error_code", "MATTER_REPLICATION_SEND_FAILED")), {
				"dispatched": dispatched,
				"remaining": queue.size(),
			})
		queue.pop_front()
		peer["transport_sequence"] = transport_sequence
		dispatched += 1
	_outbound_by_peer_id[peer_id] = queue
	_peers[peer_id] = peer
	return MatterUtilsScript.success({
		"dispatched": dispatched,
		"remaining": queue.size(),
	})


func create_state_snapshot() -> Dictionary:
	if not _configured:
		return {}
	var store_state: Dictionary = _service.snapshot_store().export_persistence_state()
	var journal_state: Dictionary = _service.mutation_journal().export_persistence_state()
	var store_transport: String = PersistenceCodecScript.encode_persistence_json(store_state)
	var journal_transport: String = PersistenceCodecScript.encode_persistence_json(journal_state)
	if store_transport.is_empty() or journal_transport.is_empty():
		return {}
	var value: Dictionary = SnapshotScript.create({
		"body_id": _body["body_id"],
		"body_definition_hash": _body["checksum"],
		"grid_profile_hash": GridProfileScript.content_hash(_grid_profile),
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"stream_sequence": _stream_sequence,
		"store_state_transport": store_transport,
		"journal_state_transport": journal_transport,
		"persistent_snapshot_count": store_state["snapshots"].size(),
		"operation_count": journal_state["records"].size(),
		"state_hash": current_state_hash(),
	})
	return value if bool(SnapshotScript.validate(value).get("success", false)) else {}


func current_state_hash() -> String:
	if not _configured:
		return ""
	return String(_state_hash_by_sequence.get(_stream_sequence, _compute_state_hash(_stream_sequence)))


func stream_sequence() -> int:
	return _stream_sequence


func replay_log_size() -> int:
	return _replay_log.size()


func outbound_count(peer_id: String) -> int:
	return Array(_outbound_by_peer_id.get(peer_id, [])).size()


func peer_snapshot(peer_id: String) -> Dictionary:
	return Dictionary(_peers.get(peer_id, {})).duplicate(true)


func _publish_delta(request: Dictionary, result: Dictionary) -> Dictionary:
	var previous_sequence: int = _stream_sequence
	var base_state_hash: String = current_state_hash()
	var snapshot_transports: Array = []
	for changed_value in result["changed_bricks"]:
		var changed: Dictionary = changed_value
		var snapshot: Dictionary = _service.snapshot_store().get_snapshot(changed["address"])
		if snapshot.is_empty() or int(snapshot["state_revision"]) < 1:
			return MatterUtilsScript.failure("MATTER_REPLICATION_SOURCE_SNAPSHOT_MISSING")
		var snapshot_transport: String = PersistenceCodecScript.encode_persistence_json(snapshot)
		if snapshot_transport.is_empty():
			return MatterUtilsScript.failure("MATTER_REPLICATION_SOURCE_SNAPSHOT_ENCODING_FAILED")
		snapshot_transports.append(snapshot_transport)
	var candidate_sequence: int = previous_sequence + 1
	var target_state_hash: String = _compute_state_hash(candidate_sequence)
	var delta: Dictionary = DeltaScript.create({
		"body_id": _body["body_id"],
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"previous_stream_sequence": previous_sequence,
		"stream_sequence": candidate_sequence,
		"operation_id": request["operation_id"],
		"request_transport": PersistenceCodecScript.encode_persistence_json(request),
		"result_transport": PersistenceCodecScript.encode_persistence_json(result),
		"snapshot_transports": snapshot_transports,
		"base_state_hash": base_state_hash,
		"target_state_hash": target_state_hash,
	})
	var validation: Dictionary = DeltaScript.validate(delta)
	if not bool(validation.get("success", false)):
		return MatterUtilsScript.failure("MATTER_REPLICATION_DELTA_BUILD_FAILED", {"cause": validation})
	_stream_sequence = candidate_sequence
	_replay_log.append(delta)
	while _replay_log.size() > _max_replay_deltas:
		_replay_log.pop_front()
	_state_hash_by_sequence[_stream_sequence] = target_state_hash
	_trim_state_hash_history()
	for peer_id in _peers.keys():
		if bool(_peers[peer_id].get("active", false)):
			_queue_delta_frame(String(peer_id), delta)
	return MatterUtilsScript.success({
		"stream_sequence": _stream_sequence,
		"delta": delta,
	})


func _queue_sync(peer_id: String, sync_request: Dictionary) -> Dictionary:
	var known_sequence: int = int(sync_request["known_stream_sequence"])
	var known_hash: String = String(sync_request["known_state_hash"])
	if known_sequence == _stream_sequence and known_hash == current_state_hash():
		return MatterUtilsScript.success({"mode": "CURRENT"})
	var replay_deltas: Array[Dictionary] = _replay_from(known_sequence, known_hash)
	if not replay_deltas.is_empty():
		for delta in replay_deltas:
			_queue_delta_frame(peer_id, delta)
		return MatterUtilsScript.success({
			"mode": "DELTA_REPLAY",
			"delta_count": replay_deltas.size(),
		})
	var snapshot: Dictionary = create_state_snapshot()
	if snapshot.is_empty():
		return MatterUtilsScript.failure("MATTER_REPLICATION_SNAPSHOT_BUILD_FAILED")
	_queue_snapshot_frame(peer_id, snapshot)
	return MatterUtilsScript.success({"mode": "FULL_SNAPSHOT"})


func _replay_from(known_sequence: int, known_hash: String) -> Array[Dictionary]:
	if known_sequence < 0 or known_sequence >= _stream_sequence:
		return []
	var expected_sequence: int = known_sequence + 1
	var selected: Array[Dictionary] = []
	for delta in _replay_log:
		var sequence: int = int(delta["stream_sequence"])
		if sequence < expected_sequence:
			continue
		if sequence != expected_sequence:
			return []
		if selected.is_empty() and String(delta["base_state_hash"]) != known_hash:
			return []
		selected.append(delta)
		expected_sequence += 1
	if expected_sequence != _stream_sequence + 1:
		return []
	return selected


func _queue_delta_frame(peer_id: String, delta: Dictionary) -> void:
	_queue_frame(peer_id, "MUTATION_DELTA", DeltaScript.SCHEMA, delta)


func _queue_snapshot_frame(peer_id: String, snapshot: Dictionary) -> void:
	_queue_frame(peer_id, "STATE_SNAPSHOT", SnapshotScript.SCHEMA, snapshot)


func _queue_frame(peer_id: String, frame_kind: String, payload_schema: String, payload: Dictionary) -> void:
	if not _peers.has(peer_id):
		return
	var payload_transport: String = PersistenceCodecScript.encode_persistence_json(payload)
	if payload_transport.is_empty():
		return
	_frame_serial += 1
	var peer: Dictionary = _peers[peer_id]
	var frame: Dictionary = FrameScript.create({
		"frame_id": "frame/mw6/%s/%d" % [peer_id.sha256_text(), _frame_serial],
		"frame_kind": frame_kind,
		"body_id": _body["body_id"],
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"session_id": peer["session_id"],
		"stream_sequence": payload["stream_sequence"],
		"payload_schema": payload_schema,
		"payload_transport": payload_transport,
	})
	if not bool(FrameScript.validate(frame).get("success", false)):
		return
	var queue: Array = _outbound_by_peer_id.get(peer_id, [])
	queue.append(frame)
	_outbound_by_peer_id[peer_id] = queue


func _compute_state_hash(sequence: int) -> String:
	return MatterUtilsScript.payload_hash({
		"body_id": _body.get("body_id", ""),
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"stream_sequence": sequence,
		"store_hash": _service.snapshot_store().content_hash(),
		"journal_hash": _service.mutation_journal().content_hash(),
	})


func _trim_state_hash_history() -> void:
	var minimum_sequence: int = maxi(0, _stream_sequence - maxi(1, _max_replay_deltas) - 1)
	for raw_sequence in _state_hash_by_sequence.keys():
		if int(raw_sequence) < minimum_sequence:
			_state_hash_by_sequence.erase(raw_sequence)


func _disconnect_peer_internal(peer_id: String) -> void:
	if not _peers.has(peer_id):
		return
	var peer: Dictionary = _peers[peer_id]
	peer["active"] = false
	_peers[peer_id] = peer
	_outbound_by_peer_id.erase(peer_id)
	var client_id: String = String(peer.get("client_id", ""))
	if String(_active_peer_by_client_id.get(client_id, "")) == peer_id:
		_active_peer_by_client_id.erase(client_id)


func _handler_failure(error_code: String) -> Dictionary:
	return {
		"success": false,
		"retryable": false,
		"error_code": error_code,
		"result_revision": _stream_sequence if _configured else -1,
		"payload": {},
	}
