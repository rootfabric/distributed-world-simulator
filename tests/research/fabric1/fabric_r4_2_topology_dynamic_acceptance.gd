extends SceneTree

# R4.2 measurement/acceptance adapter. Independent expected values are generated
# by scripts/research/fabric_holdout_r42/r42.py from raw topology; this file does
# not contain topology-specific expected numbers or a solver.
const Bridge = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_canonical_bridge_v1.gd")
const C = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_compiler_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_graph_v1.gd")
const Mechanics = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_mechanics_v1.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Bond = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const Batch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")
const U = C.U

const ELECTRICAL_TOL := 1.0e-8
const MECHANICAL_TOL := 1.0e-8
const DYNAMIC_TOL := 1.5e-3
const FULL_BAKE_TOL := 1.0e-8
const LIFECYCLE_TIME_TOL := 3.0e-3
const NEAR_SINGULAR_MIN := 1.0e4

var assertions := 0
var failures: Array[String] = []
var family_results: Array = []

func _check(ok: bool, label: String, details = null) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label, " ", details)

func _near(actual: float, expected: float, tol: float) -> bool:
	return is_finite(actual) and is_finite(expected) and absf(actual - expected) <= tol * (1.0 + absf(expected))

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("R42_USAGE: <challenge.json>")
		quit(2)
		return
	var bundle = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not bundle is Dictionary or bundle.get("schema") != "fabric.holdout_r4_2.cases.v1" or not bundle.get("cases") is Array:
		push_error("R42_INVALID_BUNDLE")
		quit(2)
		return
	var expected_checksum := str(bundle.get("checksum", ""))
	_check(expected_checksum.length() == 64 and expected_checksum.to_lower() == expected_checksum, "R42 challenge checksum shape", expected_checksum)
	var seen := {}
	for row in bundle.cases:
		var case: Dictionary = row.case
		var input: Dictionary = row.runtime_input
		var reference: Dictionary = row.reference
		seen[str(case.family)] = true
		print("R42_CASE_BEGIN=", case.id, " FAMILY=", case.family)
		var result := _run_case(case, input, reference)
		print("R42_CASE_END=", case.id, " SUCCESS=", result.get("success", false))
		family_results.append(result)
		_check(bool(result.get("success", false)), "R42 family %s" % case.family, result)
	for family in [
		"electrical_chain_2port", "electrical_branch_3port", "electrical_cycle_4port",
		"mechanics_multi_dof", "near_singular_supported", "coupled_dynamic_trajectory",
		"canonical_lifecycle_rebake", "reject_floating_electrical",
		"reject_underdetermined_mechanics", "reject_noncollinear_mechanics"]:
		_check(seen.has(family), "R42 required family present: " + family)
	var result_hash := U.canonical_hash(family_results)
	print("FABRIC_R4_2_RESULT_HASH=", result_hash)
	print("FABRIC_R4_2_ASSERTIONS=", assertions, " FAILURES=", failures.size())
	if failures.is_empty():
		print("FABRIC-R4.2-TOPOLOGY-DYNAMIC-HOLDOUT: PASS")
		quit(0)
	else:
		print("FABRIC_R4_2_FAILURES=", JSON.stringify(failures))
		print("FABRIC-R4.2-TOPOLOGY-DYNAMIC-HOLDOUT: FAIL")
		quit(1)

func _run_case(case: Dictionary, input: Dictionary, reference: Dictionary) -> Dictionary:
	var sources := _sources(input)
	var authority := _authority(sources)
	var source_hash := U.canonical_hash(sources)
	var compiled: Dictionary = C.compile(sources, authority)
	if case.expectation == "REJECT_INVALID":
		var allowed: Array = reference.get("expected_error_codes", [])
		return {
			"family": case.family,
			"success": not compiled.success and allowed.has(str(compiled.get("error_code", ""))) and source_hash == U.canonical_hash(sources),
			"error_code": compiled.get("error_code", ""),
			"source_unchanged": source_hash == U.canonical_hash(sources),
		}
	if not compiled.success:
		return {"family": case.family, "success": false, "stage": "compile", "actual": compiled}
	var model: Dictionary = compiled.details.model
	var electrical := Graph.solve_resistive(model.electrical_model, model.boundary_voltages_v)
	if not electrical.success:
		return {"family": case.family, "success": false, "stage": "electrical", "actual": electrical}
	var mechanics := Mechanics.solve_mechanical_static(model.mechanical_model, str(model.coupler_node_id))
	if not mechanics.success:
		return {"family": case.family, "success": false, "stage": "mechanical", "actual": mechanics}
	var issues: Array[String] = []
	_compare_electrical(electrical.details, reference.electrical, issues)
	_compare_mechanical(mechanics.details, reference.mechanical, issues)
	if case.family == "near_singular_supported":
		var reference_condition := maxf(float(reference.electrical.condition_inf), float(reference.mechanical.condition_inf))
		if reference_condition < NEAR_SINGULAR_MIN: issues.append("NEAR_SINGULAR_REFERENCE_TOO_SMALL")
		if not _finite_recursive(electrical.details) or not _finite_recursive(mechanics.details): issues.append("NEAR_SINGULAR_NONFINITE")
	if case.phase == "DYNAMIC":
		_run_dynamic(sources, authority, input, reference, issues)
	elif case.phase == "LIFECYCLE":
		_run_lifecycle(sources, authority, input, reference, issues)
	return {"family": case.family, "success": issues.is_empty(), "issues": issues, "model_hash": U.canonical_hash(model)}

func _compare_electrical(actual: Dictionary, reference: Dictionary, issues: Array[String]) -> void:
	for pair in [["potentials_v", "part/"], ["port_currents_a", "part/"], ["edge_currents_a", "bond/"]]:
		var field: String = pair[0]
		var prefix: String = pair[1]
		var a: Dictionary = actual[field]
		var r: Dictionary = reference[field]
		if a.size() != r.size():
			issues.append("ELECTRICAL_COVERAGE_" + field)
			continue
		for key in r:
			var runtime_key := prefix + str(key)
			if not a.has(runtime_key) or not _near(float(a[runtime_key]), float(r[key]), ELECTRICAL_TOL):
				issues.append("ELECTRICAL_ORACLE_" + field + ":" + str(key))

func _compare_mechanical(actual: Dictionary, reference: Dictionary, issues: Array[String]) -> void:
	var a: Dictionary = actual.displacement_per_newton
	var r: Dictionary = reference.displacement_per_newton
	if a.size() != r.size(): issues.append("MECHANICAL_COVERAGE")
	for key in r:
		var runtime_key := "part/" + str(key)
		if not a.has(runtime_key) or not _near(float(a[runtime_key]), float(r[key]), MECHANICAL_TOL):
			issues.append("MECHANICAL_STATIC_ORACLE:" + str(key))

func _run_dynamic(sources: Dictionary, authority: Dictionary, input: Dictionary, reference: Dictionary, issues: Array[String]) -> void:
	var traces := {}
	for fidelity in ["FULL", "BAKE"]:
		var bridge = Bridge.new()
		var initialized: Dictionary = bridge.initialize(sources, authority)
		if not initialized.success:
			issues.append("DYNAMIC_INIT_" + fidelity)
			continue
		if fidelity == "BAKE":
			var baked := bridge.execute(bridge.make_command("fidelity", {"target": "BAKE", "certificate": {}}, authority), authority)
			if not baked.success:
				issues.append("DYNAMIC_BAKE_INIT")
				continue
		var samples: Array = []
		for step_index in range(int(input.steps)):
			var advanced := bridge.execute(bridge.make_command("advance", {"dt_s": input.dt_s}, authority), authority)
			if not advanced.success:
				issues.append("DYNAMIC_ADVANCE_%s_%d" % [fidelity, step_index])
				break
			var sample: Dictionary = bridge.inspect()
			if not sample.pending_proposal.is_empty(): issues.append("DYNAMIC_UNEXPECTED_FAILURE")
			samples.append(sample)
		traces[fidelity] = samples
		_compare_trajectory(samples, reference.trajectory.samples, issues, fidelity)
	if traces.has("FULL") and traces.has("BAKE") and traces.FULL.size() == traces.BAKE.size():
		for i in range(traces.FULL.size()):
			_compare_snapshots(traces.FULL[i], traces.BAKE[i], issues, i)

func _compare_trajectory(actual: Array, reference: Array, issues: Array[String], label: String) -> void:
	if actual.size() != reference.size():
		issues.append("DYNAMIC_SAMPLE_COUNT_" + label)
		return
	for i in range(reference.size()):
		var a: Dictionary = actual[i]
		var r: Dictionary = reference[i]
		if not _near(float(a.time_s), float(r.time_s), 1.0e-10): issues.append("DYNAMIC_TIME_" + label)
		if not _near(float(a.current_a), float(r.current_a), DYNAMIC_TOL): issues.append("DYNAMIC_CURRENT_%s_%d" % [label, i])
		for key in r.displacements_m:
			var rk := "part/" + str(key)
			if not _near(float(a.mechanical_observables.displacements_m.get(rk, INF)), float(r.displacements_m[key]), DYNAMIC_TOL): issues.append("DYNAMIC_X_%s_%d_%s" % [label, i, key])
			if not _near(float(a.mechanical_observables.velocities_m_per_s.get(rk, INF)), float(r.velocities_m_per_s[key]), DYNAMIC_TOL): issues.append("DYNAMIC_V_%s_%d_%s" % [label, i, key])

func _compare_snapshots(a: Dictionary, b: Dictionary, issues: Array[String], index: int) -> void:
	if not _near(float(a.current_a), float(b.current_a), FULL_BAKE_TOL): issues.append("FULL_BAKE_CURRENT_%d" % index)
	for key in a.mechanical_observables.displacements_m:
		if not _near(float(a.mechanical_observables.displacements_m[key]), float(b.mechanical_observables.displacements_m.get(key, INF)), FULL_BAKE_TOL): issues.append("FULL_BAKE_X_%d_%s" % [index, key])
		if not _near(float(a.mechanical_observables.velocities_m_per_s[key]), float(b.mechanical_observables.velocities_m_per_s.get(key, INF)), FULL_BAKE_TOL): issues.append("FULL_BAKE_V_%d_%s" % [index, key])

func _run_lifecycle(sources: Dictionary, authority: Dictionary, input: Dictionary, reference: Dictionary, issues: Array[String]) -> void:
	var bridge = Bridge.new()
	var initialized: Dictionary = bridge.initialize(sources, authority)
	if not initialized.success:
		issues.append("LIFECYCLE_INIT")
		return
	var baked := bridge.execute(bridge.make_command("fidelity", {"target": "BAKE", "certificate": {}}, authority), authority)
	if not baked.success:
		issues.append("LIFECYCLE_INITIAL_BAKE")
		return
	var saw_refinement := false
	for step_index in range(int(input.steps)):
		var before: Dictionary = bridge.inspect()
		var advanced := bridge.execute(bridge.make_command("advance", {"dt_s": input.dt_s}, authority), authority)
		if not advanced.success:
			issues.append("LIFECYCLE_ADVANCE_%d" % step_index)
			return
		var now: Dictionary = bridge.inspect()
		if str(now.fidelity) == "FULL" and str(before.fidelity) == "BAKE": saw_refinement = true
		if not now.pending_proposal.is_empty(): break
	var pending: Dictionary = bridge.inspect().pending_proposal
	if pending.is_empty():
		issues.append("LIFECYCLE_NO_PROPOSAL")
		return
	if not saw_refinement: issues.append("LIFECYCLE_NO_LOCAL_REFINEMENT")
	var expected_id := "bond/" + str(reference.lifecycle.failure_bond_id)
	if str(pending.bond_id) != expected_id: issues.append("LIFECYCLE_FAILURE_ID")
	if absf(float(pending.time_s) - float(reference.lifecycle.failure_time_s)) > LIFECYCLE_TIME_TOL: issues.append("LIFECYCLE_FAILURE_TIME")
	var saved_snapshot: Dictionary = bridge.inspect()
	var saved_canonical: Dictionary = bridge.canonical_state()
	var denied := bridge.execute(bridge.make_command("commit_failure", {"event_id": pending.event_id}, authority), authority, false)
	if denied.success or bridge.inspect() != saved_snapshot or bridge.canonical_state() != saved_canonical: issues.append("LIFECYCLE_DENIED_NOT_ATOMIC")
	var committed := bridge.execute(bridge.make_command("commit_failure", {"event_id": pending.event_id}, authority), authority)
	if not committed.success:
		issues.append("LIFECYCLE_CANONICAL_COMMIT")
		return
	var broken := false
	for bond in bridge.sources().mechanical.bonds:
		if str(bond.bond_id) == expected_id: broken = str(bond.state) == "BROKEN"
	if not broken: issues.append("LIFECYCLE_CANONICAL_BOND_NOT_BROKEN")
	var rebaked := bridge.execute(bridge.make_command("fidelity", {"target": "BAKE", "certificate": {}}, authority), authority)
	if not rebaked.success: issues.append("LIFECYCLE_REBAKE")
	for step_index in range(int(input.post_commit_steps)):
		var advanced := bridge.execute(bridge.make_command("advance", {"dt_s": input.dt_s}, authority), authority)
		if not advanced.success:
			issues.append("LIFECYCLE_CONTINUATION_%d" % step_index)
			break
		if not _finite_recursive(bridge.inspect()): issues.append("LIFECYCLE_NONFINITE_CONTINUATION")
	var document: Dictionary = bridge.export_replay()
	var replay = Bridge.new()
	var replayed := replay.replay(document, bridge.canonical_state(), {"mechanical_matter": bridge.sources().mechanical_matter, "electrical_matter": bridge.sources().electrical_matter}, authority, document.checksum)
	if not replayed.success or U.canonical_hash(replay.inspect()) != U.canonical_hash(bridge.inspect()): issues.append("LIFECYCLE_COLD_REPLAY")

func _sources(input: Dictionary) -> Dictionary:
	var result := {}
	for domain in ["mechanical", "electrical"]:
		var spec: Dictionary = input[domain]
		var parts: Array = []
		var bonds: Array = []
		var mass := 0.0
		for node in spec.nodes:
			var metadata := {"physics_r2_anchor": node.anchored} if domain == "mechanical" else {}
			parts.append(Part.create(node.id, "item/" + node.id, "BEAM", domain, node.mass_kg, node.position_m, metadata))
			mass += float(node.mass_kg)
		for edge in spec.edges:
			bonds.append(Bond.create(edge.id, edge.a, edge.b, edge.kind, edge.capacity_n, "INTACT", edge.metadata))
		var facets := {"composition_r3": input.controls} if domain == "mechanical" else {"composition_r3_boundary_voltages_v": input.ports}
		result[domain] = Snapshot.create("construct/r42-" + domain + "-" + str(input.id), "item/r42-" + domain + "-" + str(input.id), 1, "OPERATIONAL", parts, bonds, facets)
		result[domain + "_matter"] = Batch.create({"batch_id": "batch/r42-" + domain + "-" + str(input.id), "container_id": "container/r42-" + domain, "source_body_id": "body/r42", "source_operation_id": "operation/r42-" + domain + "-" + str(input.id), "total_mass_kg": mass, "bulk_volume_m3": mass * 0.001, "composition": Composition.create([{"material_id": spec.material, "mass_fraction": 1.0}]), "temperature_k": 293.15})
	return result

func _authority(sources: Dictionary) -> Dictionary:
	var records: Array = []
	var mutable: Array = []
	var readonly: Array = []
	for domain in ["mechanical", "electrical"]:
		var id: String = sources[domain].construct_id
		records.append({"source_domain": "CONSTRUCTION", "source_id": id, "authority_epoch": 42, "owner_id": "server/r42"})
		mutable.append(U.source_key("CONSTRUCTION", id))
		id = sources[domain + "_matter"].batch_id
		records.append({"source_domain": "MATTER", "source_id": id, "authority_epoch": 42, "owner_id": "server/r42"})
		readonly.append(U.source_key("MATTER", id))
	return C.A.create("server/r42", records, mutable, readonly)

func _finite_recursive(value) -> bool:
	match typeof(value):
		TYPE_FLOAT: return is_finite(float(value))
		TYPE_ARRAY:
			for v in value:
				if not _finite_recursive(v): return false
			return true
		TYPE_DICTIONARY:
			for k in value:
				if not _finite_recursive(value[k]): return false
			return true
		_: return true
