extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Participant = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_participant.gd")
const MassLedger = preload("res://scripts/simulation/matter/transactions/distributed/matter_distributed_mass_ledger.gd")

const SCHEMA := "planet_simulator.matter_cross_region_transaction_plan.v1"
const FIELDS: Array[String] = [
	"schema", "transaction_id", "operation_id", "body_id", "created_tick",
	"participants", "mass_ledger", "participant_order_hash", "plan_hash", "checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var participants: Array = Array(data.get("participants", [])).duplicate(true)
	participants.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("region_id", "")) < String(b.get("region_id", ""))
	)
	var participant_checksums: Array = []
	for raw_participant in participants:
		if typeof(raw_participant) != TYPE_DICTIONARY:
			return {}
		participant_checksums.append(String(raw_participant.get("checksum", "")))
	var mass_ledger: Dictionary = Dictionary(data.get("mass_ledger", {})).duplicate(true)
	var value: Dictionary = {
		"schema": SCHEMA,
		"transaction_id": String(data.get("transaction_id", "")).strip_edges().to_lower(),
		"operation_id": String(data.get("operation_id", "")).strip_edges().to_lower(),
		"body_id": String(data.get("body_id", "")).strip_edges().to_lower(),
		"created_tick": int(data.get("created_tick", 0)),
		"participants": participants,
		"mass_ledger": mass_ledger,
		"participant_order_hash": MatterUtils.payload_hash(participant_checksums),
		"plan_hash": "",
		"checksum": "",
	}
	value["plan_hash"] = MatterUtils.payload_hash({
		"transaction_id": value["transaction_id"],
		"operation_id": value["operation_id"],
		"body_id": value["body_id"],
		"created_tick": value["created_tick"],
		"participant_order_hash": value["participant_order_hash"],
		"mass_ledger_checksum": mass_ledger.get("checksum", ""),
	})
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = MatterUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return MatterUtils.failure("UNSUPPORTED_MATTER_CROSS_REGION_TRANSACTION_PLAN_SCHEMA")
	for field in ["transaction_id", "operation_id", "body_id"]:
		if not MatterUtils.is_canonical_id(value.get(field), 2):
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_TRANSACTION_PLAN_ID", {"field": field})
	if not MatterUtils.is_json_integer(value.get("created_tick")) or int(value["created_tick"]) < 0:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_TRANSACTION_PLAN_TICK")
	if typeof(value.get("participants")) != TYPE_ARRAY or value["participants"].size() < 2:
		return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_REQUIRES_MULTIPLE_REGIONS")
	var previous_region_id := ""
	var participant_checksums: Array = []
	var participant_region_ids: Array[String] = []
	for index in range(value["participants"].size()):
		var raw_participant = value["participants"][index]
		if typeof(raw_participant) != TYPE_DICTIONARY:
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_TRANSACTION_PARTICIPANT")
		checked = Participant.validate(raw_participant)
		if not bool(checked.get("success", false)):
			return checked
		var participant: Dictionary = raw_participant
		var region_id: String = String(participant["region_id"])
		if index > 0 and region_id <= previous_region_id:
			return MatterUtils.failure("MATTER_CROSS_REGION_PARTICIPANTS_NOT_SORTED_UNIQUE")
		if String(participant["body_id"]) != String(value["body_id"]):
			return MatterUtils.failure("MATTER_CROSS_REGION_PARTICIPANT_BODY_MISMATCH")
		previous_region_id = region_id
		participant_region_ids.append(region_id)
		participant_checksums.append(String(participant["checksum"]))
	if typeof(value.get("mass_ledger")) != TYPE_DICTIONARY:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_MASS_LEDGER")
	checked = MassLedger.validate(value["mass_ledger"])
	if not bool(checked.get("success", false)):
		return checked
	var ledger: Dictionary = value["mass_ledger"]
	if String(ledger["transaction_id"]) != String(value["transaction_id"]):
		return MatterUtils.failure("MATTER_CROSS_REGION_MASS_LEDGER_TRANSACTION_MISMATCH")
	if MassLedger.participant_region_ids(ledger) != participant_region_ids:
		return MatterUtils.failure("MATTER_CROSS_REGION_MASS_LEDGER_PARTICIPANT_MISMATCH")
	var expected_order_hash: String = MatterUtils.payload_hash(participant_checksums)
	if not MatterUtils.is_lower_hex_64(value.get("participant_order_hash")) \
		or String(value["participant_order_hash"]) != expected_order_hash:
		return MatterUtils.failure("MATTER_CROSS_REGION_PARTICIPANT_ORDER_HASH_MISMATCH")
	var expected_plan_hash: String = MatterUtils.payload_hash({
		"transaction_id": value["transaction_id"],
		"operation_id": value["operation_id"],
		"body_id": value["body_id"],
		"created_tick": int(value["created_tick"]),
		"participant_order_hash": expected_order_hash,
		"mass_ledger_checksum": ledger["checksum"],
	})
	if not MatterUtils.is_lower_hex_64(value.get("plan_hash")) \
		or String(value["plan_hash"]) != expected_plan_hash:
		return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_PLAN_HASH_MISMATCH")
	return MatterUtils.validate_checksum(value)


static func participant_region_ids(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_participant in Array(value.get("participants", [])):
		if typeof(raw_participant) == TYPE_DICTIONARY:
			result.append(String(raw_participant.get("region_id", "")))
	return result


static func participant_by_region(value: Dictionary, region_id: String) -> Dictionary:
	var normalized: String = region_id.strip_edges().to_lower()
	for raw_participant in Array(value.get("participants", [])):
		if typeof(raw_participant) == TYPE_DICTIONARY \
			and String(raw_participant.get("region_id", "")) == normalized:
			return Dictionary(raw_participant).duplicate(true)
	return {}
