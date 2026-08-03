extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")

const SCHEMA := "planet_simulator.construction_parametric_layer.v1"
const FIELDS: Array[String] = ["schema", "layer_id", "material_id", "thickness_m", "role", "properties", "checksum"]

static func create(layer_id: String, material_id: String, thickness_m: float, role: String, properties: Dictionary = {}) -> Dictionary:
	var value := {"schema": SCHEMA, "layer_id": layer_id, "material_id": material_id, "thickness_m": ParametricUtils.metric(thickness_m), "role": role, "properties": properties.duplicate(true), "checksum": ""}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return ParametricUtils.failure("UNSUPPORTED_CONSTRUCTION_PARAMETRIC_LAYER_SCHEMA")
	if not ParametricUtils.path_id(String(value.get("layer_id", "")), "layer/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_LAYER_ID")
	if not ParametricUtils.path_id(String(value.get("material_id", "")), "material/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_LAYER_MATERIAL")
	if not ParametricUtils.positive_number(value.get("thickness_m")): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_LAYER_THICKNESS")
	if not ParametricUtils.token(String(value.get("role", ""))): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_LAYER_ROLE")
	if typeof(value.get("properties")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["properties"]).get("success", false)): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_LAYER_PROPERTIES")
	if String(value.get("checksum", "")) != compute_checksum(value): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_LAYER_CHECKSUM_MISMATCH")
	return ParametricUtils.success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
