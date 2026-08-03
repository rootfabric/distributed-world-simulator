extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CellAddress = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const SummaryNode = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_node.gd")

const SCHEMA := "planet_simulator.matter_summary_persistence_manifest.v1"
const ENTRY_FIELDS: Array[String] = [
	"summary_id", "cell_id", "cell_address", "scope_id", "level", "authority_epoch",
	"summary_revision", "build_generation", "summary_hash", "dependency_hash",
	"descendant_revision_hash", "storage_key",
]
const FIELDS: Array[String] = [
	"schema", "manifest_id", "body_id", "region_root_address", "grid_profile_hash",
	"authority_epoch", "source_revision", "manifest_revision", "entry_count", "entries", "manifest_hash", "checksum",
]


static func create(
	manifest_id: String,
	body_id: String,
	region_root_address: Dictionary,
	grid_profile_hash: String,
	source_revision: Dictionary,
	manifest_revision: int,
	summaries: Array
) -> Dictionary:
	var entries: Array = []
	for summary_value in summaries:
		if typeof(summary_value) != TYPE_DICTIONARY:
			return {}
		var summary: Dictionary = summary_value
		if not bool(SummaryNode.validate(summary).get("success", false)):
			return {}
		entries.append({
			"summary_id": String(summary["summary_id"]),
			"cell_id": String(summary["cell_address"]["cell_id"]),
			"cell_address": Dictionary(summary["cell_address"]).duplicate(true),
			"scope_id": String(summary["scope_id"]),
			"level": int(summary["cell_address"]["level"]),
			"authority_epoch": int(summary["authority_epoch"]),
			"summary_revision": int(summary["summary_revision"]),
			"build_generation": int(summary["build_generation"]),
			"summary_hash": String(summary["checksum"]),
			"dependency_hash": String(summary["dependency_hash"]),
			"descendant_revision_hash": String(summary["descendant_revision_hash"]),
			"storage_key": "summary/%s" % String(summary["checksum"]),
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["cell_id"]) < String(b["cell_id"])
	)
	var value: Dictionary = {
		"schema": SCHEMA,
		"manifest_id": manifest_id,
		"body_id": body_id,
		"region_root_address": region_root_address.duplicate(true),
		"grid_profile_hash": grid_profile_hash,
		"authority_epoch": int(source_revision.get("authority_epoch", 0)),
		"source_revision": source_revision.duplicate(true),
		"manifest_revision": manifest_revision,
		"entry_count": entries.size(),
		"entries": entries,
		"manifest_hash": RepresentationUtils.payload_hash(entries),
		"checksum": "",
	}
	value["checksum"] = RepresentationUtils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = RepresentationUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return RepresentationUtils.failure("UNSUPPORTED_MATTER_SUMMARY_MANIFEST_SCHEMA")
	if not MatterUtils.is_canonical_id(value.get("manifest_id"), 2) \
		or not MatterUtils.is_canonical_id(value.get("body_id"), 2):
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_MANIFEST_ID")
	if typeof(value.get("region_root_address")) != TYPE_DICTIONARY \
		or not bool(CellAddress.validate(value["region_root_address"]).get("success", false)):
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_MANIFEST_REGION")
	for field in ["grid_profile_hash", "manifest_hash"]:
		if not RepresentationUtils.is_lower_hex_64(value.get(field)):
			return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_MANIFEST_HASH", {"field": field})
	for field in ["authority_epoch", "manifest_revision", "entry_count"]:
		if not RepresentationUtils.is_json_integer(value.get(field)):
			return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_MANIFEST_INTEGER", {"field": field})
	if int(value["authority_epoch"]) < 1 \
		or int(value["manifest_revision"]) < 1 or int(value["entry_count"]) < 1:
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_MANIFEST_FRONTIER")
	if typeof(value.get("source_revision")) != TYPE_DICTIONARY:
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_MANIFEST_SOURCE")
	checked = SourceRevision.validate(value["source_revision"])
	if not bool(checked.get("success", false)):
		return checked
	var source: Dictionary = value["source_revision"]
	if String(source["source_domain"]) != "MATTER" \
		or String(source["source_id"]) != String(value["body_id"]) \
		or int(source["authority_epoch"]) != int(value["authority_epoch"]):
		return RepresentationUtils.failure("MATTER_SUMMARY_MANIFEST_SOURCE_BINDING_MISMATCH")
	if typeof(value.get("entries")) != TYPE_ARRAY or value["entries"].size() != int(value["entry_count"]):
		return RepresentationUtils.failure("MATTER_SUMMARY_MANIFEST_ENTRY_COUNT_MISMATCH")
	var previous_cell_id: String = ""
	var root_cell_id: String = String(value["region_root_address"]["cell_id"])
	var root_found: bool = false
	for index in range(value["entries"].size()):
		var raw_entry = value["entries"][index]
		if typeof(raw_entry) != TYPE_DICTIONARY:
			return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_MANIFEST_ENTRY", {"index": index})
		var entry: Dictionary = raw_entry
		checked = RepresentationUtils.validate_exact_fields(entry, ENTRY_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		for field in ["summary_id", "cell_id", "scope_id", "storage_key"]:
			if not MatterUtils.is_canonical_id(entry.get(field), 2):
				return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_MANIFEST_ENTRY_ID", {"index": index, "field": field})
		if typeof(entry.get("cell_address")) != TYPE_DICTIONARY \
			or not bool(CellAddress.validate(entry["cell_address"]).get("success", false)):
			return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_MANIFEST_ENTRY_ADDRESS", {"index": index})
		var address: Dictionary = entry["cell_address"]
		var cell_id: String = String(entry["cell_id"])
		if cell_id != String(address["cell_id"]) \
			or int(entry["level"]) != int(address["level"]) \
			or String(entry["summary_id"]) != SummaryNode.summary_id_for(String(value["body_id"]), address) \
			or String(entry["scope_id"]) != SummaryNode.scope_id_for(String(value["body_id"]), address):
			return RepresentationUtils.failure("MATTER_SUMMARY_MANIFEST_ENTRY_BINDING_MISMATCH", {"index": index})
		if not _contains_or_same(value["region_root_address"], address):
			return RepresentationUtils.failure("MATTER_SUMMARY_MANIFEST_ENTRY_OUTSIDE_REGION", {"index": index})
		if index > 0 and cell_id <= previous_cell_id:
			return RepresentationUtils.failure("MATTER_SUMMARY_MANIFEST_ENTRIES_NOT_SORTED_UNIQUE", {"index": index})
		previous_cell_id = cell_id
		for field in ["level", "authority_epoch", "summary_revision", "build_generation"]:
			if not RepresentationUtils.is_json_integer(entry.get(field)):
				return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_MANIFEST_ENTRY_INTEGER", {"index": index, "field": field})
		if int(entry["level"]) < int(value["region_root_address"]["level"]) \
			or int(entry["authority_epoch"]) != int(value["authority_epoch"]) \
			or int(entry["summary_revision"]) < 0 \
			or int(entry["summary_revision"]) > int(source["source_revision"]) \
			or int(entry["build_generation"]) < 1:
			return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_MANIFEST_ENTRY_FRONTIER", {"index": index})
		for field in ["summary_hash", "dependency_hash", "descendant_revision_hash"]:
			if not RepresentationUtils.is_lower_hex_64(entry.get(field)):
				return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_MANIFEST_ENTRY_HASH", {"index": index, "field": field})
		if String(entry["storage_key"]) != "summary/%s" % String(entry["summary_hash"]):
			return RepresentationUtils.failure("MATTER_SUMMARY_MANIFEST_STORAGE_KEY_MISMATCH", {"index": index})
		if cell_id == root_cell_id:
			root_found = true
	if not root_found:
		return RepresentationUtils.failure("MATTER_SUMMARY_MANIFEST_ROOT_MISSING")
	if String(value["manifest_hash"]) != RepresentationUtils.payload_hash(value["entries"]):
		return RepresentationUtils.failure("MATTER_SUMMARY_MANIFEST_CONTENT_HASH_MISMATCH")
	return RepresentationUtils.validate_checksum(value)


static func _contains_or_same(ancestor: Dictionary, descendant: Dictionary) -> bool:
	if ancestor == descendant:
		return true
	return CellAddress.is_ancestor(ancestor, descendant)
