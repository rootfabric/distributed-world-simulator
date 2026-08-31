extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const ExecutionGate = preload("res://scripts/research/fabric_bake0/bake_execution_gate_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/exact_boundary_reduction_descriptor_v1.gd")
const Reducer = preload("res://scripts/research/fabric_bake0/exact_boundary_reducer_v1.gd")

static func execute(
	artifact: Dictionary, reduction_descriptor: Dictionary,
	live_context: Dictionary, boundary_effort: Array
) -> Dictionary:
	var checked := Descriptor.validate(reduction_descriptor)
	if not bool(checked.get("success", false)):
		return checked
	if String(artifact.get("reduced_model_descriptor_hash", "")) != String(reduction_descriptor["checksum"]):
		return Utils.failure("B0_1_REDUCTION_DESCRIPTOR_BINDING_MISMATCH")
	if typeof(artifact.get("boundary_contract")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_B0_1_ARTIFACT_BOUNDARY")
	var artifact_port_ids: Array = []
	for port in artifact["boundary_contract"].get("ports", []):
		artifact_port_ids.append(String(port.get("port_id", "")))
	if artifact_port_ids != reduction_descriptor["boundary_port_ids"]:
		return Utils.failure("B0_1_RUNTIME_BOUNDARY_BINDING_MISMATCH")
	var gate := ExecutionGate.can_execute(artifact, live_context)
	if not bool(gate.get("success", false)):
		return gate
	var evaluated := Reducer.evaluate_reduced(reduction_descriptor, boundary_effort)
	if not bool(evaluated.get("success", false)):
		return evaluated
	return Utils.success({
		"artifact_id": artifact["artifact_id"],
		"boundary_effort": evaluated["details"]["boundary_effort"],
		"boundary_flow": evaluated["details"]["boundary_flow"],
		"boundary_power": evaluated["details"]["boundary_power"],
		"execution_gate": gate["details"],
	})
