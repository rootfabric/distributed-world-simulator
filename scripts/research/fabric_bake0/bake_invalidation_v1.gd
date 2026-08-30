extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_invalidation.v1"
const FIELDS: Array[String] = [
	"schema", "invalidation_id", "artifact_id", "reason",
	"previous_source_frontier_hash", "current_source_frontier_hash",
	"created_tick", "state_after", "checksum",
]
const REASONS: Array[String] = [
	"AUTHORITY", "BAKE_POLICY", "BOUNDARY_CONTRACT", "DEPENDENCY",
	"FABRIC_COMPILER", "MANUAL", "REFINEMENT_GUARD", "SOURCE_REVISION",
	"UNSUPPORTED_MODE", "VALIDITY_EXIT",
]
const STALE := "STALE"

static func create(
	invalidation_id: String, artifact_id: String, reason: String,
	previous_source_frontier_hash: String, current_source_frontier_hash: String,
	created_tick: int
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"invalidation_id": invalidation_id,
		"artifact_id": artifact_id,
		"reason": reason,
		"previous_source_frontier_hash": previous_source_frontier_hash,
		"current_source_frontier_hash": current_source_frontier_hash,
		"created_tick": created_tick,
		"state_after": STALE,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_BAKE_INVALIDATION_SCHEMA")
	if not Utils.is_canonical_id(value.get("invalidation_id"), 2) or not Utils.is_canonical_id(value.get("artifact_id"), 2):
		return Utils.failure("INVALID_BAKE_INVALIDATION_ID")
	if not REASONS.has(String(value.get("reason", ""))):
		return Utils.failure("INVALID_BAKE_INVALIDATION_REASON")
	for field in ["previous_source_frontier_hash", "current_source_frontier_hash"]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_BAKE_INVALIDATION_FRONTIER_HASH", {"field": field})
	if String(value["reason"]) == "SOURCE_REVISION" and String(value["previous_source_frontier_hash"]) == String(value["current_source_frontier_hash"]):
		return Utils.failure("BAKE_SOURCE_REVISION_INVALIDATION_WITHOUT_CHANGE")
	if not Utils.is_json_integer(value.get("created_tick")) or int(value["created_tick"]) < 0:
		return Utils.failure("INVALID_BAKE_INVALIDATION_TICK")
	if String(value.get("state_after", "")) != STALE:
		return Utils.failure("BAKE_INVALIDATION_MUST_MARK_STALE")
	return Utils.validate_checksum(value)
