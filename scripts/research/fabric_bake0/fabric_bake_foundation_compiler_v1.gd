extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const BoundaryContract = preload("res://scripts/research/fabric_bake0/physical_boundary_contract_v1.gd")
const DependencySet = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const ValidatedDomain = preload("res://scripts/research/fabric_bake0/validated_domain_v1.gd")
const ErrorEnvelope = preload("res://scripts/research/fabric_bake0/error_envelope_v1.gd")
const ConservationEnvelope = preload("res://scripts/research/fabric_bake0/conservation_envelope_v1.gd")
const RefinementGuard = preload("res://scripts/research/fabric_bake0/refinement_guard_v1.gd")
const ReconstructionDescriptor = preload("res://scripts/research/fabric_bake0/reconstruction_descriptor_v1.gd")
const StateMapping = preload("res://scripts/research/fabric_bake0/bake_state_mapping_v1.gd")
const SourceBinding = preload("res://scripts/research/fabric_bake0/bake_source_binding_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")
const CompileResult = preload("res://scripts/research/fabric_bake0/bake_compile_result_v1.gd")

const REQUEST_FIELDS: Array[String] = [
	"artifact_id", "reduction_class", "canonical_source_frontier", "authority_envelope",
	"dependency_set", "fabric_graph_hash", "fabric_compiler_version", "boundary_contract",
	"bake_policy_hash", "reduced_model_descriptor_hash", "reduced_state_schema_hash",
	"validated_domain", "error_envelope", "conservation_envelope", "refinement_guards",
	"reconstruction_descriptor", "state_mapping", "build_generation",
	"error_certified", "refinement_guard_certified", "complexity_reduction_certified",
]

static func compile(request: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(request, REQUEST_FIELDS)
	if not bool(checked.get("success", false)):
		return checked

	for pair in [
		[Frontier, "canonical_source_frontier"],
		[AuthorityEnvelope, "authority_envelope"],
		[DependencySet, "dependency_set"],
		[BoundaryContract, "boundary_contract"],
		[ValidatedDomain, "validated_domain"],
		[ErrorEnvelope, "error_envelope"],
		[ConservationEnvelope, "conservation_envelope"],
		[ReconstructionDescriptor, "reconstruction_descriptor"],
		[StateMapping, "state_mapping"],
	]:
		if typeof(request.get(pair[1])) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_BAKE_COMPILE_REQUEST_CONTRACT", {"field": pair[1]})
		checked = pair[0].validate(request[pair[1]])
		if not bool(checked.get("success", false)):
			return checked

	if typeof(request.get("refinement_guards")) != TYPE_ARRAY:
		return Utils.failure("INVALID_BAKE_COMPILE_REQUEST_GUARDS")
	for guard in request["refinement_guards"]:
		if typeof(guard) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_BAKE_COMPILE_REQUEST_GUARD")
		checked = RefinementGuard.validate(guard)
		if not bool(checked.get("success", false)):
			return checked

	for field in ["error_certified", "refinement_guard_certified", "complexity_reduction_certified"]:
		if typeof(request.get(field)) != TYPE_BOOL:
			return Utils.failure("INVALID_BAKE_COMPILE_CERTIFICATION_FLAG", {"field": field})

	checked = AuthorityEnvelope.validate_b0_safety(request["authority_envelope"])
	if not bool(checked.get("success", false)):
		var reason := String(checked.get("error_code", ""))
		if CompileResult.NO_SAFE_REASONS.has(reason):
			return CompileResult.no_safe(reason, checked.get("details", {}))
		return checked

	if not bool(request["error_certified"]):
		return CompileResult.no_safe("UNCERTIFIABLE_ERROR_ENVELOPE")
	if String(request["reduction_class"]) == "APPROXIMATE" and not bool(request["refinement_guard_certified"]):
		return CompileResult.no_safe("UNCERTIFIABLE_REFINEMENT_GUARD")
	if not bool(request["complexity_reduction_certified"]):
		return CompileResult.no_safe("INSUFFICIENT_COMPLEXITY_REDUCTION")
	if request["reconstruction_descriptor"].is_empty():
		return CompileResult.no_safe("RECONSTRUCTION_UNAVAILABLE")

	var source_binding := SourceBinding.create(
		request["canonical_source_frontier"],
		request["authority_envelope"],
		request["dependency_set"],
		String(request["fabric_graph_hash"]),
		String(request["fabric_compiler_version"]),
		String(request["boundary_contract"]["contract_hash"]),
		String(request["bake_policy_hash"])
	)
	if source_binding.is_empty():
		return Utils.failure("INVALID_BAKE_SOURCE_BINDING_ASSEMBLY")

	var artifact := Artifact.create(
		String(request["artifact_id"]),
		String(request["reduction_class"]),
		source_binding,
		request["boundary_contract"],
		String(request["reduced_model_descriptor_hash"]),
		String(request["reduced_state_schema_hash"]),
		request["validated_domain"],
		request["error_envelope"],
		request["conservation_envelope"],
		request["refinement_guards"],
		request["reconstruction_descriptor"],
		request["state_mapping"],
		int(request["build_generation"])
	)
	if artifact.is_empty():
		return Utils.failure("INVALID_PHYSICAL_BAKE_ARTIFACT_ASSEMBLY")

	return CompileResult.ready(artifact, {
		"foundation": "B0.0",
		"source_count": request["canonical_source_frontier"]["sources"].size(),
		"guard_count": request["refinement_guards"].size(),
	})
