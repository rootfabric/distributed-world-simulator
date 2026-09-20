extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/logic_component_graph_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Dependencies = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")

const WIDTH := 8
const COMPILER_VERSION := "FABRIC_R5_2_T2_LOGIC_LOOKUP_COMPILER_R1"

static func gate(component_id: String, kind: String, inputs: Array, output: String) -> Dictionary:
	return {
		"component_id": component_id,
		"kind": kind,
		"inputs": inputs,
		"output": output,
		"initial_value": false,
	}

static func register(component_id: String, input_signal: String, output: String, initial_value: bool = false) -> Dictionary:
	return {
		"component_id": component_id,
		"kind": "REGISTER",
		"inputs": [input_signal],
		"output": output,
		"initial_value": initial_value,
	}

static func make_adder_graph(mutation_revision: int = 0, reverse_input: bool = false) -> Dictionary:
	var inputs: Array = []
	for i in range(WIDTH):
		inputs.append("signal/a-%d" % i)
	for i in range(WIDTH):
		inputs.append("signal/b-%d" % i)
	inputs.append("signal/cin")
	var outputs: Array = []
	for i in range(WIDTH):
		outputs.append("signal/sum-%d" % i)
	outputs.append("signal/cout")
	var components: Array = []
	var carry := "signal/cin"
	for i in range(WIDTH):
		var xab := "signal/xab-%d" % i
		var aandb := "signal/aandb-%d" % i
		var candx := "signal/candx-%d" % i
		var carry_out := "signal/cout" if i == WIDTH - 1 else "signal/carry-%d" % (i + 1)
		var xor_kind := "OR" if mutation_revision > 0 and i == 0 else "XOR"
		components.append(gate("component/adder-xab-%02d" % i, xor_kind, ["signal/a-%d" % i, "signal/b-%d" % i], xab))
		components.append(gate("component/adder-sum-%02d" % i, "XOR", [xab, carry], "signal/sum-%d" % i))
		components.append(gate("component/adder-ab-%02d" % i, "AND", ["signal/a-%d" % i, "signal/b-%d" % i], aandb))
		components.append(gate("component/adder-cx-%02d" % i, "AND", [carry, xab], candx))
		components.append(gate("component/adder-carry-%02d" % i, "OR", [aandb, candx], carry_out))
		carry = carry_out
	if reverse_input:
		inputs.reverse()
		outputs.reverse()
		components.reverse()
	return Graph.create("graph/r5-t2-adder-8bit", inputs, outputs, components)

static func make_counter_graph(mutation_revision: int = 0, reverse_input: bool = false) -> Dictionary:
	var inputs: Array = ["signal/enable", "signal/reset"]
	var outputs: Array = []
	var components: Array = []
	for i in range(WIDTH):
		outputs.append("signal/q-%d" % i)
	components.append(gate("component/counter-not-reset", "NOT", ["signal/reset"], "signal/not-reset"))
	var carry := "signal/enable"
	for i in range(WIDTH):
		var inc := "signal/inc-%d" % i
		var d := "signal/d-%d" % i
		var xor_kind := "OR" if mutation_revision > 0 and i == 0 else "XOR"
		components.append(gate("component/counter-inc-%02d" % i, xor_kind, ["signal/q-%d" % i, carry], inc))
		if i < WIDTH - 1:
			var next_carry := "signal/carry-%d" % (i + 1)
			components.append(gate("component/counter-carry-%02d" % i, "AND", ["signal/q-%d" % i, carry], next_carry))
			carry = next_carry
		components.append(gate("component/counter-d-%02d" % i, "AND", [inc, "signal/not-reset"], d))
		components.append(register("component/counter-register-%02d" % i, d, "signal/q-%d" % i, false))
	if reverse_input:
		inputs.reverse()
		outputs.reverse()
		components.reverse()
	return Graph.create("graph/r5-t2-counter-8bit", inputs, outputs, components)

static func make_cycle_graph() -> Dictionary:
	return Graph.create(
		"graph/r5-t2-cycle",
		["signal/input"],
		["signal/a"],
		[
			gate("component/cycle-a", "BUF", ["signal/b"], "signal/a"),
			gate("component/cycle-b", "BUF", ["signal/a"], "signal/b"),
		]
	)

static func make_oversize_graph() -> Dictionary:
	var inputs: Array = []
	for i in range(18):
		inputs.append("signal/input-%02d" % i)
	return Graph.create(
		"graph/r5-t2-oversize",
		inputs,
		["signal/output"],
		[gate("component/oversize-buffer", "BUF", ["signal/input-00"], "signal/output")]
	)

static func build_request(graph: Dictionary, source_id: String, revision: int = 0) -> Dictionary:
	var dependency_hash := U.canonical_hash({"dependency": "r5-t2-logic"})
	var construction := SourceRevision.create(
		"CONSTRUCTION", source_id, 12, 200 + revision,
		String(graph.graph_hash), dependency_hash
	)
	var frontier := Frontier.create([construction])
	var source_key := U.source_key("CONSTRUCTION", source_id)
	var authority := Authority.create(
		"server/fabric-r5",
		[{"source_domain": "CONSTRUCTION", "source_id": source_id, "authority_epoch": 12, "owner_id": "server/fabric-r5"}],
		[source_key]
	)
	var dependencies := Dependencies.create([
		{"dependency_id": "dependency/r5-t2-logic-compiler", "dependency_hash": U.canonical_hash({"version": COMPILER_VERSION})},
		{"dependency_id": "dependency/r5-t2-logic-primitives", "dependency_hash": U.canonical_hash({"kinds": Graph.KINDS})},
	])
	return {
		"artifact_id": "artifact/%s" % source_id.get_slice("/", 1),
		"canonical_source_frontier": frontier,
		"authority_envelope": authority,
		"dependency_set": dependencies,
		"build_generation": 1 + revision,
	}

static func live_from(artifact: Dictionary) -> Dictionary:
	return {
		"artifact_state": "READY",
		"invalidations": [],
		"canonical_source_frontier": artifact.canonical_source_frontier.duplicate(true),
		"authority_envelope": artifact.authority_envelope.duplicate(true),
		"dependency_set": artifact.dependency_set.duplicate(true),
		"graph_hash": String(artifact.graph_hash),
		"interface_hash": String(artifact.interface_contract.interface_hash),
	}

static func pack_values(signal_order: Array, values: Dictionary) -> int:
	var word := 0
	for index in range(signal_order.size()):
		if bool(values.get(signal_order[index], false)):
			word |= 1 << index
	return word

static func adder_input_word(interface: Dictionary, a: int, b: int, carry_in: int) -> int:
	var values := {}
	for i in range(WIDTH):
		values["signal/a-%d" % i] = bool((a >> i) & 1)
		values["signal/b-%d" % i] = bool((b >> i) & 1)
	values["signal/cin"] = carry_in != 0
	return pack_values(interface.input_signals, values)

static func adder_expected_output_word(interface: Dictionary, a: int, b: int, carry_in: int) -> int:
	var total := a + b + carry_in
	var values := {"signal/cout": bool((total >> WIDTH) & 1)}
	for i in range(WIDTH):
		values["signal/sum-%d" % i] = bool((total >> i) & 1)
	return pack_values(interface.output_signals, values)

static func counter_input_word(interface: Dictionary, enable: bool, reset: bool) -> int:
	return pack_values(interface.input_signals, {"signal/enable": enable, "signal/reset": reset})

static func counter_expected_output_word(interface: Dictionary, state_word: int) -> int:
	var values := {}
	for i in range(WIDTH):
		values["signal/q-%d" % i] = bool((state_word >> i) & 1)
	return pack_values(interface.output_signals, values)

static func counter_expected_next_state(state_word: int, enable: bool, reset: bool) -> int:
	if reset:
		return 0
	if enable:
		return (state_word + 1) & 0xff
	return state_word
