extends RefCounted
## Prepared exact-linear capsule session.
## Full provenance and execution-gate validation happens once at start().
## execute() uses only the reduced 4x4 relation plus cheap live-binding fences.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/exact_boundary_reduction_descriptor_v1.gd")
const Gate = preload("res://scripts/research/fabric_bake0/bake_execution_gate_v1.gd")

const SCHEMA := "planet_simulator.fabric_r5_2_exact_linear_capsule_session.v1"
const FIELDS: Array[String] = [
	"schema", "capsule_id", "capsule_checksum", "artifact_checksum", "descriptor_checksum",
	"source_frontier_hash", "authority_checksum", "dependency_hash", "fabric_graph_hash",
	"fabric_compiler_version", "boundary_contract_hash", "bake_policy_hash",
	"boundary_port_ids", "schur_matrix", "reduced_rhs", "checksum",
]

static func start(
	capsule: Dictionary,
	artifact: Dictionary,
	descriptor: Dictionary,
	live: Dictionary
) -> Dictionary:
	var checked := Capsule.validate(capsule)
	if not checked.success:
		return checked
	checked = Artifact.validate(artifact)
	if not checked.success:
		return checked
	checked = Descriptor.validate(descriptor)
	if not checked.success:
		return checked
	if String(capsule.physical_bake_artifact_checksum) != String(artifact.checksum):
		return U.failure("R5_2_SESSION_CAPSULE_ARTIFACT_MISMATCH")
	if String(capsule.executable_descriptor_hash) != String(descriptor.checksum):
		return U.failure("R5_2_SESSION_CAPSULE_DESCRIPTOR_MISMATCH")
	if String(capsule.executable_kind) != "EXACT_LINEAR_BOUNDARY" or String(capsule.reduction_class) != "EXACT":
		return U.failure("R5_2_SESSION_UNSUPPORTED_EXECUTABLE_KIND")
	if int(capsule.runtime_source_traversals_per_execute) != 0:
		return U.failure("R5_2_SESSION_SOURCE_TRAVERSAL_CONTRACT_INVALID")
	if not artifact.refinement_guards.is_empty():
		return U.failure("R5_2_SESSION_REFINEMENT_GUARDS_REQUIRE_GENERAL_RUNTIME")
	checked = Gate.can_execute(artifact, live)
	if not checked.success:
		return checked
	var session := {
		"schema": SCHEMA,
		"capsule_id": String(capsule.capsule_id),
		"capsule_checksum": String(capsule.checksum),
		"artifact_checksum": String(artifact.checksum),
		"descriptor_checksum": String(descriptor.checksum),
		"source_frontier_hash": String(artifact.source_binding.frontier_hash),
		"authority_checksum": String(artifact.source_binding.authority_envelope.checksum),
		"dependency_hash": String(artifact.source_binding.dependency_hash),
		"fabric_graph_hash": String(artifact.source_binding.fabric_graph_hash),
		"fabric_compiler_version": String(artifact.source_binding.fabric_compiler_version),
		"boundary_contract_hash": String(artifact.source_binding.boundary_contract_hash),
		"bake_policy_hash": String(artifact.source_binding.bake_policy_hash),
		"boundary_port_ids": descriptor.boundary_port_ids.duplicate(),
		"schur_matrix": descriptor.schur_matrix.duplicate(true),
		"reduced_rhs": descriptor.reduced_rhs.duplicate(),
		"checksum": "",
	}
	session.checksum = U.compute_checksum(session)
	checked = validate(session)
	if not checked.success:
		return checked
	return U.success({"session": session, "activation_gate": checked})

static func validate(session: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(session, FIELDS)
	if not checked.success:
		return checked
	if session.get("schema") != SCHEMA:
		return U.failure("UNSUPPORTED_R5_2_CAPSULE_SESSION_SCHEMA")
	if not U.is_canonical_id(session.get("capsule_id"), 2):
		return U.failure("INVALID_R5_2_CAPSULE_SESSION_ID")
	for field in [
		"capsule_checksum", "artifact_checksum", "descriptor_checksum",
		"source_frontier_hash", "authority_checksum", "dependency_hash",
		"fabric_graph_hash", "boundary_contract_hash", "bake_policy_hash"
	]:
		if not U.is_lower_hex_64(session.get(field)):
			return U.failure("INVALID_R5_2_CAPSULE_SESSION_HASH", {"field": field})
	if typeof(session.get("fabric_compiler_version")) != TYPE_STRING or String(session.fabric_compiler_version).is_empty():
		return U.failure("INVALID_R5_2_CAPSULE_SESSION_COMPILER")
	if typeof(session.get("boundary_port_ids")) != TYPE_ARRAY or session.boundary_port_ids.is_empty():
		return U.failure("INVALID_R5_2_CAPSULE_SESSION_PORTS")
	var n := session.boundary_port_ids.size()
	if typeof(session.get("schur_matrix")) != TYPE_ARRAY or session.schur_matrix.size() != n:
		return U.failure("INVALID_R5_2_CAPSULE_SESSION_MATRIX")
	for row in session.schur_matrix:
		if typeof(row) != TYPE_ARRAY or row.size() != n:
			return U.failure("INVALID_R5_2_CAPSULE_SESSION_MATRIX")
		for value in row:
			if not U.is_finite_number(value):
				return U.failure("INVALID_R5_2_CAPSULE_SESSION_MATRIX")
	if typeof(session.get("reduced_rhs")) != TYPE_ARRAY or session.reduced_rhs.size() != n:
		return U.failure("INVALID_R5_2_CAPSULE_SESSION_RHS")
	for value in session.reduced_rhs:
		if not U.is_finite_number(value):
			return U.failure("INVALID_R5_2_CAPSULE_SESSION_RHS")
	return U.validate_checksum(session)

static func execute(session: Dictionary, live: Dictionary, boundary_effort: Array) -> Dictionary:
	var checked := validate(session)
	if not checked.success:
		return checked
	checked = _fast_live_fence(session, live)
	if not checked.success:
		return checked
	var n := session.boundary_port_ids.size()
	if boundary_effort.size() != n:
		return U.failure("R5_2_SESSION_BOUNDARY_EFFORT_SIZE_MISMATCH")
	var flow: Array = []
	flow.resize(n)
	for row_index in range(n):
		var value := -float(session.reduced_rhs[row_index])
		for column_index in range(n):
			if not U.is_finite_number(boundary_effort[column_index]):
				return U.failure("R5_2_SESSION_NONFINITE_BOUNDARY_EFFORT")
			value += float(session.schur_matrix[row_index][column_index]) * float(boundary_effort[column_index])
		flow[row_index] = value
	var power := 0.0
	for index in range(n):
		power += float(boundary_effort[index]) * float(flow[index])
	return U.success({
		"capsule_id": session.capsule_id,
		"boundary_effort": boundary_effort.duplicate(),
		"boundary_flow": flow,
		"boundary_power": power,
		"runtime_source_component_traversals": 0,
		"executable_equation_count": n,
		"fast_binding_checks": 10,
	})

static func _fast_live_fence(session: Dictionary, live: Dictionary) -> Dictionary:
	if String(live.get("artifact_state", "")) != "READY":
		return U.failure("R5_2_SESSION_PHYSICAL_BAKE_NOT_READY")
	if typeof(live.get("invalidations")) != TYPE_ARRAY or not live.invalidations.is_empty():
		return U.failure("R5_2_SESSION_INVALIDATION_REQUIRES_REACTIVATION")
	if typeof(live.get("canonical_source_frontier")) != TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash", "")) != String(session.source_frontier_hash):
		return U.failure("R5_2_SESSION_SOURCE_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope")) != TYPE_DICTIONARY or String(live.authority_envelope.get("checksum", "")) != String(session.authority_checksum):
		return U.failure("R5_2_SESSION_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set")) != TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash", "")) != String(session.dependency_hash):
		return U.failure("R5_2_SESSION_DEPENDENCY_MISMATCH")
	if String(live.get("fabric_graph_hash", "")) != String(session.fabric_graph_hash):
		return U.failure("R5_2_SESSION_GRAPH_MISMATCH")
	if String(live.get("fabric_compiler_version", "")) != String(session.fabric_compiler_version):
		return U.failure("R5_2_SESSION_COMPILER_MISMATCH")
	if String(live.get("boundary_contract_hash", "")) != String(session.boundary_contract_hash):
		return U.failure("R5_2_SESSION_BOUNDARY_MISMATCH")
	if String(live.get("bake_policy_hash", "")) != String(session.bake_policy_hash):
		return U.failure("R5_2_SESSION_POLICY_MISMATCH")
	if typeof(live.get("runtime_domain")) != TYPE_DICTIONARY:
		return U.failure("R5_2_SESSION_RUNTIME_DOMAIN_MISSING")
	if String(live.runtime_domain.get("source_frontier_hash", "")) != String(session.source_frontier_hash) or String(live.runtime_domain.get("fabric_graph_hash", "")) != String(session.fabric_graph_hash):
		return U.failure("R5_2_SESSION_RUNTIME_DOMAIN_MISMATCH")
	if String(live.runtime_domain.get("mode", "")) != "STEADY":
		return U.failure("R5_2_SESSION_RUNTIME_MODE_MISMATCH")
	if typeof(live.get("runtime_error_estimator")) != TYPE_DICTIONARY or not live.runtime_error_estimator.is_empty():
		return U.failure("R5_2_SESSION_RUNTIME_ESTIMATOR_REQUIRES_GENERAL_GATE")
	if typeof(live.get("guard_values")) != TYPE_DICTIONARY or not live.guard_values.is_empty():
		return U.failure("R5_2_SESSION_GUARDS_REQUIRE_GENERAL_GATE")
	return U.success()
