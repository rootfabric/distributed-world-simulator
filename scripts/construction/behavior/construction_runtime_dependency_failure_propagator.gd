extends RefCounted

const SubjectScript = preload("res://scripts/construction/behavior/construction_runtime_subject_state.gd")
const FailurePolicyScript = preload("res://scripts/construction/behavior/construction_runtime_failure_policy.gd")

const SCHEMA: String = "planet_simulator.construction_runtime_dependency_failure_propagator.v1"
const DEFAULT_MAX_NODES: int = 1024
const DEFAULT_MAX_EDGES: int = 4096


static func plan(
	subjects: Array,
	requirements_by_runtime_id: Dictionary,
	base_availability_by_runtime_id: Dictionary,
	edges: Array,
	max_nodes: int = DEFAULT_MAX_NODES,
	max_edges: int = DEFAULT_MAX_EDGES
) -> Dictionary:
	if max_nodes <= 0 or max_edges < 0:
		return _failure("INVALID_CONSTRUCTION_RUNTIME_DEPENDENCY_BOUNDS")
	if subjects.size() > max_nodes:
		return _failure("CONSTRUCTION_RUNTIME_DEPENDENCY_NODE_BOUND_EXCEEDED", {"node_count": subjects.size(), "max_nodes": max_nodes})
	if edges.size() > max_edges:
		return _failure("CONSTRUCTION_RUNTIME_DEPENDENCY_EDGE_BOUND_EXCEEDED", {"edge_count": edges.size(), "max_edges": max_edges})

	var normalized: Dictionary = _normalize_subjects(subjects)
	if not bool(normalized.get("success", false)):
		return normalized
	var subjects_by_id: Dictionary = Dictionary(normalized.get("subjects_by_id", {}))
	var construct_id: String = String(normalized.get("construct_id", ""))
	var ids: Array = subjects_by_id.keys()
	ids.sort()

	if requirements_by_runtime_id.size() != ids.size() or base_availability_by_runtime_id.size() != ids.size():
		return _failure("CONSTRUCTION_RUNTIME_DEPENDENCY_INPUT_CARDINALITY_MISMATCH")
	for runtime_id_value in ids:
		var runtime_id: String = String(runtime_id_value)
		if not requirements_by_runtime_id.has(runtime_id) or typeof(requirements_by_runtime_id[runtime_id]) != TYPE_DICTIONARY:
			return _failure("CONSTRUCTION_RUNTIME_DEPENDENCY_REQUIREMENTS_MISSING", {"runtime_id": runtime_id})
		if not base_availability_by_runtime_id.has(runtime_id) or typeof(base_availability_by_runtime_id[runtime_id]) != TYPE_DICTIONARY:
			return _failure("CONSTRUCTION_RUNTIME_DEPENDENCY_AVAILABILITY_MISSING", {"runtime_id": runtime_id})
		var base_validation: Dictionary = _validate_base_availability(Dictionary(base_availability_by_runtime_id[runtime_id]))
		if not bool(base_validation.get("success", false)):
			return _failure(String(base_validation.get("error_code", "INVALID_CONSTRUCTION_RUNTIME_DEPENDENCY_AVAILABILITY")), {"runtime_id": runtime_id})
		var requirement_probe: Dictionary = FailurePolicyScript.project(
			Dictionary(subjects_by_id[runtime_id]),
			Dictionary(requirements_by_runtime_id[runtime_id]),
			{"power": true, "data": true, "dependency": true}
		)
		if not bool(requirement_probe.get("success", false)):
			return requirement_probe

	var graph: Dictionary = _build_graph(ids, edges, subjects_by_id)
	if not bool(graph.get("success", false)):
		return graph
	var upstream_by_id: Dictionary = Dictionary(graph.get("upstream_by_id", {}))
	var order_result: Dictionary = _topological_order(ids, Dictionary(graph.get("downstream_by_id", {})), Dictionary(graph.get("indegree", {})))
	if not bool(order_result.get("success", false)):
		return order_result
	var order: Array = Array(order_result.get("order", []))

	var projected_operability: Dictionary = {}
	var proposals: Array = []
	var changed_runtime_ids: Array[String] = []
	for runtime_id_value in order:
		var runtime_id: String = String(runtime_id_value)
		var dependency_available: bool = true
		var upstream_ids: Array = Array(upstream_by_id.get(runtime_id, [])).duplicate()
		upstream_ids.sort()
		for upstream_value in upstream_ids:
			var upstream_id: String = String(upstream_value)
			if String(projected_operability.get(upstream_id, "OFFLINE")) == "OFFLINE":
				dependency_available = false
				break

		var base_availability: Dictionary = Dictionary(base_availability_by_runtime_id[runtime_id])
		var projection: Dictionary = FailurePolicyScript.project(
			Dictionary(subjects_by_id[runtime_id]),
			Dictionary(requirements_by_runtime_id[runtime_id]),
			{
				"power": bool(base_availability.get("power", false)),
				"data": bool(base_availability.get("data", false)),
				"dependency": dependency_available,
			}
		)
		if not bool(projection.get("success", false)):
			return projection
		projected_operability[runtime_id] = String(projection.get("operability", ""))
		var subject: Dictionary = Dictionary(subjects_by_id[runtime_id])
		var next_state: Dictionary = Dictionary(projection.get("next_state", {}))
		var changed: bool = Dictionary(subject.get("state", {})) != next_state
		if changed:
			changed_runtime_ids.append(runtime_id)
		proposals.append({
			"runtime_id": runtime_id,
			"expected_revision": int(projection.get("expected_revision", -1)),
			"next_state": next_state.duplicate(true),
			"operability": String(projection.get("operability", "")),
			"failure_codes": Array(projection.get("failure_codes", [])).duplicate(),
			"dependency_available": dependency_available,
			"upstream_runtime_ids": upstream_ids,
			"changed": changed,
		})

	return _success({
		"schema": SCHEMA,
		"construct_id": construct_id,
		"node_count": ids.size(),
		"edge_count": edges.size(),
		"order": order,
		"proposals": proposals,
		"changed_runtime_ids": changed_runtime_ids,
		"bounded": true,
		"max_nodes": max_nodes,
		"max_edges": max_edges,
		"degraded_upstream_counts_as_available": true,
		"requires_global_dependency_identity": false,
		"commits_runtime_state": false,
	})


static func _normalize_subjects(subjects: Array) -> Dictionary:
	var subjects_by_id: Dictionary = {}
	var construct_id: String = ""
	for raw in subjects:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_RUNTIME_DEPENDENCY_SUBJECT")
		var subject: Dictionary = Dictionary(raw)
		var validation: Dictionary = SubjectScript.validate(subject)
		if not bool(validation.get("success", false)):
			return validation
		var runtime_id: String = String(subject.get("runtime_id", ""))
		var subject_construct_id: String = String(subject.get("construct_id", ""))
		if construct_id.is_empty():
			construct_id = subject_construct_id
		elif subject_construct_id != construct_id:
			return _failure("CONSTRUCTION_RUNTIME_DEPENDENCY_CROSS_CONSTRUCT_SUBJECT_SET")
		if subjects_by_id.has(runtime_id):
			return _failure("DUPLICATE_CONSTRUCTION_RUNTIME_DEPENDENCY_SUBJECT", {"runtime_id": runtime_id})
		subjects_by_id[runtime_id] = subject.duplicate(true)
	if subjects_by_id.is_empty():
		return _failure("EMPTY_CONSTRUCTION_RUNTIME_DEPENDENCY_SUBJECT_SET")
	return _success({"subjects_by_id": subjects_by_id, "construct_id": construct_id})


static func _validate_base_availability(value: Dictionary) -> Dictionary:
	if value.size() != 2 or not value.has("power") or not value.has("data"):
		return _failure("INVALID_CONSTRUCTION_RUNTIME_DEPENDENCY_AVAILABILITY")
	if typeof(value["power"]) != TYPE_BOOL or typeof(value["data"]) != TYPE_BOOL:
		return _failure("INVALID_CONSTRUCTION_RUNTIME_DEPENDENCY_AVAILABILITY")
	return _success()


static func _build_graph(ids: Array, edges: Array, subjects_by_id: Dictionary) -> Dictionary:
	var upstream_by_id: Dictionary = {}
	var downstream_by_id: Dictionary = {}
	var indegree: Dictionary = {}
	for runtime_id_value in ids:
		var runtime_id: String = String(runtime_id_value)
		upstream_by_id[runtime_id] = []
		downstream_by_id[runtime_id] = []
		indegree[runtime_id] = 0

	var seen_edges: Dictionary = {}
	for raw in edges:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_RUNTIME_DEPENDENCY_EDGE")
		var edge: Dictionary = Dictionary(raw)
		if edge.size() != 2 or not edge.has("from_runtime_id") or not edge.has("to_runtime_id"):
			return _failure("INVALID_CONSTRUCTION_RUNTIME_DEPENDENCY_EDGE")
		var from_id: String = String(edge.get("from_runtime_id", ""))
		var to_id: String = String(edge.get("to_runtime_id", ""))
		if not subjects_by_id.has(from_id) or not subjects_by_id.has(to_id):
			return _failure("CONSTRUCTION_RUNTIME_DEPENDENCY_EDGE_SUBJECT_NOT_FOUND", {"from_runtime_id": from_id, "to_runtime_id": to_id})
		if from_id == to_id:
			return _failure("CONSTRUCTION_RUNTIME_DEPENDENCY_SELF_EDGE", {"runtime_id": from_id})
		var edge_key: String = "%s>%s" % [from_id, to_id]
		if seen_edges.has(edge_key):
			return _failure("DUPLICATE_CONSTRUCTION_RUNTIME_DEPENDENCY_EDGE", {"edge": edge_key})
		seen_edges[edge_key] = true
		var upstream: Array = Array(upstream_by_id[to_id])
		upstream.append(from_id)
		upstream_by_id[to_id] = upstream
		var downstream: Array = Array(downstream_by_id[from_id])
		downstream.append(to_id)
		downstream_by_id[from_id] = downstream
		indegree[to_id] = int(indegree[to_id]) + 1

	for runtime_id_value in ids:
		var runtime_id: String = String(runtime_id_value)
		var upstream_sorted: Array = Array(upstream_by_id[runtime_id])
		upstream_sorted.sort()
		upstream_by_id[runtime_id] = upstream_sorted
		var downstream_sorted: Array = Array(downstream_by_id[runtime_id])
		downstream_sorted.sort()
		downstream_by_id[runtime_id] = downstream_sorted
	return _success({"upstream_by_id": upstream_by_id, "downstream_by_id": downstream_by_id, "indegree": indegree})


static func _topological_order(ids: Array, downstream_by_id: Dictionary, indegree_source: Dictionary) -> Dictionary:
	var indegree: Dictionary = indegree_source.duplicate(true)
	var ready: Array = []
	for runtime_id_value in ids:
		var runtime_id: String = String(runtime_id_value)
		if int(indegree.get(runtime_id, 0)) == 0:
			ready.append(runtime_id)
	ready.sort()
	var order: Array = []
	while not ready.is_empty():
		var runtime_id: String = String(ready.pop_front())
		order.append(runtime_id)
		for downstream_value in Array(downstream_by_id.get(runtime_id, [])):
			var downstream_id: String = String(downstream_value)
			indegree[downstream_id] = int(indegree[downstream_id]) - 1
			if int(indegree[downstream_id]) == 0:
				ready.append(downstream_id)
				ready.sort()
	if order.size() != ids.size():
		return _failure("CONSTRUCTION_RUNTIME_DEPENDENCY_CYCLE")
	return _success({"order": order})


static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
