extends SceneTree

const B = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_canonical_bridge_v1.gd")
const F = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_fixture_v1.gd")
const C = F.C
const U = C.U
var failures: Array[String] = []
var assertions := 0

func _initialize() -> void:
	_analytic_and_convergence()
	_feedback_and_metamorphics()
	_fidelity_and_failure()
	_guard_unload_and_regeneration()
	_negative_and_replay()
	_contract_edges()
	print("R3_ASSERTIONS=", assertions, " FAILURES=", failures.size())
	if not failures.is_empty():
		print("R3_FAILURES=", JSON.stringify(failures))
		print("FABRIC-COMPOSITION-R3: FAIL")
		quit(1)
	else:
		print("FABRIC-COMPOSITION-R3: PASS")
		quit(0)

func _check(ok: bool, label: String, detail = null) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label, " ", detail)

func _new(options: Dictionary = {}) -> Dictionary:
	var s := F.create(options)
	var a := F.authority(s)
	var b = B.new()
	var result: Dictionary = b.initialize(s, a)
	_check(result.success, "initialize " + str(options), result)
	return {"b": b, "a": a, "sources": s}

func _command(case: Dictionary, action: String, payload: Dictionary) -> Dictionary:
	return case.b.execute(case.b.make_command(action, payload, case.a), case.a)

func _run(case: Dictionary, steps: int, dt: float) -> Dictionary:
	for i in range(steps):
		var result := _command(case, "advance", {"dt_s": dt})
		if not result.success:
			_check(false, "advance step %d" % i, result)
			return case.b.inspect()
	return case.b.inspect()

# Closed-form underdamped oscillator, independently parameterized from fixture
# inputs. No compiler output, numerical integrator or runtime coefficient oracle.
func _analytic(t: float, mass: float = 2.0, stiffness: float = 50.0, damping: float = 1.5, resistance: float = 4.0, coupling: float = 2.0, voltage: float = 12.0, external: float = 0.0) -> Dictionary:
	var alpha := (damping + coupling * coupling / resistance) / (2.0 * mass)
	var omega := sqrt(stiffness / mass - alpha * alpha)
	var equilibrium := (coupling * voltage / resistance + external) / stiffness
	var x := equilibrium * (1.0 - exp(-alpha * t) * (cos(omega * t) + alpha / omega * sin(omega * t)))
	var v := equilibrium * exp(-alpha * t) * stiffness / mass / omega * sin(omega * t)
	return {"x": x, "v": v, "i": (voltage - coupling * v) / resistance}

func _analytic_and_convergence() -> void:
	var errors: Array = []
	var energy_errors: Array = []
	for dt in [0.0125, 0.00625, 0.003125]:
		var case := _new({"capacity": [1000.0, 1000.0]})
		var result := _run(case, int(round(0.5 / dt)), dt)
		var exact := _analytic(0.5)
		var error := absf(float(result.displacement_m) - exact.x) + absf(float(result.velocity_m_per_s) - exact.v)
		errors.append(error)
		energy_errors.append(absf(result.energy_residual_j))
		_check(error < 2.0e-6, "analytic trajectory", error)
		_check(absf(float(result.current_a) - exact.i) < 2.0e-6, "analytic current")
		_check(absf(float(result.energy_residual_j)) < 2.0e-6, "energy work balance", result.energy_residual_j)
		_check(absf(float(result.constraint_residual_v)) < 1.0e-9, "actual DAE algebraic constraint")
		_check(absf(float(result.coupler_power_residual_w)) < 1.0e-12, "power-conserving gyrator")
	print("R3_CONVERGENCE_ERRORS=", errors, " ENERGY_ERRORS=", energy_errors)
	_check(float(errors[0]) > 10.0 * float(errors[1]) and float(errors[1]) > 10.0 * float(errors[2]), "fourth-order timestep convergence", errors)
	_check(float(energy_errors[0]) > 8.0 * float(energy_errors[1]), "energy residual convergence", energy_errors)

func _feedback_and_metamorphics() -> void:
	var baseline := _new({"capacity": [1000.0, 1000.0]})
	var loaded := _new({"capacity": [1000.0, 1000.0], "load_resistance_ohm": 7.0})
	var opposed := _new({"capacity": [1000.0, 1000.0], "force_n": -2.0})
	var base := _run(baseline, 20, 0.01)
	var electric := _run(loaded, 20, 0.01)
	var mechanical := _run(opposed, 20, 0.01)
	_check(electric.velocity_m_per_s < base.velocity_m_per_s and electric.current_a < base.current_a, "electrical load changes motion")
	_check(mechanical.velocity_m_per_s < base.velocity_m_per_s and mechanical.current_a > base.current_a, "mechanical load changes current")
	var exact := _analytic(0.2, 2.0, 50.0, 1.5, 8.0)
	_check(absf(float(electric.velocity_m_per_s) - exact.v) < 1.0e-6, "loaded analytical reference")
	var moved := _new({"capacity": [1000.0, 1000.0], "label": "renamed", "basis": Basis(Vector3(1, 2, 3).normalized(), 0.7), "origin": Vector3(15, -2, 9)})
	var transformed := _run(moved, 20, 0.01)
	_check(absf(float(transformed.displacement_m) - float(base.displacement_m)) < 1.0e-10, "rigid transform and canonical IDs do not change physics")
	var permutation := F.create({"capacity": [1000.0, 1000.0]})
	for key in ["mechanical", "electrical"]:
		permutation[key].parts.reverse()
		permutation[key].bonds.reverse()
		var s: Dictionary = permutation[key]
		permutation[key] = F.Snapshot.create(s.construct_id, s.root_item_instance_id, s.state_revision, s.build_state, s.parts, s.bonds, s.compiled_facets)
	var permuted := {"b": B.new(), "a": F.authority(permutation)}
	_check(permuted.b.initialize(permutation, permuted.a).success, "permuted source initializes")
	_check(_run(permuted, 20, 0.01) == base, "canonical insertion order replay exact")
	var small := _new({"spring_k": [50.0], "damping": [1.5], "capacity": [1000.0]})
	_check(absf(float(_run(small, 20, 0.01).velocity_m_per_s) - float(base.velocity_m_per_s)) < 1.0e-12, "one versus two parallel supports same equivalent dynamics")

func _failure_time() -> float:
	var low := 0.0
	var high := 0.6
	for i in range(60):
		var mid := (low + high) * 0.5
		var state := _analytic(mid)
		if 20.0 * float(state.x) + 0.5 * float(state.v) >= 2.0: high = mid
		else: low = mid
	return (low + high) * 0.5

func _fidelity_and_failure() -> void:
	var full := _new()
	var baked := _new()
	var switched := _command(baked, "fidelity", {"target": "BAKE", "certificate": {}})
	_check(switched.success, "exact algebraic bake admitted", switched)
	var certificate: Dictionary = baked.b.inspect().certificate
	_check(certificate.dynamic_states_before == 2 and certificate.dynamic_states_after == 2 and certificate.eliminated_algebraics == 1, "honest algebraic-only certificate")
	var guard_seen := false
	for i in range(100):
		if full.b.inspect().pending_proposal.is_empty(): _run(full, 1, 0.005)
		if baked.b.inspect().pending_proposal.is_empty(): _run(baked, 1, 0.005)
		var f: Dictionary = full.b.inspect()
		var b: Dictionary = baked.b.inspect()
		_check(absf(float(f.displacement_m) - float(b.displacement_m)) < 1.0e-10, "FULL BAKE trajectory parity")
		if b.mode == "REFINED":
			guard_seen = true
			_check(b.fidelity == "FULL" and b.certificate.is_empty(), "guard immediately retires bake")
			_check(baked.b.canonical_state().constructs == full.b.canonical_state().constructs and b.mechanical_revision == 1, "early guard is not canonical damage")
		if not f.pending_proposal.is_empty() and not b.pending_proposal.is_empty(): break
	_check(guard_seen, "pre-failure guard observed")
	var before: Dictionary = baked.b.inspect()
	_check(not before.pending_proposal.is_empty(), "solver creates failure proposal")
	if before.pending_proposal.is_empty(): return
	_check(before.pending_proposal.bond_id.ends_with("support-00"), "solver-selected weak support")
	_check(absf(float(before.time_s) - _failure_time()) < 2.0e-7, "failure time independently analytic", [before.time_s, _failure_time()])
	var old_state: Dictionary = baked.b.canonical_state()
	var command: Dictionary = baked.b.make_command("commit_failure", {"event_id": before.pending_proposal.event_id}, baked.a)
	_check(not baked.b.execute(command, baked.a, false).success, "external rejection propagated")
	_check(baked.b.inspect() == before and baked.b.canonical_state() == old_state, "denied canonical commit atomic")
	_check(not _command(baked, "advance", {"dt_s": 0.005}).success, "failure suspends physical time")
	_check(baked.b.execute(command, baked.a).success, "real ConstructionStore failure commit")
	var after: Dictionary = baked.b.inspect()
	_check(after.displacement_m == before.displacement_m and after.velocity_m_per_s == before.velocity_m_per_s, "fracture displacement velocity continuous")
	_check(after.mechanical_revision == 2 and after.pending_proposal.is_empty(), "canonical successor adopted")
	_check(absf(float(after.elastic_j) + float(after.fracture_heat_j) - float(before.elastic_j)) < 1.0e-12, "released spring energy enters fracture sink")
	_check(absf(float(after.energy_residual_j) - float(before.energy_residual_j)) < 1.0e-12, "no handoff energy creation")
	_check(not baked.b.execute(command, baked.a).success, "duplicate canonical command rejected")
	_check(not _command(baked, "fidelity", {"target": "BAKE", "certificate": certificate}).success, "old artifact fenced after canonical revision")
	_check(_command(baked, "fidelity", {"target": "BAKE", "certificate": {}}).success, "post-break exact rebake")
	var evolved := _run(baked, 20, 0.005)
	_check(evolved.supports[0].active == false and evolved.supports[0].effort_n == 0.0, "post-commit support physically removed")
	_check(absf(float(evolved.energy_residual_j)) < 1.0e-6, "post-break energy balance")
	print("R3_FIRST_FAILURE=", JSON.stringify(before.pending_proposal), " FRACTURE_J=", after.fracture_heat_j)
	# A different physical capacity, not a scenario-selected target, changes identity.
	var swapped := _new({"capacity": [1000.0, 2.0]})
	for i in range(100):
		if not swapped.b.inspect().pending_proposal.is_empty(): break
		_run(swapped, 1, 0.005)
	_check(not swapped.b.inspect().pending_proposal.is_empty() and swapped.b.inspect().pending_proposal.get("bond_id", "").ends_with("support-01"), "failure follows per-element capacity")

func _negative_and_replay() -> void:
	var case := _new({"capacity": [1000.0, 1000.0]})
	_run(case, 8, 0.01)
	var untouched: Dictionary = case.b.inspect()
	var canonical: Dictionary = case.b.canonical_state()
	var stale: Dictionary = case.b.make_command("input", {"field": "source_voltage_v", "value": 8.0}, case.a)
	for dt in [-1.0, 0.0, INF, NAN, 1.0]:
		_check(not _command(case, "advance", {"dt_s": dt}).success, "invalid timestep fail-closed")
	var wrong_owner := F.authority(case.sources, "server/other", 2)
	_check(not case.b.execute(stale, wrong_owner).success, "external owner epoch fenced")
	_check(case.b.inspect() == untouched and case.b.canonical_state() == canonical, "invalid commands leave both sides unchanged")
	_check(_command(case, "input", {"field": "external_force_n", "value": -1.0}).success, "canonical source force command")
	_check(not case.b.execute(stale, case.a).success, "stale command revision fenced")
	var position: float = case.b.inspect().displacement_m
	_check(_command(case, "load", {"resistance_ohm": 7.0}).success, "canonical resistive geometry command")
	_check(case.b.inspect().displacement_m == position and case.b.inspect().electrical_revision == 2, "load commit no pose jump")
	_check(_command(case, "fidelity", {"target": "BAKE", "certificate": {}}).success, "bake after input revision")
	_run(case, 12, 0.005)
	var document: Dictionary = case.b.export_replay()
	var fresh = B.new()
	var matter := {"mechanical_matter": case.b.sources().mechanical_matter, "electrical_matter": case.b.sources().electrical_matter}
	var replay: Dictionary = fresh.replay(document, case.b.canonical_state(), matter, case.a, document.checksum)
	_check(replay.success, "cold replay canonical genesis + commands", replay)
	_check(fresh.inspect() == case.b.inspect(), "replay exact physical readback")
	_check(not B.new().replay(document, case.b.canonical_state(), matter, wrong_owner, document.checksum).success, "replay cannot self-authorize saved owner")
	var tampered: Dictionary = document.duplicate(true)
	tampered.journal[0].command.payload.dt_s = 0.001
	tampered.checksum = U.compute_checksum(tampered)
	_check(not B.new().replay(tampered, case.b.canonical_state(), matter, case.a, document.checksum).success, "rehash alone cannot hide trajectory replay divergence")
	var source := F.create()
	source.mechanical.checksum = "0".repeat(64)
	_check(not C.compile(source, F.authority(source)).success, "source checksum rejected")
	for variant in ["missing_area", "non_collinear", "unknown_material", "bad_coupling", "bad_load", "extra_dof"]:
		source = F.create()
		match variant:
			"missing_area": source.mechanical.bonds[0].metadata.erase("area_m2")
			"non_collinear": source.mechanical.parts[0].local_position_m[1] = 1.0
			"unknown_material":
				source.mechanical_matter = F._matter("mechanism-mechanical", 4.0, "material/unknown")
			"bad_coupling": source.mechanical.compiled_facets.composition_r3.coupling_n_per_a = 0.0
			"bad_load": source.electrical.bonds[1].state = "BROKEN"
			"extra_dof": source.mechanical.parts[0].metadata.physics_r2_anchor = false
		for key in ["mechanical", "electrical"]: source[key].checksum = F.Snapshot.compute_checksum(source[key])
		_check(not C.compile(source, F.authority(source)).success, "reject " + variant)

func _guard_unload_and_regeneration() -> void:
	var case := _new({"voltage_v": 5.0})
	_check(_command(case, "fidelity", {"target": "BAKE", "certificate": {}}).success, "low-voltage bake")
	var certificate: Dictionary = case.b.inspect().certificate
	var guarded := _run(case, 150, 0.005)
	_check(guarded.mode == "REFINED" and guarded.pending_proposal.is_empty(), "guard without physical failure")
	_check(guarded.mechanical_revision == 1, "guard does not invent source revision")
	var bad: Dictionary = certificate.duplicate(true)
	bad.identity = "i=u/r"
	bad.checksum = U.compute_checksum(bad)
	_check(not _command(case, "fidelity", {"target": "BAKE", "certificate": bad}).success, "tampered certificate rejected")
	_check(_command(case, "input", {"field": "source_voltage_v", "value": 0.0}).success, "canonical source unload")
	var resting := _run(case, 200, 0.005)
	_check(resting.pending_proposal.is_empty(), "unload does not force a scripted break")
	_check(_command(case, "fidelity", {"target": "BAKE", "certificate": {}}).success, "safe unload permits rebake")
	var generator := _new({"capacity": [1000.0, 1000.0], "voltage_v": 0.0, "force_n": 5.0})
	var driven := _run(generator, 30, 0.005)
	_check(driven.velocity_m_per_s > 0.0 and driven.current_a < 0.0, "back-driven generator current is not clamped")
	_check(driven.external_work_j > 0.0 and driven.joule_heat_j > 0.0 and absf(float(driven.energy_residual_j)) < 1.0e-6, "back-driven energy accounting")
	_check(_command(generator, "input", {"field": "source_voltage_v", "value": 0.01}).success, "finite-voltage regenerative source")
	var regenerated := _run(generator, 1, 0.005)
	_check(regenerated.source_power_w < 0.0, "source can absorb regenerative power")

func _contract_edges() -> void:
	var tiny := F.create({"capacity": [1.0e-24, 1000.0]})
	_check(not C.compile(tiny, F.authority(tiny)).success, "sub-resolution capacity cannot fabricate an initial event")
	var case := _new({"capacity": [1000.0, 1000.0]})
	_check(_command(case, "fidelity", {"target": "BAKE", "certificate": {}}).success, "certificate serialization setup")
	var cert: Dictionary = JSON.parse_string(JSON.stringify(case.b.inspect().certificate, "", true, true))
	_check(_command(case, "fidelity", {"target": "FULL", "certificate": {}}).success, "full handoff")
	_check(_command(case, "fidelity", {"target": "BAKE", "certificate": cert}).success, "JSON certificate valid after integer normalization")
	var s: Dictionary = case.b.sources()
	var old_epoch := F.authority(s, "server/r3", 2)
	_check(not case.b.execute(case.b.make_command("advance", {"dt_s": 0.005}, old_epoch), old_epoch).success, "same owner stale epoch")
	var before: Dictionary = case.b.export_replay()
	_check(not _command(case, "input", {"field": "source_voltage_v", "value": NAN}).success, "NaN input rejected")
	_check(not _command(case, "load", {"resistance_ohm": INF}).success, "infinite load rejected")
	_check(not _command(case, "load", {"resistance_ohm": 0.0}).success, "zero load rejected")
	_check(case.b.export_replay() == before, "denied commands do not enter authoritative journal")
	var crossed: Dictionary = case.a.duplicate(true)
	for row in crossed.source_authority_frontier:
		if row.source_domain == "CONSTRUCTION":
			row.owner_id = "server/other"
			break
	crossed.authority_epoch_binding = U.canonical_hash(crossed.source_authority_frontier)
	crossed.checksum = U.compute_checksum(crossed)
	_check(not C.compile(s, crossed).success, "cross-owner source envelope cannot execute")
	var compiled := C.compile(s, case.a)
	var full := C.system(compiled.details.model, "FULL")
	_check(full.success and full.details.system.algebraics.size() == 1, "FULL keeps algebraic current")
	_check(C.P.dim_equal(full.details.system.modes.LIVE.residuals[0].dimension, C.P.dim_voltage()), "DAE residual has volts dimension")
	var bake := C.system(compiled.details.model, "BAKE")
	_check(bake.success and bake.details.system.algebraics.is_empty() and bake.details.system.states.size() == full.details.system.states.size(), "BAKE is not hidden state-count reduction")
	var corrupt: Dictionary = compiled.details.model.duplicate(true)
	corrupt.mass_kg = 100.0
	_check(not C.system(corrupt, "FULL").success, "tampered compiled model fenced")
	# A disconnected anchored part cannot silently become an invisible DOF/node.
	s = F.create()
	s.mechanical.parts[0].mass_kg = 0.5
	s.mechanical.parts.append(F.Part.create("part/hidden", "item/hidden", "BEAM", "anchor", 0.5, [0.0, 0.0, 0.0], {"physics_r2_anchor": true}))
	var source: Dictionary = s.mechanical
	s.mechanical = F.Snapshot.create(source.construct_id, source.root_item_instance_id, source.state_revision, source.build_state, source.parts, source.bonds, source.compiled_facets)
	var hidden := C.compile(s, F.authority(s))
	_check(not hidden.success and hidden.error_code == "R3_HIDDEN_NODE_FORBIDDEN", "hidden nodes rejected at composition boundary")
	# Equal force/capacity ratios: two physical failures at the same instant,
	# serialized as two independently revision-fenced Construction commits.
	var simultaneous := _new({"spring_k": [20.0, 20.0], "damping": [0.5, 0.5], "capacity": [2.0, 2.0]})
	for i in range(100):
		if not simultaneous.b.inspect().pending_proposal.is_empty(): break
		_run(simultaneous, 1, 0.005)
	var first: Dictionary = simultaneous.b.inspect()
	_check(not first.pending_proposal.is_empty(), "simultaneous event first proposal")
	if first.pending_proposal.is_empty(): return
	_check(_command(simultaneous, "commit_failure", {"event_id": first.pending_proposal.event_id}).success, "first simultaneous canonical commit")
	var second := _run(simultaneous, 1, 0.005)
	_check(not second.pending_proposal.is_empty() and second.time_s == first.time_s, "second failure resolved at same physical instant")
	if second.pending_proposal.is_empty(): return
	_check(second.pending_proposal.bond_id != first.pending_proposal.bond_id, "second failure identifies other support")
	_check(_command(simultaneous, "commit_failure", {"event_id": second.pending_proposal.event_id}).success, "second simultaneous canonical commit")
	var empty := _run(simultaneous, 4, 0.005)
	_check(empty.elastic_j == 0.0 and empty.mechanical_revision == 3 and absf(float(empty.energy_residual_j)) < 1.0e-6, "all supports broken: no hidden spring, conserved energy")
