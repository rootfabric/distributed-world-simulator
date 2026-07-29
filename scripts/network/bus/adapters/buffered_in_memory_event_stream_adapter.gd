extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const ResultScript = preload("res://scripts/network/bus/bus_operation_result.gd")
const DescriptorScript = preload("res://scripts/network/bus/semantic_port_descriptor.gd")
const EventScript = preload("res://scripts/network/bus/event_envelope.gd")

var _adapter_id: String
var _max_pending: int
var _pending: Array[Dictionary] = []
var _streams: Dictionary = {}
var _event_fingerprints: Dictionary = {}


func _init(adapter_id: String = "adapter/in-memory-event-buffered", max_pending: int = 128) -> void:
	_adapter_id = adapter_id
	_max_pending = maxi(1, max_pending)


func get_descriptor() -> Dictionary:
	return DescriptorScript.create("EVENT_STREAM", _adapter_id, ["buffered_publish", "canonical_round_trip", "idempotent_event_id", "monotonic_sequence"])


func publish(event_value: Dictionary) -> Dictionary:
	var check: Dictionary = EventScript.validate(event_value)
	if not bool(check.get("success", false)):
		return ResultScript.failure("REJECTED", String(check.get("error_code", "INVALID_EVENT")), false)
	var fingerprint: String = NetworkUtilsScript.payload_hash(event_value)
	var event_id: String = String(event_value["event_id"])
	if _event_fingerprints.has(event_id):
		if String(_event_fingerprints[event_id]) == fingerprint:
			return ResultScript.success("ACCEPTED", {"duplicate": true, "queued": false})
		return ResultScript.failure("REJECTED", "EVENT_ID_CONFLICT", false)
	if _pending.size() >= _max_pending:
		return ResultScript.failure("BACKPRESSURE", "EVENT_PENDING_CAPACITY", true, {"pending": _pending.size()})
	var copied: Dictionary = BusUtilsScript.deep_copy_json(event_value)
	if not bool(copied.get("success", false)):
		return ResultScript.failure("REJECTED", "NON_CANONICAL_EVENT", false)
	_pending.append(copied.get("value"))
	_event_fingerprints[event_id] = fingerprint
	return ResultScript.success("ACCEPTED", {"duplicate": false, "queued": true, "pending": _pending.size()})


func read(stream_id: String, after_sequence: int = 0, max_count: int = 64) -> Dictionary:
	if not BusUtilsScript.is_canonical_id(stream_id, "stream") or after_sequence < 0 or max_count < 1 or max_count > 1024:
		return ResultScript.failure("REJECTED", "INVALID_READ_REQUEST", false)
	var flush_result: Dictionary = _flush_pending()
	if not bool(flush_result.get("success", false)):
		return flush_result
	var output: Array = []
	for event_value in _streams.get(stream_id, []):
		if int(event_value.get("sequence", 0)) > after_sequence:
			output.append(event_value.duplicate(true))
			if output.size() >= max_count:
				break
	return ResultScript.success("AVAILABLE" if not output.is_empty() else "EMPTY", {"events": output})


func _flush_pending() -> Dictionary:
	while not _pending.is_empty():
		var event_value: Dictionary = _pending[0]
		var stream_id: String = String(event_value["stream_id"])
		var stream: Array = _streams.get(stream_id, [])
		var expected_sequence: int = stream.size() + 1
		if int(event_value["sequence"]) != expected_sequence:
			return ResultScript.failure("REJECTED", "EVENT_SEQUENCE_MISMATCH", false, {"expected_sequence": expected_sequence})
		stream.append(event_value.duplicate(true))
		_streams[stream_id] = stream
		_pending.pop_front()
	return ResultScript.success()
