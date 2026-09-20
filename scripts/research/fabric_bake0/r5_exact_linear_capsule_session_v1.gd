extends RefCounted
## Prepared exact-linear capsule execution object.
## Full provenance/gate validation is activation work, not per-tick work.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/exact_boundary_reduction_descriptor_v1.gd")
const Gate = preload("res://scripts/research/fabric_bake0/bake_execution_gate_v1.gd")

var _ready := false
var _capsule_id := ""
var _activation_hash := ""
var _source_frontier_hash := ""
var _authority_checksum := ""
var _dependency_hash := ""
var _fabric_graph_hash := ""
var _fabric_compiler_version := ""
var _boundary_contract_hash := ""
var _bake_policy_hash := ""
var _boundary_port_ids: Array = []
var _schur_matrix: Array = []
var _reduced_rhs: Array = []

func prepare(capsule: Dictionary, artifact: Dictionary, descriptor: Dictionary, live: Dictionary) -> Dictionary:
	_ready = false
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

	_capsule_id = String(capsule.capsule_id)
	_source_frontier_hash = String(artifact.source_binding.frontier_hash)
	_authority_checksum = String(artifact.source_binding.authority_envelope.checksum)
	_dependency_hash = String(artifact.source_binding.dependency_hash)
	_fabric_graph_hash = String(artifact.source_binding.fabric_graph_hash)
	_fabric_compiler_version = String(artifact.source_binding.fabric_compiler_version)
	_boundary_contract_hash = String(artifact.source_binding.boundary_contract_hash)
	_bake_policy_hash = String(artifact.source_binding.bake_policy_hash)
	_boundary_port_ids = descriptor.boundary_port_ids.duplicate()
	_schur_matrix = descriptor.schur_matrix.duplicate(true)
	_reduced_rhs = descriptor.reduced_rhs.duplicate()
	_activation_hash = U.canonical_hash({
		"capsule_checksum": capsule.checksum,
		"artifact_checksum": artifact.checksum,
		"descriptor_checksum": descriptor.checksum,
		"source_frontier_hash": _source_frontier_hash,
		"authority_checksum": _authority_checksum,
		"dependency_hash": _dependency_hash,
		"fabric_graph_hash": _fabric_graph_hash,
		"boundary_contract_hash": _boundary_contract_hash,
		"bake_policy_hash": _bake_policy_hash,
		"boundary_port_ids": _boundary_port_ids,
		"schur_matrix": _schur_matrix,
		"reduced_rhs": _reduced_rhs,
	})
	_ready = true
	return U.success({
		"activation_hash": _activation_hash,
		"capsule_id": _capsule_id,
		"executable_equation_count": _boundary_port_ids.size(),
	})

func execute(live: Dictionary, boundary_effort: Array) -> Dictionary:
	if not _ready:
		return U.failure("R5_2_SESSION_NOT_READY")
	var checked := _fast_live_fence(live)
	if not checked.success:
		return checked
	var n := _boundary_port_ids.size()
	if boundary_effort.size() != n:
		return U.failure("R5_2_SESSION_BOUNDARY_EFFORT_SIZE_MISMATCH")
	var flow: Array = []
	flow.resize(n)
	for row_index in range(n):
		var value := -float(_reduced_rhs[row_index])
		for column_index in range(n):
			if not U.is_finite_number(boundary_effort[column_index]):
				return U.failure("R5_2_SESSION_NONFINITE_BOUNDARY_EFFORT")
			value += float(_schur_matrix[row_index][column_index]) * float(boundary_effort[column_index])
		flow[row_index] = value
	var power := 0.0
	for index in range(n):
		power += float(boundary_effort[index]) * float(flow[index])
	return U.success({
		"capsule_id": _capsule_id,
		"activation_hash": _activation_hash,
		"boundary_effort": boundary_effort.duplicate(),
		"boundary_flow": flow,
		"boundary_power": power,
		"runtime_source_component_traversals": 0,
		"executable_equation_count": n,
		"fast_binding_checks": 10,
	})

func invalidate() -> void:
	_ready = false

func _fast_live_fence(live: Dictionary) -> Dictionary:
	if String(live.get("artifact_state", "")) != "READY":
		return U.failure("R5_2_SESSION_PHYSICAL_BAKE_NOT_READY")
	if typeof(live.get("invalidations")) != TYPE_ARRAY or not live.invalidations.is_empty():
		return U.failure("R5_2_SESSION_INVALIDATION_REQUIRES_REACTIVATION")
	if typeof(live.get("canonical_source_frontier")) != TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash", "")) != _source_frontier_hash:
		return U.failure("R5_2_SESSION_SOURCE_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope")) != TYPE_DICTIONARY or String(live.authority_envelope.get("checksum", "")) != _authority_checksum:
		return U.failure("R5_2_SESSION_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set")) != TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash", "")) != _dependency_hash:
		return U.failure("R5_2_SESSION_DEPENDENCY_MISMATCH")
	if String(live.get("fabric_graph_hash", "")) != _fabric_graph_hash:
		return U.failure("R5_2_SESSION_GRAPH_MISMATCH")
	if String(live.get("fabric_compiler_version", "")) != _fabric_compiler_version:
		return U.failure("R5_2_SESSION_COMPILER_MISMATCH")
	if String(live.get("boundary_contract_hash", "")) != _boundary_contract_hash:
		return U.failure("R5_2_SESSION_BOUNDARY_MISMATCH")
	if String(live.get("bake_policy_hash", "")) != _bake_policy_hash:
		return U.failure("R5_2_SESSION_POLICY_MISMATCH")
	if typeof(live.get("runtime_domain")) != TYPE_DICTIONARY:
		return U.failure("R5_2_SESSION_RUNTIME_DOMAIN_MISSING")
	if String(live.runtime_domain.get("source_frontier_hash", "")) != _source_frontier_hash or String(live.runtime_domain.get("fabric_graph_hash", "")) != _fabric_graph_hash:
		return U.failure("R5_2_SESSION_RUNTIME_DOMAIN_MISMATCH")
	if String(live.runtime_domain.get("mode", "")) != "STEADY":
		return U.failure("R5_2_SESSION_RUNTIME_MODE_MISMATCH")
	if typeof(live.get("runtime_error_estimator")) != TYPE_DICTIONARY or not live.runtime_error_estimator.is_empty():
		return U.failure("R5_2_SESSION_RUNTIME_ESTIMATOR_REQUIRES_GENERAL_GATE")
	if typeof(live.get("guard_values")) != TYPE_DICTIONARY or not live.guard_values.is_empty():
		return U.failure("R5_2_SESSION_GUARDS_REQUIRE_GENERAL_GATE")
	return U.success()
