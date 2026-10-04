extends RefCounted
## Generic exact-linear hierarchy fixture for R5.3. The full-source oracle expands
## all leaf components and hierarchy connectors without using parent ROM matrices.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/linear_conductance_component_graph_v1.gd")
const T1 = preload("res://scripts/research/fabric_bake0/r5_t1_boundary_network_capsule_compiler_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/r5_3_recursive_rom_compiler_v1.gd")

const LEAF_INTERNAL := 100
const LEAF_COUNT := 8
const PORTS := 4

static func _slug(value: String) -> String:
	return value.replace("/", "-").replace("_", "-")

static func leaf_graph(node_id: String, revision: int = 0, internal_count: int = LEAF_INTERNAL) -> Dictionary:
	var nodes: Array = ["node/boundary-a","node/boundary-b","node/boundary-c","node/boundary-d"]
	for i in range(internal_count): nodes.append("node/internal-%02d" % i)
	var ports: Array = []
	for suffix in ["a","b","c","d"]: ports.append({"port_id":"port/electrical-%s" % suffix, "node_id":"node/boundary-%s" % suffix})
	var components: Array = []; var cid := 0
	for i in range(internal_count):
		components.append(_component(cid, "node/internal-%02d" % i, "node/internal-%02d" % ((i + 1) % internal_count), 0.8 + 0.03 * float((i * 5) % 7))); cid += 1
		components.append(_component(cid, "node/internal-%02d" % i, "node/internal-%02d" % ((i + 5) % internal_count), 0.17 + 0.02 * float((i * 3) % 5))); cid += 1
	for p in range(PORTS):
		for k in range(4):
			var idx := (p * 3 + k * 5) % internal_count
			var g := 0.65 + 0.05 * float(p + k)
			if p == 0 and k == 0: g += 0.031 * float(revision)
			components.append(_component(cid, "node/boundary-%s" % ["a","b","c","d"][p], "node/internal-%02d" % idx, g)); cid += 1
	return Graph.create("graph/%s" % _slug(node_id), nodes, ports, components)

static func _component(index: int, a: String, b: String, g: float) -> Dictionary:
	return {"component_id":"component/r53-leaf-%05d" % index, "law_kind":Graph.LAW_KIND, "node_a":a, "node_b":b, "conductance":g, "material_tag":"material/conductor-characterized"}

static func compile_leaf(node_id: String, revision: int = 0, generation: int = 1, internal_count: int = LEAF_INTERNAL) -> Dictionary:
	var graph := leaf_graph(node_id, revision, internal_count)
	if graph.is_empty(): return U.failure("R5_3_FIXTURE_LEAF_GRAPH_INVALID")
	var request := Compiler._request(graph, node_id, [], revision, generation)
	if request.is_empty(): return U.failure("R5_3_FIXTURE_LEAF_REQUEST_INVALID")
	var compiled := T1.compile(graph, request, "capsule/%s" % _slug(node_id))
	if not bool(compiled.get("success", false)): return compiled
	return Compiler.leaf_from_t1(node_id, graph, compiled)

static func build_hierarchy() -> Dictionary:
	var assemblies := {}
	var leaf_total := 0
	for a in range(2):
		var modules := {}
		for m in range(2):
			var leaves := {}
			for l in range(2):
				var leaf := compile_leaf("r53/leaf-%d-%d-%d" % [a,m,l])
				if not bool(leaf.get("success", false)): return leaf
				leaves["leaf%d" % l] = leaf.details; leaf_total += 1
			var module := Compiler.compose("r53/module-%d-%d" % [a,m], 1, leaves, 0, 1)
			if not bool(module.get("success", false)): return module
			modules["module%d" % m] = module.details
		var assembly := Compiler.compose("r53/assembly-%d" % a, 2, modules, 0, 1)
		if not bool(assembly.get("success", false)): return assembly
		assemblies["assembly%d" % a] = assembly.details
	var machine := Compiler.compose("r53/machine", 3, assemblies, 0, 1)
	if not bool(machine.get("success", false)): return machine
	return U.success({"root":machine.details, "leaf_count":leaf_total})

static func _boundary_index_from_name(node: String) -> int:
	for p in range(PORTS):
		if node == "node/boundary-%s" % ["a","b","c","d"][p]: return p
	return -1

static func _expand(bundle: Dictionary) -> Dictionary:
	var slug := _slug(String(bundle.node_id))
	var boundary_nodes: Array = []
	for p in range(PORTS): boundary_nodes.append("node/full-%s/p%02d" % [slug,p])
	var nodes: Array = boundary_nodes.duplicate(); var edges: Array = []
	var children: Dictionary = bundle.children
	if children.is_empty():
		var graph: Dictionary = bundle.source_graph
		var map := {}
		for p in range(PORTS): map[String(graph.boundary_ports[p].node_id)] = boundary_nodes[p]
		for raw_node in graph.nodes:
			var old := String(raw_node)
			if not map.has(old): map[old] = "node/full-%s/%s" % [slug, old.replace("node/", "i-")]
			nodes.append(String(map[old]))
		for c in graph.components:
			edges.append({"a":String(map[c.node_a]), "b":String(map[c.node_b]), "conductance":float(c.conductance), "material_tag":String(c.material_tag)})
		return {"nodes":nodes, "edges":edges, "boundary_nodes":boundary_nodes}
	var child_expanded := {}
	var keys: Array = children.keys(); keys.sort()
	for key in keys:
		var ex := _expand(children[key]); child_expanded[String(key)] = ex
		for n in ex.nodes: nodes.append(n)
		for e in ex.edges: edges.append(e)
	for topo in bundle.topology_edges:
		var a := ""
		var b := ""
		if topo.has("a"):
			var p := _boundary_index_from_name(String(topo.a))
			if p < 0: return {}
			a = boundary_nodes[p]
		else:
			a = String(child_expanded[String(topo.a_child)].boundary_nodes[int(topo.a_port)])
		b = String(child_expanded[String(topo.b_child)].boundary_nodes[int(topo.b_port)])
		edges.append({"a":a, "b":b, "conductance":float(topo.conductance), "material_tag":"material/hierarchy-connector"})
	return {"nodes":nodes, "edges":edges, "boundary_nodes":boundary_nodes}

static func expanded_graph(root: Dictionary) -> Dictionary:
	var ex := _expand(root)
	if ex.is_empty(): return {}
	var unique := {}
	for n in ex.nodes: unique[String(n)] = true
	var nodes: Array = unique.keys(); nodes.sort()
	var components: Array = []
	for index in range(ex.edges.size()):
		var e: Dictionary = ex.edges[index]
		components.append({"component_id":"component/r53-full-%06d" % index, "law_kind":Graph.LAW_KIND, "node_a":e.a, "node_b":e.b, "conductance":e.conductance, "material_tag":e.material_tag})
	var ports: Array = []
	for p in range(PORTS): ports.append({"port_id":"port/electrical-%s" % ["a","b","c","d"][p], "node_id":String(ex.boundary_nodes[p])})
	return Graph.create("graph/r5-3-expanded-oracle", nodes, ports, components)

static func excitation_set() -> Array:
	return [[12.0,-7.0,3.5,0.25], [1.0,0.0,0.0,0.0], [0.0,1.0,-1.0,0.0], [-4.25,2.75,8.5,-7.0], [100.0,100.0,100.0,100.0], [-25.0,14.0,3.0,8.0]]
