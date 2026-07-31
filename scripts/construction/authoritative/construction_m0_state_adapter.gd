extends RefCounted

const SnapshotEnvelopeScript = preload("res://scripts/network/contracts/aggregate_snapshot_envelope.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ConstructSnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const TranslatorScript = preload("res://scripts/construction/authoritative/construction_m0_batch_translator.gd")

var _aggregate_kind: String = ""
var _state_schema: String = ""


func _init(aggregate_kind: String = "", state_schema: String = "") -> void:
	_aggregate_kind = aggregate_kind
	_state_schema = state_schema


func get_aggregate_kind() -> String:
	return _aggregate_kind


func supports_aggregate(aggregate) -> bool:
	return aggregate is Dictionary


func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	var envelope: Dictionary = SnapshotEnvelopeScript.validate(snapshot)
	if not bool(envelope.get("success", false)):
		return envelope
	var identity: Dictionary = snapshot["descriptor"]["identity"]
	if String(identity["aggregate_kind"]) != _aggregate_kind or String(identity["state_schema"]) != _state_schema:
		return _failure("CONSTRUCTION_M0_ADAPTER_IDENTITY_MISMATCH")
	var state: Dictionary = snapshot["state"]
	match _aggregate_kind:
		TranslatorScript.ITEM_GRAPH_KIND:
			return _validate_wrapped_state(state, TranslatorScript.ITEM_GRAPH_STATE_SCHEMA, ["item_registry", "container_registry"])
		TranslatorScript.LEDGER_KIND:
			return _validate_wrapped_state(state, TranslatorScript.LEDGER_STATE_SCHEMA, ["operation_ledger"])
		TranslatorScript.CONSTRUCT_KIND:
			return ConstructSnapshotScript.validate(state)
	return _failure("CONSTRUCTION_M0_ADAPTER_KIND_UNSUPPORTED")


func validate_delta(_delta: Dictionary) -> Dictionary:
	return _failure("CONSTRUCTION_M0_DELTA_UNSUPPORTED")


func export_snapshot(aggregate, _snapshot_id: String) -> Dictionary:
	return Dictionary(aggregate).duplicate(true) if aggregate is Dictionary else {}


func export_delta(_base_snapshot: Dictionary, _aggregate, _delta_id: String) -> Dictionary:
	return {}


func _validate_wrapped_state(state: Dictionary, schema: String, payload_fields: Array[String]) -> Dictionary:
	var required: Array[String] = ["schema"]
	required.append_array(payload_fields)
	required.append("checksum")
	var exact: Dictionary = UtilsScript.validate_exact_fields(state, required)
	if not bool(exact.get("success", false)):
		return exact
	if state.get("schema") != schema:
		return _failure("CONSTRUCTION_M0_STATE_SCHEMA_MISMATCH")
	for field in payload_fields:
		if typeof(state.get(field)) != TYPE_DICTIONARY:
			return _failure("CONSTRUCTION_M0_STATE_SECTION_INVALID", {"field": field})
	var payload: Dictionary = state.duplicate(true)
	payload["checksum"] = ""
	if String(state.get("checksum", "")) != UtilsScript.payload_hash(payload):
		return _failure("CONSTRUCTION_M0_STATE_CHECKSUM_MISMATCH")
	return _success()


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
