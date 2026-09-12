extends RefCounted

# Event bracketing for the generalized linear multi-coordinate R3 path.
# A single RK4 segment of an affine linear system is quartic in normalized
# segment time. Five exact integrator probes therefore reconstruct each
# spring/damper effort polynomial without a fixed-grid crossing assumption.
const C = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_compiler_v1.gd")
const D = C.D
const Graph = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_graph_v1.gd")
const ROUNDING_BAND := 2.0e-10
const ROOT_TOLERANCE := 2.0e-12
const SAMPLE_U: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]

static func advance(system: Dictionary, delta: float, model: Dictionary) -> Dictionary:
	var stats := {"algebraic_solves": 0, "algebraic_iterations": 0, "event_iterations": 0, "localized_events": 0}
	var target := float(system.time) + delta
	if not is_finite(target) or target <= float(system.time): return _failure("R3_GENERAL_EVENT_TIME_UNRESOLVED")
	for _iteration in range(D.MAX_EVENTS_PER_ADVANCE + 1):
		if system.mode == "WAIT_CANONICAL" or target - float(system.time) <= D.EPSILON:
			system.solver_stats = stats
			system.step_revision = int(system.step_revision) + 1
			return {"ok": true}
		var start := D._state_values(system)
		var t0: float = float(system.time)
		var dt := target - t0
		var end := D._integrate_segment(system, start, t0, dt, stats)
		if not _valid_probe(end): return _failure("R3_GENERAL_EVENT_PROBE_FAILED")
		var found := _first_crossing(system, model, start, end, t0, dt, stats)
		if not found.get("ok", false): return found
		if not found.has("transition"):
			D._commit_state_values(system, end.state)
			D._commit_algebraic_values(system, end.algebraic)
			system.time = target
			system.solver_stats = stats
			system.step_revision = int(system.step_revision) + 1
			return {"ok": true}
		var at_event := D._integrate_segment(system, start, t0, float(found.dt), stats)
		if not _valid_probe(at_event): return _failure("R3_GENERAL_EVENT_STATE_FAILED")
		D._commit_state_values(system, at_event.state)
		D._commit_algebraic_values(system, at_event.algebraic)
		system.time = t0 + float(found.dt)
		var processed := D._process_event_instant(system, found.transition, stats)
		if not processed.get("ok", false): return _failure("R3_GENERAL_EVENT_TRANSITION_FAILED")
		stats.localized_events += 1
	return _failure("R3_GENERAL_EVENT_WORK_BUDGET")

static func _first_crossing(system: Dictionary, model: Dictionary, start: Dictionary, end: Dictionary, t0: float, dt: float, stats: Dictionary) -> Dictionary:
	var polynomials := {}
	for element in model.mechanical_model.elements:
		if not bool(element.active): continue
		var fitted := _effort_coefficients(system, model, element, start, end, t0, dt, stats)
		if not fitted.get("ok", false): return fitted
		var coefficients: Array = fitted.coefficients
		for value in coefficients:
			if not is_finite(float(value)): return _failure("R3_GENERAL_EVENT_POLYNOMIAL_NONFINITE")
		polynomials[str(element.element_id)] = {"element": element, "coefficients": coefficients, "cuts": [0.0] + _roots(_derivative(coefficients)) + [1.0]}
	var best := {"ok": true}
	for transition in D._eligible_transitions(system, "crossing"):
		var token: String = str(transition.id)
		var parsed := _parse_transition_id(token)
		if not parsed.get("ok", false): return parsed
		var element_id: String = str(parsed.element_id)
		if not polynomials.has(element_id): return _failure("R3_GENERAL_EVENT_ELEMENT_MISSING")
		var item: Dictionary = polynomials[element_id]
		var sign_value: float = float(parsed.sign)
		var limit: float = float(transition.guard.nominal)
		var scale := maxf(limit, _norm(item.coefficients))
		if not is_finite(scale): return _failure("R3_GENERAL_EVENT_SCALE_NONFINITE")
		var band := ROUNDING_BAND * maxf(1.0, scale)
		var low := 0.0
		var g_low := sign_value * _effort(model, item.element, start) - limit
		if not is_finite(g_low): return _failure("R3_GENERAL_EVENT_EFFORT_NONFINITE")
		for high_value in item.cuts.slice(1):
			var high := float(high_value)
			var probe: Dictionary = end if high == 1.0 else D._integrate_segment(system, start, t0, high * dt, stats)
			if not _valid_probe(probe): return _failure("R3_GENERAL_EVENT_EXTREMUM_PROBE_FAILED")
			var effort := _effort(model, item.element, probe.state)
			if not is_finite(effort): return _failure("R3_GENERAL_EVENT_EFFORT_NONFINITE")
			if absf(effort - _evaluate(item.coefficients, high)) > band: return _failure("R3_GENERAL_EVENT_POLYNOMIAL_MISMATCH")
			var g_high := sign_value * effort - limit
			if g_low < 0.0 and g_high >= 0.0:
				var root := _localize(system, model, item.element, start, t0, dt, low, high, sign_value, limit, stats)
				if not root.get("ok", false): return root
				var event_dt: float = float(root.dt)
				if not best.has("transition") or event_dt < float(best.dt) - D.EVENT_TIME_TOLERANCE or (absf(event_dt - float(best.dt)) <= D.EVENT_TIME_TOLERANCE and token < str(best.transition.id)):
					best = {"ok": true, "transition": transition, "dt": event_dt}
				break
			if g_high < 0.0 and g_high >= -band: return _failure("R3_GENERAL_EVENT_TANGENCY_UNRESOLVED")
			low = high
			g_low = g_high
	return best

static func _parse_transition_id(token: String) -> Dictionary:
	var first_separator := token.find("|")
	var last_separator := token.rfind("|")
	if first_separator <= 0 or last_separator <= first_separator + 1 or last_separator >= token.length() - 1:
		return _failure("R3_GENERAL_EVENT_TRANSITION_SHAPE")
	var kind := token.substr(0, first_separator)
	if kind not in ["guard", "failure"]:
		return _failure("R3_GENERAL_EVENT_TRANSITION_SHAPE")
	var element_id := token.substr(first_separator + 1, last_separator - first_separator - 1)
	if element_id.is_empty():
		return _failure("R3_GENERAL_EVENT_TRANSITION_SHAPE")
	var sign_value := float(token.substr(last_separator + 1))
	if sign_value not in [-1.0, 1.0]:
		return _failure("R3_GENERAL_EVENT_TRANSITION_SHAPE")
	return {"ok": true, "element_id": element_id, "sign": sign_value}

static func _effort_coefficients(system: Dictionary, model: Dictionary, element: Dictionary, start: Dictionary, end: Dictionary, t0: float, dt: float, stats: Dictionary) -> Dictionary:
	var matrix: Array = []
	var rhs: Array = []
	for u in SAMPLE_U:
		var probe: Dictionary
		if u == 0.0: probe = {"ok": true, "state": start, "algebraic": {}}
		elif u == 1.0: probe = end
		else: probe = D._integrate_segment(system, start, t0, u * dt, stats)
		if not probe.get("ok", false) or not probe.get("state") is Dictionary: return _failure("R3_GENERAL_EVENT_SAMPLE_FAILED")
		var effort := _effort(model, element, probe.state)
		if not is_finite(effort): return _failure("R3_GENERAL_EVENT_EFFORT_NONFINITE")
		matrix.append([1.0, u, u * u, u * u * u, u * u * u * u])
		rhs.append(effort)
	var solved := Graph.solve_dense(matrix, rhs)
	if not solved.get("success", false): return _failure("R3_GENERAL_EVENT_INTERPOLATION_FAILED")
	var coefficients: Array = solved.details.x
	var scale := maxf(1.0, _norm(coefficients))
	for i in range(SAMPLE_U.size()):
		if absf(_evaluate(coefficients, SAMPLE_U[i]) - float(rhs[i])) > ROUNDING_BAND * scale: return _failure("R3_GENERAL_EVENT_INTERPOLATION_RESIDUAL")
	return {"ok": true, "coefficients": coefficients}

static func _localize(system: Dictionary, model: Dictionary, element: Dictionary, start: Dictionary, t0: float, dt: float, lo_value: float, hi_value: float, sign_value: float, limit: float, stats: Dictionary) -> Dictionary:
	var lo := lo_value
	var hi := hi_value
	for _iteration in range(D.EVENT_LOCALIZATION_ITERATIONS):
		if (hi - lo) * dt <= D.EVENT_TIME_TOLERANCE: return {"ok": true, "dt": hi * dt}
		var mid := (lo + hi) * 0.5
		var probe := D._integrate_segment(system, start, t0, mid * dt, stats)
		if not _valid_probe(probe): return _failure("R3_GENERAL_EVENT_LOCALIZATION_FAILED")
		var effort := sign_value * _effort(model, element, probe.state)
		if not is_finite(effort): return _failure("R3_GENERAL_EVENT_EFFORT_NONFINITE")
		if effort >= limit: hi = mid
		else: lo = mid
	return _failure("R3_GENERAL_EVENT_LOCALIZATION_BUDGET")

static func _derivative(coefficients: Array) -> Array:
	var result: Array = []
	for i in range(1, coefficients.size()): result.append(i * float(coefficients[i]))
	return result

static func _roots(input: Array) -> Array:
	var coefficients := input.duplicate()
	while coefficients.size() > 1 and float(coefficients.back()) == 0.0: coefficients.pop_back()
	var scale := _norm(coefficients)
	if coefficients.size() <= 1 or scale == 0.0: return []
	for i in range(coefficients.size()): coefficients[i] = float(coefficients[i]) / scale
	var cuts: Array = [0.0] + _roots(_derivative(coefficients)) + [1.0]
	var roots: Array = []
	for cut in cuts:
		if cut > 0.0 and cut < 1.0 and absf(_evaluate(coefficients, cut)) <= ROOT_TOLERANCE: roots.append(cut)
	for i in range(cuts.size() - 1):
		var lo: float = float(cuts[i])
		var hi: float = float(cuts[i + 1])
		var left := _evaluate(coefficients, lo)
		var right := _evaluate(coefficients, hi)
		if not ((left < 0.0 and right > 0.0) or (left > 0.0 and right < 0.0)): continue
		for _iteration in range(52):
			var mid := (lo + hi) * 0.5
			var value := _evaluate(coefficients, mid)
			if (left < 0.0 and value < 0.0) or (left > 0.0 and value > 0.0):
				lo = mid
				left = value
			else: hi = mid
		roots.append((lo + hi) * 0.5)
	roots.sort()
	return roots

static func _evaluate(coefficients: Array, u: float) -> float:
	var value := 0.0
	for i in range(coefficients.size() - 1, -1, -1): value = value * u + float(coefficients[i])
	return value

static func _norm(coefficients: Array) -> float:
	var value := 0.0
	for coefficient in coefficients: value += absf(float(coefficient))
	return value

static func _effort(model: Dictionary, element: Dictionary, state: Dictionary) -> float:
	var a_index := int(model.mobile_index.get(str(element.node_a), -1))
	var b_index := int(model.mobile_index.get(str(element.node_b), -1))
	var xa := float(state.get("x_%d" % a_index, 0.0)) if a_index >= 0 else 0.0
	var xb := float(state.get("x_%d" % b_index, 0.0)) if b_index >= 0 else 0.0
	var va := float(state.get("v_%d" % a_index, 0.0)) if a_index >= 0 else 0.0
	var vb := float(state.get("v_%d" % b_index, 0.0)) if b_index >= 0 else 0.0
	return float(element.stiffness_n_per_m) * (xb - xa) + float(element.damping_ns_per_m) * (vb - va)

static func _valid_probe(probe: Dictionary) -> bool:
	if not probe.get("ok", false): return false
	for key in ["state", "algebraic"]:
		if not probe.get(key) is Dictionary: return false
		for value in probe[key].values():
			if not C.U.is_finite_number(value): return false
	return true

static func _failure(code: String) -> Dictionary:
	return {"ok": false, "code": code}
