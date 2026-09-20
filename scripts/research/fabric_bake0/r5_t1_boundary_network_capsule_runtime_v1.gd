extends RefCounted
## T1 reduction-specific runtime adapter. It receives no source component graph.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/exact_boundary_reduction_descriptor_v1.gd")
const ExactRuntime = preload("res://scripts/research/fabric_bake0/exact_boundary_runtime_v1.gd")

static func execute(
	capsule: Dictionary,
	artifact: Dictionary,
	descriptor: Dictionary,
	live_context: Dictionary,
	boundary_effort: Array
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
		return U.failure("R5_2_T1_CAPSULE_ARTIFACT_BINDING_MISMATCH")
	if String(capsule.source_binding_checksum) != String(artifact.source_binding.checksum):
		return U.failure("R5_2_T1_CAPSULE_SOURCE_BINDING_MISMATCH")
	if String(capsule.source_frontier_hash) != String(artifact.source_binding.frontier_hash):
		return U.failure("R5_2_T1_CAPSULE_FRONTIER_MISMATCH")
	if String(capsule.fabric_graph_hash) != String(artifact.source_binding.fabric_graph_hash):
		return U.failure("R5_2_T1_CAPSULE_GRAPH_MISMATCH")
	if String(capsule.boundary_contract_hash) != String(artifact.boundary_contract.contract_hash):
		return U.failure("R5_2_T1_CAPSULE_BOUNDARY_MISMATCH")
	if String(capsule.executable_descriptor_hash) != String(descriptor.checksum):
		return U.failure("R5_2_T1_CAPSULE_DESCRIPTOR_MISMATCH")
	if int(capsule.runtime_source_traversals_per_execute) != 0:
		return U.failure("R5_2_T1_RUNTIME_SOURCE_TRAVERSAL_CONTRACT_INVALID")
	var executed := ExactRuntime.execute(artifact, descriptor, live_context, boundary_effort)
	if not executed.success:
		return executed
	return U.success({
		"capsule_id": capsule.capsule_id,
		"boundary_effort": executed.details.boundary_effort,
		"boundary_flow": executed.details.boundary_flow,
		"boundary_power": executed.details.boundary_power,
		"runtime_source_component_traversals": 0,
		"executable_equation_count": int(capsule.executable_equation_count),
		"execution_gate": executed.details.execution_gate,
	})
