extends RefCounted
## Generic Boolean gate/register graph. No device names or arithmetic opcodes.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_logic_component_graph.v1"
const KINDS: Array[String] = ["AND", "BUF", "NOT", "OR", "REGISTER", "XOR"]
const COMMUTATIVE: Array[String] = ["AND", "OR", "XOR"]
const FIELDS: Array[String] = [
	"schema", "graph_id", "input_signals", "output_signals",
	"components", "graph_hash", "checksum",
]
const COMPONENT_FIELDS: Array[String] = [
	"component_id", "kind", "inputs", "output", "initial_value",
]

static func create(graph_id: String, input_signals: Array, output_signals: Array, components: Array) -> Dictionary:
	var normalized: Array = []
	for raw in components:
		if typeof(raw) != TYPE_DICTIONARY:
			normalized.append(raw)
			continue
		var component: Dictionary = raw.duplicate(true)
		if COMMUTATIVE.has(String(component.get("kind", ""))) and typeof(component.get("inputs")) == TYPE_ARRAY:
			component.inputs = U.sorted_strings(component.inputs)
		normalized.append(component)
	normalized = U.sorted_dicts(normalized, "component_id")
	var value := {
		"schema": SCHEMA,
		"graph_id": graph_id,
		"input_signals": U.sorted_strings(input_signals),
		"output_signals": U.sorted_strings(output_signals),
		"components": normalized,
		"graph_hash": "",
		"checksum": "",
	}
	value.graph_hash = U.canonical_hash({
		"graph_id": value.graph_id,
		"input_signals": value.input_signals,
		"output_signals": value.output_signals,
		"components": value.components,
	})
	value.checksum = U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA:
		return U.failure("UNSUPPORTED_LOGIC_COMPONENT_GRAPH_SCHEMA")
	if not U.is_canonical_id(value.get("graph_id"), 2):
		return U.failure("INVALID_LOGIC_GRAPH_ID")
	checked = U.validate_sorted_unique_strings(value.get("input_signals"), false)
	if not checked.success:
		return U.failure("INVALID_LOGIC_GRAPH_INPUTS")
	checked = U.validate_sorted_unique_strings(value.get("output_signals"), false)
	if not checked.success:
		return U.failure("INVALID_LOGIC_GRAPH_OUTPUTS")
	for signal_id in value.input_signals:
		if not U.is_canonical_id(signal_id, 2):
			return U.failure("INVALID_LOGIC_INPUT_SIGNAL")
	if typeof(value.get("components")) != TYPE_ARRAY or value.components.is_empty():
		return U.failure("INVALID_LOGIC_COMPONENTS")
	var producers := {}
	for signal_id in value.input_signals:
		producers[signal_id] = "EXTERNAL"
	var previous_component := ""
	for index in range(value.components.size()):
		var raw = value.components[index]
		if typeof(raw) != TYPE_DICTIONARY:
			return U.failure("INVALID_LOGIC_COMPONENT", {"index": index})
		var component: Dictionary = raw
		checked = U.validate_exact_fields(component, COMPONENT_FIELDS)
		if not checked.success:
			return checked
		if not U.is_canonical_id(component.get("component_id"), 2):
			return U.failure("INVALID_LOGIC_COMPONENT_ID", {"index": index})
		var kind := String(component.get("kind", ""))
		if not KINDS.has(kind):
			return U.failure("UNSUPPORTED_LOGIC_COMPONENT_KIND", {"index": index, "kind": kind})
		if typeof(component.get("inputs")) != TYPE_ARRAY:
			return U.failure("INVALID_LOGIC_COMPONENT_INPUTS", {"index": index})
		var arity := 2 if ["AND", "OR", "XOR"].has(kind) else 1
		if component.inputs.size() != arity:
			return U.failure("LOGIC_COMPONENT_ARITY_MISMATCH", {"index": index, "kind": kind})
		for input_id in component.inputs:
			if not U.is_canonical_id(input_id, 2):
				return U.failure("INVALID_LOGIC_COMPONENT_INPUT_SIGNAL", {"index": index})
		if not U.is_canonical_id(component.get("output"), 2):
			return U.failure("INVALID_LOGIC_COMPONENT_OUTPUT", {"index": index})
		if producers.has(component.output):
			return U.failure("LOGIC_SIGNAL_MULTIPLE_DRIVERS", {"signal": component.output})
		producers[component.output] = component.component_id
		if typeof(component.get("initial_value")) != TYPE_BOOL:
			return U.failure("INVALID_LOGIC_COMPONENT_INITIAL_VALUE", {"index": index})
		if kind != "REGISTER" and bool(component.initial_value):
			return U.failure("LOGIC_INITIAL_VALUE_ONLY_FOR_REGISTER", {"index": index})
		if index > 0 and String(component.component_id) <= previous_component:
			return U.failure("LOGIC_COMPONENTS_NOT_SORTED_UNIQUE")
		previous_component = String(component.component_id)
	var known := producers.keys()
	for index in range(value.components.size()):
		for input_id in value.components[index].inputs:
			if not known.has(input_id):
				return U.failure("LOGIC_INPUT_SIGNAL_UNDRIVEN", {"index": index, "signal": input_id})
	for signal_id in value.output_signals:
		if not U.is_canonical_id(signal_id, 2) or not known.has(signal_id):
			return U.failure("INVALID_LOGIC_OUTPUT_SIGNAL", {"signal": signal_id})
	if not U.is_lower_hex_64(value.get("graph_hash")):
		return U.failure("INVALID_LOGIC_GRAPH_HASH")
	var expected := U.canonical_hash({
		"graph_id": value.graph_id,
		"input_signals": value.input_signals,
		"output_signals": value.output_signals,
		"components": value.components,
	})
	if String(value.graph_hash) != expected:
		return U.failure("LOGIC_GRAPH_HASH_MISMATCH")
	return U.validate_checksum(value)
