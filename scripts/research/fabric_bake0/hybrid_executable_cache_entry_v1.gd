extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const P0Cache = preload("res://scripts/research/fabric_bake0/lazy_mode_cache_entry_v1.gd")
const ExecutableMode = preload("res://scripts/research/fabric_bake0/hybrid_executable_mode_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_hybrid_executable_cache_entry.v1"
const QUALIFICATION := "B0_5_A_EXECUTABLE_CACHE"
const FIELDS: Array[String] = [
	"schema", "p0_cache_entry", "mode_contract_hash", "mode_descriptor_checksum",
	"physical_bundle_hash", "physical_artifact_checksum",
	"validity_state", "invalidation_reason", "derived_only",
	"execution_qualification", "cache_hash", "checksum",
]

static func create(p0_cache_entry: Dictionary, mode_contract: Dictionary) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"p0_cache_entry": p0_cache_entry.duplicate(true),
		"mode_contract_hash": String(mode_contract.get("mode_contract_hash", "")),
		"mode_descriptor_checksum": String(mode_contract.get("mode_descriptor_checksum", "")),
		"physical_bundle_hash": String(mode_contract.get("physical_bundle_hash", "")),
		"physical_artifact_checksum": String(mode_contract.get("physical_artifact_checksum", "")),
		"validity_state": String(p0_cache_entry.get("validity_state", "")),
		"invalidation_reason": String(p0_cache_entry.get("invalidation_reason", "")),
		"derived_only": true,
		"execution_qualification": QUALIFICATION,
		"cache_hash": "",
		"checksum": "",
	}
	value["cache_hash"] = Utils.canonical_hash(_identity_payload(value))
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_HYBRID_EXECUTABLE_CACHE_SCHEMA")
	if typeof(value.get("p0_cache_entry")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_HYBRID_EXECUTABLE_P0_CACHE")
	checked = P0Cache.validate(value["p0_cache_entry"])
	if not bool(checked.get("success", false)):
		return checked
	for field in [
		"mode_contract_hash", "mode_descriptor_checksum", "physical_bundle_hash",
		"physical_artifact_checksum", "cache_hash",
	]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_HYBRID_EXECUTABLE_CACHE_HASH", {"field": field})
	if typeof(value.get("derived_only")) != TYPE_BOOL or not bool(value["derived_only"]):
		return Utils.failure("HYBRID_EXECUTABLE_CACHE_MUST_BE_DERIVED_ONLY")
	if String(value.get("execution_qualification", "")) != QUALIFICATION:
		return Utils.failure("HYBRID_EXECUTABLE_CACHE_QUALIFICATION_MISMATCH")
	if String(value["validity_state"]) != String(value["p0_cache_entry"]["validity_state"]):
		return Utils.failure("HYBRID_EXECUTABLE_CACHE_STATE_MISMATCH")
	if String(value["invalidation_reason"]) != String(value["p0_cache_entry"]["invalidation_reason"]):
		return Utils.failure("HYBRID_EXECUTABLE_CACHE_REASON_MISMATCH")
	if String(value["cache_hash"]) != Utils.canonical_hash(_identity_payload(value)):
		return Utils.failure("HYBRID_EXECUTABLE_CACHE_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func validate_against(
	value: Dictionary,
	p0_cache_entry: Dictionary,
	mode_contract: Dictionary,
	mode_descriptor: Dictionary,
	physical_bundle: Dictionary
) -> Dictionary:
	var checked := validate(value)
	if not bool(checked.get("success", false)):
		return checked
	checked = P0Cache.validate_against(p0_cache_entry, mode_descriptor["mode_signature"], mode_descriptor)
	if not bool(checked.get("success", false)):
		return checked
	checked = ExecutableMode.validate(mode_contract, mode_descriptor, physical_bundle)
	if not bool(checked.get("success", false)):
		return checked
	if value["p0_cache_entry"] != p0_cache_entry:
		return Utils.failure("HYBRID_EXECUTABLE_CACHE_P0_ENTRY_MISMATCH")
	if String(value["mode_contract_hash"]) != String(mode_contract["mode_contract_hash"]):
		return Utils.failure("HYBRID_EXECUTABLE_CACHE_MODE_MISMATCH")
	if String(value["mode_descriptor_checksum"]) != String(mode_descriptor["checksum"]):
		return Utils.failure("HYBRID_EXECUTABLE_CACHE_DESCRIPTOR_MISMATCH")
	if String(value["physical_bundle_hash"]) != String(physical_bundle["bundle_hash"]):
		return Utils.failure("HYBRID_EXECUTABLE_CACHE_BUNDLE_MISMATCH")
	if String(value["physical_artifact_checksum"]) != String(physical_bundle["physical_artifact"]["checksum"]):
		return Utils.failure("HYBRID_EXECUTABLE_CACHE_ARTIFACT_MISMATCH")
	return Utils.success()

static func invalidate(value: Dictionary, reason: String) -> Dictionary:
	var checked := validate(value)
	if not bool(checked.get("success", false)):
		return {}
	var stale_p0 := P0Cache.invalidate(value["p0_cache_entry"], reason)
	if stale_p0.is_empty():
		return {}
	var stale := value.duplicate(true)
	stale["p0_cache_entry"] = stale_p0
	stale["validity_state"] = "STALE"
	stale["invalidation_reason"] = reason
	stale["cache_hash"] = Utils.canonical_hash(_identity_payload(stale))
	stale["checksum"] = Utils.compute_checksum(stale)
	return stale if bool(validate(stale).get("success", false)) else {}

static func _identity_payload(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("cache_hash")
	payload.erase("checksum")
	return payload
