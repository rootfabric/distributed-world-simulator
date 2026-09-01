extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const SourceBinding = preload("res://scripts/research/fabric_bake0/bake_source_binding_v1.gd")
const BoundaryContract = preload("res://scripts/research/fabric_bake0/physical_boundary_contract_v1.gd")
const StateSchema = preload("res://scripts/research/fabric_bake0/dynamic_state_schema_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_dynamic_full_model.v1"
const MODEL_CLASS := "PASSIVE_SCALAR_STORAGE_PATH_R1"
const SOLVER_METHOD := "BACKWARD_EULER_TRIDIAGONAL_PATH_R1"
const REFERENCE_CAUSALIZATION := "FLOW_DRIVEN_REFERENCE_ONLY"
const TIME_DIMENSION: Array = [0, 0, 1, 0, 0, 0, 0]

const STORAGE_FIELDS: Array[String] = [
	"state_id", "storage_coefficient", "storage_coefficient_dimension", "initial_value",
]
const EDGE_FIELDS: Array[String] = [
	"edge_id", "state_a_id", "state_b_id", "conductance", "conductance_dimension",
]
const SHUNT_FIELDS: Array[String] = [
	"shunt_id", "state_id", "conductance", "conductance_dimension",
]
const PORT_BINDING_FIELDS: Array[String] = [
	"port_id", "state_id", "frame", "orientation", "reference_causalization",
]
const SOLVER_FIELDS: Array[String] = ["method", "max_step_s"]
const PASSIVITY_FIELDS: Array[String] = [
	"certificate_kind",
	"minimum_storage_coefficient",
	"minimum_edge_conductance",
	"minimum_shunt_conductance",
	"all_edges_positive",
	"all_shunts_positive",
	"connected_path",
	"strictly_stable",
	"certificate_hash",
]
const FIELDS: Array[String] = [
	"schema", "model_id", "model_class", "source_binding", "boundary_contract",
	"full_state_schema", "storage_nodes", "edges", "shunts", "port_bindings",
	"reference_solver", "passivity_certificate", "model_hash", "checksum",
]

static func create(
	model_id: String,
	source_binding: Dictionary,
	boundary_contract: Dictionary,
	full_state_schema: Dictionary,
	storage_nodes: Array,
	edges: Array,
	shunts: Array,
	port_bindings: Array,
	reference_solver: Dictionary
) -> Dictionary:
	var canonical_edges: Array = []
	for raw in edges:
		if typeof(raw) != TYPE_DICTIONARY:
			canonical_edges.append(raw)
			continue
		var edge: Dictionary = raw.duplicate(true)
		var a := String(edge.get("state_a_id", ""))
		var b := String(edge.get("state_b_id", ""))
		if b < a:
			edge["state_a_id"] = b
			edge["state_b_id"] = a
		canonical_edges.append(edge)
	canonical_edges = Utils.sorted_dicts(canonical_edges, "edge_id")
	var canonical_storage := Utils.sorted_dicts(storage_nodes, "state_id")
	var canonical_shunts := Utils.sorted_dicts(shunts, "shunt_id")
	var canonical_bindings := Utils.sorted_dicts(port_bindings, "port_id")
	var certificate := _derive_passivity_certificate(
		full_state_schema,
		canonical_storage,
		canonical_edges,
		canonical_shunts
	)
	var value: Dictionary = {
		"schema": SCHEMA,
		"model_id": model_id,
		"model_class": MODEL_CLASS,
		"source_binding": source_binding.duplicate(true),
		"boundary_contract": boundary_contract.duplicate(true),
		"full_state_schema": full_state_schema.duplicate(true),
		"storage_nodes": canonical_storage,
		"edges": canonical_edges,
		"shunts": canonical_shunts,
		"port_bindings": canonical_bindings,
		"reference_solver": reference_solver.duplicate(true),
		"passivity_certificate": certificate,
		"model_hash": "",
		"checksum": "",
	}
	value["model_hash"] = Utils.canonical_hash(_model_payload(value))
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_DYNAMIC_FULL_MODEL_SCHEMA")
	if not Utils.is_canonical_id(value.get("model_id"), 2):
		return Utils.failure("INVALID_DYNAMIC_MODEL_ID")
	if value.get("model_class") != MODEL_CLASS:
		return Utils.failure("UNSUPPORTED_DYNAMIC_MODEL_CLASS")

	if typeof(value.get("source_binding")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_MODEL_SOURCE_BINDING")
	checked = SourceBinding.validate(value["source_binding"])
	if not bool(checked.get("success", false)):
		return checked

	if typeof(value.get("boundary_contract")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_MODEL_BOUNDARY_CONTRACT")
	checked = BoundaryContract.validate(value["boundary_contract"])
	if not bool(checked.get("success", false)):
		return checked
	if String(value["source_binding"]["boundary_contract_hash"]) != String(value["boundary_contract"]["contract_hash"]):
		return Utils.failure("DYNAMIC_MODEL_BOUNDARY_BINDING_MISMATCH")
	if value["boundary_contract"]["ports"].size() < 2:
		return Utils.failure("DYNAMIC_MODEL_REQUIRES_MULTIPORT_BOUNDARY")

	if typeof(value.get("full_state_schema")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_MODEL_STATE_SCHEMA")
	checked = StateSchema.validate(value["full_state_schema"])
	if not bool(checked.get("success", false)):
		return checked
	if int(value["full_state_schema"]["state_count"]) < 2:
		return Utils.failure("DYNAMIC_MODEL_STATE_COUNT_TOO_SMALL")

	checked = _validate_storage(value)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_edges(value)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_shunts(value)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_boundary_compatibility(value)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_solver(value)
	if not bool(checked.get("success", false)):
		return checked

	if typeof(value.get("passivity_certificate")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_PASSIVITY_CERTIFICATE")
	checked = Utils.validate_exact_fields(value["passivity_certificate"], PASSIVITY_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	var expected_certificate := _derive_passivity_certificate(
		value["full_state_schema"],
		value["storage_nodes"],
		value["edges"],
		value["shunts"]
	)
	if value["passivity_certificate"] != expected_certificate:
		return Utils.failure("DYNAMIC_PASSIVITY_CERTIFICATE_MISMATCH")
	if not bool(value["passivity_certificate"]["strictly_stable"]):
		return Utils.failure("NO_SAFE_BAKE_DYNAMIC_MODEL_NOT_STRICTLY_PASSIVE_STABLE")

	var expected_graph_hash := dynamic_graph_hash(value)
	if String(value["source_binding"]["fabric_graph_hash"]) != expected_graph_hash:
		return Utils.failure("DYNAMIC_MODEL_FABRIC_GRAPH_BINDING_MISMATCH")

	if not Utils.is_lower_hex_64(value.get("model_hash")):
		return Utils.failure("INVALID_DYNAMIC_MODEL_HASH")
	if String(value["model_hash"]) != Utils.canonical_hash(_model_payload(value)):
		return Utils.failure("DYNAMIC_MODEL_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func dynamic_graph_hash(value: Dictionary) -> String:
	var storage_graph: Array = []
	for raw in value.get("storage_nodes", []):
		if typeof(raw) != TYPE_DICTIONARY:
			storage_graph.append(raw)
			continue
		var node: Dictionary = raw.duplicate(true)
		node.erase("initial_value")
		storage_graph.append(node)
	return Utils.canonical_hash({
		"model_class": value.get("model_class"),
		"full_state_schema_hash": value.get("full_state_schema", {}).get("schema_hash", ""),
		"storage_nodes": storage_graph,
		"edges": value.get("edges", []),
		"shunts": value.get("shunts", []),
		"port_bindings": value.get("port_bindings", []),
	})

static func state_index(value: Dictionary) -> Dictionary:
	return StateSchema.state_index(value["full_state_schema"])

static func _validate_storage(value: Dictionary) -> Dictionary:
	if typeof(value.get("storage_nodes")) != TYPE_ARRAY:
		return Utils.failure("INVALID_DYNAMIC_STORAGE_NODES")
	var states: Array = value["full_state_schema"]["states"]
	if value["storage_nodes"].size() != states.size():
		return Utils.failure("DYNAMIC_STORAGE_STATE_COVERAGE_MISMATCH")
	for index in range(value["storage_nodes"].size()):
		var raw = value["storage_nodes"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_DYNAMIC_STORAGE_NODE", {"index": index})
		var node: Dictionary = raw
		var checked := Utils.validate_exact_fields(node, STORAGE_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if String(node.get("state_id", "")) != String(states[index]["state_id"]):
			return Utils.failure("DYNAMIC_STORAGE_ORDER_OR_COVERAGE_MISMATCH", {"index": index})
		if not Utils.is_positive_number(node.get("storage_coefficient")):
			return Utils.failure("NO_SAFE_BAKE_NONPOSITIVE_DYNAMIC_STORAGE", {"index": index})
		checked = Utils.validate_dimension(node.get("storage_coefficient_dimension"))
		if not bool(checked.get("success", false)):
			return Utils.failure("INVALID_DYNAMIC_STORAGE_DIMENSION", {"index": index})
		if not Utils.is_finite_number(node.get("initial_value")):
			return Utils.failure("INVALID_DYNAMIC_INITIAL_STATE", {"index": index})
	return Utils.success()

static func _validate_edges(value: Dictionary) -> Dictionary:
	if typeof(value.get("edges")) != TYPE_ARRAY:
		return Utils.failure("INVALID_DYNAMIC_EDGES")
	var states: Array = value["full_state_schema"]["states"]
	if value["edges"].size() != states.size() - 1:
		return Utils.failure("DYNAMIC_REFERENCE_GRAPH_NOT_PATH")
	var previous_id := ""
	for index in range(value["edges"].size()):
		var raw = value["edges"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_DYNAMIC_EDGE", {"index": index})
		var edge: Dictionary = raw
		var checked := Utils.validate_exact_fields(edge, EDGE_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_canonical_id(edge.get("edge_id"), 2):
			return Utils.failure("INVALID_DYNAMIC_EDGE_ID", {"index": index})
		if not Utils.is_positive_number(edge.get("conductance")):
			return Utils.failure("NO_SAFE_BAKE_NONPOSITIVE_DYNAMIC_COUPLING", {"index": index})
		checked = Utils.validate_dimension(edge.get("conductance_dimension"))
		if not bool(checked.get("success", false)):
			return Utils.failure("INVALID_DYNAMIC_CONDUCTANCE_DIMENSION", {"index": index})
		var expected_a := String(states[index]["state_id"])
		var expected_b := String(states[index + 1]["state_id"])
		if String(edge.get("state_a_id", "")) != expected_a or String(edge.get("state_b_id", "")) != expected_b:
			return Utils.failure("DYNAMIC_REFERENCE_GRAPH_NOT_CANONICAL_PATH", {"index": index})
		var current_id := String(edge["edge_id"])
		if index > 0 and current_id <= previous_id:
			return Utils.failure("DYNAMIC_EDGES_NOT_SORTED_UNIQUE", {"index": index})
		previous_id = current_id
	return Utils.success()

static func _validate_shunts(value: Dictionary) -> Dictionary:
	if typeof(value.get("shunts")) != TYPE_ARRAY:
		return Utils.failure("INVALID_DYNAMIC_SHUNTS")
	var states: Array = value["full_state_schema"]["states"]
	if value["shunts"].size() != states.size():
		return Utils.failure("DYNAMIC_SHUNT_STATE_COVERAGE_MISMATCH")
	var by_state := {}
	for index in range(value["shunts"].size()):
		var raw = value["shunts"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_DYNAMIC_SHUNT", {"index": index})
		var shunt: Dictionary = raw
		var checked := Utils.validate_exact_fields(shunt, SHUNT_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_canonical_id(shunt.get("shunt_id"), 2):
			return Utils.failure("INVALID_DYNAMIC_SHUNT_ID", {"index": index})
		if not Utils.is_positive_number(shunt.get("conductance")):
			return Utils.failure("NO_SAFE_BAKE_NONPOSITIVE_DYNAMIC_SHUNT", {"index": index})
		checked = Utils.validate_dimension(shunt.get("conductance_dimension"))
		if not bool(checked.get("success", false)):
			return Utils.failure("INVALID_DYNAMIC_SHUNT_DIMENSION", {"index": index})
		var state_id := String(shunt.get("state_id", ""))
		if by_state.has(state_id):
			return Utils.failure("DYNAMIC_SHUNT_DUPLICATE_STATE", {"state_id": state_id})
		by_state[state_id] = true
	for state in states:
		if not by_state.has(String(state["state_id"])):
			return Utils.failure("DYNAMIC_SHUNT_STATE_NOT_COVERED", {"state_id": state["state_id"]})
	return Utils.success()

static func _validate_boundary_compatibility(value: Dictionary) -> Dictionary:
	if typeof(value.get("port_bindings")) != TYPE_ARRAY:
		return Utils.failure("INVALID_DYNAMIC_PORT_BINDINGS")
	var ports: Array = value["boundary_contract"]["ports"]
	if value["port_bindings"].size() != ports.size():
		return Utils.failure("DYNAMIC_PORT_BINDING_COVERAGE_MISMATCH")
	var state_by_id := {}
	for state in value["full_state_schema"]["states"]:
		state_by_id[String(state["state_id"])] = state
	var common_effort_dimension = null
	var common_flow_dimension = null
	var common_effort_quantity := ""
	var common_flow_quantity := ""
	var seen_states := {}
	for index in range(value["port_bindings"].size()):
		var binding_raw = value["port_bindings"][index]
		if typeof(binding_raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_DYNAMIC_PORT_BINDING", {"index": index})
		var binding: Dictionary = binding_raw
		var checked := Utils.validate_exact_fields(binding, PORT_BINDING_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var port: Dictionary = ports[index]
		if String(binding.get("port_id", "")) != String(port["port_id"]):
			return Utils.failure("DYNAMIC_PORT_BINDING_ORDER_OR_COVERAGE_MISMATCH", {"index": index})
		if String(binding.get("frame", "")) != String(port["frame"]):
			return Utils.failure("DYNAMIC_PORT_FRAME_MISMATCH", {"port_id": port["port_id"]})
		if String(binding.get("orientation", "")) != String(port["orientation"]):
			return Utils.failure("DYNAMIC_PORT_ORIENTATION_MISMATCH", {"port_id": port["port_id"]})
		if String(binding.get("reference_causalization", "")) != REFERENCE_CAUSALIZATION:
			return Utils.failure("DYNAMIC_PORT_INVALID_REFERENCE_CAUSALIZATION", {"port_id": port["port_id"]})
		var state_id := String(binding.get("state_id", ""))
		if not state_by_id.has(state_id):
			return Utils.failure("DYNAMIC_PORT_STATE_NOT_FOUND", {"port_id": port["port_id"]})
		if seen_states.has(state_id):
			return Utils.failure("DYNAMIC_PORT_STATE_REUSED", {"state_id": state_id})
		seen_states[state_id] = true
		var state: Dictionary = state_by_id[state_id]
		if state["dimension"] != port["effort_dimension"]:
			return Utils.failure("DYNAMIC_PORT_EFFORT_STATE_DIMENSION_MISMATCH", {"port_id": port["port_id"]})
		if String(state["quantity_id"]) != String(port["effort_quantity"]):
			return Utils.failure("DYNAMIC_PORT_EFFORT_STATE_QUANTITY_MISMATCH", {"port_id": port["port_id"]})
		if common_effort_dimension == null:
			common_effort_dimension = port["effort_dimension"]
			common_flow_dimension = port["flow_dimension"]
			common_effort_quantity = String(port["effort_quantity"])
			common_flow_quantity = String(port["flow_quantity"])
		else:
			if port["effort_dimension"] != common_effort_dimension or port["flow_dimension"] != common_flow_dimension:
				return Utils.failure("DYNAMIC_R1_MIXED_PORT_DIMENSIONS_UNSUPPORTED")
			if String(port["effort_quantity"]) != common_effort_quantity or String(port["flow_quantity"]) != common_flow_quantity:
				return Utils.failure("DYNAMIC_R1_MIXED_PORT_QUANTITIES_UNSUPPORTED")

	for state in value["full_state_schema"]["states"]:
		if state["dimension"] != common_effort_dimension or String(state["quantity_id"]) != common_effort_quantity:
			return Utils.failure("DYNAMIC_R1_STATE_BOUNDARY_QUANTITY_MISMATCH", {"state_id": state["state_id"]})
	var expected_storage_dimension := _dim_sub(_dim_add(common_flow_dimension, TIME_DIMENSION), common_effort_dimension)
	var expected_conductance_dimension := _dim_sub(common_flow_dimension, common_effort_dimension)
	for node in value["storage_nodes"]:
		if node["storage_coefficient_dimension"] != expected_storage_dimension:
			return Utils.failure("DYNAMIC_STORAGE_PORT_DIMENSION_MISMATCH", {"state_id": node["state_id"]})
	for edge in value["edges"]:
		if edge["conductance_dimension"] != expected_conductance_dimension:
			return Utils.failure("DYNAMIC_EDGE_PORT_DIMENSION_MISMATCH", {"edge_id": edge["edge_id"]})
	for shunt in value["shunts"]:
		if shunt["conductance_dimension"] != expected_conductance_dimension:
			return Utils.failure("DYNAMIC_SHUNT_PORT_DIMENSION_MISMATCH", {"shunt_id": shunt["shunt_id"]})
	return Utils.success()

static func _validate_solver(value: Dictionary) -> Dictionary:
	if typeof(value.get("reference_solver")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_REFERENCE_SOLVER")
	var checked := Utils.validate_exact_fields(value["reference_solver"], SOLVER_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if String(value["reference_solver"].get("method", "")) != SOLVER_METHOD:
		return Utils.failure("UNSUPPORTED_DYNAMIC_REFERENCE_SOLVER")
	if not Utils.is_positive_number(value["reference_solver"].get("max_step_s")):
		return Utils.failure("INVALID_DYNAMIC_REFERENCE_MAX_STEP")
	return Utils.success()

static func _derive_passivity_certificate(
	full_state_schema: Dictionary,
	storage_nodes: Array,
	edges: Array,
	shunts: Array
) -> Dictionary:
	var min_storage := INF
	var min_edge := INF
	var min_shunt := INF
	var all_edges_positive := not edges.is_empty()
	var all_shunts_positive := not shunts.is_empty()
	for raw in storage_nodes:
		if typeof(raw) != TYPE_DICTIONARY or not Utils.is_finite_number(raw.get("storage_coefficient")):
			min_storage = -INF
			continue
		min_storage = minf(min_storage, float(raw["storage_coefficient"]))
	for raw in edges:
		if typeof(raw) != TYPE_DICTIONARY or not Utils.is_finite_number(raw.get("conductance")):
			min_edge = -INF
			all_edges_positive = false
			continue
		var g := float(raw["conductance"])
		min_edge = minf(min_edge, g)
		all_edges_positive = all_edges_positive and g > 0.0
	for raw in shunts:
		if typeof(raw) != TYPE_DICTIONARY or not Utils.is_finite_number(raw.get("conductance")):
			min_shunt = -INF
			all_shunts_positive = false
			continue
		var g := float(raw["conductance"])
		min_shunt = minf(min_shunt, g)
		all_shunts_positive = all_shunts_positive and g > 0.0
	var connected_path := (
		typeof(full_state_schema.get("states")) == TYPE_ARRAY
		and edges.size() == maxi(0, full_state_schema["states"].size() - 1)
		and all_edges_positive
	)
	var strictly_stable := min_storage > 0.0 and all_shunts_positive and connected_path
	var payload := {
		"certificate_kind": "STRUCTURAL_PASSIVITY_R1",
		"minimum_storage_coefficient": min_storage,
		"minimum_edge_conductance": min_edge,
		"minimum_shunt_conductance": min_shunt,
		"all_edges_positive": all_edges_positive,
		"all_shunts_positive": all_shunts_positive,
		"connected_path": connected_path,
		"strictly_stable": strictly_stable,
	}
	payload["certificate_hash"] = Utils.canonical_hash(payload)
	return payload

static func _model_payload(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("model_hash")
	payload.erase("checksum")
	return payload

static func _dim_add(a: Array, b: Array) -> Array:
	var result: Array = []
	for index in range(7):
		result.append(int(a[index]) + int(b[index]))
	return result

static func _dim_sub(a: Array, b: Array) -> Array:
	var result: Array = []
	for index in range(7):
		result.append(int(a[index]) - int(b[index]))
	return result
