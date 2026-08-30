extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const SourceBinding = preload("res://scripts/research/fabric_bake0/bake_source_binding_v1.gd")
const BoundaryContract = preload("res://scripts/research/fabric_bake0/physical_boundary_contract_v1.gd")
const ValidatedDomain = preload("res://scripts/research/fabric_bake0/validated_domain_v1.gd")
const ErrorEnvelope = preload("res://scripts/research/fabric_bake0/error_envelope_v1.gd")
const ConservationEnvelope = preload("res://scripts/research/fabric_bake0/conservation_envelope_v1.gd")
const RefinementGuard = preload("res://scripts/research/fabric_bake0/refinement_guard_v1.gd")
const ReconstructionDescriptor = preload("res://scripts/research/fabric_bake0/reconstruction_descriptor_v1.gd")
const StateMapping = preload("res://scripts/research/fabric_bake0/bake_state_mapping_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_physical_artifact.v1"
const FIELDS: Array[String] = [
	"schema", "artifact_id", "reduction_class", "source_binding", "boundary_contract",
	"reduced_model_descriptor_hash", "reduced_state_schema_hash", "validated_domain",
	"error_envelope", "conservation_envelope", "refinement_guards",
	"reconstruction_descriptor", "state_mapping", "build_generation", "checksum",
]
const REDUCTION_CLASSES: Array[String] = ["APPROXIMATE", "EXACT"]

static func create(
	artifact_id: String, reduction_class: String, source_binding: Dictionary,
	boundary_contract: Dictionary, reduced_model_descriptor_hash: String,
	reduced_state_schema_hash: String, validated_domain: Dictionary,
	error_envelope: Dictionary, conservation_envelope: Dictionary,
	refinement_guards: Array, reconstruction_descriptor: Dictionary,
	state_mapping: Dictionary, build_generation: int
) -> Dictionary:
	var guards := Utils.sorted_dicts(refinement_guards, "guard_id")
	var value: Dictionary = {
		"schema": SCHEMA,
		"artifact_id": artifact_id,
		"reduction_class": reduction_class,
		"source_binding": source_binding.duplicate(true),
		"boundary_contract": boundary_contract.duplicate(true),
		"reduced_model_descriptor_hash": reduced_model_descriptor_hash,
		"reduced_state_schema_hash": reduced_state_schema_hash,
		"validated_domain": validated_domain.duplicate(true),
		"error_envelope": error_envelope.duplicate(true),
		"conservation_envelope": conservation_envelope.duplicate(true),
		"refinement_guards": guards,
		"reconstruction_descriptor": reconstruction_descriptor.duplicate(true),
		"state_mapping": state_mapping.duplicate(true),
		"build_generation": build_generation,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_PHYSICAL_BAKE_ARTIFACT_SCHEMA")
	if not Utils.is_canonical_id(value.get("artifact_id"), 2):
		return Utils.failure("INVALID_PHYSICAL_BAKE_ARTIFACT_ID")
	if not REDUCTION_CLASSES.has(String(value.get("reduction_class", ""))):
		return Utils.failure("INVALID_BAKE_REDUCTION_CLASS")
	if typeof(value.get("source_binding")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_BAKE_SOURCE_BINDING")
	checked = SourceBinding.validate(value["source_binding"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("boundary_contract")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_BAKE_BOUNDARY_CONTRACT")
	checked = BoundaryContract.validate(value["boundary_contract"])
	if not bool(checked.get("success", false)):
		return checked
	if String(value["source_binding"]["boundary_contract_hash"]) != String(value["boundary_contract"]["contract_hash"]):
		return Utils.failure("BAKE_BOUNDARY_BINDING_MISMATCH")
	for field in ["reduced_model_descriptor_hash", "reduced_state_schema_hash"]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_PHYSICAL_BAKE_ARTIFACT_HASH", {"field": field})
	if typeof(value.get("validated_domain")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_BAKE_VALIDATED_DOMAIN")
	checked = ValidatedDomain.validate(value["validated_domain"])
	if not bool(checked.get("success", false)):
		return checked
	if String(value["validated_domain"]["exact_frontier_hash"]) != String(value["source_binding"]["frontier_hash"]):
		return Utils.failure("BAKE_VALIDATED_DOMAIN_FRONTIER_MISMATCH")
	if String(value["validated_domain"]["exact_fabric_graph_hash"]) != String(value["source_binding"]["fabric_graph_hash"]):
		return Utils.failure("BAKE_VALIDATED_DOMAIN_GRAPH_MISMATCH")
	if typeof(value.get("error_envelope")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_BAKE_ERROR_ENVELOPE")
	checked = ErrorEnvelope.validate(value["error_envelope"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("conservation_envelope")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_BAKE_CONSERVATION_ENVELOPE")
	checked = ConservationEnvelope.validate(value["conservation_envelope"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("refinement_guards")) != TYPE_ARRAY:
		return Utils.failure("INVALID_BAKE_REFINEMENT_GUARDS")
	var previous := ""
	for index in range(value["refinement_guards"].size()):
		var raw = value["refinement_guards"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_BAKE_REFINEMENT_GUARD", {"index": index})
		var guard: Dictionary = raw
		checked = RefinementGuard.validate(guard)
		if not bool(checked.get("success", false)):
			return checked
		var current := String(guard["guard_id"])
		if index > 0 and current <= previous:
			return Utils.failure("BAKE_REFINEMENT_GUARDS_NOT_SORTED_UNIQUE", {"index": index})
		previous = current
	if String(value["reduction_class"]) == "APPROXIMATE" and value["refinement_guards"].is_empty():
		return Utils.failure("APPROXIMATE_BAKE_REQUIRES_REFINEMENT_GUARD")
	if typeof(value.get("reconstruction_descriptor")) != TYPE_DICTIONARY or value["reconstruction_descriptor"].is_empty():
		return Utils.failure("INVALID_BAKE_RECONSTRUCTION_DESCRIPTOR")
	checked = ReconstructionDescriptor.validate(value["reconstruction_descriptor"])
	if not bool(checked.get("success", false)):
		return checked
	if String(value["reconstruction_descriptor"]["source_frontier_hash"]) != String(value["source_binding"]["frontier_hash"]):
		return Utils.failure("BAKE_RECONSTRUCTION_FRONTIER_MISMATCH")
	var source_keys := Frontier.source_keys(value["source_binding"]["canonical_source_frontier"])
	checked = ReconstructionDescriptor.validate_source_coverage(value["reconstruction_descriptor"], source_keys)
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("state_mapping")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_BAKE_STATE_MAPPING")
	checked = StateMapping.validate(value["state_mapping"])
	if not bool(checked.get("success", false)):
		return checked
	if String(value["state_mapping"]["reduced_state_schema_hash"]) != String(value["reduced_state_schema_hash"]):
		return Utils.failure("BAKE_REDUCED_STATE_SCHEMA_MISMATCH")
	if String(value["state_mapping"]["reconstruction_descriptor_hash"]) != String(value["reconstruction_descriptor"]["checksum"]):
		return Utils.failure("BAKE_RECONSTRUCTION_MAPPING_MISMATCH")
	if not Utils.is_json_integer(value.get("build_generation")) or int(value["build_generation"]) < 1:
		return Utils.failure("INVALID_BAKE_BUILD_GENERATION")
	return Utils.validate_checksum(value)
