extends RefCounted

const SCHEMA := "planet_simulator.predicted_item_interaction_journal.v1"
const SNAPSHOT_SCHEMA := "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1"
const DEFAULT_MAX_PENDING := 32
const DEFAULT_TIMEOUT_MS := 8000
const MIN_TIMEOUT_MS := 100
const MAX_TIMEOUT_MS := 120000

const PREDICTABLE_COMMANDS: Array[String] = [
	"item.pickup",
	"item.drop",
	"item.place",
	"item.transfer",
]

var _configured := false
var _local_player_id := ""
var _max_pending := DEFAULT_MAX_PENDING
var _timeout_ms := DEFAULT_TIMEOUT_MS
var _authoritative_snapshot: Dictionary = {}
var _presentation_snapshot: Dictionary = {}
var _pending: Array[Dictionary] = []
var _resolved_prediction_ids: Dictionary = {}

var _submitted := 0
var _duplicate_submissions := 0
var _confirmed := 0
var _confirmed_by_snapshot := 0
var _rolled_back := 0
var _timed_out := 0
var _rebases := 0
var _rebase_rejections := 0
var _stale_authoritative_dropped := 0
var _authoritative_conflicts := 0
var _projection_failures := 0
var _last_error_code := ""


func setup(local_player_id: String, options: Dictionary = {}) -> Dictionary:
	if _configured:
		return _failure("ITEM_PREDICTION_JOURNAL_ALREADY_CONFIGURED")
	_local_player_id = local_player_id.strip_edges().to_lower()
	_max_pending = int(options.get("max_pending", DEFAULT_MAX_PENDING))
	_timeout_ms = int(options.get("timeout_ms", DEFAULT_TIMEOUT_MS))
	if (
		_local_player_id.is_empty()
		or _max_pending < 1
		or _max_pending > 4096
		or _timeout_ms < MIN_TIMEOUT_MS
		or _timeout_ms > MAX_TIMEOUT_MS
	):
		return _failure("INVALID_ITEM_PREDICTION_JOURNAL_CONFIG")
	_configured = true
	return _success({"schema": SCHEMA, "config": get_config()})


func reset() -> void:
	_authoritative_snapshot.clear()
	_presentation_snapshot.clear()
	_pending.clear()
	_resolved_prediction_ids.clear()
	_last_error_code = ""


func supports_command(command_type: String) -> bool:
	return command_type in PREDICTABLE_COMMANDS


func adopt_authoritative(snapshot: Dictionary, now_ms: int = -1) -> Dictionary:
	if not _configured:
		return _failure("ITEM_PREDICTION_JOURNAL_NOT_CONFIGURED")
	var validation := _validate_authoritative_snapshot(snapshot)
	if not bool(validation.get("success", false)):
		_last_error_code = String(validation.get("error_code", "INVALID_AUTHORITATIVE_ITEM_GRAPH"))
		return validation
	if not _authoritative_snapshot.is_empty():
		var current_revision := int(_authoritative_snapshot.get("revision", -1))
		var incoming_revision := int(snapshot.get("revision", -1))
		var current_checksum := String(_authoritative_snapshot.get("checksum", ""))
		var incoming_checksum := String(snapshot.get("checksum", ""))
		if incoming_revision < current_revision:
			_stale_authoritative_dropped += 1
			return _failure("STALE_AUTHORITATIVE_ITEM_GRAPH")
		if incoming_revision == current_revision:
			if incoming_checksum == current_checksum:
				_expire_predictions(_now_ms(now_ms))
				return _success({
					"accepted": false,
					"duplicate": true,
					"presentation_snapshot": _presentation_snapshot.duplicate(true),
				})
			_authoritative_conflicts += 1
			return _failure("CONFLICTING_AUTHORITATIVE_ITEM_GRAPH_REVISION")
	_authoritative_snapshot = snapshot.duplicate(true)
	_expire_predictions(_now_ms(now_ms))
	var rebuild := _rebuild_projection(true)
	if not bool(rebuild.get("success", false)):
		_last_error_code = String(rebuild.get("error_code", "ITEM_PREDICTION_REBASE_FAILED"))
		return rebuild
	_last_error_code = ""
	return _success({
		"accepted": true,
		"duplicate": false,
		"presentation_snapshot": _presentation_snapshot.duplicate(true),
		"pending_count": _pending.size(),
	})


func begin_prediction(
	command_type: String,
	payload: Dictionary,
	prediction_id: String,
	now_ms: int = -1
) -> Dictionary:
	if not _configured:
		return _failure("ITEM_PREDICTION_JOURNAL_NOT_CONFIGURED")
	if _authoritative_snapshot.is_empty():
		return _failure("AUTHORITATIVE_ITEM_GRAPH_REQUIRED")
	var normalized_id := prediction_id.strip_edges()
	if normalized_id.is_empty():
		return _failure("ITEM_PREDICTION_ID_REQUIRED")
	if not supports_command(command_type):
		return _failure("ITEM_COMMAND_NOT_PREDICTABLE")
	_expire_predictions(_now_ms(now_ms))
	var fingerprint := _fingerprint({
		"command_type": command_type,
		"payload": payload,
		"local_player_id": _local_player_id,
	})
	var existing := _find_pending(normalized_id)
	if not existing.is_empty():
		if String(existing.get("fingerprint", "")) != fingerprint:
			return _failure("ITEM_PREDICTION_REPLAY_CONFLICT")
		_duplicate_submissions += 1
		return _success({
			"accepted": false,
			"duplicate": true,
			"prediction_id": normalized_id,
			"presentation_snapshot": _presentation_snapshot.duplicate(true),
		})
	if _resolved_prediction_ids.has(normalized_id):
		return _failure("ITEM_PREDICTION_ID_ALREADY_RESOLVED")
	if _pending.size() >= _max_pending:
		return _failure("ITEM_PREDICTION_WINDOW_FULL")
	var started_at_ms := _now_ms(now_ms)
	var precondition := _capture_precondition(command_type, payload)
	var entry := {
		"prediction_id": normalized_id,
		"command_type": command_type,
		"payload": payload.duplicate(true),
		"fingerprint": fingerprint,
		"base_revision": int(_authoritative_snapshot.get("revision", -1)),
		"base_checksum": String(_authoritative_snapshot.get("checksum", "")),
		"started_at_ms": started_at_ms,
		"deadline_ms": started_at_ms + _timeout_ms,
		"precondition": precondition,
	}
	var probe := _presentation_snapshot.duplicate(true)
	var applied := _apply_prediction(probe, entry)
	if not bool(applied.get("success", false)):
		_last_error_code = String(applied.get("error_code", "ITEM_PREDICTION_REJECTED"))
		return applied
	_pending.append(entry)
	_presentation_snapshot = probe
	_submitted += 1
	_last_error_code = ""
	return _success({
		"accepted": true,
		"duplicate": false,
		"prediction_id": normalized_id,
		"base_revision": int(entry.get("base_revision", -1)),
		"presentation_snapshot": _decorate_projection(_presentation_snapshot),
		"pending_count": _pending.size(),
	})


func resolve_prediction(
	prediction_id: String,
	result: Dictionary,
	authoritative_snapshot: Dictionary = {},
	now_ms: int = -1
) -> Dictionary:
	if not _configured:
		return _failure("ITEM_PREDICTION_JOURNAL_NOT_CONFIGURED")
	var normalized_id := prediction_id.strip_edges()
	if normalized_id.is_empty():
		return _failure("ITEM_PREDICTION_ID_REQUIRED")
	var index := _find_pending_index(normalized_id)
	if index < 0:
		if _resolved_prediction_ids.has(normalized_id):
			return _success({
				"accepted": false,
				"duplicate": true,
				"prediction_id": normalized_id,
				"presentation_snapshot": _decorate_projection(_presentation_snapshot),
			})
		return _failure("ITEM_PREDICTION_NOT_FOUND")
	var entry: Dictionary = _pending[index]
	_pending.remove_at(index)
	var success := bool(result.get("success", false))
	var resolution := "CONFIRMED" if success else "ROLLED_BACK"
	if success:
		_confirmed += 1
	else:
		_rolled_back += 1
	_resolved_prediction_ids[normalized_id] = {
		"resolution": resolution,
		"resolved_at_ms": _now_ms(now_ms),
		"error_code": String(result.get("error_code", "")),
		"fingerprint": String(entry.get("fingerprint", "")),
	}
	if not authoritative_snapshot.is_empty():
		var adopted := adopt_authoritative(authoritative_snapshot, now_ms)
		if not bool(adopted.get("success", false)):
			return adopted
	else:
		var rebuild := _rebuild_projection(false)
		if not bool(rebuild.get("success", false)):
			return rebuild
	_last_error_code = "" if success else String(result.get("error_code", "ITEM_PREDICTION_REJECTED"))
	return _success({
		"accepted": true,
		"duplicate": false,
		"prediction_id": normalized_id,
		"resolution": resolution,
		"presentation_snapshot": _decorate_projection(_presentation_snapshot),
		"pending_count": _pending.size(),
	})


func project_authoritative(snapshot: Dictionary, now_ms: int = -1) -> Dictionary:
	var adopted := adopt_authoritative(snapshot, now_ms)
	if not bool(adopted.get("success", false)):
		return adopted
	return _success({
		"presentation_snapshot": _decorate_projection(_presentation_snapshot),
		"pending_count": _pending.size(),
	})


func expire(now_ms: int = -1) -> Dictionary:
	if not _configured:
		return _failure("ITEM_PREDICTION_JOURNAL_NOT_CONFIGURED")
	var expired_ids := _expire_predictions(_now_ms(now_ms))
	return _success({
		"expired_prediction_ids": expired_ids,
		"presentation_snapshot": _decorate_projection(_presentation_snapshot),
		"pending_count": _pending.size(),
	})


func get_presentation_snapshot() -> Dictionary:
	return _decorate_projection(_presentation_snapshot)


func get_authoritative_snapshot() -> Dictionary:
	return _authoritative_snapshot.duplicate(true)


func get_pending_predictions() -> Array[Dictionary]:
	return _pending.duplicate(true)


func get_config() -> Dictionary:
	return {
		"local_player_id": _local_player_id,
		"max_pending": _max_pending,
		"timeout_ms": _timeout_ms,
		"predictable_commands": PREDICTABLE_COMMANDS.duplicate(),
	}


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": _configured,
		"local_player_id": _local_player_id,
		"authoritative_revision": int(_authoritative_snapshot.get("revision", -1)),
		"authoritative_checksum": String(_authoritative_snapshot.get("checksum", "")),
		"pending_count": _pending.size(),
		"submitted": _submitted,
		"duplicate_submissions": _duplicate_submissions,
		"confirmed": _confirmed,
		"confirmed_by_snapshot": _confirmed_by_snapshot,
		"rolled_back": _rolled_back,
		"timed_out": _timed_out,
		"rebases": _rebases,
		"rebase_rejections": _rebase_rejections,
		"stale_authoritative_dropped": _stale_authoritative_dropped,
		"authoritative_conflicts": _authoritative_conflicts,
		"projection_failures": _projection_failures,
		"last_error_code": _last_error_code,
		"config": get_config(),
	}


func _rebuild_projection(authoritative_changed: bool) -> Dictionary:
	if _authoritative_snapshot.is_empty():
		_presentation_snapshot.clear()
		return _success()
	var projected := _authoritative_snapshot.duplicate(true)
	projected.erase("prediction_overlay")
	var survivors: Array[Dictionary] = []
	for entry_value in _pending:
		var entry: Dictionary = entry_value
		if authoritative_changed and _prediction_satisfied(projected, entry):
			_confirmed_by_snapshot += 1
			_resolved_prediction_ids[String(entry.get("prediction_id", ""))] = {
				"resolution": "CONFIRMED_BY_SNAPSHOT",
				"resolved_at_ms": Time.get_ticks_msec(),
				"fingerprint": String(entry.get("fingerprint", "")),
			}
			continue
		var applied := _apply_prediction(projected, entry)
		if not bool(applied.get("success", false)):
			_rebase_rejections += 1
			_resolved_prediction_ids[String(entry.get("prediction_id", ""))] = {
				"resolution": "ROLLED_BACK_ON_REBASE",
				"resolved_at_ms": Time.get_ticks_msec(),
				"error_code": String(applied.get("error_code", "ITEM_PREDICTION_REBASE_REJECTED")),
				"fingerprint": String(entry.get("fingerprint", "")),
			}
			continue
		survivors.append(entry)
	_pending = survivors
	_presentation_snapshot = projected
	if authoritative_changed:
		_rebases += 1
	return _success({"pending_count": _pending.size()})


func _expire_predictions(now_ms: int) -> Array[String]:
	var expired: Array[String] = []
	var survivors: Array[Dictionary] = []
	for entry_value in _pending:
		var entry: Dictionary = entry_value
		if now_ms <= int(entry.get("deadline_ms", 0)):
			survivors.append(entry)
			continue
		var prediction_id := String(entry.get("prediction_id", ""))
		expired.append(prediction_id)
		_timed_out += 1
		_resolved_prediction_ids[prediction_id] = {
			"resolution": "TIMED_OUT",
			"resolved_at_ms": now_ms,
			"error_code": "ITEM_PREDICTION_TIMEOUT",
			"fingerprint": String(entry.get("fingerprint", "")),
		}
	_pending = survivors
	if not expired.is_empty():
		_rebuild_projection(false)
	return expired


func _apply_prediction(snapshot: Dictionary, entry: Dictionary) -> Dictionary:
	match String(entry.get("command_type", "")):
		"item.pickup":
			return _predict_pickup(snapshot, entry)
		"item.drop":
			return _predict_drop(snapshot, entry, false)
		"item.place":
			return _predict_drop(snapshot, entry, true)
		"item.transfer":
			return _predict_transfer(snapshot, entry)
	return _failure("ITEM_COMMAND_NOT_PREDICTABLE")


func _predict_pickup(snapshot: Dictionary, entry: Dictionary) -> Dictionary:
	var payload: Dictionary = entry.get("payload", {})
	var item_id := String(payload.get("item_id", ""))
	var item_index := _item_index(snapshot, item_id)
	if item_index < 0:
		return _failure("ITEM_NOT_FOUND")
	var items: Array = snapshot.get("items", [])
	var item: Dictionary = items[item_index]
	if String(item.get("location", {}).get("kind", "")) != "WORLD":
		return _failure("ITEM_NOT_IN_WORLD")
	item["location"] = {"kind": "INVENTORY", "player_id": _local_player_id}
	item.erase("transform")
	items[item_index] = item
	snapshot["items"] = items
	_add_to_player_inventory(snapshot, item_id)
	return _success({"item_id": item_id})


func _predict_drop(snapshot: Dictionary, entry: Dictionary, placement: bool) -> Dictionary:
	var payload: Dictionary = entry.get("payload", {})
	var item_id := String(payload.get("item_id", ""))
	var item_index := _item_index(snapshot, item_id)
	if item_index < 0:
		return _failure("ITEM_NOT_FOUND")
	var items: Array = snapshot.get("items", [])
	var source: Dictionary = items[item_index]
	var location: Dictionary = source.get("location", {})
	if not _is_local_owned_location(snapshot, item_id, location):
		return _failure("PLAYER_PERMISSION_DENIED")
	var source_quantity := int(source.get("quantity", 1))
	var requested := int(payload.get("quantity", 1 if placement else -1))
	var amount := source_quantity if requested < 0 else requested
	if placement:
		amount = 1
	if amount < 1 or amount > source_quantity:
		return _failure("INVALID_SPLIT_QUANTITY")
	var predicted_item_id := item_id
	if amount == source_quantity:
		_remove_from_location(snapshot, item_id, location)
		source["location"] = {"kind": "WORLD"}
		if payload.get("transform", {}) is Dictionary:
			source["transform"] = Dictionary(payload.get("transform", {})).duplicate(true)
		items[item_index] = source
	else:
		source["quantity"] = source_quantity - amount
		items[item_index] = source
		predicted_item_id = _temporary_item_id(String(entry.get("prediction_id", "")), "place" if placement else "drop")
		var spawned := source.duplicate(true)
		spawned["item_id"] = predicted_item_id
		spawned["quantity"] = amount
		spawned["location"] = {"kind": "WORLD"}
		spawned["mounted"] = false
		if payload.get("transform", {}) is Dictionary:
			spawned["transform"] = Dictionary(payload.get("transform", {})).duplicate(true)
		items.append(spawned)
	if placement:
		var mount_id := "mount/predicted/%s" % _prediction_token(String(entry.get("prediction_id", "")))
		for index in range(items.size()):
			if String(Dictionary(items[index]).get("item_id", "")) == predicted_item_id:
				var placed: Dictionary = Dictionary(items[index]).duplicate(true)
				placed["mount_id"] = mount_id
				items[index] = placed
				break
		var mounts: Array = snapshot.get("mounts", [])
		mounts.append({
			"mount_id": mount_id,
			"item_id": "",
			"parent_item_id": predicted_item_id,
			"socket_id": "beacon_socket",
		})
		snapshot["mounts"] = mounts
	snapshot["items"] = items
	return _success({"item_id": predicted_item_id, "temporary": predicted_item_id != item_id})


func _predict_transfer(snapshot: Dictionary, entry: Dictionary) -> Dictionary:
	var payload: Dictionary = entry.get("payload", {})
	var source_id := String(payload.get("item_id", ""))
	var source_index := _item_index(snapshot, source_id)
	if source_index < 0:
		return _failure("ITEM_NOT_FOUND")
	var items: Array = snapshot.get("items", [])
	var source: Dictionary = items[source_index]
	var source_location: Dictionary = source.get("location", {})
	if not _is_local_accessible_location(snapshot, source_id, source_location):
		return _failure("SOURCE_CONTAINER_ACCESS_DENIED")
	var source_quantity := int(source.get("quantity", 1))
	var requested := int(payload.get("quantity", -1))
	var amount := source_quantity if requested < 0 else requested
	if amount < 1 or amount > source_quantity:
		return _failure("INVALID_TRANSFER_QUANTITY")
	var target_item_id := String(payload.get("target_item_id", ""))
	if not target_item_id.is_empty():
		var target_index := _item_index(snapshot, target_item_id)
		if target_index < 0 or target_item_id == source_id:
			return _failure("STACK_TARGET_NOT_FOUND")
		var target: Dictionary = items[target_index]
		if String(target.get("definition_id", "")) != String(source.get("definition_id", "")):
			return _failure("STACK_DEFINITION_MISMATCH")
		target["quantity"] = int(target.get("quantity", 1)) + amount
		items[target_index] = target
		if amount == source_quantity:
			_remove_from_location(snapshot, source_id, source_location)
			items.remove_at(source_index)
		else:
			source["quantity"] = source_quantity - amount
			items[source_index] = source
		snapshot["items"] = items
		return _success({"item_id": target_item_id, "stacked": true})
	var target_container_id := String(payload.get("target_container_id", ""))
	var target_slot_index := int(payload.get("target_slot_index", -1))
	var moved_item_id := source_id
	var moved: Dictionary = source
	if amount < source_quantity:
		source["quantity"] = source_quantity - amount
		items[source_index] = source
		moved_item_id = _temporary_item_id(String(entry.get("prediction_id", "")), "transfer")
		moved = source.duplicate(true)
		moved["item_id"] = moved_item_id
		moved["quantity"] = amount
		items.append(moved)
	else:
		_remove_from_location(snapshot, source_id, source_location)
	var target_result := _assign_target_location(
		snapshot, moved_item_id, moved, target_container_id, target_slot_index
	)
	if not bool(target_result.get("success", false)):
		return target_result
	moved = Dictionary(target_result.get("details", {}).get("item", moved)).duplicate(true)
	var moved_index := _item_index_in_array(items, moved_item_id)
	if moved_index >= 0:
		items[moved_index] = moved
	else:
		items.append(moved)
	snapshot["items"] = items
	return _success({"item_id": moved_item_id, "temporary": moved_item_id != source_id})


func _assign_target_location(
	snapshot: Dictionary,
	item_id: String,
	item: Dictionary,
	target_container_id: String,
	target_slot_index: int
) -> Dictionary:
	if target_container_id == "inventory/%s" % _local_player_id:
		item["location"] = {"kind": "INVENTORY", "player_id": _local_player_id}
		_add_to_player_inventory(snapshot, item_id)
		return _success({"item": item})
	if target_container_id == "hotbar/%s" % _local_player_id:
		item["location"] = {"kind": "INVENTORY", "player_id": _local_player_id}
		_add_to_player_inventory(snapshot, item_id)
		var inventory := _player_inventory(snapshot)
		var hotbar: Array = inventory.get("hotbar", [])
		if target_slot_index < 0:
			target_slot_index = _first_empty_index(hotbar)
		if target_slot_index < 0:
			return _failure("CONTAINER_FULL")
		while hotbar.size() <= target_slot_index:
			hotbar.append("")
		var replaced := String(hotbar[target_slot_index])
		if not replaced.is_empty() and replaced != item_id:
			return _failure("TARGET_SLOT_OCCUPIED")
		hotbar[target_slot_index] = item_id
		inventory["hotbar"] = hotbar
		_set_player_inventory(snapshot, inventory)
		return _success({"item": item})
	var container_index := _container_index(snapshot, target_container_id)
	if container_index < 0:
		return _failure("CONTAINER_NOT_FOUND")
	var containers: Array = snapshot.get("containers", [])
	var container: Dictionary = containers[container_index]
	var slots: Array = container.get("slots", [])
	if slots.size() >= int(container.get("capacity", 0)):
		return _failure("CONTAINER_FULL")
	if target_slot_index < 0 or target_slot_index > slots.size():
		target_slot_index = slots.size()
	slots.insert(target_slot_index, item_id)
	container["slots"] = slots
	containers[container_index] = container
	snapshot["containers"] = containers
	item["location"] = {
		"kind": "CONTAINER",
		"container_id": target_container_id,
		"slot_index": target_slot_index,
	}
	return _success({"item": item})


func _prediction_satisfied(snapshot: Dictionary, entry: Dictionary) -> bool:
	var payload: Dictionary = entry.get("payload", {})
	var command_type := String(entry.get("command_type", ""))
	var item_id := String(payload.get("item_id", ""))
	var item := _item(snapshot, item_id)
	match command_type:
		"item.pickup":
			return (
				not item.is_empty()
				and String(item.get("location", {}).get("kind", "")) == "INVENTORY"
				and String(item.get("location", {}).get("player_id", "")) == _local_player_id
			)
		"item.drop", "item.place":
			if not item.is_empty() and String(item.get("location", {}).get("kind", "")) == "WORLD":
				return true
			return int(item.get("quantity", 0)) < int(Dictionary(entry.get("precondition", {})).get("source_quantity", 0))
		"item.transfer":
			var target_id := String(payload.get("target_item_id", ""))
			if not target_id.is_empty():
				var before_target := int(Dictionary(entry.get("precondition", {})).get("target_quantity", -1))
				return int(_item(snapshot, target_id).get("quantity", 0)) > before_target
			var target_container_id := String(payload.get("target_container_id", ""))
			if item.is_empty():
				return false
			var location: Dictionary = item.get("location", {})
			if target_container_id in ["inventory/%s" % _local_player_id, "hotbar/%s" % _local_player_id]:
				return String(location.get("kind", "")) == "INVENTORY" and String(location.get("player_id", "")) == _local_player_id
			return String(location.get("kind", "")) == "CONTAINER" and String(location.get("container_id", "")) == target_container_id
	return false


func _capture_precondition(command_type: String, payload: Dictionary) -> Dictionary:
	var source_id := String(payload.get("item_id", ""))
	var source := _item(_authoritative_snapshot, source_id)
	var result := {"source_quantity": int(source.get("quantity", 0))}
	if command_type == "item.transfer":
		var target_id := String(payload.get("target_item_id", ""))
		if not target_id.is_empty():
			result["target_quantity"] = int(_item(_authoritative_snapshot, target_id).get("quantity", -1))
	return result


func _remove_from_location(snapshot: Dictionary, item_id: String, location: Dictionary) -> void:
	match String(location.get("kind", "")):
		"INVENTORY":
			var player_id := String(location.get("player_id", ""))
			var inventories: Dictionary = snapshot.get("inventories", {})
			if inventories.has(player_id):
				var inventory: Dictionary = Dictionary(inventories[player_id]).duplicate(true)
				var values: Array = inventory.get("inventory", [])
				values.erase(item_id)
				inventory["inventory"] = values
				var hotbar: Array = inventory.get("hotbar", [])
				for index in range(hotbar.size()):
					if String(hotbar[index]) == item_id:
						hotbar[index] = ""
				inventory["hotbar"] = hotbar
				inventories[player_id] = inventory
				snapshot["inventories"] = inventories
		"CONTAINER":
			var container_id := String(location.get("container_id", ""))
			var index := _container_index(snapshot, container_id)
			if index >= 0:
				var containers: Array = snapshot.get("containers", [])
				var container: Dictionary = containers[index]
				var slots: Array = container.get("slots", [])
				slots.erase(item_id)
				container["slots"] = slots
				containers[index] = container
				snapshot["containers"] = containers


func _add_to_player_inventory(snapshot: Dictionary, item_id: String) -> void:
	var inventory := _player_inventory(snapshot)
	var values: Array = inventory.get("inventory", [])
	if item_id not in values:
		values.append(item_id)
	inventory["inventory"] = values
	_set_player_inventory(snapshot, inventory)


func _player_inventory(snapshot: Dictionary) -> Dictionary:
	var inventories: Dictionary = snapshot.get("inventories", {})
	return Dictionary(inventories.get(_local_player_id, {
		"inventory": [],
		"hotbar": [],
		"selected_hotbar_index": 0,
	})).duplicate(true)


func _set_player_inventory(snapshot: Dictionary, inventory: Dictionary) -> void:
	var inventories: Dictionary = snapshot.get("inventories", {})
	inventories[_local_player_id] = inventory.duplicate(true)
	snapshot["inventories"] = inventories


func _is_local_owned_location(snapshot: Dictionary, item_id: String, location: Dictionary) -> bool:
	if String(location.get("kind", "")) != "INVENTORY":
		return false
	if String(location.get("player_id", "")) != _local_player_id:
		return false
	return item_id in Array(_player_inventory(snapshot).get("inventory", []))


func _is_local_accessible_location(snapshot: Dictionary, item_id: String, location: Dictionary) -> bool:
	if _is_local_owned_location(snapshot, item_id, location):
		return true
	if String(location.get("kind", "")) != "CONTAINER":
		return false
	return String(snapshot.get("open_containers", {}).get(_local_player_id, "")) == String(location.get("container_id", ""))


func _decorate_projection(snapshot: Dictionary) -> Dictionary:
	if snapshot.is_empty():
		return {}
	var output := snapshot.duplicate(true)
	if _pending.is_empty():
		output.erase("prediction_overlay")
		return output
	var rows: Array[Dictionary] = []
	for entry_value in _pending:
		var entry: Dictionary = entry_value
		rows.append({
			"prediction_id": String(entry.get("prediction_id", "")),
			"command_type": String(entry.get("command_type", "")),
			"base_revision": int(entry.get("base_revision", -1)),
			"started_at_ms": int(entry.get("started_at_ms", 0)),
			"deadline_ms": int(entry.get("deadline_ms", 0)),
		})
	output["prediction_overlay"] = {
		"schema": "planet_simulator.predicted_item_graph_overlay.v1",
		"authoritative_revision": int(_authoritative_snapshot.get("revision", -1)),
		"authoritative_checksum": String(_authoritative_snapshot.get("checksum", "")),
		"pending": rows,
		"presentation_only": true,
	}
	return output


func _validate_authoritative_snapshot(snapshot: Dictionary) -> Dictionary:
	if String(snapshot.get("schema", "")) != SNAPSHOT_SCHEMA:
		return _failure("INVALID_AUTHORITATIVE_ITEM_GRAPH_SCHEMA")
	if (
		String(snapshot.get("authority_owner_id", "")).strip_edges().is_empty()
		or int(snapshot.get("authority_epoch", 0)) < 1
		or int(snapshot.get("revision", -1)) < 0
		or int(snapshot.get("tick", -1)) < 0
		or not snapshot.get("items", []) is Array
		or not snapshot.get("inventories", {}) is Dictionary
		or not snapshot.get("containers", []) is Array
		or not snapshot.get("mounts", []) is Array
		or not snapshot.get("open_containers", {}) is Dictionary
		or String(snapshot.get("checksum", "")).length() != 64
	):
		return _failure("INVALID_AUTHORITATIVE_ITEM_GRAPH")
	if snapshot.has("prediction_overlay"):
		return _failure("AUTHORITATIVE_ITEM_GRAPH_CONTAINS_PREDICTION_OVERLAY")
	return _success()


func _item(snapshot: Dictionary, item_id: String) -> Dictionary:
	var index := _item_index(snapshot, item_id)
	return Dictionary(Array(snapshot.get("items", []))[index]).duplicate(true) if index >= 0 else {}


func _item_index(snapshot: Dictionary, item_id: String) -> int:
	return _item_index_in_array(Array(snapshot.get("items", [])), item_id)


func _item_index_in_array(items: Array, item_id: String) -> int:
	for index in range(items.size()):
		if items[index] is Dictionary and String(Dictionary(items[index]).get("item_id", "")) == item_id:
			return index
	return -1


func _container_index(snapshot: Dictionary, container_id: String) -> int:
	var containers: Array = snapshot.get("containers", [])
	for index in range(containers.size()):
		if containers[index] is Dictionary and String(Dictionary(containers[index]).get("container_id", "")) == container_id:
			return index
	return -1


func _find_pending(prediction_id: String) -> Dictionary:
	var index := _find_pending_index(prediction_id)
	return Dictionary(_pending[index]).duplicate(true) if index >= 0 else {}


func _find_pending_index(prediction_id: String) -> int:
	for index in range(_pending.size()):
		if String(Dictionary(_pending[index]).get("prediction_id", "")) == prediction_id:
			return index
	return -1


func _temporary_item_id(prediction_id: String, suffix: String) -> String:
	return "item/predicted/%s/%s" % [_prediction_token(prediction_id), suffix]


func _prediction_token(prediction_id: String) -> String:
	return prediction_id.sha256_text().left(20)


func _first_empty_index(values: Array) -> int:
	for index in range(values.size()):
		if String(values[index]).is_empty():
			return index
	return values.size() if values.size() < 10 else -1


func _fingerprint(value: Dictionary) -> String:
	return JSON.stringify(value, "", true, true).sha256_text()


func _now_ms(override_ms: int) -> int:
	return override_ms if override_ms >= 0 else Time.get_ticks_msec()


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	_projection_failures += 1
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
