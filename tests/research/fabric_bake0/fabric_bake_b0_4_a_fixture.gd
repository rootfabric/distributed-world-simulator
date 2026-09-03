extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const BoundaryContract = preload("res://scripts/research/fabric_bake0/physical_boundary_contract_v1.gd")
const DependencySet = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const Model = preload("res://scripts/research/fabric_bake0/dynamic_full_model_descriptor_v1.gd")

const STATE_COUNT := 512
const VOLTAGE_DIM: Array = [1, 2, -3, -1, 0, 0, 0]
const CURRENT_DIM: Array = [0, 0, 0, 1, 0, 0, 0]
const CAPACITANCE_DIM: Array = [-1, -2, 4, 2, 0, 0, 0]
const CONDUCTANCE_DIM: Array = [-1, -2, 3, 2, 0, 0, 0]

static func build(initial_profile: String = "PATTERN") -> Dictionary:
	var states: Array = []
	var storage_nodes: Array = []
	var edges: Array = []
	var shunts: Array = []
	for index in range(STATE_COUNT):
		var state_id := _state_id(index)
		states.append({
			"state_id": state_id,
			"quantity_id": "quantity/electric-potential",
			"dimension": VOLTAGE_DIM.duplicate(true),
			"region_id": "region/dynamic/%02d" % int(index / 32),
		})
		storage_nodes.append({
			"state_id": state_id,
			"storage_coefficient": 1.0 + 0.002 * float(index % 17),
			"storage_coefficient_dimension": CAPACITANCE_DIM.duplicate(true),
			"initial_value": _initial_value(index, initial_profile),
		})
		shunts.append({
			"shunt_id": "shunt/dynamic/%04d" % index,
			"state_id": state_id,
			"conductance": 0.030 + 0.001 * float(index % 7),
			"conductance_dimension": CONDUCTANCE_DIM.duplicate(true),
		})
		if index + 1 < STATE_COUNT:
			edges.append({
				"edge_id": "edge/dynamic/%04d" % index,
				"state_a_id": state_id,
				"state_b_id": _state_id(index + 1),
				"conductance": 0.60 + 0.02 * float(index % 11),
				"conductance_dimension": CONDUCTANCE_DIM.duplicate(true),
			})

	var ports := _ports()
	var boundary := BoundaryContract.create(ports)
	var port_bindings: Array = []
	var binding_indices := [0, 170, 341, 511]
	for port_index in range(ports.size()):
		var port: Dictionary = ports[port_index]
		port_bindings.append({
			"port_id": String(port["port_id"]),
			"state_id": _state_id(int(binding_indices[port_index])),
			"frame": String(port["frame"]),
			"orientation": String(port["orientation"]),
			"reference_causalization": Model.REFERENCE_CAUSALIZATION,
		})

	var dependency_seed := {
		"fabric0_18_closure": "b9f4a11cb7c31e47884d12eaad2985811e0b6563",
		"b0_3_closure": "9575a63d6aeb4c455f8beade7588505e600c12d6",
		"b0_4_a_contract": "R1",
	}
	var dependency_hash := Utils.canonical_hash(dependency_seed)
	var source_payload := {
		"fixture": "b0.4-a-passive-scalar-path",
		"initial_profile": initial_profile,
		"state_count": STATE_COUNT,
		"states": states,
		"storage_nodes": storage_nodes,
		"edges": edges,
		"shunts": shunts,
		"boundary_contract_hash": boundary["contract_hash"],
	}
	var construction := SourceRevision.create(
		"CONSTRUCTION",
		"construct/b0-4-a-passive-network",
		11,
		41,
		Utils.canonical_hash({"construction": source_payload}),
		dependency_hash
	)
	var matter := SourceRevision.create(
		"MATTER",
		"matter/b0-4-a-passive-network",
		11,
		17,
		Utils.canonical_hash({"matter": "passive-linear-storage-r1"}),
		dependency_hash
	)
	var frontier := Frontier.create([matter, construction])
	var construction_key := Utils.source_key("CONSTRUCTION", String(construction["source_id"]))
	var matter_key := Utils.source_key("MATTER", String(matter["source_id"]))
	var authority := AuthorityEnvelope.create(
		"server/fabric-b04",
		[
			{
				"source_domain": "CONSTRUCTION",
				"source_id": String(construction["source_id"]),
				"authority_epoch": int(construction["authority_epoch"]),
				"owner_id": "server/fabric-b04",
			},
			{
				"source_domain": "MATTER",
				"source_id": String(matter["source_id"]),
				"authority_epoch": int(matter["authority_epoch"]),
				"owner_id": "server/fabric-b04",
			},
		],
		[construction_key, matter_key]
	)
	var dependencies := DependencySet.create([
		{
			"dependency_id": "dependency/b0-3-contact-wrench",
			"dependency_hash": Utils.canonical_hash({"closure": "9575a63d6aeb4c455f8beade7588505e600c12d6"}),
		},
		{
			"dependency_id": "dependency/fabric0-18-physical-core",
			"dependency_hash": Utils.canonical_hash({"closure": "b9f4a11cb7c31e47884d12eaad2985811e0b6563"}),
		},
		{
			"dependency_id": "dependency/full-reference-policy",
			"dependency_hash": Utils.canonical_hash({"solver": Model.SOLVER_METHOD, "revision": 1}),
		},
	])

	return {
		"construction": construction,
		"matter": matter,
		"frontier": frontier,
		"authority": authority,
		"boundary": boundary,
		"dependencies": dependencies,
		"states": states,
		"storage_nodes": storage_nodes,
		"edges": edges,
		"shunts": shunts,
		"port_bindings": port_bindings,
		"request": {
			"model_id": "dynamic-model/b0-4-a-passive-path",
			"canonical_source_frontier": frontier,
			"authority_envelope": authority,
			"dependency_set": dependencies,
			"boundary_contract": boundary,
			"states": states,
			"storage_nodes": storage_nodes,
			"edges": edges,
			"shunts": shunts,
			"port_bindings": port_bindings,
			"reference_solver": {
				"method": Model.SOLVER_METHOD,
				"max_step_s": 0.02,
			},
		},
	}

static func zero_flows(boundary: Dictionary) -> Dictionary:
	var output := {}
	for port in boundary["ports"]:
		output[String(port["port_id"])] = 0.0
	return output

static func reversed_request(fixture: Dictionary) -> Dictionary:
	var request: Dictionary = fixture["request"].duplicate(true)
	for field in ["states", "storage_nodes", "edges", "shunts", "port_bindings"]:
		var values: Array = request[field].duplicate(true)
		values.reverse()
		request[field] = values
	var ports: Array = request["boundary_contract"]["ports"].duplicate(true)
	ports.reverse()
	request["boundary_contract"] = BoundaryContract.create(ports)
	return request

static func _ports() -> Array:
	return [
		{
			"port_id": "port/electrical/000-left",
			"physical_domain": "ELECTRICAL",
			"effort_quantity": "quantity/electric-potential",
			"flow_quantity": "quantity/electric-current",
			"effort_dimension": VOLTAGE_DIM.duplicate(true),
			"flow_dimension": CURRENT_DIM.duplicate(true),
			"frame": "frame/electrical/reference",
			"orientation": "INTO_SUBSYSTEM",
			"conservation_group": "group/electrical/power",
			"event_observables": [],
		},
		{
			"port_id": "port/electrical/170-mid-a",
			"physical_domain": "ELECTRICAL",
			"effort_quantity": "quantity/electric-potential",
			"flow_quantity": "quantity/electric-current",
			"effort_dimension": VOLTAGE_DIM.duplicate(true),
			"flow_dimension": CURRENT_DIM.duplicate(true),
			"frame": "frame/electrical/reference",
			"orientation": "INTO_SUBSYSTEM",
			"conservation_group": "group/electrical/power",
			"event_observables": [],
		},
		{
			"port_id": "port/electrical/341-mid-b",
			"physical_domain": "ELECTRICAL",
			"effort_quantity": "quantity/electric-potential",
			"flow_quantity": "quantity/electric-current",
			"effort_dimension": VOLTAGE_DIM.duplicate(true),
			"flow_dimension": CURRENT_DIM.duplicate(true),
			"frame": "frame/electrical/reference",
			"orientation": "OUT_OF_SUBSYSTEM",
			"conservation_group": "group/electrical/power",
			"event_observables": [],
		},
		{
			"port_id": "port/electrical/511-right",
			"physical_domain": "ELECTRICAL",
			"effort_quantity": "quantity/electric-potential",
			"flow_quantity": "quantity/electric-current",
			"effort_dimension": VOLTAGE_DIM.duplicate(true),
			"flow_dimension": CURRENT_DIM.duplicate(true),
			"frame": "frame/electrical/reference",
			"orientation": "OUT_OF_SUBSYSTEM",
			"conservation_group": "group/electrical/power",
			"event_observables": [],
		},
	]

static func _state_id(index: int) -> String:
	return "state/dynamic/%04d" % index

static func _initial_value(index: int, profile: String) -> float:
	match profile:
		"ZERO":
			return 0.0
		"POSITIVE":
			return 1.0
		_:
			return 0.30 * float((index * 37) % 19 - 9) / 9.0
