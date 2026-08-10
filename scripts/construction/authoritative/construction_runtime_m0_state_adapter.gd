extends RefCounted

const SnapshotEnvelopeScript = preload("res://scripts/network/contracts/aggregate_snapshot_envelope.gd")
const RuntimePersistenceScript = preload("res://scripts/construction/behavior/construction_runtime_persistence_state.gd")
const RuntimeM0TranslatorScript = preload("res://scripts/construction/authoritative/construction_runtime_m0_translator.gd")


func get_aggregate_kind() -> String:
	return RuntimeM0TranslatorScript.RUNTIME_KIND


func supports_aggregate(aggregate) -> bool:
	return aggregate is Dictionary


func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	var envelope: Dictionary = SnapshotEnvelopeScript.validate(snapshot)
	if not bool(envelope.get("success", false)):
		return envelope
	var identity: Dictionary = snapshot["descriptor"]["identity"]
	if String(identity.get("aggregate_kind", "")) != RuntimeM0TranslatorScript.RUNTIME_KIND:
		return _failure("CONSTRUCTION_RUNTIME_M0_KIND_MISMATCH")
	if String(identity.get("state_schema", "")) != RuntimePersistenceScript.SCHEMA:
		return _failure("CONSTRUCTION_RUNTIME_M0_SCHEMA_MISMATCH")
	return RuntimePersistenceScript.validate(Dictionary(snapshot.get("state", {})))


func validate_delta(_delta: Dictionary) -> Dictionary:
	return _failure("CONSTRUCTION_RUNTIME_M0_DELTA_UNSUPPORTED")


func export_snapshot(aggregate, _snapshot_id: String) -> Dictionary:
	return Dictionary(aggregate).duplicate(true) if aggregate is Dictionary else {}


func export_delta(_base_snapshot: Dictionary, _aggregate, _delta_id: String) -> Dictionary:
	return {}


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
