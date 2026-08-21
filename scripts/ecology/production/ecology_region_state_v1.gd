extends RefCounted

const Persistence = preload("res://scripts/research/ecology/plant_ecosystem_persistence_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p4_1_region_state.v1"
const VERSION := "1.0.0"
const PARENT_P3_8_ACCEPTED_AGGREGATE := "6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0"
const MAX_REGION_ID_LENGTH := 256
const MAX_EXACT_GENERATION := 9007199254740991

const STATE_FIELDS := ["schema", "version", "region_id", "ecology_generation", "last_simulated_world_time", "parent_p3_8_accepted_aggregate", "p3_state", "p3_state_hash", "region_state_hash"]

static func create_region_state(region_id_value, last_simulated_world_time_value, p3_state_value) -> Dictionary:
	if typeof(region_id_value) != TYPE_STRING:
		return {}
	var region_id := String(region_id_value)
	if not _is_region_id(region_id):
		return {}
	var world_time := _normalized_world_time(last_simulated_world_time_value)
	if is_nan(world_time):
		return {}
	if typeof(p3_state_value) != TYPE_DICTIONARY:
		return {}
	var p3_state: Dictionary = Dictionary(p3_state_value).duplicate(true)
	if not bool(Persistence.validate_state(p3_state).get("success", false)):
		return {}
	if typeof(p3_state.get("generation")) != TYPE_INT:
		return {}
	var generation := int(p3_state.get("generation", -1))
	if generation < 0 or generation > MAX_EXACT_GENERATION:
		return {}
	var p3_state_hash := String(p3_state.get("state_hash", ""))
	if not _is_hash(p3_state_hash):
		return {}
	var state := {
		"schema": SCHEMA,
		"version": VERSION,
		"region_id": region_id,
		"ecology_generation": generation,
		"last_simulated_world_time": world_time,
		"parent_p3_8_accepted_aggregate": PARENT_P3_8_ACCEPTED_AGGREGATE,
		"p3_state": p3_state,
		"p3_state_hash": p3_state_hash,
	}
	state["region_state_hash"] = compute_region_state_hash(state)
	if not bool(validate_region_state(state).get("success", false)):
		return {}
	return state

static func validate_region_state(state: Dictionary) -> Dictionary:
	if not _exact_fields(state, STATE_FIELDS):
		return _failure("STATE_FIELDS_MISMATCH")
	if String(state.get("schema", "")) != SCHEMA or String(state.get("version", "")) != VERSION:
		return _failure("SCHEMA_OR_VERSION_MISMATCH")
	if typeof(state.get("region_id")) != TYPE_STRING or not _is_region_id(String(state.get("region_id", ""))):
		return _failure("REGION_ID_INVALID")
	if typeof(state.get("ecology_generation")) != TYPE_INT:
		return _failure("GENERATION_TYPE_INVALID")
	var generation := int(state.get("ecology_generation", -1))
	if generation < 0 or generation > MAX_EXACT_GENERATION:
		return _failure("GENERATION_RANGE_INVALID")
	if typeof(state.get("last_simulated_world_time")) != TYPE_FLOAT:
		return _failure("WORLD_TIME_TYPE_INVALID")
	var world_time := float(state.get("last_simulated_world_time", NAN))
	if not is_finite(world_time) or world_time < 0.0:
		return _failure("WORLD_TIME_RANGE_INVALID")
	if String(state.get("parent_p3_8_accepted_aggregate", "")) != PARENT_P3_8_ACCEPTED_AGGREGATE:
		return _failure("PARENT_P3_8_ACCEPTED_AGGREGATE_MISMATCH")
	if typeof(state.get("p3_state")) != TYPE_DICTIONARY:
		return _failure("P3_STATE_TYPE_INVALID")
	var p3_state: Dictionary = Dictionary(state.get("p3_state", {}))
	if not bool(Persistence.validate_state(p3_state).get("success", false)):
		return _failure("P3_STATE_INVALID")
	if int(p3_state.get("generation", -1)) != generation:
		return _failure("GENERATION_P3_MISMATCH")
	var p3_state_hash := String(p3_state.get("state_hash", ""))
	if not _is_hash(p3_state_hash) or String(state.get("p3_state_hash", "")) != p3_state_hash:
		return _failure("P3_STATE_HASH_MISMATCH")
	var expected_hash := compute_region_state_hash(state)
	if not _is_hash(expected_hash) or String(state.get("region_state_hash", "")) != expected_hash:
		return _failure("REGION_STATE_HASH_MISMATCH")
	return {"success": true, "error": "", "region_state_hash": expected_hash, "p3_state_hash": p3_state_hash, "ecology_generation": generation}

static func compute_region_state_hash(state: Dictionary) -> String:
	var canonical := [String(state.get("schema", "")), String(state.get("version", "")), String(state.get("region_id", "")), state.get("ecology_generation", -1), state.get("last_simulated_world_time", NAN), String(state.get("parent_p3_8_accepted_aggregate", "")), String(state.get("p3_state_hash", ""))]
	return JSON.stringify(canonical).sha256_text()

static func extract_p3_state(state: Dictionary) -> Dictionary:
	if not bool(validate_region_state(state).get("success", false)):
		return {}
	return Dictionary(state.get("p3_state", {})).duplicate(true)

static func _normalized_world_time(value) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return NAN
	var result := float(value)
	if not is_finite(result) or result < 0.0:
		return NAN
	return result

static func _is_region_id(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_REGION_ID_LENGTH or value != value.strip_edges():
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		var allowed := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 45 or code == 46 or code == 58 or code == 95
		if not allowed:
			return false
	return true

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
