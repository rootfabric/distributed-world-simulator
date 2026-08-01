extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ContractUtils = preload("res://scripts/construction/utilities/construction_utility_contract_utils.gd")
const ProfileScript = preload("res://scripts/construction/utilities/construction_utility_execution_profile.gd")
const STATE_SCHEMA := "planet_simulator.construction_utility_profile_store.v1"
const STATE_FIELDS: Array[String] = ["schema", "generation", "profiles", "checksum"]
var _profiles := {}; var _generation := 0

func publish(profile: Dictionary) -> Dictionary:
	var checked := ProfileScript.validate(profile); if not bool(checked.get("success", false)): return checked
	var key := String(profile["network_id"])
	if _profiles.has(key):
		var current: Dictionary = _profiles[key]
		if String(current["checksum"]) == String(profile["checksum"]): return ContractUtils.success({"replay": true, "generation": _generation})
		if int(profile["tick"]) < int(current["tick"]): return ContractUtils.failure("STALE_CONSTRUCTION_UTILITY_EXECUTION_PROFILE")
		if int(profile["tick"]) == int(current["tick"]): return ContractUtils.failure("CONSTRUCTION_UTILITY_SAME_TICK_MUTATION")
	_profiles[key] = profile.duplicate(true); _generation += 1; return ContractUtils.success({"replay": false, "generation": _generation})
func get_profile(network_id: String) -> Dictionary: return Dictionary(_profiles.get(network_id, {})).duplicate(true)
func get_all() -> Array:
	var result: Array = []
	for profile in _profiles.values(): result.append(Dictionary(profile).duplicate(true))
	result.sort_custom(func(a,b): return String(a["network_id"]) < String(b["network_id"])); return result
func get_generation() -> int: return _generation
func remove(network_id: String, expected_checksum: String = "") -> Dictionary:
	if not _profiles.has(network_id): return ContractUtils.success({"replay": true, "generation": _generation})
	if not expected_checksum.is_empty() and String(_profiles[network_id]["checksum"]) != expected_checksum: return ContractUtils.failure("CONSTRUCTION_UTILITY_PROFILE_REMOVE_PRECONDITION_MISMATCH")
	_profiles.erase(network_id); _generation += 1; return ContractUtils.success({"replay": false, "generation": _generation})
func export_state() -> Dictionary:
	var value := {"schema": STATE_SCHEMA, "generation": _generation, "profiles": get_all(), "checksum": ""}; value["checksum"] = compute_state_checksum(value); return value
func load_state(state: Dictionary) -> Dictionary:
	var checked := validate_state(state); if not bool(checked.get("success", false)): return checked
	var next := {}; for profile in state["profiles"]: next[String(profile["network_id"])] = Dictionary(profile).duplicate(true)
	_profiles = next; _generation = int(state["generation"]); return ContractUtils.success()
static func validate_state(state: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(state, STATE_FIELDS); if not bool(exact.get("success", false)): return exact
	if state.get("schema") != STATE_SCHEMA: return ContractUtils.failure("UNSUPPORTED_CONSTRUCTION_UTILITY_PROFILE_STORE_SCHEMA")
	if not UtilsScript.is_json_integer(state.get("generation")) or int(state["generation"]) < 0 or typeof(state.get("profiles")) != TYPE_ARRAY: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_PROFILE_STORE_STATE")
	var previous := ""; var seen := {}
	for profile in state["profiles"]:
		if typeof(profile) != TYPE_DICTIONARY: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_PROFILE_STORE_PROFILE")
		var checked := ProfileScript.validate(profile); if not bool(checked.get("success", false)): return checked
		var key := String(profile["network_id"]); if seen.has(key) or (not previous.is_empty() and key < previous): return ContractUtils.failure("NON_CANONICAL_CONSTRUCTION_UTILITY_PROFILE_STORE_PROFILES")
		seen[key] = true; previous = key
	if String(state.get("checksum", "")) != compute_state_checksum(state): return ContractUtils.failure("CONSTRUCTION_UTILITY_PROFILE_STORE_CHECKSUM_MISMATCH")
	return ContractUtils.success()
static func compute_state_checksum(state: Dictionary) -> String:
	var payload := state.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
