extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const DefinitionScript = preload("res://scripts/construction/composites/construction_composite_definition.gd")
const InstantiationScript = preload("res://scripts/construction/composites/construction_composite_instantiation.gd")

const SCHEMA: String = "planet_simulator.construction_composite_registry.v1"
const FIELDS: Array[String] = ["schema", "generation", "definitions", "instantiations", "checksum"]

var _definitions_by_id: Dictionary = {}
var _instantiations_by_id: Dictionary = {}
var _generation: int = 0


func setup() -> Dictionary:
	_definitions_by_id.clear()
	_instantiations_by_id.clear()
	_generation = 0
	return _success()


func register_definition(definition: Dictionary) -> Dictionary:
	var validation: Dictionary = DefinitionScript.validate(definition)
	if not bool(validation.get("success", false)):
		return validation
	var definition_id: String = String(definition["composite_definition_id"])
	var version: int = int(definition["definition_version"])
	var versions: Dictionary = Dictionary(_definitions_by_id.get(definition_id, {}))
	if versions.has(version):
		var existing: Dictionary = versions[version]
		if String(existing["checksum"]) == String(definition["checksum"]):
			return _success({"replay": true, "definition": existing.duplicate(true)})
		return _failure("COMPOSITE_DEFINITION_VERSION_CONFLICT")
	var latest: int = _latest_version_in(versions)
	if latest == 0 and version != 1:
		return _failure("COMPOSITE_DEFINITION_FIRST_VERSION_MUST_BE_ONE")
	if latest > 0 and version != latest + 1:
		return _failure("COMPOSITE_DEFINITION_VERSION_SEQUENCE_GAP", {"latest_version": latest})
	versions[version] = _canonical_dictionary(definition)
	_definitions_by_id[definition_id] = versions
	_generation += 1
	return _success({"replay": false, "definition": get_definition(definition_id, version)})


func register_instantiation(instantiation: Dictionary) -> Dictionary:
	var validation: Dictionary = InstantiationScript.validate(instantiation)
	if not bool(validation.get("success", false)):
		return validation
	var definition: Dictionary = get_definition(
		String(instantiation["composite_definition_id"]),
		int(instantiation["definition_version"])
	)
	if definition.is_empty() or String(definition["checksum"]) != String(instantiation["definition_checksum"]):
		return _failure("COMPOSITE_INSTANTIATION_DEFINITION_NOT_REGISTERED")
	var definition_binding_validation: Dictionary = InstantiationScript.validate_against_definition(instantiation, definition)
	if not bool(definition_binding_validation.get("success", false)):
		return definition_binding_validation
	var instantiation_id: String = String(instantiation["instantiation_id"])
	if _instantiations_by_id.has(instantiation_id):
		var existing: Dictionary = _instantiations_by_id[instantiation_id]
		if String(existing["checksum"]) == String(instantiation["checksum"]):
			return _success({"replay": true, "instantiation": existing.duplicate(true)})
		return _failure("COMPOSITE_INSTANTIATION_ID_CONFLICT")
	for existing in _instantiations_by_id.values():
		if String(existing["build_plan_id"]) == String(instantiation["build_plan_id"]):
			return _failure("COMPOSITE_INSTANTIATION_BUILD_PLAN_CONFLICT")
		if String(existing["construct_id"]) == String(instantiation["construct_id"]):
			return _failure("COMPOSITE_INSTANTIATION_CONSTRUCT_CONFLICT")
	_instantiations_by_id[instantiation_id] = _canonical_dictionary(instantiation)
	_generation += 1
	return _success({"replay": false, "instantiation": get_instantiation(instantiation_id)})


func get_definition(definition_id: String, version: int = 0) -> Dictionary:
	if not _definitions_by_id.has(definition_id):
		return {}
	var versions: Dictionary = _definitions_by_id[definition_id]
	var resolved_version: int = version if version > 0 else _latest_version_in(versions)
	return Dictionary(versions.get(resolved_version, {})).duplicate(true)


func get_latest_version(definition_id: String) -> int:
	return _latest_version_in(Dictionary(_definitions_by_id.get(definition_id, {})))


func get_instantiation(instantiation_id: String) -> Dictionary:
	return Dictionary(_instantiations_by_id.get(instantiation_id, {})).duplicate(true)


func get_generation() -> int:
	return _generation


func to_dict() -> Dictionary:
	var definitions: Array = []
	var definition_ids: Array = _definitions_by_id.keys()
	definition_ids.sort()
	for definition_id in definition_ids:
		var versions: Dictionary = _definitions_by_id[definition_id]
		var version_ids: Array = versions.keys()
		version_ids.sort()
		for version in version_ids:
			definitions.append(Dictionary(versions[version]).duplicate(true))
	var instantiations: Array = []
	var instantiation_ids: Array = _instantiations_by_id.keys()
	instantiation_ids.sort()
	for instantiation_id in instantiation_ids:
		instantiations.append(Dictionary(_instantiations_by_id[instantiation_id]).duplicate(true))
	var value: Dictionary = {
		"schema": SCHEMA,
		"generation": _generation,
		"definitions": definitions,
		"instantiations": instantiations,
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


func load_dict(value: Dictionary) -> Dictionary:
	var validation: Dictionary = validate_state(value)
	if not bool(validation.get("success", false)):
		return validation
	var next_definitions: Dictionary = {}
	for definition in value["definitions"]:
		var definition_id: String = String(definition["composite_definition_id"])
		var versions: Dictionary = Dictionary(next_definitions.get(definition_id, {}))
		versions[int(definition["definition_version"])] = _canonical_dictionary(definition)
		next_definitions[definition_id] = versions
	var next_instantiations: Dictionary = {}
	for instantiation in value["instantiations"]:
		next_instantiations[String(instantiation["instantiation_id"])] = _canonical_dictionary(instantiation)
	_definitions_by_id = next_definitions
	_instantiations_by_id = next_instantiations
	_generation = int(value["generation"])
	return _success({
		"definition_count": value["definitions"].size(),
		"instantiation_count": value["instantiations"].size(),
	})


static func validate_state(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_COMPOSITE_REGISTRY_SCHEMA")
	if not UtilsScript.is_json_integer(value.get("generation")) or int(value["generation"]) < 0:
		return _failure("INVALID_CONSTRUCTION_COMPOSITE_REGISTRY_GENERATION")
	for field in ["definitions", "instantiations"]:
		if typeof(value.get(field)) != TYPE_ARRAY:
			return _failure("INVALID_CONSTRUCTION_COMPOSITE_REGISTRY_COLLECTION")
	var definitions_by_key: Dictionary = {}
	var latest_by_id: Dictionary = {}
	var previous_definition_key: String = ""
	for raw in value["definitions"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_COMPOSITE_REGISTRY_DEFINITION")
		var definition: Dictionary = raw
		var validation: Dictionary = DefinitionScript.validate(definition)
		if not bool(validation.get("success", false)):
			return validation
		var definition_id: String = String(definition["composite_definition_id"])
		var version: int = int(definition["definition_version"])
		var key: String = "%s|%010d" % [definition_id, version]
		if definitions_by_key.has(key):
			return _failure("DUPLICATE_CONSTRUCTION_COMPOSITE_REGISTRY_DEFINITION")
		if not previous_definition_key.is_empty() and key < previous_definition_key:
			return _failure("CONSTRUCTION_COMPOSITE_REGISTRY_DEFINITIONS_NOT_SORTED")
		var latest: int = int(latest_by_id.get(definition_id, 0))
		if version != latest + 1:
			return _failure("CONSTRUCTION_COMPOSITE_REGISTRY_VERSION_CHAIN_BROKEN")
		latest_by_id[definition_id] = version
		definitions_by_key[key] = definition
		previous_definition_key = key
	var instantiation_ids: Dictionary = {}
	var build_plan_ids: Dictionary = {}
	var construct_ids: Dictionary = {}
	var previous_instantiation_id: String = ""
	for raw in value["instantiations"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_COMPOSITE_REGISTRY_INSTANTIATION")
		var instantiation: Dictionary = raw
		var validation: Dictionary = InstantiationScript.validate(instantiation)
		if not bool(validation.get("success", false)):
			return validation
		var instantiation_id: String = String(instantiation["instantiation_id"])
		if instantiation_ids.has(instantiation_id) or build_plan_ids.has(String(instantiation["build_plan_id"])) or construct_ids.has(String(instantiation["construct_id"])):
			return _failure("CONSTRUCTION_COMPOSITE_REGISTRY_INSTANTIATION_CONFLICT")
		if not previous_instantiation_id.is_empty() and instantiation_id < previous_instantiation_id:
			return _failure("CONSTRUCTION_COMPOSITE_REGISTRY_INSTANTIATIONS_NOT_SORTED")
		var definition_key: String = "%s|%010d" % [
			String(instantiation["composite_definition_id"]),
			int(instantiation["definition_version"]),
		]
		if not definitions_by_key.has(definition_key) or String(definitions_by_key[definition_key]["checksum"]) != String(instantiation["definition_checksum"]):
			return _failure("CONSTRUCTION_COMPOSITE_REGISTRY_INSTANTIATION_DEFINITION_MISSING")
		instantiation_ids[instantiation_id] = true
		build_plan_ids[String(instantiation["build_plan_id"])] = true
		construct_ids[String(instantiation["construct_id"])] = true
		previous_instantiation_id = instantiation_id
	var expected_generation: int = value["definitions"].size() + value["instantiations"].size()
	if int(value["generation"]) != expected_generation:
		return _failure("CONSTRUCTION_COMPOSITE_REGISTRY_GENERATION_MISMATCH", {
			"expected_generation": expected_generation,
			"actual_generation": int(value["generation"]),
		})
	if String(value.get("checksum", "")) != compute_checksum(value):
		return _failure("CONSTRUCTION_COMPOSITE_REGISTRY_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("CONSTRUCTION_COMPOSITE_REGISTRY_NOT_JSON_SAFE")
	return _success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


static func _latest_version_in(versions: Dictionary) -> int:
	var latest: int = 0
	for raw_version in versions.keys():
		latest = maxi(latest, int(raw_version))
	return latest


static func _canonical_dictionary(value: Dictionary) -> Dictionary:
	var result: Dictionary = UtilsScript.canonicalize(value)
	if bool(result.get("success", false)) and result.get("value") is Dictionary:
		return Dictionary(result["value"])
	return value.duplicate(true)


static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": false, "error_code": code, "message": code}
	for key in details:
		result[key] = details[key]
	return result
