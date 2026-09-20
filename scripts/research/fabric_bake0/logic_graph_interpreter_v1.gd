extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/logic_component_graph_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/logic_interface_contract_v1.gd")

static func prepare(graph: Dictionary) -> Dictionary:
	var checked := Graph.validate(graph)
	if not checked.success:
		return checked
	var registers: Array = []
	var gates: Array = []
	var gate_by_output := {}
	for component in graph.components:
		if String(component.kind) == "REGISTER":
			registers.append(component.duplicate(true))
		else:
			gates.append(component.duplicate(true))
			gate_by_output[String(component.output)] = component
	registers.sort_custom(func(a, b): return String(a.output) < String(b.output))
	var state_signals: Array = []
	for register in registers:
		state_signals.append(String(register.output))
	var interface := Interface.create(graph.input_signals, graph.output_signals, state_signals)
	if interface.is_empty():
		return U.failure("LOGIC_INTERFACE_CREATE_FAILED")
	var source_signals := {}
	for signal_id in graph.input_signals:
		source_signals[signal_id] = true
	for signal_id in state_signals:
		source_signals[signal_id] = true
	var dependencies := {}
	var dependents := {}
	for gate in gates:
		var gate_id := String(gate.component_id)
		dependencies[gate_id] = {}
		dependents[gate_id] = []
	for gate in gates:
		var gate_id := String(gate.component_id)
		for input_id in gate.inputs:
			if source_signals.has(input_id):
				continue
			if not gate_by_output.has(String(input_id)):
				return U.failure("LOGIC_GATE_DEPENDENCY_NOT_COMBINATIONAL", {"gate": gate_id, "signal": input_id})
			var upstream: Dictionary = gate_by_output[String(input_id)]
			dependencies[gate_id][String(upstream.component_id)] = true
			dependents[String(upstream.component_id)].append(gate_id)
	var ready: Array = []
	for gate in gates:
		if dependencies[String(gate.component_id)].is_empty():
			ready.append(String(gate.component_id))
	ready.sort()
	var gate_by_id := {}
	for gate in gates:
		gate_by_id[String(gate.component_id)] = gate
	var order: Array = []
	while not ready.is_empty():
		var current := String(ready.pop_front())
		order.append(gate_by_id[current].duplicate(true))
		var next_ids: Array = dependents[current].duplicate()
		next_ids.sort()
		for next_id in next_ids:
			dependencies[next_id].erase(current)
			if dependencies[next_id].is_empty() and not _array_has_component_id(order, next_id) and not ready.has(next_id):
				ready.append(next_id)
				ready.sort()
	if order.size() != gates.size():
		return U.failure("LOGIC_COMBINATIONAL_CYCLE")
	var initial_state_word := 0
	for index in range(registers.size()):
		if bool(registers[index].initial_value):
			initial_state_word |= 1 << index
	return U.success({
		"graph_hash": graph.graph_hash,
		"interface": interface,
		"gate_order": order,
		"registers": registers,
		"initial_state_word": initial_state_word,
		"source_operation_count": graph.components.size(),
		"gate_count": gates.size(),
		"register_count": registers.size(),
	})

static func evaluate(plan: Dictionary, input_word: int, state_word: int) -> Dictionary:
	var interface: Dictionary = plan.interface
	var input_count := interface.input_signals.size()
	var state_count := interface.state_signals.size()
	if input_word < 0 or input_word >= (1 << input_count):
		return U.failure("LOGIC_INPUT_WORD_OUT_OF_RANGE")
	if state_count == 0:
		if state_word != 0:
			return U.failure("LOGIC_STATE_WORD_OUT_OF_RANGE")
	elif state_word < 0 or state_word >= (1 << state_count):
		return U.failure("LOGIC_STATE_WORD_OUT_OF_RANGE")
	var values := {}
	for index in range(input_count):
		values[interface.input_signals[index]] = bool((input_word >> index) & 1)
	for index in range(state_count):
		values[interface.state_signals[index]] = bool((state_word >> index) & 1)
	var traversed := 0
	for gate in plan.gate_order:
		var kind := String(gate.kind)
		var a := bool(values[gate.inputs[0]])
		var result := false
		match kind:
			"AND":
				result = a and bool(values[gate.inputs[1]])
			"OR":
				result = a or bool(values[gate.inputs[1]])
			"XOR":
				result = a != bool(values[gate.inputs[1]])
			"NOT":
				result = not a
			"BUF":
				result = a
			_:
				return U.failure("LOGIC_INTERPRETER_UNSUPPORTED_GATE", {"kind": kind})
		values[gate.output] = result
		traversed += 1
	var output_word := 0
	for index in range(interface.output_signals.size()):
		if bool(values[interface.output_signals[index]]):
			output_word |= 1 << index
	var next_state_word := 0
	for index in range(plan.registers.size()):
		var register: Dictionary = plan.registers[index]
		if bool(values[register.inputs[0]]):
			next_state_word |= 1 << index
		traversed += 1
	return U.success({
		"output_word": output_word,
		"next_state_word": next_state_word,
		"source_operations_traversed": traversed,
		"event_order": ["OUTPUT_EVALUATED", "REGISTER_COMMIT"] if state_count > 0 else ["OUTPUT_EVALUATED"],
	})

static func _array_has_component_id(values: Array, component_id: String) -> bool:
	for value in values:
		if String(value.component_id) == component_id:
			return true
	return false
