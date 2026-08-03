extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")

const SCHEMA := "planet_simulator.matter_distributed_mass_ledger.v1"
const FIELDS: Array[String] = [
	"schema", "transaction_id", "participant_entries", "external_inputs",
	"external_outputs", "material_balances", "tolerance_kg", "checksum",
]
const PARTICIPANT_FIELDS: Array[String] = ["region_id", "removed", "added", "checksum"]
const QUANTITY_FIELDS: Array[String] = ["material_id", "mass_kg"]
const BALANCE_FIELDS: Array[String] = [
	"material_id", "region_removed_kg", "region_added_kg", "external_input_kg",
	"external_output_kg", "residual_kg",
]


static func create(
	transaction_id: String,
	participant_entries: Array,
	external_inputs: Array = [],
	external_outputs: Array = [],
	tolerance_kg: float = 0.000000001
) -> Dictionary:
	var participants: Array = []
	for raw_entry in participant_entries:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			return {}
		var entry: Dictionary = _create_participant_entry(raw_entry)
		if entry.is_empty():
			return {}
		participants.append(entry)
	participants.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("region_id", "")) < String(b.get("region_id", ""))
	)
	var inputs: Array = _normalize_quantities(external_inputs)
	var outputs: Array = _normalize_quantities(external_outputs)
	if inputs.is_empty() and not external_inputs.is_empty():
		return {}
	if outputs.is_empty() and not external_outputs.is_empty():
		return {}
	var balances: Array = _build_balances(participants, inputs, outputs)
	var value: Dictionary = {
		"schema": SCHEMA,
		"transaction_id": transaction_id.strip_edges().to_lower(),
		"participant_entries": participants,
		"external_inputs": inputs,
		"external_outputs": outputs,
		"material_balances": balances,
		"tolerance_kg": tolerance_kg,
		"checksum": "",
	}
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = MatterUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return MatterUtils.failure("UNSUPPORTED_MATTER_DISTRIBUTED_MASS_LEDGER_SCHEMA")
	if not MatterUtils.is_canonical_id(value.get("transaction_id"), 2):
		return MatterUtils.failure("INVALID_MATTER_DISTRIBUTED_MASS_LEDGER_TRANSACTION_ID")
	if not MatterUtils.is_positive_number(value.get("tolerance_kg")) \
		or float(value["tolerance_kg"]) > 0.001:
		return MatterUtils.failure("INVALID_MATTER_DISTRIBUTED_MASS_TOLERANCE")
	if typeof(value.get("participant_entries")) != TYPE_ARRAY \
		or value["participant_entries"].size() < 2:
		return MatterUtils.failure("MATTER_DISTRIBUTED_MASS_PARTICIPANTS_REQUIRED")
	var previous_region_id := ""
	for index in range(value["participant_entries"].size()):
		var raw_entry = value["participant_entries"][index]
		if typeof(raw_entry) != TYPE_DICTIONARY:
			return MatterUtils.failure("INVALID_MATTER_DISTRIBUTED_MASS_PARTICIPANT_ENTRY")
		checked = _validate_participant_entry(raw_entry)
		if not bool(checked.get("success", false)):
			return checked
		var region_id: String = String(raw_entry["region_id"])
		if index > 0 and region_id <= previous_region_id:
			return MatterUtils.failure("MATTER_DISTRIBUTED_MASS_PARTICIPANTS_NOT_SORTED_UNIQUE")
		previous_region_id = region_id
	checked = _validate_quantities(value.get("external_inputs"), "INPUT")
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_quantities(value.get("external_outputs"), "OUTPUT")
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("material_balances")) != TYPE_ARRAY:
		return MatterUtils.failure("INVALID_MATTER_DISTRIBUTED_MASS_BALANCES")
	var expected_balances: Array = _build_balances(
		value["participant_entries"], value["external_inputs"], value["external_outputs"]
	)
	if value["material_balances"] != expected_balances:
		return MatterUtils.failure("MATTER_DISTRIBUTED_MASS_BALANCE_DERIVATION_MISMATCH")
	var previous_material_id := ""
	for index in range(value["material_balances"].size()):
		var raw_balance = value["material_balances"][index]
		if typeof(raw_balance) != TYPE_DICTIONARY:
			return MatterUtils.failure("INVALID_MATTER_DISTRIBUTED_MASS_BALANCE")
		checked = MatterUtils.validate_exact_fields(raw_balance, BALANCE_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var material_id: String = String(raw_balance.get("material_id", ""))
		if not MatterUtils.is_canonical_id(material_id, 2):
			return MatterUtils.failure("INVALID_MATTER_DISTRIBUTED_MASS_MATERIAL_ID")
		if index > 0 and material_id <= previous_material_id:
			return MatterUtils.failure("MATTER_DISTRIBUTED_MASS_BALANCES_NOT_SORTED_UNIQUE")
		previous_material_id = material_id
		for field in [
			"region_removed_kg", "region_added_kg", "external_input_kg", "external_output_kg",
		]:
			if not MatterUtils.is_non_negative_number(raw_balance.get(field)):
				return MatterUtils.failure("INVALID_MATTER_DISTRIBUTED_MASS_BALANCE_VALUE", {"field": field})
		if not MatterUtils.is_finite_number(raw_balance.get("residual_kg")):
			return MatterUtils.failure("INVALID_MATTER_DISTRIBUTED_MASS_RESIDUAL")
		if absf(float(raw_balance["residual_kg"])) > float(value["tolerance_kg"]):
			return MatterUtils.failure("MATTER_DISTRIBUTED_MASS_NOT_CONSERVED", {
				"material_id": material_id,
				"residual_kg": float(raw_balance["residual_kg"]),
			})
	return MatterUtils.validate_checksum(value)


static func participant_region_ids(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_entry in Array(value.get("participant_entries", [])):
		if typeof(raw_entry) == TYPE_DICTIONARY:
			result.append(String(raw_entry.get("region_id", "")))
	return result


static func _create_participant_entry(data: Dictionary) -> Dictionary:
	var removed: Array = _normalize_quantities(Array(data.get("removed", [])))
	var added: Array = _normalize_quantities(Array(data.get("added", [])))
	if removed.is_empty() and not Array(data.get("removed", [])).is_empty():
		return {}
	if added.is_empty() and not Array(data.get("added", [])).is_empty():
		return {}
	var value: Dictionary = {
		"region_id": String(data.get("region_id", "")).strip_edges().to_lower(),
		"removed": removed,
		"added": added,
		"checksum": "",
	}
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value if bool(_validate_participant_entry(value).get("success", false)) else {}


static func _validate_participant_entry(value: Dictionary) -> Dictionary:
	var checked: Dictionary = MatterUtils.validate_exact_fields(value, PARTICIPANT_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if not MatterUtils.is_canonical_id(value.get("region_id"), 2):
		return MatterUtils.failure("INVALID_MATTER_DISTRIBUTED_MASS_REGION_ID")
	checked = _validate_quantities(value.get("removed"), "REMOVED")
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_quantities(value.get("added"), "ADDED")
	if not bool(checked.get("success", false)):
		return checked
	return MatterUtils.validate_checksum(value)


static func _normalize_quantities(values: Array) -> Array:
	var totals: Dictionary = {}
	for raw_value in values:
		if typeof(raw_value) != TYPE_DICTIONARY:
			return []
		var material_id: String = String(raw_value.get("material_id", "")).strip_edges().to_lower()
		var mass = raw_value.get("mass_kg")
		if not MatterUtils.is_canonical_id(material_id, 2) or not MatterUtils.is_non_negative_number(mass):
			return []
		totals[material_id] = float(totals.get(material_id, 0.0)) + float(mass)
	var ids: Array = totals.keys()
	ids.sort()
	var result: Array = []
	for material_id in ids:
		result.append({"material_id": material_id, "mass_kg": float(totals[material_id])})
	return result


static func _validate_quantities(value, label: String) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return MatterUtils.failure("INVALID_MATTER_DISTRIBUTED_MASS_%s_QUANTITIES" % label)
	var previous_material_id := ""
	for index in range(value.size()):
		var raw_quantity = value[index]
		if typeof(raw_quantity) != TYPE_DICTIONARY:
			return MatterUtils.failure("INVALID_MATTER_DISTRIBUTED_MASS_%s_QUANTITY" % label)
		var checked: Dictionary = MatterUtils.validate_exact_fields(raw_quantity, QUANTITY_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var material_id: String = String(raw_quantity.get("material_id", ""))
		if not MatterUtils.is_canonical_id(material_id, 2) \
			or not MatterUtils.is_non_negative_number(raw_quantity.get("mass_kg")):
			return MatterUtils.failure("INVALID_MATTER_DISTRIBUTED_MASS_%s_QUANTITY" % label)
		if index > 0 and material_id <= previous_material_id:
			return MatterUtils.failure("MATTER_DISTRIBUTED_MASS_%s_NOT_SORTED_UNIQUE" % label)
		previous_material_id = material_id
	return MatterUtils.success()


static func _build_balances(participants: Array, inputs: Array, outputs: Array) -> Array:
	var totals: Dictionary = {}
	for raw_entry in participants:
		var entry: Dictionary = raw_entry
		for raw_quantity in entry.get("removed", []):
			_accumulate(totals, String(raw_quantity["material_id"]), "region_removed_kg", float(raw_quantity["mass_kg"]))
		for raw_quantity in entry.get("added", []):
			_accumulate(totals, String(raw_quantity["material_id"]), "region_added_kg", float(raw_quantity["mass_kg"]))
	for raw_quantity in inputs:
		_accumulate(totals, String(raw_quantity["material_id"]), "external_input_kg", float(raw_quantity["mass_kg"]))
	for raw_quantity in outputs:
		_accumulate(totals, String(raw_quantity["material_id"]), "external_output_kg", float(raw_quantity["mass_kg"]))
	var ids: Array = totals.keys()
	ids.sort()
	var result: Array = []
	for material_id in ids:
		var row: Dictionary = totals[material_id]
		var removed: float = float(row.get("region_removed_kg", 0.0))
		var added: float = float(row.get("region_added_kg", 0.0))
		var input: float = float(row.get("external_input_kg", 0.0))
		var output: float = float(row.get("external_output_kg", 0.0))
		result.append({
			"material_id": material_id,
			"region_removed_kg": removed,
			"region_added_kg": added,
			"external_input_kg": input,
			"external_output_kg": output,
			"residual_kg": removed + input - added - output,
		})
	return result


static func _accumulate(totals: Dictionary, material_id: String, field: String, amount: float) -> void:
	if not totals.has(material_id):
		totals[material_id] = {
			"region_removed_kg": 0.0,
			"region_added_kg": 0.0,
			"external_input_kg": 0.0,
			"external_output_kg": 0.0,
		}
	var row: Dictionary = totals[material_id]
	row[field] = float(row.get(field, 0.0)) + amount
	totals[material_id] = row
