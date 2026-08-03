extends RefCounted
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const RecipeScript = preload("res://scripts/construction/fabrication/construction_fabrication_recipe.gd")
const SCHEMA := "planet_simulator.construction_fabrication_catalog.v1"
const FIELDS: Array[String] = ["schema", "generation", "recipes", "checksum"]
var _recipes: Dictionary = {}
var _generation := 0
func setup() -> Dictionary: _recipes.clear(); _generation = 0; return _success()
func publish(recipe: Dictionary) -> Dictionary:
	var checked := RecipeScript.validate(recipe); if not bool(checked.get("success", false)): return checked
	var recipe_id := String(recipe["recipe_id"]); var key := "%s@%d" % [recipe_id, int(recipe["recipe_version"])]
	if _recipes.has(key):
		if String(_recipes[key]["checksum"]) == String(recipe["checksum"]): return _success({"replay": true, "recipe": get_recipe(recipe_id, int(recipe["recipe_version"])), "generation": _generation})
		return _failure("CONSTRUCTION_FABRICATION_RECIPE_VERSION_CONFLICT")
	var latest := latest_version(recipe_id)
	if latest > 0 and int(recipe["recipe_version"]) != latest + 1: return _failure("CONSTRUCTION_FABRICATION_RECIPE_VERSION_GAP")
	if latest == 0 and int(recipe["recipe_version"]) != 1: return _failure("CONSTRUCTION_FABRICATION_RECIPE_FIRST_VERSION_MUST_BE_ONE")
	_recipes[key] = _canonical(recipe); _generation += 1
	return _success({"replay": false, "recipe": get_recipe(recipe_id, int(recipe["recipe_version"])), "generation": _generation})
func get_recipe(recipe_id: String, version: int = -1) -> Dictionary:
	var resolved := latest_version(recipe_id) if version < 0 else version
	return Dictionary(_recipes.get("%s@%d" % [recipe_id, resolved], {})).duplicate(true)
func latest_version(recipe_id: String) -> int:
	var latest := 0
	for key in _recipes:
		var recipe: Dictionary = _recipes[key]
		if String(recipe["recipe_id"]) == recipe_id: latest = maxi(latest, int(recipe["recipe_version"]))
	return latest
func list_recipes() -> Array:
	var keys := _recipes.keys(); keys.sort(); var result: Array = []
	for key in keys: result.append(Dictionary(_recipes[key]).duplicate(true))
	return result
func get_generation() -> int: return _generation
func to_dict() -> Dictionary:
	var value := {"schema": SCHEMA, "generation": _generation, "recipes": list_recipes(), "checksum": ""}; value["checksum"] = compute_checksum(value); return value
func load_dict(value: Dictionary) -> Dictionary:
	var checked := validate_state(value); if not bool(checked.get("success", false)): return checked
	var next: Dictionary = {}
	for recipe in value["recipes"]:
		next["%s@%d" % [String(recipe["recipe_id"]), int(recipe["recipe_version"])]] = _canonical(recipe)
	_recipes = next; _generation = int(value["generation"]); return _success({"recipe_count": _recipes.size(), "generation": _generation})
static func validate_state(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_FABRICATION_CATALOG_SCHEMA")
	if not UtilsScript.is_json_integer(value.get("generation")) or int(value["generation"]) < 0: return _failure("INVALID_CONSTRUCTION_FABRICATION_CATALOG_GENERATION")
	if typeof(value.get("recipes")) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_FABRICATION_CATALOG_RECIPES")
	var previous := ""; var seen := {}; var versions: Dictionary = {}
	for raw in value["recipes"]:
		if typeof(raw) != TYPE_DICTIONARY: return _failure("INVALID_PERSISTED_CONSTRUCTION_FABRICATION_RECIPE")
		var checked := RecipeScript.validate(raw); if not bool(checked.get("success", false)): return checked
		var key := "%s@%d" % [String(raw["recipe_id"]), int(raw["recipe_version"])]
		if seen.has(key) or (not previous.is_empty() and key < previous): return _failure("NON_CANONICAL_CONSTRUCTION_FABRICATION_CATALOG")
		var id := String(raw["recipe_id"]); var expected := int(versions.get(id, 0)) + 1
		if int(raw["recipe_version"]) != expected: return _failure("INVALID_PERSISTED_CONSTRUCTION_FABRICATION_RECIPE_VERSION_CHAIN")
		versions[id] = int(raw["recipe_version"]); seen[key] = true; previous = key
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_FABRICATION_CATALOG_CHECKSUM_MISMATCH")
	return _success()
static func compute_checksum(value: Dictionary) -> String: var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _canonical(value: Dictionary) -> Dictionary: var result := UtilsScript.canonicalize(value); return Dictionary(result.get("value", {})).duplicate(true) if bool(result.get("success", false)) else {}
static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}
