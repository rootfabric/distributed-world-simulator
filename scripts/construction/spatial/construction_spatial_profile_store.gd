extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ProfileScript = preload("res://scripts/construction/spatial/construction_spatial_profile.gd")
const CompilerScript = preload("res://scripts/construction/spatial/construction_spatial_compiler.gd")

const SCHEMA := "planet_simulator.construction_spatial_profile_store.v1"
const FIELDS: Array[String] = ["schema", "generation", "profiles", "checksum"]
var _profiles_by_construct_id: Dictionary = {}
var _generation: int = 0

func setup() -> Dictionary:
	_profiles_by_construct_id.clear()
	_generation = 0
	return _success()

func compile_snapshot(snapshot: Dictionary) -> Dictionary:
	var compiled := CompilerScript.compile(snapshot)
	if not bool(compiled.get("success", false)):
		return compiled
	var published := publish_profile(compiled["profile"])
	if bool(published.get("success", false)):
		published["compiled"] = true
	return published

func publish_profile(profile: Dictionary) -> Dictionary:
	var validation := ProfileScript.validate(profile)
	if not bool(validation.get("success", false)):
		return validation
	var construct_id := String(profile["construct_id"])
	if _profiles_by_construct_id.has(construct_id):
		var existing: Dictionary = _profiles_by_construct_id[construct_id]
		if String(existing["checksum"]) == String(profile["checksum"]):
			return _success({"replay": true, "no_change": true, "profile": existing.duplicate(true), "generation": _generation})
		var incoming_revision := int(profile["construct_revision"])
		var current_revision := int(existing["construct_revision"])
		if incoming_revision < current_revision:
			return _failure("STALE_CONSTRUCTION_SPATIAL_PROFILE")
		if incoming_revision == current_revision:
			return _failure("CONSTRUCTION_SPATIAL_PROFILE_SAME_REVISION_CONFLICT")
	_profiles_by_construct_id[construct_id] = _canonical_dictionary(profile)
	_generation += 1
	return _success({"replay": false, "no_change": false, "profile": get_profile(construct_id), "generation": _generation})

func remove_profile(construct_id: String, expected_construct_checksum: String) -> Dictionary:
	if not _profiles_by_construct_id.has(construct_id):
		return _success({"replay": true, "removed": false, "generation": _generation})
	if String(_profiles_by_construct_id[construct_id]["construct_checksum"]) != expected_construct_checksum:
		return _failure("CONSTRUCTION_SPATIAL_PROFILE_REMOVE_PRECONDITION_MISMATCH")
	_profiles_by_construct_id.erase(construct_id)
	_generation += 1
	return _success({"replay": false, "removed": true, "generation": _generation})

func get_profile(construct_id: String) -> Dictionary:
	return Dictionary(_profiles_by_construct_id.get(construct_id, {})).duplicate(true)
func list_profiles() -> Array:
	return _sorted_values(_profiles_by_construct_id)
func get_generation() -> int:
	return _generation

func to_dict() -> Dictionary:
	var value := {"schema": SCHEMA, "generation": _generation, "profiles": _sorted_values(_profiles_by_construct_id), "checksum": ""}
	value["checksum"] = compute_checksum(value)
	return value

func load_dict(value: Dictionary) -> Dictionary:
	var validation := validate_state(value)
	if not bool(validation.get("success", false)):
		return validation
	var canonical := _canonical_dictionary(value)
	var next_profiles: Dictionary = {}
	for profile in canonical["profiles"]:
		next_profiles[String(profile["construct_id"])] = Dictionary(profile).duplicate(true)
	_profiles_by_construct_id = next_profiles
	_generation = int(canonical["generation"])
	return _success({"profile_count": _profiles_by_construct_id.size(), "generation": _generation})

static func validate_state(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_SPATIAL_PROFILE_STORE_SCHEMA")
	if not UtilsScript.is_json_integer(value.get("generation")) or int(value["generation"]) < 0:
		return _failure("INVALID_CONSTRUCTION_SPATIAL_PROFILE_STORE_GENERATION")
	if typeof(value.get("profiles")) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_SPATIAL_PROFILE_STORE_PROFILES")
	var seen: Dictionary = {}
	var previous := ""
	for raw in value["profiles"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_PERSISTED_CONSTRUCTION_SPATIAL_PROFILE")
		var checked := ProfileScript.validate(raw)
		if not bool(checked.get("success", false)):
			return checked
		var construct_id := String(raw["construct_id"])
		if seen.has(construct_id):
			return _failure("DUPLICATE_PERSISTED_CONSTRUCTION_SPATIAL_PROFILE")
		if not previous.is_empty() and construct_id < previous:
			return _failure("PERSISTED_CONSTRUCTION_SPATIAL_PROFILES_NOT_SORTED")
		seen[construct_id] = true
		previous = construct_id
	if String(value.get("checksum", "")) != compute_checksum(value):
		return _failure("CONSTRUCTION_SPATIAL_PROFILE_STORE_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("CONSTRUCTION_SPATIAL_PROFILE_STORE_NOT_JSON_SAFE")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)
static func _sorted_values(values: Dictionary) -> Array:
	var ids := values.keys()
	ids.sort()
	var result: Array = []
	for identifier in ids:
		result.append(Dictionary(values[identifier]).duplicate(true))
	return result
static func _canonical_dictionary(value: Dictionary) -> Dictionary:
	var canonical := UtilsScript.canonicalize(value)
	return Dictionary(canonical.get("value", {})).duplicate(true) if bool(canonical.get("success", false)) else {}
static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result
static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
