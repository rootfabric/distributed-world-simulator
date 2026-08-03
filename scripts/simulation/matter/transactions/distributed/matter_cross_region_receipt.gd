extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")

const SCHEMA := "planet_simulator.matter_cross_region_receipt.v1"
const ACTION_PREPARE := "PREPARE"
const ACTION_COMMIT := "COMMIT"
const ACTION_ROLLBACK := "ROLLBACK"
const ACTIONS: Array[String] = [ACTION_PREPARE, ACTION_COMMIT, ACTION_ROLLBACK]
const FIELDS: Array[String] = [
	"schema", "transaction_id", "region_id", "action", "participant_checksum",
	"prepare_receipt_checksum", "source_revision", "runtime_state_hash", "created_tick",
	"receipt_hash", "checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var action: String = String(data.get("action", "")).strip_edges().to_upper()
	var value: Dictionary = {
		"schema": SCHEMA,
		"transaction_id": String(data.get("transaction_id", "")).strip_edges().to_lower(),
		"region_id": String(data.get("region_id", "")).strip_edges().to_lower(),
		"action": action,
		"participant_checksum": String(data.get("participant_checksum", "")).strip_edges().to_lower(),
		"prepare_receipt_checksum": String(data.get("prepare_receipt_checksum", "")).strip_edges().to_lower(),
		"source_revision": Dictionary(data.get("source_revision", {})).duplicate(true),
		"runtime_state_hash": String(data.get("runtime_state_hash", "")).strip_edges().to_lower(),
		"created_tick": int(data.get("created_tick", 0)),
		"receipt_hash": "",
		"checksum": "",
	}
	value["receipt_hash"] = MatterUtils.payload_hash({
		"transaction_id": value["transaction_id"],
		"region_id": value["region_id"],
		"action": action,
		"participant_checksum": value["participant_checksum"],
		"prepare_receipt_checksum": value["prepare_receipt_checksum"],
		"source_revision_checksum": value["source_revision"].get("checksum", ""),
		"runtime_state_hash": value["runtime_state_hash"],
		"created_tick": value["created_tick"],
	})
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = MatterUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return MatterUtils.failure("UNSUPPORTED_MATTER_CROSS_REGION_RECEIPT_SCHEMA")
	for field in ["transaction_id", "region_id"]:
		if not MatterUtils.is_canonical_id(value.get(field), 2):
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_RECEIPT_ID", {"field": field})
	var action: String = String(value.get("action", ""))
	if not action in ACTIONS:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_RECEIPT_ACTION")
	if not MatterUtils.is_lower_hex_64(value.get("participant_checksum")):
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_RECEIPT_PARTICIPANT_CHECKSUM")
	var prepare_checksum: String = String(value.get("prepare_receipt_checksum", ""))
	if action == ACTION_PREPARE:
		if not prepare_checksum.is_empty():
			return MatterUtils.failure("MATTER_CROSS_REGION_PREPARE_RECEIPT_HAS_PARENT")
	elif not MatterUtils.is_lower_hex_64(prepare_checksum):
		return MatterUtils.failure("MATTER_CROSS_REGION_RECEIPT_PREPARE_CHECKSUM_REQUIRED")
	if typeof(value.get("source_revision")) != TYPE_DICTIONARY:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_RECEIPT_SOURCE")
	checked = SourceRevision.validate(value["source_revision"])
	if not bool(checked.get("success", false)):
		return checked
	if String(value["source_revision"]["source_domain"]) != "MATTER":
		return MatterUtils.failure("MATTER_CROSS_REGION_RECEIPT_SOURCE_DOMAIN_MISMATCH")
	if not MatterUtils.is_lower_hex_64(value.get("runtime_state_hash")):
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_RUNTIME_STATE_HASH")
	if not MatterUtils.is_json_integer(value.get("created_tick")) or int(value["created_tick"]) < 0:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_RECEIPT_TICK")
	var expected_hash: String = MatterUtils.payload_hash({
		"transaction_id": value["transaction_id"],
		"region_id": value["region_id"],
		"action": action,
		"participant_checksum": value["participant_checksum"],
		"prepare_receipt_checksum": prepare_checksum,
		"source_revision_checksum": value["source_revision"]["checksum"],
		"runtime_state_hash": value["runtime_state_hash"],
		"created_tick": int(value["created_tick"]),
	})
	if not MatterUtils.is_lower_hex_64(value.get("receipt_hash")) \
		or String(value["receipt_hash"]) != expected_hash:
		return MatterUtils.failure("MATTER_CROSS_REGION_RECEIPT_HASH_MISMATCH")
	return MatterUtils.validate_checksum(value)
