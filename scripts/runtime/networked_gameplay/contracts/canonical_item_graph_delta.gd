extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.canonical_item_graph_delta.v1"
const SNAPSHOT_SCHEMA: String = "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1"
const VALIDATION_POLICY: String = "STRICT_JSON_INTEGER_LOWERCASE_SHA256_V1"
const FIELDS: Array[String] = [
	"schema", "authority_owner_id", "authority_epoch", "base_revision", "target_revision",
	"target_tick", "base_checksum", "target_checksum", "changes", "checksum",
]
const CHANGE_FIELDS: Array[String] = [
	"items_upsert", "items_removed",
	"inventories_upsert", "inventories_removed",
	"containers_upsert", "containers_removed",
	"mounts_upsert", "mounts_removed",
	"open_containers_upsert", "open_containers_removed",
	"playable_sandbox",
]


static func create(base_snapshot: Dictionary, target_snapshot: Dictionary) -> Dictionary:
	var base_check: Dictionary = validate_snapshot(base_snapshot)
	if not bool(base_check.get("success", false)):
		return _failure("INVALID_BASE_ITEM_GRAPH_SNAPSHOT", {"cause": base_check})
	var target_check: Dictionary = validate_snapshot(target_snapshot)
	if not bool(target_check.get("success", false)):
		return _failure("INVALID_TARGET_ITEM_GRAPH_SNAPSHOT", {"cause": target_check})
	if String(base_snapshot.get("authority_owner_id", "")) != String(target_snapshot.get("authority_owner_id", "")):
		return _failure("ITEM_GRAPH_DELTA_OWNER_MISMATCH")
	if int(base_snapshot.get("authority_epoch", 0)) != int(target_snapshot.get("authority_epoch", 0)):
		return _failure("ITEM_GRAPH_DELTA_EPOCH_MISMATCH")
	if int(target_snapshot.get("revision", -1)) <= int(base_snapshot.get("revision", -1)):
		return _failure("ITEM_GRAPH_DELTA_REVISION_NOT_ADVANCED")
	var changes: Dictionary = {
		"items_upsert": [], "items_removed": [],
		"inventories_upsert": {}, "inventories_removed": [],
		"containers_upsert": [], "containers_removed": [],
		"mounts_upsert": [], "mounts_removed": [],
		"open_containers_upsert": {}, "open_containers_removed": [],
		"playable_sandbox": bool(target_snapshot.get("playable_sandbox", false)),
	}
	_apply_array_diff(changes, "items", "item_id", base_snapshot, target_snapshot)
	_apply_map_diff(changes, "inventories", base_snapshot, target_snapshot)
	_apply_array_diff(changes, "containers", "container_id", base_snapshot, target_snapshot)
	_apply_array_diff(changes, "mounts", "mount_id", base_snapshot, target_snapshot)
	_apply_map_diff(changes, "open_containers", base_snapshot, target_snapshot)
	var body: Dictionary = {
		"schema": SCHEMA,
		"authority_owner_id": String(target_snapshot.get("authority_owner_id", "")),
		"authority_epoch": int(target_snapshot.get("authority_epoch", 0)),
		"base_revision": int(base_snapshot.get("revision", -1)),
		"target_revision": int(target_snapshot.get("revision", -1)),
		"target_tick": int(target_snapshot.get("tick", -1)),
		"base_checksum": String(base_snapshot.get("checksum", "")),
		"target_checksum": String(target_snapshot.get("checksum", "")),
		"changes": changes,
	}
	body["checksum"] = Utils.payload_hash(body)
	return _success({"delta": body})


static func apply(base_snapshot: Dictionary, delta: Dictionary) -> Dictionary:
	var base_check: Dictionary = validate_snapshot(base_snapshot)
	if not bool(base_check.get("success", false)):
		return _failure("INVALID_BASE_ITEM_GRAPH_SNAPSHOT", {"cause": base_check})
	var delta_check: Dictionary = validate(delta)
	if not bool(delta_check.get("success", false)):
		return delta_check
	if String(base_snapshot.get("authority_owner_id", "")) != String(delta.get("authority_owner_id", "")):
		return _failure("ITEM_GRAPH_DELTA_OWNER_MISMATCH")
	if int(base_snapshot.get("authority_epoch", 0)) != int(delta.get("authority_epoch", 0)):
		return _failure("ITEM_GRAPH_DELTA_EPOCH_MISMATCH")
	if int(base_snapshot.get("revision", -1)) != int(delta.get("base_revision", -2)):
		return _failure("ITEM_GRAPH_DELTA_BASE_REVISION_MISMATCH")
	if String(base_snapshot.get("checksum", "")) != String(delta.get("base_checksum", "")):
		return _failure("ITEM_GRAPH_DELTA_BASE_CHECKSUM_MISMATCH")
	var next: Dictionary = base_snapshot.duplicate(true)
	var changes: Dictionary = delta.get("changes", {})
	next["items"] = _apply_array_changes(
		Array(next.get("items", [])), "item_id",
		Array(changes.get("items_upsert", [])), Array(changes.get("items_removed", []))
	)
	next["inventories"] = _apply_map_changes(
		Dictionary(next.get("inventories", {})), Dictionary(changes.get("inventories_upsert", {})),
		Array(changes.get("inventories_removed", []))
	)
	next["containers"] = _apply_array_changes(
		Array(next.get("containers", [])), "container_id",
		Array(changes.get("containers_upsert", [])), Array(changes.get("containers_removed", []))
	)
	next["mounts"] = _apply_array_changes(
		Array(next.get("mounts", [])), "mount_id",
		Array(changes.get("mounts_upsert", [])), Array(changes.get("mounts_removed", []))
	)
	next["open_containers"] = _apply_map_changes(
		Dictionary(next.get("open_containers", {})), Dictionary(changes.get("open_containers_upsert", {})),
		Array(changes.get("open_containers_removed", []))
	)
	if bool(changes.get("playable_sandbox", false)):
		next["playable_sandbox"] = true
	else:
		next.erase("playable_sandbox")
	next["revision"] = int(delta.get("target_revision", -1))
	next["tick"] = int(delta.get("target_tick", -1))
	next.erase("checksum")
	var computed_checksum: String = Utils.payload_hash(next)
	if computed_checksum != String(delta.get("target_checksum", "")):
		return _failure("ITEM_GRAPH_DELTA_TARGET_CHECKSUM_MISMATCH", {
			"computed": computed_checksum,
			"expected": String(delta.get("target_checksum", "")),
		})
	next["checksum"] = computed_checksum
	return _success({"snapshot": next})


static func validate(delta: Dictionary) -> Dictionary:
	var exact: Dictionary = Utils.validate_exact_fields(delta, FIELDS)
	if not bool(exact.get("success", false)):
		return _failure("ITEM_GRAPH_DELTA_FIELD_SET_MISMATCH")
	if String(delta.get("schema", "")) != SCHEMA:
		return _failure("INVALID_ITEM_GRAPH_DELTA_SCHEMA")
	if String(delta.get("authority_owner_id", "")).strip_edges().is_empty() \
		or not Utils.is_json_integer(delta.get("authority_epoch")) \
		or int(delta.get("authority_epoch", 0)) < 1:
		return _failure("INVALID_ITEM_GRAPH_DELTA_AUTHORITY")
	if not Utils.is_json_integer(delta.get("base_revision")) \
		or not Utils.is_json_integer(delta.get("target_revision")) \
		or int(delta.get("base_revision", -1)) < 0 \
		or int(delta.get("target_revision", -1)) <= int(delta.get("base_revision", -1)):
		return _failure("INVALID_ITEM_GRAPH_DELTA_REVISION")
	if not Utils.is_json_integer(delta.get("target_tick")) or int(delta.get("target_tick", -1)) < 0:
		return _failure("INVALID_ITEM_GRAPH_DELTA_TICK")
	for checksum_field in ["base_checksum", "target_checksum", "checksum"]:
		if not _valid_sha256(String(delta.get(checksum_field, ""))):
			return _failure("INVALID_ITEM_GRAPH_DELTA_CHECKSUM")
	if not delta.get("changes") is Dictionary:
		return _failure("INVALID_ITEM_GRAPH_DELTA_CHANGES")
	var changes: Dictionary = delta.get("changes", {})
	var changes_exact: Dictionary = Utils.validate_exact_fields(changes, CHANGE_FIELDS)
	if not bool(changes_exact.get("success", false)):
		return _failure("ITEM_GRAPH_DELTA_CHANGE_FIELD_SET_MISMATCH")
	for array_field in [
		"items_upsert", "items_removed", "inventories_removed", "containers_upsert",
		"containers_removed", "mounts_upsert", "mounts_removed", "open_containers_removed",
	]:
		if not changes.get(array_field) is Array:
			return _failure("INVALID_ITEM_GRAPH_DELTA_CHANGE_ARRAY", {"field": array_field})
	for map_field in ["inventories_upsert", "open_containers_upsert"]:
		if not changes.get(map_field) is Dictionary:
			return _failure("INVALID_ITEM_GRAPH_DELTA_CHANGE_MAP", {"field": map_field})
	if typeof(changes.get("playable_sandbox")) != TYPE_BOOL:
		return _failure("INVALID_ITEM_GRAPH_DELTA_SANDBOX_FLAG")
	var copy: Dictionary = delta.duplicate(true)
	var checksum: String = String(copy.get("checksum", ""))
	copy.erase("checksum")
	if checksum != Utils.payload_hash(copy):
		return _failure("ITEM_GRAPH_DELTA_CHECKSUM_MISMATCH")
	return _success()


static func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	if String(snapshot.get("schema", "")) != SNAPSHOT_SCHEMA:
		return _failure("INVALID_ITEM_GRAPH_SNAPSHOT_SCHEMA")
	if String(snapshot.get("authority_owner_id", "")).strip_edges().is_empty() \
		or not Utils.is_json_integer(snapshot.get("authority_epoch")) \
		or int(snapshot.get("authority_epoch", 0)) < 1:
		return _failure("INVALID_ITEM_GRAPH_SNAPSHOT_AUTHORITY")
	if not Utils.is_json_integer(snapshot.get("revision")) \
		or not Utils.is_json_integer(snapshot.get("tick")) \
		or int(snapshot.get("revision", -1)) < 0 \
		or int(snapshot.get("tick", -1)) < 0:
		return _failure("INVALID_ITEM_GRAPH_SNAPSHOT_REVISION")
	for field in ["items", "containers", "mounts"]:
		if not snapshot.get(field) is Array:
			return _failure("INVALID_ITEM_GRAPH_SNAPSHOT_ARRAY", {"field": field})
	for field in ["inventories", "open_containers"]:
		if not snapshot.get(field) is Dictionary:
			return _failure("INVALID_ITEM_GRAPH_SNAPSHOT_MAP", {"field": field})
	var copy: Dictionary = snapshot.duplicate(true)
	var checksum: String = String(copy.get("checksum", ""))
	copy.erase("checksum")
	if not _valid_sha256(checksum) or checksum != Utils.payload_hash(copy):
		return _failure("ITEM_GRAPH_SNAPSHOT_CHECKSUM_MISMATCH")
	return _success()


static func _valid_sha256(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for index in range(value.length()):
		var character: String = value.substr(index, 1)
		if not "0123456789abcdef".contains(character):
			return false
	return true


static func _apply_array_diff(changes: Dictionary, field: String, id_field: String, base_snapshot: Dictionary, target_snapshot: Dictionary) -> void:
	var base_map: Dictionary = _array_to_map(Array(base_snapshot.get(field, [])), id_field)
	var target_map: Dictionary = _array_to_map(Array(target_snapshot.get(field, [])), id_field)
	var upsert: Array = []
	var removed: Array = []
	var target_keys: Array = target_map.keys()
	target_keys.sort()
	for key_value in target_keys:
		var key: String = String(key_value)
		if not base_map.has(key) or base_map[key] != target_map[key]:
			upsert.append(Dictionary(target_map[key]).duplicate(true))
	var base_keys: Array = base_map.keys()
	base_keys.sort()
	for key_value in base_keys:
		var key: String = String(key_value)
		if not target_map.has(key):
			removed.append(key)
	changes["%s_upsert" % field] = upsert
	changes["%s_removed" % field] = removed


static func _apply_map_diff(changes: Dictionary, field: String, base_snapshot: Dictionary, target_snapshot: Dictionary) -> void:
	var base_map: Dictionary = Dictionary(base_snapshot.get(field, {}))
	var target_map: Dictionary = Dictionary(target_snapshot.get(field, {}))
	var upsert: Dictionary = {}
	var removed: Array = []
	var target_keys: Array = target_map.keys()
	target_keys.sort()
	for key_value in target_keys:
		var key: String = String(key_value)
		if not base_map.has(key) or base_map[key] != target_map[key]:
			var value = target_map[key]
			upsert[key] = Dictionary(value).duplicate(true) if value is Dictionary else value
	var base_keys: Array = base_map.keys()
	base_keys.sort()
	for key_value in base_keys:
		var key: String = String(key_value)
		if not target_map.has(key):
			removed.append(key)
	changes["%s_upsert" % field] = upsert
	changes["%s_removed" % field] = removed


static func _apply_array_changes(base: Array, id_field: String, upsert: Array, removed: Array) -> Array:
	var values: Dictionary = _array_to_map(base, id_field)
	for id_value in removed:
		values.erase(String(id_value))
	for row_value in upsert:
		if row_value is Dictionary:
			var row: Dictionary = row_value
			values[String(row.get(id_field, ""))] = row.duplicate(true)
	var keys: Array = values.keys()
	keys.sort()
	var result: Array = []
	for key_value in keys:
		result.append(Dictionary(values[key_value]).duplicate(true))
	return result


static func _apply_map_changes(base: Dictionary, upsert: Dictionary, removed: Array) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	for key_value in removed:
		result.erase(String(key_value))
	var keys: Array = upsert.keys()
	keys.sort()
	for key_value in keys:
		var key: String = String(key_value)
		var value = upsert[key]
		result[key] = Dictionary(value).duplicate(true) if value is Dictionary else value
	return result


static func _array_to_map(values: Array, id_field: String) -> Dictionary:
	var result: Dictionary = {}
	for row_value in values:
		if row_value is Dictionary:
			var row: Dictionary = row_value
			var key: String = String(row.get(id_field, ""))
			if not key.is_empty():
				result[key] = row.duplicate(true)
	return result


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
