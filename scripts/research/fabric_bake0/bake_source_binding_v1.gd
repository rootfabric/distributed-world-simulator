extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const DependencySet = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_source_binding.v1"
const FIELDS: Array[String] = [
	"schema", "canonical_source_frontier", "frontier_hash", "authority_envelope",
	"dependency_set", "dependency_hash", "fabric_graph_hash", "fabric_compiler_version",
	"boundary_contract_hash", "bake_policy_hash", "checksum",
]

static func create(
	canonical_source_frontier: Dictionary, authority_envelope: Dictionary,
	dependency_set: Dictionary, fabric_graph_hash: String,
	fabric_compiler_version: String, boundary_contract_hash: String,
	bake_policy_hash: String
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"canonical_source_frontier": canonical_source_frontier.duplicate(true),
		"frontier_hash": String(canonical_source_frontier.get("frontier_hash", "")),
		"authority_envelope": authority_envelope.duplicate(true),
		"dependency_set": dependency_set.duplicate(true),
		"dependency_hash": String(dependency_set.get("dependency_hash", "")),
		"fabric_graph_hash": fabric_graph_hash,
		"fabric_compiler_version": fabric_compiler_version,
		"boundary_contract_hash": boundary_contract_hash,
		"bake_policy_hash": bake_policy_hash,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_BAKE_SOURCE_BINDING_SCHEMA")
	if typeof(value.get("canonical_source_frontier")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_BAKE_SOURCE_FRONTIER")
	checked = Frontier.validate(value["canonical_source_frontier"])
	if not bool(checked.get("success", false)):
		return checked
	if String(value.get("frontier_hash", "")) != String(value["canonical_source_frontier"]["frontier_hash"]):
		return Utils.failure("BAKE_FRONTIER_HASH_MISMATCH")
	if typeof(value.get("authority_envelope")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_BAKE_AUTHORITY_ENVELOPE")
	checked = AuthorityEnvelope.validate(value["authority_envelope"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("dependency_set")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_BAKE_DEPENDENCY_SET")
	checked = DependencySet.validate(value["dependency_set"])
	if not bool(checked.get("success", false)):
		return checked
	if String(value.get("dependency_hash", "")) != String(value["dependency_set"]["dependency_hash"]):
		return Utils.failure("BAKE_DEPENDENCY_HASH_MISMATCH")
	for field in ["fabric_graph_hash", "boundary_contract_hash", "bake_policy_hash"]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_BAKE_SOURCE_BINDING_HASH", {"field": field})
	if typeof(value.get("fabric_compiler_version")) != TYPE_STRING or String(value["fabric_compiler_version"]).strip_edges().is_empty():
		return Utils.failure("INVALID_FABRIC_COMPILER_VERSION")
	var frontier_sources: Dictionary = {}
	for source in value["canonical_source_frontier"]["sources"]:
		var key := Utils.source_key(String(source["source_domain"]), String(source["source_id"]))
		frontier_sources[key] = int(source["authority_epoch"])
	var authority_sources: Dictionary = {}
	for record in value["authority_envelope"]["source_authority_frontier"]:
		var key := Utils.source_key(String(record["source_domain"]), String(record["source_id"]))
		authority_sources[key] = int(record["authority_epoch"])
	if frontier_sources != authority_sources:
		return Utils.failure("BAKE_AUTHORITY_FRONTIER_SOURCE_MISMATCH")
	return Utils.validate_checksum(value)
