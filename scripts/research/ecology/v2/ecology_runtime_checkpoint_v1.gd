extends RefCounted
## Shared durable checkpoint for the single EcologyRuntimeV1 state.
## This is a generalized ecology payload/service, not a workbench-owned save
## truth. It follows the A8 trust model: canonical payload + explicit external
## text/hash anchor supplied by the caller at admission.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")

const SCHEMA := "dws.ecology.runtime-checkpoint.v1"
const FIELDS := ["schema", "manifest_hash", "tick", "runtime_state", "runtime_state_hash", "external_state", "external_state_hash", "checksum"]

static func create(manifest_hash: String, runtime_state: Dictionary, external_state: Dictionary = {}) -> Dictionary:
	if not F.valid_hash(manifest_hash):
		return {}
	if not Runtime.validate(runtime_state).is_empty():
		return {}
	if not external_state is Dictionary or C.encode(external_state).is_empty():
		return {}
	var external_hash := "" if external_state.is_empty() else C.digest(external_state)
	if not external_hash.is_empty() and not F.valid_hash(external_hash):
		return {}
	var value := {
		"schema": SCHEMA,
		"manifest_hash": manifest_hash,
		"tick": int(runtime_state.tick),
		"runtime_state": runtime_state.duplicate(true),
		"runtime_state_hash": Runtime.state_hash(runtime_state),
		"external_state": external_state.duplicate(true),
		"external_state_hash": external_hash,
		"checksum": "",
	}
	value.checksum = _checksum(value)
	return value if validate(value).is_empty() else {}

static func validate(value: Variant) -> String:
	if not C.keys(value, FIELDS) or String(value.schema) != SCHEMA:
		return "RUNTIME_CHECKPOINT_SCHEMA"
	if not F.valid_hash(value.manifest_hash) or not C.integer(value.tick, 0, F.MAX_TICK):
		return "RUNTIME_CHECKPOINT_FIELDS"
	if not value.runtime_state is Dictionary:
		return "RUNTIME_CHECKPOINT_RUNTIME"
	var runtime_error := Runtime.validate(value.runtime_state)
	if not runtime_error.is_empty():
		return "RUNTIME_CHECKPOINT_RUNTIME:" + runtime_error
	if int(value.runtime_state.tick) != int(value.tick):
		return "RUNTIME_CHECKPOINT_TICK"
	if not F.valid_hash(value.runtime_state_hash) or String(value.runtime_state_hash) != Runtime.state_hash(value.runtime_state):
		return "RUNTIME_CHECKPOINT_RUNTIME_HASH"
	if not value.external_state is Dictionary:
		return "RUNTIME_CHECKPOINT_EXTERNAL_STATE"
	if value.external_state.is_empty():
		if not String(value.external_state_hash).is_empty():
			return "RUNTIME_CHECKPOINT_EXTERNAL_HASH"
	else:
		if not F.valid_hash(value.external_state_hash) or String(value.external_state_hash) != C.digest(value.external_state):
			return "RUNTIME_CHECKPOINT_EXTERNAL_HASH"
	if not F.valid_hash(value.checksum) or String(value.checksum) != _checksum(value):
		return "RUNTIME_CHECKPOINT_CHECKSUM"
	return "RUNTIME_CHECKPOINT_NONCANONICAL" if C.encode(value).is_empty() else ""

static func admit(value: Dictionary, expected_checksum: String, expected_manifest_hash: String = "") -> Dictionary:
	if not F.valid_hash(expected_checksum) or String(value.get("checksum", "")) != expected_checksum:
		return {"success": false, "error": "RUNTIME_CHECKPOINT_EXTERNAL_ANCHOR"}
	var error := validate(value)
	if not error.is_empty():
		return {"success": false, "error": error}
	if not expected_manifest_hash.is_empty() and String(value.manifest_hash) != expected_manifest_hash:
		return {"success": false, "error": "RUNTIME_CHECKPOINT_MANIFEST"}
	return {"success": true, "checkpoint": value.duplicate(true)}

static func serialize(value: Dictionary) -> String:
	return C.encode(value) if validate(value).is_empty() else ""

static func deserialize(text: String, expected_text_hash: String, expected_manifest_hash: String = "") -> Dictionary:
	if not F.valid_hash(expected_text_hash) or text.sha256_text() != expected_text_hash:
		return {}
	var decoded := C.decode(text)
	if not bool(decoded.get("success", false)) or not decoded.value is Dictionary:
		return {}
	var value: Dictionary = decoded.value
	var admitted := admit(value, String(value.get("checksum", "")), expected_manifest_hash)
	return admitted.checkpoint if bool(admitted.get("success", false)) else {}

static func _checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.checksum = ""
	return C.digest(payload)
