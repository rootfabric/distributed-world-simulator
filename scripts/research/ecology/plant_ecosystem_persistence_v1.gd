extends RefCounted

const Coexistence = preload("res://scripts/research/ecology/plant_multi_niche_coexistence_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p3_8_ecosystem_persistence.v1"
const VERSION := "1.0.0"
const PARENT_P3_7_CANDIDATE_AGGREGATE := "ef05ffb15d33819d3a6c4a1d534670e570ecb2ec674ad4a232e151e680a0e53a"
const MAGIC := "DWS_ECO_P3_8_CHECKPOINT_V1"
const MAX_EXACT_GENERATION := 9007199254740991
const MAX_ADVANCE_STEPS := 1000000

const STATE_FIELDS := [
	"schema",
	"version",
	"parent_p3_7_candidate_aggregate",
	"root_p3_7_result_hash",
	"generation",
	"current_p3_7_result",
	"current_p3_7_result_hash",
	"state_hash",
]

static func initialize(p3_7_result: Dictionary) -> Dictionary:
	if not bool(Coexistence.validate_result(p3_7_result).get("success", false)):
		return {}
	var result_hash := String(p3_7_result.get("result_hash", ""))
	if not _is_hash(result_hash):
		return {}
	return _build_state(result_hash, 0, p3_7_result)

static func advance(state: Dictionary, step_count_value) -> Dictionary:
	if not bool(validate_state(state).get("success", false)):
		return {}
	if typeof(step_count_value) != TYPE_INT:
		return {}
	var step_count := int(step_count_value)
	if step_count < 0 or step_count > MAX_ADVANCE_STEPS:
		return {}
	var generation := int(state.get("generation", -1))
	if generation > MAX_EXACT_GENERATION - step_count:
		return {}
	var root_hash := String(state.get("root_p3_7_result_hash", ""))
	var current: Dictionary = Dictionary(state.get("current_p3_7_result", {})).duplicate(true)
	for _step_index in range(step_count):
		var next_result := Coexistence.step(
			Dictionary(current.get("disturbance_result", {})),
			Array(current.get("next_community", [])).duplicate(true),
			Array(current.get("niches", [])).duplicate(true),
			Dictionary(current.get("config", {})).duplicate(true)
		)
		if next_result.is_empty() or not bool(Coexistence.validate_result(next_result).get("success", false)):
			return {}
		current = next_result
		generation += 1
	return _build_state(root_hash, generation, current)

static func validate_state(state: Dictionary) -> Dictionary:
	if not _exact_fields(state, STATE_FIELDS):
		return _failure("STATE_FIELDS_MISMATCH")
	if String(state.get("schema", "")) != SCHEMA or String(state.get("version", "")) != VERSION:
		return _failure("SCHEMA_OR_VERSION_MISMATCH")
	if String(state.get("parent_p3_7_candidate_aggregate", "")) != PARENT_P3_7_CANDIDATE_AGGREGATE:
		return _failure("PARENT_P3_7_MISMATCH")
	var root_hash := String(state.get("root_p3_7_result_hash", ""))
	if not _is_hash(root_hash):
		return _failure("ROOT_HASH_INVALID")
	if typeof(state.get("generation")) != TYPE_INT:
		return _failure("GENERATION_TYPE_INVALID")
	var generation := int(state.get("generation", -1))
	if generation < 0 or generation > MAX_EXACT_GENERATION:
		return _failure("GENERATION_RANGE_INVALID")
	if typeof(state.get("current_p3_7_result")) != TYPE_DICTIONARY:
		return _failure("CURRENT_RESULT_TYPE_INVALID")
	var current: Dictionary = Dictionary(state.get("current_p3_7_result", {}))
	var validation := Coexistence.validate_result(current)
	if not bool(validation.get("success", false)):
		return _failure("CURRENT_P3_7_RESULT_INVALID")
	var current_hash := String(current.get("result_hash", ""))
	if String(state.get("current_p3_7_result_hash", "")) != current_hash or not _is_hash(current_hash):
		return _failure("CURRENT_RESULT_HASH_MISMATCH")
	if generation == 0 and root_hash != current_hash:
		return _failure("GENERATION_ZERO_ROOT_MISMATCH")
	var expected_hash := compute_state_hash(state)
	if String(state.get("state_hash", "")) != expected_hash:
		return _failure("STATE_HASH_MISMATCH")
	return {"success": true, "error": "", "state_hash": expected_hash}

static func compute_state_hash(state: Dictionary) -> String:
	var canonical := {
		"schema": String(state.get("schema", "")),
		"version": String(state.get("version", "")),
		"parent_p3_7_candidate_aggregate": String(state.get("parent_p3_7_candidate_aggregate", "")),
		"root_p3_7_result_hash": String(state.get("root_p3_7_result_hash", "")),
		"generation": state.get("generation", -1),
		"current_p3_7_result": Dictionary(state.get("current_p3_7_result", {})).duplicate(true),
		"current_p3_7_result_hash": String(state.get("current_p3_7_result_hash", "")),
	}
	return _sha256_bytes(var_to_bytes(canonical))

static func serialize_state(state: Dictionary) -> PackedByteArray:
	if not bool(validate_state(state).get("success", false)):
		return PackedByteArray()
	var payload := var_to_bytes(state)
	if payload.is_empty():
		return PackedByteArray()
	var payload_hash := _sha256_bytes(payload)
	var header := "%s\npayload_sha256=%s\npayload_bytes=%d\nstate_hash=%s\n\n" % [
		MAGIC,
		payload_hash,
		payload.size(),
		String(state.get("state_hash", "")),
	]
	var out := header.to_utf8_buffer()
	out.append_array(payload)
	return out

static func deserialize_state(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty():
		return {}
	var separator := _find_header_separator(bytes)
	if separator < 0:
		return {}
	var header_bytes := bytes.slice(0, separator)
	var header := header_bytes.get_string_from_utf8()
	var lines := header.split("\n", false)
	if lines.size() != 4 or String(lines[0]) != MAGIC:
		return {}
	var payload_hash := _parse_header_value(String(lines[1]), "payload_sha256")
	var payload_size_text := _parse_header_value(String(lines[2]), "payload_bytes")
	var header_state_hash := _parse_header_value(String(lines[3]), "state_hash")
	if not _is_hash(payload_hash) or not _is_hash(header_state_hash) or not payload_size_text.is_valid_int():
		return {}
	var expected_size := int(payload_size_text)
	if expected_size < 0:
		return {}
	var payload := bytes.slice(separator + 2)
	if payload.size() != expected_size:
		return {}
	if _sha256_bytes(payload) != payload_hash:
		return {}
	var decoded = bytes_to_var(payload)
	if typeof(decoded) != TYPE_DICTIONARY:
		return {}
	var state: Dictionary = Dictionary(decoded)
	if String(state.get("state_hash", "")) != header_state_hash:
		return {}
	if not bool(validate_state(state).get("success", false)):
		return {}
	return state.duplicate(true)

static func save_file(path: String, state: Dictionary) -> Dictionary:
	if path.is_empty():
		return _failure("PATH_EMPTY")
	var bytes := serialize_state(state)
	if bytes.is_empty():
		return _failure("STATE_INVALID")
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
		"state_hash": String(state.get("state_hash", "")),
	}

static func load_file(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var length := file.get_length()
	if length <= 0:
		file.close()
		return {}
	var bytes := file.get_buffer(length)
	file.close()
	return deserialize_state(bytes)

static func serialized_sha256(state: Dictionary) -> String:
	var bytes := serialize_state(state)
	if bytes.is_empty():
		return ""
	return _sha256_bytes(bytes)

static func _build_state(root_hash: String, generation: int, current_result: Dictionary) -> Dictionary:
	if not _is_hash(root_hash) or generation < 0 or generation > MAX_EXACT_GENERATION:
		return {}
	if not bool(Coexistence.validate_result(current_result).get("success", false)):
		return {}
	var current_hash := String(current_result.get("result_hash", ""))
	var state := {
		"schema": SCHEMA,
		"version": VERSION,
		"parent_p3_7_candidate_aggregate": PARENT_P3_7_CANDIDATE_AGGREGATE,
		"root_p3_7_result_hash": root_hash,
		"generation": generation,
		"current_p3_7_result": current_result.duplicate(true),
		"current_p3_7_result_hash": current_hash,
	}
	state["state_hash"] = compute_state_hash(state)
	if not bool(validate_state(state).get("success", false)):
		return {}
	return state

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
	return {"success": false, "error": error}
