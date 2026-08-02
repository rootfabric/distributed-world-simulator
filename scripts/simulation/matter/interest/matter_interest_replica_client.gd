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
const RegionScript = preload("res://scripts/simulation/matter/interest/matter_interest_region.gd")
const SubscriptionScript = preload("res://scripts/simulation/matter/interest/matter_interest_subscription.gd")
const SyncRequestScript = preload("res://scripts/simulation/matter/interest/matter_interest_sync_request.gd")
const AckScript = preload("res://scripts/simulation/matter/interest/matter_interest_ack.gd")
const DeltaScript = preload("res://scripts/simulation/matter/interest/matter_interest_delta.gd")
const SnapshotScript = preload("res://scripts/simulation/matter/interest/matter_interest_snapshot.gd")
const FrameScript = preload("res://scripts/simulation/matter/interest/matter_interest_frame.gd")

const COMMAND_TYPE: String = "MATTER_MUTATION"
const COMMAND_RESULT_PAYLOAD_SCHEMA: String = "planet_simulator.matter_authority_command_result.v1"

var _configured: bool = false
var _body: Dictionary = {}
var _grid_profile: Dictionary = {}
var _grid_profile_hash: String = ""
var _authority_owner_id: String = ""
var _authority_epoch: int = 0
var _client_id: String = ""
var _peer_id: String = ""
var _session_id: String = ""
var _subscription: Dictionary = {}
var _pending_subscription: Dictionary = {}
var _region_sequence: int = 0
var _source_global_stream_sequence: int = 0
var _store = null
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
		return MatterUtilsScript.failure("MATTER_INTEREST_REPLICA_ALREADY_CONFIGURED")
	if not bool(BodyScript.validate(body).get("success", false)) \
			or not bool(GridProfileScript.validate(grid_profile).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_REPLICA_WORLD")
	if String(body["body_id"]) != String(grid_profile["body_id"]) \
			or String(body["body_frame_id"]) != String(grid_profile["body_frame_id"]):
		return MatterUtilsScript.failure("MATTER_INTEREST_REPLICA_BODY_GRID_MISMATCH")
	if not MatterUtilsScript.is_canonical_id(authority_owner_id, 2) \
			or authority_epoch < 1 or not MatterUtilsScript.is_canonical_id(client_id, 2):
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_REPLICA_CONFIGURATION")
	if presenter != null and not presenter.has_method("invalidate_brick_addresses"):
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_REPLICA_PRESENTER")
	_store = SnapshotStoreScript.new()
	var store_setup: Dictionary = _store.configure(body, grid_profile)
	if not bool(store_setup.get("success", false)):
		return store_setup
	_body = body.duplicate(true)
	_grid_profile = grid_profile.duplicate(true)
	_grid_profile_hash = GridProfileScript.content_hash(grid_profile)
	_authority_owner_id = authority_owner_id.strip_edges().to_lower()
	_authority_epoch = authority_epoch
	_client_id = client_id.strip_edges().to_lower()
	_presenter = presenter
	_configured = true
	return MatterUtilsScript.success()


func activate_session(peer_id: String, session_id: String) -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("MATTER_INTEREST_REPLICA_NOT_CONFIGURED")
	if not MatterUtilsScript.is_canonical_id(peer_id, 2) \
			or not MatterUtilsScript.is_canonical_id(session_id, 2):
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_REPLICA_SESSION")
	_peer_id = peer_id.strip_edges().to_lower()
	_session_id = session_id.strip_edges().to_lower()
	return MatterUtilsScript.success({"peer_id": _peer_id, "session_id": _session_id})


func set_interest(
	subscription_id: String,
	interest_revision: int,
	center_cell_address: Dictionary,
	radius_cells: int
) -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("MATTER_INTEREST_REPLICA_NOT_CONFIGURED")
	var subscription: Dictionary = SubscriptionScript.create(
		subscription_id,
		_client_id,
		_authority_epoch,
		interest_revision,
		int(center_cell_address.get("level", -1)),
		center_cell_address,
		radius_cells
	)
	var validation: Dictionary = RegionScript.validate_subscription(_grid_profile, subscription)
	if not bool(validation.get("success", false)):
		return validation
	var comparison: Dictionary = _pending_subscription if not _pending_subscription.is_empty() else _subscription
	if not comparison.is_empty():
		var previous_revision: int = int(comparison["interest_revision"])
		if interest_revision < previous_revision:
			return MatterUtilsScript.failure("STALE_MATTER_INTEREST_REVISION")
		if interest_revision == previous_revision \
				and String(subscription["checksum"]) != String(comparison["checksum"]):
			return MatterUtilsScript.failure("SAME_REVISION_MATTER_INTEREST_CONFLICT")
		if String(subscription["checksum"]) == String(comparison["checksum"]):
			return MatterUtilsScript.success({"replay": true})
	if _subscription.is_empty():
		_subscription = subscription
		_pending_subscription.clear()
		_region_sequence = 0
		_source_global_stream_sequence = 0
		_requires_resync = false
		return MatterUtilsScript.success({
			"replay": false,
			"pending": false,
			"projection_hash": projection_hash(),
		})
	_pending_subscription = subscription
	_requires_resync = false
	return MatterUtilsScript.success({
		"replay": false,
		"pending": true,
		"projection_hash": _pending_empty_projection_hash(),
	})


func create_sync_request() -> Dictionary:
	if not _configured or _session_id.is_empty() \
			or (_subscription.is_empty() and _pending_subscription.is_empty()):
		return {}
	var requested_subscription: Dictionary = _pending_subscription \
		if not _pending_subscription.is_empty() else _subscription
	var known_sequence: int = 0 if not _pending_subscription.is_empty() else _region_sequence
	var known_hash: String = _pending_empty_projection_hash() \
		if not _pending_subscription.is_empty() else projection_hash()
	return SyncRequestScript.create(
		_client_id,
		_session_id,
		_authority_epoch,
		requested_subscription,
		known_sequence,
		known_hash
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
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_COMMAND_RESULT_ENVELOPE")
	if int(result_envelope["authority_epoch"]) != _authority_epoch:
		return MatterUtilsScript.failure("STALE_MATTER_INTEREST_COMMAND_RESULT_EPOCH")
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
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_COMMAND_RESULT_PAYLOAD")
	var result_raw: Dictionary = PersistenceCodecScript.decode_persistence_json(
		String(payload["matter_result_transport"])
	)
	var result: Dictionary = PersistenceCodecScript.rehydrate_result(result_raw)
	if result.is_empty() or String(result["operation_id"]) != String(result_envelope["operation_id"]):
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_COMMAND_DOMAIN_RESULT")
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
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_REPLICA_POLL")
	var polled: Dictionary = replication_adapter.poll(_peer_id, max_count)
	if not bool(polled.get("success", false)):
		return MatterUtilsScript.failure(String(polled.get("error_code", "MATTER_INTEREST_POLL_FAILED")))
	var applied: int = 0
	for message_value in polled.get("details", {}).get("messages", []):
		if typeof(message_value) != TYPE_DICTIONARY:
			return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_REPLICATION_MESSAGE")
		var message: Dictionary = message_value
		var envelope_validation: Dictionary = ReplicationEnvelopeScript.validate(message)
		if not bool(envelope_validation.get("success", false)):
			return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_REPLICATION_ENVELOPE")
		if String(message["target_peer_id"]) != _peer_id \
				or String(message["payload_schema"]) != FrameScript.SCHEMA \
				or String(message["replication_kind"]) != "INTEREST":
			return MatterUtilsScript.failure("MATTER_INTEREST_ENVELOPE_ROUTE_MISMATCH")
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
		return MatterUtilsScript.failure("MATTER_INTEREST_FRAME_AUTHORITY_MISMATCH")
	if String(frame["session_id"]) != _session_id:
		return MatterUtilsScript.failure("STALE_MATTER_INTEREST_FRAME_SESSION")
	var frame_matches_active: bool = not _subscription.is_empty() \
		and String(frame["subscription_id"]) == String(_subscription["subscription_id"]) \
		and int(frame["interest_revision"]) == int(_subscription["interest_revision"])
	var frame_matches_pending: bool = not _pending_subscription.is_empty() \
		and String(frame["subscription_id"]) == String(_pending_subscription["subscription_id"]) \
		and int(frame["interest_revision"]) == int(_pending_subscription["interest_revision"])
	if not frame_matches_active and not frame_matches_pending:
		if not _subscription.is_empty() \
				and String(frame["subscription_id"]) == String(_subscription["subscription_id"]) \
				and int(frame["interest_revision"]) < int(_subscription["interest_revision"]):
			_duplicate_frame_count += 1
			return MatterUtilsScript.success({"stale_subscription_frame": true})
		return MatterUtilsScript.failure("STALE_MATTER_INTEREST_FRAME_SUBSCRIPTION")
	var payload: Dictionary = FrameScript.decode_payload(frame)
	if payload.is_empty():
		return MatterUtilsScript.failure("MATTER_INTEREST_FRAME_DECODE_FAILED")
	if String(frame["frame_kind"]) == "REGION_SNAPSHOT":
		return _apply_snapshot(payload)
	return _apply_delta(payload)


func create_ack() -> Dictionary:
	if not _configured or _session_id.is_empty() or _subscription.is_empty() \
			or not _pending_subscription.is_empty():
		return {}
	return AckScript.create(
		_client_id,
		_session_id,
		_authority_epoch,
		String(_subscription["subscription_id"]),
		int(_subscription["interest_revision"]),
		_region_sequence,
		projection_hash()
	)


func projection_hash() -> String:
	if not _configured or _subscription.is_empty():
		return ""
	return RegionScript.projection_hash(
		String(_body["body_id"]),
		_authority_owner_id,
		_authority_epoch,
		_subscription,
		_region_sequence,
		_source_global_stream_sequence,
		_store.content_hash()
	)


func region_sequence() -> int:
	return _region_sequence


func source_global_stream_sequence() -> int:
	return _source_global_stream_sequence


func snapshot_store():
	return _store


func subscription() -> Dictionary:
	return _subscription.duplicate(true)


func pending_subscription() -> Dictionary:
	return _pending_subscription.duplicate(true)


func requires_resync() -> bool:
	return _requires_resync


func command_result(operation_id: String) -> Dictionary:
	return Dictionary(_command_results.get(operation_id, {})).duplicate(true)


func report() -> Dictionary:
	return {
		"schema": "planet_simulator.matter_interest_replica_report.v1",
		"client_id": _client_id,
		"peer_id": _peer_id,
		"session_id": _session_id,
		"subscription_id": String(_subscription.get("subscription_id", "")),
		"interest_revision": int(_subscription.get("interest_revision", 0)),
		"pending_interest_revision": int(_pending_subscription.get("interest_revision", 0)),
		"region_sequence": _region_sequence,
		"source_global_stream_sequence": _source_global_stream_sequence,
		"projection_hash": projection_hash(),
		"requires_resync": _requires_resync,
		"applied_deltas": _applied_delta_count,
		"applied_snapshots": _applied_snapshot_count,
		"duplicate_frames": _duplicate_frame_count,
		"persistent_snapshots": _store.size(),
	}


func _pending_empty_projection_hash() -> String:
	if _pending_subscription.is_empty():
		return projection_hash()
	var empty_store_hash: String = RegionScript.projection_store_hash(
		String(_body["checksum"]), _grid_profile_hash, {}
	)
	return RegionScript.projection_hash(
		String(_body["body_id"]),
		_authority_owner_id,
		_authority_epoch,
		_pending_subscription,
		0,
		0,
		empty_store_hash
	)


func _apply_delta(delta: Dictionary) -> Dictionary:
	var validation: Dictionary = DeltaScript.validate(delta)
	if not bool(validation.get("success", false)):
		return validation
	if not _pending_subscription.is_empty() \
			and String(delta["subscription_id"]) == String(_pending_subscription["subscription_id"]) \
			and int(delta["interest_revision"]) == int(_pending_subscription["interest_revision"]):
		return MatterUtilsScript.failure("MATTER_INTEREST_DELTA_BEFORE_SNAPSHOT")
	if String(delta["subscription_id"]) != String(_subscription["subscription_id"]) \
			or int(delta["interest_revision"]) != int(_subscription["interest_revision"]):
		return MatterUtilsScript.failure("MATTER_INTEREST_DELTA_SUBSCRIPTION_MISMATCH")
	var sequence: int = int(delta["region_sequence"])
	if sequence == _region_sequence:
		if String(delta["target_projection_hash"]) == projection_hash():
			_duplicate_frame_count += 1
			return MatterUtilsScript.success({"replay": true})
		_requires_resync = true
		return MatterUtilsScript.failure("SAME_SEQUENCE_MATTER_INTEREST_CONFLICT")
	if sequence <= _region_sequence:
		return MatterUtilsScript.failure("STALE_MATTER_INTEREST_DELTA")
	if int(delta["previous_region_sequence"]) != _region_sequence \
			or sequence != _region_sequence + 1:
		_requires_resync = true
		return MatterUtilsScript.failure("MATTER_INTEREST_SEQUENCE_GAP")
	if int(delta["source_global_stream_sequence"]) <= _source_global_stream_sequence:
		_requires_resync = true
		return MatterUtilsScript.failure("STALE_MATTER_INTEREST_GLOBAL_SEQUENCE")
	if String(delta["base_projection_hash"]) != projection_hash():
		_requires_resync = true
		return MatterUtilsScript.failure("MATTER_INTEREST_BASE_PROJECTION_MISMATCH")
	var store_backup: Dictionary = _store.export_persistence_state()
	var snapshots: Array = []
	var expected_by_address: Dictionary = {}
	var changed_address_ids: Array = []
	for transport_value in delta["snapshot_transports"]:
		var raw_snapshot: Dictionary = PersistenceCodecScript.decode_persistence_json(String(transport_value))
		var snapshot: Dictionary = PersistenceCodecScript.rehydrate_snapshot(raw_snapshot)
		if snapshot.is_empty() or not RegionScript.contains_snapshot(_grid_profile, _subscription, snapshot):
			return MatterUtilsScript.failure("MATTER_INTEREST_DELTA_BRICK_OUTSIDE_REGION")
		var address_id: String = String(snapshot["address"]["address_id"])
		expected_by_address[address_id] = _store.revision_for_address_id(address_id)
		snapshots.append(snapshot)
		changed_address_ids.append(address_id)
	var commit: Dictionary = _store.put_many_atomic(snapshots, expected_by_address)
	if not bool(commit.get("success", false)):
		_requires_resync = true
		return MatterUtilsScript.failure("MATTER_INTEREST_STORE_COMMIT_FAILED", {"cause": commit})
	var old_region_sequence: int = _region_sequence
	var old_global_sequence: int = _source_global_stream_sequence
	_region_sequence = sequence
	_source_global_stream_sequence = int(delta["source_global_stream_sequence"])
	if projection_hash() != String(delta["target_projection_hash"]):
		_store.restore_persistence_state(store_backup)
		_region_sequence = old_region_sequence
		_source_global_stream_sequence = old_global_sequence
		_requires_resync = true
		return MatterUtilsScript.failure("MATTER_INTEREST_TARGET_PROJECTION_MISMATCH")
	_requires_resync = false
	_applied_delta_count += 1
	if _presenter != null:
		changed_address_ids.sort()
		_presenter.invalidate_brick_addresses(changed_address_ids)
	return MatterUtilsScript.success({
		"region_sequence": _region_sequence,
		"changed_address_ids": changed_address_ids,
	})


func _apply_snapshot(snapshot: Dictionary) -> Dictionary:
	var validation: Dictionary = SnapshotScript.validate(snapshot)
	if not bool(validation.get("success", false)):
		return validation
	var snapshot_subscription: Dictionary = SnapshotScript.decode_subscription(snapshot)
	var matches_pending: bool = not _pending_subscription.is_empty() \
		and String(snapshot_subscription.get("checksum", "")) == String(_pending_subscription.get("checksum", ""))
	var matches_active: bool = not _subscription.is_empty() \
		and String(snapshot_subscription.get("checksum", "")) == String(_subscription.get("checksum", ""))
	if not matches_pending and not matches_active:
		return MatterUtilsScript.failure("MATTER_INTEREST_SNAPSHOT_SUBSCRIPTION_MISMATCH")
	if String(snapshot["body_definition_hash"]) != String(_body["checksum"]) \
			or String(snapshot["grid_profile_hash"]) != _grid_profile_hash:
		return MatterUtilsScript.failure("MATTER_INTEREST_SNAPSHOT_WORLD_MISMATCH")
	var sequence: int = int(snapshot["region_sequence"])
	var replacing_interest: bool = matches_pending
	if not replacing_interest and sequence < _region_sequence:
		return MatterUtilsScript.failure("STALE_MATTER_INTEREST_SNAPSHOT")
	if not replacing_interest and sequence == _region_sequence \
			and String(snapshot["projection_hash"]) == projection_hash():
		_duplicate_frame_count += 1
		return MatterUtilsScript.success({"replay": true})
	var temporary_store = SnapshotStoreScript.new()
	var setup: Dictionary = temporary_store.configure(_body, _grid_profile)
	if not bool(setup.get("success", false)):
		return setup
	for transport_value in snapshot["snapshot_transports"]:
		var raw_snapshot: Dictionary = PersistenceCodecScript.decode_persistence_json(String(transport_value))
		var typed_snapshot: Dictionary = PersistenceCodecScript.rehydrate_snapshot(raw_snapshot)
		if typed_snapshot.is_empty() \
				or not RegionScript.contains_snapshot(_grid_profile, snapshot_subscription, typed_snapshot):
			return MatterUtilsScript.failure("MATTER_INTEREST_SNAPSHOT_BRICK_OUTSIDE_REGION")
		var stored: Dictionary = temporary_store.put(typed_snapshot)
		if not bool(stored.get("success", false)):
			return MatterUtilsScript.failure("MATTER_INTEREST_SNAPSHOT_TEMP_STORE_FAILED", {"cause": stored})
	var old_address_ids: Array = _store.address_ids()
	var old_region_sequence: int = _region_sequence
	var old_global_sequence: int = _source_global_stream_sequence
	var old_store_state: Dictionary = _store.export_persistence_state()
	var temporary_state: Dictionary = temporary_store.export_persistence_state()
	var restored: Dictionary = _store.restore_persistence_state(temporary_state)
	if not bool(restored.get("success", false)):
		return MatterUtilsScript.failure("MATTER_INTEREST_SNAPSHOT_STORE_RESTORE_FAILED", {"cause": restored})
	var candidate_region_sequence: int = sequence
	var candidate_global_sequence: int = int(snapshot["source_global_stream_sequence"])
	var candidate_hash: String = RegionScript.projection_hash(
		String(_body["body_id"]),
		_authority_owner_id,
		_authority_epoch,
		snapshot_subscription,
		candidate_region_sequence,
		candidate_global_sequence,
		_store.content_hash()
	)
	if candidate_hash != String(snapshot["projection_hash"]):
		_store.restore_persistence_state(old_store_state)
		_region_sequence = old_region_sequence
		_source_global_stream_sequence = old_global_sequence
		_requires_resync = true
		return MatterUtilsScript.failure("MATTER_INTEREST_SNAPSHOT_PROJECTION_MISMATCH")
	_subscription = snapshot_subscription
	if replacing_interest:
		_pending_subscription.clear()
	_region_sequence = candidate_region_sequence
	_source_global_stream_sequence = candidate_global_sequence
	_requires_resync = false
	_applied_snapshot_count += 1
	if _presenter != null:
		var invalidated: Array = MatterUtilsScript.sorted_unique_ids(old_address_ids + _store.address_ids())
		if not invalidated.is_empty():
			_presenter.invalidate_brick_addresses(invalidated)
	return MatterUtilsScript.success({
		"region_sequence": _region_sequence,
		"persistent_snapshot_count": _store.size(),
	})
