extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const InvalidationBatch = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_invalidation_batch.gd")

const SCHEMA := "planet_simulator.matter_cross_region_invalidation_outbox_record.v1"
const FIELDS: Array[String] = [
	"schema", "outbox_id", "transaction_id", "committed_record_checksum",
	"invalidation_batch", "published", "published_tick", "checksum",
]


static func create(
	outbox_id: String,
	transaction_id: String,
	committed_record_checksum: String,
	invalidation_batch: Dictionary
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"outbox_id": outbox_id.strip_edges().to_lower(),
		"transaction_id": transaction_id.strip_edges().to_lower(),
		"committed_record_checksum": committed_record_checksum.strip_edges().to_lower(),
		"invalidation_batch": invalidation_batch.duplicate(true),
		"published": false,
		"published_tick": -1,
		"checksum": "",
	}
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func mark_published(value: Dictionary, published_tick: int) -> Dictionary:
	if not bool(validate(value).get("success", false)) or bool(value["published"]):
		return value.duplicate(true) if bool(value.get("published", false)) else {}
	var updated: Dictionary = value.duplicate(true)
	updated["published"] = true
	updated["published_tick"] = published_tick
	updated["checksum"] = MatterUtils.compute_checksum(updated)
	return updated if bool(validate(updated).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = MatterUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return MatterUtils.failure("UNSUPPORTED_MATTER_CROSS_REGION_INVALIDATION_OUTBOX_SCHEMA")
	for field in ["outbox_id", "transaction_id"]:
		if not MatterUtils.is_canonical_id(value.get(field), 2):
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_OUTBOX_ID", {"field": field})
	if not MatterUtils.is_lower_hex_64(value.get("committed_record_checksum")):
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_OUTBOX_RECORD_CHECKSUM")
	if typeof(value.get("invalidation_batch")) != TYPE_DICTIONARY:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_OUTBOX_BATCH")
	checked = InvalidationBatch.validate(value["invalidation_batch"])
	if not bool(checked.get("success", false)):
		return checked
	if String(value["invalidation_batch"]["transaction_id"]) != String(value["transaction_id"]):
		return MatterUtils.failure("MATTER_CROSS_REGION_OUTBOX_TRANSACTION_MISMATCH")
	if typeof(value.get("published")) != TYPE_BOOL:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_OUTBOX_PUBLISHED")
	if not MatterUtils.is_json_integer(value.get("published_tick")):
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_OUTBOX_PUBLISHED_TICK")
	if bool(value["published"]):
		if int(value["published_tick"]) < 0:
			return MatterUtils.failure("MATTER_CROSS_REGION_OUTBOX_PUBLISHED_TICK_REQUIRED")
	elif int(value["published_tick"]) != -1:
		return MatterUtils.failure("MATTER_CROSS_REGION_OUTBOX_UNPUBLISHED_TICK_CHANGED")
	return MatterUtils.validate_checksum(value)
