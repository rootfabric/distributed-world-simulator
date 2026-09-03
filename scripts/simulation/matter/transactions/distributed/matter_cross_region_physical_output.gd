extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Plan = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_plan.gd")
const Receipt = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_receipt.gd")
const MassLedger = preload("res://scripts/simulation/matter/transactions/distributed/matter_distributed_mass_ledger.gd")
const MatterResult = preload("res://scripts/simulation/matter/contracts/matter_mutation_result.gd")
const MaterialBatch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")

const SCHEMA := "planet_simulator.matter_cross_region_physical_output.v1"
const OUTPUT_KIND_EXTRACTED_MATERIAL := "EXTRACTED_MATERIAL"
const FIELDS: Array[String] = [
	"schema", "output_kind", "plan", "participant_outputs",
	"total_mass_kg", "total_bulk_volume_m3", "checksum",
]
const PARTICIPANT_FIELDS: Array[String] = [
	"region_id", "participant_checksum", "commit_receipt",
	"matter_result", "material_batch", "checksum",
]
const MASS_TOLERANCE_KG := 0.001
const VOLUME_TOLERANCE_M3 := 0.000000001


static func create(plan: Dictionary, participant_outputs: Array) -> Dictionary:
	if not bool(Plan.validate(plan).get("success", false)):
		return {}
	var outputs: Array = []
	for raw_output in participant_outputs:
		if typeof(raw_output) != TYPE_DICTIONARY:
			return {}
		var output: Dictionary = _normalize_participant_output(raw_output)
		if output.is_empty():
			return {}
		outputs.append(output)
	outputs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("region_id", "")) < String(b.get("region_id", ""))
	)
	var total_mass_kg := 0.0
	var total_bulk_volume_m3 := 0.0
	for raw_output in outputs:
		var output: Dictionary = raw_output
		var batch: Dictionary = output["material_batch"]
		total_mass_kg += float(batch.get("total_mass_kg", 0.0))
		total_bulk_volume_m3 += float(batch.get("bulk_volume_m3", 0.0))
	var value: Dictionary = {
		"schema": SCHEMA,
		"output_kind": OUTPUT_KIND_EXTRACTED_MATERIAL,
		"plan": plan.duplicate(true),
		"participant_outputs": outputs,
		"total_mass_kg": total_mass_kg,
		"total_bulk_volume_m3": total_bulk_volume_m3,
		"checksum": "",
	}
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = MatterUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if String(value.get("schema", "")) != SCHEMA:
		return MatterUtils.failure("UNSUPPORTED_MATTER_CROSS_REGION_PHYSICAL_OUTPUT_SCHEMA")
	if String(value.get("output_kind", "")) != OUTPUT_KIND_EXTRACTED_MATERIAL:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_PHYSICAL_OUTPUT_KIND")
	if typeof(value.get("plan")) != TYPE_DICTIONARY:
		return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_OUTPUT_PLAN_REQUIRED")
	var plan: Dictionary = value["plan"]
	checked = Plan.validate(plan)
	if not bool(checked.get("success", false)):
		return checked
	var ledger: Dictionary = plan["mass_ledger"]
	checked = MassLedger.validate(ledger)
	if not bool(checked.get("success", false)):
		return checked
	if not Array(ledger.get("external_inputs", [])).is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_EXTRACTION_HAS_EXTERNAL_INPUTS")

	if typeof(value.get("participant_outputs")) != TYPE_ARRAY:
		return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_PARTICIPANT_OUTPUTS_REQUIRED")
	var outputs: Array = value["participant_outputs"]
	var plan_regions: Array[String] = Plan.participant_region_ids(plan)
	if outputs.size() != plan_regions.size() or outputs.size() < 2:
		return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_PARTICIPANT_CARDINALITY_MISMATCH")

	var output_regions: Array[String] = []
	var aggregate_material_mass: Dictionary = {}
	var total_mass_kg := 0.0
	var total_bulk_volume_m3 := 0.0
	var previous_region_id := ""

	for index in range(outputs.size()):
		var raw_output = outputs[index]
		if typeof(raw_output) != TYPE_DICTIONARY:
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_PHYSICAL_PARTICIPANT_OUTPUT", {"index": index})
		var output: Dictionary = raw_output
		checked = MatterUtils.validate_exact_fields(output, PARTICIPANT_FIELDS)
		if not bool(checked.get("success", false)):
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_PHYSICAL_PARTICIPANT_FIELDS", {"index": index})
		var region_id := String(output.get("region_id", ""))
		if not MatterUtils.is_canonical_id(region_id, 2):
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_PHYSICAL_REGION_ID", {"index": index})
		if index > 0 and region_id <= previous_region_id:
			return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_OUTPUTS_NOT_SORTED_UNIQUE")
		previous_region_id = region_id
		output_regions.append(region_id)

		var participant: Dictionary = Plan.participant_by_region(plan, region_id)
		if participant.is_empty():
			return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_PARTICIPANT_NOT_IN_PLAN", {"region_id": region_id})
		if String(output.get("participant_checksum", "")) != String(participant.get("checksum", "")):
			return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_PARTICIPANT_CHECKSUM_MISMATCH", {"region_id": region_id})

		var commit_receipt_value = output.get("commit_receipt", null)
		if typeof(commit_receipt_value) != TYPE_DICTIONARY:
			return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_COMMIT_RECEIPT_REQUIRED", {"region_id": region_id})
		var commit_receipt: Dictionary = commit_receipt_value
		checked = Receipt.validate(commit_receipt)
		if not bool(checked.get("success", false)):
			return checked
		if String(commit_receipt.get("action", "")) != Receipt.ACTION_COMMIT 				or String(commit_receipt.get("transaction_id", "")) != String(plan.get("transaction_id", "")) 				or String(commit_receipt.get("region_id", "")) != region_id 				or String(commit_receipt.get("participant_checksum", "")) != String(participant.get("checksum", "")):
			return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_COMMIT_RECEIPT_BINDING_MISMATCH", {"region_id": region_id})

		var result_value = output.get("matter_result", null)
		if typeof(result_value) != TYPE_DICTIONARY:
			return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_MATTER_RESULT_REQUIRED", {"region_id": region_id})
		var matter_result: Dictionary = result_value
		checked = MatterResult.validate(matter_result)
		if not bool(checked.get("success", false)):
			return checked
		if String(matter_result.get("status", "")) != "COMMITTED" 				or String(matter_result.get("operation_id", "")) != String(plan.get("operation_id", "")):
			return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_MATTER_RESULT_BINDING_MISMATCH", {"region_id": region_id})

		var batch_value = output.get("material_batch", null)
		if typeof(batch_value) != TYPE_DICTIONARY:
			return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_MATERIAL_BATCH_REQUIRED", {"region_id": region_id})
		var batch: Dictionary = batch_value
		checked = MaterialBatch.validate(batch)
		if not bool(checked.get("success", false)):
			return checked
		if String(batch.get("source_operation_id", "")) != String(plan.get("operation_id", "")) 				or String(batch.get("source_body_id", "")) != String(plan.get("body_id", "")):
			return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_BATCH_BINDING_MISMATCH", {"region_id": region_id})
		var aggregate_ids: Array = matter_result.get("created_aggregate_ids", [])
		if aggregate_ids.size() != 1 or String(aggregate_ids[0]) != String(batch.get("batch_id", "")):
			return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_BATCH_RESULT_ID_MISMATCH", {"region_id": region_id})
		if absf(float(batch.get("total_mass_kg", 0.0)) - float(matter_result.get("removed_mass_kg", 0.0))) > MASS_TOLERANCE_KG:
			return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_BATCH_RESULT_MASS_MISMATCH", {"region_id": region_id})
		if Dictionary(batch.get("composition", {})) != Dictionary(matter_result.get("extracted_composition", {})):
			return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_BATCH_RESULT_COMPOSITION_MISMATCH", {"region_id": region_id})
		if float(matter_result.get("deposited_mass_kg", 0.0)) != 0.0:
			return MatterUtils.failure("MATTER_CROSS_REGION_EXTRACTION_RESULT_HAS_DEPOSIT", {"region_id": region_id})

		var participant_entry: Dictionary = _ledger_participant_entry(ledger, region_id)
		if participant_entry.is_empty():
			return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_LEDGER_PARTICIPANT_MISSING", {"region_id": region_id})
		if not Array(participant_entry.get("added", [])).is_empty():
			return MatterUtils.failure("MATTER_CROSS_REGION_EXTRACTION_LEDGER_HAS_REGION_ADDITION", {"region_id": region_id})
		var batch_material_mass: Dictionary = _batch_material_masses(batch)
		var removed_material_mass: Dictionary = _quantity_map(Array(participant_entry.get("removed", [])))
		if not _quantity_maps_equal(batch_material_mass, removed_material_mass, float(ledger.get("tolerance_kg", 0.0))):
			return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_REGION_LEDGER_MISMATCH", {"region_id": region_id})

		for material_id in batch_material_mass.keys():
			aggregate_material_mass[material_id] = float(aggregate_material_mass.get(material_id, 0.0)) 				+ float(batch_material_mass[material_id])
		total_mass_kg += float(batch.get("total_mass_kg", 0.0))
		total_bulk_volume_m3 += float(batch.get("bulk_volume_m3", 0.0))

		var expected_participant_checksum := MatterUtils.compute_checksum({
			"region_id": region_id,
			"participant_checksum": output["participant_checksum"],
			"commit_receipt": commit_receipt,
			"matter_result": matter_result,
			"material_batch": batch,
			"checksum": "",
		})
		if not MatterUtils.is_lower_hex_64(output.get("checksum")) 				or String(output["checksum"]) != expected_participant_checksum:
			return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_PARTICIPANT_OUTPUT_CHECKSUM_MISMATCH", {"region_id": region_id})

	if output_regions != plan_regions:
		return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_PARTICIPANT_SET_MISMATCH")
	var external_output_mass: Dictionary = _quantity_map(Array(ledger.get("external_outputs", [])))
	if not _quantity_maps_equal(
		aggregate_material_mass,
		external_output_mass,
		float(ledger.get("tolerance_kg", 0.0))
	):
		return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_EXTERNAL_OUTPUT_LEDGER_MISMATCH")

	if not MatterUtils.is_positive_number(value.get("total_mass_kg")) 			or absf(float(value["total_mass_kg"]) - total_mass_kg) > MASS_TOLERANCE_KG:
		return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_TOTAL_MASS_MISMATCH")
	if not MatterUtils.is_positive_number(value.get("total_bulk_volume_m3")) 			or absf(float(value["total_bulk_volume_m3"]) - total_bulk_volume_m3) > VOLUME_TOLERANCE_M3:
		return MatterUtils.failure("MATTER_CROSS_REGION_PHYSICAL_TOTAL_VOLUME_MISMATCH")
	var safe: Dictionary = MatterUtils.validate_json_safe(value, "$.matter_cross_region_physical_output")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtils.validate_checksum(value)


static func participant_output_by_region(value: Dictionary, region_id: String) -> Dictionary:
	var normalized := region_id.strip_edges().to_lower()
	for raw_output in Array(value.get("participant_outputs", [])):
		if typeof(raw_output) == TYPE_DICTIONARY 				and String(raw_output.get("region_id", "")) == normalized:
			return Dictionary(raw_output).duplicate(true)
	return {}


static func material_batches(value: Dictionary) -> Array:
	var batches: Array = []
	for raw_output in Array(value.get("participant_outputs", [])):
		if typeof(raw_output) == TYPE_DICTIONARY:
			batches.append(Dictionary(raw_output.get("material_batch", {})).duplicate(true))
	return batches


static func _normalize_participant_output(raw_output: Dictionary) -> Dictionary:
	var value: Dictionary = {
		"region_id": String(raw_output.get("region_id", "")).strip_edges().to_lower(),
		"participant_checksum": String(raw_output.get("participant_checksum", "")).strip_edges().to_lower(),
		"commit_receipt": Dictionary(raw_output.get("commit_receipt", {})).duplicate(true),
		"matter_result": Dictionary(raw_output.get("matter_result", {})).duplicate(true),
		"material_batch": Dictionary(raw_output.get("material_batch", {})).duplicate(true),
		"checksum": "",
	}
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value


static func _ledger_participant_entry(ledger: Dictionary, region_id: String) -> Dictionary:
	for raw_entry in Array(ledger.get("participant_entries", [])):
		if typeof(raw_entry) == TYPE_DICTIONARY 				and String(raw_entry.get("region_id", "")) == region_id:
			return Dictionary(raw_entry).duplicate(true)
	return {}


static func _batch_material_masses(batch: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var total_mass := float(batch.get("total_mass_kg", 0.0))
	var composition: Dictionary = batch.get("composition", {})
	for raw_component in Array(composition.get("components", [])):
		if typeof(raw_component) != TYPE_DICTIONARY:
			continue
		var material_id := String(raw_component.get("material_id", ""))
		result[material_id] = total_mass * float(raw_component.get("mass_fraction", 0.0))
	return result


static func _quantity_map(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_value in values:
		if typeof(raw_value) != TYPE_DICTIONARY:
			continue
		var material_id := String(raw_value.get("material_id", ""))
		result[material_id] = float(result.get(material_id, 0.0)) + float(raw_value.get("mass_kg", 0.0))
	return result


static func _quantity_maps_equal(a: Dictionary, b: Dictionary, tolerance_kg: float) -> bool:
	var ids: Dictionary = {}
	for material_id in a.keys():
		ids[material_id] = true
	for material_id in b.keys():
		ids[material_id] = true
	var tolerance := maxf(MASS_TOLERANCE_KG, tolerance_kg)
	for material_id in ids.keys():
		if absf(float(a.get(material_id, 0.0)) - float(b.get(material_id, 0.0))) > tolerance:
			return false
	return true
