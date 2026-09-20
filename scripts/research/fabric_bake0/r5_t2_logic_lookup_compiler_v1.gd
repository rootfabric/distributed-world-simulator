extends RefCounted
## Generic logic graph -> exhaustive lookup compiler.
## It knows only Boolean primitives/register semantics, never Adder/Counter names.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Interpreter = preload("res://scripts/research/fabric_bake0/logic_graph_interpreter_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/logic_lookup_descriptor_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/logic_execution_artifact_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")

const VERSION := "FABRIC_R5_2_T2_LOGIC_LOOKUP_COMPILER_R1"
const MAX_ADDRESS_BITS := 17
const COMPILED_OPERATION_COUNT := 3

static func compile(graph: Dictionary, request: Dictionary, capsule_id: String) -> Dictionary:
	var planned := Interpreter.prepare(graph)
	if not planned.success:
		return planned
	var plan: Dictionary = planned.details
	var interface: Dictionary = plan.interface
	var address_bits: int = interface.input_signals.size() + interface.state_signals.size()
	if address_bits > MAX_ADDRESS_BITS:
		return U.failure("LOGIC_STATE_SPACE_TOO_LARGE", {"address_bits": address_bits, "maximum": MAX_ADDRESS_BITS})
	if typeof(request.get("canonical_source_frontier")) != TYPE_DICTIONARY:
		return U.failure("LOGIC_CANONICAL_FRONTIER_REQUIRED")
	var bound := false
	for source in request.canonical_source_frontier.get("sources", []):
		if String(source.get("source_domain", "")) == "CONSTRUCTION" and String(source.get("source_hash", "")) == String(graph.graph_hash):
			bound = true
			break
	if not bound:
		return U.failure("LOGIC_CANONICAL_GRAPH_SOURCE_MISMATCH")
	var input_bits: int = interface.input_signals.size()
	var output_bits: int = interface.output_signals.size()
	var state_bits: int = interface.state_signals.size()
	var input_mask: int = (1 << input_bits) - 1
	var entries: int = 1 << address_bits
	var table: Array = []
	table.resize(entries)
	for address in range(entries):
		var input_word: int = address & input_mask
		var state_word: int = address >> input_bits
		var evaluated := Interpreter.evaluate(plan, input_word, state_word)
		if not evaluated.success:
			return evaluated
		table[address] = int(evaluated.details.output_word) | (int(evaluated.details.next_state_word) << output_bits)
	var descriptor := Descriptor.create(
		String(graph.graph_hash),
		interface,
		int(plan.initial_state_word),
		int(plan.source_operation_count),
		COMPILED_OPERATION_COUNT,
		table
	)
	if descriptor.is_empty():
		return U.failure("LOGIC_LOOKUP_DESCRIPTOR_CREATE_FAILED")
	var artifact := Artifact.create(
		String(request.get("artifact_id", "")),
		request.canonical_source_frontier,
		request.authority_envelope,
		request.dependency_set,
		String(graph.graph_hash),
		interface,
		descriptor,
		int(request.get("build_generation", 1))
	)
	if artifact.is_empty():
		return U.failure("LOGIC_EXECUTION_ARTIFACT_CREATE_FAILED")
	var provenance := U.canonical_hash({
		"compiler_version": VERSION,
		"graph_hash": graph.graph_hash,
		"interface_hash": interface.interface_hash,
		"descriptor_hash": descriptor.descriptor_hash,
		"artifact_hash": artifact.artifact_hash,
	})
	var capsule := Capsule.create(
		capsule_id,
		"LOGIC_LOOKUP",
		"EXACT_DISCRETE",
		String(artifact.canonical_source_frontier.frontier_hash),
		String(graph.graph_hash),
		String(interface.interface_hash),
		"LOGIC_LOOKUP",
		String(artifact.checksum),
		String(descriptor.checksum),
		String(artifact.state_schema_hash),
		int(graph.components.size()),
		int(plan.source_operation_count),
		COMPILED_OPERATION_COUNT,
		0,
		int(artifact.build_generation),
		["DISCRETE", "EXACT_LOGIC", "LOOKUP", "SYNCHRONOUS"],
		provenance
	)
	if capsule.is_empty():
		return U.failure("LOGIC_BEHAVIOR_CAPSULE_CREATE_FAILED")
	return U.success({
		"plan": plan,
		"descriptor": descriptor,
		"artifact": artifact,
		"capsule": capsule,
		"compile_stats": {
			"address_bits": address_bits,
			"entries": entries,
			"source_operations": int(plan.source_operation_count),
			"compiled_operations": COMPILED_OPERATION_COUNT,
			"lookup_bytes_estimate": entries * 4,
		},
	})
