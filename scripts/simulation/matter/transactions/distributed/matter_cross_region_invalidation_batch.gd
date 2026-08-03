extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Invalidation = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")

const SCHEMA := "planet_simulator.matter_cross_region_invalidation_batch.v1"
const FIELDS: Array[String] = [
	"schema", "batch_id", "transaction_id", "global_commit_hash",
	"invalidations", "created_tick", "checksum",
]


static func create(
	batch_id: String,
	transaction_id: String,
	global_commit_hash: String,
	invalidations: Array,
	created_tick: int
) -> Dictionary:
	var sorted_invalidations: Array = invalidations.duplicate(true)
	sorted_invalidations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("invalidation_id", "")) < String(b.get("invalidation_id", ""))
	)
	var value: Dictionary = {
		"schema": SCHEMA,
		"batch_id": batch_id.strip_edges().to_lower(),
		"transaction_id": transaction_id.strip_edges().to_lower(),
		"global_commit_hash": global_commit_hash.strip_edges().to_lower(),
		"invalidations": sorted_invalidations,
		"created_tick": created_tick,
		"checksum": "",
	}
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = MatterUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return MatterUtils.failure("UNSUPPORTED_MATTER_CROSS_REGION_INVALIDATION_BATCH_SCHEMA")
	for field in ["batch_id", "transaction_id"]:
		if not MatterUtils.is_canonical_id(value.get(field), 2):
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_INVALIDATION_BATCH_ID", {"field": field})
	if not MatterUtils.is_lower_hex_64(value.get("global_commit_hash")):
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_GLOBAL_COMMIT_HASH")
	if typeof(value.get("invalidations")) != TYPE_ARRAY or value["invalidations"].size() < 2:
		return MatterUtils.failure("MATTER_CROSS_REGION_INVALIDATIONS_REQUIRED")
	var previous_id := ""
	for index in range(value["invalidations"].size()):
		var raw_invalidation = value["invalidations"][index]
		if typeof(raw_invalidation) != TYPE_DICTIONARY:
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_INVALIDATION")
		checked = Invalidation.validate(raw_invalidation)
		if not bool(checked.get("success", false)):
			return checked
		var invalidation_id: String = String(raw_invalidation["invalidation_id"])
		if index > 0 and invalidation_id <= previous_id:
			return MatterUtils.failure("MATTER_CROSS_REGION_INVALIDATIONS_NOT_SORTED_UNIQUE")
		previous_id = invalidation_id
	if not MatterUtils.is_json_integer(value.get("created_tick")) or int(value["created_tick"]) < 0:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_INVALIDATION_BATCH_TICK")
	return MatterUtils.validate_checksum(value)
