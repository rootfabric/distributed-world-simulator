extends RefCounted

## P6.7 THE single persistence owner for all P6 replay state.
##
## Owner identity: "p6-owner/directory-one-writer" (declared in
## p6_ownership_map.gd as SINGLE_PERSISTENCE_OWNER_ID). This is the ONLY file
## in the runtime allowed to write persistence (enforced by the zero-write
## fence test); every other module must route durable state through here.
##
## Durability contract:
## - save() is atomic: canonical JSON is written to "<path>.tmp", flushed, and
##   then renamed over the target, so a crash mid-write never leaves a torn
##   canonical file behind;
## - load() is fail-closed: envelope schema, owner identity, declared domain,
##   and the SHA-256 checksum of the state payload are all verified before a
##   P6OutpostState is reconstructed; any violation rejects the file.

const OwnershipMapScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_ownership_map.gd")
const StateScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")

const SCHEMA := "planet_simulator.p6_persistence_owner.v1"
const ENVELOPE_VERSION := 1
const DOMAIN_ID := "p6-domain/outpost-world-state"

const ENVELOPE_FIELDS: Array = [
	"schema",
	"version",
	"persistence_owner",
	"domain_id",
	"checksum",
	"state",
]

var _saves: int = 0
var _loads: int = 0
var _save_failures: int = 0
var _load_failures: int = 0
var _last_error_code: String = ""


## Atomically persist one outpost state. Writes "<path>.tmp" first, flushes,
## then renames over <path>. Creates missing parent directories. Returns true
## only when the canonical file is fully in place.
func save(state, file_path: String) -> bool:
	if state == null or not state.has_method("serialize"):
		return _save_reject("INVALID_STATE")
	var state_data: Dictionary = state.serialize()
	if state_data.is_empty():
		return _save_reject("INVALID_STATE")
	if file_path.is_empty():
		return _save_reject("BAD_FILE_PATH")
	var ownership: Dictionary = OwnershipMapScript.assert_domains_declared([DOMAIN_ID])
	if not bool(ownership.get("success", false)):
		return _save_reject("PERSISTENCE_DOMAIN_UNDECLARED")
	var envelope: Dictionary = {
		"schema": SCHEMA,
		"version": ENVELOPE_VERSION,
		"persistence_owner": OwnershipMapScript.SINGLE_PERSISTENCE_OWNER_ID,
		"domain_id": DOMAIN_ID,
		"checksum": StateScript.checksum_of_data(state_data),
		"state": state_data,
	}
	var abs_path := ProjectSettings.globalize_path(file_path)
	var abs_tmp := abs_path + ".tmp"
	var parent_dir := abs_path.get_base_dir()
	if not parent_dir.is_empty() and not DirAccess.dir_exists_absolute(parent_dir):
		var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(parent_dir)
		if mkdir_error != OK:
			return _save_reject("MKDIR_FAILED")
	DirAccess.remove_absolute(abs_tmp)
	var file := FileAccess.open(abs_tmp, FileAccess.WRITE)
	if file == null:
		return _save_reject("WRITE_FAILED")
	file.store_string(StateScript.canonical_json(envelope))
	file.flush()
	file.close()
	var rename_error: Error = DirAccess.rename_absolute(abs_tmp, abs_path)
	if rename_error != OK:
		DirAccess.remove_absolute(abs_tmp)
		return _save_reject("RENAME_FAILED")
	_saves = int(_saves) + 1
	_last_error_code = ""
	return true


## Load a persisted outpost state. Returns
## {"success": true, "details": {"state": P6OutpostState, "checksum": ..., "domain_id": ...}}
## on success, or {"success": false, "error_code": ...} on any violation.
func load(file_path: String) -> Dictionary:
	var abs_path := ProjectSettings.globalize_path(file_path)
	if not FileAccess.file_exists(abs_path):
		return _load_reject("FILE_NOT_FOUND")
	var text := FileAccess.get_file_as_string(abs_path)
	if text.is_empty():
		return _load_reject("EMPTY_FILE")
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _load_reject("PARSE_FAILED")
	var envelope: Dictionary = parsed
	for required in ENVELOPE_FIELDS:
		if not envelope.has(required):
			return _load_reject("MISSING_ENVELOPE_FIELD")
	for field in envelope.keys():
		if not ENVELOPE_FIELDS.has(String(field)):
			return _load_reject("UNKNOWN_ENVELOPE_FIELD")
	if String(envelope["schema"]) != SCHEMA:
		return _load_reject("SCHEMA_MISMATCH")
	var version_value: Variant = envelope["version"]
	if typeof(version_value) != TYPE_INT and typeof(version_value) != TYPE_FLOAT:
		return _load_reject("VERSION_MISMATCH")
	if int(version_value) != ENVELOPE_VERSION:
		return _load_reject("VERSION_MISMATCH")
	if String(envelope["persistence_owner"]) != OwnershipMapScript.SINGLE_PERSISTENCE_OWNER_ID:
		return _load_reject("WRONG_PERSISTENCE_OWNER")
	var domain_id := String(envelope["domain_id"])
	var ownership: Dictionary = OwnershipMapScript.assert_domains_declared([domain_id])
	if not bool(ownership.get("success", false)):
		return _load_reject("UNDECLARED_DOMAIN")
	var state_value: Variant = envelope["state"]
	if typeof(state_value) != TYPE_DICTIONARY:
		return _load_reject("BAD_STATE_PAYLOAD")
	var restored_state = StateScript.new()
	if not restored_state.deserialize(Dictionary(state_value)):
		return _load_reject("STATE_SCHEMA_INVALID")
	# Verify the checksum against the NORMALIZED canonical form: JSON parsing
	# turns ints into floats, so the raw parsed payload is not byte-identical
	# to the saved serialization; deserialize() restores canonical types.
	var expected_checksum := String(envelope["checksum"])
	var actual_checksum := StateScript.checksum_of_data(restored_state.serialize())
	if actual_checksum != expected_checksum:
		return _load_reject("CHECKSUM_MISMATCH")
	_loads = int(_loads) + 1
	_last_error_code = ""
	return {
		"success": true,
		"details": {
			"state": restored_state,
			"checksum": actual_checksum,
			"domain_id": domain_id,
			"persistence_owner": OwnershipMapScript.SINGLE_PERSISTENCE_OWNER_ID,
		},
	}


func file_exists(file_path: String) -> bool:
	if file_path.is_empty():
		return false
	return FileAccess.file_exists(ProjectSettings.globalize_path(file_path))


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"persistence_owner": OwnershipMapScript.SINGLE_PERSISTENCE_OWNER_ID,
		"domain_id": DOMAIN_ID,
		"saves": _saves,
		"loads": _loads,
		"save_failures": _save_failures,
		"load_failures": _load_failures,
		"last_error_code": _last_error_code,
	}


func _save_reject(error_code: String) -> bool:
	_save_failures = int(_save_failures) + 1
	_last_error_code = error_code
	return false


func _load_reject(error_code: String) -> Dictionary:
	_load_failures = int(_load_failures) + 1
	_last_error_code = error_code
	return {"success": false, "error_code": error_code, "details": {}}
