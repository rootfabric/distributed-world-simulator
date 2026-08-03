extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_fabrication_recipe.v1"
const FIELDS: Array[String] = ["schema", "recipe_id", "recipe_version", "display_name", "input_requirements", "output_products", "required_machine_capabilities", "required_utility_kinds", "work_units", "metadata", "checksum"]
const INPUT_FIELDS: Array[String] = ["definition_id", "quantity", "components_exact"]
const OUTPUT_FIELDS: Array[String] = ["product_key", "definition_id", "display_name", "quantity", "components"]

static func create(recipe_id: String, recipe_version: int, display_name: String, input_requirements: Array, output_products: Array, required_machine_capabilities: Array, required_utility_kinds: Array, work_units: int, metadata: Dictionary = {}) -> Dictionary:
	var value := {"schema": SCHEMA, "recipe_id": recipe_id, "recipe_version": recipe_version, "display_name": display_name, "input_requirements": _sorted_rows(input_requirements, "definition_id"), "output_products": _sorted_rows(output_products, "product_key"), "required_machine_capabilities": _sorted_strings(required_machine_capabilities), "required_utility_kinds": _sorted_strings(required_utility_kinds), "work_units": work_units, "metadata": metadata.duplicate(true), "checksum": ""}
	value["checksum"] = compute_checksum(value)
	return value

static func input_requirement(definition_id: String, quantity: int, components_exact: Dictionary = {}) -> Dictionary:
	return {"definition_id": definition_id, "quantity": quantity, "components_exact": components_exact.duplicate(true)}
static func output_product(product_key: String, definition_id: String, display_name: String, quantity: int = 1, components: Dictionary = {}) -> Dictionary:
	return {"product_key": product_key, "definition_id": definition_id, "display_name": display_name, "quantity": quantity, "components": components.duplicate(true)}

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_FABRICATION_RECIPE_SCHEMA")
	if not _is_path_id(String(value.get("recipe_id", "")), "fabrication-recipe/"): return _failure("INVALID_CONSTRUCTION_FABRICATION_RECIPE_ID")
	if not UtilsScript.is_json_integer(value.get("recipe_version")) or int(value["recipe_version"]) < 1: return _failure("INVALID_CONSTRUCTION_FABRICATION_RECIPE_VERSION")
	if typeof(value.get("display_name")) != TYPE_STRING or String(value["display_name"]).strip_edges().is_empty(): return _failure("CONSTRUCTION_FABRICATION_RECIPE_NAME_REQUIRED")
	var inputs := _validate_inputs(value.get("input_requirements")); if not bool(inputs.get("success", false)): return inputs
	var outputs := _validate_outputs(value.get("output_products")); if not bool(outputs.get("success", false)): return outputs
	for spec in [["required_machine_capabilities", false], ["required_utility_kinds", true]]:
		var checked := _validate_upper_list(value.get(String(spec[0])), bool(spec[1])); if not bool(checked.get("success", false)): return checked
	if not UtilsScript.is_json_integer(value.get("work_units")) or int(value["work_units"]) < 1: return _failure("INVALID_CONSTRUCTION_FABRICATION_WORK_UNITS")
	if typeof(value.get("metadata")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["metadata"]).get("success", false)): return _failure("INVALID_CONSTRUCTION_FABRICATION_RECIPE_METADATA")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_FABRICATION_RECIPE_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)): return _failure("CONSTRUCTION_FABRICATION_RECIPE_NOT_JSON_SAFE")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)

static func _validate_inputs(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or Array(value).is_empty(): return _failure("CONSTRUCTION_FABRICATION_INPUTS_REQUIRED")
	var previous := ""; var seen := {}
	for raw in value:
		if typeof(raw) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_FABRICATION_INPUT")
		var exact := UtilsScript.validate_exact_fields(raw, INPUT_FIELDS); if not bool(exact.get("success", false)): return exact
		var definition_id := String(raw.get("definition_id", ""))
		if not _is_token(definition_id) or seen.has(definition_id): return _failure("INVALID_CONSTRUCTION_FABRICATION_INPUT_DEFINITION")
		if not previous.is_empty() and definition_id < previous: return _failure("CONSTRUCTION_FABRICATION_INPUTS_NOT_SORTED")
		if not UtilsScript.is_json_integer(raw.get("quantity")) or int(raw["quantity"]) < 1: return _failure("INVALID_CONSTRUCTION_FABRICATION_INPUT_QUANTITY")
		if typeof(raw.get("components_exact")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(raw["components_exact"]).get("success", false)): return _failure("INVALID_CONSTRUCTION_FABRICATION_INPUT_COMPONENTS")
		seen[definition_id] = true; previous = definition_id
	return _success()
static func _validate_outputs(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or Array(value).is_empty(): return _failure("CONSTRUCTION_FABRICATION_OUTPUTS_REQUIRED")
	var previous := ""; var seen := {}
	for raw in value:
		if typeof(raw) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_FABRICATION_OUTPUT")
		var exact := UtilsScript.validate_exact_fields(raw, OUTPUT_FIELDS); if not bool(exact.get("success", false)): return exact
		var key := String(raw.get("product_key", ""))
		if not _is_token(key) or seen.has(key): return _failure("INVALID_CONSTRUCTION_FABRICATION_PRODUCT_KEY")
		if not previous.is_empty() and key < previous: return _failure("CONSTRUCTION_FABRICATION_OUTPUTS_NOT_SORTED")
		if not _is_token(String(raw.get("definition_id", ""))) or typeof(raw.get("display_name")) != TYPE_STRING or String(raw["display_name"]).strip_edges().is_empty(): return _failure("INVALID_CONSTRUCTION_FABRICATION_OUTPUT_IDENTITY")
		if not UtilsScript.is_json_integer(raw.get("quantity")) or int(raw["quantity"]) < 1: return _failure("INVALID_CONSTRUCTION_FABRICATION_OUTPUT_QUANTITY")
		if typeof(raw.get("components")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(raw["components"]).get("success", false)): return _failure("INVALID_CONSTRUCTION_FABRICATION_OUTPUT_COMPONENTS")
		seen[key] = true; previous = key
	return _success()
static func _validate_upper_list(value, allow_empty: bool) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or (not allow_empty and Array(value).is_empty()): return _failure("INVALID_CONSTRUCTION_FABRICATION_REQUIREMENTS")
	var previous := ""; var seen := {}
	for raw in value:
		if typeof(raw) != TYPE_STRING: return _failure("INVALID_CONSTRUCTION_FABRICATION_REQUIREMENT")
		var text := String(raw)
		if not _is_upper(text) or seen.has(text) or (not previous.is_empty() and text < previous): return _failure("INVALID_CONSTRUCTION_FABRICATION_REQUIREMENT")
		seen[text] = true; previous = text
	return _success()
static func _sorted_rows(values: Array, key: String) -> Array:
	var result := values.duplicate(true); result.sort_custom(func(a,b): return String(a.get(key,"")) < String(b.get(key,""))); return result
static func _sorted_strings(values: Array) -> Array:
	var result: Array = []
	for raw in values:
		result.append(String(raw))
	result.sort()
	return result
static func _is_path_id(value: String, prefix: String) -> bool: return value.begins_with(prefix) and value.length() > prefix.length() and _is_token(value)
static func _is_token(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges(): return false
	for c in value:
		if not String(c) in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./:": return false
	return true
static func _is_upper(value: String) -> bool:
	if value.is_empty() or value != value.to_upper(): return false
	for c in value:
		if not String(c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_": return false
	return true
static func _success(details: Dictionary = {}) -> Dictionary: return {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}
static func _failure(code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
