extends RefCounted

const VisualProfile = preload("res://scripts/labs/t1/presentation/t1_part_visual_profile.gd")
const CATALOG_PATH := "res://config/construction/t1-part-visual-catalog.v1.json"
const SCHEMA := "planet_simulator.t1_part_visual_catalog.v1"

var _catalog: Dictionary = {}
var _profiles_by_id: Dictionary = {}
var _manifest_hash := ""

func load_catalog(path: String = CATALOG_PATH) -> Dictionary:
	if not FileAccess.file_exists(path): return _failure("T1A1_CATALOG_NOT_FOUND")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _failure("T1A1_CATALOG_OPEN_FAILED")
	var decoded = JSON.parse_string(file.get_as_text())
	if typeof(decoded) != TYPE_DICTIONARY: return _failure("T1A1_CATALOG_INVALID_JSON")
	var catalog: Dictionary = decoded
	var validation := validate_catalog(catalog)
	if not bool(validation.get("success", false)): return validation
	_catalog = catalog.duplicate(true)
	_profiles_by_id = {}
	for raw_profile in Array(_catalog["profiles"]):
		var profile: Dictionary = raw_profile
		_profiles_by_id[String(profile["visual_profile_id"])] = profile.duplicate(true)
	_manifest_hash = compute_manifest_hash(_catalog)
	return {"success": true, "manifest_hash": _manifest_hash, "profile_count": _profiles_by_id.size()}

func validate_catalog(catalog: Dictionary) -> Dictionary:
	if String(catalog.get("schema", "")) != SCHEMA: return _failure("T1A1_CATALOG_SCHEMA_MISMATCH")
	if typeof(catalog.get("catalog_revision")) != TYPE_STRING or String(catalog["catalog_revision"]).is_empty(): return _failure("T1A1_CATALOG_REVISION_INVALID")
	if typeof(catalog.get("profiles")) != TYPE_ARRAY or Array(catalog["profiles"]).is_empty(): return _failure("T1A1_CATALOG_PROFILES_INVALID")
	if typeof(catalog.get("semantic_bindings")) != TYPE_DICTIONARY: return _failure("T1A1_SEMANTIC_BINDINGS_INVALID")
	if typeof(catalog.get("fixture_binding_rules")) != TYPE_DICTIONARY: return _failure("T1A1_FIXTURE_BINDING_RULES_INVALID")
	var ids := {}
	for raw_profile in Array(catalog["profiles"]):
		if typeof(raw_profile) != TYPE_DICTIONARY: return _failure("T1A1_PROFILE_ENTRY_INVALID")
		var profile: Dictionary = raw_profile
		var result := VisualProfile.validate(profile)
		if not bool(result.get("success", false)): return result
		var profile_id := String(profile["visual_profile_id"])
		if ids.has(profile_id): return _failure("T1A1_DUPLICATE_VISUAL_PROFILE_ID")
		ids[profile_id] = true
	var bindings: Dictionary = catalog["semantic_bindings"]
	for semantic_class in VisualProfile.REPRESENTATION_CLASSES:
		if not bindings.has(semantic_class): return _failure("T1A1_MISSING_SEMANTIC_BINDING")
		if not ids.has(String(bindings[semantic_class])): return _failure("T1A1_UNKNOWN_SEMANTIC_PROFILE")
	for profile_id in ["D0", "D1"]:
		if not Dictionary(catalog["fixture_binding_rules"]).has(profile_id): return _failure("T1A1_MISSING_FIXTURE_BINDING_RULES")
		var rules = Dictionary(catalog["fixture_binding_rules"])[profile_id]
		if typeof(rules) != TYPE_ARRAY or Array(rules).is_empty(): return _failure("T1A1_FIXTURE_RULES_INVALID")
		for raw_rule in Array(rules):
			if typeof(raw_rule) != TYPE_DICTIONARY: return _failure("T1A1_FIXTURE_RULE_INVALID")
			var rule: Dictionary = raw_rule
			if not _has_exact_fields(rule, ["start", "end", "semantic_class"]): return _failure("T1A1_FIXTURE_RULE_FIELDS_MISMATCH")
			if not _json_integer(rule["start"]) or not _json_integer(rule["end"]) or int(rule["start"]) < 0 or int(rule["end"]) < int(rule["start"]): return _failure("T1A1_FIXTURE_RULE_RANGE_INVALID")
			if not VisualProfile.REPRESENTATION_CLASSES.has(String(rule["semantic_class"])): return _failure("T1A1_FIXTURE_RULE_SEMANTIC_INVALID")
	return {"success": true}

func resolve_profile(profile_id: String) -> Dictionary:
	if _profiles_by_id.is_empty():
		var loaded := load_catalog()
		if not bool(loaded.get("success", false)): return loaded
	if not _profiles_by_id.has(profile_id): return _failure("T1A1_VISUAL_PROFILE_NOT_FOUND")
	return {"success": true, "profile": Dictionary(_profiles_by_id[profile_id]).duplicate(true)}

func resolve_semantic(semantic_class: String) -> Dictionary:
	if _catalog.is_empty():
		var loaded := load_catalog()
		if not bool(loaded.get("success", false)): return loaded
	var bindings: Dictionary = _catalog["semantic_bindings"]
	if not bindings.has(semantic_class): return _failure("T1A1_SEMANTIC_CLASS_NOT_BOUND")
	return resolve_profile(String(bindings[semantic_class]))

func fixture_rules(profile_id: String) -> Dictionary:
	if _catalog.is_empty():
		var loaded := load_catalog()
		if not bool(loaded.get("success", false)): return loaded
	var rules: Dictionary = _catalog["fixture_binding_rules"]
	if not rules.has(profile_id): return _failure("T1A1_FIXTURE_PROFILE_NOT_BOUND")
	return {"success": true, "rules": Array(rules[profile_id]).duplicate(true)}

func manifest_hash() -> String:
	if _manifest_hash.is_empty():
		var loaded := load_catalog()
		if not bool(loaded.get("success", false)): return ""
	return _manifest_hash

static func compute_manifest_hash(catalog: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(String(catalog.get("schema", "")))
	lines.append(String(catalog.get("catalog_revision", "")))
	var profile_lines: Array[String] = []
	for raw_profile in Array(catalog.get("profiles", [])):
		var profile: Dictionary = raw_profile
		profile_lines.append("%s=%s" % [String(profile.get("visual_profile_id", "")), String(profile.get("checksum", ""))])
	profile_lines.sort()
	for line in profile_lines: lines.append(line)
	var bindings: Dictionary = catalog.get("semantic_bindings", {})
	var binding_keys: Array = bindings.keys(); binding_keys.sort()
	for key in binding_keys: lines.append("binding:%s=%s" % [String(key), String(bindings[key])])
	var rules_dict: Dictionary = catalog.get("fixture_binding_rules", {})
	var profile_keys: Array = rules_dict.keys(); profile_keys.sort()
	for profile_key in profile_keys:
		for raw_rule in Array(rules_dict[profile_key]):
			var rule: Dictionary = raw_rule
			lines.append("rule:%s:%d:%d:%s" % [String(profile_key), int(rule["start"]), int(rule["end"]), String(rule["semantic_class"])])
	return "\n".join(lines).sha256_text()

static func _json_integer(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]: return false
	var numeric := float(value)
	return not is_nan(numeric) and not is_inf(numeric) and absf(numeric - float(int(numeric))) <= 0.000001

static func _has_exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size(): return false
	for field in fields:
		if not value.has(field): return false
	return true

static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code}
