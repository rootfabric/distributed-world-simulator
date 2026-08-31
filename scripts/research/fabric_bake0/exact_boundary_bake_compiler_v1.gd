extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const BoundaryContract = preload("res://scripts/research/fabric_bake0/physical_boundary_contract_v1.gd")
const DependencySet = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const ValidatedDomain = preload("res://scripts/research/fabric_bake0/validated_domain_v1.gd")
const ErrorEnvelope = preload("res://scripts/research/fabric_bake0/error_envelope_v1.gd")
const ConservationEnvelope = preload("res://scripts/research/fabric_bake0/conservation_envelope_v1.gd")
const ReconstructionDescriptor = preload("res://scripts/research/fabric_bake0/reconstruction_descriptor_v1.gd")
const StateMapping = preload("res://scripts/research/fabric_bake0/bake_state_mapping_v1.gd")
const CompileResult = preload("res://scripts/research/fabric_bake0/bake_compile_result_v1.gd")
const FoundationCompiler = preload("res://scripts/research/fabric_bake0/fabric_bake_foundation_compiler_v1.gd")
const LinearSystem = preload("res://scripts/research/fabric_bake0/linear_boundary_system_v1.gd")
const Reducer = preload("res://scripts/research/fabric_bake0/exact_boundary_reducer_v1.gd")

const MIN_BOUNDARY_PORTS := 2
const MAX_BOUNDARY_PORTS := 8
const MIN_INTERNAL_VARIABLES := 100
const POWER_DIMENSION: Array[int] = [1, 2, -3, 0, 0, 0, 0]
const REDUCER_DEPENDENCY_ID := "dependency/fabric-bake-exact-boundary-reducer"
const REDUCER_VERSION := "FABRIC_BAKE_B0_1_EXACT_SCHUR_R1"

const REQUEST_FIELDS: Array[String] = [
	"artifact_id", "canonical_source_frontier", "authority_envelope", "dependency_set",
	"fabric_graph_hash", "fabric_compiler_version", "boundary_contract", "bake_policy_hash",
	"validated_domain", "error_envelope", "conservation_envelope", "build_generation",
	"linear_system", "pivot_relative_tolerance", "symmetry_tolerance", "passivity_tolerance",
	"require_symmetric", "require_passive_laplacian",
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
		[LinearSystem, "linear_system"],
	]:
		if typeof(request.get(pair[1])) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_B0_1_COMPILE_REQUEST_CONTRACT", {"field": pair[1]})
		checked = pair[0].validate(request[pair[1]])
		if not bool(checked.get("success", false)):
			return checked

	for field in ["pivot_relative_tolerance", "symmetry_tolerance", "passivity_tolerance"]:
		if not Utils.is_positive_number(request.get(field)):
			return Utils.failure("INVALID_B0_1_COMPILE_POLICY_NUMBER", {"field": field})
	for field in ["require_symmetric", "require_passive_laplacian"]:
		if typeof(request.get(field)) != TYPE_BOOL:
			return Utils.failure("INVALID_B0_1_COMPILE_POLICY_FLAG", {"field": field})
	if not Utils.is_json_integer(request.get("build_generation")) or int(request["build_generation"]) < 1:
		return Utils.failure("INVALID_B0_1_BUILD_GENERATION")
	if not Utils.is_lower_hex_64(request.get("fabric_graph_hash")) or not Utils.is_lower_hex_64(request.get("bake_policy_hash")):
		return Utils.failure("INVALID_B0_1_BINDING_HASH")
	if typeof(request.get("fabric_compiler_version")) != TYPE_STRING or String(request["fabric_compiler_version"]).strip_edges().is_empty():
		return Utils.failure("INVALID_B0_1_FABRIC_COMPILER_VERSION")

	var system: Dictionary = request["linear_system"]
	var boundary_count: int = int(system["boundary_port_ids"].size())
	var internal_count: int = int(system["internal_variable_ids"].size())
	if boundary_count < MIN_BOUNDARY_PORTS or boundary_count > MAX_BOUNDARY_PORTS:
		return CompileResult.no_safe("UNSAFE_ELIMINATION", {
			"stage": "B0.1", "reason_detail": "BOUNDARY_PORT_COUNT_OUT_OF_SCOPE",
			"boundary_count": boundary_count,
		})
	if internal_count < MIN_INTERNAL_VARIABLES:
		return CompileResult.no_safe("INSUFFICIENT_COMPLEXITY_REDUCTION", {
			"stage": "B0.1", "reason_detail": "INTERNAL_BLOCK_BELOW_ACCEPTANCE_SCOPE",
			"internal_count": internal_count,
		})

	var contract_port_ids: Array = []
	for port in request["boundary_contract"]["ports"]:
		contract_port_ids.append(String(port["port_id"]))
	if contract_port_ids != system["boundary_port_ids"]:
		return Utils.failure("B0_1_BOUNDARY_PORT_BINDING_MISMATCH")
	checked = _validate_power_dimensions(request["boundary_contract"])
	if not bool(checked.get("success", false)):
		return checked

	checked = AuthorityEnvelope.validate_b0_safety(request["authority_envelope"])
	if not bool(checked.get("success", false)):
		var authority_reason := String(checked.get("error_code", ""))
		if CompileResult.NO_SAFE_REASONS.has(authority_reason):
			return CompileResult.no_safe(authority_reason, checked.get("details", {}))
		return checked

	var policy := {
		"pivot_relative_tolerance": float(request["pivot_relative_tolerance"]),
		"symmetry_tolerance": float(request["symmetry_tolerance"]),
		"passivity_tolerance": float(request["passivity_tolerance"]),
		"require_symmetric": bool(request["require_symmetric"]),
		"require_passive_laplacian": bool(request["require_passive_laplacian"]),
	}
	var reduced := Reducer.reduce(system, policy)
	if not bool(reduced.get("success", false)):
		return reduced
	if String(reduced.get("status", "")) == Reducer.NO_SAFE_BAKE:
		var reduction_reason := String(reduced.get("reason", ""))
		if CompileResult.NO_SAFE_REASONS.has(reduction_reason):
			return CompileResult.no_safe(reduction_reason, reduced.get("diagnostics", {}))
		return Utils.failure("INVALID_B0_1_REDUCTION_REASON")
	if String(reduced.get("status", "")) != Reducer.REDUCED:
		return Utils.failure("INVALID_B0_1_REDUCTION_STATUS")
	var reduction: Dictionary = reduced["descriptor"]

	var effective_dependencies := _with_reducer_dependency(request["dependency_set"])
	if effective_dependencies.is_empty():
		return Utils.failure("B0_1_REDUCER_DEPENDENCY_ASSEMBLY_FAILED")

	var source_keys := Frontier.source_keys(request["canonical_source_frontier"])
	var reconstruction := ReconstructionDescriptor.create(
		"reconstruction/b0-1-exact-boundary",
		String(request["canonical_source_frontier"]["frontier_hash"]),
		String(reduction["reconstruction_recipe_hash"]),
		"CANONICAL_PLUS_REDUCED",
		[{"region_id": "region/b0-1-exact-boundary", "source_keys": source_keys}],
		"STRICT",
		Utils.canonical_hash({
			"boundary_events": _boundary_event_frontier(request["boundary_contract"]),
			"source_system_hash": system["system_hash"],
		}),
		"b0.1-exact-schur-r1"
	)
	if reconstruction.is_empty():
		return CompileResult.no_safe("RECONSTRUCTION_UNAVAILABLE")

	var reduced_state_schema_hash := Utils.canonical_hash({
		"kind": "STATELESS_LINEAR_BOUNDARY_RELATION",
		"boundary_port_ids": system["boundary_port_ids"],
	})
	var full_state_schema_hash := Utils.canonical_hash({
		"kind": "LINEAR_ACAUSAL_BOUNDARY_SYSTEM",
		"boundary_port_ids": system["boundary_port_ids"],
		"internal_variable_ids": system["internal_variable_ids"],
	})
	var state_mapping := StateMapping.create(
		"mapping/b0-1-exact-boundary",
		full_state_schema_hash,
		reduced_state_schema_hash,
		Utils.canonical_hash({
			"kind": "BOUNDARY_PORT_PROJECTION",
			"boundary_port_ids": system["boundary_port_ids"],
		}),
		String(reconstruction["checksum"])
	)
	if state_mapping.is_empty():
		return CompileResult.no_safe("RECONSTRUCTION_UNAVAILABLE")

	var effective_policy_hash := Utils.canonical_hash({
		"base_bake_policy_hash": request["bake_policy_hash"],
		"algorithm": "EXACT_SCHUR_DETERMINISTIC_LU_V1",
		"pivot_relative_tolerance": policy["pivot_relative_tolerance"],
		"symmetry_tolerance": policy["symmetry_tolerance"],
		"passivity_tolerance": policy["passivity_tolerance"],
		"require_symmetric": policy["require_symmetric"],
		"require_passive_laplacian": policy["require_passive_laplacian"],
	})

	var foundation_request := {
		"artifact_id": request["artifact_id"],
		"reduction_class": "EXACT",
		"canonical_source_frontier": request["canonical_source_frontier"],
		"authority_envelope": request["authority_envelope"],
		"dependency_set": effective_dependencies,
		"fabric_graph_hash": request["fabric_graph_hash"],
		"fabric_compiler_version": request["fabric_compiler_version"],
		"boundary_contract": request["boundary_contract"],
		"bake_policy_hash": effective_policy_hash,
		"reduced_model_descriptor_hash": String(reduction["checksum"]),
		"reduced_state_schema_hash": reduced_state_schema_hash,
		"validated_domain": request["validated_domain"],
		"error_envelope": request["error_envelope"],
		"conservation_envelope": request["conservation_envelope"],
		"refinement_guards": [],
		"reconstruction_descriptor": reconstruction,
		"state_mapping": state_mapping,
		"build_generation": int(request["build_generation"]),
		"error_certified": true,
		"refinement_guard_certified": true,
		"complexity_reduction_certified": float(reduction["runtime_work_ratio"]) > 1.0,
	}
	var compiled := FoundationCompiler.compile(foundation_request)
	if not bool(compiled.get("success", true)) and not compiled.has("status"):
		return compiled
	if String(compiled.get("status", "")) != CompileResult.BAKE_READY:
		return compiled
	return CompileResult.ready(compiled["artifact"], {
		"stage": "B0.1",
		"algorithm": "EXACT_SCHUR_DETERMINISTIC_LU_V1",
		"base_bake_policy_hash": request["bake_policy_hash"],
		"effective_bake_policy_hash": effective_policy_hash,
		"base_dependency_hash": request["dependency_set"]["dependency_hash"],
		"effective_dependency_hash": effective_dependencies["dependency_hash"],
		"boundary_power_dimension": POWER_DIMENSION,
		"reduction": reduction,
	})

static func _with_reducer_dependency(dependency_set: Dictionary) -> Dictionary:
	for dependency in dependency_set["dependencies"]:
		if String(dependency["dependency_id"]) == REDUCER_DEPENDENCY_ID:
			return {}
	var dependencies: Array = dependency_set["dependencies"].duplicate(true)
	dependencies.append({
		"dependency_id": REDUCER_DEPENDENCY_ID,
		"dependency_hash": Utils.canonical_hash({
			"version": REDUCER_VERSION,
			"algorithm": "EXACT_SCHUR_DETERMINISTIC_LU_V1",
		}),
	})
	return DependencySet.create(dependencies)

static func _validate_power_dimensions(boundary_contract: Dictionary) -> Dictionary:
	for port in boundary_contract["ports"]:
		var power_dimension: Array = []
		for index in range(POWER_DIMENSION.size()):
			power_dimension.append(int(port["effort_dimension"][index]) + int(port["flow_dimension"][index]))
		if power_dimension != POWER_DIMENSION:
			return Utils.failure("B0_1_NON_POWER_CONJUGATE_BOUNDARY_DIMENSIONS", {"port_id": port["port_id"]})
	return Utils.success()

static func _boundary_event_frontier(boundary_contract: Dictionary) -> Array:
	var events: Array = []
	for port in boundary_contract["ports"]:
		for event_id in port["event_observables"]:
			var key := "%s|%s" % [String(port["port_id"]), String(event_id)]
			if not events.has(key):
				events.append(key)
	events.sort()
	return events
