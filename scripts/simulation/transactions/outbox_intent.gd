extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const TxUtilsScript = preload("res://scripts/simulation/transactions/transaction_contract_utils.gd")

const SCHEMA: String = "planet_simulator.outbox_intent.v1"
const FIELDS: Array[String] = ["schema", "intent_id", "stream_id", "event_schema", "payload"]


static func create(intent_id: String, stream_id: String, event_schema: String, payload: Dictionary) -> Dictionary:
	return {"schema": SCHEMA, "intent_id": intent_id, "stream_id": stream_id, "event_schema": event_schema, "payload": payload.duplicate(true)}


static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return TxUtilsScript.failure("UNSUPPORTED_OUTBOX_INTENT_SCHEMA")
	if not TxUtilsScript.is_identifier(String(value.get("intent_id", "")), "outbox-intent/") or not TxUtilsScript.is_identifier(String(value.get("stream_id", "")), "stream/"):
		return TxUtilsScript.failure("INVALID_OUTBOX_INTENT_IDENTITY")
	if not TxUtilsScript.is_versioned_schema(String(value.get("event_schema", ""))):
		return TxUtilsScript.failure("INVALID_OUTBOX_EVENT_SCHEMA")
	if typeof(value.get("payload")) != TYPE_DICTIONARY:
		return TxUtilsScript.failure("INVALID_OUTBOX_PAYLOAD")
	var payload_validation := BusUtilsScript.validate_payload(value["payload"])
	if not bool(payload_validation.get("success", false)):
		return TxUtilsScript.failure(String(payload_validation.get("error_code", "INVALID_OUTBOX_PAYLOAD")))
	return TxUtilsScript.success()
