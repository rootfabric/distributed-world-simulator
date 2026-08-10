extends RefCounted

const SnapshotScript = preload("res://scripts/runtime/networked_gameplay/contracts/construction_runtime_snapshot.gd")

const SCHEMA: String = "planet_simulator.construction_runtime_selective_replication_planner.v1"

var _configured: bool = false
var _authority_epoch: int = 0
var _constructs_by_client_id: Dictionary = {}
var _clients_by_construct_id: Dictionary = {}
var _selection_updates: int = 0
var _selection_replays: int = 0
var _plans: int = 0
var _plan_replays: int = 0
var _dirty_runtime_ids_total: int = 0
var _targeted_deliveries: int = 0
var _avoided_peer_deliveries: int = 0
var _plan_failures: int = 0


func configure(authority_epoch: int) -> Dictionary:
	if _configured:
		return _failure("T1A7_3_REPLICATION_PLANNER_ALREADY_CONFIGURED")
	if authority_epoch < 1:
		return _failure("T1A7_3_REPLICATION_AUTHORITY_EPOCH_INVALID")
	_authority_epoch = authority_epoch
	_constructs_by_client_id.clear()
	_clients_by_construct_id.clear()
	_configured = true
	return _success({"authority_epoch": _authority_epoch})


func update_selection(client_id: String, selected_construct_ids: Array) -> Dictionary:
	if not _configured:
		return _failure("T1A7_3_REPLICATION_PLANNER_NOT_CONFIGURED")
	var client: String = client_id.strip_edges().to_lower()
	if client.is_empty():
		return _failure("T1A7_3_REPLICATION_CLIENT_ID_REQUIRED")
	var normalized_result: Dictionary = _normalize_ids(selected_construct_ids)
	if not bool(normalized_result.get("success", false)):
		return normalized_result
	var normalized: Array = Array(Dictionary(normalized_result.get("details", {})).get("ids", [])).duplicate()
	var previous: Array = Array(_constructs_by_client_id.get(client, [])).duplicate()
	if previous == normalized:
		_selection_replays += 1
		return _success({"replay": true, "client_id": client, "selected_construct_ids": normalized})

	for construct_id_value in previous:
		var construct_id: String = String(construct_id_value)
		if normalized.has(construct_id):
			continue
		var clients: Dictionary = Dictionary(_clients_by_construct_id.get(construct_id, {})).duplicate()
		clients.erase(client)
		if clients.is_empty():
			_clients_by_construct_id.erase(construct_id)
		else:
			_clients_by_construct_id[construct_id] = clients

	for construct_id_value in normalized:
		var construct_id: String = String(construct_id_value)
		var clients: Dictionary = Dictionary(_clients_by_construct_id.get(construct_id, {})).duplicate()
		clients[client] = true
		_clients_by_construct_id[construct_id] = clients

	_constructs_by_client_id[client] = normalized.duplicate()
	_selection_updates += 1
	return _success({
		"replay": false,
		"client_id": client,
		"selected_construct_ids": normalized.duplicate(),
	})


func selected_clients(construct_id: String) -> Array:
	var construct: String = construct_id.strip_edges().to_lower()
	var ids: Array = Dictionary(_clients_by_construct_id.get(construct, {})).keys()
	ids.sort()
	return ids


func plan_mutation(
	previous_snapshot: Dictionary,
	current_snapshot: Dictionary,
	active_routes_by_client: Dictionary,
	total_active_peer_count: int
) -> Dictionary:
	if not _configured:
		return _plan_failure("T1A7_3_REPLICATION_PLANNER_NOT_CONFIGURED")
	var current_validation: Dictionary = SnapshotScript.validate(current_snapshot)
	if not bool(current_validation.get("success", false)):
		return _plan_failure("T1A7_3_CURRENT_RUNTIME_SNAPSHOT_INVALID", {"cause": current_validation})
	var previous_validation: Dictionary = SnapshotScript.validate(previous_snapshot)
	if not bool(previous_validation.get("success", false)):
		return _plan_failure("T1A7_3_PREVIOUS_RUNTIME_SNAPSHOT_INVALID", {"cause": previous_validation})
	if int(current_snapshot.get("authority_epoch", 0)) != _authority_epoch \
			or int(previous_snapshot.get("authority_epoch", 0)) != _authority_epoch:
		return _plan_failure("T1A7_3_REPLICATION_AUTHORITY_EPOCH_MISMATCH")
	var construct_id: String = String(current_snapshot.get("construct_id", ""))
	if String(previous_snapshot.get("construct_id", "")) != construct_id:
		return _plan_failure("T1A7_3_REPLICATION_CONSTRUCT_MISMATCH")

	var previous_revision: int = int(previous_snapshot.get("revision", -1))
	var current_revision: int = int(current_snapshot.get("revision", -1))
	if current_revision < previous_revision:
		return _plan_failure("T1A7_3_REPLICATION_STALE_RUNTIME_REVISION")
	if current_revision == previous_revision:
		if String(current_snapshot.get("state_checksum", "")) != String(previous_snapshot.get("state_checksum", "")):
			return _plan_failure("T1A7_3_REPLICATION_SAME_REVISION_MUTATION")
		_plan_replays += 1
		return _success({
			"replay": true,
			"construct_id": construct_id,
			"revision": current_revision,
			"dirty_runtime_ids": [],
			"target_routes": [],
			"target_count": 0,
			"avoided_peer_deliveries": 0,
		})

	var dirty_runtime_ids: Array = _dirty_runtime_ids(
		Dictionary(previous_snapshot.get("runtime_state", {})),
		Dictionary(current_snapshot.get("runtime_state", {}))
	)
	if dirty_runtime_ids.is_empty():
		return _plan_failure("T1A7_3_RUNTIME_REVISION_ADVANCED_WITHOUT_DIRTY_SUBJECT")

	var routes: Array = []
	for client_id_value in selected_clients(construct_id):
		var client_id: String = String(client_id_value)
		var route_value = active_routes_by_client.get(client_id, {})
		if not route_value is Dictionary:
			continue
		var route: Dictionary = Dictionary(route_value)
		var peer_id: String = String(route.get("peer_id", "")).strip_edges().to_lower()
		var session_id: String = String(route.get("session_id", "")).strip_edges().to_lower()
		if peer_id.is_empty() or session_id.is_empty():
			continue
		routes.append({
			"client_id": client_id,
			"peer_id": peer_id,
			"session_id": session_id,
		})
	routes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("client_id", "")) < String(b.get("client_id", "")))

	var target_count: int = routes.size()
	var avoided: int = maxi(total_active_peer_count - target_count, 0)
	_plans += 1
	_dirty_runtime_ids_total += dirty_runtime_ids.size()
	_targeted_deliveries += target_count
	_avoided_peer_deliveries += avoided
	return _success({
		"replay": false,
		"construct_id": construct_id,
		"revision": current_revision,
		"dirty_runtime_ids": dirty_runtime_ids,
		"selected_client_count": selected_clients(construct_id).size(),
		"target_routes": routes,
		"target_count": target_count,
		"avoided_peer_deliveries": avoided,
	})


func report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"authority_epoch": _authority_epoch,
		"client_selection_count": _constructs_by_client_id.size(),
		"indexed_construct_count": _clients_by_construct_id.size(),
		"selection_updates": _selection_updates,
		"selection_replays": _selection_replays,
		"plans": _plans,
		"plan_replays": _plan_replays,
		"dirty_runtime_ids_total": _dirty_runtime_ids_total,
		"targeted_deliveries": _targeted_deliveries,
		"avoided_peer_deliveries": _avoided_peer_deliveries,
		"plan_failures": _plan_failures,
	}


func _dirty_runtime_ids(previous_state: Dictionary, current_state: Dictionary) -> Array:
	var previous_by_id: Dictionary = _subjects_by_id(previous_state)
	var current_by_id: Dictionary = _subjects_by_id(current_state)
	var union: Dictionary = {}
	for runtime_id in previous_by_id.keys():
		union[String(runtime_id)] = true
	for runtime_id in current_by_id.keys():
		union[String(runtime_id)] = true
	var ids: Array = union.keys()
	ids.sort()
	var dirty: Array = []
	for runtime_id_value in ids:
		var runtime_id: String = String(runtime_id_value)
		var before: Dictionary = Dictionary(previous_by_id.get(runtime_id, {}))
		var after: Dictionary = Dictionary(current_by_id.get(runtime_id, {}))
		if before.is_empty() or after.is_empty() \
				or String(before.get("checksum", "")) != String(after.get("checksum", "")):
			dirty.append(runtime_id)
	return dirty


func _subjects_by_id(state: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for subject_value in state.get("subjects", []):
		if subject_value is Dictionary:
			var subject: Dictionary = Dictionary(subject_value)
			out[String(subject.get("runtime_id", ""))] = subject
	return out


func _normalize_ids(values: Array) -> Dictionary:
	var seen: Dictionary = {}
	var normalized: Array[String] = []
	for value in values:
		var text: String = String(value).strip_edges().to_lower()
		if text.is_empty() or not text.begins_with("construct/"):
			return _failure("T1A7_3_REPLICATION_CONSTRUCT_ID_INVALID")
		if not seen.has(text):
			seen[text] = true
			normalized.append(text)
	normalized.sort()
	return _success({"ids": normalized})


func _plan_failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	_plan_failures += 1
	return _failure(error_code, details)


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
