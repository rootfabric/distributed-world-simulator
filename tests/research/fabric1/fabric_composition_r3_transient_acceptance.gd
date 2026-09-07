extends SceneTree

const B = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_canonical_bridge_v1.gd")
const F = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_fixture_v1.gd")
const E = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_event_step_v1.gd")
var failures: Array[String] = []
var assertions := 0

func _initialize() -> void:
	for sign_value in [1.0, -1.0]:
		for fidelity in ["FULL", "BAKE"]:
			_transient(sign_value, fidelity, 0.015, 4.0280)
	_transient(1.0, "FULL", 0.014, 4.0280)
	_transient(1.0, "BAKE", 0.016, 4.0280)
	_transient(1.0, "FULL", 0.015, 4.02837)
	_transient(-1.0, "BAKE", 0.015, 4.02837)
	_guard_only_and_safe_peak()
	_same_step_guard_failure()
	_root_isolation()
	print("R3_TRANSIENT_ASSERTIONS=", assertions, " FAILURES=", failures.size())
	print("FABRIC-COMPOSITION-R3-TRANSIENT: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String, details = null) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label, " ", details)

func _command(b, a: Dictionary, action: String, data: Dictionary) -> Dictionary:
	return b.execute(b.make_command(action, data, a), a)

# Independent closed form of the fixture, not runtime coefficients.
func _effort(t: float) -> float:
	var alpha := 0.625
	var omega := sqrt(25.0 - alpha * alpha)
	var x := 0.12 * (1.0 - exp(-alpha * t) * (cos(omega*t) + alpha/omega*sin(omega*t)))
	var v := 3.0 / omega * exp(-alpha*t) * sin(omega*t)
	return 20.0*x + 0.5*v

func _first_root(capacity: float) -> float:
	var lo := 0.600
	var hi := 0.60802
	for iteration in range(60):
		var mid := (lo + hi) * 0.5
		if _effort(mid) >= capacity: hi = mid
		else: lo = mid
	return (lo+hi)*0.5

func _transient(sign_value: float, fidelity: String, dt: float, capacity: float) -> void:
	var sources := F.create({"capacity": [capacity, 1000.0], "voltage_v": 12.0*sign_value})
	var authority := F.authority(sources)
	var b := B.new()
	_check(b.initialize(sources, authority).success, "initialize transient")
	if fidelity == "BAKE": _check(_command(b, authority, "fidelity", {"target": "BAKE", "certificate": {}}).success, "bake transient")
	_check(_effort(0.600) < capacity and _effort(0.615) < capacity and _effort(0.60802) > capacity, "analytic hidden peak")
	for step in range(60):
		if not b.inspect().pending_proposal.is_empty(): break
		var advanced := _command(b, authority, "advance", {"dt_s": dt})
		_check(advanced.success, "advance transient", advanced)
		if not advanced.success: return
	var view: Dictionary = b.inspect()
	print("R3_TRANSIENT=", JSON.stringify({"sign": sign_value, "fidelity": fidelity, "proposal": view.pending_proposal, "reference_first_crossing_s": _first_root(capacity)}))
	_check(not view.pending_proposal.is_empty(), "no missed interior peak")
	if view.pending_proposal.is_empty(): return
	_check(view.pending_proposal.bond_id.ends_with("support-00"), "first support identity")
	_check(absf(float(view.time_s)-_first_root(capacity)) < (6.0e-5 if capacity > 4.0283 else 2.0e-5), "first crossing, not peak", view.time_s)
	_check(view.mechanical_revision == 1, "proposal is not canonical damage")

	# The transient proposal and its event ID must survive a cold reconstruction.
	var document: Dictionary = b.export_replay()
	var replay := B.new()
	var matter := {"mechanical_matter": sources.mechanical_matter, "electrical_matter": sources.electrical_matter}
	_check(replay.replay(document, b.canonical_state(), matter, authority, document.checksum).success, "transient replay")
	_check(replay.inspect() == view, "transient snapshot replay exact")
	var command: Dictionary = b.make_command("commit_failure", {"event_id": view.pending_proposal.event_id}, authority)
	var before: Dictionary = b.canonical_state()
	_check(not b.execute(command, authority, false).success and b.inspect() == view and b.canonical_state() == before, "denied transient commit atomic")
	_check(b.execute(command, authority).success and b.inspect().mechanical_revision == 2, "transient canonical commit")
	_check(not b.execute(command, authority).success, "duplicate transient rejected")

func _guard_only_and_safe_peak() -> void:
	for capacity in [4.0285, 4.0280/0.8]:
		var sources := F.create({"capacity": [capacity, 1000.0]})
		var a := F.authority(sources)
		var b := B.new()
		_check(b.initialize(sources, a).success, "safe peak initialize")
		_check(_command(b, a, "fidelity", {"target": "BAKE", "certificate": {}}).success, "safe peak bake")
		for step in range(60):
			var result := _command(b, a, "advance", {"dt_s": 0.015})
			_check(result.success, "safe peak advance", result)
			if not result.success: return
		var s: Dictionary = b.inspect()
		_check(s.pending_proposal.is_empty() and s.mechanical_revision == 1, "no false failure below capacity")
		_check(s.fidelity == "FULL" and s.mode == "REFINED", "interior guard retires BAKE")
		if capacity > 5.0:
			_check(s.events.size() == 1 and str(s.events[0].transition).begins_with("guard|"), "guard-only transient")
			_check(absf(float(s.events[0].time_s)-_first_root(4.0280)) < 2.0e-5, "guard first crossing not peak")

func _same_step_guard_failure() -> void:
	var sources := F.create({"capacity": [4.0280, 1000.0]})
	var m: Dictionary = sources.mechanical
	m.compiled_facets.composition_r3.guard_fraction = 0.999999
	sources.mechanical = F.Snapshot.create(m.construct_id, m.root_item_instance_id, m.state_revision, m.build_state, m.parts, m.bonds, m.compiled_facets)
	var a := F.authority(sources)
	var b := B.new()
	_check(b.initialize(sources, a).success, "nearby guard initialize")
	_check(_command(b, a, "fidelity", {"target": "BAKE", "certificate": {}}).success, "nearby guard bake")
	for step in range(50):
		if not b.inspect().pending_proposal.is_empty(): break
		var result := _command(b, a, "advance", {"dt_s": 0.015})
		_check(result.success, "post-guard remainder", result)
		if not result.success: return
	var s: Dictionary = b.inspect()
	_check(not s.pending_proposal.is_empty() and s.fidelity == "FULL", "same-step guard then failure")
	_check(s.events.size() == 2 and s.events[0].time_s < s.events[1].time_s, "ordered guard and failure")
	_check(absf(float(s.time_s)-_first_root(4.0280)) < 2.0e-5, "remainder localized")

func _root_isolation() -> void:
	# Cubic with three roots, repeated root, degenerate degree, tiny coefficient scale.
	for scale in [1.0, 1.0e-180, 1.0e180]:
		var coefficients: Array = [-0.08*scale, 0.66*scale, -1.5*scale, scale]
		var roots: Array = E._roots(coefficients)
		_check(roots.size() == 3, "three stationary roots", roots)
		if roots.size() == 3:
			for i in range(3): _check(absf(float(roots[i])-[0.2,0.5,0.8][i]) < 1.0e-10, "stationary root position")
	var repeated: Array = E._roots([-0.112, 0.72, -1.5, 1.0]) # (u-.4)^2*(u-.7)
	var hit := false
	for root in repeated: hit = hit or absf(root-0.4) < 1.0e-8
	_check(hit, "repeated derivative root retained", repeated)
	_check(E._roots([0.0]).is_empty(), "constant force no extrema")
	var linear: Array = E._roots([-0.5, 1.0, 0.0, 0.0])
	_check(linear.size() == 1 and absf(float(linear[0])-0.5) < 1.0e-12, "degenerate polynomial")
