class_name NetworkCharacterEquipmentPresentationCoordinator
extends RefCounted

signal equipment_presentation_updated(logical_player_id: String, result: Dictionary)

const EquipmentProjection = preload("res://scripts/characters/equipment/network_character_equipment_projection.gd")

const RESULT_OK := "OK"
const RESULT_INVALID_RUNTIME := "CH9_5_INVALID_EQUIPMENT_RUNTIME"
const RESULT_PLAYER_ID_REQUIRED := "CH9_5_PRESENTATION_PLAYER_ID_REQUIRED"
const RESULT_INVALID_PRESENTER := "CH9_5_INVALID_EQUIPMENT_PRESENTER"
const RESULT_NOT_CONFIGURED := "CH9_5_PRESENTATION_COORDINATOR_NOT_CONFIGURED"
const RESULT_PROJECTION_FAILED := "CH9_5_EQUIPMENT_PROJECTION_FAILED"
const RESULT_PRESENTATION_APPLY_FAILED := "CH9_5_EQUIPMENT_PRESENTATION_APPLY_FAILED"

var _runtime
var _bindings: Dictionary = {}
var _last_canonical_checksum := ""
var _last_result: Dictionary = {}
var _signal_updates := 0
var _synchronize_calls := 0
var _projection_failures := 0
var _presentation_failures := 0
var _presentation_changes := 0
var _presentation_reuses := 0


func setup(runtime) -> Dictionary:
	if _runtime != null:
		return _failure("CH9_5_PRESENTATION_COORDINATOR_ALREADY_CONFIGURED")
	if (
		runtime == null
		or not runtime.has_method("get_item_graph_snapshot")
		or not runtime.has_signal("item_graph_updated")
	):
		return _failure(RESULT_INVALID_RUNTIME)
	_runtime = runtime
	_runtime.item_graph_updated.connect(_on_item_graph_updated)
	var current: Dictionary = _runtime.get_item_graph_snapshot()
	if current.is_empty():
		return _store(_success({"pending_initial_snapshot": true}))
	return synchronize(current)


func stop(clear_presenters: bool = false) -> Dictionary:
	if _runtime != null and _runtime.item_graph_updated.is_connected(_on_item_graph_updated):
		_runtime.item_graph_updated.disconnect(_on_item_graph_updated)
	if clear_presenters:
		for player_id_value in _sorted_binding_ids():
			var binding: Dictionary = _bindings[player_id_value]
			var presenter = binding.get("presenter")
			if presenter != null and presenter.has_method("clear"):
				presenter.clear()
	_bindings.clear()
	_runtime = null
	_last_canonical_checksum = ""
	return _store(_success({"stopped": true, "cleared_presenters": clear_presenters}))


func bind_presenter(logical_player_id: String, presenter) -> Dictionary:
	if _runtime == null:
		return _failure(RESULT_NOT_CONFIGURED)
	var player_id := logical_player_id.strip_edges().to_lower()
	if player_id.is_empty():
		return _failure(RESULT_PLAYER_ID_REQUIRED)
	if presenter == null or not presenter.has_method("apply_snapshot"):
		return _failure(RESULT_INVALID_PRESENTER, {"logical_player_id": player_id})
	if _bindings.has(player_id):
		return _failure("CH9_5_PRESENTER_ALREADY_BOUND", {"logical_player_id": player_id})
	_bindings[player_id] = {
		"presenter": presenter,
		"projection": EquipmentProjection.new(),
		"last_state_fingerprint": "",
		"last_revision": -1,
		"apply_count": 0,
		"change_count": 0,
	}
	var canonical: Dictionary = _runtime.get_item_graph_snapshot()
	if canonical.is_empty():
		return _success({"logical_player_id": player_id, "pending_snapshot": true})
	var applied: Dictionary = _apply_binding(player_id, canonical)
	if not bool(applied.get("success", false)):
		# A presenter may be bound before that logical player has joined and before
		# its canonical equipment container exists. Keep the binding alive so the
		# next Item Graph update can satisfy it.
		if String(applied.get("cause_code", "")) == EquipmentProjection.RESULT_EQUIPMENT_CONTAINER_MISSING:
			return _success({"logical_player_id": player_id, "pending_player": true})
		_bindings.erase(player_id)
		return applied
	return applied


func unbind_presenter(logical_player_id: String, clear_presenter: bool = false) -> Dictionary:
	var player_id := logical_player_id.strip_edges().to_lower()
	if not _bindings.has(player_id):
		return _success({"logical_player_id": player_id, "already_unbound": true})
	var binding: Dictionary = _bindings[player_id]
	var presenter = binding.get("presenter")
	if clear_presenter and presenter != null and presenter.has_method("clear"):
		presenter.clear()
	_bindings.erase(player_id)
	return _success({"logical_player_id": player_id, "cleared_presenter": clear_presenter})


func synchronize(canonical_snapshot: Dictionary = {}) -> Dictionary:
	if _runtime == null:
		return _store(_failure(RESULT_NOT_CONFIGURED))
	var canonical: Dictionary = canonical_snapshot.duplicate(true)
	if canonical.is_empty():
		canonical = _runtime.get_item_graph_snapshot()
	if canonical.is_empty():
		return _store(_success({"pending_snapshot": true, "binding_count": _bindings.size()}))
	_synchronize_calls += 1
	_last_canonical_checksum = String(canonical.get("checksum", ""))
	var applied_players: Array[String] = []
	var pending_players: Array[String] = []
	var failures: Array[Dictionary] = []
	for player_id in _sorted_binding_ids():
		var applied: Dictionary = _apply_binding(player_id, canonical)
		if bool(applied.get("success", false)):
			applied_players.append(player_id)
		elif String(applied.get("cause_code", "")) == EquipmentProjection.RESULT_EQUIPMENT_CONTAINER_MISSING:
			pending_players.append(player_id)
		else:
			failures.append(applied)
	if not failures.is_empty():
		return _store(_failure("CH9_5_EQUIPMENT_PRESENTATION_SYNC_FAILED", {
			"failures": failures,
			"applied_players": applied_players,
			"pending_players": pending_players,
		}))
	return _store(_success({
		"canonical_checksum": _last_canonical_checksum,
		"binding_count": _bindings.size(),
		"applied_players": applied_players,
		"pending_players": pending_players,
	}))


func get_binding_report(logical_player_id: String) -> Dictionary:
	var player_id := logical_player_id.strip_edges().to_lower()
	if not _bindings.has(player_id):
		return {}
	var binding: Dictionary = _bindings[player_id]
	return {
		"logical_player_id": player_id,
		"last_state_fingerprint": String(binding.get("last_state_fingerprint", "")),
		"last_revision": int(binding.get("last_revision", -1)),
		"apply_count": int(binding.get("apply_count", 0)),
		"change_count": int(binding.get("change_count", 0)),
	}


func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.network_character_equipment_presentation_coordinator.v1",
		"configured": _runtime != null,
		"binding_count": _bindings.size(),
		"last_canonical_checksum": _last_canonical_checksum,
		"signal_updates": _signal_updates,
		"synchronize_calls": _synchronize_calls,
		"projection_failures": _projection_failures,
		"presentation_failures": _presentation_failures,
		"presentation_changes": _presentation_changes,
		"presentation_reuses": _presentation_reuses,
		"owns_item_truth": false,
		"owns_transport": false,
		"owns_persistence": false,
		"presentation_only": true,
	}


func get_last_result() -> Dictionary:
	return _last_result.duplicate(true)


func _on_item_graph_updated(canonical_snapshot: Dictionary) -> void:
	_signal_updates += 1
	synchronize(canonical_snapshot)


func _apply_binding(player_id: String, canonical_snapshot: Dictionary) -> Dictionary:
	if not _bindings.has(player_id):
		return _failure("CH9_5_PRESENTATION_BINDING_MISSING", {"logical_player_id": player_id})
	var binding: Dictionary = _bindings[player_id]
	var projection: NetworkCharacterEquipmentProjection = binding.get("projection")
	var projected: Dictionary = projection.project(canonical_snapshot, player_id)
	if not bool(projected.get("success", false)):
		_projection_failures += 1
		return _failure(RESULT_PROJECTION_FAILED, {
			"logical_player_id": player_id,
			"cause": projected,
		}, String(projected.get("error_code", projected.get("code", ""))))
	var snapshot = projected.get("details", {}).get("snapshot")
	if not snapshot is CharacterEquipmentDomain.Snapshot:
		_projection_failures += 1
		return _failure(RESULT_PROJECTION_FAILED, {
			"logical_player_id": player_id,
			"cause": "INVALID_PROJECTED_SNAPSHOT_TYPE",
		})
	var presenter = binding.get("presenter")
	var presentation_value = presenter.apply_snapshot(snapshot)
	if not presentation_value is Dictionary:
		_presentation_failures += 1
		return _failure(RESULT_PRESENTATION_APPLY_FAILED, {
			"logical_player_id": player_id,
			"cause": "PRESENTER_RESULT_NOT_DICTIONARY",
		})
	var presentation: Dictionary = presentation_value
	if not bool(presentation.get("success", false)):
		_presentation_failures += 1
		return _failure(RESULT_PRESENTATION_APPLY_FAILED, {
			"logical_player_id": player_id,
			"cause": presentation,
		})
	binding["last_state_fingerprint"] = snapshot.state_fingerprint()
	binding["last_revision"] = snapshot.revision
	binding["apply_count"] = int(binding.get("apply_count", 0)) + 1
	var details: Dictionary = Dictionary(presentation.get("details", {}))
	if bool(details.get("changed", false)):
		binding["change_count"] = int(binding.get("change_count", 0)) + 1
		_presentation_changes += 1
	else:
		_presentation_reuses += 1
	_bindings[player_id] = binding
	var result := _success({
		"logical_player_id": player_id,
		"state_fingerprint": snapshot.state_fingerprint(),
		"revision": snapshot.revision,
		"equipped_item_count": snapshot.entries().size(),
		"presentation": presentation,
	})
	equipment_presentation_updated.emit(player_id, result.duplicate(true))
	return result


func _sorted_binding_ids() -> Array[String]:
	var result: Array[String] = []
	for player_id_value in _bindings.keys():
		result.append(String(player_id_value))
	result.sort()
	return result


func _store(result: Dictionary) -> Dictionary:
	_last_result = result.duplicate(true)
	return result


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "code": RESULT_OK, "error_code": "", "details": details.duplicate(true)}


func _failure(code: String, details: Dictionary = {}, cause_code: String = "") -> Dictionary:
	var result := {"success": false, "code": code, "error_code": code, "details": details.duplicate(true)}
	if not cause_code.is_empty():
		result["cause_code"] = cause_code
	return result
