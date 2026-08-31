extends RefCounted

const BatchScript = preload(
	"res://scripts/simulation/matter/contracts/matter_material_batch.gd"
)

# P7.3 intentionally defines a product conversion policy rather than changing
# Matter or Item Graph semantics. One canonical item/ore quantity represents
# one kilogram of successfully extracted, supported lunar geological matter.
# Fractional mass is retained as explicit immutable batch residual provenance;
# it is never rounded up, silently dropped, or stored in a P7-private balance.
const POLICY_ID := "p7/matter-material-delivery/r1"
const OUTPUT_DEFINITION_ID := "item/ore"
const KG_PER_ITEM_UNIT: float = 1.0
const MASS_TOLERANCE_KG: float = 0.000000001
const QUANTIZATION_EPSILON_KG: float = 0.000000000001
const SUPPORTED_MATERIAL_IDS := {
	"matter/regolith-loose": true,
	"matter/regolith-compacted": true,
	"matter/fractured-basalt": true,
	"matter/basalt": true,
}


static func plan(batch: Dictionary) -> Dictionary:
	var validation: Dictionary = BatchScript.validate(batch)
	if not bool(validation.get("success", false)):
		return _failure("P7_INVALID_MATTER_MATERIAL_BATCH")
	var components: Array = Dictionary(batch["composition"]).get("components", [])
	var mapped_components: Array = []
	for component_value in components:
		var component: Dictionary = component_value
		var material_id := String(component.get("material_id", ""))
		if not SUPPORTED_MATERIAL_IDS.has(material_id):
			return _failure("P7_UNSUPPORTED_MATTER_MATERIAL", {
				"material_id": material_id,
				"policy_id": POLICY_ID,
			})
		mapped_components.append({
			"material_id": material_id,
			"mass_fraction": float(component.get("mass_fraction", 0.0)),
			"output_definition_id": OUTPUT_DEFINITION_ID,
		})

	var total_mass_kg := float(batch["total_mass_kg"])
	# Tiny tolerance only stabilizes values that are already an integer kilogram
	# within the Matter contract tolerance. It must never turn a material
	# fractional remainder into a gameplay unit.
	var quantity := int(floor(total_mass_kg / KG_PER_ITEM_UNIT + QUANTIZATION_EPSILON_KG))
	var represented_mass_kg := float(quantity) * KG_PER_ITEM_UNIT
	if represented_mass_kg > total_mass_kg + MASS_TOLERANCE_KG:
		return _failure("P7_MATERIAL_QUANTIZATION_OVERREPRESENTS_MASS")
	var residual_mass_kg := maxf(0.0, total_mass_kg - represented_mass_kg)
	var conservation_error_kg := absf(
		total_mass_kg - represented_mass_kg - residual_mass_kg
	)
	if conservation_error_kg > MASS_TOLERANCE_KG:
		return _failure("P7_MATERIAL_MASS_CONSERVATION_FAILED", {
			"conservation_error_kg": conservation_error_kg,
		})
	var batch_id := String(batch["batch_id"])
	var batch_checksum := String(batch["checksum"])
	var operation_id := "operation/p7-3/item-output/%s" % batch_id.sha256_text().left(32)
	# Bind the existing Item Graph replay fingerprint to immutable batch content,
	# not only batch_id. If a corrupted/reconstructed batch reuses the same id
	# with different physical contents, the canonical Item Graph ledger must fail
	# closed with OPERATION_REPLAY_CONFLICT instead of treating it as a replay.
	var source_id := "%s/%s" % [batch_id, batch_checksum.left(16)]
	return _success({
		"policy_id": POLICY_ID,
		"batch_id": batch_id,
		"source_operation_id": String(batch["source_operation_id"]),
		"batch_checksum": batch_checksum,
		"output_operation_id": operation_id,
		"output_definition_id": OUTPUT_DEFINITION_ID,
		"output_quantity": quantity,
		"source_id": source_id,
		"kg_per_item_unit": KG_PER_ITEM_UNIT,
		"total_mass_kg": total_mass_kg,
		"represented_mass_kg": represented_mass_kg,
		"residual_mass_kg": residual_mass_kg,
		"conservation_error_kg": conservation_error_kg,
		"mapped_components": mapped_components,
		"delivery_status": "DELIVERABLE" if quantity > 0 else "RESIDUAL_ONLY",
	})


static func contract_report() -> Dictionary:
	var material_ids: Array = SUPPORTED_MATERIAL_IDS.keys()
	material_ids.sort()
	return {
		"policy_id": POLICY_ID,
		"output_definition_id": OUTPUT_DEFINITION_ID,
		"kg_per_item_unit": KG_PER_ITEM_UNIT,
		"supported_material_ids": material_ids,
		"rounding": "FLOOR_WITH_EXPLICIT_RESIDUAL",
		"residual_owner": "IMMUTABLE_MATTER_MATERIAL_BATCH_PROVENANCE",
		"exactly_once_owner": "CANONICAL_ITEM_GRAPH_REPLAY_LEDGER",
		"new_canonical_state_owned": false,
		"delivery_receipt_store": false,
	}


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
