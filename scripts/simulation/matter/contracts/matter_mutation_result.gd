extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const AddressScript = preload("res://scripts/simulation/matter/contracts/matter_brick_address.gd")
const CompositionScript = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const LedgerScript = preload("res://scripts/simulation/matter/contracts/matter_mass_ledger.gd")

const SCHEMA: String = "planet_simulator.matter_mutation_result.v1"
const STATUSES: Array[String] = ["COMMITTED", "REJECTED"]
const FIELDS: Array[String] = [
	"schema",
	"operation_id",
	"status",
	"changed_bricks",
	"removed_mass_kg",
	"deposited_mass_kg",
	"extracted_composition",
	"generated_heat_j",
	"consumed_energy_j",
	"created_aggregate_ids",
	"mass_ledger",
	"error_code",
	"checksum",
]
const CHANGED_BRICK_FIELDS: Array[String] = [
	"address", "previous_revision", "new_revision", "snapshot_checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var changed_bricks: Array = Array(data.get("changed_bricks", [])).duplicate(true)
	changed_bricks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("address", {}).get("address_id", "")) \
			< String(b.get("address", {}).get("address_id", ""))
	)
	var value: Dictionary = {
		"schema": SCHEMA,
		"operation_id": String(data.get("operation_id", "")).strip_edges().to_lower(),
		"status": String(data.get("status", "")).strip_edges().to_upper(),
		"changed_bricks": changed_bricks,
		"removed_mass_kg": float(data.get("removed_mass_kg", 0.0)),
		"deposited_mass_kg": float(data.get("deposited_mass_kg", 0.0)),
		"extracted_composition": Dictionary(data.get("extracted_composition", CompositionScript.empty())).duplicate(true),
		"generated_heat_j": float(data.get("generated_heat_j", 0.0)),
		"consumed_energy_j": float(data.get("consumed_energy_j", 0.0)),
		"created_aggregate_ids": MatterUtilsScript.sorted_unique_ids(Array(data.get("created_aggregate_ids", []))),
		"mass_ledger": Dictionary(data.get("mass_ledger", {})).duplicate(true),
		"error_code": String(data.get("error_code", "")).strip_edges().to_upper(),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_MUTATION_RESULT_SCHEMA")
	if not MatterUtilsScript.is_canonical_id(value.get("operation_id"), 2):
		return MatterUtilsScript.failure("INVALID_MATTER_RESULT_OPERATION_ID")
	if typeof(value.get("status")) != TYPE_STRING or not String(value["status"]) in STATUSES:
		return MatterUtilsScript.failure("INVALID_MATTER_RESULT_STATUS")
	if typeof(value.get("changed_bricks")) != TYPE_ARRAY:
		return MatterUtilsScript.failure("INVALID_CHANGED_MATTER_BRICKS")
	var previous_address_id: String = ""
	for index in range(value["changed_bricks"].size()):
		var changed = value["changed_bricks"][index]
		if typeof(changed) != TYPE_DICTIONARY:
			return MatterUtilsScript.failure("INVALID_CHANGED_MATTER_BRICK", {"index": index})
		var changed_exact: Dictionary = MatterUtilsScript.validate_exact_fields(changed, CHANGED_BRICK_FIELDS)
		if not bool(changed_exact.get("success", false)):
			return MatterUtilsScript.failure("INVALID_CHANGED_MATTER_BRICK_FIELDS", {"index": index})
		if typeof(changed.get("address")) != TYPE_DICTIONARY \
			or not bool(AddressScript.validate(changed["address"]).get("success", false)):
			return MatterUtilsScript.failure("INVALID_CHANGED_MATTER_BRICK_ADDRESS", {"index": index})
		var address_id: String = String(changed["address"]["address_id"])
		if index > 0 and address_id <= previous_address_id:
			return MatterUtilsScript.failure("CHANGED_MATTER_BRICKS_NOT_SORTED_UNIQUE", {"index": index})
		for field in ["previous_revision", "new_revision"]:
			if not MatterUtilsScript.is_json_integer(changed.get(field)) or int(changed[field]) < 0:
				return MatterUtilsScript.failure("INVALID_CHANGED_MATTER_REVISION", {"field": field, "index": index})
		if int(changed["new_revision"]) <= int(changed["previous_revision"]):
			return MatterUtilsScript.failure("NON_MONOTONIC_CHANGED_MATTER_REVISION", {"index": index})
		if not MatterUtilsScript.is_lower_hex_64(changed.get("snapshot_checksum")):
			return MatterUtilsScript.failure("INVALID_CHANGED_MATTER_CHECKSUM", {"index": index})
		previous_address_id = address_id
	for field in ["removed_mass_kg", "deposited_mass_kg", "generated_heat_j", "consumed_energy_j"]:
		if not MatterUtilsScript.is_non_negative_number(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_RESULT_QUANTITY", {"field": field})
	if typeof(value.get("extracted_composition")) != TYPE_DICTIONARY \
		or not bool(CompositionScript.validate(value["extracted_composition"]).get("success", false)):
		return MatterUtilsScript.failure("INVALID_EXTRACTED_MATTER_COMPOSITION")
	var created_ids: Dictionary = MatterUtilsScript.validate_sorted_unique_ids(value.get("created_aggregate_ids"), true)
	if not bool(created_ids.get("success", false)):
		return MatterUtilsScript.failure("INVALID_CREATED_MATTER_AGGREGATE_IDS")
	if typeof(value.get("mass_ledger")) != TYPE_DICTIONARY \
		or not bool(LedgerScript.validate(value["mass_ledger"]).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_RESULT_LEDGER")
	if not bool(value["mass_ledger"].get("closed", false)):
		return MatterUtilsScript.failure("OPEN_MATTER_RESULT_LEDGER")
	if String(value["mass_ledger"].get("operation_id", "")) != String(value["operation_id"]):
		return MatterUtilsScript.failure("MATTER_RESULT_LEDGER_OPERATION_MISMATCH")
	if typeof(value.get("error_code")) != TYPE_STRING:
		return MatterUtilsScript.failure("INVALID_MATTER_RESULT_ERROR_CODE")
	if String(value["status"]) == "COMMITTED":
		if not String(value["error_code"]).is_empty() or value["changed_bricks"].is_empty():
			return MatterUtilsScript.failure("INVALID_COMMITTED_MATTER_RESULT")
	else:
		if String(value["error_code"]).is_empty() or not value["changed_bricks"].is_empty():
			return MatterUtilsScript.failure("INVALID_REJECTED_MATTER_RESULT")
		for field in ["removed_mass_kg", "deposited_mass_kg", "generated_heat_j", "consumed_energy_j"]:
			if float(value[field]) != 0.0:
				return MatterUtilsScript.failure("REJECTED_MATTER_RESULT_HAS_EFFECTS", {"field": field})
		if not CompositionScript.is_empty(value["extracted_composition"]) \
			or not value["created_aggregate_ids"].is_empty():
			return MatterUtilsScript.failure("REJECTED_MATTER_RESULT_HAS_OUTPUTS")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_mutation_result")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return MatterUtilsScript.normalize(value, validate)
