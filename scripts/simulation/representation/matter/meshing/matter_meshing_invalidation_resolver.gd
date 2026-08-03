extends RefCounted

const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const Invalidation = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")
const RepresentationKey = preload("res://scripts/simulation/representation/contracts/representation_key.gd")


static func stale_keys(invalidation: Dictionary, representation_keys: Array) -> Dictionary:
	var checked: Dictionary = Invalidation.validate(invalidation)
	if not bool(checked.get("success", false)):
		return checked
	var previous: Dictionary = invalidation["previous_source_revision"]
	var affected: Dictionary = {}
	for scope_id in invalidation["affected_scope_ids"]:
		affected[String(scope_id)] = true
	var stale: Array = []
	var seen: Dictionary = {}
	for raw_key in representation_keys:
		if typeof(raw_key) != TYPE_DICTIONARY:
			return RepresentationUtils.failure("INVALID_MATTER_MESHING_INVALIDATION_KEY")
		var key: Dictionary = raw_key
		checked = RepresentationKey.validate(key)
		if not bool(checked.get("success", false)):
			return checked
		var source: Dictionary = key["source_revision"]
		if String(source["source_domain"]) != String(previous["source_domain"]) \
			or String(source["source_id"]) != String(previous["source_id"]) \
			or not affected.has(String(key["scope_id"])):
			continue
		var not_newer: bool = int(source["authority_epoch"]) < int(invalidation["new_source_revision"]["authority_epoch"]) \
			or (int(source["authority_epoch"]) == int(invalidation["new_source_revision"]["authority_epoch"]) \
			and int(source["source_revision"]) < int(invalidation["new_source_revision"]["source_revision"]))
		if not not_newer:
			continue
		var checksum: String = String(key["checksum"])
		if not seen.has(checksum):
			seen[checksum] = true
			stale.append(key.duplicate(true))
	stale.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if String(a["scope_id"]) != String(b["scope_id"]):
			return String(a["scope_id"]) < String(b["scope_id"])
		if int(a["lod_level"]) != int(b["lod_level"]):
			return int(a["lod_level"]) < int(b["lod_level"])
		return String(a["variant_id"]) < String(b["variant_id"])
	)
	return RepresentationUtils.success({
		"stale_keys": stale,
		"stale_key_hash": RepresentationUtils.payload_hash(stale),
	})
