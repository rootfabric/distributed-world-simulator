extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const ResultScript = preload("res://scripts/network/bus/bus_operation_result.gd")
const DescriptorScript = preload("res://scripts/network/bus/semantic_port_descriptor.gd")
const ReplicationScript = preload("res://scripts/network/bus/replication_envelope.gd")

var _adapter_id: String
var _max_messages_per_peer: int
var _queues: Dictionary = {}
var _fingerprints: Dictionary = {}
var _last_sequence_by_source_target: Dictionary = {}


func _init(adapter_id: String = "adapter/in-memory-replication", max_messages_per_peer: int = 128) -> void:
	_adapter_id = adapter_id
	_max_messages_per_peer = maxi(1, max_messages_per_peer)


func get_descriptor() -> Dictionary:
	return DescriptorScript.create("REPLICATION_TRANSPORT", _adapter_id, ["ephemeral", "per_peer_backpressure", "targeted_delivery"])


func send(message: Dictionary) -> Dictionary:
	var check: Dictionary = ReplicationScript.validate(message)
	if not bool(check.get("success", false)):
		return ResultScript.failure("REJECTED", String(check.get("error_code", "INVALID_REPLICATION")), false)
	var message_id: String = String(message["replication_id"])
	var fingerprint: String = NetworkUtilsScript.payload_hash(message)
	if _fingerprints.has(message_id):
		if String(_fingerprints[message_id]) == fingerprint:
			return ResultScript.success("ACCEPTED", {"duplicate": true})
		return ResultScript.failure("REJECTED", "REPLICATION_ID_CONFLICT", false)
	var peer_id: String = String(message["target_peer_id"])
	var queue: Array = _queues.get(peer_id, [])
	if queue.size() >= _max_messages_per_peer:
		return ResultScript.failure("BACKPRESSURE", "REPLICATION_PEER_CAPACITY", true, {"target_peer_id": peer_id, "queued_messages": queue.size()})
	var sequence_key := "%s|%s" % [message["source_id"], peer_id]
	var expected_sequence: int = int(_last_sequence_by_source_target.get(sequence_key, 0)) + 1
	if int(message["sequence"]) != expected_sequence:
		return ResultScript.failure("REJECTED", "REPLICATION_SEQUENCE_MISMATCH", false, {"expected_sequence": expected_sequence})
	var copied: Dictionary = BusUtilsScript.deep_copy_json(message)
	if not bool(copied.get("success", false)):
		return ResultScript.failure("REJECTED", "NON_CANONICAL_REPLICATION", false)
	queue.append(copied.get("value"))
	_queues[peer_id] = queue
	_fingerprints[message_id] = fingerprint
	_last_sequence_by_source_target[sequence_key] = expected_sequence
	return ResultScript.success("ACCEPTED", {"duplicate": false, "queued_messages": queue.size()})


func poll(target_peer_id: String, max_count: int = 64) -> Dictionary:
	if not BusUtilsScript.is_canonical_id(target_peer_id, "peer") or max_count < 1 or max_count > 1024:
		return ResultScript.failure("REJECTED", "INVALID_POLL_REQUEST", false)
	var queue: Array = _queues.get(target_peer_id, [])
	var messages: Array = []
	while not queue.is_empty() and messages.size() < max_count:
		messages.append(queue.pop_front().duplicate(true))
	_queues[target_peer_id] = queue
	return ResultScript.success("AVAILABLE" if not messages.is_empty() else "EMPTY", {"messages": messages, "remaining": queue.size()})
