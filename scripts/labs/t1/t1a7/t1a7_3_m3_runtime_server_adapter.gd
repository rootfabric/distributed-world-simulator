extends "res://scripts/labs/t1/t1a7/t1a7_m3_runtime_server_adapter.gd"

const SelectivePlannerScript = preload("res://scripts/labs/t1/t1a7/construction_runtime_selective_replication_planner.gd")

const T1A7_3_SCHEMA: String = "planet_simulator.t1a7_3_m3_runtime_server_adapter.v1"

var _selective_planner
var _last_selective_snapshot: Dictionary = {}
var _selective_mutation_plans: int = 0
var _selective_targeted_sends: int = 0
var _selective_send_failures: int = 0
var _selective_fallback_broadcasts: int = 0


func setup(config: Dictionary) -> Dictionary:
	_selective_planner = SelectivePlannerScript.new()
	var planner_setup: Dictionary = _selective_planner.configure(int(config.get("authority_epoch", 1)))
	if not bool(planner_setup.get("success", false)):
		_selective_planner = null
		return _t1a7_3_failure("T1A7_3_SELECTIVE_PLANNER_SETUP_FAILED", {"cause": planner_setup})
	var base_setup: Dictionary = super.setup(config)
	if not bool(base_setup.get("success", false)):
		_selective_planner = null
		return base_setup
	_last_selective_snapshot = create_construction_runtime_snapshot()
	return _t1a7_3_success({
		"runtime_snapshot": _last_selective_snapshot.duplicate(true),
		"selective_replication": _selective_planner.report(),
	})


func apply_runtime_interest(
	client_id: String,
	interest_revision: int,
	selected_construct_ids: Array
) -> Dictionary:
	var result: Dictionary = super.apply_runtime_interest(
		client_id, interest_revision, selected_construct_ids
	)
	if not bool(result.get("success", false)):
		return result
	if _selective_planner == null:
		return _t1a7_3_failure("T1A7_3_SELECTIVE_PLANNER_NOT_READY")
	var indexed: Dictionary = _selective_planner.update_selection(
		client_id, selected_construct_ids
	)
	if not bool(indexed.get("success", false)):
		return _t1a7_3_failure("T1A7_3_SELECTIVE_SELECTION_INDEX_FAILED", {"cause": indexed})
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["selective_index"] = Dictionary(indexed.get("details", {})).duplicate(true)
	return _t1a7_3_success(details)


func _broadcast_runtime_snapshot(reason: String) -> void:
	var current_snapshot: Dictionary = create_construction_runtime_snapshot()
	if _selective_planner == null or _last_selective_snapshot.is_empty() or current_snapshot.is_empty():
		_selective_fallback_broadcasts += 1
		super._broadcast_runtime_snapshot(reason)
		_last_selective_snapshot = current_snapshot.duplicate(true)
		return

	var active_routes: Dictionary = _active_routes_for_selected_clients(
		String(current_snapshot.get("construct_id", ""))
	)
	var plan: Dictionary = _selective_planner.plan_mutation(
		_last_selective_snapshot,
		current_snapshot,
		active_routes,
		_peer_to_player.size()
	)
	if not bool(plan.get("success", false)):
		_selective_fallback_broadcasts += 1
		super._broadcast_runtime_snapshot(reason)
		_last_selective_snapshot = current_snapshot.duplicate(true)
		return

	var plan_details: Dictionary = Dictionary(plan.get("details", {}))
	if bool(plan_details.get("replay", false)):
		_last_selective_snapshot = current_snapshot.duplicate(true)
		return
	_selective_mutation_plans += 1
	for route_value in plan_details.get("target_routes", []):
		if not route_value is Dictionary:
			continue
		var peer_id: String = String(Dictionary(route_value).get("peer_id", ""))
		if peer_id.is_empty():
			continue
		if _send_runtime_snapshot(peer_id, "SELECTIVE_%s" % reason):
			_selective_targeted_sends += 1
		else:
			_selective_send_failures += 1
	_last_selective_snapshot = current_snapshot.duplicate(true)


func _active_routes_for_selected_clients(construct_id: String) -> Dictionary:
	var routes: Dictionary = {}
	if _selective_planner == null or _runtime_interest == null:
		return routes
	for client_id_value in _selective_planner.selected_clients(construct_id):
		var client_id: String = String(client_id_value)
		var peer_id: String = String(_runtime_interest.active_peer_id(client_id))
		var session_id: String = String(_runtime_interest.active_session_id(client_id))
		if peer_id.is_empty() or session_id.is_empty():
			continue
		if not _peer_to_player.has(peer_id):
			continue
		if String(_peer_to_player.get(peer_id, "")) != client_id \
				or String(_peer_to_session.get(peer_id, "")) != session_id:
			continue
		routes[client_id] = {
			"client_id": client_id,
			"peer_id": peer_id,
			"session_id": session_id,
		}
	return routes


func get_t1a7_3_runtime_report() -> Dictionary:
	return {
		"schema": T1A7_3_SCHEMA,
		"selective_mutation_plans": _selective_mutation_plans,
		"selective_targeted_sends": _selective_targeted_sends,
		"selective_send_failures": _selective_send_failures,
		"selective_fallback_broadcasts": _selective_fallback_broadcasts,
		"planner": _selective_planner.report() if _selective_planner != null else {},
		"t1a7_2": get_t1a7_runtime_report(),
	}


static func _t1a7_3_success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _t1a7_3_failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
