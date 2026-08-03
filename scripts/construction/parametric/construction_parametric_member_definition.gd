extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const LayerScript = preload("res://scripts/construction/parametric/construction_parametric_layer.gd")

const SCHEMA := "planet_simulator.construction_parametric_member_definition.v1"
const FIELDS: Array[String] = ["schema", "member_definition_id", "definition_version", "display_name", "member_kind", "primary_material_id", "parameter_defaults", "parameter_limits", "layers", "fabrication", "metadata", "checksum"]
const LIMIT_FIELDS: Array[String] = ["minimum", "maximum"]
const KINDS: Array[String] = ["BEAM", "PANEL", "PIPE", "CABLE", "LAYERED_WALL"]

static func expected_parameters(kind: String) -> Array[String]:
	match kind:
		"BEAM": return ["height_m", "length_m", "width_m"]
		"PANEL": return ["length_m", "thickness_m", "width_m"]
		"PIPE": return ["length_m", "outer_diameter_m", "wall_thickness_m"]
		"CABLE": return ["diameter_m", "length_m"]
		"LAYERED_WALL": return ["height_m", "length_m"]
	return []

static func create(member_definition_id: String, definition_version: int, display_name: String, member_kind: String, primary_material_id: String, parameter_defaults: Dictionary, parameter_limits: Dictionary, layers: Array = [], fabrication: Dictionary = {}, metadata: Dictionary = {}) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"member_definition_id": member_definition_id,
		"definition_version": definition_version,
		"display_name": display_name,
		"member_kind": member_kind,
		"primary_material_id": primary_material_id,
		"parameter_defaults": parameter_defaults.duplicate(true),
		"parameter_limits": parameter_limits.duplicate(true),
		"layers": ParametricUtils.sorted_rows(layers, "layer_id"),
		"fabrication": fabrication.duplicate(true),
		"metadata": metadata.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value

static func limit(minimum: float, maximum: float) -> Dictionary:
	return {"minimum": ParametricUtils.metric(minimum), "maximum": ParametricUtils.metric(maximum)}

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return ParametricUtils.failure("UNSUPPORTED_CONSTRUCTION_PARAMETRIC_MEMBER_DEFINITION_SCHEMA")
	if not ParametricUtils.path_id(String(value.get("member_definition_id", "")), "parametric-definition/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MEMBER_DEFINITION_ID")
	if not UtilsScript.is_json_integer(value.get("definition_version")) or int(value["definition_version"]) < 1: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MEMBER_DEFINITION_VERSION")
	if typeof(value.get("display_name")) != TYPE_STRING or String(value["display_name"]).strip_edges().is_empty(): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_MEMBER_DEFINITION_NAME_REQUIRED")
	var kind := String(value.get("member_kind", ""))
	if not KINDS.has(kind): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MEMBER_KIND")
	var parameters := expected_parameters(kind)
	if typeof(value.get("parameter_defaults")) != TYPE_DICTIONARY or typeof(value.get("parameter_limits")) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_PARAMETER_SCHEMA")
	if not _same_keys(value["parameter_defaults"], parameters) or not _same_keys(value["parameter_limits"], parameters): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_PARAMETER_SET_MISMATCH")
	for parameter in parameters:
		if not ParametricUtils.positive_number(value["parameter_defaults"][parameter]): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_PARAMETER_DEFAULT")
		var raw_limit = value["parameter_limits"][parameter]
		if typeof(raw_limit) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_PARAMETER_LIMIT")
		var limit_exact := UtilsScript.validate_exact_fields(raw_limit, LIMIT_FIELDS)
		if not bool(limit_exact.get("success", false)): return limit_exact
		if not ParametricUtils.positive_number(raw_limit.get("minimum")) or not ParametricUtils.positive_number(raw_limit.get("maximum")) or float(raw_limit["minimum"]) > float(raw_limit["maximum"]): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_PARAMETER_LIMIT")
		var default_value := float(value["parameter_defaults"][parameter])
		if default_value < float(raw_limit["minimum"]) or default_value > float(raw_limit["maximum"]): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_PARAMETER_DEFAULT_OUT_OF_RANGE")
	if typeof(value.get("layers")) != TYPE_ARRAY: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_LAYER_COLLECTION")
	var previous := ""; var seen := {}
	for layer in value["layers"]:
		if typeof(layer) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_LAYER")
		var checked := LayerScript.validate(layer); if not bool(checked.get("success", false)): return checked
		var layer_id := String(layer["layer_id"])
		if seen.has(layer_id) or (not previous.is_empty() and layer_id < previous): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_LAYER_ORDER")
		seen[layer_id] = true; previous = layer_id
	if kind == "LAYERED_WALL":
		if not String(value.get("primary_material_id", "")).is_empty(): return ParametricUtils.failure("LAYERED_WALL_PRIMARY_MATERIAL_FORBIDDEN")
		if Array(value["layers"]).is_empty(): return ParametricUtils.failure("LAYERED_WALL_LAYERS_REQUIRED")
	else:
		if not ParametricUtils.path_id(String(value.get("primary_material_id", "")), "material/"): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_PRIMARY_MATERIAL_REQUIRED")
		if not Array(value["layers"]).is_empty(): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_LAYERS_FORBIDDEN_FOR_MEMBER_KIND")
	if kind == "PIPE" and float(value["parameter_defaults"]["wall_thickness_m"]) * 2.0 >= float(value["parameter_defaults"]["outer_diameter_m"]): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_PIPE_WALL_TOO_THICK")
	for field in ["fabrication", "metadata"]:
		if typeof(value.get(field)) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value[field]).get("success", false)): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MEMBER_DEFINITION_METADATA")
	if String(value.get("checksum", "")) != compute_checksum(value): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_MEMBER_DEFINITION_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_MEMBER_DEFINITION_NOT_JSON_SAFE")
	return ParametricUtils.success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)

static func _same_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.size() != expected.size(): return false
	for key in expected:
		if not value.has(key): return false
	for raw_key in value.keys():
		if typeof(raw_key) != TYPE_STRING: return false
	return true
