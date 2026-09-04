extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Fixture = preload("res://scripts/research/fabric_bake0/complex2_modular_machine_fixture_v1.gd")
const Complex1A = preload("res://tests/research/fabric_bake0/fabric_bake_complex1a_fixture.gd")

const SCHEMA := "planet_simulator.fabric_complex2_independent_structural_failure.v1"
const BACKEND_CONTRACT_ID := "COMPLEX2D_REDUNDANT_STRUCTURAL_LOAD_PATH_R1"
const EVENT_ID := "event/complex2d-independent-brace-failure"
const FAILURE_SUPPORT_ID := "brace/complex2-12-16"
const LOAD_NODE_ID := "module/complex2-16"
const ANCHOR_NODE_ID := "module/complex2-12"
const TEST_LOAD_N := 100.0
const MAX_CERTIFIED_LOAD_N := 150.0
const MAX_CERTIFIED_TIP_DEFLECTION_M := 0.40
const NODE_IDS := [
	"module/complex2-12",
	"module/complex2-13",
	"module/complex2-14",
	"module/complex2-15",
	"module/complex2-16",
]
const EDGE_SPECS := [
	["support/complex2-12-13", "module/complex2-12", "module/complex2-13", 1200.0, "CHAIN"],
	["support/complex2-13-14", "module/complex2-13", "module/complex2-14", 1350.0, "CHAIN"],
	["support/complex2-14-15", "module/complex2-14", "module/complex2-15", 1275.0, "CHAIN"],
	["support/complex2-15-16", "module/complex2-15", "module/complex2-16", 1175.0, "CHAIN"],
	[FAILURE_SUPPORT_ID, "module/complex2-12", "module/complex2-16", 500.0, "BRACE"],
]

static func backend_family_hash() -> String:
	return Utils.canonical_hash({
		"backend_contract_id": BACKEND_CONTRACT_ID,
		"nodes": NODE_IDS,
		"edge_specs": EDGE_SPECS,
		"failure_support_id": FAILURE_SUPPORT_ID,
	})

static func compile_from_machine(machine: Dictionary) -> Dictionary:
	if not bool(machine.get("success", false)):
		return _failure("COMPLEX2D_MACHINE_REQUIRED")
	var modules_by_id := {}
	for module in machine.get("modules", []):
		modules_by_id[String(module["module_id"])] = module
	for node_id in NODE_IDS:
		if not modules_by_id.has(node_id):
			return _failure("COMPLEX2D_NODE_MISSING", {"node_id": node_id})
	var supports_by_id := {}
	for support in machine.get("supports", []):
		supports_by_id[String(support["support_id"])] = support
	var edges: Array = []
	for spec in EDGE_SPECS:
		var support_id := String(spec[0])
		if not supports_by_id.has(support_id):
			return _failure("COMPLEX2D_CANONICAL_SUPPORT_MISSING", {"support_id": support_id})
		var canonical: Dictionary = supports_by_id[support_id]
		if String(canonical["module_a"]) != String(spec[1]) or String(canonical["module_b"]) != String(spec[2]):
			return _failure("COMPLEX2D_CANONICAL_SUPPORT_ENDPOINT_MISMATCH", {"support_id": support_id})
		edges.append({
			"support_id": support_id,
			"module_a": String(spec[1]),
			"module_b": String(spec[2]),
			"stiffness_n_per_m": float(spec[3]),
			"role": String(spec[4]),
			"active": bool(canonical["active"]),
		})
	var value := {
		"success": true,
		"schema": SCHEMA,
		"backend_contract_id": BACKEND_CONTRACT_ID,
		"node_ids": NODE_IDS.duplicate(),
		"anchor_node_id": ANCHOR_NODE_ID,
		"load_node_id": LOAD_NODE_ID,
		"failure_support_id": FAILURE_SUPPORT_ID,
		"edges": edges,
		"backend_family_hash": backend_family_hash(),
		"topology_hash": "",
	}
	value["topology_hash"] = Utils.canonical_hash({
		"node_ids": value["node_ids"],
		"edges": value["edges"],
	})
	return value

static func solve_static(assembly: Dictionary, load_n: float) -> Dictionary:
	if String(assembly.get("schema", "")) != SCHEMA:
		return _failure("COMPLEX2D_ASSEMBLY_SCHEMA_MISMATCH")
	if not is_finite(load_n) or load_n <= 0.0:
		return _failure("COMPLEX2D_INVALID_LOAD")
	if load_n > MAX_CERTIFIED_LOAD_N:
		return _failure("COMPLEX2D_REFINEMENT_REQUIRED_LOAD")
	var unknown_ids: Array = []
	for node_id in assembly["node_ids"]:
		if String(node_id) != ANCHOR_NODE_ID:
			unknown_ids.append(String(node_id))
	var index_by_id := {}
	for index in range(unknown_ids.size()):
		index_by_id[String(unknown_ids[index])] = index
	var matrix: Array = []
	var rhs: Array = []
	for row in range(unknown_ids.size()):
		var values: Array = []
		values.resize(unknown_ids.size())
		values.fill(0.0)
		matrix.append(values)
		rhs.append(load_n if String(unknown_ids[row]) == LOAD_NODE_ID else 0.0)
	for edge in assembly["edges"]:
		if not bool(edge["active"]):
			continue
		var a := String(edge["module_a"])
		var b := String(edge["module_b"])
		var k := float(edge["stiffness_n_per_m"])
		var a_unknown := index_by_id.has(a)
		var b_unknown := index_by_id.has(b)
		if a_unknown:
			var ia := int(index_by_id[a])
			matrix[ia][ia] = float(matrix[ia][ia]) + k
		if b_unknown:
			var ib := int(index_by_id[b])
			matrix[ib][ib] = float(matrix[ib][ib]) + k
		if a_unknown and b_unknown:
			var ia2 := int(index_by_id[a])
			var ib2 := int(index_by_id[b])
			matrix[ia2][ib2] = float(matrix[ia2][ib2]) - k
			matrix[ib2][ia2] = float(matrix[ib2][ia2]) - k
	var solved := _solve_linear(matrix, rhs)
	if not bool(solved.get("success", false)):
		return solved
	var displacement := {ANCHOR_NODE_ID: 0.0}
	for index in range(unknown_ids.size()):
		displacement[String(unknown_ids[index])] = float(solved["x"][index])
	var edge_forces := {}
	var brace_force := 0.0
	var max_chain_force := 0.0
	var strain_energy := 0.0
	var anchor_support_force := 0.0
	for edge in assembly["edges"]:
		var support_id := String(edge["support_id"])
		var force := 0.0
		if bool(edge["active"]):
			var a := String(edge["module_a"])
			var b := String(edge["module_b"])
			var k := float(edge["stiffness_n_per_m"])
			var delta := float(displacement[b]) - float(displacement[a])
			force = k * delta
			strain_energy += 0.5 * k * delta * delta
			if a == ANCHOR_NODE_ID:
				anchor_support_force += force
			elif b == ANCHOR_NODE_ID:
				anchor_support_force -= force
		edge_forces[support_id] = force
		if String(edge["role"]) == "BRACE":
			brace_force = absf(force)
		else:
			max_chain_force = maxf(max_chain_force, absf(force))
	var tip := float(displacement[LOAD_NODE_ID])
	if absf(tip) > MAX_CERTIFIED_TIP_DEFLECTION_M:
		return _failure("COMPLEX2D_REFINEMENT_REQUIRED_DEFLECTION", {"tip_deflection_m": tip})
	var equilibrium_residual := absf(anchor_support_force - load_n)
	var work_identity_residual := absf(2.0 * strain_energy - load_n * tip)
	return {
		"success": true,
		"load_n": load_n,
		"displacement_m": displacement,
		"tip_deflection_m": tip,
		"edge_force_n": edge_forces,
		"brace_force_n": brace_force,
		"max_chain_force_n": max_chain_force,
		"anchor_support_force_n": anchor_support_force,
		"strain_energy_j": strain_energy,
		"equilibrium_residual_n": equilibrium_residual,
		"work_identity_residual_j": work_identity_residual,
		"state_hash": Utils.canonical_hash({
			"displacement_m": displacement,
			"edge_force_n": edge_forces,
			"load_n": load_n,
		}),
	}

static func apply_independent_failure(machine: Dictionary, event_id: String = EVENT_ID) -> Dictionary:
	if event_id.is_empty():
		return _failure("COMPLEX2D_EVENT_ID_REQUIRED")
	if event_id == Fixture.EVENT_DETACH or event_id == Fixture.EVENT_SECOND:
		return _failure("COMPLEX2D_FAILURE_NOT_INDEPENDENT")
	if Array(machine.get("applied_event_ids", [])).has(event_id):
		return _failure("COMPLEX2D_EVENT_ALREADY_APPLIED", {"event_id": event_id})
	if FAILURE_SUPPORT_ID == Fixture.DETACH_SUPPORT_ID or FAILURE_SUPPORT_ID == Fixture.SECOND_SUPPORT_ID:
		return _failure("COMPLEX2D_SUPPORT_NOT_INDEPENDENT")
	var next := machine.duplicate(true)
	var found := false
	for index in range(next["supports"].size()):
		var support: Dictionary = next["supports"][index]
		if String(support["support_id"]) != FAILURE_SUPPORT_ID:
			continue
		found = true
		if not bool(support["active"]):
			return _failure("COMPLEX2D_SUPPORT_ALREADY_FAILED")
		support["active"] = false
		next["supports"][index] = support
		break
	if not found:
		return _failure("COMPLEX2D_FAILURE_SUPPORT_NOT_FOUND")
	next["revision"] = int(next["revision"]) + 1
	next["applied_event_ids"].append(event_id)
	next["applied_event_ids"].sort()
	return {
		"success": true,
		"subject": next,
		"event_id": event_id,
		"support_id": FAILURE_SUPPORT_ID,
	}

static func run_failure(machine: Dictionary) -> Dictionary:
	var before_assembly := compile_from_machine(machine)
	if not bool(before_assembly.get("success", false)):
		return before_assembly
	var before := solve_static(before_assembly, TEST_LOAD_N)
	if not bool(before.get("success", false)):
		return before
	var functional_before := Complex1A.solve(machine["functional_subject"])
	if not bool(functional_before.get("success", false)):
		return _failure("COMPLEX2D_FUNCTIONAL_BASELINE_FAILED", functional_before)
	var broken := apply_independent_failure(machine)
	if not bool(broken.get("success", false)):
		return broken
	var failed_machine: Dictionary = broken["subject"]
	var after_assembly := compile_from_machine(failed_machine)
	if not bool(after_assembly.get("success", false)):
		return after_assembly
	var after := solve_static(after_assembly, TEST_LOAD_N)
	if not bool(after.get("success", false)):
		return after
	var functional_after := Complex1A.solve(failed_machine["functional_subject"])
	if not bool(functional_after.get("success", false)):
		return _failure("COMPLEX2D_FUNCTIONAL_AFTER_FAILED", functional_after)
	var components := _components(failed_machine)
	var duplicate := apply_independent_failure(failed_machine)
	var over_load := solve_static(after_assembly, MAX_CERTIFIED_LOAD_N + 1.0)
	var result := {
		"success": true,
		"schema": SCHEMA,
		"backend_contract_id": BACKEND_CONTRACT_ID,
		"event_id": EVENT_ID,
		"failure_support_id": FAILURE_SUPPORT_ID,
		"machine_before_revision": int(machine["revision"]),
		"machine_after_revision": int(failed_machine["revision"]),
		"before": before,
		"after": after,
		"before_topology_hash": String(before_assembly["topology_hash"]),
		"after_topology_hash": String(after_assembly["topology_hash"]),
		"component_count_after": components.size(),
		"components_after": components,
		"functional_before_hash": Utils.canonical_hash(functional_before),
		"functional_after_hash": Utils.canonical_hash(functional_after),
		"functional_subject_hash_before": Utils.canonical_hash(machine["functional_subject"]),
		"functional_subject_hash_after": Utils.canonical_hash(failed_machine["functional_subject"]),
		"duplicate_error": String(duplicate.get("error_code", "")),
		"over_load_error": String(over_load.get("error_code", "")),
		"tip_deflection_ratio": absf(float(after["tip_deflection_m"])) / maxf(absf(float(before["tip_deflection_m"])), 1.0e-15),
		"chain_force_ratio": float(after["max_chain_force_n"]) / maxf(float(before["max_chain_force_n"]), 1.0e-15),
		"failed_machine": failed_machine,
		"experiment_hash": "",
	}
	result["experiment_hash"] = Utils.canonical_hash({
		"event_id": EVENT_ID,
		"before_state_hash": before["state_hash"],
		"after_state_hash": after["state_hash"],
		"component_count_after": result["component_count_after"],
		"functional_after_hash": result["functional_after_hash"],
	})
	return result

static func _components(machine: Dictionary) -> Array:
	var adjacency := {}
	for module in machine["modules"]:
		adjacency[String(module["module_id"])] = []
	for support in machine["supports"]:
		if not bool(support["active"]):
			continue
		var a := String(support["module_a"])
		var b := String(support["module_b"])
		adjacency[a].append(b)
		adjacency[b].append(a)
	var ids: Array = adjacency.keys()
	ids.sort()
	var visited := {}
	var result: Array = []
	for start in ids:
		if visited.has(start):
			continue
		var queue: Array = [String(start)]
		visited[String(start)] = true
		var component: Array = []
		while not queue.is_empty():
			var current := String(queue.pop_front())
			component.append(current)
			var neighbors: Array = Array(adjacency[current]).duplicate()
			neighbors.sort()
			for neighbor in neighbors:
				var next_id := String(neighbor)
				if visited.has(next_id):
					continue
				visited[next_id] = true
				queue.append(next_id)
		component.sort()
		result.append(component)
	result.sort_custom(func(a: Array, b: Array) -> bool: return String(a[0]) < String(b[0]))
	return result

static func _solve_linear(matrix: Array, rhs: Array) -> Dictionary:
	var n := rhs.size()
	var a: Array = []
	for row in range(n):
		var values: Array = Array(matrix[row]).duplicate()
		values.append(float(rhs[row]))
		a.append(values)
	for col in range(n):
		var pivot := col
		var best := absf(float(a[col][col]))
		for row in range(col + 1, n):
			var candidate := absf(float(a[row][col]))
			if candidate > best:
				best = candidate
				pivot = row
		if best <= 1.0e-14:
			return _failure("COMPLEX2D_SINGULAR_STRUCTURAL_SYSTEM")
		if pivot != col:
			var temp = a[col]
			a[col] = a[pivot]
			a[pivot] = temp
		var diagonal := float(a[col][col])
		for j in range(col, n + 1):
			a[col][j] = float(a[col][j]) / diagonal
		for row in range(n):
			if row == col:
				continue
			var factor := float(a[row][col])
			if absf(factor) <= 1.0e-18:
				continue
			for j in range(col, n + 1):
				a[row][j] = float(a[row][j]) - factor * float(a[col][j])
	var x: Array = []
	for row in range(n):
		x.append(float(a[row][n]))
	return {"success": true, "x": x}

static func _failure(error_code: String, details = null) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}
