extends RefCounted

# Event bracketing for the affine R3 grammar. Trajectories, algebraic solves and
# transitions remain owned by the unchanged FABRIC0 coupled DAE integrator.
const C = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_compiler_v1.gd")
const D = C.D
const ROUNDING_BAND := 2.0e-12
const ROOT_TOLERANCE := 2.0e-14

static func advance(system: Dictionary, delta: float, model: Dictionary) -> Dictionary:
	var stats := {"algebraic_solves": 0, "algebraic_iterations": 0, "event_iterations": 0, "localized_events": 0}
	var target := float(system.time) + delta
	if not is_finite(target) or target <= float(system.time):
		return _failure("R3_EVENT_TIME_UNRESOLVED")
	for iteration in range(D.MAX_EVENTS_PER_ADVANCE + 1):
		if system.mode == "WAIT_CANONICAL" or target - float(system.time) <= D.EPSILON:
			system.solver_stats = stats
			system.step_revision = int(system.step_revision) + 1
			return {"ok": true}
		var start := D._state_values(system)
		var t0: float = system.time
		var dt := target - t0
		var probe := D._integrate_segment(system, start, t0, dt, stats)
		if not _valid_probe(probe): return _failure("R3_EVENT_PROBE_FAILED")
		var found := _first_crossing(system, model, start, probe, t0, dt, stats)
		if not found.ok: return found
		if not found.has("transition"):
			D._commit_state_values(system, probe.state)
			D._commit_algebraic_values(system, probe.algebraic)
			system.time = target
			system.solver_stats = stats
			system.step_revision = int(system.step_revision) + 1
			return {"ok": true}
		var at_event := D._integrate_segment(system, start, t0, found.dt, stats)
		if not _valid_probe(at_event): return _failure("R3_EVENT_STATE_FAILED")
		D._commit_state_values(system, at_event.state)
		D._commit_algebraic_values(system, at_event.algebraic)
		system.time = t0 + float(found.dt)
		var processed := D._process_event_instant(system, found.transition, stats)
		if not processed.get("ok", false): return _failure("R3_EVENT_TRANSITION_FAILED")
		stats.localized_events += 1
	return _failure("R3_EVENT_WORK_BUDGET")

static func _first_crossing(system: Dictionary, model: Dictionary, start: Dictionary, end: Dictionary, t0: float, dt: float, stats: Dictionary) -> Dictionary:
	var polynomials := {}
	for element in model.mechanical_model.elements:
		if not element.active: continue
		var coefficients := _effort_coefficients(model, element, start, dt)
		for value in coefficients:
			if not is_finite(value): return _failure("R3_EVENT_POLYNOMIAL_NONFINITE")
		polynomials[element.element_id] = {"element": element, "coefficients": coefficients, "cuts": [0.0] + _roots(_derivative(coefficients)) + [1.0]}
	var best := {"ok": true}
	for transition in D._eligible_transitions(system, "crossing"):
		var token: String = transition.id
		var item: Dictionary = polynomials[token.get_slice("|", 1)]
		var sign_value := float(token.get_slice("|", 2))
		var limit: float = transition.guard.nominal
		var scale := maxf(limit, _norm(item.coefficients))
		if not is_finite(scale): return _failure("R3_EVENT_SCALE_NONFINITE")
		var band := ROUNDING_BAND * scale
		var low := 0.0
		var g_low := sign_value * _effort(item.element, start) - limit
		if not is_finite(g_low): return _failure("R3_EVENT_EFFORT_NONFINITE")
		for high_value in item.cuts.slice(1):
			var high := float(high_value)
			var probe: Dictionary = end if high == 1.0 else D._integrate_segment(system, start, t0, high * dt, stats)
			if not _valid_probe(probe): return _failure("R3_EVENT_EXTREMUM_PROBE_FAILED")
			var effort := _effort(item.element, probe.state)
			if not is_finite(effort): return _failure("R3_EVENT_EFFORT_NONFINITE")
			if absf(effort - _evaluate(item.coefficients, high)) > band:
				return _failure("R3_EVENT_POLYNOMIAL_MISMATCH")
			var g_high := sign_value * effort - limit
			if g_low < 0.0 and g_high >= 0.0:
				var root := _localize(system, item.element, start, t0, dt, low, high, sign_value, limit, stats)
				if not root.ok: return root
				var event_dt: float = root.dt
				if not best.has("transition") or event_dt < float(best.dt) - D.EVENT_TIME_TOLERANCE or (absf(event_dt - float(best.dt)) <= D.EVENT_TIME_TOLERANCE and token < str(best.transition.id)):
					best = {"ok": true, "transition": transition, "dt": event_dt}
				break
			# A numerically unresolved tangent is not proof of no crossing.
			if g_high < 0.0 and g_high >= -band:
				return _failure("R3_EVENT_TANGENCY_UNRESOLVED")
			low = high
			g_low = g_high
	return best

# With constant affine flow RK4 produces exactly a degree-four x/v polynomial
# in u=h/dt. These are event-observable coefficients, not an alternative step.
static func _effort_coefficients(model: Dictionary, element: Dictionary, state: Dictionary, dt: float) -> Array:
	var mass: float = model.mass_kg
	var k: float = model.stiffness_n_per_m / mass
	var gamma: float = model.controls.coupling_n_per_a
	var c: float = (model.damping_ns_per_m + gamma * gamma / model.resistance_ohm) / mass
	var drive: float = (gamma * model.controls.source_voltage_v / model.resistance_ohm + model.controls.external_force_n) / mass
	var x: float = state.x
	var v: float = state.v
	var result: Array = [_effort(element, state)]
	for order in range(1, 5):
		var nx := v * dt / order
		var nv := ((drive if order == 1 else 0.0) - k*x - c*v) * dt / order
		x = nx
		v = nv
		result.append(float(element.stiffness_n_per_m)*x + float(element.damping_ns_per_m)*v)
	return result

# Recursive derivative partitioning isolates every real root of degree <= 3
# on [0,1], including repeated roots. No fixed sample grid can miss a narrow peak.
static func _roots(input: Array) -> Array:
	var coefficients := input.duplicate()
	while coefficients.size() > 1 and coefficients.back() == 0.0: coefficients.pop_back()
	var scale := _norm(coefficients)
	if coefficients.size() <= 1 or scale == 0.0: return []
	for i in range(coefficients.size()): coefficients[i] = float(coefficients[i]) / scale
	var cuts: Array = [0.0] + _roots(_derivative(coefficients)) + [1.0]
	var roots: Array = []
	for cut in cuts:
		if cut > 0.0 and cut < 1.0 and absf(_evaluate(coefficients, cut)) <= ROOT_TOLERANCE:
			roots.append(cut)
	for i in range(cuts.size()-1):
		var lo: float = cuts[i]
		var hi: float = cuts[i+1]
		var left := _evaluate(coefficients, lo)
		var right := _evaluate(coefficients, hi)
		if not ((left < 0.0 and right > 0.0) or (left > 0.0 and right < 0.0)): continue
		for iteration in range(52):
			var mid := (lo+hi)*0.5
			var value := _evaluate(coefficients, mid)
			if (left < 0.0 and value < 0.0) or (left > 0.0 and value > 0.0):
				lo = mid
			else: hi = mid
		roots.append((lo+hi)*0.5)
	roots.sort()
	return roots

static func _localize(system: Dictionary, element: Dictionary, start: Dictionary, t0: float, dt: float, lo: float, hi: float, sign_value: float, limit: float, stats: Dictionary) -> Dictionary:
	for iteration in range(D.EVENT_LOCALIZATION_ITERATIONS):
		if (hi-lo)*dt <= D.EVENT_TIME_TOLERANCE: return {"ok": true, "dt": hi*dt}
		var mid := (lo+hi)*0.5
		var probe := D._integrate_segment(system, start, t0, mid*dt, stats)
		if not _valid_probe(probe): return _failure("R3_EVENT_LOCALIZATION_FAILED")
		var effort := sign_value*_effort(element, probe.state)
		if not is_finite(effort): return _failure("R3_EVENT_EFFORT_NONFINITE")
		if effort >= limit: hi = mid
		else: lo = mid
	return _failure("R3_EVENT_LOCALIZATION_BUDGET")

static func _derivative(coefficients: Array) -> Array:
	var result: Array = []
	for i in range(1, coefficients.size()): result.append(i*float(coefficients[i]))
	return result

static func _evaluate(coefficients: Array, u: float) -> float:
	var value := 0.0
	for i in range(coefficients.size()-1, -1, -1): value = value*u + float(coefficients[i])
	return value

static func _norm(coefficients: Array) -> float:
	var value := 0.0
	for coefficient in coefficients: value += absf(float(coefficient))
	return value

static func _effort(element: Dictionary, state: Dictionary) -> float:
	return float(element.stiffness_n_per_m)*float(state.x) + float(element.damping_ns_per_m)*float(state.v)

static func _valid_probe(probe: Dictionary) -> bool:
	if not probe.get("ok", false): return false
	for key in ["state", "algebraic"]:
		for value in probe[key].values():
			if not C.U.is_finite_number(value): return false
	return true

static func _failure(code: String) -> Dictionary:
	return {"ok": false, "code": code}
