extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")

const SCHEMA: String = "planet_simulator.matter_composition.v1"
const FIELDS: Array[String] = ["schema", "components", "checksum"]
const COMPONENT_FIELDS: Array[String] = ["material_id", "mass_fraction"]
const FRACTION_TOLERANCE: float = 0.000000001


static func create(components: Array = []) -> Dictionary:
	var normalized_components: Array = []
	for component in components:
		if typeof(component) != TYPE_DICTIONARY:
			continue
		normalized_components.append({
			"material_id": String(component.get("material_id", "")).strip_edges().to_lower(),
			"mass_fraction": float(component.get("mass_fraction", 0.0)),
		})
	normalized_components.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("material_id", "")) < String(b.get("material_id", ""))
	)
	var value: Dictionary = {
		"schema": SCHEMA,
		"components": normalized_components,
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func from_weights(weights: Dictionary) -> Dictionary:
	var material_ids: Array = weights.keys()
	material_ids.sort()
	var total: float = 0.0
	for material_id in material_ids:
		var weight = weights.get(material_id)
		if not MatterUtilsScript.is_positive_number(weight):
			return {}
		total += float(weight)
	if total <= 0.0 or not is_finite(total):
		return {}
	var components: Array = []
	for material_id in material_ids:
		components.append({
			"material_id": String(material_id),
			"mass_fraction": float(weights[material_id]) / total,
		})
	return create(components)


static func empty() -> Dictionary:
	return create([])


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_COMPOSITION_SCHEMA")
	if typeof(value.get("components")) != TYPE_ARRAY:
		return MatterUtilsScript.failure("INVALID_MATTER_COMPONENTS")
	var previous_id: String = ""
	var total_fraction: float = 0.0
	for index in range(value["components"].size()):
		var component = value["components"][index]
		if typeof(component) != TYPE_DICTIONARY:
			return MatterUtilsScript.failure("INVALID_MATTER_COMPONENT", {"index": index})
		var component_exact: Dictionary = MatterUtilsScript.validate_exact_fields(component, COMPONENT_FIELDS)
		if not bool(component_exact.get("success", false)):
			return MatterUtilsScript.failure("INVALID_MATTER_COMPONENT_FIELDS", {"index": index})
		var material_id: String = String(component.get("material_id", ""))
		if not MatterUtilsScript.is_canonical_id(material_id, 2):
			return MatterUtilsScript.failure("INVALID_MATTER_COMPONENT_ID", {"index": index})
		if index > 0 and material_id <= previous_id:
			return MatterUtilsScript.failure("MATTER_COMPONENTS_NOT_SORTED_UNIQUE", {"index": index})
		if not MatterUtilsScript.is_positive_number(component.get("mass_fraction")):
			return MatterUtilsScript.failure("INVALID_MATTER_COMPONENT_FRACTION", {"index": index})
		if float(component["mass_fraction"]) > 1.0:
			return MatterUtilsScript.failure("INVALID_MATTER_COMPONENT_FRACTION", {"index": index})
		total_fraction += float(component["mass_fraction"])
		previous_id = material_id
	if not value["components"].is_empty() \
		and not MatterUtilsScript.approximately_equal(total_fraction, 1.0, FRACTION_TOLERANCE):
		return MatterUtilsScript.failure("MATTER_FRACTIONS_NOT_NORMALIZED", {"sum": total_fraction})
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_composition")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return MatterUtilsScript.normalize(value, validate)


static func is_empty(value: Dictionary) -> bool:
	return bool(validate(value).get("success", false)) and Array(value["components"]).is_empty()


static func fraction_for(value: Dictionary, material_id: String) -> float:
	if not bool(validate(value).get("success", false)):
		return 0.0
	for component in value["components"]:
		if String(component["material_id"]) == material_id:
			return float(component["mass_fraction"])
	return 0.0
