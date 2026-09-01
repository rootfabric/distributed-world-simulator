extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const BoundaryContract = preload("res://scripts/research/fabric_bake0/physical_boundary_contract_v1.gd")
const DependencySet = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const SourceBinding = preload("res://scripts/research/fabric_bake0/bake_source_binding_v1.gd")
const StateSchema = preload("res://scripts/research/fabric_bake0/dynamic_state_schema_v1.gd")
const Model = preload("res://scripts/research/fabric_bake0/dynamic_full_model_descriptor_v1.gd")

const STATUS_READY := "DYNAMIC_FULL_MODEL_READY"
const STATUS_NO_SAFE_BAKE := "NO_SAFE_BAKE"
const COMPILER_VERSION := "FABRIC-BAKE/B0.4-A/R1"
const MIN_FULL_STATE_COUNT := 512

const REQUEST_FIELDS: Array[String] = [
	"model_id",
	"canonical_source_frontier",
	"authority_envelope",
	"dependency_set",
	"boundary_contract",
	"states",
	"storage_nodes",
	"edges",
	"shunts",
	"port_bindings",
	"reference_solver",
]

static func compile(request: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(request, REQUEST_FIELDS)
	if not bool(checked.get("success", false)):
		return _no_safe(String(checked.get("error_code", "B0_4_A_INVALID_REQUEST")))

	if typeof(request.get("canonical_source_frontier")) != TYPE_DICTIONARY:
		return _no_safe("B0_4_A_INVALID_SOURCE_FRONTIER")
	checked = Frontier.validate(request["canonical_source_frontier"])
	if not bool(checked.get("success", false)):
		return _no_safe(String(checked.get("error_code", "B0_4_A_INVALID_SOURCE_FRONTIER")))

	if typeof(request.get("authority_envelope")) != TYPE_DICTIONARY:
		return _no_safe("B0_4_A_INVALID_AUTHORITY_ENVELOPE")
	checked = AuthorityEnvelope.validate_b0_safety(request["authority_envelope"])
	if not bool(checked.get("success", false)):
		return _no_safe(String(checked.get("error_code", "B0_4_A_INVALID_AUTHORITY_ENVELOPE")))

	if typeof(request.get("dependency_set")) != TYPE_DICTIONARY:
		return _no_safe("B0_4_A_INVALID_DEPENDENCY_SET")
	checked = DependencySet.validate(request["dependency_set"])
	if not bool(checked.get("success", false)):
		return _no_safe(String(checked.get("error_code", "B0_4_A_INVALID_DEPENDENCY_SET")))

	if typeof(request.get("boundary_contract")) != TYPE_DICTIONARY:
		return _no_safe("B0_4_A_INVALID_BOUNDARY_CONTRACT")
	checked = BoundaryContract.validate(request["boundary_contract"])
	if not bool(checked.get("success", false)):
		return _no_safe(String(checked.get("error_code", "B0_4_A_INVALID_BOUNDARY_CONTRACT")))

	if typeof(request.get("states")) != TYPE_ARRAY:
		return _no_safe("B0_4_A_INVALID_STATES")
	var full_state_schema := StateSchema.create(request["states"])
	if full_state_schema.is_empty():
		return _no_safe("B0_4_A_INVALID_STATE_SCHEMA")
	if int(full_state_schema["state_count"]) < MIN_FULL_STATE_COUNT:
		return _no_safe("B0_4_A_REFERENCE_STATE_COUNT_BELOW_512", {
			"state_count": int(full_state_schema["state_count"]),
		})

	var graph_hash := Model.graph_hash_from_components(
		full_state_schema,
		request["storage_nodes"],
		request["edges"],
		request["shunts"],
		request["port_bindings"]
	)
	var source_binding := SourceBinding.create(
		request["canonical_source_frontier"],
		request["authority_envelope"],
		request["dependency_set"],
		graph_hash,
		COMPILER_VERSION,
		String(request["boundary_contract"]["contract_hash"]),
		policy_hash()
	)
	if source_binding.is_empty():
		return _no_safe("B0_4_A_SOURCE_BINDING_FAILED")

	var model := Model.create(
		String(request["model_id"]),
		source_binding,
		request["boundary_contract"],
		full_state_schema,
		request["storage_nodes"],
		request["edges"],
		request["shunts"],
		request["port_bindings"],
		request["reference_solver"]
	)
	if model.is_empty():
		var probe: Dictionary = {
			"schema": Model.SCHEMA,
			"model_id": request.get("model_id"),
			"model_class": Model.MODEL_CLASS,
			"source_binding": source_binding,
			"boundary_contract": request["boundary_contract"],
			"full_state_schema": full_state_schema,
			"storage_nodes": Utils.sorted_dicts(request["storage_nodes"], "state_id"),
			"edges": _canonical_edges(request["edges"]),
			"shunts": Utils.sorted_dicts(request["shunts"], "shunt_id"),
			"port_bindings": Utils.sorted_dicts(request["port_bindings"], "port_id"),
			"reference_solver": request["reference_solver"],
			"passivity_certificate": {},
			"model_hash": "",
			"checksum": "",
		}
		var reason := _diagnose_model_failure(probe)
		return _no_safe(reason)

	checked = Model.validate(model)
	if not bool(checked.get("success", false)):
		return _no_safe(String(checked.get("error_code", "B0_4_A_MODEL_VALIDATION_FAILED")))

	return {
		"success": true,
		"status": STATUS_READY,
		"error_code": "",
		"reason": "",
		"model": model,
		"diagnostics": {
			"full_state_count": int(model["full_state_schema"]["state_count"]),
			"boundary_port_count": model["boundary_contract"]["ports"].size(),
			"fabric_graph_hash": String(model["source_binding"]["fabric_graph_hash"]),
			"frontier_hash": String(model["source_binding"]["frontier_hash"]),
			"dependency_hash": String(model["source_binding"]["dependency_hash"]),
			"boundary_contract_hash": String(model["boundary_contract"]["contract_hash"]),
			"full_state_schema_hash": String(model["full_state_schema"]["schema_hash"]),
			"strictly_passive_stable": bool(model["passivity_certificate"]["strictly_stable"]),
			"minimum_storage_coefficient": float(model["passivity_certificate"]["minimum_storage_coefficient"]),
			"minimum_edge_conductance": float(model["passivity_certificate"]["minimum_edge_conductance"]),
			"minimum_shunt_conductance": float(model["passivity_certificate"]["minimum_shunt_conductance"]),
			"reference_solver": String(model["reference_solver"]["method"]),
		},
	}

static func policy_hash() -> String:
	return Utils.canonical_hash({
		"checkpoint": "B0.4-A",
		"scope": "DYNAMIC_FULL_MODEL_PORT_CONTRACT",
		"model_class": Model.MODEL_CLASS,
		"reference_solver": Model.SOLVER_METHOD,
		"minimum_full_state_count": MIN_FULL_STATE_COUNT,
		"canonical_boundary": "PHYSICAL_BOUNDARY_CONTRACT_V1",
		"authority": "B0_SINGLE_MUTABLE_OWNER_OR_FAIL_CLOSED",
	})

static func _diagnose_model_failure(probe: Dictionary) -> String:
	# Derive the real contract error without trusting a half-built certificate.
	var canonical_storage: Array = probe["storage_nodes"]
	var canonical_edges: Array = probe["edges"]
	var canonical_shunts: Array = probe["shunts"]
	var canonical_bindings: Array = probe["port_bindings"]
	var temp := Model.create(
		String(probe["model_id"]),
		probe["source_binding"],
		probe["boundary_contract"],
		probe["full_state_schema"],
		canonical_storage,
		canonical_edges,
		canonical_shunts,
		canonical_bindings,
		probe["reference_solver"]
	)
	if not temp.is_empty():
		return "B0_4_A_UNKNOWN_MODEL_BUILD_FAILURE"

	# Re-run focused checks in stable order to preserve exact diagnostics.
	var state_count := int(probe["full_state_schema"]["state_count"])
	if canonical_storage.size() != state_count:
		return "DYNAMIC_STORAGE_STATE_COVERAGE_MISMATCH"
	for node_any in canonical_storage:
		if typeof(node_any) != TYPE_DICTIONARY:
			return "INVALID_DYNAMIC_STORAGE_NODE"
		var node: Dictionary = node_any
		if not Utils.is_positive_number(node.get("storage_coefficient")):
			return "NO_SAFE_BAKE_NONPOSITIVE_DYNAMIC_STORAGE"
	if canonical_edges.size() != state_count - 1:
		return "DYNAMIC_REFERENCE_GRAPH_NOT_PATH"
	for edge_any in canonical_edges:
		if typeof(edge_any) != TYPE_DICTIONARY:
			return "INVALID_DYNAMIC_EDGE"
		var edge: Dictionary = edge_any
		if not Utils.is_positive_number(edge.get("conductance")):
			return "NO_SAFE_BAKE_NONPOSITIVE_DYNAMIC_COUPLING"
	if canonical_shunts.size() != state_count:
		return "DYNAMIC_SHUNT_STATE_COVERAGE_MISMATCH"
	for shunt_any in canonical_shunts:
		if typeof(shunt_any) != TYPE_DICTIONARY:
			return "INVALID_DYNAMIC_SHUNT"
		var shunt: Dictionary = shunt_any
		if not Utils.is_positive_number(shunt.get("conductance")):
			return "NO_SAFE_BAKE_NONPOSITIVE_DYNAMIC_SHUNT"

	# Build a provisional value with a derived certificate by creating a known-good
	# structure is not safe here; inspect boundary mismatches directly instead.
	var ports: Array = probe["boundary_contract"]["ports"]
	if canonical_bindings.size() != ports.size():
		return "DYNAMIC_PORT_BINDING_COVERAGE_MISMATCH"
	var state_by_id := {}
	for state in probe["full_state_schema"]["states"]:
		state_by_id[String(state["state_id"])] = state
	for index in range(canonical_bindings.size()):
		if typeof(canonical_bindings[index]) != TYPE_DICTIONARY:
			return "INVALID_DYNAMIC_PORT_BINDING"
		var binding: Dictionary = canonical_bindings[index]
		var port: Dictionary = ports[index]
		if String(binding.get("port_id", "")) != String(port["port_id"]):
			return "DYNAMIC_PORT_BINDING_ORDER_OR_COVERAGE_MISMATCH"
		if String(binding.get("frame", "")) != String(port["frame"]):
			return "DYNAMIC_PORT_FRAME_MISMATCH"
		if String(binding.get("orientation", "")) != String(port["orientation"]):
			return "DYNAMIC_PORT_ORIENTATION_MISMATCH"
		if String(binding.get("reference_causalization", "")) != Model.REFERENCE_CAUSALIZATION:
			return "DYNAMIC_PORT_INVALID_REFERENCE_CAUSALIZATION"
		var state_id := String(binding.get("state_id", ""))
		if not state_by_id.has(state_id):
			return "DYNAMIC_PORT_STATE_NOT_FOUND"
		var state: Dictionary = state_by_id[state_id]
		if state["dimension"] != port["effort_dimension"]:
			return "DYNAMIC_PORT_EFFORT_STATE_DIMENSION_MISMATCH"
		if String(state["quantity_id"]) != String(port["effort_quantity"]):
			return "DYNAMIC_PORT_EFFORT_STATE_QUANTITY_MISMATCH"

	return "B0_4_A_MODEL_CONTRACT_REJECTED"

static func _canonical_edges(edges: Array) -> Array:
	var output: Array = []
	for raw in edges:
		if typeof(raw) != TYPE_DICTIONARY:
			output.append(raw)
			continue
		var edge: Dictionary = raw.duplicate(true)
		var a := String(edge.get("state_a_id", ""))
		var b := String(edge.get("state_b_id", ""))
		if b < a:
			edge["state_a_id"] = b
			edge["state_b_id"] = a
		output.append(edge)
	return Utils.sorted_dicts(output, "edge_id")

static func _no_safe(reason: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"status": STATUS_NO_SAFE_BAKE,
		"error_code": reason,
		"reason": reason,
		"details": details.duplicate(true),
	}
