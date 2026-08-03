extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const RepresentationKey = preload("res://scripts/simulation/representation/contracts/representation_key.gd")
const ArtifactManifest = preload("res://scripts/simulation/representation/contracts/representation_artifact_manifest.gd")

const SCHEMA := "planet_simulator.representation_cache_entry.v1"
const FIELDS: Array[String] = [
	"schema",
	"representation_key",
	"artifact_manifest",
	"state",
	"last_access_tick",
	"resident_bytes",
	"failure_code",
	"checksum",
]


static func create(
	representation_key: Dictionary,
	artifact_manifest: Dictionary,
	state: String,
	last_access_tick: int,
	resident_bytes: int,
	failure_code: String = ""
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"representation_key": representation_key.duplicate(true),
		"artifact_manifest": artifact_manifest.duplicate(true),
		"state": state,
		"last_access_tick": last_access_tick,
		"resident_bytes": resident_bytes,
		"failure_code": failure_code,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_REPRESENTATION_CACHE_ENTRY_SCHEMA")
	if typeof(value.get("representation_key")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_REPRESENTATION_CACHE_KEY")
	checked = RepresentationKey.validate(value["representation_key"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("state")) != TYPE_STRING or not Utils.CACHE_STATES.has(String(value["state"])):
		return Utils.failure("INVALID_REPRESENTATION_CACHE_STATE")
	if not Utils.is_json_integer(value.get("last_access_tick")) or int(value["last_access_tick"]) < 0:
		return Utils.failure("INVALID_REPRESENTATION_CACHE_TICK")
	if not Utils.is_json_integer(value.get("resident_bytes")) or int(value["resident_bytes"]) < 0:
		return Utils.failure("INVALID_REPRESENTATION_CACHE_RESIDENT_BYTES")
	if typeof(value.get("failure_code")) != TYPE_STRING:
		return Utils.failure("INVALID_REPRESENTATION_CACHE_FAILURE_CODE")
	var state: String = String(value["state"])
	var raw_manifest = value.get("artifact_manifest", {})
	if typeof(raw_manifest) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_REPRESENTATION_CACHE_MANIFEST")
	var manifest: Dictionary = raw_manifest
	if state in ["READY", "STALE", "EVICTED"]:
		if manifest.is_empty():
			return Utils.failure("REPRESENTATION_CACHE_MANIFEST_REQUIRED")
		checked = ArtifactManifest.validate(manifest)
		if not bool(checked.get("success", false)):
			return checked
		if String(manifest["representation_key"].get("checksum", "")) != String(value["representation_key"].get("checksum", "")):
			return Utils.failure("REPRESENTATION_CACHE_KEY_MISMATCH")
		if state == "READY" and int(value["resident_bytes"]) != int(manifest["byte_size"]):
			return Utils.failure("REPRESENTATION_CACHE_READY_SIZE_MISMATCH")
		if state == "EVICTED" and int(value["resident_bytes"]) != 0:
			return Utils.failure("REPRESENTATION_CACHE_EVICTED_BYTES_PRESENT")
		if state == "STALE" and int(value["resident_bytes"]) > int(manifest["byte_size"]):
			return Utils.failure("REPRESENTATION_CACHE_STALE_SIZE_INVALID")
		if not String(value["failure_code"]).is_empty():
			return Utils.failure("REPRESENTATION_CACHE_FAILURE_CODE_UNEXPECTED")
	else:
		if typeof(manifest) != TYPE_DICTIONARY or not manifest.is_empty():
			return Utils.failure("REPRESENTATION_CACHE_MANIFEST_FORBIDDEN")
		if int(value["resident_bytes"]) != 0:
			return Utils.failure("REPRESENTATION_CACHE_TRANSIENT_BYTES_PRESENT")
		if state == "FAILED" and String(value["failure_code"]).is_empty():
			return Utils.failure("REPRESENTATION_CACHE_FAILURE_CODE_REQUIRED")
		if state == "BUILDING" and not String(value["failure_code"]).is_empty():
			return Utils.failure("REPRESENTATION_CACHE_FAILURE_CODE_UNEXPECTED")
	return Utils.validate_checksum(value)


static func can_transition(from_state: String, to_state: String) -> bool:
	if from_state == to_state:
		return true
	var allowed: Dictionary = {
		"BUILDING": ["FAILED", "READY"],
		"READY": ["EVICTED", "STALE"],
		"STALE": ["BUILDING", "EVICTED"],
		"FAILED": ["BUILDING", "EVICTED"],
		"EVICTED": ["BUILDING"],
	}
	return allowed.has(from_state) and Array(allowed[from_state]).has(to_state)
