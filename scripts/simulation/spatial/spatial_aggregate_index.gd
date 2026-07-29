extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const CellAddressScript = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const CellDescriptorScript = preload("res://scripts/simulation/spatial/spatial_cell_descriptor.gd")
const ShardDescriptorScript = preload("res://scripts/simulation/spatial/aggregate_shard_descriptor.gd")
const NeighbourDescriptorScript = preload("res://scripts/simulation/spatial/cell_neighbour_descriptor.gd")
const BoundarySummaryScript = preload("res://scripts/simulation/spatial/boundary_summary.gd")

var _configured: bool = false
var _cells_by_id: Dictionary = {}
var _shards_by_id: Dictionary = {}
var _cell_to_shards: Dictionary = {}
var _logical_to_shards: Dictionary = {}
var _neighbours_by_id: Dictionary = {}
var _cell_to_neighbour_ids: Dictionary = {}
var _summary_by_id: Dictionary = {}
var _latest_summary_id_by_stream: Dictionary = {}


func setup() -> Dictionary:
	if _configured:
		return _success({"replay": true})
	_configured = true
	return _success()


func register_cell(descriptor: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("SPATIAL_INDEX_NOT_CONFIGURED")
	var validation: Dictionary = CellDescriptorScript.validate(descriptor)
	if not bool(validation.get("success", false)):
		return _failure("INVALID_SPATIAL_CELL_DESCRIPTOR", validation)
	var normalized: Dictionary = CellDescriptorScript.normalize(descriptor)
	var cell_id: String = CellDescriptorScript.cell_id(normalized)
	if _cells_by_id.has(cell_id):
		if NetworkUtilsScript.canonical_json(_cells_by_id[cell_id]) == NetworkUtilsScript.canonical_json(normalized):
			return _success({"cell_id": cell_id, "replay": true})
		return _failure("SPATIAL_CELL_DESCRIPTOR_CONFLICT", {"cell_id": cell_id})
	var parent_cell_id: String = String(normalized["parent_cell_id"])
	if not parent_cell_id.is_empty():
		if not _cells_by_id.has(parent_cell_id):
			return _failure("SPATIAL_CELL_PARENT_NOT_FOUND", {"parent_cell_id": parent_cell_id})
		var parent: Dictionary = _cells_by_id[parent_cell_id]
		if String(parent["frame_id"]) != String(normalized["frame_id"]):
			return _failure("SPATIAL_CELL_PARENT_FRAME_MISMATCH")
		var child_path: Array = normalized["address"]["path"]
		var child_index: int = int(child_path[child_path.size() - 1])
		if child_index >= int(parent["child_capacity"]):
			return _failure("SPATIAL_CELL_CHILD_INDEX_EXCEEDS_PARENT_CAPACITY")
		if not _bounds_contain(parent["bounds_m"], normalized["bounds_m"]):
			return _failure("SPATIAL_CELL_CHILD_OUTSIDE_PARENT_BOUNDS")
	_cells_by_id[cell_id] = normalized
	_cell_to_shards[cell_id] = []
	_cell_to_neighbour_ids[cell_id] = []
	return _success({"cell_id": cell_id, "replay": false})


func register_neighbour(descriptor: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("SPATIAL_INDEX_NOT_CONFIGURED")
	var validation: Dictionary = NeighbourDescriptorScript.validate(descriptor)
	if not bool(validation.get("success", false)):
		return _failure("INVALID_CELL_NEIGHBOUR_DESCRIPTOR", validation)
	var copy_result: Dictionary = NetworkUtilsScript.json_round_trip(descriptor)
	if not bool(copy_result.get("success", false)):
		return _failure("CELL_NEIGHBOUR_COPY_FAILED")
	var normalized: Dictionary = copy_result["value"]
	var neighbour_id: String = String(normalized["neighbour_id"])
	if _neighbours_by_id.has(neighbour_id):
		if NetworkUtilsScript.canonical_json(_neighbours_by_id[neighbour_id]) == NetworkUtilsScript.canonical_json(normalized):
			return _success({"neighbour_id": neighbour_id, "replay": true})
		return _failure("CELL_NEIGHBOUR_DESCRIPTOR_CONFLICT")
	var source_id: String = String(normalized["source_cell_id"])
	var target_id: String = String(normalized["target_cell_id"])
	if not _cells_by_id.has(source_id) or not _cells_by_id.has(target_id):
		return _failure("CELL_NEIGHBOUR_ENDPOINT_NOT_FOUND")
	if String(normalized["relation_kind"]) == NeighbourDescriptorScript.RELATION_PARENT_CHILD:
		var source_address: Dictionary = _cells_by_id[source_id]["address"]
		var target_address: Dictionary = _cells_by_id[target_id]["address"]
		var expected_parent: Dictionary = CellAddressScript.parent(target_address)
		if String(expected_parent.get("cell_id", "")) != source_id or not CellAddressScript.is_ancestor(source_address, target_address):
			return _failure("INVALID_PARENT_CHILD_NEIGHBOUR")
	var pair_key: String = _neighbour_pair_key(source_id, target_id, String(normalized["source_boundary_key"]), String(normalized["target_boundary_key"]), bool(normalized["bidirectional"]))
	for existing in _neighbours_by_id.values():
		var existing_pair: String = _neighbour_pair_key(
			String(existing["source_cell_id"]),
			String(existing["target_cell_id"]),
			String(existing["source_boundary_key"]),
			String(existing["target_boundary_key"]),
			bool(existing["bidirectional"])
		)
		if existing_pair == pair_key:
			return _failure("CELL_NEIGHBOUR_PAIR_CONFLICT")
	_neighbours_by_id[neighbour_id] = normalized
	_append_sorted_unique(_cell_to_neighbour_ids[source_id], neighbour_id)
	if bool(normalized["bidirectional"]):
		_append_sorted_unique(_cell_to_neighbour_ids[target_id], neighbour_id)
	return _success({"neighbour_id": neighbour_id, "replay": false})


func bind_shard(descriptor: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("SPATIAL_INDEX_NOT_CONFIGURED")
	var validation: Dictionary = ShardDescriptorScript.validate(descriptor)
	if not bool(validation.get("success", false)):
		return _failure("INVALID_AGGREGATE_SHARD_DESCRIPTOR", validation)
	var normalized: Dictionary = ShardDescriptorScript.normalize(descriptor)
	var shard_id: String = String(normalized["shard_id"])
	for cell_id in normalized["cell_ids"]:
		if not _cells_by_id.has(cell_id):
			return _failure("AGGREGATE_SHARD_CELL_NOT_FOUND", {"cell_id": cell_id})
	for neighbour_shard_id in normalized["neighbour_shard_ids"]:
		if not _shards_by_id.has(neighbour_shard_id):
			return _failure("AGGREGATE_NEIGHBOUR_SHARD_NOT_FOUND", {"shard_id": neighbour_shard_id})
	if _shards_by_id.has(shard_id):
		var current: Dictionary = _shards_by_id[shard_id]
		if NetworkUtilsScript.canonical_json(current) == NetworkUtilsScript.canonical_json(normalized):
			return _success({"shard_id": shard_id, "replay": true})
		if int(normalized["descriptor_revision"]) <= int(current["descriptor_revision"]):
			return _failure("AGGREGATE_SHARD_DESCRIPTOR_STALE")
		for immutable_field in ["shard_id", "logical_aggregate_id", "aggregate_kind", "state_schema"]:
			if normalized[immutable_field] != current[immutable_field]:
				return _failure("AGGREGATE_SHARD_IDENTITY_MUTATION", {"field": immutable_field})
		var current_authority: Dictionary = current["authority_address"]
		var next_authority: Dictionary = normalized["authority_address"]
		if int(next_authority["authority_epoch"]) < int(current_authority["authority_epoch"]):
			return _failure("AGGREGATE_SHARD_AUTHORITY_EPOCH_ROLLBACK")
		if String(next_authority["authority_owner_id"]) != String(current_authority["authority_owner_id"]) and int(next_authority["authority_epoch"]) <= int(current_authority["authority_epoch"]):
			return _failure("AGGREGATE_SHARD_OWNER_CHANGE_REQUIRES_NEW_EPOCH")
		_remove_shard_mappings(current)
	_shards_by_id[shard_id] = normalized
	_add_shard_mappings(normalized)
	return _success({"shard_id": shard_id, "replay": false})


func publish_boundary_summary(summary: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("SPATIAL_INDEX_NOT_CONFIGURED")
	var validation: Dictionary = BoundarySummaryScript.validate(summary)
	if not bool(validation.get("success", false)):
		return _failure("INVALID_BOUNDARY_SUMMARY", validation)
	var copy_result: Dictionary = NetworkUtilsScript.json_round_trip(summary)
	if not bool(copy_result.get("success", false)):
		return _failure("BOUNDARY_SUMMARY_COPY_FAILED")
	var normalized: Dictionary = copy_result["value"]
	var summary_id: String = String(normalized["summary_id"])
	if _summary_by_id.has(summary_id):
		if NetworkUtilsScript.canonical_json(_summary_by_id[summary_id]) == NetworkUtilsScript.canonical_json(normalized):
			return _success({"summary_id": summary_id, "replay": true})
		return _failure("BOUNDARY_SUMMARY_ID_CONFLICT")
	var source_shard_id: String = String(normalized["source_shard_id"])
	var target_shard_id: String = String(normalized["target_shard_id"])
	if not _shards_by_id.has(source_shard_id) or not _shards_by_id.has(target_shard_id):
		return _failure("BOUNDARY_SUMMARY_SHARD_NOT_FOUND")
	if not _shards_touch(source_shard_id, target_shard_id):
		return _failure("BOUNDARY_SUMMARY_SHARDS_NOT_NEIGHBOURS")
	var stream_key: String = "%s|%s|%s|%s" % [
		source_shard_id,
		target_shard_id,
		String(normalized["boundary_id"]),
		String(normalized["summary_schema"]),
	]
	if _latest_summary_id_by_stream.has(stream_key):
		var latest: Dictionary = _summary_by_id[_latest_summary_id_by_stream[stream_key]]
		if int(normalized["to_tick"]) < int(latest["to_tick"]) or int(normalized["from_tick"]) < int(latest["to_tick"]):
			return _failure("BOUNDARY_SUMMARY_TICK_ROLLBACK")
		if int(normalized["source_revision"]) <= int(latest["source_revision"]):
			return _failure("BOUNDARY_SUMMARY_REVISION_NOT_MONOTONIC")
	_summary_by_id[summary_id] = normalized
	_latest_summary_id_by_stream[stream_key] = summary_id
	return _success({"summary_id": summary_id, "replay": false})


func get_cell_descriptor(cell_id: String) -> Dictionary:
	return _json_dictionary_copy(_cells_by_id.get(cell_id, {}))


func get_shard_descriptor(shard_id: String) -> Dictionary:
	return _json_dictionary_copy(_shards_by_id.get(shard_id, {}))


func get_shard_ids_for_cell(cell_id: String) -> Array:
	return Array(_cell_to_shards.get(cell_id, [])).duplicate()


func get_cell_ids_for_shard(shard_id: String) -> Array:
	if not _shards_by_id.has(shard_id):
		return []
	return Array(_shards_by_id[shard_id]["cell_ids"]).duplicate()


func get_shard_ids_for_logical_aggregate(logical_aggregate_id: String) -> Array:
	return Array(_logical_to_shards.get(logical_aggregate_id, [])).duplicate()


func get_authority_address_for_shard(shard_id: String) -> Dictionary:
	if not _shards_by_id.has(shard_id):
		return {}
	return _json_dictionary_copy(_shards_by_id[shard_id]["authority_address"])


func get_authority_addresses_for_cell(cell_id: String) -> Dictionary:
	var result: Dictionary = {}
	for shard_id in _cell_to_shards.get(cell_id, []):
		result[shard_id] = _json_dictionary_copy(_shards_by_id[shard_id]["authority_address"])
	return result


func get_neighbour_cell_ids(cell_id: String) -> Array:
	var result: Array = []
	for neighbour_id in _cell_to_neighbour_ids.get(cell_id, []):
		var descriptor: Dictionary = _neighbours_by_id[neighbour_id]
		if String(descriptor["source_cell_id"]) == cell_id:
			_append_sorted_unique(result, String(descriptor["target_cell_id"]))
		elif bool(descriptor["bidirectional"]) and String(descriptor["target_cell_id"]) == cell_id:
			_append_sorted_unique(result, String(descriptor["source_cell_id"]))
	return result


func get_latest_boundary_summary(
	source_shard_id: String,
	target_shard_id: String,
	boundary_id: String,
	summary_schema: String
) -> Dictionary:
	var stream_key: String = "%s|%s|%s|%s" % [source_shard_id, target_shard_id, boundary_id, summary_schema]
	if not _latest_summary_id_by_stream.has(stream_key):
		return {}
	return _json_dictionary_copy(_summary_by_id[_latest_summary_id_by_stream[stream_key]])


func get_counts() -> Dictionary:
	return {
		"cells": _cells_by_id.size(),
		"shards": _shards_by_id.size(),
		"neighbours": _neighbours_by_id.size(),
		"boundary_summaries": _summary_by_id.size(),
	}


func _add_shard_mappings(descriptor: Dictionary) -> void:
	var shard_id: String = String(descriptor["shard_id"])
	for cell_id in descriptor["cell_ids"]:
		_append_sorted_unique(_cell_to_shards[cell_id], shard_id)
	var logical_id: String = String(descriptor["logical_aggregate_id"])
	if not _logical_to_shards.has(logical_id):
		_logical_to_shards[logical_id] = []
	_append_sorted_unique(_logical_to_shards[logical_id], shard_id)


func _remove_shard_mappings(descriptor: Dictionary) -> void:
	var shard_id: String = String(descriptor["shard_id"])
	for cell_id in descriptor["cell_ids"]:
		if _cell_to_shards.has(cell_id):
			_cell_to_shards[cell_id].erase(shard_id)
	var logical_id: String = String(descriptor["logical_aggregate_id"])
	if _logical_to_shards.has(logical_id):
		_logical_to_shards[logical_id].erase(shard_id)
		if _logical_to_shards[logical_id].is_empty():
			_logical_to_shards.erase(logical_id)


func _shards_touch(source_shard_id: String, target_shard_id: String) -> bool:
	var source: Dictionary = _shards_by_id[source_shard_id]
	var target: Dictionary = _shards_by_id[target_shard_id]
	if Array(source["neighbour_shard_ids"]).has(target_shard_id) or Array(target["neighbour_shard_ids"]).has(source_shard_id):
		return true
	for source_cell_id in source["cell_ids"]:
		var neighbours: Array = get_neighbour_cell_ids(source_cell_id)
		for target_cell_id in target["cell_ids"]:
			if neighbours.has(target_cell_id):
				return true
	return false


func _bounds_contain(parent_bounds: Dictionary, child_bounds: Dictionary) -> bool:
	for index in range(3):
		if float(child_bounds["minimum_m"][index]) < float(parent_bounds["minimum_m"][index]):
			return false
		if float(child_bounds["maximum_m"][index]) > float(parent_bounds["maximum_m"][index]):
			return false
	return true


func _neighbour_pair_key(source: String, target: String, source_boundary: String, target_boundary: String, bidirectional: bool) -> String:
	if bidirectional and target < source:
		return "%s|%s|%s|%s|bi" % [target, source, target_boundary, source_boundary]
	return "%s|%s|%s|%s|%s" % [source, target, source_boundary, target_boundary, "bi" if bidirectional else "one"]


func _append_sorted_unique(target: Array, value: String) -> void:
	if not target.has(value):
		target.append(value)
		target.sort()


func _json_dictionary_copy(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY or value.is_empty():
		return {}
	var result: Dictionary = NetworkUtilsScript.json_round_trip(value)
	return Dictionary(result.get("value", {})) if bool(result.get("success", false)) else {}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
