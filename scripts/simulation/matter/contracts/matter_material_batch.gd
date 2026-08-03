extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CompositionScript = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")

const SCHEMA: String = "planet_simulator.matter_material_batch.v1"
const FIELDS: Array[String] = [
	"schema",
	"batch_id",
	"container_id",
	"source_body_id",
	"source_operation_id",
	"total_mass_kg",
	"bulk_volume_m3",
	"composition",
	"temperature_k",
	"checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"batch_id": String(data.get("batch_id", "")).strip_edges().to_lower(),
		"container_id": String(data.get("container_id", "")).strip_edges().to_lower(),
		"source_body_id": String(data.get("source_body_id", "")).strip_edges().to_lower(),
		"source_operation_id": String(data.get("source_operation_id", "")).strip_edges().to_lower(),
		"total_mass_kg": float(data.get("total_mass_kg", 0.0)),
		"bulk_volume_m3": float(data.get("bulk_volume_m3", 0.0)),
		"composition": Dictionary(data.get("composition", CompositionScript.empty())).duplicate(true),
		"temperature_k": float(data.get("temperature_k", 0.0)),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_MATERIAL_BATCH_SCHEMA")
	for field in ["batch_id", "container_id", "source_body_id", "source_operation_id"]:
		if not MatterUtilsScript.is_canonical_id(value.get(field), 2):
			return MatterUtilsScript.failure("INVALID_MATTER_MATERIAL_BATCH_ID", {"field": field})
	for field in ["total_mass_kg", "bulk_volume_m3"]:
		if not MatterUtilsScript.is_positive_number(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_MATERIAL_BATCH_QUANTITY", {"field": field})
	if not MatterUtilsScript.is_non_negative_number(value.get("temperature_k")):
		return MatterUtilsScript.failure("INVALID_MATTER_MATERIAL_BATCH_TEMPERATURE")
	if typeof(value.get("composition")) != TYPE_DICTIONARY \
		or not bool(CompositionScript.validate(value["composition"]).get("success", false)) \
		or CompositionScript.is_empty(value["composition"]):
		return MatterUtilsScript.failure("INVALID_MATTER_MATERIAL_BATCH_COMPOSITION")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_material_batch")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return MatterUtilsScript.normalize(value, validate)
