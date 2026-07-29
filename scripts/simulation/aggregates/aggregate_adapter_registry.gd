extends RefCounted

const AdapterPortScript = preload("res://scripts/simulation/aggregates/aggregate_adapter_port.gd")
const SnapshotScript = preload("res://scripts/network/contracts/aggregate_snapshot_envelope.gd")
const DeltaScript = preload("res://scripts/network/contracts/aggregate_delta_envelope.gd")

var _adapters_by_kind: Dictionary = {}
var _configured: bool = false


func setup() -> Dictionary:
	_adapters_by_kind.clear()
	_configured = true
	return _success()


func register_adapter(adapter) -> Dictionary:
	if not _configured:
		return _failure("AGGREGATE_ADAPTER_REGISTRY_NOT_CONFIGURED")
	var validation: Dictionary = AdapterPortScript.validate_adapter(adapter)
	if not bool(validation.get("success", false)):
		return validation
	var kind: String = String(validation.get("details", {}).get("aggregate_kind", ""))
	if _adapters_by_kind.has(kind):
		if _adapters_by_kind[kind] == adapter:
			return _success({"aggregate_kind": kind, "replay": true})
		return _failure("AGGREGATE_ADAPTER_KIND_CONFLICT", {"aggregate_kind": kind})
	_adapters_by_kind[kind] = adapter
	return _success({"aggregate_kind": kind, "replay": false})


func resolve_adapter(aggregate_kind: String):
	return _adapters_by_kind.get(aggregate_kind)


func export_snapshot(aggregate_kind: String, aggregate, snapshot_id: String) -> Dictionary:
	var adapter = resolve_adapter(aggregate_kind)
	if adapter == null:
		return _failure("AGGREGATE_ADAPTER_NOT_FOUND", {"aggregate_kind": aggregate_kind})
	if not bool(adapter.call("supports_aggregate", aggregate)):
		return _failure("AGGREGATE_ADAPTER_REJECTED_VALUE", {"aggregate_kind": aggregate_kind})
	var snapshot = adapter.call("export_snapshot", aggregate, snapshot_id)
	if typeof(snapshot) != TYPE_DICTIONARY:
		return _failure("AGGREGATE_ADAPTER_INVALID_SNAPSHOT")
	var validation: Dictionary = validate_snapshot(snapshot)
	if not bool(validation.get("success", false)):
		return _failure("AGGREGATE_ADAPTER_INVALID_SNAPSHOT", {"cause": validation})
	return _success({"snapshot": SnapshotScript.normalize(snapshot)})


func export_delta(aggregate_kind: String, base_snapshot: Dictionary, aggregate, delta_id: String) -> Dictionary:
	var adapter = resolve_adapter(aggregate_kind)
	if adapter == null:
		return _failure("AGGREGATE_ADAPTER_NOT_FOUND", {"aggregate_kind": aggregate_kind})
	var base_validation: Dictionary = validate_snapshot(base_snapshot)
	if not bool(base_validation.get("success", false)):
		return _failure("AGGREGATE_ADAPTER_INVALID_BASE_SNAPSHOT", {"cause": base_validation})
	if String(base_snapshot["descriptor"]["identity"]["aggregate_kind"]) != aggregate_kind:
		return _failure("AGGREGATE_ADAPTER_BASE_KIND_MISMATCH", {"aggregate_kind": aggregate_kind})
	if not bool(adapter.call("supports_aggregate", aggregate)):
		return _failure("AGGREGATE_ADAPTER_REJECTED_VALUE", {"aggregate_kind": aggregate_kind})
	var delta = adapter.call("export_delta", base_snapshot, aggregate, delta_id)
	if typeof(delta) != TYPE_DICTIONARY:
		return _failure("AGGREGATE_ADAPTER_INVALID_DELTA")
	var validation: Dictionary = validate_delta(delta)
	if not bool(validation.get("success", false)):
		return _failure("AGGREGATE_ADAPTER_INVALID_DELTA", {"cause": validation})
	return _success({"delta": delta.duplicate(true)})


func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	var envelope_validation: Dictionary = SnapshotScript.validate(snapshot)
	if not bool(envelope_validation.get("success", false)):
		return _failure("INVALID_AGGREGATE_SNAPSHOT", {"cause": envelope_validation})
	var kind: String = String(snapshot["descriptor"]["identity"]["aggregate_kind"])
	var adapter = resolve_adapter(kind)
	if adapter == null:
		return _failure("AGGREGATE_ADAPTER_NOT_FOUND", {"aggregate_kind": kind})
	var result = adapter.call("validate_snapshot", snapshot)
	if typeof(result) != TYPE_DICTIONARY or not bool(result.get("success", false)):
		return _failure("AGGREGATE_KIND_SNAPSHOT_REJECTED", {"aggregate_kind": kind, "cause": result})
	return _success({"aggregate_kind": kind})


func validate_delta(delta: Dictionary) -> Dictionary:
	var envelope_validation: Dictionary = DeltaScript.validate(delta)
	if not bool(envelope_validation.get("success", false)):
		return _failure("INVALID_AGGREGATE_DELTA", {"cause": envelope_validation})
	var kind: String = String(delta["aggregate_kind"])
	var adapter = resolve_adapter(kind)
	if adapter == null:
		return _failure("AGGREGATE_ADAPTER_NOT_FOUND", {"aggregate_kind": kind})
	var result = adapter.call("validate_delta", delta)
	if typeof(result) != TYPE_DICTIONARY or not bool(result.get("success", false)):
		return _failure("AGGREGATE_KIND_DELTA_REJECTED", {"aggregate_kind": kind, "cause": result})
	return _success({"aggregate_kind": kind})


func get_registered_kinds() -> Array[String]:
	var kinds: Array[String] = []
	for kind in _adapters_by_kind.keys():
		kinds.append(String(kind))
	kinds.sort()
	return kinds


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
