extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")

const SCHEMA := "planet_simulator.fabric_bridge2_source_slice.v1"
const FIELDS: Array[String] = [
	"schema", "region_id", "source_keys", "frontier", "authority_envelope",
	"slice_hash", "checksum",
]

static func create(
	region_id: String,
	master_frontier: Dictionary,
	master_authority: Dictionary,
	source_keys: Array
) -> Dictionary:
	var checked := Frontier.validate(master_frontier)
	if not bool(checked.get("success", false)):
		return {}
	checked = AuthorityEnvelope.validate_b0_safety(master_authority)
	if not bool(checked.get("success", false)):
		return {}
	var keys := Utils.sorted_strings(source_keys)
	if keys.is_empty():
		return {}
	var sources: Array = []
	var records: Array = []
	var mutable: Array = []
	var readonly: Array = []
	for source_key in keys:
		var source := _source_by_key(master_frontier, String(source_key))
		if source.is_empty():
			return {}
		sources.append(source)
		var record := _authority_record(master_authority, source)
		if record.is_empty():
			return {}
		records.append(record)
		if master_authority["mutable_source_ids"].has(source_key):
			mutable.append(source_key)
		else:
			readonly.append(source_key)
	var frontier := Frontier.create(sources)
	var authority := AuthorityEnvelope.create(
		String(master_authority["execution_owner"]),
		records,
		mutable,
		readonly
	)
	if frontier.is_empty() or authority.is_empty():
		return {}
	var value: Dictionary = {
		"schema": SCHEMA,
		"region_id": region_id,
		"source_keys": keys,
		"frontier": frontier,
		"authority_envelope": authority,
		"slice_hash": "",
		"checksum": "",
	}
	value["slice_hash"] = Utils.canonical_hash({
		"region_id": region_id,
		"source_keys": keys,
		"frontier_hash": frontier["frontier_hash"],
		"authority_checksum": authority["checksum"],
	})
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_BRIDGE2_SOURCE_SLICE_SCHEMA")
	if not Utils.is_canonical_id(value.get("region_id"), 2):
		return Utils.failure("INVALID_BRIDGE2_SOURCE_SLICE_REGION")
	checked = Utils.validate_sorted_unique_strings(value.get("source_keys"), false)
	if not bool(checked.get("success", false)) or value["source_keys"].is_empty():
		return Utils.failure("INVALID_BRIDGE2_SOURCE_SLICE_KEYS")
	if typeof(value.get("frontier")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_BRIDGE2_SOURCE_SLICE_FRONTIER")
	checked = Frontier.validate(value["frontier"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("authority_envelope")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_BRIDGE2_SOURCE_SLICE_AUTHORITY")
	checked = AuthorityEnvelope.validate_b0_safety(value["authority_envelope"])
	if not bool(checked.get("success", false)):
		return checked
	var actual_keys := Frontier.source_keys(value["frontier"])
	actual_keys.sort()
	if actual_keys != value["source_keys"]:
		return Utils.failure("BRIDGE2_SOURCE_SLICE_KEY_COVERAGE_MISMATCH")
	if not Utils.is_lower_hex_64(value.get("slice_hash")):
		return Utils.failure("INVALID_BRIDGE2_SOURCE_SLICE_HASH")
	var expected := Utils.canonical_hash({
		"region_id": value["region_id"],
		"source_keys": value["source_keys"],
		"frontier_hash": value["frontier"]["frontier_hash"],
		"authority_checksum": value["authority_envelope"]["checksum"],
	})
	if String(value["slice_hash"]) != expected:
		return Utils.failure("BRIDGE2_SOURCE_SLICE_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func validate_against_master(
	value: Dictionary,
	master_frontier: Dictionary,
	master_authority: Dictionary
) -> Dictionary:
	var checked := validate(value)
	if not bool(checked.get("success", false)):
		return checked
	checked = Frontier.validate(master_frontier)
	if not bool(checked.get("success", false)):
		return checked
	checked = AuthorityEnvelope.validate_b0_safety(master_authority)
	if not bool(checked.get("success", false)):
		return checked
	for source in value["frontier"]["sources"]:
		var live := _source_by_key(master_frontier, Utils.source_key(String(source["source_domain"]), String(source["source_id"])))
		if live.is_empty() or String(live["checksum"]) != String(source["checksum"]):
			return Utils.failure("BRIDGE2_SOURCE_SLICE_STALE", {
				"region_id": value["region_id"],
				"source_id": source["source_id"],
			})
	return Utils.success()

static func refreshed(
	value: Dictionary,
	master_frontier: Dictionary,
	master_authority: Dictionary
) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return create(
		String(value.get("region_id", "")),
		master_frontier,
		master_authority,
		value.get("source_keys", [])
	)

static func _source_by_key(frontier: Dictionary, key: String) -> Dictionary:
	for source in frontier.get("sources", []):
		var current := Utils.source_key(String(source.get("source_domain", "")), String(source.get("source_id", "")))
		if current == key:
			return Dictionary(source).duplicate(true)
	return {}

static func _authority_record(authority: Dictionary, source: Dictionary) -> Dictionary:
	for record in authority.get("source_authority_frontier", []):
		if String(record.get("source_domain", "")) == String(source["source_domain"]) and String(record.get("source_id", "")) == String(source["source_id"]):
			return Dictionary(record).duplicate(true)
	return {}
