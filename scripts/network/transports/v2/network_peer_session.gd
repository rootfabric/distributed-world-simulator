extends RefCounted

const TransportUtilsScript = preload("res://scripts/network/transports/v2/transport_contract_utils.gd")

const SCHEMA: String = "planet_simulator.network_peer_session.v2"
const UNRELIABLE_SEQUENCE_POLICY: String = "GAP_TOLERANT_LATEST_WINS_V1"
const INCOMING_SEQUENCE_STREAM_POLICY: String = "DELIVERY_CLASS_ENET_CHANNEL_V1"
const RELIABLE_SEQUENCE_POLICY: String = "MONOTONIC_PER_STREAM_GLOBAL_GAPS_V1"
const STATE_CONNECTING := "CONNECTING"
const STATE_TRANSPORT_CONNECTED := "TRANSPORT_CONNECTED"
const STATE_HANDSHAKING := "HANDSHAKING"
const STATE_SYNCHRONIZING := "SYNCHRONIZING"
const STATE_READY := "READY"
const STATE_DRAINING := "DRAINING"
const STATE_CLOSED := "CLOSED"
const STATE_FAILED := "FAILED"

const TRANSITIONS: Dictionary = {
	STATE_CONNECTING: [STATE_TRANSPORT_CONNECTED, STATE_FAILED, STATE_CLOSED],
	STATE_TRANSPORT_CONNECTED: [STATE_HANDSHAKING, STATE_SYNCHRONIZING, STATE_READY, STATE_DRAINING, STATE_FAILED, STATE_CLOSED],
	STATE_HANDSHAKING: [STATE_SYNCHRONIZING, STATE_READY, STATE_DRAINING, STATE_FAILED, STATE_CLOSED],
	STATE_SYNCHRONIZING: [STATE_READY, STATE_DRAINING, STATE_FAILED, STATE_CLOSED],
	STATE_READY: [STATE_DRAINING, STATE_FAILED, STATE_CLOSED],
	STATE_DRAINING: [STATE_CLOSED, STATE_FAILED],
	STATE_CLOSED: [],
	STATE_FAILED: [STATE_CLOSED],
}

var _peer_id: String = ""
var _session_id: String = ""
var _state: String = STATE_CONNECTING
var _route_id: String = ""
var _route_generation: int = 0
var _outgoing_sequence: int = 0
var _incoming_sequence: int = 0
var _incoming_sequences: Dictionary = {}
var _queued_messages: int = 0
var _queued_bytes: int = 0
var _max_pending_messages: int = 128
var _max_pending_bytes: int = 1048576
var _failure_code: String = ""


func configure(peer_id: String, session_id: String, route_id: String, route_generation: int, max_messages: int, max_bytes: int) -> Dictionary:
	if not _peer_id.is_empty():
		return TransportUtilsScript.failure("SESSION_ALREADY_CONFIGURED")
	if not TransportUtilsScript.is_canonical_transport_id(peer_id, "peer"):
		return TransportUtilsScript.failure("INVALID_PEER_ID")
	if not TransportUtilsScript.is_canonical_transport_id(session_id, "transport-session"):
		return TransportUtilsScript.failure("INVALID_SESSION_ID")
	if not TransportUtilsScript.is_canonical_transport_id(route_id, "route"):
		return TransportUtilsScript.failure("INVALID_ROUTE_ID")
	if route_generation < 1:
		return TransportUtilsScript.failure("INVALID_ROUTE_GENERATION")
	if max_messages < 1 or max_bytes < 1:
		return TransportUtilsScript.failure("INVALID_QUEUE_LIMIT")
	_peer_id = peer_id
	_session_id = session_id
	_route_id = route_id
	_route_generation = route_generation
	_max_pending_messages = max_messages
	_max_pending_bytes = max_bytes
	return TransportUtilsScript.success()


func transition(target_state: String, failure_code: String = "") -> Dictionary:
	if target_state == _state:
		return TransportUtilsScript.success({"replay": true, "state": _state})
	if not TRANSITIONS.has(_state) or not TRANSITIONS[_state].has(target_state):
		return TransportUtilsScript.failure("INVALID_PEER_STATE_TRANSITION", {"state": _state, "target_state": target_state})
	_state = target_state
	if target_state == STATE_FAILED:
		_failure_code = failure_code if not failure_code.is_empty() else "PEER_FAILURE"
	return TransportUtilsScript.success({"replay": false, "state": _state})


func update_route(route_id: String, route_generation: int) -> Dictionary:
	if not TransportUtilsScript.is_canonical_transport_id(route_id, "route"):
		return TransportUtilsScript.failure("INVALID_ROUTE_ID")
	if route_generation < _route_generation:
		return TransportUtilsScript.failure("STALE_ROUTE_GENERATION")
	if route_generation == _route_generation:
		if route_id != _route_id:
			return TransportUtilsScript.failure("ROUTE_CHANGED_WITHOUT_GENERATION")
		return TransportUtilsScript.success({"replay": true})
	_route_id = route_id
	_route_generation = route_generation
	return TransportUtilsScript.success({"replay": false})


func peek_next_outgoing_sequence() -> int:
	return _outgoing_sequence + 1


func commit_outgoing_sequence(sequence: int) -> Dictionary:
	if sequence <= _outgoing_sequence:
		return TransportUtilsScript.failure("STALE_OR_DUPLICATE_OUTGOING_FRAME")
	if sequence != _outgoing_sequence + 1:
		return TransportUtilsScript.failure("OUTGOING_FRAME_SEQUENCE_GAP", {"expected": _outgoing_sequence + 1})
	_outgoing_sequence = sequence
	return TransportUtilsScript.success()


func accept_incoming_sequence(
	sequence: int,
	allow_gap: bool = false,
	sequence_stream: String = "LEGACY",
	require_contiguous: bool = true
) -> Dictionary:
	var normalized_stream: String = sequence_stream.strip_edges().to_upper()
	if normalized_stream.is_empty():
		return TransportUtilsScript.failure("INVALID_SEQUENCE_STREAM")
	var last_sequence: int = int(_incoming_sequences.get(normalized_stream, 0))
	if sequence <= last_sequence:
		if allow_gap:
			return TransportUtilsScript.success({
				"accepted": false,
				"stale": true,
				"last_sequence": last_sequence,
				"sequence_stream": normalized_stream,
			})
		return TransportUtilsScript.failure("STALE_OR_DUPLICATE_FRAME", {
			"last_sequence": last_sequence,
			"sequence_stream": normalized_stream,
		})
	if require_contiguous and sequence != last_sequence + 1:
		return TransportUtilsScript.failure("FRAME_SEQUENCE_GAP", {
			"expected": last_sequence + 1,
			"sequence_stream": normalized_stream,
		})
	var previous_sequence: int = last_sequence
	_incoming_sequences[normalized_stream] = sequence
	_incoming_sequence = maxi(_incoming_sequence, sequence)
	return TransportUtilsScript.success({
		"accepted": true,
		"gap": maxi(sequence - previous_sequence - 1, 0),
		"sequence_stream": normalized_stream,
	})


func reserve_queue(bytes: int) -> Dictionary:
	if bytes < 1:
		return TransportUtilsScript.failure("INVALID_QUEUE_BYTES")
	if _queued_messages >= _max_pending_messages:
		return TransportUtilsScript.failure("PEER_QUEUE_MESSAGE_LIMIT")
	if _queued_bytes + bytes > _max_pending_bytes:
		return TransportUtilsScript.failure("PEER_QUEUE_BYTE_LIMIT")
	_queued_messages += 1
	_queued_bytes += bytes
	return TransportUtilsScript.success()


func release_queue(bytes: int) -> void:
	_queued_messages = maxi(0, _queued_messages - 1)
	_queued_bytes = maxi(0, _queued_bytes - maxi(0, bytes))


func snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"peer_id": _peer_id,
		"session_id": _session_id,
		"state": _state,
		"route_id": _route_id,
		"route_generation": _route_generation,
		"outgoing_sequence": _outgoing_sequence,
		"incoming_sequence": _incoming_sequence,
		"incoming_sequences": _incoming_sequences.duplicate(true),
		"queued_messages": _queued_messages,
		"queued_bytes": _queued_bytes,
		"max_pending_messages": _max_pending_messages,
		"max_pending_bytes": _max_pending_bytes,
		"failure_code": _failure_code,
	}
