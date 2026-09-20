extends RefCounted
## R5.2 T1 compiler: component graph -> exact physical bake -> generic behavior capsule.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const GraphCompiler = preload("res://scripts/research/fabric_bake0/linear_conductance_graph_compiler_v1.gd")
const ExactCompiler = preload("res://scripts/research/fabric_bake0/exact_boundary_bake_compiler_v1.gd")
const CompileResult = preload("res://scripts/research/fabric_bake0/bake_compile_result_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/exact_boundary_reduction_descriptor_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v1.gd")

const VERSION := "FABRIC_R5_2_T1_BOUNDARY_NETWORK_CAPSULE_COMPILER_R1"

static func compile(graph: Dictionary, bake_request: Dictionary, capsule_id: String) -> Dictionary:
	var graph_compiled := GraphCompiler.compile(graph)
	if not graph_compiled.success:
		return graph_compiled
	if typeof(bake_request.get("canonical_source_frontier")) != TYPE_DICTIONARY:
		return U.failure("R5_2_T1_CANONICAL_FRONTIER_REQUIRED")
	var canonical_graph_bound := false
	for source in bake_request.canonical_source_frontier.get("sources", []):
		if String(source.get("source_domain", "")) == "CONSTRUCTION" and String(source.get("source_hash", "")) == String(graph.graph_hash):
			canonical_graph_bound = true
			break
	if not canonical_graph_bound:
		return U.failure("R5_2_T1_CANONICAL_GRAPH_SOURCE_MISMATCH", {
			"graph_hash": graph.graph_hash,
			"frontier_hash": bake_request.canonical_source_frontier.get("frontier_hash", ""),
		})
	var request: Dictionary = bake_request.duplicate(true)
	request.linear_system = graph_compiled.details.linear_system
	request.fabric_graph_hash = String(graph.graph_hash)
	var exact := ExactCompiler.compile(request)
	if not exact.get("success", true) and not exact.has("status"):
		return exact
	if String(exact.get("status", "")) != CompileResult.BAKE_READY:
		return exact
	var artifact: Dictionary = exact.artifact
	var descriptor: Dictionary = exact.diagnostics.reduction
	if not Artifact.validate(artifact).success or not Descriptor.validate(descriptor).success:
		return U.failure("R5_2_T1_COMPILED_CONTRACT_INVALID")
	if String(artifact.source_binding.fabric_graph_hash) != String(graph.graph_hash):
		return U.failure("R5_2_T1_GRAPH_BINDING_MISMATCH")
	var provenance := U.canonical_hash({
		"compiler_version": VERSION,
		"graph_compiler_version": graph_compiled.details.compiler_version,
		"graph_hash": graph.graph_hash,
		"artifact_checksum": artifact.checksum,
		"descriptor_checksum": descriptor.checksum,
		"boundary_contract_hash": artifact.boundary_contract.contract_hash,
	})
	var capsule := Capsule.create(
		capsule_id,
		"EXACT_LINEAR_BOUNDARY",
		"EXACT",
		String(artifact.checksum),
		String(artifact.source_binding.checksum),
		String(artifact.source_binding.frontier_hash),
		String(artifact.source_binding.fabric_graph_hash),
		String(artifact.boundary_contract.contract_hash),
		String(descriptor.checksum),
		String(artifact.reduced_state_schema_hash),
		int(graph.components.size()),
		int(descriptor.full_equation_count),
		int(descriptor.reduced_equation_count),
		0,
		int(artifact.build_generation),
		["ELECTRICAL", "EXACT_BOUNDARY", "STATELESS"],
		provenance
	)
	if capsule.is_empty():
		return U.failure("R5_2_T1_CAPSULE_ASSEMBLY_FAILED")
	return U.success({
		"capsule": capsule,
		"artifact": artifact,
		"reduction": descriptor,
		"linear_system": graph_compiled.details.linear_system,
		"graph_compile": graph_compiled.details,
		"bake_request": request,
	})
