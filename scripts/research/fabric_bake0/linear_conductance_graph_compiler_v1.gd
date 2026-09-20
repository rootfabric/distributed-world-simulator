extends RefCounted
## Generic topology compiler: characterized conductance components -> linear boundary system.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/linear_conductance_component_graph_v1.gd")
const LinearSystem = preload("res://scripts/research/fabric_bake0/linear_boundary_system_v1.gd")

const VERSION := "FABRIC_R5_2_LINEAR_COMPONENT_GRAPH_COMPILER_R1"

static func compile(graph: Dictionary) -> Dictionary:
	var checked := Graph.validate(graph)
	if not checked.success:
		return checked
	var boundary_node_ids: Array = []
	var boundary_port_ids: Array = []
	for port in graph.boundary_ports:
		boundary_port_ids.append(String(port.port_id))
		boundary_node_ids.append(String(port.node_id))
	var internal_node_ids: Array = []
	for node_id in graph.nodes:
		if not boundary_node_ids.has(node_id):
			internal_node_ids.append(String(node_id))
	var ordered_node_ids := boundary_node_ids.duplicate()
	ordered_node_ids.append_array(internal_node_ids)
	var index_by_node := {}
	for index in range(ordered_node_ids.size()):
		index_by_node[ordered_node_ids[index]] = index
	var total := ordered_node_ids.size()
	var matrix: Array = []
	for _row in range(total):
		var row: Array = []
		row.resize(total)
		row.fill(0.0)
		matrix.append(row)
	for component in graph.components:
		var a := int(index_by_node[component.node_a])
		var b := int(index_by_node[component.node_b])
		var g := float(component.conductance)
		matrix[a][a] = float(matrix[a][a]) + g
		matrix[b][b] = float(matrix[b][b]) + g
		matrix[a][b] = float(matrix[a][b]) - g
		matrix[b][a] = float(matrix[b][a]) - g
	var rhs: Array = []
	rhs.resize(total)
	rhs.fill(0.0)
	var graph_suffix := String(graph.graph_id).get_slice("/", 1)
	var system := LinearSystem.create(
		"system/%s" % graph_suffix,
		boundary_port_ids,
		internal_node_ids,
		matrix,
		rhs
	)
	if system.is_empty():
		return U.failure("R5_2_LINEAR_SYSTEM_ASSEMBLY_FAILED")
	return U.success({
		"linear_system": system,
		"graph_hash": graph.graph_hash,
		"component_count": graph.components.size(),
		"node_count": graph.nodes.size(),
		"boundary_count": boundary_port_ids.size(),
		"internal_count": internal_node_ids.size(),
		"components_scanned": graph.components.size(),
		"compiler_version": VERSION,
	})
