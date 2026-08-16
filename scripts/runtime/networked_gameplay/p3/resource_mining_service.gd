extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ResourceSnapshot = preload("res://scripts/runtime/networked_gameplay/p3/resource_mining_snapshot.gd")

const CATALOG_PATH := "res://config/resources/v0_resource_nodes.json"
const CATALOG_SCHEMA := "planet_simulator.resource_node_catalog.v1"
const DURABLE_SCHEMA := "planet_simulator.resource_mining_state.v1"
const REPLAY_SCHEMA := "planet_simulator.resource_mining_replay.v1"
const COMMAND_TYPE := "resource.mine"
const MINING_RANGE_M := 5.0

var _configured := false
var _authority_owner_id := ""
var _authority_epoch := 0
var _generation := 0
var _nodes: Dictionary = {}
var _ledger: Dictionary = {}
var _item_graph
var _spatial_resolver


func setup(
	authority_owner_id: String,
	authority_epoch: int,
	item_graph,
	spatial_resolver,
	options: Dictionary = {}
) -> Dictionary:
	if _configured:
		return _failure("RESOURCE_MINING_ALREADY_CONFIGURED")
	var owner := authority_owner_id.strip_edges()
	if owner.is_empty() or authority_epoch < 1:
		return _failure("INVALID_RESOURCE_MINING_AUTHORITY")
	if (
		item_graph == null
		or not item_graph.has_method("preflight_server_output")
		or not item_graph.has_method("apply_server_output")
	):
		return _failure("RESOURCE_ITEM_OUTPUT_PORT_INVALID")
	if spatial_resolver == null or not spatial_resolver.has_method("resolve_planar"):
		return _failure("RESOURCE_SPATIAL_RESOLVER_INVALID")
	var catalog_path := String(options.get("catalog_path", CATALOG_PATH)).strip_edges()
	var catalog_result := _load_catalog(catalog_path)
	if not bool(catalog_result.get("success", false)):
		return catalog_result
	_authority_owner_id = owner
	_authority_epoch = authority_epoch
	_generation = 1
	_nodes = Dictionary(catalog_result.get("details", {}).get("nodes", {})).duplicate(true)
	_ledger.clear()
	_item_graph = item_graph
	_spatial_resolver = spatial_resolver
	_configured = true
	return _success({"snapshot": create_snapshot()})


func mine(
	logical_player_id: String,
	operation_id: String,
	payload: Dictionary,
	player_position: Dictionary
) -> Dictionary:
	if not _configured:
		return _failure("RESOURCE_MINING_NOT_CONFIGURED")
	var player_id := logical_player_id.strip_edges().to_lower()
	var op := operation_id.strip_edges()
	if player_id.is_empty() or op.is_empty():
		return _failure("INVALID_RESOURCE_COMMAND")
	var fingerprint := Utils.payload_hash({
		"player": player_id,
		"command_type": COMMAND_TYPE,
		"payload": payload,
	})
	var replay := _lookup_replay(op, fingerprint)
	if not replay.is_empty():
		return replay
	if payload.size() != 2 or not payload.has("resource_node_id") or not payload.has("requested_units"):
		return _record_result(op, fingerprint, _failure("INVALID_RESOURCE_COMMAND"))
	if typeof(payload.get("resource_node_id")) != TYPE_STRING or typeof(payload.get("requested_units")) != TYPE_INT:
		return _record_result(op, fingerprint, _failure("INVALID_MINING_QUANTITY"))
	var node_id := String(payload.get("resource_node_id", "")).strip_edges().to_lower()
	var requested_units := int(payload.get("requested_units", 0))
	if node_id.is_empty() or not _nodes.has(node_id):
		return _record_result(op, fingerprint, _failure("RESOURCE_NOT_FOUND"))
	if requested_units < 1:
		return _record_result(op, fingerprint, _failure("INVALID_MINING_QUANTITY"))
	var node: Dictionary = Dictionary(_nodes[node_id]).duplicate(true)
	var remaining_units := int(node.get("remaining_units", 0))
	if remaining_units <= 0:
		return _record_result(op, fingerprint, _failure("RESOURCE_DEPLETED"))
	if requested_units > remaining_units:
		return _record_result(op, fingerprint, _failure("INVALID_MINING_QUANTITY"))

	var range_result := _validate_range(node, player_position)
	if not bool(range_result.get("success", false)):
		return _record_result(op, fingerprint, range_result)
	var output_quantity := requested_units * int(node.get("unit_item_quantity", 1))
	var output_operation_id := _output_operation_id(op)
	var preflight: Dictionary = _item_graph.preflight_server_output(
		output_operation_id,
		player_id,
		String(node.get("output_definition_id", "")),
		output_quantity,
		node_id
	)
	if not bool(preflight.get("success", false)):
		return _record_result(op, fingerprint, _failure("RESOURCE_OUTPUT_REJECTED", {
			"cause": String(preflight.get("error_code", "SERVER_OUTPUT_REJECTED")),
		}))
	var output_result: Dictionary = _item_graph.apply_server_output(
		output_operation_id,
		player_id,
		String(node.get("output_definition_id", "")),
		output_quantity,
		node_id
	)
	if not bool(output_result.get("success", false)):
		return _record_result(op, fingerprint, _failure("RESOURCE_OUTPUT_REJECTED", {
			"cause": String(output_result.get("error_code", "SERVER_OUTPUT_REJECTED")),
		}))

	# There are no fallible calls after the canonical Item Graph commit. A crash
	# before the outer aggregate durable commit loses both in-memory mutations;
	# a successful aggregate commit publishes both together.
	node["remaining_units"] = remaining_units - requested_units
	_nodes[node_id] = node
	_generation += 1
	var resource_snapshot := create_snapshot()
	var output_details: Dictionary = Dictionary(output_result.get("details", {}))
	var result := _success({
		"resource_node_id": node_id,
		"requested_units": requested_units,
		"remaining_units": int(node.get("remaining_units", 0)),
		"output_item_id": String(output_details.get("output_item_id", output_details.get("item_id", ""))),
		"output_definition_id": String(node.get("output_definition_id", "")),
		"output_quantity": output_quantity,
		"resource_generation": _generation,
		"resource_checksum": String(resource_snapshot.get("checksum", "")),
		"item_graph_revision": int(output_result.get("revision", -1)),
		"item_graph_tick": int(output_result.get("tick", -1)),
		"distance_m": float(range_result.get("details", {}).get("distance_m", 0.0)),
	})
	result["replay"] = false
	return _record_result(op, fingerprint, result)


func create_snapshot() -> Dictionary:
	if not _configured:
		return {}
	var values: Array = []
	for node in _nodes.values():
		values.append(Dictionary(node).duplicate(true))
	return ResourceSnapshot.create(_authority_owner_id, _authority_epoch, _generation, values)


func get_node(resource_node_id: String) -> Dictionary:
	var node_id := resource_node_id.strip_edges().to_lower()
	return Dictionary(_nodes[node_id]).duplicate(true) if _nodes.has(node_id) else {}


func export_durable_state() -> Dictionary:
	if not _configured:
		return {}
	var state: Dictionary = {
		"schema": DURABLE_SCHEMA,
		"snapshot": create_snapshot(),
		"checksum": "",
	}
	return Utils.finalize_json_checksum(state)


func validate_durable_state(value: Dictionary) -> Dictionary:
	if String(value.get("schema", "")) != DURABLE_SCHEMA or typeof(value.get("snapshot")) != TYPE_DICTIONARY:
		return _failure("INVALID_RESOURCE_DURABLE_STATE")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value.get("checksum", "")) != _state_checksum(value):
		return _failure("RESOURCE_DURABLE_CHECKSUM_MISMATCH")
	var snapshot: Dictionary = value.get("snapshot", {})
	var validation := ResourceSnapshot.validate(snapshot)
	if not bool(validation.get("success", false)):
		return _failure("INVALID_RESOURCE_DURABLE_SNAPSHOT", {"cause": validation})
	return _success()


func restore_durable_state(value: Dictionary) -> Dictionary:
	var validation := validate_durable_state(value)
	if not bool(validation.get("success", false)):
		return validation
	var snapshot: Dictionary = value.get("snapshot", {})
	if _configured and (
		String(snapshot.get("authority_owner_id", "")) != _authority_owner_id
		or int(snapshot.get("authority_epoch", 0)) != _authority_epoch
	):
		return _failure("RESOURCE_RECOVERY_AUTHORITY_MISMATCH")
	var staged_nodes: Dictionary = {}
	for node_value in snapshot.get("nodes", []):
		var node: Dictionary = Dictionary(node_value).duplicate(true)
		staged_nodes[String(node.get("resource_node_id", ""))] = node
	_authority_owner_id = String(snapshot.get("authority_owner_id", ""))
	_authority_epoch = int(snapshot.get("authority_epoch", 0))
	_generation = int(snapshot.get("generation", 0))
	_nodes = staged_nodes
	_configured = true
	return _success({
		"generation": _generation,
		"node_count": _nodes.size(),
		"snapshot_checksum": String(create_snapshot().get("checksum", "")),
	})


func export_replay_state() -> Dictionary:
	if not _configured:
		return {}
	var records: Dictionary = {}
	var operation_ids := _ledger.keys()
	operation_ids.sort()
	for operation_id_value in operation_ids:
		records[String(operation_id_value)] = Dictionary(_ledger[operation_id_value]).duplicate(true)
	var state: Dictionary = {
		"schema": REPLAY_SCHEMA,
		"records": records,
		"checksum": "",
	}
	return Utils.finalize_json_checksum(state)


func validate_replay_state(value: Dictionary) -> Dictionary:
	if String(value.get("schema", "")) != REPLAY_SCHEMA or typeof(value.get("records")) != TYPE_DICTIONARY:
		return _failure("INVALID_RESOURCE_REPLAY_STATE")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value.get("checksum", "")) != _state_checksum(value):
		return _failure("RESOURCE_REPLAY_CHECKSUM_MISMATCH")
	for operation_id_value in value.get("records", {}).keys():
		var entry_value = value["records"][operation_id_value]
		if String(operation_id_value).strip_edges().is_empty() or not entry_value is Dictionary:
			return _failure("INVALID_RESOURCE_REPLAY_RECORD")
		var entry: Dictionary = entry_value
		if String(entry.get("fingerprint", "")).length() != 64 or typeof(entry.get("result")) != TYPE_DICTIONARY:
			return _failure("INVALID_RESOURCE_REPLAY_RECORD")
	var safe := Utils.canonicalize(value, "$.resource_mining_replay")
	if not bool(safe.get("success", false)):
		return _failure("RESOURCE_REPLAY_NOT_JSON_SAFE")
	return _success({"operation_count": value.get("records", {}).size()})


func restore_replay_state(value: Dictionary) -> Dictionary:
	var validation := validate_replay_state(value)
	if not bool(validation.get("success", false)):
		return validation
	_ledger = Dictionary(value.get("records", {})).duplicate(true)
	return _success({"operation_count": _ledger.size()})


func has_replay_operation(operation_id: String) -> bool:
	return not operation_id.is_empty() and _ledger.has(operation_id)


func get_replay_operation_count() -> int:
	return _ledger.size()


func _validate_range(node: Dictionary, player_position: Dictionary) -> Dictionary:
	if (
		not _is_number(player_position.get("x"))
		or not _is_number(player_position.get("z"))
	):
		return _failure("RESOURCE_OUT_OF_RANGE")
	var resolved: Dictionary = _spatial_resolver.resolve_planar(Dictionary(node.get("spatial", {})))
	if not bool(resolved.get("success", false)):
		return _failure("RESOURCE_OUT_OF_RANGE", {
			"cause": String(resolved.get("error_code", "RESOURCE_SPATIAL_RESOLUTION_FAILED")),
		})
	var target: Dictionary = Dictionary(resolved.get("details", {}).get("planar_position", {}))
	if not _is_number(target.get("x")) or not _is_number(target.get("z")):
		return _failure("RESOURCE_OUT_OF_RANGE")
	var delta_x := float(target.get("x", 0.0)) - float(player_position.get("x", 0.0))
	var delta_z := float(target.get("z", 0.0)) - float(player_position.get("z", 0.0))
	var distance := sqrt(delta_x * delta_x + delta_z * delta_z)
	if distance > MINING_RANGE_M:
		return _failure("RESOURCE_OUT_OF_RANGE", {"distance_m": distance, "maximum_distance_m": MINING_RANGE_M})
	return _success({
		"distance_m": distance,
		"target_position": target.duplicate(true),
	})


func _load_catalog(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return _failure("RESOURCE_CATALOG_NOT_FOUND")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return _failure("RESOURCE_CATALOG_INVALID")
	var catalog: Dictionary = parsed
	if String(catalog.get("schema", "")) != CATALOG_SCHEMA or typeof(catalog.get("nodes")) != TYPE_ARRAY:
		return _failure("RESOURCE_CATALOG_INVALID")
	var staged: Dictionary = {}
	for node_value in catalog.get("nodes", []):
		if not node_value is Dictionary:
			return _failure("RESOURCE_CATALOG_INVALID")
		var source: Dictionary = node_value
		var node_id := String(source.get("resource_node_id", "")).strip_edges().to_lower()
		var spatial_value = source.get("spatial", {})
		if (
			node_id.is_empty()
			or staged.has(node_id)
			or String(source.get("resource_definition_id", "")).strip_edges().is_empty()
			or String(source.get("output_definition_id", "")).strip_edges().is_empty()
			or int(source.get("initial_units", 0)) < 1
			or int(source.get("unit_item_quantity", 0)) < 1
			or not spatial_value is Dictionary
		):
			return _failure("RESOURCE_CATALOG_INVALID")
		var spatial: Dictionary = spatial_value
		if (
			String(spatial.get("frame", "")) != "earth-fixed"
			or not _is_number(spatial.get("latitude_deg"))
			or not _is_number(spatial.get("longitude_deg"))
			or not _is_number(spatial.get("altitude_m"))
		):
			return _failure("RESOURCE_CATALOG_INVALID")
		staged[node_id] = {
			"resource_node_id": node_id,
			"resource_definition_id": String(source.get("resource_definition_id", "")).strip_edges().to_lower(),
			"output_definition_id": String(source.get("output_definition_id", "")).strip_edges().to_lower(),
			"remaining_units": int(source.get("initial_units", 0)),
			"unit_item_quantity": int(source.get("unit_item_quantity", 1)),
			"spatial": spatial.duplicate(true),
		}
	if staged.is_empty():
		return _failure("RESOURCE_CATALOG_EMPTY")
	return _success({"nodes": staged})


func _lookup_replay(operation_id: String, fingerprint: String) -> Dictionary:
	if not _ledger.has(operation_id):
		return {}
	var entry: Dictionary = _ledger[operation_id]
	if String(entry.get("fingerprint", "")) != fingerprint:
		return _failure("OPERATION_REPLAY_CONFLICT")
	var replay: Dictionary = Dictionary(entry.get("result", {})).duplicate(true)
	replay["replay"] = true
	var details: Dictionary = Dictionary(replay.get("details", {})).duplicate(true)
	details["replay"] = true
	replay["details"] = details
	return replay


func _record_result(operation_id: String, fingerprint: String, result: Dictionary) -> Dictionary:
	_ledger[operation_id] = {
		"fingerprint": fingerprint,
		"result": result.duplicate(true),
	}
	return result


func _output_operation_id(resource_operation_id: String) -> String:
	return "operation/p3/item-output/%s" % resource_operation_id.sha256_text().left(32)


func _state_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("checksum")
	return Utils.payload_hash(payload)


func _is_number(value) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
