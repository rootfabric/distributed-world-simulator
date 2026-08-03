extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ProfileScript = preload("res://scripts/construction/structural/construction_structural_profile.gd")
const STATE_SCHEMA := "planet_simulator.construction_structural_profile_store.v1"
const STATE_FIELDS: Array[String] = ["schema", "generation", "profiles", "checksum"]

var _profiles := {}
var _generation := 0

func publish(profile: Dictionary) -> Dictionary:
	var checked := ProfileScript.validate(profile); if not bool(checked.get("success", false)): return checked
	var key := _key(String(profile["construct_id"]), String(profile["load_case_id"]))
	if _profiles.has(key):
		var current: Dictionary = _profiles[key]
		if String(current["checksum"]) == String(profile["checksum"]): return _success({"replay": true, "generation": _generation})
		if int(profile["construct_revision"]) < int(current["construct_revision"]): return _failure("STALE_CONSTRUCTION_STRUCTURAL_PROFILE")
		if int(profile["construct_revision"]) == int(current["construct_revision"]) and String(profile["construct_checksum"]) != String(current["construct_checksum"]): return _failure("CONSTRUCTION_STRUCTURAL_SAME_REVISION_MUTATION")
	_profiles[key] = profile.duplicate(true); _generation += 1
	return _success({"replay": false, "generation": _generation})

func remove(construct_id: String, load_case_id: String, expected_checksum: String = "") -> Dictionary:
	var key := _key(construct_id, load_case_id)
	if not _profiles.has(key): return _success({"replay": true, "generation": _generation})
	if not expected_checksum.is_empty() and String(_profiles[key]["checksum"]) != expected_checksum: return _failure("CONSTRUCTION_STRUCTURAL_REMOVE_PRECONDITION_MISMATCH")
	_profiles.erase(key); _generation += 1; return _success({"replay": false, "generation": _generation})

func get_profile(construct_id: String, load_case_id: String) -> Dictionary: return Dictionary(_profiles.get(_key(construct_id, load_case_id), {})).duplicate(true)
func get_all() -> Array:
	var result: Array = []
	for value in _profiles.values(): result.append(Dictionary(value).duplicate(true))
	result.sort_custom(func(a, b):
		var ac := String(a["construct_id"]); var bc := String(b["construct_id"])
		return ac < bc if ac != bc else String(a["load_case_id"]) < String(b["load_case_id"])
	)
	return result
func get_generation() -> int: return _generation

func export_state() -> Dictionary:
	var state := {"schema": STATE_SCHEMA, "generation": _generation, "profiles": get_all(), "checksum": ""}; state["checksum"] = compute_state_checksum(state); return state
func load_state(state: Dictionary) -> Dictionary:
	var checked := validate_state(state); if not bool(checked.get("success", false)): return checked
	var next := {}; for profile in state["profiles"]: next[_key(String(profile["construct_id"]), String(profile["load_case_id"]))] = Dictionary(profile).duplicate(true)
	_profiles = next; _generation = int(state["generation"]); return _success()

static func validate_state(state: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(state, STATE_FIELDS); if not bool(exact.get("success", false)): return exact
	if state.get("schema") != STATE_SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_STRUCTURAL_STORE_SCHEMA")
	if not UtilsScript.is_json_integer(state.get("generation")) or int(state["generation"]) < 0: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_STORE_GENERATION")
	if typeof(state.get("profiles")) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_STORE_PROFILES")
	var previous := ""; var seen := {}
	for profile in state["profiles"]:
		if typeof(profile) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STRUCTURAL_STORE_PROFILE")
		var checked := ProfileScript.validate(profile); if not bool(checked.get("success", false)): return checked
		var key := _key(String(profile["construct_id"]), String(profile["load_case_id"]))
		if seen.has(key) or (not previous.is_empty() and key < previous): return _failure("NON_CANONICAL_CONSTRUCTION_STRUCTURAL_STORE_PROFILES")
		seen[key] = true; previous = key
	if String(state.get("checksum", "")) != compute_state_checksum(state): return _failure("CONSTRUCTION_STRUCTURAL_STORE_CHECKSUM_MISMATCH")
	return _success()

static func compute_state_checksum(state: Dictionary) -> String:
	var payload := state.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _key(construct_id: String, load_case_id: String) -> String: return "%s|%s" % [construct_id, load_case_id]
static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}; for key in details: result[key] = details[key]
	return result
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code, "details": {}}
