extends RefCounted

# Pure static PlanetDefinition resolver for catalog-driven worlds. It never owns
# mutable runtime state: callers resolve a world entry from
# config/worlds/catalog.json and receive a derived, deterministic definition and
# generator hash (sha256 over canonical JSON). Mirrors the static-module style of
# earth_surface_render_projector.gd.
#
# The catalog is the single authoritative seed source. Generation rules files
# must not carry their own seed anymore; consumers receive the seed as a
# parameter resolved through this module so that every side of a networked
# session computes an identical world definition hash.
const CATALOG_PATH: String = "res://config/worlds/catalog.json"
const DEFAULT_WORLD_ID: String = "earth"
const DEFAULT_GENERATOR_VERSION: String = "earth-rule-pipeline-v1"
# Test-only injection hook: when this environment variable holds a positive
# integer, it overrides the catalog seed so tests can prove fail-closed
# behaviour on world definition mismatch. Production runs never set it.
const TEST_SEED_OVERRIDE_ENV: String = "PLANET_SIMULATOR_TEST_WORLD_SEED"
const DEFINITION_FIELDS: Array[String] = [
	"world_id",
	"generator_version",
	"seed",
	"rules_config",
]


static func load_definition(world_id: String = DEFAULT_WORLD_ID) -> Dictionary:
	var definition := _load_catalog_definition(world_id)
	if definition.is_empty():
		return {}
	var override_seed := _environment_seed_override()
	if override_seed > 0:
		definition["seed"] = override_seed
	if int(definition["seed"]) <= 0 or String(definition["rules_config"]).is_empty():
		return {}
	return definition


static func get_world_seed(world_id: String = DEFAULT_WORLD_ID) -> int:
	var definition := load_definition(world_id)
	return int(definition.get("seed", 0))


static func compute_rules_config_content_hash(rules_config_path: String) -> String:
	if rules_config_path.is_empty() or not FileAccess.file_exists(rules_config_path):
		return ""
	return sha256_hex(FileAccess.get_file_as_string(rules_config_path))


static func compute_definition_hash(definition: Dictionary) -> String:
	if not _is_valid_definition_shape(definition):
		return ""
	return sha256_hex(canonical_json({
		"world_id": String(definition.get("world_id", "")),
		"generator_version": String(definition.get("generator_version", "")),
		"seed": int(definition.get("seed", 0)),
		"rules_config_sha256": compute_rules_config_content_hash(
			String(definition.get("rules_config", ""))
		),
	}))


static func get_world_definition_hash(world_id: String = DEFAULT_WORLD_ID) -> String:
	return compute_definition_hash(load_definition(world_id))


# Compact identity published on the wire by the server during session setup and
# recomputed independently by the client for comparison.
static func create_announcement(world_id: String = DEFAULT_WORLD_ID) -> Dictionary:
	var definition := load_definition(world_id)
	if definition.is_empty():
		return {}
	return {
		"world_id": String(definition["world_id"]),
		"generator_version": String(definition["generator_version"]),
		"generator_hash": compute_definition_hash(definition),
	}


static func evaluate_announcement(expected: Dictionary, announced: Dictionary) -> Dictionary:
	# expected is computed locally from res:// configs; announced arrives from
	# the remote peer. Any divergence fails closed with WORLD_DEFINITION_MISMATCH.
	if expected.is_empty():
		return _failure("WORLD_DEFINITION_UNRESOLVABLE")
	for field in ["world_id", "generator_version", "generator_hash"]:
		if not announced.has(field) or typeof(announced[field]) != TYPE_STRING:
			return _failure("INVALID_WORLD_DEFINITION_ANNOUNCEMENT", {"field": field})
	if String(expected["world_id"]) != String(announced["world_id"]) \
			or String(expected["generator_version"]) != String(announced["generator_version"]) \
			or String(expected["generator_hash"]) != String(announced["generator_hash"]):
		return _failure("WORLD_DEFINITION_MISMATCH", {
			"expected": expected.duplicate(true),
			"announced": announced.duplicate(true),
		})
	return _success({"compatible": true})


# Deterministic JSON: object keys sorted lexicographically at every depth,
# arrays keep order, scalars use Godot's stable JSON scalar encoding. Both
# peers run the same engine build, so encoding is byte-identical.
static func canonical_json(value) -> String:
	if value is Dictionary:
		var dictionary: Dictionary = value
		var keys: Array = dictionary.keys()
		keys.sort()
		var parts: PackedStringArray = []
		for key in keys:
			parts.append("%s:%s" % [canonical_json(String(key)), canonical_json(dictionary[key])])
		return "{%s}" % ",".join(parts)
	if value is Array:
		var parts: PackedStringArray = []
		for element in value:
			parts.append(canonical_json(element))
		return "[%s]" % ",".join(parts)
	return JSON.stringify(value)


static func sha256_hex(text: String) -> String:
	return text.sha256_text()


static func _load_catalog_definition(world_id: String) -> Dictionary:
	var catalog_value = _load_json(CATALOG_PATH)
	if catalog_value.is_empty():
		return {}
	for entry_value in catalog_value.get("worlds", []):
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		if String(entry.get("id", "")) != world_id:
			continue
		return {
			"world_id": world_id,
			"generator_version": String(entry.get("generator_version", DEFAULT_GENERATOR_VERSION)),
			"seed": int(entry.get("seed", 0)),
			"rules_config": String(entry.get("rules_config", "")),
		}
	return {}


static func _is_valid_definition_shape(definition: Dictionary) -> bool:
	for field in DEFINITION_FIELDS:
		if not definition.has(field):
			return false
	return int(definition.get("seed", 0)) > 0 \
		and not String(definition.get("rules_config", "")).is_empty()


static func _environment_seed_override() -> int:
	if not OS.has_environment(TEST_SEED_OVERRIDE_ENV):
		return 0
	var parsed := int(OS.get_environment(TEST_SEED_OVERRIDE_ENV).strip_edges())
	return parsed if parsed > 0 else 0


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
