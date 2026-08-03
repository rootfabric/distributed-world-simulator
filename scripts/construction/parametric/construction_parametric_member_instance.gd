extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const DefinitionScript = preload("res://scripts/construction/parametric/construction_parametric_member_definition.gd")

const SCHEMA := "planet_simulator.construction_parametric_member_instance.v1"
const FIELDS: Array[String] = ["schema", "member_instance_id", "member_definition_id", "definition_version", "definition_checksum", "member_kind", "parameter_values", "material_usage", "geometry", "mass_kg", "item_instance_id", "provenance", "checksum"]
const USAGE_FIELDS: Array[String] = ["material_id", "stock_definition_id", "volume_m3", "mass_kg", "stock_units"]
const GEOMETRY_FIELDS: Array[String] = ["length_m", "width_m", "height_m", "outer_diameter_m", "wall_thickness_m", "diameter_m", "total_thickness_m", "cross_section_area_m2", "surface_area_m2", "volume_m3", "bounding_box_m"]

static func create(member_instance_id: String, definition: Dictionary, parameter_values: Dictionary, material_usage: Array, geometry: Dictionary, mass_kg: float, item_instance_id: String, provenance: Dictionary = {}) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"member_instance_id": member_instance_id,
		"member_definition_id": String(definition.get("member_definition_id", "")),
		"definition_version": int(definition.get("definition_version", 0)),
		"definition_checksum": String(definition.get("checksum", "")),
		"member_kind": String(definition.get("member_kind", "")),
		"parameter_values": parameter_values.duplicate(true),
		"material_usage": ParametricUtils.sorted_rows(material_usage, "material_id"),
		"geometry": geometry.duplicate(true),
		"mass_kg": ParametricUtils.metric(mass_kg),
		"item_instance_id": item_instance_id,
		"provenance": provenance.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return ParametricUtils.failure("UNSUPPORTED_CONSTRUCTION_PARAMETRIC_MEMBER_INSTANCE_SCHEMA")
	if not ParametricUtils.path_id(String(value.get("member_instance_id", "")), "parametric-member/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MEMBER_INSTANCE_ID")
	if not ParametricUtils.path_id(String(value.get("member_definition_id", "")), "parametric-definition/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MEMBER_INSTANCE_DEFINITION")
	if not UtilsScript.is_json_integer(value.get("definition_version")) or int(value["definition_version"]) < 1: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MEMBER_INSTANCE_VERSION")
	if typeof(value.get("definition_checksum")) != TYPE_STRING or String(value["definition_checksum"]).length() != 64: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MEMBER_INSTANCE_DEFINITION_CHECKSUM")
	var kind := String(value.get("member_kind", ""))
	if not DefinitionScript.KINDS.has(kind): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MEMBER_KIND")
	if typeof(value.get("parameter_values")) != TYPE_DICTIONARY or not _same_parameter_keys(value["parameter_values"], DefinitionScript.expected_parameters(kind)): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_INSTANCE_PARAMETER_SET_MISMATCH")
	for parameter in value["parameter_values"].values():
		if not ParametricUtils.positive_number(parameter): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_INSTANCE_PARAMETER")
	if typeof(value.get("material_usage")) != TYPE_ARRAY or Array(value["material_usage"]).is_empty(): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_MATERIAL_USAGE_REQUIRED")
	var total_mass := 0.0; var total_volume := 0.0; var previous := ""; var seen := {}
	for raw in value["material_usage"]:
		if typeof(raw) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MATERIAL_USAGE")
		var usage_exact := UtilsScript.validate_exact_fields(raw, USAGE_FIELDS); if not bool(usage_exact.get("success", false)): return usage_exact
		var material_id := String(raw.get("material_id", ""))
		if not ParametricUtils.path_id(material_id, "material/") or seen.has(material_id) or (not previous.is_empty() and material_id < previous): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MATERIAL_USAGE_ORDER")
		if not ParametricUtils.token(String(raw.get("stock_definition_id", ""))): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MATERIAL_USAGE_STOCK")
		if not ParametricUtils.positive_number(raw.get("volume_m3")) or not ParametricUtils.positive_number(raw.get("mass_kg")): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MATERIAL_USAGE_METRIC")
		if not UtilsScript.is_json_integer(raw.get("stock_units")) or int(raw["stock_units"]) < 1: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MATERIAL_USAGE_UNITS")
		total_mass += float(raw["mass_kg"]); total_volume += float(raw["volume_m3"]); seen[material_id] = true; previous = material_id
	if typeof(value.get("geometry")) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_GEOMETRY")
	var geometry_exact := UtilsScript.validate_exact_fields(value["geometry"], GEOMETRY_FIELDS); if not bool(geometry_exact.get("success", false)): return geometry_exact
	for field in GEOMETRY_FIELDS:
		if field == "bounding_box_m": continue
		if not ParametricUtils.non_negative_number(value["geometry"][field]): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_GEOMETRY_METRIC")
	if not ParametricUtils.positive_number(value["geometry"]["length_m"]) or not ParametricUtils.positive_number(value["geometry"]["volume_m3"]) or not ParametricUtils.positive_number(value["geometry"]["surface_area_m2"]): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_GEOMETRY_METRIC")
	if typeof(value["geometry"].get("bounding_box_m")) != TYPE_ARRAY or Array(value["geometry"]["bounding_box_m"]).size() != 3: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_BOUNDING_BOX")
	for component in value["geometry"]["bounding_box_m"]:
		if not ParametricUtils.positive_number(component): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_BOUNDING_BOX")
	if not ParametricUtils.positive_number(value.get("mass_kg")): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MEMBER_MASS")
	if not ParametricUtils.nearly_equal(total_mass, float(value["mass_kg"])): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_MASS_NOT_CONSERVED")
	if not ParametricUtils.nearly_equal(total_volume, float(value["geometry"]["volume_m3"])): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_VOLUME_NOT_CONSERVED")
	if not ParametricUtils.path_id(String(value.get("item_instance_id", "")), "item/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MEMBER_ITEM_ID")
	if typeof(value.get("provenance")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["provenance"]).get("success", false)): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_PROVENANCE")
	if String(value.get("checksum", "")) != compute_checksum(value): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_MEMBER_INSTANCE_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_MEMBER_INSTANCE_NOT_JSON_SAFE")
	return ParametricUtils.success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)

static func with_updates(value: Dictionary, updates: Dictionary) -> Dictionary:
	var next := value.duplicate(true)
	for key in updates: next[key] = updates[key]
	next["checksum"] = compute_checksum(next)
	return next

static func _same_parameter_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.size() != expected.size(): return false
	for key in expected:
		if not value.has(key): return false
	return true
