extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Dependencies = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/logic_interface_contract_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/logic_lookup_descriptor_v1.gd")

const SCHEMA := "planet_simulator.fabric_logic_execution_artifact.v1"
const KIND := "LOGIC_LOOKUP"
const FIELDS: Array[String] = [
	"schema", "artifact_id", "artifact_kind", "canonical_source_frontier",
	"authority_envelope", "dependency_set", "graph_hash", "interface_contract",
	"descriptor_checksum", "state_schema_hash", "build_generation",
	"derived_only", "artifact_hash", "checksum",
]

static func create(
	artifact_id: String,
	canonical_source_frontier: Dictionary,
	authority_envelope: Dictionary,
	dependency_set: Dictionary,
	graph_hash: String,
	interface_contract: Dictionary,
	descriptor: Dictionary,
	build_generation: int
) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"artifact_id": artifact_id,
		"artifact_kind": KIND,
		"canonical_source_frontier": canonical_source_frontier.duplicate(true),
		"authority_envelope": authority_envelope.duplicate(true),
		"dependency_set": dependency_set.duplicate(true),
		"graph_hash": graph_hash,
		"interface_contract": interface_contract.duplicate(true),
		"descriptor_checksum": String(descriptor.checksum),
		"state_schema_hash": U.canonical_hash(interface_contract.state_signals),
		"build_generation": build_generation,
		"derived_only": true,
		"artifact_hash": "",
		"checksum": "",
	}
	value.artifact_hash = U.canonical_hash(_identity_payload(value))
	value.checksum = U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA or value.get("artifact_kind") != KIND:
		return U.failure("UNSUPPORTED_LOGIC_EXECUTION_ARTIFACT")
	if not U.is_canonical_id(value.get("artifact_id"), 2):
		return U.failure("INVALID_LOGIC_ARTIFACT_ID")
	if typeof(value.get("canonical_source_frontier")) != TYPE_DICTIONARY:
		return U.failure("INVALID_LOGIC_ARTIFACT_FRONTIER")
	checked = Frontier.validate(value.canonical_source_frontier)
	if not checked.success:
		return checked
	if typeof(value.get("authority_envelope")) != TYPE_DICTIONARY:
		return U.failure("INVALID_LOGIC_ARTIFACT_AUTHORITY")
	checked = Authority.validate_b0_safety(value.authority_envelope)
	if not checked.success:
		return checked
	if typeof(value.get("dependency_set")) != TYPE_DICTIONARY:
		return U.failure("INVALID_LOGIC_ARTIFACT_DEPENDENCIES")
	checked = Dependencies.validate(value.dependency_set)
	if not checked.success:
		return checked
	if not U.is_lower_hex_64(value.get("graph_hash")):
		return U.failure("INVALID_LOGIC_ARTIFACT_GRAPH_HASH")
	var canonical_bound := false
	for source in value.canonical_source_frontier.sources:
		if String(source.source_domain) == "CONSTRUCTION" and String(source.source_hash) == String(value.graph_hash):
			canonical_bound = true
			break
	if not canonical_bound:
		return U.failure("LOGIC_ARTIFACT_CANONICAL_GRAPH_SOURCE_MISMATCH")
	if typeof(value.get("interface_contract")) != TYPE_DICTIONARY:
		return U.failure("INVALID_LOGIC_ARTIFACT_INTERFACE")
	checked = Interface.validate(value.interface_contract)
	if not checked.success:
		return checked
	for field in ["descriptor_checksum", "state_schema_hash", "artifact_hash"]:
		if not U.is_lower_hex_64(value.get(field)):
			return U.failure("INVALID_LOGIC_ARTIFACT_HASH", {"field": field})
	if String(value.state_schema_hash) != U.canonical_hash(value.interface_contract.state_signals):
		return U.failure("LOGIC_ARTIFACT_STATE_SCHEMA_MISMATCH")
	if not U.is_json_integer(value.get("build_generation")) or int(value.build_generation) < 1:
		return U.failure("INVALID_LOGIC_ARTIFACT_BUILD_GENERATION")
	if value.get("derived_only") != true:
		return U.failure("LOGIC_ARTIFACT_MUST_BE_DERIVED")
	if String(value.artifact_hash) != U.canonical_hash(_identity_payload(value)):
		return U.failure("LOGIC_ARTIFACT_HASH_MISMATCH")
	return U.validate_checksum(value)

static func verify_descriptor(value: Dictionary, descriptor: Dictionary) -> Dictionary:
	var checked := validate(value)
	if not checked.success:
		return checked
	checked = Descriptor.validate(descriptor)
	if not checked.success:
		return checked
	if String(value.descriptor_checksum) != String(descriptor.checksum):
		return U.failure("LOGIC_ARTIFACT_DESCRIPTOR_MISMATCH")
	if String(value.graph_hash) != String(descriptor.graph_hash):
		return U.failure("LOGIC_ARTIFACT_DESCRIPTOR_GRAPH_MISMATCH")
	if String(value.interface_contract.interface_hash) != String(descriptor.interface_contract.interface_hash):
		return U.failure("LOGIC_ARTIFACT_DESCRIPTOR_INTERFACE_MISMATCH")
	return U.success()

static func _identity_payload(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("artifact_hash")
	payload.erase("checksum")
	return payload
