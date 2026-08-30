extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const DependencySet = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const RuntimeErrorEstimator = preload("res://scripts/research/fabric_bake0/runtime_error_estimator_v1.gd")
const RefinementGuard = preload("res://scripts/research/fabric_bake0/refinement_guard_v1.gd")
const ValidatedDomain = preload("res://scripts/research/fabric_bake0/validated_domain_v1.gd")
const BakeInvalidation = preload("res://scripts/research/fabric_bake0/bake_invalidation_v1.gd")

const LIVE_FIELDS: Array[String] = [
	"artifact_state", "canonical_source_frontier", "authority_envelope", "dependency_set",
	"fabric_graph_hash", "fabric_compiler_version", "boundary_contract_hash",
	"bake_policy_hash", "runtime_domain", "runtime_error_estimator",
	"guard_values", "invalidations",
]

static func can_execute(artifact: Dictionary, live: Dictionary) -> Dictionary:
	var checked := Artifact.validate(artifact)
	if not bool(checked.get("success", false)):
		return checked
	checked = Utils.validate_exact_fields(live, LIVE_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if typeof(live.get("artifact_state")) != TYPE_STRING:
		return Utils.failure("INVALID_PHYSICAL_BAKE_STATE")
	if String(live["artifact_state"]) == "STALE":
		return Utils.failure("STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN")
	if String(live["artifact_state"]) != "READY":
		return Utils.failure("PHYSICAL_BAKE_NOT_READY")

	if typeof(live.get("invalidations")) != TYPE_ARRAY:
		return Utils.failure("INVALID_BAKE_INVALIDATION_SET")
	for invalidation in live["invalidations"]:
		if typeof(invalidation) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_BAKE_INVALIDATION_SET")
		checked = BakeInvalidation.validate(invalidation)
		if not bool(checked.get("success", false)):
			return checked
		if String(invalidation["artifact_id"]) == String(artifact["artifact_id"]):
			return Utils.failure("STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN", {
				"reason": invalidation["reason"],
				"invalidation_id": invalidation["invalidation_id"],
			})

	if typeof(live.get("canonical_source_frontier")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_LIVE_CANONICAL_SOURCE_FRONTIER")
	checked = Frontier.validate(live["canonical_source_frontier"])
	if not bool(checked.get("success", false)):
		return checked
	if String(live["canonical_source_frontier"]["frontier_hash"]) != String(artifact["source_binding"]["frontier_hash"]):
		return Utils.failure("BAKE_SOURCE_FRONTIER_MISMATCH")

	if typeof(live.get("authority_envelope")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_LIVE_AUTHORITY_ENVELOPE")
	checked = AuthorityEnvelope.validate_b0_safety(live["authority_envelope"])
	if not bool(checked.get("success", false)):
		return checked
	if String(live["authority_envelope"]["checksum"]) != String(artifact["source_binding"]["authority_envelope"]["checksum"]):
		return Utils.failure("BAKE_AUTHORITY_BINDING_MISMATCH")

	if typeof(live.get("dependency_set")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_LIVE_BAKE_DEPENDENCY_SET")
	checked = DependencySet.validate(live["dependency_set"])
	if not bool(checked.get("success", false)):
		return checked
	if String(live["dependency_set"]["dependency_hash"]) != String(artifact["source_binding"]["dependency_hash"]):
		return Utils.failure("BAKE_DEPENDENCY_MISMATCH")

	if String(live.get("fabric_graph_hash", "")) != String(artifact["source_binding"]["fabric_graph_hash"]):
		return Utils.failure("BAKE_FABRIC_GRAPH_MISMATCH")
	if String(live.get("fabric_compiler_version", "")) != String(artifact["source_binding"]["fabric_compiler_version"]):
		return Utils.failure("BAKE_FABRIC_COMPILER_MISMATCH")
	if String(live.get("boundary_contract_hash", "")) != String(artifact["source_binding"]["boundary_contract_hash"]):
		return Utils.failure("BAKE_BOUNDARY_CONTRACT_MISMATCH")
	if String(live.get("bake_policy_hash", "")) != String(artifact["source_binding"]["bake_policy_hash"]):
		return Utils.failure("BAKE_POLICY_MISMATCH")

	if typeof(live.get("runtime_domain")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_BAKE_RUNTIME_DOMAIN")
	checked = ValidatedDomain.contains(artifact["validated_domain"], live["runtime_domain"])
	if not bool(checked.get("success", false)):
		return checked

	if typeof(live.get("runtime_error_estimator")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_BAKE_RUNTIME_ERROR_ESTIMATOR")
	if String(artifact["reduction_class"]) == "APPROXIMATE":
		if live["runtime_error_estimator"].is_empty():
			return Utils.failure("APPROXIMATE_BAKE_RUNTIME_ESTIMATOR_REQUIRED")
		checked = RuntimeErrorEstimator.validate_against(live["runtime_error_estimator"], artifact["error_envelope"])
		if not bool(checked.get("success", false)):
			return checked
	elif not live["runtime_error_estimator"].is_empty():
		checked = RuntimeErrorEstimator.validate_against(live["runtime_error_estimator"], artifact["error_envelope"])
		if not bool(checked.get("success", false)):
			return checked

	if typeof(live.get("guard_values")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_BAKE_GUARD_VALUES")
	var minimum_guard_margin := INF
	for guard in artifact["refinement_guards"]:
		checked = RefinementGuard.evaluate(guard, live["guard_values"])
		if not bool(checked.get("success", false)):
			return checked
		minimum_guard_margin = minf(minimum_guard_margin, float(checked["details"]["remaining_guard_margin"]))

	return Utils.success({
		"artifact_id": artifact["artifact_id"],
		"minimum_guard_margin": minimum_guard_margin if minimum_guard_margin < INF else 0.0,
		"minimum_safe_fidelity": String(artifact["reduction_class"]),
	})
