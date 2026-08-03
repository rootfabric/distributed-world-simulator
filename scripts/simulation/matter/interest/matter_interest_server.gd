extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const ReplicationEnvelopeScript = preload("res://scripts/network/bus/replication_envelope.gd")
const BodyScript = preload("res://scripts/simulation/matter/contracts/matter_body_definition.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const GlobalDeltaScript = preload("res://scripts/simulation/matter/network/matter_replication_delta.gd")
const RegionScript = preload("res://scripts/simulation/matter/interest/matter_interest_region.gd")
const SyncRequestScript = preload("res://scripts/simulation/matter/interest/matter_interest_sync_request.gd")
const AckScript = preload("res://scripts/simulation/matter/interest/matter_interest_ack.gd")
const DeltaScript = preload("res://scripts/simulation/matter/interest/matter_interest_delta.gd")
const SnapshotScript = preload("res://scripts/simulation/matter/interest/matter_interest_snapshot.gd")
const FrameScript = preload("res://scripts/simulation/matter/interest/matter_interest_frame.gd")

const SOURCE_ID: String = "source/mw7-matter-interest"

var _configured: bool = false
var _body: Dictionary = {}
var _grid_profile: Dictionary = {}
var _grid_profile_hash: String = ""
var _service = null
var _authority = null
var _authority_owner_id: String = ""
var _authority_epoch: int = 0
var _max_replay_deltas: int = 64
var _states_by_client_id: Dictionary = {}
var _peer_by_id: Dictionary = {}
var _active_peer_by_client_id: Dictionary = {}
var _outbound_by_peer_id: Dictionary = {}
var _frame_serial: int = 0


func configure(
	body: Dictionary,
	grid_profile: Dictionary,
	excavation_service,
	authority,
	authority_owner_id: String,
	authority_epoch: int,
	max_replay_deltas: int = 64
) -> Dictionary:
	if _configured:
		return MatterUtilsScript.failure("MATTER_INTEREST_SERVER_ALREADY_CONFIGURED")
	if not bool(BodyScript.validate(body).get("success", false)) \
			or not bool(GridProfileScript.validate(grid_profile).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_SERVER_WORLD")
	if String(body["body_id"]) != String(grid_profile["body_id"]) \
			or String(body["body_frame_id"]) != String(grid_profile["body_frame_id"]):
		return MatterUtilsScript.failure("MATTER_INTEREST_SERVER_BODY_GRID_MISMATCH")
	if excavation_service == null or not excavation_service.has_method("snapshot_store"):
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_SERVER_SERVICE")
	if authority == null or not authority.has_method("register_replication_observer") \
			or not authority.has_method("stream_sequence") \
			or not authority.has_method("peer_snapshot"):
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_AUTHORITY")
	if not MatterUtilsScript.is_canonical_id(authority_owner_id, 2) \
			or authority_epoch < 1 or max_replay_deltas < 0 or max_replay_deltas > 4096:
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_SERVER_CONFIGURATION")
	_body = body.duplicate(true)
	_grid_profile = grid_profile.duplicate(true)
	_grid_profile_hash = GridProfileScript.content_hash(grid_profile)
	_service = excavation_service
	_authority = authority
	_authority_owner_id = authority_owner_id.strip_edges().to_lower()
	_authority_epoch = authority_epoch
	_max_replay_deltas = max_replay_deltas
	_states_by_client_id.clear()
	_peer_by_id.clear()
	_active_peer_by_client_id.clear()
	_outbound_by_peer_id.clear()
	var registered: Dictionary = authority.register_replication_observer(self)
	if not bool(registered.get("success", false)):
		return registered
	_configured = true
	return MatterUtilsScript.success({
		"source_global_stream_sequence": int(authority.stream_sequence()),
	})


func shutdown() -> Dictionary:
	if not _configured:
		return MatterUtilsScript.success({"replay": true})
	var observer_result: Dictionary = MatterUtilsScript.success({"replay": true})
	if _authority != null and _authority.has_method("unregister_replication_observer"):
		observer_result = _authority.unregister_replication_observer(self)
	_states_by_client_id.clear()
	_peer_by_id.clear()
	_active_peer_by_client_id.clear()
	_outbound_by_peer_id.clear()
	_authority = null
	_service = null
	_body.clear()
	_grid_profile.clear()
	_grid_profile_hash = ""
	_configured = false
	if not bool(observer_result.get("success", false)):
		return observer_result
	return MatterUtilsScript.success({"replay": false})


func connect_peer(peer_id: String, sync_request: Dictionary) -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("MATTER_INTEREST_SERVER_NOT_CONFIGURED")
	if not MatterUtilsScript.is_canonical_id(peer_id, 2):
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_PEER_ID")
	var sync_validation: Dictionary = SyncRequestScript.validate(sync_request)
	if not bool(sync_validation.get("success", false)):
		return sync_validation
	if int(sync_request["authority_epoch"]) != _authority_epoch:
		return MatterUtilsScript.failure("STALE_MATTER_INTEREST_AUTHORITY_EPOCH")
	var subscription: Dictionary = SyncRequestScript.decode_subscription(sync_request)
	var region_validation: Dictionary = RegionScript.validate_subscription(_grid_profile, subscription)
	if not bool(region_validation.get("success", false)):
		return region_validation
	var client_id: String = String(sync_request["client_id"])
	var session_id: String = String(sync_request["session_id"])
	var normalized_peer_id: String = peer_id.strip_edges().to_lower()
	var authority_peer: Dictionary = _authority.peer_snapshot(normalized_peer_id)
	if authority_peer.is_empty() or not bool(authority_peer.get("active", false)) \
			or String(authority_peer.get("client_id", "")) != client_id \
			or String(authority_peer.get("session_id", "")) != session_id \
			or String(authority_peer.get("replication_mode", "")) != "INTEREST":
		return MatterUtilsScript.failure("MATTER_INTEREST_AUTHORITY_PEER_BINDING_MISMATCH")
	var state_result: Dictionary = _resolve_subscription_state(client_id, subscription)
	if not bool(state_result.get("success", false)):
		return state_result
	if _active_peer_by_client_id.has(client_id):
		var old_peer_id: String = String(_active_peer_by_client_id[client_id])
		if old_peer_id != normalized_peer_id:
			_disconnect_peer_internal(old_peer_id)
	var previous_transport_sequence: int = 0
	if _peer_by_id.has(normalized_peer_id):
		previous_transport_sequence = int(_peer_by_id[normalized_peer_id].get("transport_sequence", 0))
	_peer_by_id[normalized_peer_id] = {
		"peer_id": normalized_peer_id,
		"client_id": client_id,
		"session_id": session_id,
		"transport_sequence": previous_transport_sequence,
		"active": true,
	}
	_active_peer_by_client_id[client_id] = normalized_peer_id
	_outbound_by_peer_id[normalized_peer_id] = []
	var synchronized: Dictionary = _queue_sync(normalized_peer_id, sync_request)
	if not bool(synchronized.get("success", false)):
		_disconnect_peer_internal(normalized_peer_id)
		return synchronized
	return MatterUtilsScript.success({
		"peer_id": normalized_peer_id,
		"mode": synchronized.get("details", {}).get("mode", ""),
		"interest_revision": int(subscription["interest_revision"]),
		"queued_frames": outbound_count(normalized_peer_id),
	})


func update_interest(peer_id: String, sync_request: Dictionary) -> Dictionary:
	if not _peer_by_id.has(peer_id) or not bool(_peer_by_id[peer_id].get("active", false)):
		return MatterUtilsScript.failure("UNKNOWN_MATTER_INTEREST_PEER")
	var peer: Dictionary = _peer_by_id[peer_id]
	if String(sync_request.get("client_id", "")) != String(peer["client_id"]) \
			or String(sync_request.get("session_id", "")) != String(peer["session_id"]):
		return MatterUtilsScript.failure("MATTER_INTEREST_UPDATE_BINDING_MISMATCH")
	return connect_peer(peer_id, sync_request)


func disconnect_peer(peer_id: String) -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("MATTER_INTEREST_SERVER_NOT_CONFIGURED")
	if not _peer_by_id.has(peer_id):
		return MatterUtilsScript.success({"replay": true})
	_disconnect_peer_internal(peer_id)
	return MatterUtilsScript.success({"replay": false})


func on_authoritative_matter_delta(global_delta: Dictionary) -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("MATTER_INTEREST_SERVER_NOT_CONFIGURED")
	var validation: Dictionary = GlobalDeltaScript.validate(global_delta)
	if not bool(validation.get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_SOURCE_DELTA", {"cause": validation})
	if global_delta["snapshot_transports"].is_empty():
		return MatterUtilsScript.success({"published_regions": 0})
	var decoded_snapshots: Array[Dictionary] = []
	for transport_value in global_delta["snapshot_transports"]:
		var raw_snapshot: Dictionary = PersistenceCodecScript.decode_persistence_json(String(transport_value))
		var snapshot: Dictionary = PersistenceCodecScript.rehydrate_snapshot(raw_snapshot)
		if snapshot.is_empty():
			return MatterUtilsScript.failure("MATTER_INTEREST_SOURCE_BRICK_DECODE_FAILED")
		decoded_snapshots.append(snapshot)
	var published_regions: int = 0
	var client_ids: Array = _states_by_client_id.keys()
	client_ids.sort()
	for raw_client_id in client_ids:
		var client_id: String = String(raw_client_id)
		var state: Dictionary = Dictionary(_states_by_client_id[client_id]).duplicate(true)
		var subscription: Dictionary = state["subscription"]
		var relevant: Array[Dictionary] = []
		for snapshot in decoded_snapshots:
			if RegionScript.contains_snapshot(_grid_profile, subscription, snapshot):
				relevant.append(snapshot)
		if relevant.is_empty():
			continue
		relevant.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["address"]["address_id"]) < String(b["address"]["address_id"])
		)
		var previous_sequence: int = int(state["region_sequence"])
		var base_hash: String = String(state["projection_hash"])
		var snapshots_by_address_id: Dictionary = Dictionary(
			state["snapshots_by_address_id"]
		).duplicate(true)
		var snapshot_transports: Array = []
		for snapshot in relevant:
			var address_id: String = String(snapshot["address"]["address_id"])
			snapshots_by_address_id[address_id] = snapshot.duplicate(true)
			snapshot_transports.append(PersistenceCodecScript.encode_persistence_json(snapshot))
		var next_sequence: int = previous_sequence + 1
		var source_global_sequence: int = int(global_delta["stream_sequence"])
		var store_hash: String = RegionScript.projection_store_hash(
			String(_body["checksum"]), _grid_profile_hash, snapshots_by_address_id
		)
		var target_hash: String = RegionScript.projection_hash(
			String(_body["body_id"]), _authority_owner_id, _authority_epoch,
			subscription, next_sequence, source_global_sequence, store_hash
		)
		var delta: Dictionary = DeltaScript.create({
			"body_id": _body["body_id"],
			"authority_owner_id": _authority_owner_id,
			"authority_epoch": _authority_epoch,
			"subscription_id": subscription["subscription_id"],
			"interest_revision": subscription["interest_revision"],
			"previous_region_sequence": previous_sequence,
			"region_sequence": next_sequence,
			"source_global_stream_sequence": source_global_sequence,
			"operation_id": global_delta["operation_id"],
			"result_transport": global_delta["result_transport"],
			"snapshot_transports": snapshot_transports,
			"base_projection_hash": base_hash,
			"target_projection_hash": target_hash,
		})
		var delta_validation: Dictionary = DeltaScript.validate(delta)
		if not bool(delta_validation.get("success", false)):
			return MatterUtilsScript.failure("MATTER_INTEREST_DELTA_BUILD_FAILED", {"cause": delta_validation})
		var active_peer_id: String = String(_active_peer_by_client_id.get(client_id, ""))
		if not active_peer_id.is_empty() and _peer_by_id.has(active_peer_id) \
				and bool(_peer_by_id[active_peer_id].get("active", false)):
			var queued: Dictionary = _queue_delta_frame(active_peer_id, delta)
			if not bool(queued.get("success", false)):
				return MatterUtilsScript.failure("MATTER_INTEREST_DELTA_QUEUE_FAILED", {"cause": queued})
		state["snapshots_by_address_id"] = snapshots_by_address_id
		state["region_sequence"] = next_sequence
		state["source_global_stream_sequence"] = source_global_sequence
		state["projection_hash"] = target_hash
		var replay_log: Array = Array(state["replay_log"]).duplicate(true)
		replay_log.append(delta)
		while replay_log.size() > _max_replay_deltas:
			replay_log.pop_front()
		state["replay_log"] = replay_log
		var hashes: Dictionary = Dictionary(state["hash_by_region_sequence"]).duplicate(true)
		hashes[next_sequence] = target_hash
		_trim_hash_history(hashes, next_sequence)
		state["hash_by_region_sequence"] = hashes
		_states_by_client_id[client_id] = state
		published_regions += 1
	return MatterUtilsScript.success({"published_regions": published_regions})


func acknowledge(peer_id: String, ack: Dictionary) -> Dictionary:
	if not _configured or not _peer_by_id.has(peer_id):
		return MatterUtilsScript.failure("UNKNOWN_MATTER_INTEREST_PEER")
	var validation: Dictionary = AckScript.validate(ack)
	if not bool(validation.get("success", false)):
		return validation
	var peer: Dictionary = _peer_by_id[peer_id]
	if String(ack["client_id"]) != String(peer["client_id"]) \
			or String(ack["session_id"]) != String(peer["session_id"]) \
			or int(ack["authority_epoch"]) != _authority_epoch:
		return MatterUtilsScript.failure("MATTER_INTEREST_ACK_BINDING_MISMATCH")
	var state: Dictionary = _states_by_client_id.get(String(peer["client_id"]), {})
	if state.is_empty() or String(ack["subscription_id"]) != String(state["subscription"]["subscription_id"]) \
			or int(ack["interest_revision"]) != int(state["subscription"]["interest_revision"]):
		return MatterUtilsScript.failure("MATTER_INTEREST_ACK_SUBSCRIPTION_MISMATCH")
	var sequence: int = int(ack["acknowledged_region_sequence"])
	var hashes: Dictionary = state["hash_by_region_sequence"]
	if not hashes.has(sequence) or String(hashes[sequence]) != String(ack["projection_hash"]):
		return MatterUtilsScript.failure("MATTER_INTEREST_ACK_HASH_MISMATCH")
	if sequence < int(state.get("acknowledged_region_sequence", -1)):
		return MatterUtilsScript.failure("STALE_MATTER_INTEREST_ACK")
	state["acknowledged_region_sequence"] = sequence
	state["acknowledged_projection_hash"] = String(ack["projection_hash"])
	_states_by_client_id[String(peer["client_id"])] = state
	return MatterUtilsScript.success({"acknowledged_region_sequence": sequence})


func dispatch_peer(peer_id: String, replication_adapter, max_frames: int = 64) -> Dictionary:
	if not _configured or not _peer_by_id.has(peer_id):
		return MatterUtilsScript.failure("UNKNOWN_MATTER_INTEREST_PEER")
	if replication_adapter == null or not replication_adapter.has_method("send") \
			or max_frames < 1 or max_frames > 1024:
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_DISPATCH")
	var queue: Array = _outbound_by_peer_id.get(peer_id, [])
	var peer: Dictionary = _peer_by_id[peer_id]
	var dispatched: int = 0
	while not queue.is_empty() and dispatched < max_frames:
		var frame: Dictionary = queue[0]
		var transport_sequence: int = int(peer.get("transport_sequence", 0)) + 1
		var envelope: Dictionary = ReplicationEnvelopeScript.create(
			"replication/mw7/%s/%d" % [peer_id.sha256_text(), transport_sequence],
			SOURCE_ID,
			peer_id,
			"INTEREST",
			transport_sequence,
			FrameScript.SCHEMA,
			frame
		)
		var sent: Dictionary = replication_adapter.send(envelope)
		if not bool(sent.get("success", false)):
			_outbound_by_peer_id[peer_id] = queue
			_peer_by_id[peer_id] = peer
			return MatterUtilsScript.failure(String(sent.get("error_code", "MATTER_INTEREST_SEND_FAILED")), {
				"dispatched": dispatched,
				"remaining": queue.size(),
			})
		queue.pop_front()
		peer["transport_sequence"] = transport_sequence
		dispatched += 1
	_outbound_by_peer_id[peer_id] = queue
	_peer_by_id[peer_id] = peer
	return MatterUtilsScript.success({"dispatched": dispatched, "remaining": queue.size()})


func create_region_snapshot(client_id: String) -> Dictionary:
	if not _configured or not _states_by_client_id.has(client_id):
		return {}
	var state: Dictionary = _states_by_client_id[client_id]
	var subscription: Dictionary = state["subscription"]
	var transports: Array = []
	var address_ids: Array = state["snapshots_by_address_id"].keys()
	address_ids.sort()
	for address_id in address_ids:
		var encoded: String = PersistenceCodecScript.encode_persistence_json(
			Dictionary(state["snapshots_by_address_id"][address_id])
		)
		if encoded.is_empty():
			return {}
		transports.append(encoded)
	var snapshot: Dictionary = SnapshotScript.create({
		"body_id": _body["body_id"],
		"body_definition_hash": _body["checksum"],
		"grid_profile_hash": _grid_profile_hash,
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"subscription_transport": PersistenceCodecScript.encode_persistence_json(subscription),
		"interest_revision": subscription["interest_revision"],
		"region_sequence": state["region_sequence"],
		"source_global_stream_sequence": state["source_global_stream_sequence"],
		"snapshot_transports": transports,
		"persistent_snapshot_count": transports.size(),
		"projection_hash": state["projection_hash"],
	})
	return snapshot if bool(SnapshotScript.validate(snapshot).get("success", false)) else {}


func outbound_count(peer_id: String) -> int:
	return Array(_outbound_by_peer_id.get(peer_id, [])).size()


func subscription_state(client_id: String) -> Dictionary:
	return Dictionary(_states_by_client_id.get(client_id, {})).duplicate(true)


func _resolve_subscription_state(client_id: String, subscription: Dictionary) -> Dictionary:
	var snapshots_by_address_id: Dictionary = {}
	if _states_by_client_id.has(client_id):
		var existing: Dictionary = _states_by_client_id[client_id]
		var existing_subscription: Dictionary = existing["subscription"]
		var incoming_revision: int = int(subscription["interest_revision"])
		var existing_revision: int = int(existing_subscription["interest_revision"])
		if incoming_revision < existing_revision:
			return MatterUtilsScript.failure("STALE_MATTER_INTEREST_REVISION")
		if incoming_revision == existing_revision:
			if String(subscription["checksum"]) != String(existing_subscription["checksum"]):
				return MatterUtilsScript.failure("SAME_REVISION_MATTER_INTEREST_CONFLICT")
			snapshots_by_address_id = RegionScript.snapshots_from_store(
				_service.snapshot_store(), _grid_profile, subscription
			)
			if _snapshot_sets_equal(snapshots_by_address_id, existing["snapshots_by_address_id"]):
				return MatterUtilsScript.success({"reused": true})
	if snapshots_by_address_id.is_empty():
		snapshots_by_address_id = RegionScript.snapshots_from_store(
			_service.snapshot_store(), _grid_profile, subscription
		)
	var source_global_sequence: int = int(_authority.stream_sequence())
	var store_hash: String = RegionScript.projection_store_hash(
		String(_body["checksum"]), _grid_profile_hash, snapshots_by_address_id
	)
	var projection_hash: String = RegionScript.projection_hash(
		String(_body["body_id"]), _authority_owner_id, _authority_epoch,
		subscription, 0, source_global_sequence, store_hash
	)
	_states_by_client_id[client_id] = {
		"subscription": subscription.duplicate(true),
		"snapshots_by_address_id": snapshots_by_address_id,
		"region_sequence": 0,
		"source_global_stream_sequence": source_global_sequence,
		"projection_hash": projection_hash,
		"replay_log": [],
		"hash_by_region_sequence": {0: projection_hash},
		"acknowledged_region_sequence": -1,
		"acknowledged_projection_hash": "",
	}
	return MatterUtilsScript.success({"reused": false})


func _snapshot_sets_equal(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for raw_address_id in left.keys():
		var address_id: String = String(raw_address_id)
		if not right.has(address_id):
			return false
		var left_snapshot: Dictionary = left[address_id]
		var right_snapshot: Dictionary = right[address_id]
		if int(left_snapshot.get("state_revision", -1)) != int(right_snapshot.get("state_revision", -1)) \
				or String(left_snapshot.get("checksum", "")) != String(right_snapshot.get("checksum", "")):
			return false
	return true


func _queue_sync(peer_id: String, sync_request: Dictionary) -> Dictionary:
	var client_id: String = String(sync_request["client_id"])
	var state: Dictionary = _states_by_client_id[client_id]
	var known_sequence: int = int(sync_request["known_region_sequence"])
	var known_hash: String = String(sync_request["known_projection_hash"])
	if known_sequence == int(state["region_sequence"]) and known_hash == String(state["projection_hash"]):
		return MatterUtilsScript.success({"mode": "CURRENT"})
	var replay_deltas: Array[Dictionary] = _replay_from(state, known_sequence, known_hash)
	if not replay_deltas.is_empty():
		for delta in replay_deltas:
			var queued_delta: Dictionary = _queue_delta_frame(peer_id, delta)
			if not bool(queued_delta.get("success", false)):
				return MatterUtilsScript.failure("MATTER_INTEREST_REPLAY_QUEUE_FAILED", {"cause": queued_delta})
		return MatterUtilsScript.success({"mode": "DELTA_REPLAY", "delta_count": replay_deltas.size()})
	var snapshot: Dictionary = create_region_snapshot(client_id)
	if snapshot.is_empty():
		return MatterUtilsScript.failure("MATTER_INTEREST_SNAPSHOT_BUILD_FAILED")
	var queued_snapshot: Dictionary = _queue_snapshot_frame(peer_id, snapshot)
	if not bool(queued_snapshot.get("success", false)):
		return MatterUtilsScript.failure("MATTER_INTEREST_SNAPSHOT_QUEUE_FAILED", {"cause": queued_snapshot})
	return MatterUtilsScript.success({"mode": "REGION_SNAPSHOT"})


func _replay_from(state: Dictionary, known_sequence: int, known_hash: String) -> Array[Dictionary]:
	var current_sequence: int = int(state["region_sequence"])
	if known_sequence < 0 or known_sequence >= current_sequence:
		return []
	var expected_sequence: int = known_sequence + 1
	var selected: Array[Dictionary] = []
	for delta_value in state["replay_log"]:
		var delta: Dictionary = delta_value
		var sequence: int = int(delta["region_sequence"])
		if sequence < expected_sequence:
			continue
		if sequence != expected_sequence:
			return []
		if selected.is_empty() and String(delta["base_projection_hash"]) != known_hash:
			return []
		selected.append(delta)
		expected_sequence += 1
	if expected_sequence != current_sequence + 1:
		return []
	return selected


func _queue_delta_frame(peer_id: String, delta: Dictionary) -> Dictionary:
	return _queue_frame(peer_id, "REGION_DELTA", DeltaScript.SCHEMA, delta)


func _queue_snapshot_frame(peer_id: String, snapshot: Dictionary) -> Dictionary:
	return _queue_frame(peer_id, "REGION_SNAPSHOT", SnapshotScript.SCHEMA, snapshot)


func _queue_frame(peer_id: String, frame_kind: String, payload_schema: String, payload: Dictionary) -> Dictionary:
	if not _peer_by_id.has(peer_id):
		return MatterUtilsScript.failure("UNKNOWN_MATTER_INTEREST_FRAME_PEER")
	var peer: Dictionary = _peer_by_id[peer_id]
	var payload_transport: String = PersistenceCodecScript.encode_persistence_json(payload)
	if payload_transport.is_empty():
		return MatterUtilsScript.failure("MATTER_INTEREST_FRAME_ENCODE_FAILED")
	_frame_serial += 1
	var subscription_id: String = String(payload.get("subscription_id", ""))
	if frame_kind == "REGION_SNAPSHOT":
		var subscription: Dictionary = SnapshotScript.decode_subscription(payload)
		subscription_id = String(subscription.get("subscription_id", ""))
	var frame: Dictionary = FrameScript.create({
		"frame_id": "frame/mw7/%s/%d" % [peer_id.sha256_text(), _frame_serial],
		"frame_kind": frame_kind,
		"body_id": _body["body_id"],
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"session_id": peer["session_id"],
		"subscription_id": subscription_id,
		"interest_revision": payload["interest_revision"],
		"region_sequence": payload["region_sequence"],
		"source_global_stream_sequence": payload["source_global_stream_sequence"],
		"payload_schema": payload_schema,
		"payload_transport": payload_transport,
	})
	var frame_validation: Dictionary = FrameScript.validate(frame)
	if not bool(frame_validation.get("success", false)):
		return MatterUtilsScript.failure("MATTER_INTEREST_FRAME_BUILD_FAILED", {"cause": frame_validation})
	var queue: Array = _outbound_by_peer_id.get(peer_id, [])
	queue.append(frame)
	_outbound_by_peer_id[peer_id] = queue
	return MatterUtilsScript.success({"queued": queue.size()})


func _trim_hash_history(hashes: Dictionary, current_sequence: int) -> void:
	var minimum_sequence: int = maxi(0, current_sequence - maxi(1, _max_replay_deltas) - 1)
	for raw_sequence in hashes.keys():
		if int(raw_sequence) < minimum_sequence:
			hashes.erase(raw_sequence)


func _disconnect_peer_internal(peer_id: String) -> void:
	if not _peer_by_id.has(peer_id):
		return
	var peer: Dictionary = _peer_by_id[peer_id]
	peer["active"] = false
	_peer_by_id[peer_id] = peer
	_outbound_by_peer_id.erase(peer_id)
	var client_id: String = String(peer.get("client_id", ""))
	if String(_active_peer_by_client_id.get(client_id, "")) == peer_id:
		_active_peer_by_client_id.erase(client_id)
