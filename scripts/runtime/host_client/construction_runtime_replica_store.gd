extends RefCounted

const SnapshotScript = preload("res://scripts/runtime/networked_gameplay/contracts/construction_runtime_snapshot.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.construction_runtime_replica_store.v1"

var _snapshot: Dictionary = {}
var _accepted: int = 0
var _replays: int = 0
var _stale: int = 0
var _clock_only: int = 0
var _conflicts: int = 0
var _authority_resets: int = 0


func accept_snapshot(snapshot: Dictionary) -> Dictionary:
	var validation: Dictionary = SnapshotScript.validate(snapshot)
	if not bool(validation.get("success", false)):
		return validation
	if _snapshot.is_empty():
		_snapshot = snapshot.duplicate(true)
		_accepted += 1
		return _success({"accepted": true, "reset_reason": "INITIAL"})

	var incoming_epoch := int(snapshot.get("authority_epoch", 0))
	var current_epoch := int(_snapshot.get("authority_epoch", 0))
	if incoming_epoch < current_epoch:
		_stale += 1
		return _success({"accepted": false, "stale": true, "reset_reason": ""})
	if incoming_epoch > current_epoch:
		_snapshot = snapshot.duplicate(true)
		_accepted += 1
		_authority_resets += 1
		return _success({"accepted": true, "reset_reason": "AUTHORITY_CHANGED"})

	var incoming_revision := int(snapshot.get("revision", -1))
	var current_revision := int(_snapshot.get("revision", -1))
	if incoming_revision < current_revision:
		_stale += 1
		return _success({"accepted": false, "stale": true, "reset_reason": ""})
	if incoming_revision == current_revision:
		var same_state := SnapshotScript.semantic_checksum(snapshot) == SnapshotScript.semantic_checksum(_snapshot)
		if not same_state:
			_conflicts += 1
			return _failure("CONSTRUCTION_RUNTIME_SAME_REVISION_MUTATION")
		var incoming_tick := int(snapshot.get("server_tick", -1))
		var current_tick := int(_snapshot.get("server_tick", -1))
		if incoming_tick < current_tick:
			_stale += 1
			return _success({"accepted": false, "stale": true, "reset_reason": ""})
		if String(snapshot.get("checksum", "")) == String(_snapshot.get("checksum", "")):
			_replays += 1
			return _success({"accepted": false, "replay": true, "reset_reason": ""})
		_snapshot = snapshot.duplicate(true)
		_clock_only += 1
		return _success({"accepted": true, "clock_only": true, "reset_reason": ""})

	_snapshot = snapshot.duplicate(true)
	_accepted += 1
	return _success({"accepted": true, "reset_reason": ""})


func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func get_runtime_state() -> Dictionary:
	return Dictionary(_snapshot.get("runtime_state", {})).duplicate(true) if not _snapshot.is_empty() else {}


func get_subject(runtime_id: String) -> Dictionary:
	for subject_value in get_runtime_state().get("subjects", []):
		if subject_value is Dictionary and String(subject_value.get("runtime_id", "")) == runtime_id:
			return Dictionary(subject_value).duplicate(true)
	return {}


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"has_snapshot": not _snapshot.is_empty(),
		"authority_epoch": int(_snapshot.get("authority_epoch", 0)),
		"server_tick": int(_snapshot.get("server_tick", 0)),
		"revision": int(_snapshot.get("revision", 0)),
		"state_checksum": String(_snapshot.get("state_checksum", "")),
		"accepted": _accepted,
		"replays": _replays,
		"stale": _stale,
		"clock_only": _clock_only,
		"conflicts": _conflicts,
		"authority_resets": _authority_resets,
	}


func state_semantically_equals(other_snapshot: Dictionary) -> bool:
	if _snapshot.is_empty():
		return false
	return SnapshotScript.semantic_checksum(_snapshot) == SnapshotScript.semantic_checksum(other_snapshot) \
		and UtilsScript.canonical_json(_snapshot.get("runtime_state", {})) == UtilsScript.canonical_json(other_snapshot.get("runtime_state", {}))


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
