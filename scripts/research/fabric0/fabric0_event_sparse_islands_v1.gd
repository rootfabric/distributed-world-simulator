class_name Fabric0EventSparseIslandsV1
extends RefCounted

const Prev = preload("res://scripts/research/fabric0/fabric0_persistent_contact_graph_v1.gd")

const EPS := 1.0e-12
const DEFAULT_RHO := 0.2
const DEFAULT_ADMM_TOLERANCE := 1.0e-10
const DEFAULT_ADMM_MAX_ITERATIONS := 5000
const DEFAULT_PCG_TOLERANCE := 1.0e-12
const DEFAULT_PCG_MAX_ITERATIONS := 128
const DEFAULT_MAX_SUBSTEP := 0.01
const EVENT_TIME_TOLERANCE := 1.0e-11
const EVENT_LOCALIZATION_ITERATIONS := 64
const BAUMGARTE := 0.2
const IMPACT_SPEED_THRESHOLD := 0.5

# =============================================================================
# PUBLIC WRAPPERS / CONTRACT
# =============================================================================

static func new_world(gravity: Vector3 = Vector3(0.0, -9.81, 0.0)) -> Dictionary:
	return Prev.new_world(gravity)

static func new_sphere_body(
	body_id: String,
	mass: float,
	radius: float,
	position: Vector3,
	linear_velocity: Vector3 = Vector3.ZERO,
	angular_velocity: Vector3 = Vector3.ZERO,
	friction: float = 0.5,
	restitution: float = 0.0,
	dynamic: bool = true
) -> Dictionary:
	return Prev.new_sphere_body(body_id, mass, radius, position, linear_velocity, angular_velocity, friction, restitution, dynamic)

static func new_plane(plane_id: String, normal: Vector3, offset: float, friction: float = 0.5, restitution: float = 0.0) -> Dictionary:
	return Prev.new_plane(plane_id, normal, offset, friction, restitution)

static func add_body(world: Dictionary, body: Dictionary) -> bool:
	return Prev.add_body(world, body)

static func compile_contacts(world: Dictionary, planes: Array, tolerance: float = Prev.CONTACT_TOLERANCE) -> Dictionary:
	return Prev.compile_sphere_contacts(world, planes, tolerance)

static func world_hash(world: Dictionary) -> String:
	return Prev.world_hash(world)

# =============================================================================
# TRUE SPARSE CONTACT STEP
# =============================================================================

# Same physical contact grammar as FABRIC0.10, but the ADMM linear subproblem is
# solved directly on sparse row dictionaries with Jacobi-preconditioned PCG.
# No dense effective-mass matrix or dense factorization is constructed.
static func step_sparse(world: Dictionary, provider_contacts: Array, dt: float, options: Dictionary = {}) -> Dictionary:
	if dt <= 0.0:
		return {"ok": false, "code": "DT_NONPOSITIVE"}
	var graph: Dictionary
	if bool(options.get("_skip_graph_update", false)):
		var contacts_copy: Array = provider_contacts.duplicate(true)
		contacts_copy.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
		graph = {
			"ok": true,
			"contacts": contacts_copy,
			"lifecycle": {
				"step": int(world["step"]),
				"time": float(world["time"]),
				"appeared": [],
				"persisted": _sorted_contact_ids(contacts_copy),
				"disappeared": [],
			},
		}
	else:
		graph = Prev.update_contact_graph(world, provider_contacts)
		if not bool(graph.get("ok", false)):
			return graph
	var contacts: Array = graph["contacts"]
	var islands: Array = Prev.compile_islands(world, contacts)
	world["last_islands"] = islands.duplicate(true)

	var free := {}
	var body_ids: Array = world["bodies"].keys()
	body_ids.sort()
	for id in body_ids:
		var body: Dictionary = world["bodies"][id]
		if bool(body["dynamic"]):
			free[id] = {
				"linear": body["linear_velocity"] + world["gravity"] * dt,
				"angular": body["angular_velocity"],
			}

	var schedule: Array = islands.duplicate(true)
	if bool(options.get("reverse_island_schedule", false)):
		schedule.reverse()
	var island_results: Array = []
	var stats := _empty_stats()
	for island in schedule:
		var solved := _solve_island_sparse(world, island, free, dt, options)
		if not bool(solved.get("ok", false)):
			return solved
		island_results.append(solved)
		_accumulate_stats(stats, solved)
		for id in solved["post_velocities"].keys():
			free[id] = solved["post_velocities"][id]
		for contact_id in solved["impulse_by_id"].keys():
			if world["contact_cache"].has(contact_id):
				world["contact_cache"][contact_id]["warm_impulse"] = solved["impulse_by_id"][contact_id]

	# Deterministic commit is by body identity, independent of island solve schedule.
	for id in body_ids:
		var body: Dictionary = world["bodies"][id]
		if not bool(body["dynamic"]):
			continue
		body["linear_velocity"] = free[id]["linear"]
		body["angular_velocity"] = free[id]["angular"]
		body["position"] = body["position"] + body["linear_velocity"] * dt

	world["time"] = float(world["time"]) + dt
	world["step"] = int(world["step"]) + 1
	stats["island_count"] = islands.size()
	stats["max_island_count"] = islands.size()
	stats["island_solve_count"] = islands.size()
	stats["linear_backend"] = "SPARSE_PCG"
	stats["dense_materializations"] = 0
	world["solver_stats"] = stats.duplicate(true)
	island_results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["island_id"]) < String(b["island_id"]))
	return {
		"ok": true,
		"lifecycle": graph["lifecycle"],
		"islands": island_results,
		"solver_stats": stats,
		"state_hash": Prev.world_hash(world),
	}

# Resolve a newly compiled graph at the current physical time without advancing
# differential time. This is the same-time graph recompile/jump solve used by
# event-localized contact creation.
static func resolve_current_contacts_sparse(world: Dictionary, provider_contacts: Array, reference_dt: float, options: Dictionary = {}) -> Dictionary:
	if reference_dt <= 0.0:
		return {"ok": false, "code": "REFERENCE_DT_NONPOSITIVE"}
	var graph := Prev.update_contact_graph(world, provider_contacts)
	if not bool(graph.get("ok", false)):
		return graph
	var contacts: Array = graph["contacts"]
	var islands: Array = Prev.compile_islands(world, contacts)
	world["last_islands"] = islands.duplicate(true)
	var free := {}
	var body_ids: Array = world["bodies"].keys()
	body_ids.sort()
	for id in body_ids:
		var body: Dictionary = world["bodies"][id]
		if bool(body["dynamic"]):
			free[id] = {"linear": body["linear_velocity"], "angular": body["angular_velocity"]}

	var schedule: Array = islands.duplicate(true)
	if bool(options.get("reverse_island_schedule", false)):
		schedule.reverse()
	var island_results: Array = []
	var stats := _empty_stats()
	for island in schedule:
		var solved := _solve_island_sparse(world, island, free, reference_dt, options)
		if not bool(solved.get("ok", false)):
			return solved
		island_results.append(solved)
		_accumulate_stats(stats, solved)
		for id in solved["post_velocities"].keys():
			free[id] = solved["post_velocities"][id]
		for contact_id in solved["impulse_by_id"].keys():
			if world["contact_cache"].has(contact_id):
				world["contact_cache"][contact_id]["warm_impulse"] = solved["impulse_by_id"][contact_id]

	for id in body_ids:
		var body: Dictionary = world["bodies"][id]
		if bool(body["dynamic"]):
			body["linear_velocity"] = free[id]["linear"]
			body["angular_velocity"] = free[id]["angular"]
	stats["island_count"] = islands.size()
	stats["max_island_count"] = islands.size()
	stats["island_solve_count"] = islands.size()
	stats["linear_backend"] = "SPARSE_PCG"
	stats["dense_materializations"] = 0
	island_results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["island_id"]) < String(b["island_id"]))
	return {
		"ok": true,
		"lifecycle": graph["lifecycle"],
		"islands": island_results,
		"solver_stats": stats,
		"state_hash": Prev.world_hash(world),
	}

# =============================================================================
# GENERAL EVENT LOCALIZATION WHILE OLD ISLANDS REMAIN CONSTRAINED
# =============================================================================

# Advance a macrostep while the contact graph already contains persistent
# constraints. Candidate trajectories during bisection repeatedly solve ONLY the
# contact identities active at macrostep start. The first graph topology change
# is localized, then the full provider graph is compiled at the same physical
# event time, warm-start state is remapped by stable contact identity, and the
# remaining macrostep continues through the new sparse islands.
static func advance_event_localized(world: Dictionary, planes: Array, dt: float, options: Dictionary = {}) -> Dictionary:
	if dt <= 0.0:
		return {"ok": false, "code": "DT_NONPOSITIVE"}
	var start_compile := Prev.compile_sphere_contacts(world, planes, float(options.get("contact_tolerance", 1.0e-7)))
	if not bool(start_compile.get("ok", false)):
		return start_compile
	var start_contacts: Array = start_compile["contacts"]
	if start_contacts.is_empty():
		return {"ok": false, "code": "EVENT011_REQUIRES_EXISTING_CONTACT_ISLAND"}
	var start_ids := _contact_id_set(start_contacts)
	var start_time := float(world["time"])
	var start_hash := Prev.world_hash(world)
	var start_islands := Prev.compile_islands(world, start_contacts)
	var start_warm := _warm_snapshot(world, start_ids)

	var endpoint := _simulate_old_graph(world, planes, dt, start_ids, options)
	if not bool(endpoint.get("ok", false)):
		return endpoint
	var end_compile := Prev.compile_sphere_contacts(endpoint["world"], planes, float(options.get("contact_tolerance", 1.0e-7)))
	if not bool(end_compile.get("ok", false)):
		return end_compile
	if _same_id_set(start_ids, _contact_id_set(end_compile["contacts"])):
		# No topology event: commit a normal sparse constrained advance.
		return _advance_full_sparse(world, planes, dt, options, {"event_found": false, "start_hash": start_hash})

	var low := 0.0
	var high := dt
	var probes := 0
	for _iteration in range(EVENT_LOCALIZATION_ITERATIONS):
		if high - low <= EVENT_TIME_TOLERANCE:
			break
		var mid := 0.5 * (low + high)
		var probe := _simulate_old_graph(world, planes, mid, start_ids, options)
		if not bool(probe.get("ok", false)):
			return probe
		probes += 1
		var compiled := Prev.compile_sphere_contacts(probe["world"], planes, float(options.get("contact_tolerance", 1.0e-7)))
		if not bool(compiled.get("ok", false)):
			return compiled
		if _same_id_set(start_ids, _contact_id_set(compiled["contacts"])):
			low = mid
		else:
			high = mid
	var event_dt := high

	# Advance the real world while preserving only the old graph until te.
	var pre_result := _advance_filtered_sparse(world, planes, event_dt, start_ids, options)
	if not bool(pre_result.get("ok", false)):
		return pre_result
	var event_time := float(world["time"])
	var event_compile := Prev.compile_sphere_contacts(world, planes, maxf(float(options.get("contact_tolerance", 1.0e-7)), 1.0e-7))
	if not bool(event_compile.get("ok", false)):
		return event_compile
	var event_ids := _contact_id_set(event_compile["contacts"])
	if _same_id_set(start_ids, event_ids):
		return {"ok": false, "code": "EVENT011_LOCALIZATION_DID_NOT_CHANGE_GRAPH"}

	var appeared := _set_difference(event_ids, start_ids)
	var disappeared := _set_difference(start_ids, event_ids)
	var old_gap_audit := _gap_audit(event_compile["contacts"], start_ids)
	var appeared_set := {}
	for contact_id in appeared:
		appeared_set[String(contact_id)] = true
	var appeared_gap_audit := _gap_audit(event_compile["contacts"], appeared_set)
	var resolve := resolve_current_contacts_sparse(
		world,
		event_compile["contacts"],
		float(options.get("impact_reference_dt", minf(DEFAULT_MAX_SUBSTEP, maxf(dt - event_dt, 1.0e-4)))),
		options
	)
	if not bool(resolve.get("ok", false)):
		return resolve
	var event_islands: Array = resolve["islands"]
	var warm_preserved := []
	for contact_id in start_ids.keys():
		if world["contact_cache"].has(contact_id) and start_warm.has(contact_id):
			warm_preserved.append(String(contact_id))
	warm_preserved.sort()

	var remaining := dt - event_dt
	var continuation := {"ok": true, "substeps": 0, "aggregate": _empty_stats()}
	if remaining > EPS:
		continuation = _advance_full_sparse(world, planes, remaining, options, {"skip_first_graph_update": true})
		if not bool(continuation.get("ok", false)):
			return continuation

	return {
		"ok": true,
		"event_found": true,
		"macrostep_start_time": start_time,
		"macrostep_dt": dt,
		"event_dt": event_dt,
		"event_time": event_time,
		"localization_probes": probes,
		"start_contact_ids": _sorted_set_keys(start_ids),
		"appeared": appeared,
		"disappeared": disappeared,
		"old_contact_gap_audit": old_gap_audit,
		"appeared_contact_gap_audit": appeared_gap_audit,
		"start_islands": _island_signature(start_islands),
		"event_islands": _island_signature(event_islands),
		"event_resolve": resolve,
		"warm_contacts_preserved": warm_preserved,
		"remaining_dt": remaining,
		"continuation": continuation,
		"start_hash": start_hash,
		"final_hash": Prev.world_hash(world),
	}

# =============================================================================
# INTERNAL EVENT ADVANCE HELPERS
# =============================================================================

static func _simulate_old_graph(source_world: Dictionary, planes: Array, dt: float, allowed_ids: Dictionary, options: Dictionary) -> Dictionary:
	var trial: Dictionary = source_world.duplicate(true)
	var result := _advance_filtered_sparse(trial, planes, dt, allowed_ids, options)
	if not bool(result.get("ok", false)):
		return result
	return {"ok": true, "world": trial, "advance": result}

static func _advance_filtered_sparse(world: Dictionary, planes: Array, dt: float, allowed_ids: Dictionary, options: Dictionary) -> Dictionary:
	var remaining := dt
	var substeps := 0
	var aggregate := _empty_stats()
	var max_substep := float(options.get("max_substep", DEFAULT_MAX_SUBSTEP))
	if max_substep <= 0.0:
		return {"ok": false, "code": "MAX_SUBSTEP_NONPOSITIVE"}
	while remaining > EPS:
		var h := minf(max_substep, remaining)
		var compiled := Prev.compile_sphere_contacts(world, planes, float(options.get("contact_tolerance", 1.0e-7)))
		if not bool(compiled.get("ok", false)):
			return compiled
		var filtered: Array = []
		for contact in compiled["contacts"]:
			if allowed_ids.has(String(contact["id"])):
				filtered.append(contact)
		if filtered.size() != allowed_ids.size():
			return {"ok": false, "code": "EVENT011_OLD_CONTACT_DISAPPEARED_DURING_PROBE", "time": float(world["time"])}
		var step_result := step_sparse(world, filtered, h, options)
		if not bool(step_result.get("ok", false)):
			return step_result
		_accumulate_stats(aggregate, step_result["solver_stats"])
		substeps += 1
		remaining -= h
	aggregate["linear_backend"] = "SPARSE_PCG"
	aggregate["dense_materializations"] = 0
	return {"ok": true, "substeps": substeps, "aggregate": aggregate}

static func _advance_full_sparse(world: Dictionary, planes: Array, dt: float, options: Dictionary, extras: Dictionary) -> Dictionary:
	var remaining := dt
	var substeps := 0
	var aggregate := _empty_stats()
	var max_substep := float(options.get("max_substep", DEFAULT_MAX_SUBSTEP))
	var first_substep := true
	while remaining > EPS:
		var h := minf(max_substep, remaining)
		var compiled := Prev.compile_sphere_contacts(world, planes, float(options.get("contact_tolerance", 1.0e-7)))
		if not bool(compiled.get("ok", false)):
			return compiled
		var step_options: Dictionary = options.duplicate(true)
		if first_substep and bool(extras.get("skip_first_graph_update", false)):
			step_options["_skip_graph_update"] = true
		var step_result := step_sparse(world, compiled["contacts"], h, step_options)
		if not bool(step_result.get("ok", false)):
			return step_result
		_accumulate_stats(aggregate, step_result["solver_stats"])
		substeps += 1
		first_substep = false
		remaining -= h
	aggregate["linear_backend"] = "SPARSE_PCG"
	aggregate["dense_materializations"] = 0
	var result := {"ok": true, "substeps": substeps, "aggregate": aggregate, "state_hash": Prev.world_hash(world)}
	for key in extras.keys():
		result[key] = extras[key]
	return result

# =============================================================================
# SPARSE ISLAND SOLVER
# =============================================================================

static func _solve_island_sparse(world: Dictionary, island: Dictionary, free: Dictionary, dt: float, options: Dictionary) -> Dictionary:
	var body_ids: Array = island["body_ids"]
	var contacts: Array = island["contacts"]
	var body_index := {}
	for i in range(body_ids.size()):
		body_index[body_ids[i]] = i
	var dof := 6 * body_ids.size()
	var rows: Array = []
	var bvec: Array = []
	var friction: Array = []
	var warm := _zero_vector(3 * contacts.size())
	var warm_contacts := 0

	for contact_index in range(contacts.size()):
		var contact: Dictionary = contacts[contact_index]
		var directions := [contact["normal"], contact["tangent_1"], contact["tangent_2"]]
		for local_row in range(3):
			var sparse_row := {}
			_append_body_jacobian(sparse_row, body_index, String(contact["body_a"]), directions[local_row], contact["r_a"], 1.0)
			_append_body_jacobian(sparse_row, body_index, String(contact["body_b"]), directions[local_row], contact["r_b"], -1.0)
			rows.append(sparse_row)
		var vn := _relative_component(free, contact, contact["normal"])
		var vt1 := _relative_component(free, contact, contact["tangent_1"])
		var vt2 := _relative_component(free, contact, contact["tangent_2"])
		var penetration_bias := BAUMGARTE * minf(float(contact["gap"]), 0.0) / dt
		var restitution_term := float(contact["restitution"]) * vn if vn < -IMPACT_SPEED_THRESHOLD else 0.0
		bvec.append(vn + restitution_term + penetration_bias)
		bvec.append(vt1)
		bvec.append(vt2)
		friction.append(float(contact["friction"]))
		var cache: Dictionary = world["contact_cache"].get(String(contact["id"]), {})
		var previous: Vector3 = cache.get("warm_impulse", Vector3.ZERO)
		if previous.length() > EPS:
			warm_contacts += 1
		warm[3 * contact_index] = previous.x
		warm[3 * contact_index + 1] = previous.y
		warm[3 * contact_index + 2] = previous.z

	var minv := _inverse_mass(world, body_ids)
	var sparse_a := _assemble_sparse_effective_mass(rows, minv)
	var solved := _admm_sparse_pcg(sparse_a, bvec, friction, warm, options)
	if not bool(solved.get("ok", false)):
		solved["island_id"] = String(island["id"])
		return solved

	var lambda: Array = solved["lambda"]
	var generalized_impulse := _sparse_mat_t_vec(rows, lambda, dof)
	var post := {}
	for body_i in range(body_ids.size()):
		var id := String(body_ids[body_i])
		var base := 6 * body_i
		var current: Dictionary = free[id]
		var body: Dictionary = world["bodies"][id]
		post[id] = {
			"linear": current["linear"] + Vector3(generalized_impulse[base], generalized_impulse[base + 1], generalized_impulse[base + 2]) * float(body["inv_mass"]),
			"angular": current["angular"] + Vector3(generalized_impulse[base + 3], generalized_impulse[base + 4], generalized_impulse[base + 5]) * body["inv_inertia"],
		}
	var impulse_by_id := {}
	var active_contacts := 0
	for contact_index in range(contacts.size()):
		var impulse := Vector3(lambda[3 * contact_index], lambda[3 * contact_index + 1], lambda[3 * contact_index + 2])
		impulse_by_id[String(contacts[contact_index]["id"])] = impulse
		if impulse.x > 1.0e-8:
			active_contacts += 1

	return {
		"ok": true,
		"island_id": String(island["id"]),
		"body_ids": body_ids.duplicate(true),
		"contact_ids": _sorted_contact_ids(contacts),
		"post_velocities": post,
		"impulse_by_id": impulse_by_id,
		"active_contacts": active_contacts,
		"iterations": int(solved["iterations"]),
		"warm_start_contacts": warm_contacts,
		"primal_residual": float(solved["primal_residual"]),
		"dual_residual": float(solved["dual_residual"]),
		"sparse_jacobian_entries": _sparse_row_entry_count(rows),
		"sparse_effective_mass_entries": _sparse_matrix_entry_count(sparse_a),
		"dense_effective_mass_capacity": bvec.size() * bvec.size(),
		"pcg_calls": int(solved["pcg_calls"]),
		"pcg_iterations": int(solved["pcg_iterations"]),
		"pcg_max_iterations_one_call": int(solved["pcg_max_iterations_one_call"]),
		"linear_backend": "SPARSE_PCG",
		"dense_materializations": 0,
	}

static func _admm_sparse_pcg(a: Array, b: Array, friction: Array, warm: Array, options: Dictionary) -> Dictionary:
	var rho := float(options.get("rho", DEFAULT_RHO))
	var tolerance := float(options.get("tolerance", DEFAULT_ADMM_TOLERANCE))
	var max_iterations := int(options.get("max_iterations", DEFAULT_ADMM_MAX_ITERATIONS))
	var pcg_tolerance := float(options.get("pcg_tolerance", DEFAULT_PCG_TOLERANCE))
	var pcg_max_iterations := int(options.get("pcg_max_iterations", DEFAULT_PCG_MAX_ITERATIONS))
	if rho <= 0.0 or tolerance <= 0.0 or max_iterations < 1 or pcg_tolerance <= 0.0 or pcg_max_iterations < 1:
		return {"ok": false, "code": "BAD_SPARSE_SOLVER_OPTIONS"}
	var n := b.size()
	var h := _sparse_add_diagonal(a, rho)
	var diagonal := _sparse_diagonal(h, n)
	for value in diagonal:
		if float(value) <= EPS:
			return {"ok": false, "code": "SPARSE_PCG_NONPOSITIVE_DIAGONAL"}

	var lambda: Array = warm.duplicate(true)
	var z: Array = warm.duplicate(true)
	var u := _zero_vector(n)
	for contact_index in range(friction.size()):
		var projected := _project_cone(Vector3(z[3 * contact_index], z[3 * contact_index + 1], z[3 * contact_index + 2]), float(friction[contact_index]))
		z[3 * contact_index] = projected.x
		z[3 * contact_index + 1] = projected.y
		z[3 * contact_index + 2] = projected.z
		lambda[3 * contact_index] = projected.x
		lambda[3 * contact_index + 1] = projected.y
		lambda[3 * contact_index + 2] = projected.z

	var primal := INF
	var dual := INF
	var iterations := 0
	var pcg_calls := 0
	var pcg_iterations := 0
	var pcg_max_one := 0
	for iteration in range(max_iterations):
		iterations = iteration + 1
		var rhs := _zero_vector(n)
		for i in range(n):
			rhs[i] = rho * (float(z[i]) - float(u[i])) - float(b[i])
		var linear := _pcg(h, rhs, lambda, diagonal, pcg_tolerance, pcg_max_iterations)
		if not bool(linear.get("ok", false)):
			linear["code"] = "SPARSE_PCG_LINEAR_SOLVE_FAILED"
			return linear
		lambda = linear["x"]
		pcg_calls += 1
		pcg_iterations += int(linear["iterations"])
		pcg_max_one = maxi(pcg_max_one, int(linear["iterations"]))
		var old_z: Array = z.duplicate(true)
		for contact_index in range(friction.size()):
			var q := Vector3(lambda[3 * contact_index] + u[3 * contact_index], lambda[3 * contact_index + 1] + u[3 * contact_index + 1], lambda[3 * contact_index + 2] + u[3 * contact_index + 2])
			var projected := _project_cone(q, float(friction[contact_index]))
			z[3 * contact_index] = projected.x
			z[3 * contact_index + 1] = projected.y
			z[3 * contact_index + 2] = projected.z
		for i in range(n):
			u[i] = float(u[i]) + float(lambda[i]) - float(z[i])
		primal = 0.0
		dual = 0.0
		for i in range(n):
			primal = maxf(primal, absf(float(lambda[i]) - float(z[i])))
			dual = maxf(dual, rho * absf(float(z[i]) - float(old_z[i])))
		if maxf(primal, dual) <= tolerance:
			break
	if maxf(primal, dual) > tolerance:
		return {"ok": false, "code": "SPARSE_ADMM_NO_CONVERGENCE", "iterations": iterations, "primal_residual": primal, "dual_residual": dual}
	return {
		"ok": true,
		"lambda": z,
		"iterations": iterations,
		"primal_residual": primal,
		"dual_residual": dual,
		"pcg_calls": pcg_calls,
		"pcg_iterations": pcg_iterations,
		"pcg_max_iterations_one_call": pcg_max_one,
	}

# Jacobi-preconditioned Conjugate Gradient over sparse symmetric row dictionaries.
static func _pcg(matrix: Array, rhs: Array, initial: Array, diagonal: Array, tolerance: float, max_iterations: int) -> Dictionary:
	var n := rhs.size()
	var x: Array = initial.duplicate(true)
	if x.size() != n:
		x = _zero_vector(n)
	var ax := _sparse_mat_vec(matrix, x)
	var r := _zero_vector(n)
	var rhs_norm_sq := 0.0
	for i in range(n):
		r[i] = float(rhs[i]) - float(ax[i])
		rhs_norm_sq += float(rhs[i]) * float(rhs[i])
	var z := _zero_vector(n)
	for i in range(n):
		z[i] = float(r[i]) / float(diagonal[i])
	var p: Array = z.duplicate(true)
	var rz_old := _dot(r, z)
	var target := tolerance * maxf(1.0, sqrt(rhs_norm_sq))
	if sqrt(_dot(r, r)) <= target:
		return {"ok": true, "x": x, "iterations": 0, "residual": sqrt(_dot(r, r))}
	for iteration in range(max_iterations):
		var ap := _sparse_mat_vec(matrix, p)
		var denom := _dot(p, ap)
		if denom <= 0.0:
			return {"ok": false, "reason": "PCG_NONPOSITIVE_CURVATURE", "iterations": iteration}
		var alpha := rz_old / denom
		for i in range(n):
			x[i] = float(x[i]) + alpha * float(p[i])
			r[i] = float(r[i]) - alpha * float(ap[i])
		var residual_norm := sqrt(_dot(r, r))
		if residual_norm <= target:
			return {"ok": true, "x": x, "iterations": iteration + 1, "residual": residual_norm}
		for i in range(n):
			z[i] = float(r[i]) / float(diagonal[i])
		var rz_new := _dot(r, z)
		if absf(rz_old) <= 1.0e-30:
			return {"ok": false, "reason": "PCG_BREAKDOWN", "iterations": iteration + 1}
		var beta := rz_new / rz_old
		for i in range(n):
			p[i] = float(z[i]) + beta * float(p[i])
		rz_old = rz_new
	return {"ok": false, "reason": "PCG_NO_CONVERGENCE", "iterations": max_iterations}

# =============================================================================
# SPARSE ALGEBRA / CONTACT HELPERS
# =============================================================================

static func _append_body_jacobian(row: Dictionary, body_index: Dictionary, body_id: String, direction: Vector3, r: Vector3, sign: float) -> void:
	if body_id.begins_with("@static/") or not body_index.has(body_id):
		return
	var base := 6 * int(body_index[body_id])
	var angular := r.cross(direction)
	var values := [direction.x, direction.y, direction.z, angular.x, angular.y, angular.z]
	for i in range(6):
		var value := sign * float(values[i])
		if absf(value) > EPS:
			row[base + i] = value

static func _inverse_mass(world: Dictionary, body_ids: Array) -> Array:
	var result: Array = []
	for id in body_ids:
		var body: Dictionary = world["bodies"][id]
		result.append(float(body["inv_mass"])); result.append(float(body["inv_mass"])); result.append(float(body["inv_mass"]))
		var inv_i: Vector3 = body["inv_inertia"]
		result.append(inv_i.x); result.append(inv_i.y); result.append(inv_i.z)
	return result

static func _assemble_sparse_effective_mass(rows: Array, minv: Array) -> Array:
	var result: Array = []
	for _i in range(rows.size()):
		result.append({})
	for i in range(rows.size()):
		for j in range(i, rows.size()):
			var value := 0.0
			for key in rows[i].keys():
				if rows[j].has(key):
					value += float(rows[i][key]) * float(minv[int(key)]) * float(rows[j][key])
			if absf(value) > EPS:
				result[i][j] = value
				if i != j:
					result[j][i] = value
	return result

static func _sparse_add_diagonal(matrix: Array, value: float) -> Array:
	var result: Array = []
	for row_index in range(matrix.size()):
		var row: Dictionary = matrix[row_index].duplicate(true)
		row[row_index] = float(row.get(row_index, 0.0)) + value
		result.append(row)
	return result

static func _sparse_diagonal(matrix: Array, size: int) -> Array:
	var result := _zero_vector(size)
	for i in range(size):
		result[i] = float(matrix[i].get(i, 0.0))
	return result

static func _sparse_mat_vec(matrix: Array, vector: Array) -> Array:
	var result := _zero_vector(matrix.size())
	for row_index in range(matrix.size()):
		var sum := 0.0
		for column in matrix[row_index].keys():
			sum += float(matrix[row_index][column]) * float(vector[int(column)])
		result[row_index] = sum
	return result

static func _sparse_mat_t_vec(rows: Array, vector: Array, cols: int) -> Array:
	var result := _zero_vector(cols)
	for row_index in range(rows.size()):
		for column in rows[row_index].keys():
			result[int(column)] += float(rows[row_index][column]) * float(vector[row_index])
	return result

static func _relative_component(free: Dictionary, contact: Dictionary, direction: Vector3) -> float:
	var va := _point_velocity(free, String(contact["body_a"]), contact["r_a"])
	var vb := _point_velocity(free, String(contact["body_b"]), contact["r_b"])
	return direction.dot(va - vb)

static func _point_velocity(free: Dictionary, body_id: String, r: Vector3) -> Vector3:
	if body_id.begins_with("@static/"):
		return Vector3.ZERO
	var velocity: Dictionary = free[body_id]
	return velocity["linear"] + velocity["angular"].cross(r)

static func _project_cone(value: Vector3, friction: float) -> Vector3:
	var normal := value.x
	var tangent := Vector2(value.y, value.z)
	var tangent_norm := tangent.length()
	if friction <= EPS:
		return Vector3(maxf(normal, 0.0), 0.0, 0.0)
	if normal >= 0.0 and tangent_norm <= friction * normal:
		return value
	var projected_normal := (normal + friction * tangent_norm) / (1.0 + friction * friction)
	if projected_normal <= 0.0:
		return Vector3.ZERO
	if tangent_norm <= EPS:
		return Vector3(projected_normal, 0.0, 0.0)
	var scale := friction * projected_normal / tangent_norm
	return Vector3(projected_normal, tangent.x * scale, tangent.y * scale)

static func _zero_vector(size: int) -> Array:
	var result: Array = []
	result.resize(size)
	result.fill(0.0)
	return result

static func _dot(a: Array, b: Array) -> float:
	var result := 0.0
	for i in range(a.size()):
		result += float(a[i]) * float(b[i])
	return result

static func _sparse_row_entry_count(rows: Array) -> int:
	var count := 0
	for row in rows:
		count += row.size()
	return count

static func _sparse_matrix_entry_count(matrix: Array) -> int:
	var count := 0
	for row in matrix:
		count += row.size()
	return count

static func _sorted_contact_ids(contacts: Array) -> Array:
	var ids: Array = []
	for contact in contacts:
		ids.append(String(contact["id"]))
	ids.sort()
	return ids

# =============================================================================
# EVIDENCE HELPERS
# =============================================================================

static func _contact_id_set(contacts: Array) -> Dictionary:
	var result := {}
	for contact in contacts:
		result[String(contact["id"])] = true
	return result

static func _same_id_set(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a.keys():
		if not b.has(key):
			return false
	return true

static func _set_difference(a: Dictionary, b: Dictionary) -> Array:
	var result: Array = []
	for key in a.keys():
		if not b.has(key):
			result.append(String(key))
	result.sort()
	return result

static func _sorted_set_keys(values: Dictionary) -> Array:
	var result: Array = []
	for key in values.keys():
		result.append(String(key))
	result.sort()
	return result

static func _warm_snapshot(world: Dictionary, ids: Dictionary) -> Dictionary:
	var result := {}
	for id in ids.keys():
		if world["contact_cache"].has(id):
			result[id] = world["contact_cache"][id].get("warm_impulse", Vector3.ZERO)
	return result

static func _gap_audit(contacts: Array, ids: Dictionary) -> Dictionary:
	var result := {}
	for contact in contacts:
		var id := String(contact["id"])
		if ids.has(id):
			result[id] = float(contact["gap"])
	return result

static func _island_signature(islands: Array) -> Array:
	var result: Array = []
	for island in islands:
		result.append({
			"id": String(island.get("island_id", island.get("id", ""))),
			"body_ids": island["body_ids"].duplicate(true),
			"contact_ids": island.get("contact_ids", _sorted_contact_ids(island.get("contacts", []))),
			"warm_start_contacts": int(island.get("warm_start_contacts", 0)),
			"linear_backend": String(island.get("linear_backend", "")),
			"dense_materializations": int(island.get("dense_materializations", 0)),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	return result

static func _empty_stats() -> Dictionary:
	return {
		"island_count": 0,
		"iterations": 0,
		"warm_start_contacts": 0,
		"sparse_jacobian_entries": 0,
		"sparse_effective_mass_entries": 0,
		"dense_effective_mass_capacity": 0,
		"pcg_calls": 0,
		"pcg_iterations": 0,
		"pcg_max_iterations_one_call": 0,
		"dense_materializations": 0,
		"max_island_count": 0,
		"island_solve_count": 0,
	}

static func _accumulate_stats(target: Dictionary, source: Dictionary) -> void:
	for key in ["iterations", "warm_start_contacts", "sparse_jacobian_entries", "sparse_effective_mass_entries", "dense_effective_mass_capacity", "pcg_calls", "pcg_iterations"]:
		target[key] = int(target.get(key, 0)) + int(source.get(key, 0))
	target["max_island_count"] = maxi(int(target.get("max_island_count", 0)), int(source.get("island_count", 0)))
	target["island_solve_count"] = int(target.get("island_solve_count", 0)) + int(source.get("island_count", 0))
	target["pcg_max_iterations_one_call"] = maxi(int(target.get("pcg_max_iterations_one_call", 0)), int(source.get("pcg_max_iterations_one_call", 0)))
	target["dense_materializations"] = int(target.get("dense_materializations", 0)) + int(source.get("dense_materializations", 0))
