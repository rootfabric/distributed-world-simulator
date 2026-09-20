extends RefCounted
## Durable externally-anchored checkpoint for the shared composed ecology runtime.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_composed_runtime_v1.gd")
const SCHEMA := "dws.ecology.runtime-checkpoint.v1"

static func create(manifest_hash: String, runtime_state: Dictionary) -> Dictionary:
	if not F.valid_hash(manifest_hash) or not Runtime.validate(runtime_state).is_empty(): return {}
	var value := {"schema": SCHEMA, "manifest_hash": manifest_hash, "tick": int(runtime_state.tick),
		"runtime_state": runtime_state.duplicate(true), "runtime_state_hash": C.digest(runtime_state), "checksum": ""}
	value.checksum = _checksum(value)
	return value if validate(value).is_empty() else {}

static func validate(v: Variant) -> String:
	if not C.keys(v, ["schema","manifest_hash","tick","runtime_state","runtime_state_hash","checksum"]) or v.schema != SCHEMA: return "CHECKPOINT_SCHEMA"
	if not F.valid_hash(v.manifest_hash) or not C.integer(v.tick, 0, C.MAX_INT) or not v.runtime_state is Dictionary: return "CHECKPOINT_FIELDS"
	var error := Runtime.validate(v.runtime_state)
	if not error.is_empty(): return "CHECKPOINT_RUNTIME:" + error
	if int(v.runtime_state.tick) != int(v.tick) or C.digest(v.runtime_state) != String(v.runtime_state_hash): return "CHECKPOINT_RUNTIME_HASH"
	if not F.valid_hash(v.runtime_state_hash) or not F.valid_hash(v.checksum) or String(v.checksum) != _checksum(v): return "CHECKPOINT_CHECKSUM"
	return ""

static func admit(v: Dictionary, expected_checksum: String, expected_manifest_hash: String = "") -> Dictionary:
	if not F.valid_hash(expected_checksum) or String(v.get("checksum", "")) != expected_checksum: return {"success": false, "error": "CHECKPOINT_EXTERNAL_ANCHOR"}
	var error := validate(v)
	if not error.is_empty(): return {"success": false, "error": error}
	if not expected_manifest_hash.is_empty() and String(v.manifest_hash) != expected_manifest_hash: return {"success": false, "error": "CHECKPOINT_MANIFEST"}
	return {"success": true, "checkpoint": v.duplicate(true)}

static func serialize(v: Dictionary) -> String:
	return C.encode(v) if validate(v).is_empty() else ""

static func deserialize(text: String, expected_checksum: String, expected_manifest_hash: String = "") -> Dictionary:
	var decoded := C.decode(text)
	if not decoded.success or not decoded.value is Dictionary: return {}
	var admitted := admit(decoded.value, expected_checksum, expected_manifest_hash)
	return admitted.checkpoint if bool(admitted.get("success", false)) else {}

static func _checksum(v: Dictionary) -> String:
	var payload := v.duplicate(true)
	payload.checksum = ""
	return C.digest(payload)
