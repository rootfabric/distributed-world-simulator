extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const MaterialScript = preload("res://scripts/construction/parametric/construction_parametric_material.gd")
const DefinitionScript = preload("res://scripts/construction/parametric/construction_parametric_member_definition.gd")

const STATE_SCHEMA := "planet_simulator.construction_parametric_catalog_state.v1"
const STATE_FIELDS: Array[String] = ["schema", "generation", "materials", "definitions", "checksum"]

var _materials: Dictionary = {}
var _definitions: Dictionary = {}
var _generation: int = 0

func publish_material(material: Dictionary) -> Dictionary:
	var checked := MaterialScript.validate(material)
	if not bool(checked.get("success", false)): return checked
	var material_id := String(material["material_id"])
	if _materials.has(material_id):
		if String(_materials[material_id]["checksum"]) == String(material["checksum"]): return ParametricUtils.success({"replay": true, "generation": _generation})
		return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_MATERIAL_CONFLICT")
	_materials[material_id] = material.duplicate(true); _generation += 1
	return ParametricUtils.success({"replay": false, "generation": _generation})

func publish_definition(definition: Dictionary) -> Dictionary:
	var checked := DefinitionScript.validate(definition)
	if not bool(checked.get("success", false)): return checked
	for material_id in _referenced_material_ids(definition):
		if not _materials.has(material_id): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_DEFINITION_MATERIAL_NOT_FOUND", {"material_id": material_id})
	var definition_id := String(definition["member_definition_id"]); var version := int(definition["definition_version"])
	var versions: Dictionary = _definitions.get(definition_id, {})
	if versions.has(version):
		if String(versions[version]["checksum"]) == String(definition["checksum"]): return ParametricUtils.success({"replay": true, "generation": _generation})
		return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_DEFINITION_VERSION_CONFLICT")
	var expected := 1 if versions.is_empty() else int(versions.keys().max()) + 1
	if version != expected: return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_DEFINITION_VERSION_GAP")
	versions[version] = definition.duplicate(true); _definitions[definition_id] = versions; _generation += 1
	return ParametricUtils.success({"replay": false, "generation": _generation})

func get_material(material_id: String) -> Dictionary:
	return Dictionary(_materials.get(material_id, {})).duplicate(true)

func get_definition(definition_id: String, version: int = 0) -> Dictionary:
	if not _definitions.has(definition_id): return {}
	var versions: Dictionary = _definitions[definition_id]
	var selected := version
	if selected == 0: selected = int(versions.keys().max())
	return Dictionary(versions.get(selected, {})).duplicate(true)

func get_materials_for_definition(definition: Dictionary) -> Array:
	var result: Array = []
	for material_id in _referenced_material_ids(definition):
		if _materials.has(material_id): result.append(Dictionary(_materials[material_id]).duplicate(true))
	result.sort_custom(func(left, right): return String(left["material_id"]) < String(right["material_id"]))
	return result

func get_generation() -> int:
	return _generation

func export_state() -> Dictionary:
	var materials: Array = []
	var material_ids: Array = _materials.keys(); material_ids.sort()
	for material_id in material_ids: materials.append(Dictionary(_materials[material_id]).duplicate(true))
	var definitions: Array = []
	var definition_ids: Array = _definitions.keys(); definition_ids.sort()
	for definition_id in definition_ids:
		var versions: Dictionary = _definitions[definition_id]; var version_ids: Array = versions.keys(); version_ids.sort()
		for version in version_ids: definitions.append(Dictionary(versions[version]).duplicate(true))
	var state := {"schema": STATE_SCHEMA, "generation": _generation, "materials": materials, "definitions": definitions, "checksum": ""}
	state["checksum"] = compute_state_checksum(state)
	return state

func load_state(state: Dictionary) -> Dictionary:
	var checked := validate_state(state)
	if not bool(checked.get("success", false)): return checked
	var candidate = get_script().new()
	for material in state["materials"]:
		checked = candidate.publish_material(material); if not bool(checked.get("success", false)): return checked
	for definition in state["definitions"]:
		checked = candidate.publish_definition(definition); if not bool(checked.get("success", false)): return checked
	if int(candidate.get_generation()) != int(state["generation"]): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_CATALOG_GENERATION_MISMATCH")
	_materials = candidate._materials.duplicate(true); _definitions = candidate._definitions.duplicate(true); _generation = candidate._generation
	return ParametricUtils.success()

static func validate_state(state: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(state, STATE_FIELDS)
	if not bool(exact.get("success", false)): return exact
	if state.get("schema") != STATE_SCHEMA: return ParametricUtils.failure("UNSUPPORTED_CONSTRUCTION_PARAMETRIC_CATALOG_STATE_SCHEMA")
	if not UtilsScript.is_json_integer(state.get("generation")) or int(state["generation"]) < 0: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_CATALOG_GENERATION")
	if typeof(state.get("materials")) != TYPE_ARRAY or typeof(state.get("definitions")) != TYPE_ARRAY: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_CATALOG_COLLECTION")
	var material_ids := {}; var previous := ""
	for material in state["materials"]:
		if typeof(material) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_CATALOG_MATERIAL")
		var checked := MaterialScript.validate(material); if not bool(checked.get("success", false)): return checked
		var material_id := String(material["material_id"])
		if material_ids.has(material_id) or (not previous.is_empty() and material_id < previous): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_CATALOG_MATERIAL_ORDER")
		material_ids[material_id] = true; previous = material_id
	var previous_key := ""; var seen := {}
	for definition in state["definitions"]:
		if typeof(definition) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_CATALOG_DEFINITION")
		var checked := DefinitionScript.validate(definition); if not bool(checked.get("success", false)): return checked
		var key := "%s#%08d" % [String(definition["member_definition_id"]), int(definition["definition_version"])]
		if seen.has(key) or (not previous_key.is_empty() and key < previous_key): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_CATALOG_DEFINITION_ORDER")
		seen[key] = true; previous_key = key
	if String(state.get("checksum", "")) != compute_state_checksum(state): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_CATALOG_STATE_CHECKSUM_MISMATCH")
	return ParametricUtils.success()

static func compute_state_checksum(state: Dictionary) -> String:
	var payload := state.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)

static func _referenced_material_ids(definition: Dictionary) -> Array:
	var ids: Array = []
	if not String(definition.get("primary_material_id", "")).is_empty(): ids.append(String(definition["primary_material_id"]))
	for layer in definition.get("layers", []):
		var material_id := String(layer.get("material_id", ""))
		if not ids.has(material_id): ids.append(material_id)
	ids.sort(); return ids
