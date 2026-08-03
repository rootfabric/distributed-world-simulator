extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")

const SCHEMA := "planet_simulator.construction_parametric_material.v1"
const FIELDS: Array[String] = ["schema", "material_id", "display_name", "density_kg_m3", "stock_definition_id", "stock_unit_mass_kg", "properties", "checksum"]

static func create(material_id: String, display_name: String, density_kg_m3: float, stock_definition_id: String, stock_unit_mass_kg: float, properties: Dictionary = {}) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"material_id": material_id,
		"display_name": display_name,
		"density_kg_m3": ParametricUtils.metric(density_kg_m3),
		"stock_definition_id": stock_definition_id,
		"stock_unit_mass_kg": ParametricUtils.metric(stock_unit_mass_kg),
		"properties": properties.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return ParametricUtils.failure("UNSUPPORTED_CONSTRUCTION_PARAMETRIC_MATERIAL_SCHEMA")
	if not ParametricUtils.path_id(String(value.get("material_id", "")), "material/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MATERIAL_ID")
	if typeof(value.get("display_name")) != TYPE_STRING or String(value["display_name"]).strip_edges().is_empty(): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_MATERIAL_NAME_REQUIRED")
	if not ParametricUtils.positive_number(value.get("density_kg_m3")): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MATERIAL_DENSITY")
	if not ParametricUtils.token(String(value.get("stock_definition_id", ""))): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_STOCK_DEFINITION")
	if not ParametricUtils.positive_number(value.get("stock_unit_mass_kg")): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_STOCK_UNIT_MASS")
	if typeof(value.get("properties")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["properties"]).get("success", false)): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MATERIAL_PROPERTIES")
	if String(value.get("checksum", "")) != compute_checksum(value): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_MATERIAL_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_MATERIAL_NOT_JSON_SAFE")
	return ParametricUtils.success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
