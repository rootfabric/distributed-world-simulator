extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")

const SCHEMA: String = "planet_simulator.matter_material_definition.v1"
const PHASES: Array[String] = ["SOLID", "LIQUID", "GAS", "PLASMA"]
const FIELDS: Array[String] = [
	"schema",
	"material_id",
	"display_name",
	"family",
	"phase",
	"density_kg_m3",
	"hardness_pa",
	"compressive_strength_pa",
	"tensile_strength_pa",
	"fracture_toughness_pa_m_sqrt",
	"cohesion_pa",
	"abrasiveness_ratio",
	"porosity_ratio",
	"permeability_m2",
	"heat_capacity_j_kg_k",
	"thermal_conductivity_w_m_k",
	"melting_temperature_k",
	"vaporization_temperature_k",
	"mining_energy_j_kg",
	"tags",
	"checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"material_id": String(data.get("material_id", "")).strip_edges().to_lower(),
		"display_name": String(data.get("display_name", "")).strip_edges(),
		"family": String(data.get("family", "")).strip_edges().to_lower(),
		"phase": String(data.get("phase", "SOLID")).strip_edges().to_upper(),
		"density_kg_m3": float(data.get("density_kg_m3", 0.0)),
		"hardness_pa": float(data.get("hardness_pa", 0.0)),
		"compressive_strength_pa": float(data.get("compressive_strength_pa", 0.0)),
		"tensile_strength_pa": float(data.get("tensile_strength_pa", 0.0)),
		"fracture_toughness_pa_m_sqrt": float(data.get("fracture_toughness_pa_m_sqrt", 0.0)),
		"cohesion_pa": float(data.get("cohesion_pa", 0.0)),
		"abrasiveness_ratio": float(data.get("abrasiveness_ratio", 0.0)),
		"porosity_ratio": float(data.get("porosity_ratio", 0.0)),
		"permeability_m2": float(data.get("permeability_m2", 0.0)),
		"heat_capacity_j_kg_k": float(data.get("heat_capacity_j_kg_k", 0.0)),
		"thermal_conductivity_w_m_k": float(data.get("thermal_conductivity_w_m_k", 0.0)),
		"melting_temperature_k": float(data.get("melting_temperature_k", 0.0)),
		"vaporization_temperature_k": float(data.get("vaporization_temperature_k", 0.0)),
		"mining_energy_j_kg": float(data.get("mining_energy_j_kg", 0.0)),
		"tags": MatterUtilsScript.sorted_unique_ids(Array(data.get("tags", []))),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_MATERIAL_SCHEMA")
	if not MatterUtilsScript.is_canonical_id(value.get("material_id"), 2):
		return MatterUtilsScript.failure("INVALID_MATERIAL_ID")
	if typeof(value.get("display_name")) != TYPE_STRING or String(value["display_name"]).strip_edges().is_empty():
		return MatterUtilsScript.failure("INVALID_MATERIAL_DISPLAY_NAME")
	if not MatterUtilsScript.is_canonical_id(value.get("family"), 2):
		return MatterUtilsScript.failure("INVALID_MATERIAL_FAMILY")
	if typeof(value.get("phase")) != TYPE_STRING or not String(value["phase"]) in PHASES:
		return MatterUtilsScript.failure("INVALID_MATERIAL_PHASE")
	if not MatterUtilsScript.is_positive_number(value.get("density_kg_m3")):
		return MatterUtilsScript.failure("INVALID_MATERIAL_DENSITY")
	for field in [
		"hardness_pa",
		"compressive_strength_pa",
		"tensile_strength_pa",
		"fracture_toughness_pa_m_sqrt",
		"cohesion_pa",
		"permeability_m2",
		"heat_capacity_j_kg_k",
		"thermal_conductivity_w_m_k",
		"melting_temperature_k",
		"vaporization_temperature_k",
		"mining_energy_j_kg",
	]:
		if not MatterUtilsScript.is_non_negative_number(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATERIAL_PROPERTY", {"field": field})
	for field in ["abrasiveness_ratio", "porosity_ratio"]:
		if not MatterUtilsScript.is_ratio(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATERIAL_RATIO", {"field": field})
	if float(value["heat_capacity_j_kg_k"]) <= 0.0:
		return MatterUtilsScript.failure("INVALID_MATERIAL_HEAT_CAPACITY")
	if float(value["melting_temperature_k"]) <= 0.0:
		return MatterUtilsScript.failure("INVALID_MATERIAL_MELTING_TEMPERATURE")
	if float(value["vaporization_temperature_k"]) <= float(value["melting_temperature_k"]):
		return MatterUtilsScript.failure("INVALID_MATERIAL_PHASE_TEMPERATURES")
	var tags: Dictionary = MatterUtilsScript.validate_sorted_unique_ids(value.get("tags"), true)
	if not bool(tags.get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATERIAL_TAGS")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_material")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return MatterUtilsScript.normalize(value, validate)
