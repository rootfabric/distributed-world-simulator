extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const BoundaryContract = preload("res://scripts/research/fabric_bake0/physical_boundary_contract_v1.gd")
const DependencySet = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const ValidatedDomain = preload("res://scripts/research/fabric_bake0/validated_domain_v1.gd")
const ErrorEnvelope = preload("res://scripts/research/fabric_bake0/error_envelope_v1.gd")
const ConservationEnvelope = preload("res://scripts/research/fabric_bake0/conservation_envelope_v1.gd")
const LinearSystem = preload("res://scripts/research/fabric_bake0/linear_boundary_system_v1.gd")

const BOUNDARY_COUNT := 4
const INTERNAL_COUNT := 128
const PIVOT_TOLERANCE := 1.0e-12
const SYMMETRY_TOLERANCE := 2.0e-12
const PASSIVITY_TOLERANCE := 2.0e-12

static func h(value) -> String:
	return Utils.canonical_hash(value)

static func build(mutation_revision: int = 0) -> Dictionary:
	var source_dependency_hash := h({"dependency": "b0.1-canonical-source"})
	var construction := SourceRevision.create(
		"CONSTRUCTION", "construct/b0-1-network", 7, 20 + mutation_revision,
		h({"construction": "b0.1-network", "mutation_revision": mutation_revision}),
		source_dependency_hash
	)
	var matter := SourceRevision.create(
		"MATTER", "matter/b0-1-region", 7, 5,
		h({"matter": "b0.1-region"}), source_dependency_hash
	)
	var frontier := Frontier.create([matter, construction])
	var construction_key := Utils.source_key("CONSTRUCTION", "construct/b0-1-network")
	var matter_key := Utils.source_key("MATTER", "matter/b0-1-region")
	var authority := AuthorityEnvelope.create(
		"server/bake-alpha",
		[
			{"source_domain": "MATTER", "source_id": "matter/b0-1-region", "authority_epoch": 7, "owner_id": "server/bake-alpha"},
			{"source_domain": "CONSTRUCTION", "source_id": "construct/b0-1-network", "authority_epoch": 7, "owner_id": "server/bake-alpha"},
		],
		[construction_key, matter_key]
	)
	var boundary := make_boundary_contract()
	var dependencies := DependencySet.create([
		{"dependency_id": "dependency/fabric-linear-core", "dependency_hash": h({"fabric": "0.5-linear"})},
		{"dependency_id": "dependency/material-conductance", "dependency_hash": h({"table": "conductance-v1"})},
	])
	var linear_system := make_linear_system(INTERNAL_COUNT, mutation_revision)
	var fabric_graph_hash := h({
		"fixture": "b0.1-exact-boundary",
		"mutation_revision": mutation_revision,
		"linear_system_hash": linear_system["system_hash"],
	})
	var validated := ValidatedDomain.create(
		String(frontier["frontier_hash"]), fabric_graph_hash, [], ["STEADY"], 0.0
	)
	var error_envelope := ErrorEnvelope.create(
		5.0e-12, 5.0e-12, 2.0e-11, 5.0e-12,
		5.0e-10, 1.0e-11, 0.0, 0.0,
		0.0, 0.0, 0.0, 1.0, true
	)
	var conservation := ConservationEnvelope.create(5.0e-10, 0.0, 0.0, 0.0, 0.0)
	var request := {
		"artifact_id": "bake/b0-1-exact-boundary",
		"canonical_source_frontier": frontier,
		"authority_envelope": authority,
		"dependency_set": dependencies,
		"fabric_graph_hash": fabric_graph_hash,
		"fabric_compiler_version": "FABRIC0.15/a8ff0d7-linear-substrate",
		"boundary_contract": boundary,
		"bake_policy_hash": h({"policy": "b0.1-exact-default"}),
		"validated_domain": validated,
		"error_envelope": error_envelope,
		"conservation_envelope": conservation,
		"build_generation": 1 + mutation_revision,
		"linear_system": linear_system,
		"pivot_relative_tolerance": PIVOT_TOLERANCE,
		"symmetry_tolerance": SYMMETRY_TOLERANCE,
		"passivity_tolerance": PASSIVITY_TOLERANCE,
		"require_symmetric": true,
		"require_passive_laplacian": true,
	}
	return {
		"construction": construction,
		"matter": matter,
		"frontier": frontier,
		"authority": authority,
		"boundary": boundary,
		"dependencies": dependencies,
		"linear_system": linear_system,
		"fabric_graph_hash": fabric_graph_hash,
		"request": request,
	}

static func make_boundary_contract(flow_dimension_override: Array = []) -> Dictionary:
	var flow_dimension: Array = flow_dimension_override.duplicate() if not flow_dimension_override.is_empty() else [0, 0, 0, 1, 0, 0, 0]
	var ports: Array = []
	for suffix in ["a", "b", "c", "d"]:
		ports.append({
			"port_id": "port/electrical-%s" % suffix,
			"physical_domain": "ELECTRICAL",
			"effort_quantity": "quantity/voltage",
			"flow_quantity": "quantity/current",
			"effort_dimension": [1, 2, -3, -1, 0, 0, 0],
			"flow_dimension": flow_dimension,
			"frame": "frame/electrical-reference",
			"orientation": "INTO_SUBSYSTEM",
			"conservation_group": "group/electrical-power",
			"event_observables": [],
		})
	return BoundaryContract.create(ports)

static func make_linear_system(
	internal_count: int = INTERNAL_COUNT, mutation_revision: int = 0,
	singular: bool = false, non_passive: bool = false, reverse_input: bool = false
) -> Dictionary:
	var total: int = BOUNDARY_COUNT + internal_count
	var matrix: Array = []
	for row_index in range(total):
		var row: Array = []
		row.resize(total)
		row.fill(0.0)
		matrix.append(row)

	var connected_internal_count: int = internal_count - 1 if singular else internal_count
	for index in range(maxi(0, connected_internal_count - 1)):
		_add_edge(
			matrix, BOUNDARY_COUNT + index, BOUNDARY_COUNT + index + 1,
			1.0 + float((index * 17) % 11) * 0.07
		)
	for index in range(connected_internal_count):
		var neighbor: int = (index + 9) % connected_internal_count if connected_internal_count > 0 else 0
		if index < neighbor:
			_add_edge(
				matrix, BOUNDARY_COUNT + index, BOUNDARY_COUNT + neighbor,
				0.15 + float((index * 13) % 7) * 0.03
			)
	for boundary_index in range(BOUNDARY_COUNT):
		for k in range(4):
			var internal_index: int = (boundary_index * 31 + k * 17) % connected_internal_count
			var mutation_delta := 0.013 * float(mutation_revision) if boundary_index == 0 and k == 0 else 0.0
			_add_edge(
				matrix, boundary_index, BOUNDARY_COUNT + internal_index,
				0.8 + 0.11 * float(boundary_index + k + 1) + mutation_delta
			)
	if non_passive and connected_internal_count > 2:
		_add_edge(matrix, BOUNDARY_COUNT, BOUNDARY_COUNT + 2, -3.0)

	var boundary_ids: Array = [
		"port/electrical-a", "port/electrical-b", "port/electrical-c", "port/electrical-d",
	]
	var internal_ids: Array = []
	for index in range(internal_count):
		internal_ids.append("node/internal-%03d" % index)
	if reverse_input:
		boundary_ids.reverse()
		internal_ids.reverse()
		matrix = _reverse_group_order(matrix, BOUNDARY_COUNT, internal_count)
	var rhs: Array = []
	rhs.resize(total)
	rhs.fill(0.0)
	return LinearSystem.create(
		"system/b0-1-passive-network", boundary_ids, internal_ids, matrix, rhs
	)

static func live_context(artifact: Dictionary, invalidations: Array = []) -> Dictionary:
	return {
		"artifact_state": "READY",
		"canonical_source_frontier": artifact["source_binding"]["canonical_source_frontier"].duplicate(true),
		"authority_envelope": artifact["source_binding"]["authority_envelope"].duplicate(true),
		"dependency_set": artifact["source_binding"]["dependency_set"].duplicate(true),
		"fabric_graph_hash": artifact["source_binding"]["fabric_graph_hash"],
		"fabric_compiler_version": artifact["source_binding"]["fabric_compiler_version"],
		"boundary_contract_hash": artifact["source_binding"]["boundary_contract_hash"],
		"bake_policy_hash": artifact["source_binding"]["bake_policy_hash"],
		"runtime_domain": {
			"source_frontier_hash": artifact["source_binding"]["frontier_hash"],
			"fabric_graph_hash": artifact["source_binding"]["fabric_graph_hash"],
			"elapsed_s": 0.0,
			"mode": "STEADY",
			"quantities": {},
		},
		"runtime_error_estimator": {},
		"guard_values": {},
		"invalidations": invalidations.duplicate(true),
	}

static func _add_edge(matrix: Array, a: int, b: int, conductance: float) -> void:
	matrix[a][a] = float(matrix[a][a]) + conductance
	matrix[b][b] = float(matrix[b][b]) + conductance
	matrix[a][b] = float(matrix[a][b]) - conductance
	matrix[b][a] = float(matrix[b][a]) - conductance

static func _reverse_group_order(matrix: Array, boundary_count: int, internal_count: int) -> Array:
	var permutation: Array = []
	for index in range(boundary_count):
		permutation.append(boundary_count - 1 - index)
	for index in range(internal_count):
		permutation.append(boundary_count + internal_count - 1 - index)
	var output: Array = []
	for source_row in permutation:
		var row: Array = []
		for source_column in permutation:
			row.append(matrix[source_row][source_column])
		output.append(row)
	return output
