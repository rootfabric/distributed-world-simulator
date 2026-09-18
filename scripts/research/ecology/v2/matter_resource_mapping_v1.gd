extends RefCounted
## A10 R2: explicit Matter material -> ECO resource admission.
## This layer performs accounting only. It does not mutate Matter or ECO fields.
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Catalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Batch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")

const SCHEMA := "dws.ecology.a10-matter-resource-map.v1"
const ADMISSION_SCHEMA := "dws.ecology.a10-matter-resource-admission.v1"
const FIELDS := ["schema", "map_id", "catalog_hash", "entries", "checksum"]
const ENTRY_FIELDS := ["material_id", "resource"]
const KG_TO_MG := 1000000.0
const MASS_TOLERANCE_MG := 0.000001

static func create(catalog: Dictionary, map_id: String, entries: Array = []) -> Dictionary:
	if not bool(Catalog.validate(catalog).get("success", false)):
		return {}
	var normalized: Array = []
	for raw in entries:
		if not raw is Dictionary:
			continue
		normalized.append({
			"material_id": String(raw.get("material_id", "")).strip_edges().to_lower(),
			"resource": String(raw.get("resource", "")).strip_edges(),
		})
	normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["material_id"]) < String(b["material_id"])
	)
	var value := {
		"schema": SCHEMA,
		"map_id": map_id.strip_edges().to_lower(),
		"catalog_hash": String(catalog["catalog_hash"]),
		"entries": normalized,
		"checksum": "",
	}
	value["checksum"] = _checksum(value)
	return value if validate(value, catalog).is_empty() else {}

static func validate(value: Dictionary, catalog: Dictionary) -> String:
	if not bool(Catalog.validate(catalog).get("success", false)):
		return "A10_R2_CATALOG_INVALID"
	var exact: Dictionary = MatterUtils.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return "A10_R2_MAP_FIELDS"
	if value.get("schema") != SCHEMA:
		return "A10_R2_MAP_SCHEMA"
	if not MatterUtils.is_canonical_id(value.get("map_id"), 2):
		return "A10_R2_MAP_ID"
	if String(value.get("catalog_hash", "")) != String(catalog["catalog_hash"]):
		return "A10_R2_CATALOG_HASH"
	if not value.get("entries") is Array or value["entries"].size() > 128:
		return "A10_R2_MAP_ENTRIES"
	var known_materials := {}
	for material in catalog["materials"]:
		known_materials[String(material["material_id"])] = true
	var seen_materials := {}
	var prior := ""
	for raw in value["entries"]:
		if not raw is Dictionary:
			return "A10_R2_MAP_ENTRY"
		var fields: Dictionary = MatterUtils.validate_exact_fields(raw, ENTRY_FIELDS)
		if not bool(fields.get("success", false)):
			return "A10_R2_MAP_ENTRY_FIELDS"
		var material_id := String(raw.get("material_id", ""))
		var resource := String(raw.get("resource", ""))
		if not known_materials.has(material_id):
			return "A10_R2_UNKNOWN_MATERIAL"
		if not resource in F.RESOURCES:
			return "A10_R2_UNKNOWN_RESOURCE"
		if seen_materials.has(material_id):
			return "A10_R2_DUPLICATE_MATERIAL"
		if not prior.is_empty() and material_id <= prior:
			return "A10_R2_MAP_NOT_SORTED"
		seen_materials[material_id] = true
		prior = material_id
	if String(value.get("checksum", "")) != _checksum(value):
		return "A10_R2_MAP_CHECKSUM"
	return ""

static func admit_material_batch(batch: Dictionary, catalog: Dictionary, mapping: Dictionary) -> Dictionary:
	var map_error := validate(mapping, catalog)
	if not map_error.is_empty():
		return _fail(map_error)
	if not bool(Batch.validate(batch).get("success", false)):
		return _fail("A10_R2_BATCH_INVALID")
	var total := _exact_mg(float(batch["total_mass_kg"]))
	if not bool(total.get("success", false)):
		return _fail("A10_R2_TOTAL_MASS_NOT_EXACT_MG")
	var total_mg: int = int(total["mg"])
	var known_materials := {}
	for material in catalog["materials"]:
		known_materials[String(material["material_id"])] = true
	var resource_by_material := {}
	for entry in mapping["entries"]:
		resource_by_material[String(entry["material_id"])] = String(entry["resource"])
	var resources := F.stock()
	var unmapped: Array = []
	var accounted := 0
	for component in batch["composition"]["components"]:
		var material_id := String(component["material_id"])
		if not known_materials.has(material_id):
			return _fail("A10_R2_BATCH_MATERIAL_NOT_IN_CATALOG")
		var component_mg_float := float(total_mg) * float(component["mass_fraction"])
		var nearest := roundi(component_mg_float)
		if absf(component_mg_float - float(nearest)) > MASS_TOLERANCE_MG:
			return _fail("A10_R2_COMPONENT_MASS_NOT_EXACT_MG")
		if nearest <= 0:
			return _fail("A10_R2_COMPONENT_MASS_ZERO")
		accounted += nearest
		if resource_by_material.has(material_id):
			var resource := String(resource_by_material[material_id])
			if resources[resource] > F.MAX_CELL_STOCK - nearest:
				return _fail("A10_R2_RESOURCE_OVERFLOW")
			resources[resource] += nearest
		else:
			unmapped.append({"material_id": material_id, "mass_mg": nearest})
	if accounted != total_mg:
		return _fail("A10_R2_COMPONENT_TOTAL_MISMATCH")
	unmapped.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["material_id"]) < String(b["material_id"])
	)
	var mapped_mg := 0
	for resource in F.RESOURCES:
		mapped_mg += int(resources[resource])
	var unmapped_mg := 0
	for item in unmapped:
		unmapped_mg += int(item["mass_mg"])
	if mapped_mg + unmapped_mg != total_mg:
		return _fail("A10_R2_MASS_CONSERVATION")
	var result := {
		"schema": ADMISSION_SCHEMA,
		"scope": "CANONICAL_BATCH_ADMISSION_NOT_ENVIRONMENT_EXTRACTION",
		"batch_id": String(batch["batch_id"]),
		"batch_checksum": String(batch["checksum"]),
		"map_id": String(mapping["map_id"]),
		"map_checksum": String(mapping["checksum"]),
		"catalog_hash": String(catalog["catalog_hash"]),
		"total_mass_mg": total_mg,
		"resources": resources,
		"unmapped_materials": unmapped,
		"mapped_mass_mg": mapped_mg,
		"unmapped_mass_mg": unmapped_mg,
		"accounting_hash": "",
	}
	result["accounting_hash"] = _hash_without(result, "accounting_hash")
	if String(result["accounting_hash"]).is_empty():
		return _fail("A10_R2_ACCOUNTING_HASH")
	return {"success": true, "admission": result}

static func _exact_mg(mass_kg: float) -> Dictionary:
	if not is_finite(mass_kg) or mass_kg <= 0.0:
		return {"success": false}
	var scaled := mass_kg * KG_TO_MG
	if not is_finite(scaled) or scaled > float(F.MAX_CELL_STOCK):
		return {"success": false}
	var nearest := roundi(scaled)
	if nearest <= 0 or absf(scaled - float(nearest)) > MASS_TOLERANCE_MG:
		return {"success": false}
	return {"success": true, "mg": nearest}

static func _checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload["checksum"] = ""
	return MatterUtils.payload_hash(payload)

static func _hash_without(value: Dictionary, field: String) -> String:
	var payload := value.duplicate(true)
	payload[field] = ""
	return MatterUtils.payload_hash(payload)

static func _fail(error: String) -> Dictionary:
	return {"success": false, "error": error}
