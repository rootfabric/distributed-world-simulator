extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const RuntimeStoreScript = preload("res://scripts/construction/behavior/construction_runtime_state_store.gd")

const SCHEMA: String = "planet_simulator.construction_runtime_snapshot.v1"
const FIELDS: Array[String] = [
	"schema",
	"construct_id",
	"authority_epoch",
	"server_tick",
	"revision",
	"runtime_state",
	"state_checksum",
	"checksum",
]


static func create(
	construct_id: String,
	authority_epoch: int,
	server_tick: int,
	runtime_state: Dictionary
) -> Dictionary:
	var state: Dictionary = runtime_state.duplicate(true)
	var snapshot: Dictionary = {
		"schema": SCHEMA,
		"construct_id": construct_id,
		"authority_epoch": authority_epoch,
		"server_tick": server_tick,
		"revision": int(state.get("generation", 0)),
		"runtime_state": state,
		"state_checksum": String(state.get("checksum", "")),
		"checksum": "",
	}
	snapshot["checksum"] = compute_checksum(snapshot)
	return snapshot


static func validate(snapshot: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(snapshot, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(snapshot.get("schema", "")) != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_RUNTIME_SNAPSHOT_SCHEMA")
	if not String(snapshot.get("construct_id", "")).begins_with("construct/"):
		return _failure("INVALID_CONSTRUCTION_RUNTIME_SNAPSHOT_CONSTRUCT")
	for field in ["authority_epoch", "server_tick", "revision"]:
		if not UtilsScript.is_json_integer(snapshot.get(field)):
			return _failure("INVALID_CONSTRUCTION_RUNTIME_SNAPSHOT_INTEGER", {"field": field})
	if int(snapshot.get("authority_epoch", 0)) < 1 or int(snapshot.get("server_tick", -1)) < 0 or int(snapshot.get("revision", -1)) < 0:
		return _failure("INVALID_CONSTRUCTION_RUNTIME_SNAPSHOT_REVISION")
	var state_value = snapshot.get("runtime_state", {})
	if not state_value is Dictionary:
		return _failure("INVALID_CONSTRUCTION_RUNTIME_SNAPSHOT_STATE")
	var state: Dictionary = Dictionary(state_value)
	var state_validation: Dictionary = RuntimeStoreScript.validate_state(state)
	if not bool(state_validation.get("success", false)):
		return _failure("INVALID_CONSTRUCTION_RUNTIME_SNAPSHOT_STATE", {"cause": state_validation})
	if int(state.get("generation", -1)) != int(snapshot.get("revision", -2)):
		return _failure("CONSTRUCTION_RUNTIME_SNAPSHOT_REVISION_MISMATCH")
	if String(state.get("checksum", "")) != String(snapshot.get("state_checksum", "")):
		return _failure("CONSTRUCTION_RUNTIME_SNAPSHOT_STATE_CHECKSUM_MISMATCH")
	if String(snapshot.get("checksum", "")) != compute_checksum(snapshot):
		return _failure("CONSTRUCTION_RUNTIME_SNAPSHOT_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(snapshot).get("success", false)):
		return _failure("CONSTRUCTION_RUNTIME_SNAPSHOT_NOT_JSON_SAFE")
	return _success()


static func compute_checksum(snapshot: Dictionary) -> String:
	var payload: Dictionary = snapshot.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


static func semantic_checksum(snapshot: Dictionary) -> String:
	return String(snapshot.get("state_checksum", ""))


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
