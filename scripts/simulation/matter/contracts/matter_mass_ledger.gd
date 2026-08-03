extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")

const SCHEMA: String = "planet_simulator.matter_mass_ledger.v1"
const FIELDS: Array[String] = [
	"schema",
	"operation_id",
	"inputs",
	"outputs",
	"tolerance_kg",
	"input_total_kg",
	"output_total_kg",
	"balance_error_kg",
	"material_balance_kg",
	"closed",
	"checksum",
]
const ENTRY_FIELDS: Array[String] = ["account_id", "material_id", "mass_kg"]


static func create(
	operation_id: String,
	inputs: Array,
	outputs: Array,
	tolerance_kg: float = 0.000001
) -> Dictionary:
	var normalized_inputs: Array = _normalize_entries(inputs)
	var normalized_outputs: Array = _normalize_entries(outputs)
	var calculations: Dictionary = _calculate(normalized_inputs, normalized_outputs, tolerance_kg)
	var value: Dictionary = {
		"schema": SCHEMA,
		"operation_id": operation_id.strip_edges().to_lower(),
		"inputs": normalized_inputs,
		"outputs": normalized_outputs,
		"tolerance_kg": tolerance_kg,
		"input_total_kg": calculations.get("input_total_kg", 0.0),
		"output_total_kg": calculations.get("output_total_kg", 0.0),
		"balance_error_kg": calculations.get("balance_error_kg", 0.0),
		"material_balance_kg": calculations.get("material_balance_kg", {}),
		"closed": calculations.get("closed", false),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_MASS_LEDGER_SCHEMA")
	if not MatterUtilsScript.is_canonical_id(value.get("operation_id"), 2):
		return MatterUtilsScript.failure("INVALID_MATTER_LEDGER_OPERATION_ID")
	for field in ["inputs", "outputs"]:
		var entries_result: Dictionary = _validate_entries(value.get(field))
		if not bool(entries_result.get("success", false)):
			return MatterUtilsScript.failure("INVALID_MATTER_LEDGER_ENTRIES", {"field": field})
	if not MatterUtilsScript.is_non_negative_number(value.get("tolerance_kg")):
		return MatterUtilsScript.failure("INVALID_MATTER_LEDGER_TOLERANCE")
	for field in ["input_total_kg", "output_total_kg"]:
		if not MatterUtilsScript.is_non_negative_number(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_LEDGER_TOTAL", {"field": field})
	if not MatterUtilsScript.is_finite_number(value.get("balance_error_kg")):
		return MatterUtilsScript.failure("INVALID_MATTER_LEDGER_BALANCE")
	if typeof(value.get("material_balance_kg")) != TYPE_DICTIONARY:
		return MatterUtilsScript.failure("INVALID_MATTER_MATERIAL_BALANCE")
	for material_id in value["material_balance_kg"].keys():
		if not MatterUtilsScript.is_canonical_id(material_id, 2) \
			or not MatterUtilsScript.is_finite_number(value["material_balance_kg"][material_id]):
			return MatterUtilsScript.failure("INVALID_MATTER_MATERIAL_BALANCE_ENTRY")
	if typeof(value.get("closed")) != TYPE_BOOL:
		return MatterUtilsScript.failure("INVALID_MATTER_LEDGER_CLOSED_FLAG")
	var calculated: Dictionary = _calculate(value["inputs"], value["outputs"], float(value["tolerance_kg"]))
	for field in ["input_total_kg", "output_total_kg", "balance_error_kg"]:
		if not MatterUtilsScript.approximately_equal(float(value[field]), float(calculated[field]), 0.000000000001):
			return MatterUtilsScript.failure("MATTER_LEDGER_DERIVED_FIELD_MISMATCH", {"field": field})
	if value["material_balance_kg"] != calculated["material_balance_kg"]:
		return MatterUtilsScript.failure("MATTER_LEDGER_MATERIAL_BALANCE_MISMATCH")
	if bool(value["closed"]) != bool(calculated["closed"]):
		return MatterUtilsScript.failure("MATTER_LEDGER_CLOSED_MISMATCH")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_mass_ledger")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return MatterUtilsScript.normalize(value, validate)


static func _normalize_entries(entries: Array) -> Array:
	var result: Array = []
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		result.append({
			"account_id": String(entry.get("account_id", "")).strip_edges().to_lower(),
			"material_id": String(entry.get("material_id", "")).strip_edges().to_lower(),
			"mass_kg": float(entry.get("mass_kg", 0.0)),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_key: String = "%s|%s" % [a.get("material_id", ""), a.get("account_id", "")]
		var b_key: String = "%s|%s" % [b.get("material_id", ""), b.get("account_id", "")]
		return a_key < b_key
	)
	return result


static func _validate_entries(entries) -> Dictionary:
	if typeof(entries) != TYPE_ARRAY:
		return MatterUtilsScript.failure("INVALID_LEDGER_ENTRY_ARRAY")
	var previous_key: String = ""
	for index in range(entries.size()):
		var entry = entries[index]
		if typeof(entry) != TYPE_DICTIONARY:
			return MatterUtilsScript.failure("INVALID_LEDGER_ENTRY", {"index": index})
		var exact: Dictionary = MatterUtilsScript.validate_exact_fields(entry, ENTRY_FIELDS)
		if not bool(exact.get("success", false)):
			return exact
		if not MatterUtilsScript.is_canonical_id(entry.get("account_id"), 2):
			return MatterUtilsScript.failure("INVALID_LEDGER_ACCOUNT_ID", {"index": index})
		if not MatterUtilsScript.is_canonical_id(entry.get("material_id"), 2):
			return MatterUtilsScript.failure("INVALID_LEDGER_MATERIAL_ID", {"index": index})
		if not MatterUtilsScript.is_positive_number(entry.get("mass_kg")):
			return MatterUtilsScript.failure("INVALID_LEDGER_MASS", {"index": index})
		var key: String = "%s|%s" % [entry["material_id"], entry["account_id"]]
		if index > 0 and key <= previous_key:
			return MatterUtilsScript.failure("LEDGER_ENTRIES_NOT_SORTED_UNIQUE", {"index": index})
		previous_key = key
	return MatterUtilsScript.success()


static func _calculate(inputs: Array, outputs: Array, tolerance_kg: float) -> Dictionary:
	var input_total: float = 0.0
	var output_total: float = 0.0
	var material_balance: Dictionary = {}
	for entry in inputs:
		var mass: float = float(entry.get("mass_kg", 0.0))
		var material_id: String = String(entry.get("material_id", ""))
		input_total += mass
		material_balance[material_id] = float(material_balance.get(material_id, 0.0)) - mass
	for entry in outputs:
		var mass: float = float(entry.get("mass_kg", 0.0))
		var material_id: String = String(entry.get("material_id", ""))
		output_total += mass
		material_balance[material_id] = float(material_balance.get(material_id, 0.0)) + mass
	var sorted_material_ids: Array = material_balance.keys()
	sorted_material_ids.sort()
	var canonical_balance: Dictionary = {}
	var closed: bool = absf(output_total - input_total) <= tolerance_kg
	for material_id in sorted_material_ids:
		var balance: float = float(material_balance[material_id])
		canonical_balance[material_id] = balance
		closed = closed and absf(balance) <= tolerance_kg
	return {
		"input_total_kg": input_total,
		"output_total_kg": output_total,
		"balance_error_kg": output_total - input_total,
		"material_balance_kg": canonical_balance,
		"closed": closed,
	}
