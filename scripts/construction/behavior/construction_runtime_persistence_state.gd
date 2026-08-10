extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const RuntimeStoreScript = preload("res://scripts/construction/behavior/construction_runtime_state_store.gd")
const OperationLedgerScript = preload("res://scripts/items/services/item_operation_ledger.gd")
const StorageScript = preload("res://scripts/construction/utilities/construction_utility_storage_state.gd")
const ExecutionProfileScript = preload("res://scripts/construction/utilities/construction_utility_execution_profile.gd")

const SCHEMA: String = "planet_simulator.construction_runtime_persistence_state.v1"
const FIELDS: Array[String] = [
	"schema",
	"construct_id",
	"construct_checksum",
	"runtime_state",
	"operation_ledger",
	"power_tick",
	"power_storage",
	"power_execution_profile",
	"checksum",
]


static func create(
	construct_id: String,
	construct_checksum: String,
	runtime_state: Dictionary,
	operation_ledger: Dictionary,
	power_tick: int,
	power_storage: Dictionary,
	power_execution_profile: Dictionary
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"construct_id": construct_id,
		"construct_checksum": construct_checksum,
		"runtime_state": runtime_state.duplicate(true),
		"operation_ledger": operation_ledger.duplicate(true),
		"power_tick": power_tick,
		"power_storage": power_storage.duplicate(true),
		"power_execution_profile": power_execution_profile.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_RUNTIME_PERSISTENCE_SCHEMA")
	var construct_id: String = String(value.get("construct_id", ""))
	if not _is_path(construct_id, "construct/"):
		return _failure("INVALID_CONSTRUCTION_RUNTIME_PERSISTENCE_CONSTRUCT_ID")
	var construct_checksum: String = String(value.get("construct_checksum", ""))
	if not _is_lower_hex_64(construct_checksum):
		return _failure("INVALID_CONSTRUCTION_RUNTIME_PERSISTENCE_CONSTRUCT_CHECKSUM")
	for field in ["runtime_state", "operation_ledger", "power_storage", "power_execution_profile"]:
		if typeof(value.get(field)) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_RUNTIME_PERSISTENCE_SECTION", {"field": field})

	var runtime_state: Dictionary = Dictionary(value["runtime_state"])
	var runtime_validation: Dictionary = RuntimeStoreScript.validate_state(runtime_state)
	if not bool(runtime_validation.get("success", false)):
		return _failure("CONSTRUCTION_RUNTIME_PERSISTENCE_RUNTIME_STATE_INVALID", {"cause": runtime_validation})
	for subject_value in runtime_state.get("subjects", []):
		if not subject_value is Dictionary or String(Dictionary(subject_value).get("construct_id", "")) != construct_id:
			return _failure("CONSTRUCTION_RUNTIME_PERSISTENCE_SUBJECT_CONSTRUCT_MISMATCH")

	var operation_ledger: Dictionary = Dictionary(value["operation_ledger"])
	var ledger = OperationLedgerScript.new(maxi(1, int(operation_ledger.get("maximum_entries", 1))))
	var ledger_validation: Dictionary = ledger.load_dict(operation_ledger)
	if not bool(ledger_validation.get("success", false)):
		return _failure("CONSTRUCTION_RUNTIME_PERSISTENCE_LEDGER_INVALID", {"cause": ledger_validation})

	if not UtilsScript.is_json_integer(value.get("power_tick")) or int(value["power_tick"]) < 0:
		return _failure("INVALID_CONSTRUCTION_RUNTIME_PERSISTENCE_POWER_TICK")
	var power_tick: int = int(value["power_tick"])
	var power_storage: Dictionary = Dictionary(value["power_storage"])
	var storage_validation: Dictionary = StorageScript.validate(power_storage)
	if not bool(storage_validation.get("success", false)):
		return _failure("CONSTRUCTION_RUNTIME_PERSISTENCE_STORAGE_INVALID", {"cause": storage_validation})
	var power_profile: Dictionary = Dictionary(value["power_execution_profile"])
	var profile_validation: Dictionary = ExecutionProfileScript.validate(power_profile)
	if not bool(profile_validation.get("success", false)):
		return _failure("CONSTRUCTION_RUNTIME_PERSISTENCE_POWER_PROFILE_INVALID", {"cause": profile_validation})
	if int(power_storage.get("tick", -1)) != power_tick or int(power_profile.get("tick", -1)) != power_tick:
		return _failure("CONSTRUCTION_RUNTIME_PERSISTENCE_POWER_TICK_MISMATCH")
	if String(power_profile.get("construct_id", "")) != construct_id or String(power_profile.get("construct_checksum", "")) != construct_checksum:
		return _failure("CONSTRUCTION_RUNTIME_PERSISTENCE_POWER_IDENTITY_MISMATCH")
	var storage_rows: Array = Array(power_profile.get("storage_states", []))
	if storage_rows.size() != 1 or not storage_rows[0] is Dictionary:
		return _failure("CONSTRUCTION_RUNTIME_PERSISTENCE_POWER_STORAGE_WITNESS_MISSING")
	if UtilsScript.canonical_json(Dictionary(storage_rows[0])) != UtilsScript.canonical_json(power_storage):
		return _failure("CONSTRUCTION_RUNTIME_PERSISTENCE_POWER_STORAGE_WITNESS_MISMATCH")
	if String(value.get("checksum", "")) != compute_checksum(value):
		return _failure("CONSTRUCTION_RUNTIME_PERSISTENCE_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("CONSTRUCTION_RUNTIME_PERSISTENCE_NOT_JSON_SAFE")
	return _success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


static func _is_path(value: String, prefix: String) -> bool:
	if not value.begins_with(prefix) or value.length() <= prefix.length() or value != value.to_lower() or value.contains("//"):
		return false
	for segment in value.split("/", true):
		if segment.is_empty():
			return false
		for character in segment:
			if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_":
				return false
	return true


static func _is_lower_hex_64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in "0123456789abcdef":
			return false
	return true


static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
