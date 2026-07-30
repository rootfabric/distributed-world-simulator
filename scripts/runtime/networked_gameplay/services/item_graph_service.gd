extends RefCounted

const ItemGraphSnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/item_graph_snapshot.gd")
const ItemGraphDelta = preload("res://scripts/runtime/networked_gameplay/contracts/item_graph_delta.gd")

const SCHEMA := "planet_simulator.item_graph_service.v1"

var _backend
var _configured := false
var _commands_routed := 0
var _snapshots_published := 0


func setup(backend_reference) -> Dictionary:
	if _configured:
		return _failure("ITEM_GRAPH_SERVICE_ALREADY_CONFIGURED")
	if backend_reference == null or not backend_reference.has_method("handle_command"):
		return _failure("INVALID_ITEM_GRAPH_BACKEND")
	_backend = backend_reference
	_configured = true
	return _success()


func handle_command(command: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("ITEM_GRAPH_SERVICE_NOT_CONFIGURED")
	_commands_routed += 1
	return _backend.handle_command(command)


func create_initial_snapshots() -> Array[Dictionary]:
	if not _configured:
		return []
	var snapshots: Array[Dictionary] = _backend.create_initial_snapshots()
	for snapshot in snapshots:
		if String(snapshot.get("entity_type", "")) == "item_graph":
			var validation := ItemGraphSnapshot.validate(snapshot)
			if bool(validation.get("success", false)):
				_snapshots_published += 1
	return snapshots


func create_snapshot(entity_id: String) -> Dictionary:
	if not _configured:
		return {}
	var snapshot: Dictionary = _backend.create_snapshot(entity_id)
	if String(snapshot.get("entity_type", "")) == "item_graph":
		var validation := ItemGraphSnapshot.validate(snapshot)
		if bool(validation.get("success", false)):
			_snapshots_published += 1
	return snapshot


func validate_delta(delta: Dictionary) -> Dictionary:
	return ItemGraphDelta.validate(delta)


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": _configured,
		"commands_routed": _commands_routed,
		"snapshots_published": _snapshots_published,
		"wire_snapshot_schema": ItemGraphSnapshot.SCHEMA,
		"wire_delta_schema": ItemGraphDelta.SCHEMA,
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": {}}
