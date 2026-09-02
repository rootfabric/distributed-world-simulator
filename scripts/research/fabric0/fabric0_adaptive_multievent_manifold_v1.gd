class_name Fabric0AdaptiveMultiEventManifoldV1
extends RefCounted

const EPS := 1.0e-14
const EVENT_TIME_TOLERANCE := 1.0e-12
const MAX_EVENT_BISECTION := 80
const DEFAULT_ATOL := 1.0e-10
const DEFAULT_RTOL := 1.0e-10
const DEFAULT_INITIAL_STEP := 0.12
const DEFAULT_MIN_STEP := 1.0e-7
const DEFAULT_MAX_STEP := 0.25
const DEFAULT_MAX_STEPS := 100000

# =============================================================================
# ORIENTATION-AWARE CORNER MANIFOLD
# =============================================================================

static func new_corner_system(theta: float = -0.3, omega: float = 1.2, frequency: float = 4.0, hx: float = 0.5, hy: float = 0.3) -> Dictionary:
	var side := -1 if theta < 0.0 else 1
	var system := {
		"time": 0.0,
		"theta": theta,
		"omega": omega,
		"frequency": frequency,
		"hx": hx,
		"hy": hy,
		"side": side,
		"warm_cache": {},
		"events": [],
		"accepted_steps": 0,
		"rejected_steps": 0,
		"min_accepted_step": INF,
		"max_accepted_step": 0.0,
		"max_constraint_residual": 0.0,
		"energy_initial": _energy(theta, omega, frequency),
		"energy_final": _energy(theta, omega, frequency),
	}
	_update_constraint_audit(system)
	return system

static func seed_warm_cache(system: Dictionary, floor_impulse: float, wall_impulse: float) -> void:
	var contacts := current_contacts(system)
	for contact in contacts:
		if String(contact["plane"]) == "floor":
			system["warm_cache"][String(contact["id"])] = floor_impulse
		else:
			system["warm_cache"][String(contact["id"])] = wall_impulse

static func current_contacts(system: Dictionary) -> Array:
	return _vertex_contacts(int(system["side"]))

static func algebraic_center(system: Dictionary, theta_override = null, side_override = null) -> Vector2:
	var theta := float(system["theta"]) if theta_override == null else float(theta_override)
	var side := int(system["side"]) if side_override == null else int(side_override)
	var hx := float(system["hx"])
	var hy := float(system["hy"])
	if absf(theta) <= EPS:
		return Vector2(hx, hy)
	var vertices := _local_vertices(hx, hy)
	var wall_vertex: Vector2
	var floor_vertex: Vector2
	if side < 0:
		wall_vertex = vertices["BL"]
		floor_vertex = vertices["BR"]
	else:
		wall_vertex = vertices["TL"]
		floor_vertex = vertices["BL"]
	var rw := _rotate(wall_vertex, theta)
	var rf := _rotate(floor_vertex, theta)
	return Vector2(-rw.x, -rf.y)

static func contact_gaps(system: Dictionary, contacts: Array, theta_override = null, side_override = null) -> Dictionary:
	var theta := float(system["theta"]) if theta_override == null else float(theta_override)
	var side := int(system["side"]) if side_override == null else int(side_override)
	var center := algebraic_center(system, theta, side)
	var vertices := _local_vertices(float(system["hx"]), float(system["hy"]))
	var result := {}
	for contact in contacts:
		var feature := String(contact["feature"])
		var plane := String(contact["plane"])
		var lineage: Array = contact["lineage"]
		var max_abs := 0.0
		for vertex_id in lineage:
			var p := center + _rotate(vertices[String(vertex_id)], theta)
			var gap := p.y if plane == "floor" else p.x
			max_abs = maxf(max_abs, absf(gap))
		result[String(contact["id"])] = max_abs
	return result

static func _vertex_contacts(side: int) -> Array:
	if side < 0:
		return [
			_contact("floor|vertex:BR", "floor", "vertex:BR", ["BR"]),
			_contact("wall|vertex:BL", "wall", "vertex:BL", ["BL"]),
		]
	return [
		_contact("floor|vertex:BL", "floor", "vertex:BL", ["BL"]),
		_contact("wall|vertex:TL", "wall", "vertex:TL", ["TL"]),
	]

static func _degenerate_edge_contacts() -> Array:
	return [
		_contact("floor|edge:bottom", "floor", "edge:bottom", ["BL", "BR"]),
		_contact("wall|edge:left", "wall", "edge:left", ["BL", "TL"]),
	]

static func _contact(id: String, plane: String, feature: String, lineage: Array) -> Dictionary:
	return {"id": id, "plane": plane, "feature": feature, "lineage": lineage.duplicate(true)}

static func _local_vertices(hx: float, hy: float) -> Dictionary:
	return {
		"BL": Vector2(-hx, -hy),
		"BR": Vector2(hx, -hy),
		"TL": Vector2(-hx, hy),
		"TR": Vector2(hx, hy),
	}

static func _rotate(v: Vector2, theta: float) -> Vector2:
	var c := cos(theta)
	var s := sin(theta)
	return Vector2(c * v.x - s * v.y, s * v.x + c * v.y)

# =============================================================================
# GENERIC FEATURE-LINEAGE WARM REMAP
# =============================================================================

static func remap_warm_cache(old_contacts: Array, old_cache: Dictionary, new_contacts: Array) -> Dictionary:
	var result := {}
	for contact in new_contacts:
		result[String(contact["id"])] = 0.0
	for old_contact in old_contacts:
		var old_id := String(old_contact["id"])
		if not old_cache.has(old_id):
			continue
		var candidates: Array = []
		var total_score := 0.0
		for new_contact in new_contacts:
			if String(new_contact["plane"]) != String(old_contact["plane"]):
				continue
			var overlap := _lineage_overlap(old_contact["lineage"], new_contact["lineage"])
			if overlap > 0:
				var score := float(overlap)
				candidates.append({"id": String(new_contact["id"]), "score": score})
				total_score += score
		if total_score <= 0.0:
			continue
		for candidate in candidates:
			var weight := float(candidate["score"]) / total_score
			var id := String(candidate["id"])
			result[id] = float(result[id]) + float(old_cache[old_id]) * weight
	return result

static func _lineage_overlap(a: Array, b: Array) -> int:
	var set_b := {}
	for item in b:
		set_b[String(item)] = true
	var count := 0
	for item in a:
		if set_b.has(String(item)):
			count += 1
	return count

static func synthetic_split_remap(value: float) -> Dictionary:
	var old_contacts := [_contact("floor|edge:bottom", "floor", "edge:bottom", ["BL", "BR"])]
	var old_cache := {"floor|edge:bottom": value}
	var new_contacts := [
		_contact("floor|vertex:BL", "floor", "vertex:BL", ["BL"]),
		_contact("floor|vertex:BR", "floor", "vertex:BR", ["BR"]),
	]
	return remap_warm_cache(old_contacts, old_cache, new_contacts)

static func synthetic_merge_remap(bl_value: float, br_value: float) -> Dictionary:
	var old_contacts := [
		_contact("floor|vertex:BL", "floor", "vertex:BL", ["BL"]),
		_contact("floor|vertex:BR", "floor", "vertex:BR", ["BR"]),
	]
	var old_cache := {"floor|vertex:BL": bl_value, "floor|vertex:BR": br_value}
	var new_contacts := [_contact("floor|edge:bottom", "floor", "edge:bottom", ["BL", "BR"])]
	return remap_warm_cache(old_contacts, old_cache, new_contacts)

# =============================================================================
# SAME-TIME MANIFOLD EVENT ITERATION
# =============================================================================

static func process_zero_event(system: Dictionary, direction: int) -> Dictionary:
	var old_contacts := current_contacts(system)
	var old_cache: Dictionary = system["warm_cache"].duplicate(true)
	var transitions: Array = []

	# Iteration 1: exact degeneracy exposes edge features.
	var edges := _degenerate_edge_contacts()
	var edge_cache := remap_warm_cache(old_contacts, old_cache, edges)
	transitions.append(_transition_record(old_contacts, edges, old_cache, edge_cache, "vertex_to_degenerate_edge"))

	# Iteration 2: right-limit direction selects the post-event support vertices.
	var new_side := 1 if direction > 0 else -1
	var post_contacts := _vertex_contacts(new_side)
	var post_cache := remap_warm_cache(edges, edge_cache, post_contacts)
	transitions.append(_transition_record(edges, post_contacts, edge_cache, post_cache, "degenerate_edge_to_directed_vertex"))

	# Iteration 3: recompile directed manifold; no further topology change => fixed point.
	system["side"] = new_side
	system["warm_cache"] = post_cache
	var fixed_contacts := current_contacts(system)
	var fixed := _contact_ids(fixed_contacts) == _contact_ids(post_contacts)
	var event := {
		"event_id": "fabric0.12/manifold/%03d" % (system["events"].size() + 1),
		"time": float(system["time"]),
		"direction": direction,
		"iterations": 3,
		"topology_mutations": 2,
		"fixed_point": fixed,
		"transitions": transitions,
		"final_contact_ids": _contact_ids(fixed_contacts),
		"final_warm_cache": post_cache.duplicate(true),
	}
	system["events"].append(event)
	_update_constraint_audit(system)
	return event

static func _transition_record(old_contacts: Array, new_contacts: Array, old_cache: Dictionary, new_cache: Dictionary, kind: String) -> Dictionary:
	var old_ids := _contact_ids(old_contacts)
	var new_ids := _contact_ids(new_contacts)
	return {
		"kind": kind,
		"old_ids": old_ids,
		"new_ids": new_ids,
		"appeared": _array_difference(new_ids, old_ids),
		"disappeared": _array_difference(old_ids, new_ids),
		"warm_before": _cache_subset(old_cache, old_ids),
		"warm_after": _cache_subset(new_cache, new_ids),
	}

# =============================================================================
# ADAPTIVE CONSTRAINED TIME INTEGRATION
# =============================================================================

static func advance_adaptive(system: Dictionary, duration: float, options: Dictionary = {}) -> Dictionary:
	if duration <= 0.0:
		return {"ok": false, "code": "DURATION_NONPOSITIVE"}
	var atol := float(options.get("atol", DEFAULT_ATOL))
	var rtol := float(options.get("rtol", DEFAULT_RTOL))
	var h := float(options.get("initial_step", DEFAULT_INITIAL_STEP))
	var min_step := float(options.get("min_step", DEFAULT_MIN_STEP))
	var max_step := float(options.get("max_step", DEFAULT_MAX_STEP))
	var max_steps := int(options.get("max_steps", DEFAULT_MAX_STEPS))
	if atol <= 0.0 or rtol <= 0.0 or min_step <= 0.0 or max_step <= 0.0 or h <= 0.0:
		return {"ok": false, "code": "BAD_ADAPTIVE_OPTIONS"}
	var end_time := float(system["time"]) + duration
	var iterations := 0
	while float(system["time"]) < end_time - EPS:
		iterations += 1
		if iterations > max_steps:
			return {"ok": false, "code": "ADAPTIVE_MAX_STEPS"}
		h = minf(h, end_time - float(system["time"]))
		h = minf(h, max_step)
		if h < min_step:
			return {"ok": false, "code": "ADAPTIVE_STEP_UNDERFLOW", "h": h}
		var start_state := Vector2(float(system["theta"]), float(system["omega"]))
		var trial := _step_doubling(start_state, h, float(system["frequency"]), atol, rtol)
		var err := float(trial["error_norm"])
		if err > 1.0:
			system["rejected_steps"] = int(system["rejected_steps"]) + 1
			var shrink := clampf(0.9 * pow(1.0 / err, 0.2), 0.1, 0.5)
			h = maxf(min_step, h * shrink)
			continue
		var end_state: Vector2 = trial["state"]
		var crossing := start_state.x * end_state.x < 0.0
		if crossing:
			var localized := _localize_zero(start_state, h, float(system["frequency"]), EVENT_TIME_TOLERANCE)
			var event_dt := float(localized["dt"])
			var event_state: Vector2 = localized["state"]
			system["time"] = float(system["time"]) + event_dt
			system["theta"] = 0.0
			system["omega"] = event_state.y
			system["accepted_steps"] = int(system["accepted_steps"]) + 1
			system["min_accepted_step"] = minf(float(system["min_accepted_step"]), event_dt)
			system["max_accepted_step"] = maxf(float(system["max_accepted_step"]), event_dt)
			_update_constraint_audit(system)
			var direction := 1 if event_state.y > 0.0 else -1
			var event := process_zero_event(system, direction)
			event["bisection_iterations"] = int(localized["iterations"])
			event["localized_dt"] = event_dt
			# Restart integration from the event fixed point. Do not consume the rest of
			# the old candidate step under stale manifold semantics.
			h = clampf(maxf(min_step, minf(h - event_dt, h * 0.5)), min_step, max_step)
			continue

		# Accept the higher-accuracy two-half-step state.
		system["theta"] = end_state.x
		system["omega"] = end_state.y
		system["time"] = float(system["time"]) + h
		system["accepted_steps"] = int(system["accepted_steps"]) + 1
		system["min_accepted_step"] = minf(float(system["min_accepted_step"]), h)
		system["max_accepted_step"] = maxf(float(system["max_accepted_step"]), h)
		_update_constraint_audit(system)
		var factor := 2.5 if err <= 1.0e-16 else clampf(0.9 * pow(1.0 / maxf(err, 1.0e-16), 0.2), 0.5, 2.5)
		h = clampf(h * factor, min_step, max_step)

	system["energy_final"] = _energy(float(system["theta"]), float(system["omega"]), float(system["frequency"]))
	return {
		"ok": true,
		"time": float(system["time"]),
		"events": system["events"].duplicate(true),
		"accepted_steps": int(system["accepted_steps"]),
		"rejected_steps": int(system["rejected_steps"]),
		"min_accepted_step": float(system["min_accepted_step"]),
		"max_accepted_step": float(system["max_accepted_step"]),
		"max_constraint_residual": float(system["max_constraint_residual"]),
		"energy_initial": float(system["energy_initial"]),
		"energy_final": float(system["energy_final"]),
		"energy_drift": float(system["energy_final"]) - float(system["energy_initial"]),
		"state_hash": system_hash(system),
	}

static func _step_doubling(state: Vector2, h: float, frequency: float, atol: float, rtol: float) -> Dictionary:
	var full := _rk4(state, h, frequency)
	var half := _rk4(state, 0.5 * h, frequency)
	var two_half := _rk4(half, 0.5 * h, frequency)
	var dtheta := absf(two_half.x - full.x) / 15.0
	var domega := absf(two_half.y - full.y) / 15.0
	var scale_theta := atol + rtol * maxf(absf(state.x), absf(two_half.x))
	var scale_omega := atol + rtol * maxf(absf(state.y), absf(two_half.y))
	var err := maxf(dtheta / scale_theta, domega / scale_omega)
	return {"state": two_half, "error_norm": err, "raw_difference": Vector2(two_half.x - full.x, two_half.y - full.y)}

static func _rk4(state: Vector2, h: float, frequency: float) -> Vector2:
	var k1 := _derivative(state, frequency)
	var k2 := _derivative(state + 0.5 * h * k1, frequency)
	var k3 := _derivative(state + 0.5 * h * k2, frequency)
	var k4 := _derivative(state + h * k3, frequency)
	return state + (h / 6.0) * (k1 + 2.0 * k2 + 2.0 * k3 + k4)

static func _derivative(state: Vector2, frequency: float) -> Vector2:
	return Vector2(state.y, -frequency * frequency * state.x)

static func _localize_zero(start: Vector2, h: float, frequency: float, tolerance: float) -> Dictionary:
	var lo := 0.0
	var hi := h
	var theta_lo := start.x
	var iterations := 0
	for iteration in range(MAX_EVENT_BISECTION):
		iterations = iteration + 1
		if hi - lo <= tolerance:
			break
		var mid := 0.5 * (lo + hi)
		var state_mid := _rk4(_rk4(start, 0.5 * mid, frequency), 0.5 * mid, frequency)
		if theta_lo * state_mid.x <= 0.0:
			hi = mid
		else:
			lo = mid
			theta_lo = state_mid.x
	var dt := 0.5 * (lo + hi)
	var state := _rk4(_rk4(start, 0.5 * dt, frequency), 0.5 * dt, frequency)
	return {"dt": dt, "state": state, "iterations": iterations}

static func analytic_zero_times(theta0: float, omega0: float, frequency: float, duration: float) -> Array:
	# theta=A*cos(wt)+B*sin(wt), B=omega0/w.
	var a := theta0
	var b := omega0 / frequency
	var phase := atan2(-a, b) # solves a*cos(x)+b*sin(x)=0 near the first positive x.
	if phase < 0.0:
		phase += PI
	var result: Array = []
	var x := phase
	while x / frequency <= duration + 1.0e-14:
		if x > 1.0e-14:
			result.append(x / frequency)
		x += PI
	return result

static func _energy(theta: float, omega: float, frequency: float) -> float:
	return 0.5 * omega * omega + 0.5 * frequency * frequency * theta * theta

static func _update_constraint_audit(system: Dictionary) -> void:
	var gaps := contact_gaps(system, current_contacts(system))
	for value in gaps.values():
		system["max_constraint_residual"] = maxf(float(system["max_constraint_residual"]), absf(float(value)))

# =============================================================================
# SPARSE PATTERN/PRECONDITIONER CACHE + ACTUAL THREAD PARALLELISM
# =============================================================================

static func new_pattern_cache() -> Dictionary:
	return {"entries": {}, "hits": 0, "misses": 0}

static func sparse_pattern_key(island_id: String, matrix: Array) -> String:
	var rows: Array = []
	for row_index in range(matrix.size()):
		var cols: Array = matrix[row_index].keys()
		cols.sort()
		rows.append({"r": row_index, "c": cols})
	return "%s|%s" % [island_id, JSON.stringify(rows, "", false)]

static func prepare_cached_preconditioner(cache: Dictionary, island_id: String, matrix: Array) -> Dictionary:
	var key := sparse_pattern_key(island_id, matrix)
	if cache["entries"].has(key):
		cache["hits"] = int(cache["hits"]) + 1
		return {"key": key, "inverse_diagonal": cache["entries"][key]["inverse_diagonal"].duplicate(true), "cache_hit": true}
	var inverse_diagonal: Array = []
	for row_index in range(matrix.size()):
		var diagonal := float(matrix[row_index].get(row_index, 0.0))
		if diagonal <= EPS:
			return {"ok": false, "code": "PATTERN_NONPOSITIVE_DIAGONAL", "row": row_index}
		inverse_diagonal.append(1.0 / diagonal)
	cache["entries"][key] = {"inverse_diagonal": inverse_diagonal.duplicate(true)}
	cache["misses"] = int(cache["misses"]) + 1
	return {"key": key, "inverse_diagonal": inverse_diagonal, "cache_hit": false, "ok": true}

func solve_islands_parallel(tasks: Array, cache: Dictionary, reverse_spawn: bool = false) -> Dictionary:
	var prepared: Array = []
	var canonical: Array = tasks.duplicate(true)
	canonical.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	var hits_before := int(cache["hits"])
	var misses_before := int(cache["misses"])
	for task in canonical:
		var prep := prepare_cached_preconditioner(cache, String(task["id"]), task["matrix"])
		if prep.has("ok") and not bool(prep["ok"]):
			return prep
		var t: Dictionary = task.duplicate(true)
		t["inverse_diagonal"] = prep["inverse_diagonal"]
		t["pattern_key"] = prep["key"]
		t["cache_hit"] = bool(prep["cache_hit"])
		prepared.append(t)
	var spawn: Array = prepared.duplicate(true)
	if reverse_spawn:
		spawn.reverse()
	var records: Array = []
	for task in spawn:
		var thread := Thread.new()
		var error := thread.start(Callable(self, "_thread_solve_task").bind(task.duplicate(true)))
		if error != OK:
			return {"ok": false, "code": "THREAD_START_FAILED", "error": error}
		records.append({"thread": thread, "id": String(task["id"])})
	var results: Array = []
	for record in records:
		var solved = record["thread"].wait_to_finish()
		if typeof(solved) != TYPE_DICTIONARY or not bool(solved.get("ok", false)):
			return {"ok": false, "code": "THREAD_SOLVE_FAILED", "result": solved}
		results.append(solved)
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	return {
		"ok": true,
		"parallel": true,
		"threads_started": records.size(),
		"results": results,
		"cache_hits": int(cache["hits"]) - hits_before,
		"cache_misses": int(cache["misses"]) - misses_before,
		"hash": parallel_results_hash(results),
	}

func _thread_solve_task(task: Dictionary) -> Dictionary:
	var solved := _pcg_cached(task["matrix"], task["rhs"], task["inverse_diagonal"], float(task.get("tolerance", 1.0e-12)), int(task.get("max_iterations", 128)))
	solved["id"] = String(task["id"])
	solved["pattern_key"] = String(task["pattern_key"])
	solved["cache_hit"] = bool(task["cache_hit"])
	return solved

static func _pcg_cached(matrix: Array, rhs: Array, inverse_diagonal: Array, tolerance: float, max_iterations: int) -> Dictionary:
	var n := rhs.size()
	var x := _zero_array(n)
	var r: Array = rhs.duplicate(true)
	var z := _zero_array(n)
	for i in range(n):
		z[i] = float(r[i]) * float(inverse_diagonal[i])
	var p: Array = z.duplicate(true)
	var rz_old := _dot_array(r, z)
	var rhs_norm := sqrt(_dot_array(rhs, rhs))
	var target := tolerance * maxf(1.0, rhs_norm)
	if sqrt(_dot_array(r, r)) <= target:
		return {"ok": true, "x": x, "iterations": 0, "residual": sqrt(_dot_array(r, r))}
	for iteration in range(max_iterations):
		var ap := _sparse_mat_vec(matrix, p)
		var denom := _dot_array(p, ap)
		if denom <= 0.0:
			return {"ok": false, "code": "PCG_NONPOSITIVE_CURVATURE"}
		var alpha := rz_old / denom
		for i in range(n):
			x[i] = float(x[i]) + alpha * float(p[i])
			r[i] = float(r[i]) - alpha * float(ap[i])
		var residual := sqrt(_dot_array(r, r))
		if residual <= target:
			return {"ok": true, "x": x, "iterations": iteration + 1, "residual": residual}
		for i in range(n):
			z[i] = float(r[i]) * float(inverse_diagonal[i])
		var rz_new := _dot_array(r, z)
		if absf(rz_old) <= 1.0e-30:
			return {"ok": false, "code": "PCG_BREAKDOWN"}
		var beta := rz_new / rz_old
		for i in range(n):
			p[i] = float(z[i]) + beta * float(p[i])
		rz_old = rz_new
	return {"ok": false, "code": "PCG_NO_CONVERGENCE", "iterations": max_iterations}

static func _sparse_mat_vec(matrix: Array, vector: Array) -> Array:
	var result := _zero_array(matrix.size())
	for row_index in range(matrix.size()):
		var sum := 0.0
		for column in matrix[row_index].keys():
			sum += float(matrix[row_index][column]) * float(vector[int(column)])
		result[row_index] = sum
	return result

static func parallel_results_hash(results: Array) -> String:
	var payload: Array = []
	for result in results:
		payload.append({"id": String(result["id"]), "x": result["x"], "pattern_key": String(result["pattern_key"])})
	payload.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	return _sha256(JSON.stringify(payload, "", false))

# =============================================================================
# DERIVED SLEEP / WAKE COMPUTATIONAL STATE
# =============================================================================

static func new_sleep_tracker() -> Dictionary:
	return {"entries": {}}

static func update_sleep_state(tracker: Dictionary, island_id: String, speed_metric: float, constraint_residual: float, quiet_required: int = 3, speed_threshold: float = 1.0e-8, residual_threshold: float = 1.0e-8) -> Dictionary:
	var previous: Dictionary = tracker["entries"].get(island_id, {"quiet_steps": 0, "sleeping": false})
	var quiet := speed_metric <= speed_threshold and constraint_residual <= residual_threshold
	var quiet_steps := int(previous["quiet_steps"]) + 1 if quiet else 0
	var sleeping := quiet_steps >= quiet_required
	var woke := bool(previous["sleeping"]) and not sleeping
	var slept := not bool(previous["sleeping"]) and sleeping
	var state := {"quiet_steps": quiet_steps, "sleeping": sleeping, "woke": woke, "slept": slept}
	tracker["entries"][island_id] = state.duplicate(true)
	return state

# =============================================================================
# CANONICAL EVIDENCE
# =============================================================================

static func system_hash(system: Dictionary) -> String:
	var warm_keys: Array = system["warm_cache"].keys(); warm_keys.sort()
	var warm := []
	for key in warm_keys:
		warm.append({"id": String(key), "value": float(system["warm_cache"][key])})
	var events := []
	for event in system["events"]:
		events.append({
			"time": float(event["time"]),
			"direction": int(event["direction"]),
			"final_contact_ids": event["final_contact_ids"],
			"topology_mutations": int(event["topology_mutations"]),
		})
	return _sha256(JSON.stringify({
		"time": float(system["time"]),
		"theta": float(system["theta"]),
		"omega": float(system["omega"]),
		"side": int(system["side"]),
		"warm": warm,
		"events": events,
	}, "", false))

static func _sha256(text: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(text.to_utf8_buffer())
	return context.finish().hex_encode()

static func _contact_ids(contacts: Array) -> Array:
	var ids: Array = []
	for contact in contacts:
		ids.append(String(contact["id"]))
	ids.sort()
	return ids

static func _array_difference(a: Array, b: Array) -> Array:
	var set_b := {}
	for item in b: set_b[String(item)] = true
	var result: Array = []
	for item in a:
		if not set_b.has(String(item)): result.append(String(item))
	result.sort()
	return result

static func _cache_subset(cache: Dictionary, ids: Array) -> Dictionary:
	var result := {}
	for id in ids:
		if cache.has(id): result[String(id)] = float(cache[id])
	return result

static func _zero_array(size: int) -> Array:
	var result: Array = []
	result.resize(size)
	result.fill(0.0)
	return result

static func _dot_array(a: Array, b: Array) -> float:
	var result := 0.0
	for i in range(a.size()): result += float(a[i]) * float(b[i])
	return result
