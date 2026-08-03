extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")

const SCHEMA := "planet_simulator.representation_invalidation.v1"
const FIELDS: Array[String] = [
	"schema",
	"invalidation_id",
	"previous_source_revision",
	"new_source_revision",
	"dirty_bounds_m",
	"reason",
	"affected_scope_ids",
	"created_tick",
	"checksum",
]


static func create(
	invalidation_id: String,
	previous_source_revision: Dictionary,
	new_source_revision: Dictionary,
	dirty_bounds_m: Array,
	reason: String,
	affected_scope_ids: Array,
	created_tick: int
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"invalidation_id": invalidation_id,
		"previous_source_revision": previous_source_revision.duplicate(true),
		"new_source_revision": new_source_revision.duplicate(true),
		"dirty_bounds_m": dirty_bounds_m.duplicate(true),
		"reason": reason,
		"affected_scope_ids": affected_scope_ids.duplicate(true),
		"created_tick": created_tick,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_REPRESENTATION_INVALIDATION_SCHEMA")
	if not Utils.is_canonical_id(value.get("invalidation_id"), 2):
		return Utils.failure("INVALID_REPRESENTATION_INVALIDATION_ID")
	if typeof(value.get("previous_source_revision")) != TYPE_DICTIONARY \
		or typeof(value.get("new_source_revision")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_REPRESENTATION_INVALIDATION_SOURCE")
	var previous: Dictionary = value["previous_source_revision"]
	var current: Dictionary = value["new_source_revision"]
	checked = SourceRevision.validate(previous)
	if not bool(checked.get("success", false)):
		return checked
	checked = SourceRevision.validate(current)
	if not bool(checked.get("success", false)):
		return checked
	if String(previous["source_domain"]) != String(current["source_domain"]) \
		or String(previous["source_id"]) != String(current["source_id"]):
		return Utils.failure("REPRESENTATION_INVALIDATION_SOURCE_CHANGED")
	var previous_epoch: int = int(previous["authority_epoch"])
	var current_epoch: int = int(current["authority_epoch"])
	var previous_revision: int = int(previous["source_revision"])
	var current_revision: int = int(current["source_revision"])
	if current_epoch < previous_epoch:
		return Utils.failure("REPRESENTATION_INVALIDATION_AUTHORITY_ROLLBACK")
	if current_epoch == previous_epoch and current_revision <= previous_revision:
		return Utils.failure("REPRESENTATION_INVALIDATION_REVISION_NOT_ADVANCED")
	if current_epoch > previous_epoch and current_revision < previous_revision:
		return Utils.failure("REPRESENTATION_INVALIDATION_REVISION_ROLLBACK")
	checked = Utils.validate_bounds_m(value.get("dirty_bounds_m"))
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("reason")) != TYPE_STRING or not Utils.INVALIDATION_REASONS.has(String(value["reason"])):
		return Utils.failure("INVALID_REPRESENTATION_INVALIDATION_REASON")
	checked = Utils.validate_sorted_unique_ids(value.get("affected_scope_ids"), false)
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_json_integer(value.get("created_tick")) or int(value["created_tick"]) < 0:
		return Utils.failure("INVALID_REPRESENTATION_INVALIDATION_TICK")
	return Utils.validate_checksum(value)
