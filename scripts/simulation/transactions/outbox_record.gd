extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const TxUtilsScript = preload("res://scripts/simulation/transactions/transaction_contract_utils.gd")

const SCHEMA: String = "planet_simulator.outbox_record.v1"
const FIELDS: Array[String] = ["schema", "record_id", "batch_id", "operation_id", "stream_id", "event_schema", "payload", "commit_generation", "created_at_tick", "delivery_checksum", "published", "publish_attempts", "checksum"]


static func create(record_id: String, batch_id: String, operation_id: String, stream_id: String, event_schema: String, payload: Dictionary, generation: int, tick: int) -> Dictionary:
	var value := {"schema": SCHEMA, "record_id": record_id, "batch_id": batch_id, "operation_id": operation_id, "stream_id": stream_id, "event_schema": event_schema, "payload": payload.duplicate(true), "commit_generation": generation, "created_at_tick": tick, "delivery_checksum": "", "published": false, "publish_attempts": 0, "checksum": ""}
	value["delivery_checksum"] = compute_delivery_checksum(value)
	value["checksum"] = compute_checksum(value)
	return value


static func compute_delivery_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	for field in ["delivery_checksum", "published", "publish_attempts", "checksum"]: payload.erase(field)
	return UtilsScript.payload_hash(payload)


static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload.erase("checksum")
	return UtilsScript.payload_hash(payload)


static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return TxUtilsScript.failure("UNSUPPORTED_OUTBOX_RECORD_SCHEMA")
	if not TxUtilsScript.is_identifier(String(value.get("record_id", "")), "outbox/") or not TxUtilsScript.is_identifier(String(value.get("batch_id", "")), "batch/") or not TxUtilsScript.is_identifier(String(value.get("operation_id", "")), "operation/") or not TxUtilsScript.is_identifier(String(value.get("stream_id", "")), "stream/"):
		return TxUtilsScript.failure("INVALID_OUTBOX_RECORD_IDENTITY")
	if not TxUtilsScript.is_versioned_schema(String(value.get("event_schema", ""))) or typeof(value.get("payload")) != TYPE_DICTIONARY:
		return TxUtilsScript.failure("INVALID_OUTBOX_RECORD_PAYLOAD")
	if not bool(BusUtilsScript.validate_payload(value["payload"]).get("success", false)): return TxUtilsScript.failure("INVALID_OUTBOX_RECORD_PAYLOAD")
	for field in ["commit_generation", "created_at_tick", "publish_attempts"]:
		if not UtilsScript.is_json_integer(value.get(field)) or int(value[field]) < 0: return TxUtilsScript.failure("INVALID_OUTBOX_RECORD_INTEGER", {"field": field})
	if int(value["commit_generation"]) < 1 or not TxUtilsScript.is_lower_hex_64(String(value.get("delivery_checksum", ""))) or String(value["delivery_checksum"]) != compute_delivery_checksum(value) or typeof(value.get("published")) != TYPE_BOOL: return TxUtilsScript.failure("INVALID_OUTBOX_RECORD_STATE")
	if not TxUtilsScript.is_lower_hex_64(String(value.get("checksum", ""))) or String(value["checksum"]) != compute_checksum(value): return TxUtilsScript.failure("OUTBOX_RECORD_CHECKSUM_MISMATCH")
	return TxUtilsScript.success()


static func mark_published(value: Dictionary) -> Dictionary:
	var copy := value.duplicate(true)
	copy["published"] = true
	copy["publish_attempts"] = int(copy["publish_attempts"]) + 1
	copy["checksum"] = compute_checksum(copy)
	return copy
