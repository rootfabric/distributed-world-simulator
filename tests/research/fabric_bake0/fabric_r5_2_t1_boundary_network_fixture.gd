extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/linear_conductance_component_graph_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const BoundaryContract = preload("res://scripts/research/fabric_bake0/physical_boundary_contract_v1.gd")
const DependencySet = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const ValidatedDomain = preload("res://scripts/research/fabric_bake0/validated_domain_v1.gd")
const ErrorEnvelope = preload("res://scripts/research/fabric_bake0/error_envelope_v1.gd")
const ConservationEnvelope = preload("res://scripts/research/fabric_bake0/conservation_envelope_v1.gd")

const BOUNDARY_COUNT := 4
const INTERNAL_NODE_COUNT := 128
const PIVOT_TOLERANCE := 1.0e-12
const SYMMETRY_TOLERANCE := 2.0e-12
const PASSIVITY_TOLERANCE := 2.0e-12
const GRAPH_COMPILER_DEPENDENCY := "FABRIC_R5_2_LINEAR_COMPONENT_GRAPH_COMPILER_R1"

static func h(value) -> String:
	return U.canonical_hash(value)

static func make_graph(
	mutation_revision: int = 0,
	singular: bool = false,
	negative: bool = false,
	reverse_input: bool = false
) -> Dictionary:
	var nodes: Array = [
		"node/boundary-a", "node/boundary-b", "node/boundary-c", "node/boundary-d",
	]
	for i in range(INTERNAL_NODE_COUNT):
		nodes.append("node/internal-%03d" % i)
	var ports: Array = []
	for suffix in ["a", "b", "c", "d"]:
		ports.append({"port_id": "port/electrical-%s" % suffix, "node_id": "node/boundary-%s" % suffix})
	var components: Array = []
	var connected := INTERNAL_NODE_COUNT - 1 if singular else INTERNAL_NODE_COUNT
	var cid := 0
	for i in range(maxi(0, connected - 1)):
		components.append(_component(cid, "node/internal-%03d" % i, "node/internal-%03d" % (i + 1),
			1.0 + 0.03 * float((i * 17) % 13)))
		cid += 1
	var offsets := [7, 23, 41]
	for i in range(connected):
		for offset in offsets:
			var j := (i + int(offset)) % connected
			if i == j:
				continue
			components.append(_component(cid, "node/internal-%03d" % i, "node/internal-%03d" % j,
				0.11 + 0.01 * float((i * 11 + int(offset)) % 17)))
			cid += 1
	for boundary_index in range(BOUNDARY_COUNT):
		for k in range(8):
			var internal_index := (boundary_index * 29 + k * 13) % connected
			var g := 0.7 + 0.04 * float(boundary_index + k + 1)
			if boundary_index == 0 and k == 0:
				g += 0.017 * float(mutation_revision)
			components.append(_component(
				cid,
				"node/boundary-%s" % ["a", "b", "c", "d"][boundary_index],
				"node/internal-%03d" % internal_index,
				g
			))
			cid += 1
	if negative and not components.is_empty():
		components[0].conductance = -1.0
	if reverse_input:
		nodes.reverse()
		ports.reverse()
		components.reverse()
	return Graph.create("graph/r5-t1-boundary-network", nodes, ports, components)

static func _component(index: int, a: String, b: String, conductance: float) -> Dictionary:
	return {
		"component_id": "component/conductor-%04d" % index,
		"law_kind": Graph.LAW_KIND,
		"node_a": a,
		"node_b": b,
		"conductance": conductance,
		"material_tag": "material/conductor-characterized",
	}

static func make_boundary_contract() -> Dictionary:
	var ports: Array = []
	for suffix in ["a", "b", "c", "d"]:
		ports.append({
			"port_id": "port/electrical-%s" % suffix,
			"physical_domain": "ELECTRICAL",
			"effort_quantity": "quantity/voltage",
			"flow_quantity": "quantity/current",
			"effort_dimension": [1, 2, -3, -1, 0, 0, 0],
			"flow_dimension": [0, 0, 0, 1, 0, 0, 0],
			"frame": "frame/electrical-reference",
			"orientation": "INTO_SUBSYSTEM",
			"conservation_group": "group/electrical-power",
			"event_observables": [],
		})
	return BoundaryContract.create(ports)

static func build(
	mutation_revision: int = 0,
	singular: bool = false,
	reverse_input: bool = false
) -> Dictionary:
	var graph := make_graph(mutation_revision, singular, false, reverse_input)
	if graph.is_empty():
		return {}
	var dependency_hash := h({"dependency": "r5.2-t1-canonical"})
	var construction := SourceRevision.create(
		"CONSTRUCTION", "construct/r5-t1-network", 9, 100 + mutation_revision,
		String(graph.graph_hash),
		dependency_hash
	)
	var matter := SourceRevision.create(
		"MATTER", "matter/r5-t1-support", 9, 3,
		h({"support": "r5-t1"}), dependency_hash
	)
	var frontier := Frontier.create([matter, construction])
	var construction_key := U.source_key("CONSTRUCTION", "construct/r5-t1-network")
	var matter_key := U.source_key("MATTER", "matter/r5-t1-support")
	var authority := AuthorityEnvelope.create(
		"server/fabric-r5",
		[
			{"source_domain": "MATTER", "source_id": "matter/r5-t1-support", "authority_epoch": 9, "owner_id": "server/fabric-r5"},
			{"source_domain": "CONSTRUCTION", "source_id": "construct/r5-t1-network", "authority_epoch": 9, "owner_id": "server/fabric-r5"},
		],
		[construction_key, matter_key]
	)
	var boundary := make_boundary_contract()
	var dependencies := DependencySet.create([
		{"dependency_id": "dependency/r5-linear-component-graph-compiler", "dependency_hash": h({"version": GRAPH_COMPILER_DEPENDENCY})},
		{"dependency_id": "dependency/material-characterized-conductance", "dependency_hash": h({"table": "r5-t1-characterized-v1"})},
	])
	var validated := ValidatedDomain.create(String(frontier.frontier_hash), String(graph.graph_hash), [], ["STEADY"], 0.0)
	var error_envelope := ErrorEnvelope.create(
		5.0e-12, 5.0e-12, 2.0e-11, 5.0e-12,
		5.0e-10, 1.0e-11, 0.0, 0.0,
		0.0, 0.0, 0.0, 1.0, true
	)
	var conservation := ConservationEnvelope.create(5.0e-10, 0.0, 0.0, 0.0, 0.0)
	var request := {
		"artifact_id": "bake/r5-t1-boundary-network",
		"canonical_source_frontier": frontier,
		"authority_envelope": authority,
		"dependency_set": dependencies,
		"fabric_graph_hash": String(graph.graph_hash),
		"fabric_compiler_version": GRAPH_COMPILER_DEPENDENCY,
		"boundary_contract": boundary,
		"bake_policy_hash": h({"policy": "r5-t1-exact-boundary-default"}),
		"validated_domain": validated,
		"error_envelope": error_envelope,
		"conservation_envelope": conservation,
		"build_generation": 1 + mutation_revision,
		"linear_system": {},
		"pivot_relative_tolerance": PIVOT_TOLERANCE,
		"symmetry_tolerance": SYMMETRY_TOLERANCE,
		"passivity_tolerance": PASSIVITY_TOLERANCE,
		"require_symmetric": true,
		"require_passive_laplacian": true,
	}
	return {
		"graph": graph,
		"construction": construction,
		"matter": matter,
		"frontier": frontier,
		"authority": authority,
		"boundary": boundary,
		"dependencies": dependencies,
		"request": request,
	}
