class_name Fabric0CoupledHybridDAEV1
extends RefCounted

const Physical = preload("res://scripts/research/fabric0/fabric0_nonsmooth_fabric_v1.gd")

const EPSILON := 1.0e-10
const PIVOT_EPSILON := 1.0e-12
const NEWTON_TOLERANCE := 1.0e-11
const NEWTON_MAX_ITERATIONS := 32
const NEWTON_MAX_LINE_SEARCH := 12
const EVENT_TIME_TOLERANCE := 1.0e-11
const EVENT_LOCALIZATION_ITERATIONS := 64
const MAX_EVENTS_PER_ADVANCE := 32
const MAX_EVENT_ITERATIONS := 16
const GUARD_TOLERANCE := 1.0e-10

# =============================================================================
# DIMENSIONS
# =============================================================================

static func dim_dimensionless() -> Dictionary: return Physical.dim_dimensionless()
static func dim_time() -> Dictionary: return Physical.dim_time()
static func dim_length() -> Dictionary: return Physical.dim(1)
static func dim_velocity() -> Dictionary: return Physical.dim_velocity()
static func dim_acceleration() -> Dictionary: return Physical.dim(1, 0, -2)
static func dim_mass() -> Dictionary: return Physical.dim(0, 1)
static func dim_force() -> Dictionary: return Physical.dim_force()
static func dim_impulse() -> Dictionary: return Physical.dim_mul(Physical.dim_force(), Physical.dim_time())
static func dim_energy() -> Dictionary: return Physical.dim_energy()
static func dim_mul(a: Dictionary, b: Dictionary) -> Dictionary: return Physical.dim_mul(a, b)
static func dim_div(a: Dictionary, b: Dictionary) -> Dictionary: return Physical.dim_div(a, b)
static func dim_pow(a: Dictionary, n: int) -> Dictionary: return Physical.dim_pow(a, n)
static func dim_equal(a: Dictionary, b: Dictionary) -> bool: return Physical.dim_equal(a, b)
static func dim_string(a: Dictionary) -> String: return Physical.dim_string(a)

# =============================================================================
# EXPRESSION DSL
# =============================================================================

static func expr_constant(value: float, dimension: Dictionary = {}) -> Dictionary:
	return {"op":"constant", "value":value, "dimension":dimension.duplicate(true)}

static func expr_state(name: String) -> Dictionary: return {"op":"state", "name":name}
static func expr_algebraic(name: String) -> Dictionary: return {"op":"algebraic", "name":name}
static func expr_parameter(name: String) -> Dictionary: return {"op":"parameter", "name":name}
static func expr_time() -> Dictionary: return {"op":"time"}
static func expr_bond_active(bond_id: String) -> Dictionary: return {"op":"bond_active", "bond_id":bond_id}
static func expr_pre_state(name: String) -> Dictionary: return {"op":"pre_state", "name":name}
static func expr_post_state(name: String) -> Dictionary: return {"op":"post_state", "name":name}
static func expr_jump(name: String) -> Dictionary: return {"op":"jump", "name":name}
static func expr_add(a: Dictionary, b: Dictionary) -> Dictionary: return {"op":"add", "a":a, "b":b}
static func expr_sub(a: Dictionary, b: Dictionary) -> Dictionary: return {"op":"sub", "a":a, "b":b}
static func expr_mul(a: Dictionary, b: Dictionary) -> Dictionary: return {"op":"mul", "a":a, "b":b}
static func expr_div(a: Dictionary, b: Dictionary) -> Dictionary: return {"op":"div", "a":a, "b":b}
static func expr_neg(a: Dictionary) -> Dictionary: return {"op":"neg", "a":a}
static func expr_pow_int(a: Dictionary, n: int) -> Dictionary: return {"op":"pow_int", "a":a, "exponent":n}

static func residual(expr: Dictionary, nominal: float) -> Dictionary:
	assert(nominal > 0.0)
	return {"expr":expr.duplicate(true), "nominal":nominal}

static func inequality(expr: Dictionary, nominal: float, label: String = "") -> Dictionary:
	assert(nominal > 0.0)
	return {"expr":expr.duplicate(true), "nominal":nominal, "label":label}

static func jump_branch(branch_id: String, residuals: Array, inequalities: Array = [], priority: int = 0) -> Dictionary:
	return {
		"id":branch_id,
		"residuals":residuals.duplicate(true),
		"inequalities":inequalities.duplicate(true),
		"priority":priority,
	}

# =============================================================================
# SYSTEM MODEL
# =============================================================================

static func new_system(physical_network: Dictionary = {}) -> Dictionary:
	return {
		"time":0.0,
		"states":{},
		"algebraics":{},
		"parameters":{},
		"modes":{},
		"mode":"",
		"transitions":[],
		"events":[],
		"diagnostics":[],
		"physical_network":physical_network,
		"topology_revision":0,
		"step_revision":0,
		"solver_stats":{},
	}

static func add_state(system: Dictionary, name: String, value: float, dimension: Dictionary, nominal: float = 1.0) -> bool:
	if name.is_empty() or system["states"].has(name) or nominal <= 0.0: return false
	system["states"][name] = {"value":value, "dimension":dimension.duplicate(true), "nominal":nominal}
	return true

static func add_algebraic(system: Dictionary, name: String, value: float, dimension: Dictionary, nominal: float = 1.0) -> bool:
	if name.is_empty() or system["algebraics"].has(name) or nominal <= 0.0: return false
	system["algebraics"][name] = {"value":value, "dimension":dimension.duplicate(true), "nominal":nominal}
	return true

static func add_parameter(system: Dictionary, name: String, value: float, dimension: Dictionary) -> bool:
	if name.is_empty() or system["parameters"].has(name): return false
	system["parameters"][name] = {"value":value, "dimension":dimension.duplicate(true)}
	return true

static func set_parameter_value(system: Dictionary, name: String, value: float) -> bool:
	if not system["parameters"].has(name): return false
	system["parameters"][name]["value"] = value
	return true

# mode = flows(state -> expr), algebraic residuals F(x,y,p,t)=0.
static func add_mode(system: Dictionary, mode_id: String, flows: Dictionary, algebraic_residuals: Array) -> bool:
	if mode_id.is_empty() or system["modes"].has(mode_id): return false
	if algebraic_residuals.size() != system["algebraics"].size():
		system["diagnostics"].append({"code":"DAE_NON_SQUARE_ALGEBRAIC_SYSTEM", "mode":mode_id})
		return false
	for state_name in flows.keys():
		if not system["states"].has(state_name): return false
		var inferred := _infer_expr_dimension(system, flows[state_name], {})
		if not bool(inferred.get("ok", false)):
			system["diagnostics"].append({"code":"DAE_FLOW_DIMENSION_ERROR", "mode":mode_id, "state":String(state_name), "reason":inferred})
			return false
		var expected := dim_div(system["states"][state_name]["dimension"], dim_time())
		if not dim_equal(inferred["dimension"], expected):
			system["diagnostics"].append({"code":"DAE_FLOW_DIMENSION_MISMATCH", "mode":mode_id, "state":String(state_name), "expected":dim_string(expected), "actual":dim_string(inferred["dimension"])})
			return false
	var normalized: Array = []
	for row in algebraic_residuals:
		if not row.has("expr") or float(row.get("nominal",0.0)) <= 0.0: return false
		var inferred := _infer_expr_dimension(system, row["expr"], {})
		if not bool(inferred.get("ok", false)):
			system["diagnostics"].append({"code":"DAE_RESIDUAL_DIMENSION_ERROR", "mode":mode_id, "reason":inferred})
			return false
		normalized.append({"expr":row["expr"].duplicate(true), "nominal":float(row["nominal"]), "dimension":inferred["dimension"]})
	system["modes"][mode_id] = {"flows":flows.duplicate(true), "residuals":normalized}
	return true

static func set_initial_mode(system: Dictionary, mode_id: String) -> bool:
	if not system["modes"].has(mode_id): return false
	system["mode"] = mode_id
	return true

# transition:
# id, from_modes, to_mode,
# guard {expr, nominal, direction, kind:"crossing"|"condition"},
# jump {post_states:[...], unknowns:{name:{dimension,nominal,initial}}, branches:[...]}, optional
# topology_ops, priority.
static func add_transition(system: Dictionary, transition: Dictionary) -> bool:
	var transition_id := String(transition.get("id", ""))
	if transition_id.is_empty(): return false
	for existing in system["transitions"]:
		if String(existing["id"]) == transition_id: return false
	var from_modes: Array = transition.get("from_modes", [])
	var to_mode := String(transition.get("to_mode", ""))
	if from_modes.is_empty() or not system["modes"].has(to_mode): return false
	for mode_id in from_modes:
		if not system["modes"].has(String(mode_id)): return false
	var guard: Dictionary = transition.get("guard", {})
	if not guard.has("expr") or float(guard.get("nominal",0.0)) <= 0.0: return false
	var kind := String(guard.get("kind", "crossing"))
	if kind != "crossing" and kind != "condition": return false
	var direction := int(guard.get("direction", 0))
	if direction < -1 or direction > 1: return false
	var guard_dim := _infer_expr_dimension(system, guard["expr"], {})
	if not bool(guard_dim.get("ok", false)):
		system["diagnostics"].append({"code":"EVENT_GUARD_DIMENSION_ERROR", "transition":transition_id, "reason":guard_dim})
		return false

	var jump: Dictionary = transition.get("jump", {})
	var normalized_jump := {}
	if not jump.is_empty():
		var post_states: Array = jump.get("post_states", [])
		var jump_unknowns: Dictionary = jump.get("unknowns", {})
		var jump_dims := {}
		for state_name in post_states:
			if not system["states"].has(String(state_name)): return false
			jump_dims["post:%s" % String(state_name)] = system["states"][String(state_name)]["dimension"]
		for unknown_name in jump_unknowns.keys():
			var spec: Dictionary = jump_unknowns[unknown_name]
			if not spec.has("dimension") or float(spec.get("nominal",0.0)) <= 0.0: return false
			jump_dims["jump:%s" % String(unknown_name)] = spec["dimension"].duplicate(true)
		var branches: Array = jump.get("branches", [])
		if branches.is_empty(): return false
		var expected_rows := post_states.size() + jump_unknowns.size()
		var normalized_branches: Array = []
		for branch_spec in branches:
			if String(branch_spec.get("id","")) == "": return false
			var rows: Array = branch_spec.get("residuals", [])
			if rows.size() != expected_rows:
				system["diagnostics"].append({"code":"JUMP_NON_SQUARE_BRANCH", "transition":transition_id, "branch":String(branch_spec.get("id","")), "rows":rows.size(), "unknowns":expected_rows})
				return false
			var normalized_rows: Array = []
			for row in rows:
				if not row.has("expr") or float(row.get("nominal",0.0)) <= 0.0: return false
				var inferred := _infer_expr_dimension(system, row["expr"], jump_dims)
				if not bool(inferred.get("ok", false)):
					system["diagnostics"].append({"code":"JUMP_RESIDUAL_DIMENSION_ERROR", "transition":transition_id, "branch":String(branch_spec["id"]), "reason":inferred})
					return false
				normalized_rows.append({"expr":row["expr"].duplicate(true), "nominal":float(row["nominal"]), "dimension":inferred["dimension"]})
			var normalized_ineq: Array = []
			for item in branch_spec.get("inequalities", []):
				if not item.has("expr") or float(item.get("nominal",0.0)) <= 0.0: return false
				var inferred := _infer_expr_dimension(system, item["expr"], jump_dims)
				if not bool(inferred.get("ok", false)):
					system["diagnostics"].append({"code":"JUMP_INEQUALITY_DIMENSION_ERROR", "transition":transition_id, "branch":String(branch_spec["id"]), "reason":inferred})
					return false
				normalized_ineq.append({"expr":item["expr"].duplicate(true), "nominal":float(item["nominal"]), "label":String(item.get("label","")), "dimension":inferred["dimension"]})
			normalized_branches.append({"id":String(branch_spec["id"]), "residuals":normalized_rows, "inequalities":normalized_ineq, "priority":int(branch_spec.get("priority",0))})
		normalized_jump = {"post_states":post_states.duplicate(true), "unknowns":jump_unknowns.duplicate(true), "branches":normalized_branches}

	for op in transition.get("topology_ops", []):
		if String(op.get("op","")) != "set_bond_active": return false
	system["transitions"].append({
		"id":transition_id,
		"from_modes":from_modes.duplicate(true),
		"to_mode":to_mode,
		"guard":{"expr":guard["expr"].duplicate(true), "nominal":float(guard["nominal"]), "direction":direction, "kind":kind, "dimension":guard_dim["dimension"]},
		"jump":normalized_jump,
		"topology_ops":transition.get("topology_ops", []).duplicate(true),
		"priority":int(transition.get("priority",0)),
	})
	return true

static func read_state(system: Dictionary, name: String) -> float: return float(system["states"][name]["value"])
static func read_algebraic(system: Dictionary, name: String) -> float: return float(system["algebraics"][name]["value"])
static func read_mode(system: Dictionary) -> String: return String(system["mode"])

# =============================================================================
# DAE ALGEBRAIC SOLVER
# =============================================================================

static func solve_algebraic(system: Dictionary) -> Dictionary:
	var state_values := _state_values(system)
	var initial := _algebraic_values(system)
	var result := _solve_algebraic_for(system, state_values, float(system["time"]), String(system["mode"]), initial)
	if bool(result.get("ok", false)):
		_commit_algebraic_values(system, result["values"])
	return result

static func _solve_algebraic_for(system: Dictionary, state_values: Dictionary, time_value: float, mode_id: String, initial_values: Dictionary) -> Dictionary:
	var names: Array = system["algebraics"].keys()
	names.sort()
	if names.is_empty(): return {"ok":true, "values":{}, "iterations":0}
	var x: Array = []
	for name in names: x.append(float(initial_values.get(name, system["algebraics"][name]["value"])))
	var rows: Array = system["modes"][mode_id]["residuals"]
	for iteration in range(NEWTON_MAX_ITERATIONS):
		var assembled := _assemble_algebraic(system, state_values, time_value, names, x, rows)
		if not bool(assembled.get("ok", false)): return {"ok":false, "code":assembled.get("code","DAE_ASSEMBLY_FAILED")}
		var norm := _normalized_norm(assembled["residual"], _row_nominals(rows))
		if norm <= NEWTON_TOLERANCE:
			var rank := _solve_dense(assembled["jacobian"], _zero_vector(x.size()))
			if not bool(rank.get("ok", false)): return {"ok":false, "code":"DAE_SINGULAR_ALGEBRAIC_MANIFOLD", "normalized_residual":norm}
			var values := {}
			for i in range(names.size()): values[names[i]] = float(x[i])
			return {"ok":true, "values":values, "iterations":iteration+1, "normalized_residual":norm}
		var rhs: Array = []
		for value in assembled["residual"]: rhs.append(-float(value))
		var step := _solve_dense(assembled["jacobian"], rhs)
		if not bool(step.get("ok", false)): return {"ok":false, "code":"DAE_SINGULAR_JACOBIAN", "normalized_residual":norm}
		var dx: Array = step["x"]
		var alpha := 1.0
		var accepted := false
		for _ls in range(NEWTON_MAX_LINE_SEARCH):
			var candidate := x.duplicate(true)
			for i in range(candidate.size()): candidate[i] = float(candidate[i]) + alpha * float(dx[i])
			var probe := _assemble_algebraic(system, state_values, time_value, names, candidate, rows)
			if bool(probe.get("ok", false)) and _normalized_norm(probe["residual"], _row_nominals(rows)) < norm:
				x = candidate
				accepted = true
				break
			alpha *= 0.5
		if not accepted: return {"ok":false, "code":"DAE_LINE_SEARCH_FAILED", "normalized_residual":norm}
	return {"ok":false, "code":"DAE_NO_CONVERGENCE"}

static func _assemble_algebraic(system: Dictionary, state_values: Dictionary, time_value: float, names: Array, x: Array, rows: Array) -> Dictionary:
	var index := {}
	var algebraics := {}
	for i in range(names.size()):
		index[names[i]] = i
		algebraics[names[i]] = float(x[i])
	var residual_values: Array = []
	var jacobian := _zero_matrix(rows.size(), names.size())
	for row_i in range(rows.size()):
		var evaluated := _eval_expr_dual_algebraic(system, rows[row_i]["expr"], state_values, algebraics, time_value, index)
		if not bool(evaluated.get("ok", false)): return evaluated
		residual_values.append(float(evaluated["value"]))
		for key in evaluated["grad"].keys(): jacobian[row_i][int(key)] = float(evaluated["grad"][key])
	return {"ok":true, "residual":residual_values, "jacobian":jacobian}

# =============================================================================
# COUPLED RK4 ADVANCE
# =============================================================================

static func advance(system: Dictionary, delta: float) -> Dictionary:
	if delta < 0.0 or String(system["mode"]).is_empty(): return {"ok":false, "code":"BAD_ADVANCE_REQUEST"}
	if delta <= EPSILON: return {"ok":true, "events":0, "time":float(system["time"])}
	var snapshot := _capture_snapshot(system)
	system["diagnostics"] = []
	var stats := {"algebraic_solves":0, "algebraic_iterations":0, "event_iterations":0, "localized_events":0}
	var remaining := delta
	var event_instants := 0
	while remaining > EPSILON:
		var start_time := float(system["time"])
		var start_state := _state_values(system)
		var integrated := _integrate_segment(system, start_state, start_time, remaining, stats)
		if not bool(integrated.get("ok", false)):
			_restore_snapshot(system, snapshot)
			system["diagnostics"] = [{"code":String(integrated.get("code","DAE_INTEGRATION_FAILED"))}]
			return {"ok":false, "code":String(integrated.get("code","DAE_INTEGRATION_FAILED")), "rolled_back":true}
		var candidate := _find_earliest_crossing(system, start_state, integrated["state"], start_time, remaining, stats)
		if not bool(candidate.get("found", false)):
			_commit_state_values(system, integrated["state"])
			_commit_algebraic_values(system, integrated["algebraic"])
			system["time"] = start_time + remaining
			remaining = 0.0
			break

		var event_dt := float(candidate["dt"])
		var at_event := _integrate_segment(system, start_state, start_time, event_dt, stats)
		if not bool(at_event.get("ok", false)):
			_restore_snapshot(system, snapshot)
			return {"ok":false, "code":String(at_event.get("code","DAE_EVENT_INTEGRATION_FAILED")), "rolled_back":true}
		_commit_state_values(system, at_event["state"])
		_commit_algebraic_values(system, at_event["algebraic"])
		system["time"] = start_time + event_dt
		var instant := _process_event_instant(system, candidate["transition"], stats)
		if not bool(instant.get("ok", false)):
			_restore_snapshot(system, snapshot)
			system["diagnostics"] = [{"code":String(instant.get("code","EVENT_INSTANT_FAILED"))}]
			return {"ok":false, "code":String(instant.get("code","EVENT_INSTANT_FAILED")), "rolled_back":true}
		event_instants += 1
		stats["localized_events"] = event_instants
		if event_instants > MAX_EVENTS_PER_ADVANCE:
			_restore_snapshot(system, snapshot)
			system["diagnostics"] = [{"code":"ZENO_OR_EVENT_STORM", "limit":MAX_EVENTS_PER_ADVANCE}]
			return {"ok":false, "code":"ZENO_OR_EVENT_STORM", "rolled_back":true}
		remaining -= event_dt
		if remaining < EPSILON: remaining = 0.0

	system["step_revision"] = int(system["step_revision"]) + 1
	system["solver_stats"] = stats
	return {"ok":true, "events":event_instants, "time":float(system["time"]), "solver_stats":stats.duplicate(true)}

static func _integrate_segment(system: Dictionary, initial_state: Dictionary, start_time: float, delta: float, stats: Dictionary) -> Dictionary:
	if delta <= EPSILON:
		var alg := _solve_algebraic_counted(system, initial_state, start_time, String(system["mode"]), _algebraic_values(system), stats)
		if not bool(alg.get("ok", false)): return alg
		return {"ok":true, "state":initial_state.duplicate(true), "algebraic":alg["values"]}
	var mode_id := String(system["mode"])
	var a1 := _solve_algebraic_counted(system, initial_state, start_time, mode_id, _algebraic_values(system), stats)
	if not bool(a1.get("ok", false)): return a1
	var k1 := _flow_vector(system, mode_id, initial_state, a1["values"], start_time)
	var s2 := _state_plus_scaled(initial_state, k1, 0.5*delta)
	var a2 := _solve_algebraic_counted(system, s2, start_time+0.5*delta, mode_id, a1["values"], stats)
	if not bool(a2.get("ok", false)): return a2
	var k2 := _flow_vector(system, mode_id, s2, a2["values"], start_time+0.5*delta)
	var s3 := _state_plus_scaled(initial_state, k2, 0.5*delta)
	var a3 := _solve_algebraic_counted(system, s3, start_time+0.5*delta, mode_id, a2["values"], stats)
	if not bool(a3.get("ok", false)): return a3
	var k3 := _flow_vector(system, mode_id, s3, a3["values"], start_time+0.5*delta)
	var s4 := _state_plus_scaled(initial_state, k3, delta)
	var a4 := _solve_algebraic_counted(system, s4, start_time+delta, mode_id, a3["values"], stats)
	if not bool(a4.get("ok", false)): return a4
	var k4 := _flow_vector(system, mode_id, s4, a4["values"], start_time+delta)
	var result := initial_state.duplicate(true)
	for state_name in result.keys():
		result[state_name] = float(initial_state[state_name]) + delta/6.0*(float(k1[state_name])+2.0*float(k2[state_name])+2.0*float(k3[state_name])+float(k4[state_name]))
	var afinal := _solve_algebraic_counted(system, result, start_time+delta, mode_id, a4["values"], stats)
	if not bool(afinal.get("ok", false)): return afinal
	return {"ok":true, "state":result, "algebraic":afinal["values"]}

static func _solve_algebraic_counted(system: Dictionary, state_values: Dictionary, time_value: float, mode_id: String, initial: Dictionary, stats: Dictionary) -> Dictionary:
	var result := _solve_algebraic_for(system, state_values, time_value, mode_id, initial)
	stats["algebraic_solves"] = int(stats["algebraic_solves"]) + 1
	stats["algebraic_iterations"] = int(stats["algebraic_iterations"]) + int(result.get("iterations",0))
	return result

static func _flow_vector(system: Dictionary, mode_id: String, states: Dictionary, algebraics: Dictionary, time_value: float) -> Dictionary:
	var result := {}
	var flows: Dictionary = system["modes"][mode_id]["flows"]
	for state_name in system["states"].keys():
		if flows.has(state_name):
			var v := _eval_expr_value(system, flows[state_name], states, algebraics, time_value, {}, {}, {})
			result[state_name] = float(v.get("value",0.0))
		else: result[state_name] = 0.0
	return result

# =============================================================================
# EVENT LOCALIZATION + SAME-TIME ITERATION
# =============================================================================

static func _find_earliest_crossing(system: Dictionary, start_state: Dictionary, end_state: Dictionary, start_time: float, delta: float, stats: Dictionary) -> Dictionary:
	var candidates: Array = []
	for transition in _eligible_transitions(system, "crossing"):
		var start_alg := _solve_algebraic_counted(system, start_state, start_time, String(system["mode"]), _algebraic_values(system), stats)
		var end_alg := _solve_algebraic_counted(system, end_state, start_time+delta, String(system["mode"]), start_alg.get("values",{}), stats)
		if not bool(start_alg.get("ok",false)) or not bool(end_alg.get("ok",false)): continue
		var g0 := _eval_expr_value(system, transition["guard"]["expr"], start_state, start_alg["values"], start_time, {}, {}, {})
		var g1 := _eval_expr_value(system, transition["guard"]["expr"], end_state, end_alg["values"], start_time+delta, {}, {}, {})
		if not bool(g0.get("ok",false)) or not bool(g1.get("ok",false)): continue
		if not _crossed(float(g0["value"]), float(g1["value"]), int(transition["guard"]["direction"]), float(transition["guard"]["nominal"])): continue
		var dt := _localize_crossing(system, transition, start_state, start_time, delta, stats)
		candidates.append({"transition":transition, "dt":dt})
	if candidates.is_empty(): return {"found":false}
	candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		if absf(float(a["dt"])-float(b["dt"])) > EVENT_TIME_TOLERANCE: return float(a["dt"]) < float(b["dt"])
		if int(a["transition"]["priority"]) != int(b["transition"]["priority"]): return int(a["transition"]["priority"]) < int(b["transition"]["priority"])
		return String(a["transition"]["id"]) < String(b["transition"]["id"])
	)
	return {"found":true, "transition":candidates[0]["transition"], "dt":float(candidates[0]["dt"])}

static func _localize_crossing(system: Dictionary, transition: Dictionary, start_state: Dictionary, start_time: float, delta: float, stats: Dictionary) -> float:
	var low := 0.0
	var high := delta
	var start_alg := _solve_algebraic_counted(system, start_state, start_time, String(system["mode"]), _algebraic_values(system), stats)
	var g_low := float(_eval_expr_value(system, transition["guard"]["expr"], start_state, start_alg["values"], start_time, {}, {}, {})["value"])
	for _i in range(EVENT_LOCALIZATION_ITERATIONS):
		if high-low <= EVENT_TIME_TOLERANCE: break
		var mid := 0.5*(low+high)
		var probe := _integrate_segment(system, start_state, start_time, mid, stats)
		if not bool(probe.get("ok",false)): return high
		var g_mid := float(_eval_expr_value(system, transition["guard"]["expr"], probe["state"], probe["algebraic"], start_time+mid, {}, {}, {})["value"])
		var dir := int(transition["guard"]["direction"])
		if dir > 0:
			if g_mid >= 0.0: high = mid
			else:
				low = mid
				g_low = g_mid
		elif dir < 0:
			if g_mid <= 0.0: high = mid
			else:
				low = mid
				g_low = g_mid
		else:
			if (g_low <= 0.0 and g_mid >= 0.0) or (g_low >= 0.0 and g_mid <= 0.0): high = mid
			else:
				low = mid
				g_low = g_mid
	return high

static func _process_event_instant(system: Dictionary, root_transition: Dictionary, stats: Dictionary) -> Dictionary:
	var instant_time := float(system["time"])
	var instant_index: int = system["events"].size() + 1
	var instant := {"event_id":"fabric0/instant/%06d" % instant_index, "sequence":instant_index, "time":instant_time, "transitions":[], "pre_state_hash":state_hash(system), "topology_revision_before":int(system["topology_revision"])}
	var fired := {}
	var pending: Dictionary = root_transition
	for iteration in range(MAX_EVENT_ITERATIONS):
		stats["event_iterations"] = int(stats["event_iterations"])+1
		if pending.is_empty():
			pending = _next_enabled_condition_transition(system, fired)
			if pending.is_empty():
				instant["post_state_hash"] = state_hash(system)
				instant["topology_revision_after"] = int(system["topology_revision"])
				system["events"].append(instant)
				return {"ok":true, "instant":instant}
		var transition_id := String(pending["id"])
		if fired.has(transition_id):
			pending = {}
			continue
		var sub := _apply_transition(system, pending)
		if not bool(sub.get("ok",false)): return sub
		fired[transition_id] = true
		instant["transitions"].append(sub["record"])
		# Re-solve algebraics immediately after every jump/topology mutation at the same physical time.
		var alg := _solve_algebraic_for(system, _state_values(system), instant_time, String(system["mode"]), _algebraic_values(system))
		if not bool(alg.get("ok",false)): return {"ok":false, "code":"EVENT_POST_DAE_SOLVE_FAILED"}
		_commit_algebraic_values(system, alg["values"])
		instant["transitions"][instant["transitions"].size()-1]["post_algebraics"] = alg["values"].duplicate(true)
		pending = {}
	return {"ok":false, "code":"EVENT_ITERATION_NO_FIXED_POINT"}

static func _next_enabled_condition_transition(system: Dictionary, fired: Dictionary) -> Dictionary:
	var candidates: Array = []
	for transition in _eligible_transitions(system, "condition"):
		if fired.has(String(transition["id"])): continue
		var value := _eval_expr_value(system, transition["guard"]["expr"], _state_values(system), _algebraic_values(system), float(system["time"]), {}, {}, {})
		if not bool(value.get("ok",false)): continue
		var normalized := float(value["value"])/maxf(float(transition["guard"]["nominal"]), EPSILON)
		if normalized >= -GUARD_TOLERANCE: candidates.append(transition)
	if candidates.is_empty(): return {}
	candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		if int(a["priority"]) != int(b["priority"]): return int(a["priority"]) < int(b["priority"])
		return String(a["id"]) < String(b["id"])
	)
	return candidates[0]

static func _apply_transition(system: Dictionary, transition: Dictionary) -> Dictionary:
	var pre_states := _state_values(system)
	var pre_algebraics := _algebraic_values(system)
	var pre_mode := String(system["mode"])
	var pre_hash := state_hash(system)
	var topology_before := int(system["topology_revision"])
	var jump_branch_id := ""
	var jump_values := {}
	if not transition["jump"].is_empty():
		var jump_result := _solve_jump(system, transition, pre_states, pre_algebraics)
		if not bool(jump_result.get("ok",false)): return jump_result
		jump_branch_id = String(jump_result["branch"])
		jump_values = jump_result["jump_values"].duplicate(true)
		for state_name in jump_result["post_states"].keys(): system["states"][state_name]["value"] = float(jump_result["post_states"][state_name])
	var tx := _validate_topology_transaction(system, transition["topology_ops"])
	if not bool(tx.get("ok",false)): return tx
	system["mode"] = String(transition["to_mode"])
	var topology_changed := _commit_topology_transaction(system, transition["topology_ops"])
	if topology_changed: system["topology_revision"] = topology_before+1
	var record := {
		"transition_id":String(transition["id"]),
		"pre_mode":pre_mode,
		"post_mode":String(system["mode"]),
		"pre_states":pre_states,
		"post_states":_state_values(system),
		"pre_algebraics":pre_algebraics,
		"pre_state_hash":pre_hash,
		"post_state_hash":state_hash(system),
		"topology_revision_before":topology_before,
		"topology_revision_after":int(system["topology_revision"]),
		"jump_branch":jump_branch_id,
		"jump_values":jump_values,
	}
	return {"ok":true, "record":record}

static func _eligible_transitions(system: Dictionary, kind: String) -> Array:
	var mode := String(system["mode"])
	var result: Array = []
	for transition in system["transitions"]:
		if String(transition["guard"]["kind"]) == kind and mode in transition["from_modes"]: result.append(transition)
	return result

static func _crossed(g0: float, g1: float, direction: int, nominal: float) -> bool:
	var eps := GUARD_TOLERANCE*maxf(nominal,1.0)
	if direction > 0: return g0 < -eps and g1 >= 0.0
	if direction < 0: return g0 > eps and g1 <= 0.0
	return (g0 < -eps and g1 >= 0.0) or (g0 > eps and g1 <= 0.0)

# =============================================================================
# GENERIC BRANCH-BASED JUMP / IMPULSE SOLVE
# =============================================================================

static func _solve_jump(system: Dictionary, transition: Dictionary, pre_states: Dictionary, pre_algebraics: Dictionary) -> Dictionary:
	var jump: Dictionary = transition["jump"]
	var post_names: Array = jump["post_states"].duplicate(true)
	post_names.sort()
	var jump_names: Array = jump["unknowns"].keys()
	jump_names.sort()
	var unknown_keys: Array = []
	var x0: Array = []
	var nominals: Array = []
	for state_name in post_names:
		unknown_keys.append("post:%s" % String(state_name))
		x0.append(float(pre_states[state_name]))
		nominals.append(float(system["states"][state_name]["nominal"]))
	for name in jump_names:
		unknown_keys.append("jump:%s" % String(name))
		x0.append(float(jump["unknowns"][name].get("initial",0.0)))
		nominals.append(float(jump["unknowns"][name]["nominal"]))
	var candidates: Array = []
	for branch_spec in jump["branches"]:
		var solved := _solve_jump_branch(system, branch_spec, unknown_keys, x0, pre_states, pre_algebraics)
		if not bool(solved.get("ok",false)): continue
		var guards := _check_jump_inequalities(system, branch_spec, unknown_keys, solved["x"], pre_states, pre_algebraics)
		if not bool(guards.get("ok",false)): continue
		candidates.append({"branch":String(branch_spec["id"]), "priority":int(branch_spec["priority"]), "x":solved["x"], "iterations":int(solved.get("iterations",0))})
	if candidates.is_empty(): return {"ok":false, "code":"NO_ADMISSIBLE_JUMP_BRANCH", "transition":String(transition["id"])}
	candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		if int(a["priority"]) != int(b["priority"]): return int(a["priority"]) < int(b["priority"])
		return String(a["branch"]) < String(b["branch"])
	)
	var selected: Dictionary = candidates[0]
	var post_states := {}
	for state_name in system["states"].keys(): post_states[state_name] = float(pre_states[state_name])
	var jump_values := {}
	for i in range(unknown_keys.size()):
		var key := String(unknown_keys[i])
		if key.begins_with("post:"): post_states[key.substr(5)] = float(selected["x"][i])
		else: jump_values[key.substr(5)] = float(selected["x"][i])
	return {"ok":true, "branch":selected["branch"], "post_states":post_states, "jump_values":jump_values, "iterations":selected["iterations"]}

static func _solve_jump_branch(system: Dictionary, branch_spec: Dictionary, unknown_keys: Array, initial: Array, pre_states: Dictionary, pre_algebraics: Dictionary) -> Dictionary:
	var x := initial.duplicate(true)
	var rows: Array = branch_spec["residuals"]
	var row_nominals := _row_nominals(rows)
	for iteration in range(NEWTON_MAX_ITERATIONS):
		var assembled := _assemble_jump(system, rows, unknown_keys, x, pre_states, pre_algebraics)
		if not bool(assembled.get("ok",false)): return assembled
		var norm := _normalized_norm(assembled["residual"], row_nominals)
		if norm <= NEWTON_TOLERANCE:
			var rank := _solve_dense(assembled["jacobian"], _zero_vector(x.size()))
			if not bool(rank.get("ok",false)): return {"ok":false, "code":"JUMP_SINGULAR_MANIFOLD"}
			return {"ok":true, "x":x, "iterations":iteration+1}
		var rhs: Array = []
		for v in assembled["residual"]: rhs.append(-float(v))
		var step := _solve_dense(assembled["jacobian"], rhs)
		if not bool(step.get("ok",false)): return {"ok":false, "code":"JUMP_SINGULAR_JACOBIAN"}
		var dx: Array = step["x"]
		var alpha := 1.0
		var accepted := false
		for _ls in range(NEWTON_MAX_LINE_SEARCH):
			var candidate := x.duplicate(true)
			for i in range(candidate.size()): candidate[i] = float(candidate[i]) + alpha*float(dx[i])
			var probe := _assemble_jump(system, rows, unknown_keys, candidate, pre_states, pre_algebraics)
			if bool(probe.get("ok",false)) and _normalized_norm(probe["residual"], row_nominals) < norm:
				x = candidate
				accepted = true
				break
			alpha *= 0.5
		if not accepted: return {"ok":false, "code":"JUMP_LINE_SEARCH_FAILED"}
	return {"ok":false, "code":"JUMP_NO_CONVERGENCE"}

static func _assemble_jump(system: Dictionary, rows: Array, unknown_keys: Array, x: Array, pre_states: Dictionary, pre_algebraics: Dictionary) -> Dictionary:
	var index := {}
	var post := pre_states.duplicate(true)
	var jump_values := {}
	for i in range(unknown_keys.size()):
		index[unknown_keys[i]] = i
		var key := String(unknown_keys[i])
		if key.begins_with("post:"): post[key.substr(5)] = float(x[i])
		else: jump_values[key.substr(5)] = float(x[i])
	var residual_values: Array = []
	var jacobian := _zero_matrix(rows.size(), unknown_keys.size())
	for row_i in range(rows.size()):
		var evaluated := _eval_expr_dual_jump(system, rows[row_i]["expr"], pre_states, post, jump_values, pre_algebraics, float(system["time"]), index)
		if not bool(evaluated.get("ok",false)): return evaluated
		residual_values.append(float(evaluated["value"]))
		for key in evaluated["grad"].keys(): jacobian[row_i][int(key)] = float(evaluated["grad"][key])
	return {"ok":true, "residual":residual_values, "jacobian":jacobian}

static func _check_jump_inequalities(system: Dictionary, branch_spec: Dictionary, unknown_keys: Array, x: Array, pre_states: Dictionary, pre_algebraics: Dictionary) -> Dictionary:
	var post := pre_states.duplicate(true)
	var jump_values := {}
	for i in range(unknown_keys.size()):
		var key := String(unknown_keys[i])
		if key.begins_with("post:"): post[key.substr(5)] = float(x[i])
		else: jump_values[key.substr(5)] = float(x[i])
	for item in branch_spec["inequalities"]:
		var evaluated := _eval_expr_value(system, item["expr"], pre_states, pre_algebraics, float(system["time"]), post, jump_values, pre_states)
		if not bool(evaluated.get("ok",false)): return {"ok":false}
		if float(evaluated["value"])/maxf(float(item["nominal"]),EPSILON) < -GUARD_TOLERANCE: return {"ok":false}
	return {"ok":true}

# =============================================================================
# TOPOLOGY TRANSACTION
# =============================================================================

static func _validate_topology_transaction(system: Dictionary, ops: Array) -> Dictionary:
	if ops.is_empty(): return {"ok":true}
	var network: Dictionary = system["physical_network"]
	if network.is_empty() or not network.has("bonds"): return {"ok":false, "code":"TOPOLOGY_TRANSACTION_NO_NETWORK"}
	var seen := {}
	for op in ops:
		if String(op.get("op","")) != "set_bond_active": return {"ok":false, "code":"TOPOLOGY_TRANSACTION_UNSUPPORTED_OP"}
		var bond_id := String(op.get("bond_id",""))
		if bond_id.is_empty() or seen.has(bond_id): return {"ok":false, "code":"TOPOLOGY_TRANSACTION_DUPLICATE_OR_EMPTY_BOND"}
		seen[bond_id] = true
		if _find_bond_index(network,bond_id) < 0: return {"ok":false, "code":"TOPOLOGY_TRANSACTION_UNKNOWN_BOND", "bond_id":bond_id}
	return {"ok":true}

static func _commit_topology_transaction(system: Dictionary, ops: Array) -> bool:
	var changed := false
	for op in ops:
		var index := _find_bond_index(system["physical_network"], String(op["bond_id"]))
		var target := bool(op["active"])
		if bool(system["physical_network"]["bonds"][index]["active"]) != target:
			system["physical_network"]["bonds"][index]["active"] = target
			changed = true
	return changed

# =============================================================================
# DIMENSION INFERENCE
# =============================================================================

static func _infer_expr_dimension(system: Dictionary, expr: Dictionary, jump_dims: Dictionary) -> Dictionary:
	var op := String(expr.get("op",""))
	match op:
		"constant": return {"ok":true, "dimension":expr.get("dimension",{}).duplicate(true)}
		"state", "pre_state", "post_state":
			var name := String(expr.get("name",""))
			if not system["states"].has(name): return {"ok":false, "reason":"UNKNOWN_STATE", "name":name}
			return {"ok":true, "dimension":system["states"][name]["dimension"]}
		"algebraic":
			var name := String(expr.get("name",""))
			if not system["algebraics"].has(name): return {"ok":false, "reason":"UNKNOWN_ALGEBRAIC", "name":name}
			return {"ok":true, "dimension":system["algebraics"][name]["dimension"]}
		"jump":
			var key := "jump:%s" % String(expr.get("name",""))
			if not jump_dims.has(key): return {"ok":false, "reason":"UNKNOWN_JUMP_UNKNOWN", "name":String(expr.get("name",""))}
			return {"ok":true, "dimension":jump_dims[key]}
		"parameter":
			var name := String(expr.get("name",""))
			if not system["parameters"].has(name): return {"ok":false, "reason":"UNKNOWN_PARAMETER", "name":name}
			return {"ok":true, "dimension":system["parameters"][name]["dimension"]}
		"time": return {"ok":true, "dimension":dim_time()}
		"bond_active": return {"ok":true, "dimension":dim_dimensionless()}
		"neg": return _infer_expr_dimension(system, expr["a"], jump_dims)
		"add", "sub":
			var a := _infer_expr_dimension(system,expr["a"],jump_dims)
			if not bool(a.get("ok",false)): return a
			var b := _infer_expr_dimension(system,expr["b"],jump_dims)
			if not bool(b.get("ok",false)): return b
			if not dim_equal(a["dimension"],b["dimension"]): return {"ok":false, "reason":"ADD_SUB_DIMENSION_MISMATCH", "left":dim_string(a["dimension"]), "right":dim_string(b["dimension"])}
			return {"ok":true, "dimension":a["dimension"]}
		"mul", "div":
			var a := _infer_expr_dimension(system,expr["a"],jump_dims)
			if not bool(a.get("ok",false)): return a
			var b := _infer_expr_dimension(system,expr["b"],jump_dims)
			if not bool(b.get("ok",false)): return b
			return {"ok":true, "dimension":dim_mul(a["dimension"],b["dimension"]) if op=="mul" else dim_div(a["dimension"],b["dimension"])}
		"pow_int":
			var a := _infer_expr_dimension(system,expr["a"],jump_dims)
			if not bool(a.get("ok",false)): return a
			return {"ok":true, "dimension":dim_pow(a["dimension"],int(expr.get("exponent",1)))}
		_:
			return {"ok":false, "reason":"UNKNOWN_EXPRESSION_OP", "op":op}

# =============================================================================
# EXPRESSION EVALUATION / AD
# =============================================================================

static func _eval_expr_value(system: Dictionary, expr: Dictionary, states: Dictionary, algebraics: Dictionary, time_value: float, post_states: Dictionary, jump_values: Dictionary, pre_states: Dictionary) -> Dictionary:
	var op := String(expr.get("op",""))
	match op:
		"constant": return {"ok":true,"value":float(expr.get("value",0.0))}
		"state": return {"ok":true,"value":float(states[String(expr["name"])])}
		"pre_state": return {"ok":true,"value":float(pre_states[String(expr["name"])])}
		"post_state": return {"ok":true,"value":float(post_states[String(expr["name"])])}
		"algebraic": return {"ok":true,"value":float(algebraics[String(expr["name"])])}
		"jump": return {"ok":true,"value":float(jump_values[String(expr["name"])])}
		"parameter": return {"ok":true,"value":float(system["parameters"][String(expr["name"])]["value"])}
		"time": return {"ok":true,"value":time_value}
		"bond_active": return {"ok":true,"value":1.0 if _bond_active(system,String(expr["bond_id"])) else 0.0}
		"neg":
			var a := _eval_expr_value(system,expr["a"],states,algebraics,time_value,post_states,jump_values,pre_states)
			return {"ok":bool(a.get("ok",false)),"value":-float(a.get("value",0.0))}
		"add", "sub", "mul", "div":
			var a := _eval_expr_value(system,expr["a"],states,algebraics,time_value,post_states,jump_values,pre_states)
			var b := _eval_expr_value(system,expr["b"],states,algebraics,time_value,post_states,jump_values,pre_states)
			if not bool(a.get("ok",false)) or not bool(b.get("ok",false)): return {"ok":false}
			var av:=float(a["value"]); var bv:=float(b["value"])
			if op=="add": return {"ok":true,"value":av+bv}
			if op=="sub": return {"ok":true,"value":av-bv}
			if op=="mul": return {"ok":true,"value":av*bv}
			if absf(bv)<=1e-15: return {"ok":false,"code":"DIVISION_BY_ZERO"}
			return {"ok":true,"value":av/bv}
		"pow_int":
			var a := _eval_expr_value(system,expr["a"],states,algebraics,time_value,post_states,jump_values,pre_states)
			if not bool(a.get("ok",false)): return a
			return {"ok":true,"value":pow(float(a["value"]),int(expr.get("exponent",1)))}
	return {"ok":false,"code":"UNKNOWN_EXPRESSION_OP"}

static func _eval_expr_dual_algebraic(system: Dictionary, expr: Dictionary, states: Dictionary, algebraics: Dictionary, time_value: float, index: Dictionary) -> Dictionary:
	var op:=String(expr.get("op",""))
	if op=="algebraic":
		var name:=String(expr["name"]); var i:=int(index[name]); return {"ok":true,"value":float(algebraics[name]),"grad":{i:1.0}}
	if op in ["constant","state","parameter","time","bond_active"]:
		var v:=_eval_expr_value(system,expr,states,algebraics,time_value,{}, {}, states); return {"ok":bool(v.get("ok",false)),"value":float(v.get("value",0.0)),"grad":{}}
	return _eval_dual_recursive(system,expr,func(child): return _eval_expr_dual_algebraic(system,child,states,algebraics,time_value,index))

static func _eval_expr_dual_jump(system: Dictionary, expr: Dictionary, pre_states: Dictionary, post_states: Dictionary, jump_values: Dictionary, pre_algebraics: Dictionary, time_value: float, index: Dictionary) -> Dictionary:
	var op:=String(expr.get("op",""))
	if op=="post_state":
		var key:="post:%s" % String(expr["name"]); return {"ok":true,"value":float(post_states[String(expr["name"])]),"grad":{int(index[key]):1.0}}
	if op=="jump":
		var key:="jump:%s" % String(expr["name"]); return {"ok":true,"value":float(jump_values[String(expr["name"])]),"grad":{int(index[key]):1.0}}
	if op in ["constant","pre_state","parameter","time","bond_active","algebraic"]:
		var v:=_eval_expr_value(system,expr,pre_states,pre_algebraics,time_value,post_states,jump_values,pre_states); return {"ok":bool(v.get("ok",false)),"value":float(v.get("value",0.0)),"grad":{}}
	if op=="state":
		# During a jump, plain state refers to pre-state to keep semantics explicit and stable.
		return {"ok":true,"value":float(pre_states[String(expr["name"])]),"grad":{}}
	return _eval_dual_recursive(system,expr,func(child): return _eval_expr_dual_jump(system,child,pre_states,post_states,jump_values,pre_algebraics,time_value,index))

static func _eval_dual_recursive(_system: Dictionary, expr: Dictionary, recurse: Callable) -> Dictionary:
	var op:=String(expr.get("op",""))
	if op=="neg":
		var a:Dictionary=recurse.call(expr["a"]); if not bool(a.get("ok",false)): return a
		return {"ok":true,"value":-float(a["value"]),"grad":_grad_scaled(a["grad"],-1.0)}
	if op in ["add","sub","mul","div"]:
		var a:Dictionary=recurse.call(expr["a"]); if not bool(a.get("ok",false)): return a
		var b:Dictionary=recurse.call(expr["b"]); if not bool(b.get("ok",false)): return b
		var av:=float(a["value"]); var bv:=float(b["value"])
		if op=="add": return {"ok":true,"value":av+bv,"grad":_grad_combine(a["grad"],1.0,b["grad"],1.0)}
		if op=="sub": return {"ok":true,"value":av-bv,"grad":_grad_combine(a["grad"],1.0,b["grad"],-1.0)}
		if op=="mul": return {"ok":true,"value":av*bv,"grad":_grad_combine(a["grad"],bv,b["grad"],av)}
		if absf(bv)<=1e-15: return {"ok":false,"code":"DIVISION_BY_ZERO"}
		return {"ok":true,"value":av/bv,"grad":_grad_combine(a["grad"],1.0/bv,b["grad"],-av/(bv*bv))}
	if op=="pow_int":
		var a:Dictionary=recurse.call(expr["a"]); if not bool(a.get("ok",false)): return a
		var n:=int(expr.get("exponent",1)); var av:=float(a["value"])
		if n<0 and absf(av)<=1e-15: return {"ok":false,"code":"NEGATIVE_POWER_ZERO"}
		var value:=pow(av,n); var derivative:=0.0 if n==0 else float(n)*pow(av,n-1)
		return {"ok":true,"value":value,"grad":_grad_scaled(a["grad"],derivative)}
	return {"ok":false,"code":"UNKNOWN_EXPRESSION_OP","op":op}

# =============================================================================
# SNAPSHOT / HASH / HELPERS
# =============================================================================

static func _capture_snapshot(system: Dictionary) -> Dictionary:
	var bonds := {}
	if not system["physical_network"].is_empty() and system["physical_network"].has("bonds"):
		for bond in system["physical_network"]["bonds"]: bonds[String(bond["id"])] = bool(bond["active"])
	return {"time":float(system["time"]),"states":_state_values(system),"algebraics":_algebraic_values(system),"mode":String(system["mode"]),"events":system["events"].duplicate(true),"topology_revision":int(system["topology_revision"]),"step_revision":int(system["step_revision"]),"bonds":bonds,"solver_stats":system["solver_stats"].duplicate(true)}

static func _restore_snapshot(system: Dictionary, snapshot: Dictionary) -> void:
	system["time"]=float(snapshot["time"]); _commit_state_values(system,snapshot["states"]); _commit_algebraic_values(system,snapshot["algebraics"]); system["mode"]=String(snapshot["mode"]); system["events"]=snapshot["events"].duplicate(true); system["topology_revision"]=int(snapshot["topology_revision"]); system["step_revision"]=int(snapshot["step_revision"]); system["solver_stats"]=snapshot["solver_stats"].duplicate(true)
	for bond_id in snapshot["bonds"].keys():
		var i:=_find_bond_index(system["physical_network"],String(bond_id)); if i>=0: system["physical_network"]["bonds"][i]["active"]=bool(snapshot["bonds"][bond_id])

static func state_hash(system: Dictionary) -> String:
	var bonds: Array=[]
	if not system["physical_network"].is_empty() and system["physical_network"].has("bonds"):
		for bond in system["physical_network"]["bonds"]: bonds.append({"id":String(bond["id"]),"active":bool(bond["active"])})
		bonds.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return String(a["id"])<String(b["id"]))
	var payload:=JSON.stringify({"time":float(system["time"]),"mode":String(system["mode"]),"states":_state_values(system),"algebraics":_algebraic_values(system),"topology_revision":int(system["topology_revision"]),"bonds":bonds},"",false)
	var ctx:=HashingContext.new(); ctx.start(HashingContext.HASH_SHA256); ctx.update(payload.to_utf8_buffer()); return ctx.finish().hex_encode()

static func _state_values(system: Dictionary) -> Dictionary:
	var result := {}
	var keys: Array = system["states"].keys()
	keys.sort()
	for key in keys:
		result[key] = float(system["states"][key]["value"])
	return result

static func _algebraic_values(system: Dictionary) -> Dictionary:
	var result := {}
	var keys: Array = system["algebraics"].keys()
	keys.sort()
	for key in keys:
		result[key] = float(system["algebraics"][key]["value"])
	return result

static func _commit_state_values(system: Dictionary, values: Dictionary) -> void:
	for key in values.keys():
		system["states"][key]["value"] = float(values[key])

static func _commit_algebraic_values(system: Dictionary, values: Dictionary) -> void:
	for key in values.keys():
		system["algebraics"][key]["value"] = float(values[key])

static func _state_plus_scaled(state: Dictionary, derivative: Dictionary, scale: float) -> Dictionary:
	var result := state.duplicate(true)
	for key in result.keys():
		result[key] = float(state[key]) + scale * float(derivative[key])
	return result

static func _row_nominals(rows: Array) -> Array:
	var result: Array = []
	for row in rows:
		result.append(float(row["nominal"]))
	return result

static func _normalized_norm(values: Array, nominals: Array) -> float:
	var result := 0.0
	for i in range(values.size()):
		result = maxf(result, absf(float(values[i])) / maxf(float(nominals[i]), EPSILON))
	return result

static func _grad_scaled(source: Dictionary, scale: float) -> Dictionary:
	var result := {}
	for key in source.keys():
		result[key] = float(source[key]) * scale
	return result

static func _grad_combine(a: Dictionary, sa: float, b: Dictionary, sb: float) -> Dictionary:
	var result := {}
	for key_a in a.keys():
		result[key_a] = float(result.get(key_a, 0.0)) + float(a[key_a]) * sa
	for key_b in b.keys():
		result[key_b] = float(result.get(key_b, 0.0)) + float(b[key_b]) * sb
	return result

static func _zero_vector(size: int) -> Array:
	var r:Array=[]; r.resize(size); r.fill(0.0); return r

static func _zero_matrix(rows: int, cols: int) -> Array:
	var result:Array=[]
	for _r in range(rows): var row:Array=[]; row.resize(cols); row.fill(0.0); result.append(row)
	return result

static func _solve_dense(matrix: Array, rhs: Array) -> Dictionary:
	var n := rhs.size()
	if matrix.size() != n:
		return {"ok": false}
	if n == 0:
		return {"ok": true, "x": []}
	var a: Array = []
	var b: Array = []
	for r in range(n):
		if matrix[r].size() != n:
			return {"ok": false}
		var row: Array = []
		for c in range(n):
			row.append(float(matrix[r][c]))
		a.append(row)
		b.append(float(rhs[r]))
	for col in range(n):
		var pivot := col
		var pivot_abs := absf(float(a[col][col]))
		for r in range(col + 1, n):
			var candidate := absf(float(a[r][col]))
			if candidate > pivot_abs:
				pivot = r
				pivot_abs = candidate
		if pivot_abs <= PIVOT_EPSILON:
			return {"ok": false}
		if pivot != col:
			var tmp_row = a[col]
			a[col] = a[pivot]
			a[pivot] = tmp_row
			var tmp_b = b[col]
			b[col] = b[pivot]
			b[pivot] = tmp_b
		var pv := float(a[col][col])
		for c in range(col, n):
			a[col][c] = float(a[col][c]) / pv
		b[col] = float(b[col]) / pv
		for r in range(n):
			if r == col:
				continue
			var factor := float(a[r][col])
			if absf(factor) <= EPSILON:
				continue
			for c in range(col, n):
				a[r][c] = float(a[r][c]) - factor * float(a[col][c])
			b[r] = float(b[r]) - factor * float(b[col])
	return {"ok": true, "x": b}

static func _find_bond_index(network: Dictionary, bond_id: String) -> int:
	if network.is_empty() or not network.has("bonds"):return -1
	for i in range(network["bonds"].size()): if String(network["bonds"][i].get("id",""))==bond_id:return i
	return -1

static func _bond_active(system: Dictionary, bond_id: String) -> bool:
	var i:=_find_bond_index(system["physical_network"],bond_id); return i>=0 and bool(system["physical_network"]["bonds"][i]["active"])
