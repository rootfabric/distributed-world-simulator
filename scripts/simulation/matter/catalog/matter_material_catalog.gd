extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const MaterialScript = preload("res://scripts/simulation/matter/contracts/matter_material_definition.gd")

const SCHEMA: String = "planet_simulator.matter_material_catalog.v1"
const CATALOG_ID: String = "matter-catalog/core-v1"
const CATALOG_VERSION: String = "1.0.0"
const FIELDS: Array[String] = [
	"schema", "catalog_id", "catalog_version", "materials", "catalog_hash", "checksum",
]


static func create(materials: Array, catalog_id: String = CATALOG_ID, catalog_version: String = CATALOG_VERSION) -> Dictionary:
	var normalized_materials: Array = []
	for material in materials:
		if typeof(material) == TYPE_DICTIONARY:
			normalized_materials.append(Dictionary(material).duplicate(true))
	normalized_materials.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("material_id", "")) < String(b.get("material_id", ""))
	)
	var value: Dictionary = {
		"schema": SCHEMA,
		"catalog_id": catalog_id.strip_edges().to_lower(),
		"catalog_version": catalog_version.strip_edges(),
		"materials": normalized_materials,
		"catalog_hash": MatterUtilsScript.payload_hash(normalized_materials),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_CATALOG_SCHEMA")
	if not MatterUtilsScript.is_canonical_id(value.get("catalog_id"), 2):
		return MatterUtilsScript.failure("INVALID_MATTER_CATALOG_ID")
	if not MatterUtilsScript.is_semantic_version(value.get("catalog_version")):
		return MatterUtilsScript.failure("INVALID_MATTER_CATALOG_VERSION")
	if typeof(value.get("materials")) != TYPE_ARRAY or value["materials"].is_empty():
		return MatterUtilsScript.failure("EMPTY_MATTER_CATALOG")
	var previous_id: String = ""
	for index in range(value["materials"].size()):
		var material = value["materials"][index]
		if typeof(material) != TYPE_DICTIONARY or not bool(MaterialScript.validate(material).get("success", false)):
			return MatterUtilsScript.failure("INVALID_MATTER_CATALOG_ENTRY", {"index": index})
		var material_id: String = String(material["material_id"])
		if index > 0 and material_id <= previous_id:
			return MatterUtilsScript.failure("MATTER_CATALOG_NOT_SORTED_UNIQUE", {"index": index})
		previous_id = material_id
	if not MatterUtilsScript.is_lower_hex_64(value.get("catalog_hash")) \
		or String(value["catalog_hash"]) != MatterUtilsScript.payload_hash(value["materials"]):
		return MatterUtilsScript.failure("MATTER_CATALOG_HASH_MISMATCH")
	return MatterUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return MatterUtilsScript.normalize(value, validate)


static func default_catalog() -> Dictionary:
	var materials: Array = []
	for spec in _default_specs():
		materials.append(MaterialScript.create(spec))
	return create(materials)


static func material_by_id(catalog: Dictionary, material_id: String) -> Dictionary:
	if not bool(validate(catalog).get("success", false)):
		return {}
	for material in catalog["materials"]:
		if String(material["material_id"]) == material_id:
			return Dictionary(material).duplicate(true)
	return {}


static func _default_specs() -> Array:
	return [
		_spec("matter/regolith-loose", "Loose regolith", "matter-family/regolith", 1500.0, 1000000.0, 500000.0, 10000.0, 1000.0, 5000.0, 0.15, 0.45, 0.0000000001, 680.0, 0.25, 1400.0, 2800.0, 15000.0, ["matter-tag/geological", "matter-tag/loose"]),
		_spec("matter/regolith-compacted", "Compacted regolith", "matter-family/regolith", 1900.0, 5000000.0, 6000000.0, 200000.0, 10000.0, 250000.0, 0.25, 0.25, 0.00000000001, 720.0, 0.5, 1450.0, 2850.0, 50000.0, ["matter-tag/bonded", "matter-tag/geological"]),
		_spec("matter/basalt", "Basalt", "matter-family/silicate-rock", 2900.0, 7000000000.0, 250000000.0, 20000000.0, 2000000.0, 12000000.0, 0.8, 0.05, 0.000000000000001, 840.0, 1.7, 1450.0, 3000.0, 450000.0, ["matter-tag/bonded", "matter-tag/geological"]),
		_spec("matter/fractured-basalt", "Fractured basalt", "matter-family/silicate-rock", 2400.0, 2500000000.0, 70000000.0, 3000000.0, 400000.0, 1500000.0, 0.65, 0.22, 0.000000000001, 820.0, 1.1, 1450.0, 3000.0, 180000.0, ["matter-tag/fractured", "matter-tag/geological"]),
		_spec("matter/water-ice", "Water ice", "matter-family/volatile-ice", 917.0, 1500000000.0, 25000000.0, 1500000.0, 150000.0, 1000000.0, 0.2, 0.08, 0.0000000000001, 2050.0, 2.2, 273.15, 373.15, 90000.0, ["matter-tag/bonded", "matter-tag/volatile"]),
		_spec("matter/iron-nickel-ore", "Iron-nickel ore", "matter-family/metallic-ore", 5200.0, 4500000000.0, 400000000.0, 80000000.0, 4000000.0, 30000000.0, 0.9, 0.04, 0.000000000000001, 600.0, 12.0, 1750.0, 3200.0, 650000.0, ["matter-tag/bonded", "matter-tag/ore"]),
		_spec("matter/silicate-waste", "Silicate waste", "matter-family/silicate-rock", 2100.0, 800000000.0, 30000000.0, 800000.0, 100000.0, 400000.0, 0.45, 0.32, 0.00000000001, 750.0, 0.7, 1400.0, 2900.0, 90000.0, ["matter-tag/loose", "matter-tag/waste"]),
	]


static func _spec(
	material_id: String,
	display_name: String,
	family: String,
	density_kg_m3: float,
	hardness_pa: float,
	compressive_strength_pa: float,
	tensile_strength_pa: float,
	fracture_toughness_pa_m_sqrt: float,
	cohesion_pa: float,
	abrasiveness_ratio: float,
	porosity_ratio: float,
	permeability_m2: float,
	heat_capacity_j_kg_k: float,
	thermal_conductivity_w_m_k: float,
	melting_temperature_k: float,
	vaporization_temperature_k: float,
	mining_energy_j_kg: float,
	tags: Array
) -> Dictionary:
	return {
		"material_id": material_id,
		"display_name": display_name,
		"family": family,
		"phase": "SOLID",
		"density_kg_m3": density_kg_m3,
		"hardness_pa": hardness_pa,
		"compressive_strength_pa": compressive_strength_pa,
		"tensile_strength_pa": tensile_strength_pa,
		"fracture_toughness_pa_m_sqrt": fracture_toughness_pa_m_sqrt,
		"cohesion_pa": cohesion_pa,
		"abrasiveness_ratio": abrasiveness_ratio,
		"porosity_ratio": porosity_ratio,
		"permeability_m2": permeability_m2,
		"heat_capacity_j_kg_k": heat_capacity_j_kg_k,
		"thermal_conductivity_w_m_k": thermal_conductivity_w_m_k,
		"melting_temperature_k": melting_temperature_k,
		"vaporization_temperature_k": vaporization_temperature_k,
		"mining_energy_j_kg": mining_energy_j_kg,
		"tags": tags,
	}
