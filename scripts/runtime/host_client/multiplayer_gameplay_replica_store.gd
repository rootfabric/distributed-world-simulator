extends RefCounted

const SnapshotContract = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")
const DeltaContract = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_delta.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.multiplayer_gameplay_replica_store.v1"

var _snapshot: Dictionary = {}
var _snapshot_deliveries := 0
var _delta_deliveries := 0
var _replays := 0


func accept_snapshot(snapshot: Dictionary) -> Dictionary:
	var normalized: Dictionary = SnapshotContract.Wire.stringify_dictionary_keys(snapshot)
	var validation := SnapshotContract.validate(normalized)
	snapshot = normalized
	if not bool(validation.get("success", false)):
		return validation
	if not _snapshot.is_empty():
		if String(snapshot.get("authority_owner_id", "")) != String(_snapshot.get("authority_owner_id", "")) or int(snapshot.get("authority_epoch", 0)) != int(_snapshot.get("authority_epoch", 0)):
			return _failure("MULTIPLAYER_AUTHORITY_MISMATCH")
		if int(snapshot.get("revision", 0)) < int(_snapshot.get("revision", 0)):
			return _failure("MULTIPLAYER_REVISION_ROLLBACK")
		if int(snapshot.get("revision", 0)) == int(_snapshot.get("revision", 0)):
			if String(snapshot.get("checksum", "")) != String(_snapshot.get("checksum", "")):
				return _failure("MULTIPLAYER_SAME_REVISION_MUTATION")
			_replays += 1
			return _success({"replay": true})
	_snapshot = snapshot.duplicate(true)
	_snapshot_deliveries += 1
	return _success({"replay": false})


func accept_delta(delta: Dictionary) -> Dictionary:
	var normalized: Dictionary = DeltaContract.Wire.stringify_dictionary_keys(delta)
	var validation := DeltaContract.validate(normalized)
	delta = normalized
	if not bool(validation.get("success", false)):
		return validation
	if _snapshot.is_empty():
		return _failure("MULTIPLAYER_SNAPSHOT_REQUIRED")
	if String(delta.get("authority_owner_id", "")) != String(_snapshot.get("authority_owner_id", "")) or int(delta.get("authority_epoch", 0)) != int(_snapshot.get("authority_epoch", 0)):
		return _failure("MULTIPLAYER_AUTHORITY_MISMATCH")
	var current_revision := int(_snapshot.get("revision", 0))
	var base_revision := int(delta.get("base_revision", -1))
	var target_revision := int(delta.get("target_revision", -1))
	if target_revision == current_revision and String(delta.get("target_checksum", "")) == String(_snapshot.get("checksum", "")):
		_replays += 1
		return _success({"replay": true})
	if base_revision != current_revision:
		return _failure("MULTIPLAYER_DELTA_BASE_MISMATCH")
	var next_snapshot := _snapshot.duplicate(true)
	var player: Dictionary = delta.get("player", {})
	if not player.is_empty():
		var replaced := false
		for index in range(next_snapshot.get("players", []).size()):
			if String(next_snapshot["players"][index].get("logical_player_id", "")) == String(player.get("logical_player_id", "")):
				next_snapshot["players"][index] = player.duplicate(true)
				replaced = true
				break
		if not replaced:
			next_snapshot["players"].append(player.duplicate(true))
		next_snapshot["players"].sort_custom(func(a, b): return String(a.get("logical_player_id", "")) < String(b.get("logical_player_id", "")))
	var shared_item: Dictionary = delta.get("shared_item", {})
	if not shared_item.is_empty():
		next_snapshot["shared_item"] = shared_item.duplicate(true)
	next_snapshot["revision"] = target_revision
	next_snapshot["server_tick"] = int(delta.get("server_tick", 0))
	next_snapshot.erase("checksum")
	var computed_checksum := Utils.payload_hash(next_snapshot)
	if computed_checksum != String(delta.get("target_checksum", "")):
		return _failure("MULTIPLAYER_DELTA_TARGET_CHECKSUM_MISMATCH")
	next_snapshot["checksum"] = computed_checksum
	_snapshot = next_snapshot
	_delta_deliveries += 1
	return _success({"replay": false})


func get_player(logical_player_id: String) -> Dictionary:
	for player in _snapshot.get("players", []):
		if String(player.get("logical_player_id", "")) == logical_player_id:
			return Dictionary(player).duplicate(true)
	return {}


func get_shared_item() -> Dictionary:
	return Dictionary(_snapshot.get("shared_item", {})).duplicate(true)


func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": not _snapshot.is_empty(),
		"revision": int(_snapshot.get("revision", -1)),
		"snapshot_deliveries": _snapshot_deliveries,
		"delta_deliveries": _delta_deliveries,
		"replays": _replays,
		"direct_authority_references": 0,
		"direct_domain_references": 0,
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": {}}
