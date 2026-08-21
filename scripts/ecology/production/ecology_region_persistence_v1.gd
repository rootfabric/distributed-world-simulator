extends RefCounted

const OfflineCatchup = preload("res://scripts/ecology/production/ecology_offline_catchup_v1.gd")
const RegionState = preload("res://scripts/ecology/production/ecology_region_state_v1.gd")
const EcologyClock = preload("res://scripts/ecology/production/ecology_clock_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p4_4_region_snapshot.v1"
const VERSION := "1.0.0"
const FORMAT_VERSION := 1
const MAGIC := "DWS_ECO_P4_4_REGION_SNAPSHOT_V1"
const PARENT_P4_3_ACCEPTED_AGGREGATE := "4bdfd994a27ef15ff4010643e35f4652a0a2f3fdb2d3fcfa6b86b816b14cca62"
const MAX_PAYLOAD_BYTES := 134217728

const SNAPSHOT_FIELDS := [
	"schema",
	"version",
	"format_version",
	"parent_p4_3_accepted_aggregate",
	"region_id",
	"clock_hash",
	"catchup_hash",
	"region_state_hash",
	"ecology_generation",
	"observed_target_world_time",
	"catchup_state",
	"snapshot_hash",
]

static func create_snapshot(catchup_state: Dictionary) -> Dictionary:
	if not bool(OfflineCatchup.validate_state(catchup_state).get("success", false)):
		return {}
	var region: Dictionary = Dictionary(catchup_state.get("region_state", {}))
	var clock: Dictionary = Dictionary(catchup_state.get("clock", {}))
	if not bool(RegionState.validate_region_state(region).get("success", false)):
		return {}
	if not bool(EcologyClock.validate_clock(clock).get("success", false)):
		return {}
	var snapshot := {
		"schema": SCHEMA,
		"version": VERSION,
		"format_version": FORMAT_VERSION,
		"parent_p4_3_accepted_aggregate": PARENT_P4_3_ACCEPTED_AGGREGATE,
		"region_id": String(region.get("region_id", "")),
		"clock_hash": String(catchup_state.get("clock_hash", "")),
		"catchup_hash": String(catchup_state.get("catchup_hash", "")),
		"region_state_hash": String(catchup_state.get("region_state_hash", "")),
		"ecology_generation": int(region.get("ecology_generation", -1)),
		"observed_target_world_time": float(catchup_state.get("observed_target_world_time", NAN)),
		"catchup_state": catchup_state.duplicate(true),
	}
	snapshot["snapshot_hash"] = compute_snapshot_hash(snapshot)
	if not bool(validate_snapshot(snapshot).get("success", false)):
		return {}
	return snapshot

static func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	if not _exact_fields(snapshot, SNAPSHOT_FIELDS):
		return _failure("SNAPSHOT_FIELDS_MISMATCH")
	if String(snapshot.get("schema", "")) != SCHEMA or String(snapshot.get("version", "")) != VERSION:
		return _failure("SCHEMA_OR_VERSION_MISMATCH")
	if typeof(snapshot.get("format_version")) != TYPE_INT or int(snapshot.get("format_version", -1)) != FORMAT_VERSION:
		return _failure("FORMAT_VERSION_UNSUPPORTED")
	if String(snapshot.get("parent_p4_3_accepted_aggregate", "")) != PARENT_P4_3_ACCEPTED_AGGREGATE:
		return _failure("PARENT_P4_3_MISMATCH")
	if typeof(snapshot.get("catchup_state")) != TYPE_DICTIONARY:
		return _failure("CATCHUP_STATE_TYPE_INVALID")
	var catchup: Dictionary = Dictionary(snapshot.get("catchup_state", {}))
	if not bool(OfflineCatchup.validate_state(catchup).get("success", false)):
		return _failure("CATCHUP_STATE_INVALID")
	var region: Dictionary = Dictionary(catchup.get("region_state", {}))
	if String(snapshot.get("region_id", "")) != String(region.get("region_id", "")):
		return _failure("REGION_ID_DERIVED_MISMATCH")
	if String(snapshot.get("clock_hash", "")) != String(catchup.get("clock_hash", "")):
		return _failure("CLOCK_HASH_DERIVED_MISMATCH")
	if String(snapshot.get("catchup_hash", "")) != String(catchup.get("catchup_hash", "")):
		return _failure("CATCHUP_HASH_DERIVED_MISMATCH")
	if String(snapshot.get("region_state_hash", "")) != String(catchup.get("region_state_hash", "")):
		return _failure("REGION_HASH_DERIVED_MISMATCH")
	if typeof(snapshot.get("ecology_generation")) != TYPE_INT or int(snapshot.get("ecology_generation", -1)) != int(region.get("ecology_generation", -1)):
		return _failure("GENERATION_DERIVED_MISMATCH")
	if typeof(snapshot.get("observed_target_world_time")) != TYPE_FLOAT or float(snapshot.get("observed_target_world_time", NAN)) != float(catchup.get("observed_target_world_time", NAN)):
		return _failure("OBSERVED_TIME_DERIVED_MISMATCH")
	var expected_hash := compute_snapshot_hash(snapshot)
	if not _is_hash(expected_hash) or String(snapshot.get("snapshot_hash", "")) != expected_hash:
		return _failure("SNAPSHOT_HASH_MISMATCH")
	return {
		"success": true,
		"error": "",
		"snapshot_hash": expected_hash,
		"region_id": String(snapshot["region_id"]),
		"ecology_generation": int(snapshot["ecology_generation"]),
		"catchup_hash": String(snapshot["catchup_hash"]),
	}

static func compute_snapshot_hash(snapshot: Dictionary) -> String:
	var canonical := [
		String(snapshot.get("schema", "")),
		String(snapshot.get("version", "")),
		snapshot.get("format_version", -1),
		String(snapshot.get("parent_p4_3_accepted_aggregate", "")),
		String(snapshot.get("region_id", "")),
		String(snapshot.get("clock_hash", "")),
		String(snapshot.get("catchup_hash", "")),
		String(snapshot.get("region_state_hash", "")),
		snapshot.get("ecology_generation", -1),
		snapshot.get("observed_target_world_time", NAN),
	]
	return JSON.stringify(canonical).sha256_text()

static func serialize_snapshot(snapshot: Dictionary) -> PackedByteArray:
	if not bool(validate_snapshot(snapshot).get("success", false)):
		return PackedByteArray()
	var payload := var_to_bytes(snapshot)
	if payload.is_empty() or payload.size() > MAX_PAYLOAD_BYTES:
		return PackedByteArray()
	var payload_hash := _sha256_bytes(payload)
	if not _is_hash(payload_hash):
		return PackedByteArray()
	var header := "%s\nformat_version=%d\npayload_sha256=%s\npayload_bytes=%d\nsnapshot_hash=%s\n\n" % [
		MAGIC,
		FORMAT_VERSION,
		payload_hash,
		payload.size(),
		String(snapshot.get("snapshot_hash", "")),
	]
	var out := header.to_utf8_buffer()
	out.append_array(payload)
	return out

static func deserialize_snapshot(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty():
		return {}
	var separator := _find_header_separator(bytes)
	if separator < 0:
		return {}
	var header := bytes.slice(0, separator).get_string_from_utf8()
	var lines := header.split("\n", false)
	if lines.size() != 5 or String(lines[0]) != MAGIC:
		return {}
	var format_text := _parse_header_value(String(lines[1]), "format_version")
	var payload_hash := _parse_header_value(String(lines[2]), "payload_sha256")
	var payload_size_text := _parse_header_value(String(lines[3]), "payload_bytes")
	var header_snapshot_hash := _parse_header_value(String(lines[4]), "snapshot_hash")
	if not format_text.is_valid_int() or int(format_text) != FORMAT_VERSION:
		return {}
	if not _is_hash(payload_hash) or not _is_hash(header_snapshot_hash) or not payload_size_text.is_valid_int():
		return {}
	var expected_size := int(payload_size_text)
	if expected_size <= 0 or expected_size > MAX_PAYLOAD_BYTES:
		return {}
	var payload := bytes.slice(separator + 2)
	if payload.size() != expected_size or _sha256_bytes(payload) != payload_hash:
		return {}
	var decoded = bytes_to_var(payload)
	if typeof(decoded) != TYPE_DICTIONARY:
		return {}
	var snapshot: Dictionary = Dictionary(decoded)
	if String(snapshot.get("snapshot_hash", "")) != header_snapshot_hash:
		return {}
	if not bool(validate_snapshot(snapshot).get("success", false)):
		return {}
	return snapshot.duplicate(true)

static func restore_catchup_state(snapshot: Dictionary) -> Dictionary:
	if not bool(validate_snapshot(snapshot).get("success", false)):
		return {}
	return Dictionary(snapshot.get("catchup_state", {})).duplicate(true)

static func migrate_to_current(snapshot_value) -> Dictionary:
	if typeof(snapshot_value) != TYPE_DICTIONARY:
		return {}
	var snapshot: Dictionary = Dictionary(snapshot_value)
	if typeof(snapshot.get("format_version")) != TYPE_INT:
		return {}
	if int(snapshot.get("format_version", -1)) != FORMAT_VERSION:
		return {}
	if not bool(validate_snapshot(snapshot).get("success", false)):
		return {}
	return snapshot.duplicate(true)

static func save_file(path: String, snapshot: Dictionary) -> Dictionary:
	if path.is_empty():
		return _failure("PATH_EMPTY")
	var bytes := serialize_snapshot(snapshot)
	if bytes.is_empty():
		return _failure("SNAPSHOT_INVALID")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure("OPEN_WRITE_FAILED")
	file.store_buffer(bytes)
	file.flush()
	file.close()
	return {
		"success": true,
		"error": "",
		"bytes": bytes.size(),
		"file_sha256": _sha256_bytes(bytes),
		"snapshot_hash": String(snapshot.get("snapshot_hash", "")),
		"region_id": String(snapshot.get("region_id", "")),
	}

static func load_file(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var length := file.get_length()
	if length <= 0 or length > MAX_PAYLOAD_BYTES + 4096:
		file.close()
		return {}
	var bytes := file.get_buffer(length)
	file.close()
	return deserialize_snapshot(bytes)

static func serialized_sha256(snapshot: Dictionary) -> String:
	var bytes := serialize_snapshot(snapshot)
	if bytes.is_empty():
		return ""
	return _sha256_bytes(bytes)

static func _find_header_separator(bytes: PackedByteArray) -> int:
	for index in range(bytes.size() - 1):
		if bytes[index] == 10 and bytes[index + 1] == 10:
			return index
	return -1

static func _parse_header_value(line: String, key: String) -> String:
	var prefix := key + "="
	if not line.begins_with(prefix):
		return ""
	return line.substr(prefix.length())

static func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()

static func _is_hash(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true

static func _exact_fields(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true

static func _failure(error: String) -> Dictionary:
	return {"success": false, "error": "ECO_P4_4_" + error}
