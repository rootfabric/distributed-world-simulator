class_name Fabric0PersistentContactGraphV1
extends RefCounted

const EPS := 1.0e-12
const CONTACT_TOLERANCE := 1.0e-7
const DEFAULT_RHO := 0.2
const DEFAULT_TOLERANCE := 1.0e-10
const DEFAULT_MAX_ITERATIONS := 5000
const BAUMGARTE := 0.2
const IMPACT_SPEED_THRESHOLD := 0.5
const WARM_DECAY := 1.0

# =============================================================================
# WORLD / BODY / PROVIDER MODEL
# =============================================================================

static func new_world(gravity: Vector3 = Vector3(0.0, -9.81, 0.0)) -> Dictionary:
	return {
		"time": 0.0,
		"step": 0,
		"gravity": gravity,
		"bodies": {},
		"contact_cache": {},
		"contact_history": [],
		"last_islands": [],
		"diagnostics": [],
		"solver_stats": {},
	}

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
	var inertia_scalar := 0.4 * mass * radius * radius if dynamic else 1.0
	return {
		"id": body_id,
		"dynamic": dynamic,
		"mass": mass if dynamic else INF,
		"inv_mass": 1.0 / mass if dynamic and mass > 0.0 else 0.0,
		"radius": radius,
		"position": position,
		"linear_velocity": linear_velocity,
		"angular_velocity": angular_velocity,
		"inertia": Vector3(inertia_scalar, inertia_scalar, inertia_scalar),
		"inv_inertia": Vector3(1.0 / inertia_scalar, 1.0 / inertia_scalar, 1.0 / inertia_scalar) if dynamic and inertia_scalar > 0.0 else Vector3.ZERO,
		"friction": friction,
		"restitution": restitution,
	}

static func new_plane(plane_id: String, normal: Vector3, offset: float, friction: float = 0.5, restitution: float = 0.0) -> Dictionary:
	return {"id": plane_id, "normal": normal, "offset": offset, "friction": friction, "restitution": restitution}

static func add_body(world: Dictionary, body: Dictionary) -> bool:
	var id := String(body.get("id", ""))
	if id.is_empty() or world["bodies"].has(id):
		return false
	if bool(body.get("dynamic", true)):
		if float(body.get("mass", 0.0)) <= 0.0 or float(body.get("radius", 0.0)) <= 0.0:
			return false
	world["bodies"][id] = body.duplicate(true)
	return true

# Generic provider output contract is an Array[Dictionary] with stable IDs and
# body_a/body_b. body_b may be "@static/<feature>" and then contributes no DOF.
# This built-in sphere provider is only a research provider exercising the boundary.
static func compile_sphere_contacts(world: Dictionary, planes: Array, tolerance: float = CONTACT_TOLERANCE) -> Dictionary:
	if tolerance <= 0.0:
		return {"ok": false, "code": "CONTACT_TOLERANCE_NONPOSITIVE"}
	var contacts: Array = []
	var body_ids: Array = world["bodies"].keys()
	body_ids.sort()
	var plane_ids := {}
	for raw_plane in planes:
		var plane: Dictionary = raw_plane
		var pid := String(plane.get("id", ""))
		if pid.is_empty() or plane_ids.has(pid):
			return {"ok": false, "code": "PLANE_ID_INVALID_OR_DUPLICATE"}
		plane_ids[pid] = true
		var normal: Vector3 = plane.get("normal", Vector3.ZERO)
		if normal.length() <= EPS:
			return {"ok": false, "code": "PLANE_NORMAL_ZERO", "plane_id": pid}
		normal = normal.normalized()
		for bid in body_ids:
			var body: Dictionary = world["bodies"][bid]
			if not bool(body["dynamic"]):
				continue
			var radius := float(body["radius"])
			var gap := normal.dot(body["position"]) - float(plane["offset"]) - radius
			if gap <= tolerance:
				var point: Vector3 = body["position"] - normal * radius
				var tangents := _tangent_basis(normal)
				contacts.append({
					"id": "plane:%s|body:%s" % [pid, String(bid)],
					"body_a": String(bid),
					"body_b": "@static/%s" % pid,
					"point": point,
					"r_a": point - body["position"],
					"r_b": Vector3.ZERO,
					"normal": normal,
					"tangent_1": tangents[0],
					"tangent_2": tangents[1],
					"gap": gap,
					"friction": sqrt(float(body["friction"]) * float(plane["friction"])),
					"restitution": maxf(float(body["restitution"]), float(plane["restitution"])),
				})

	for i in range(body_ids.size()):
		var id_a := String(body_ids[i])
		var a: Dictionary = world["bodies"][id_a]
		if not bool(a["dynamic"]): continue
		for j in range(i + 1, body_ids.size()):
			var id_b := String(body_ids[j])
			var b: Dictionary = world["bodies"][id_b]
			if not bool(b["dynamic"]): continue
			var delta: Vector3 = a["position"] - b["position"]
			var distance := delta.length()
			var combined := float(a["radius"]) + float(b["radius"])
			var gap := distance - combined
			if gap <= tolerance:
				var normal := delta / distance if distance > EPS else Vector3.UP
				# normal points body_b -> body_a; positive relative normal velocity separates.
				var point: Vector3 = b["position"] + normal * float(b["radius"])
				var tangents := _tangent_basis(normal)
				contacts.append({
					"id": "pair:%s|%s" % [id_a, id_b],
					"body_a": id_a,
					"body_b": id_b,
					"point": point,
					"r_a": point - a["position"],
					"r_b": point - b["position"],
					"normal": normal,
					"tangent_1": tangents[0],
					"tangent_2": tangents[1],
					"gap": gap,
					"friction": sqrt(float(a["friction"]) * float(b["friction"])),
					"restitution": maxf(float(a["restitution"]), float(b["restitution"])),
				})
	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	return {"ok": true, "contacts": contacts}

# =============================================================================
# PERSISTENT CONTACT GRAPH / LIFECYCLE
# =============================================================================

static func update_contact_graph(world: Dictionary, provider_contacts: Array) -> Dictionary:
	var contacts: Array = []
	var seen := {}
	for source in provider_contacts:
		var c: Dictionary = source.duplicate(true)
		var id := String(c.get("id", ""))
		if id.is_empty() or seen.has(id):
			return {"ok": false, "code": "CONTACT_ID_INVALID_OR_DUPLICATE", "contact_id": id}
		seen[id] = true
		if not world["bodies"].has(String(c["body_a"])):
			return {"ok": false, "code": "CONTACT_BODY_A_UNKNOWN", "contact_id": id}
		var body_b := String(c["body_b"])
		if not body_b.begins_with("@static/") and not world["bodies"].has(body_b):
			return {"ok": false, "code": "CONTACT_BODY_B_UNKNOWN", "contact_id": id}
		contacts.append(c)
	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))

	var previous: Dictionary = world["contact_cache"]
	var next_cache := {}
	var appeared: Array = []
	var persisted: Array = []
	var disappeared: Array = []
	for c in contacts:
		var id := String(c["id"])
		var old: Dictionary = previous.get(id, {})
		if old.is_empty():
			appeared.append(id)
			next_cache[id] = {
				"age_steps": 1,
				"first_step": int(world["step"]),
				"last_step": int(world["step"]),
				"warm_impulse": Vector3.ZERO,
			}
		else:
			persisted.append(id)
			next_cache[id] = {
				"age_steps": int(old["age_steps"]) + 1,
				"first_step": int(old["first_step"]),
				"last_step": int(world["step"]),
				"warm_impulse": old.get("warm_impulse", Vector3.ZERO),
			}
	for id in previous.keys():
		if not next_cache.has(id):
			disappeared.append(String(id))
	appeared.sort(); persisted.sort(); disappeared.sort()
	world["contact_cache"] = next_cache
	var event := {
		"step": int(world["step"]),
		"time": float(world["time"]),
		"appeared": appeared,
		"persisted": persisted,
		"disappeared": disappeared,
	}
	world["contact_history"].append(event)
	return {"ok": true, "contacts": contacts, "lifecycle": event}

# =============================================================================
# CONTACT GRAPH -> INDEPENDENT ISLANDS
# =============================================================================

static func compile_islands(world: Dictionary, contacts: Array) -> Array:
	var dynamic_ids: Array = []
	for id in world["bodies"].keys():
		if bool(world["bodies"][id]["dynamic"]): dynamic_ids.append(String(id))
	dynamic_ids.sort()
	var adjacency := {}
	for id in dynamic_ids: adjacency[id] = []
	for c in contacts:
		var a := String(c["body_a"])
		var b := String(c["body_b"])
		if not b.begins_with("@static/"):
			adjacency[a].append(b)
			adjacency[b].append(a)
	for id in adjacency.keys():
		adjacency[id].sort()

	var visited := {}
	var islands: Array = []
	for seed in dynamic_ids:
		if visited.has(seed): continue
		# Ignore completely unconstrained bodies; they are free-flow, not contact islands.
		var has_contact := false
		for c in contacts:
			if String(c["body_a"]) == seed or String(c["body_b"]) == seed:
				has_contact = true; break
		if not has_contact: continue
		var queue: Array = [seed]
		visited[seed] = true
		var bodies: Array = []
		while not queue.is_empty():
			var current := String(queue.pop_front())
			bodies.append(current)
			for neighbor in adjacency[current]:
				if not visited.has(neighbor):
					visited[neighbor] = true
					queue.append(neighbor)
		bodies.sort()
		var body_set := {}
		for id in bodies: body_set[id] = true
		var island_contacts: Array = []
		for c in contacts:
			if body_set.has(String(c["body_a"])) or body_set.has(String(c["body_b"])):
				island_contacts.append(c)
		island_contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
		islands.append({
			"id": "island:%s" % String(bodies[0]),
			"body_ids": bodies,
			"contacts": island_contacts,
		})
	islands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	return islands

# =============================================================================
# SPARSE ISLAND ASSEMBLY + WARM-STARTED CONE SOLVE
# =============================================================================

static func step(world: Dictionary, provider_contacts: Array, dt: float, options: Dictionary = {}) -> Dictionary:
	if dt <= 0.0:
		return {"ok": false, "code": "DT_NONPOSITIVE"}
	var graph := update_contact_graph(world, provider_contacts)
	if not bool(graph.get("ok", false)): return graph
	var contacts: Array = graph["contacts"]
	var islands := compile_islands(world, contacts)
	world["last_islands"] = islands.duplicate(true)

	# Free velocity from external acceleration. This is the differential part of
	# the velocity-level hybrid DAE step; contacts then solve algebraic impulses.
	var free := {}
	for id in world["bodies"].keys():
		var body: Dictionary = world["bodies"][id]
		if bool(body["dynamic"]):
			free[id] = {
				"linear": body["linear_velocity"] + world["gravity"] * dt,
				"angular": body["angular_velocity"],
			}

	var island_results: Array = []
	var total_iterations := 0
	var warm_hits := 0
	var sparse_entries := 0
	for island in islands:
		var solved := _solve_island(world, island, free, dt, options)
		if not bool(solved.get("ok", false)):
			return solved
		island_results.append(solved)
		total_iterations += int(solved["iterations"])
		warm_hits += int(solved["warm_start_contacts"])
		sparse_entries += int(solved["sparse_effective_mass_entries"])
		for id in solved["post_velocities"].keys():
			free[id] = solved["post_velocities"][id]
		for cid in solved["impulse_by_id"].keys():
			if world["contact_cache"].has(cid):
				world["contact_cache"][cid]["warm_impulse"] = solved["impulse_by_id"][cid] * WARM_DECAY

	# Bodies without islands retain free velocities. Then integrate positions.
	for id in world["bodies"].keys():
		var body: Dictionary = world["bodies"][id]
		if not bool(body["dynamic"]): continue
		body["linear_velocity"] = free[id]["linear"]
		body["angular_velocity"] = free[id]["angular"]
		body["position"] = body["position"] + body["linear_velocity"] * dt

	world["time"] = float(world["time"]) + dt
	world["step"] = int(world["step"]) + 1
	world["solver_stats"] = {
		"island_count": islands.size(),
		"iterations": total_iterations,
		"warm_start_contacts": warm_hits,
		"sparse_effective_mass_entries": sparse_entries,
	}
	return {
		"ok": true,
		"lifecycle": graph["lifecycle"],
		"islands": island_results,
		"solver_stats": world["solver_stats"].duplicate(true),
		"state_hash": world_hash(world),
	}

static func _solve_island(world: Dictionary, island: Dictionary, free: Dictionary, dt: float, options: Dictionary) -> Dictionary:
	var body_ids: Array = island["body_ids"]
	var contacts: Array = island["contacts"]
	var body_index := {}
	for i in range(body_ids.size()): body_index[body_ids[i]] = i
	var dof := 6 * body_ids.size()
	var row_count := 3 * contacts.size()
	var rows: Array = []
	var bvec: Array = []
	var mu: Array = []
	var warm := _zero_vector(row_count)
	var warm_contacts := 0

	for ci in range(contacts.size()):
		var c: Dictionary = contacts[ci]
		var dirs := [c["normal"], c["tangent_1"], c["tangent_2"]]
		for local_row in range(3):
			var sparse_row := {}
			_append_body_jacobian(sparse_row, world, body_index, String(c["body_a"]), dirs[local_row], c["r_a"], 1.0)
			_append_body_jacobian(sparse_row, world, body_index, String(c["body_b"]), dirs[local_row], c["r_b"], -1.0)
			rows.append(sparse_row)
		var vn := _relative_contact_component(world, free, c, c["normal"])
		var vt1 := _relative_contact_component(world, free, c, c["tangent_1"])
		var vt2 := _relative_contact_component(world, free, c, c["tangent_2"])
		var penetration_bias := BAUMGARTE * minf(float(c["gap"]), 0.0) / dt
		var restitution_term := float(c["restitution"]) * vn if vn < -IMPACT_SPEED_THRESHOLD else 0.0
		bvec.append(vn + restitution_term + penetration_bias)
		bvec.append(vt1)
		bvec.append(vt2)
		mu.append(float(c["friction"]))
		var cache: Dictionary = world["contact_cache"].get(String(c["id"]), {})
		var previous: Vector3 = cache.get("warm_impulse", Vector3.ZERO)
		if previous.length() > EPS:
			warm_contacts += 1
		warm[3 * ci] = previous.x
		warm[3 * ci + 1] = previous.y
		warm[3 * ci + 2] = previous.z

	var minv := _island_inverse_mass(world, body_ids)
	var sparse_a := _assemble_sparse_effective_mass(rows, minv)
	var dense_a := _sparse_to_dense(sparse_a, row_count)
	var rho := float(options.get("rho", DEFAULT_RHO))
	var tolerance := float(options.get("tolerance", DEFAULT_TOLERANCE))
	var max_iterations := int(options.get("max_iterations", DEFAULT_MAX_ITERATIONS))
	var solved := _admm_cone(dense_a, bvec, mu, warm, rho, tolerance, max_iterations)
	if not bool(solved.get("ok", false)):
		solved["island_id"] = String(island["id"])
		return solved

	var lambda: Array = solved["lambda"]
	var generalized_impulse := _sparse_mat_t_vec(rows, lambda, dof)
	var post := {}
	for bi in range(body_ids.size()):
		var id := String(body_ids[bi])
		var base := 6 * bi
		var current: Dictionary = free[id]
		var body: Dictionary = world["bodies"][id]
		post[id] = {
			"linear": current["linear"] + Vector3(generalized_impulse[base], generalized_impulse[base+1], generalized_impulse[base+2]) * float(body["inv_mass"]),
			"angular": current["angular"] + Vector3(generalized_impulse[base+3], generalized_impulse[base+4], generalized_impulse[base+5]) * body["inv_inertia"],
		}
	var impulse_by_id := {}
	var active := 0
	var sliding := 0
	for ci in range(contacts.size()):
		var j := Vector3(lambda[3*ci], lambda[3*ci+1], lambda[3*ci+2])
		impulse_by_id[String(contacts[ci]["id"])] = j
		if j.x > 1.0e-8:
			active += 1
			if absf(Vector2(j.y,j.z).length() - float(contacts[ci]["friction"]) * j.x) <= 1.0e-6:
				sliding += 1

	return {
		"ok": true,
		"island_id": String(island["id"]),
		"body_ids": body_ids.duplicate(true),
		"contact_ids": _contact_ids(contacts),
		"post_velocities": post,
		"impulse_by_id": impulse_by_id,
		"active_contacts": active,
		"sliding_contacts": sliding,
		"iterations": int(solved["iterations"]),
		"warm_start_contacts": warm_contacts,
		"primal_residual": float(solved["primal_residual"]),
		"dual_residual": float(solved["dual_residual"]),
		"sparse_jacobian_entries": _sparse_row_entry_count(rows),
		"sparse_effective_mass_entries": sparse_a.size(),
		"dense_effective_mass_capacity": row_count * row_count,
	}


# =============================================================================
# EVENT-AWARE CONTACT APPEARANCE BRIDGE
# =============================================================================

# Research bridge back to FABRIC0.8 semantics. It localizes the first sphere-plane
# contact while the world is contact-free, advances ballistic differential state
# to that exact event time, then lets the persistent contact graph solve the
# remaining macrostep. Existing active contact islands are deliberately rejected: a
# general event-localized sparse hybrid DAE remains a later production-scale wall.
static func advance_contact_free_to_first_plane_event(world: Dictionary, planes: Array, dt: float, options: Dictionary = {}) -> Dictionary:
	if dt <= 0.0:
		return {"ok": false, "code": "DT_NONPOSITIVE"}
	var start_contacts := compile_sphere_contacts(world, planes, CONTACT_TOLERANCE)
	if not bool(start_contacts.get("ok", false)):
		return start_contacts
	if not start_contacts["contacts"].is_empty():
		return {"ok": false, "code": "EVENT_BRIDGE_REQUIRES_CONTACT_FREE_START"}
	var candidate := _find_first_plane_event(world, planes, dt)
	if not bool(candidate.get("found", false)):
		return {"ok": false, "code": "NO_CONTACT_EVENT_IN_INTERVAL"}
	var event_time := float(candidate["dt"])
	# Exact constant-acceleration ballistic flow to event instant.
	var ids: Array = world["bodies"].keys(); ids.sort()
	for id in ids:
		var body: Dictionary = world["bodies"][id]
		if not bool(body["dynamic"]): continue
		var v0: Vector3 = body["linear_velocity"]
		body["position"] = body["position"] + v0 * event_time + 0.5 * world["gravity"] * event_time * event_time
		body["linear_velocity"] = v0 + world["gravity"] * event_time
	world["time"] = float(world["time"]) + event_time

	var at_event := compile_sphere_contacts(world, planes, maxf(CONTACT_TOLERANCE, 1.0e-8))
	if not bool(at_event.get("ok", false)) or at_event["contacts"].is_empty():
		return {"ok": false, "code": "EVENT_LOCALIZATION_DID_NOT_COMPILE_CONTACT"}
	var remaining := dt - event_time
	var solve_result := step(world, at_event["contacts"], remaining, options)
	if not bool(solve_result.get("ok", false)):
		return solve_result
	return {
		"ok": true,
		"event_time": event_time,
		"event_body": String(candidate["body_id"]),
		"event_plane": String(candidate["plane_id"]),
		"event_contact_ids": _contact_ids(at_event["contacts"]),
		"remaining_dt": remaining,
		"contact_step": solve_result,
		"state_hash": world_hash(world),
	}

static func _find_first_plane_event(world: Dictionary, planes: Array, dt: float) -> Dictionary:
	var best_dt := INF
	var best := {}
	var ids: Array = world["bodies"].keys(); ids.sort()
	var sorted_planes: Array = planes.duplicate(true)
	sorted_planes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	for id in ids:
		var body: Dictionary = world["bodies"][id]
		if not bool(body["dynamic"]): continue
		for plane in sorted_planes:
			var normal: Vector3 = plane["normal"]
			if normal.length() <= EPS: continue
			normal = normal.normalized()
			var gap0 := normal.dot(body["position"]) - float(plane["offset"]) - float(body["radius"])
			if gap0 <= CONTACT_TOLERANCE: continue
			var p_end: Vector3 = body["position"] + body["linear_velocity"] * dt + 0.5 * world["gravity"] * dt * dt
			var gap1 := normal.dot(p_end) - float(plane["offset"]) - float(body["radius"])
			if gap1 > 0.0: continue
			var lo := 0.0
			var hi := dt
			for _iter in range(64):
				if hi - lo <= 1.0e-11: break
				var mid := 0.5 * (lo + hi)
				var p_mid: Vector3 = body["position"] + body["linear_velocity"] * mid + 0.5 * world["gravity"] * mid * mid
				var gap_mid := normal.dot(p_mid) - float(plane["offset"]) - float(body["radius"])
				if gap_mid <= 0.0: hi = mid
				else: lo = mid
			if hi < best_dt:
				best_dt = hi
				best = {"found": true, "dt": hi, "body_id": String(id), "plane_id": String(plane["id"])}
	return best if not best.is_empty() else {"found": false}

# =============================================================================
# ADMM + SPARSE HELPERS
# =============================================================================

static func _admm_cone(a: Array, b: Array, mu: Array, warm: Array, rho: float, tolerance: float, max_iterations: int) -> Dictionary:
	if rho <= 0.0 or tolerance <= 0.0 or max_iterations < 1:
		return {"ok": false, "code": "BAD_SOLVER_OPTIONS"}
	var n := b.size()
	var h: Array = []
	for r in range(n):
		var row: Array = a[r].duplicate(true)
		row[r] = float(row[r]) + rho
		h.append(row)
	var chol := _cholesky(h)
	if not bool(chol.get("ok", false)):
		return {"ok": false, "code": "ADMM_FACTOR_FAILED"}
	var lambda: Array = warm.duplicate(true)
	var z: Array = warm.duplicate(true)
	var u := _zero_vector(n)
	# Ensure warm cache itself is admissible.
	for ci in range(mu.size()):
		var p := _project_cone(Vector3(z[3*ci],z[3*ci+1],z[3*ci+2]), float(mu[ci]))
		z[3*ci]=p.x; z[3*ci+1]=p.y; z[3*ci+2]=p.z
		lambda[3*ci]=p.x; lambda[3*ci+1]=p.y; lambda[3*ci+2]=p.z
	var primal := INF
	var dual := INF
	var iterations := 0
	for iteration in range(max_iterations):
		iterations = iteration + 1
		var rhs := _zero_vector(n)
		for i in range(n): rhs[i] = rho * (float(z[i]) - float(u[i])) - float(b[i])
		lambda = _cholesky_solve(chol["l"], rhs)
		var old_z: Array = z.duplicate(true)
		for ci in range(mu.size()):
			var q := Vector3(lambda[3*ci]+u[3*ci], lambda[3*ci+1]+u[3*ci+1], lambda[3*ci+2]+u[3*ci+2])
			var p := _project_cone(q, float(mu[ci]))
			z[3*ci]=p.x; z[3*ci+1]=p.y; z[3*ci+2]=p.z
		for i in range(n): u[i] = float(u[i]) + float(lambda[i]) - float(z[i])
		primal = 0.0; dual = 0.0
		for i in range(n):
			primal = maxf(primal, absf(float(lambda[i]) - float(z[i])))
			dual = maxf(dual, rho * absf(float(z[i]) - float(old_z[i])))
		if maxf(primal, dual) <= tolerance: break
	if maxf(primal, dual) > tolerance:
		return {"ok": false, "code": "ADMM_NO_CONVERGENCE", "iterations": iterations, "primal_residual": primal, "dual_residual": dual}
	return {"ok": true, "lambda": z, "iterations": iterations, "primal_residual": primal, "dual_residual": dual}

static func _append_body_jacobian(row: Dictionary, world: Dictionary, body_index: Dictionary, body_id: String, d: Vector3, r: Vector3, sign: float) -> void:
	if body_id.begins_with("@static/") or not body_index.has(body_id): return
	var base := 6 * int(body_index[body_id])
	var angular := r.cross(d)
	var values := [d.x,d.y,d.z,angular.x,angular.y,angular.z]
	for i in range(6):
		var v := sign * float(values[i])
		if absf(v) > EPS: row[base+i] = v

static func _island_inverse_mass(world: Dictionary, body_ids: Array) -> Array:
	var result: Array = []
	for id in body_ids:
		var b: Dictionary = world["bodies"][id]
		result.append(float(b["inv_mass"])); result.append(float(b["inv_mass"])); result.append(float(b["inv_mass"]))
		var ii: Vector3 = b["inv_inertia"]
		result.append(ii.x); result.append(ii.y); result.append(ii.z)
	return result

static func _assemble_sparse_effective_mass(rows: Array, minv: Array) -> Dictionary:
	var result := {}
	for i in range(rows.size()):
		for j in range(i, rows.size()):
			var sum := 0.0
			# intersect sparse column keys
			for k in rows[i].keys():
				if rows[j].has(k): sum += float(rows[i][k]) * float(minv[int(k)]) * float(rows[j][k])
			if absf(sum) > EPS:
				result["%d:%d" % [i,j]] = sum
				if i != j: result["%d:%d" % [j,i]] = sum
	return result

static func _sparse_to_dense(sparse: Dictionary, size: int) -> Array:
	var result: Array = []
	for r in range(size):
		var row := _zero_vector(size); result.append(row)
	for key in sparse.keys():
		var parts := String(key).split(":")
		result[int(parts[0])][int(parts[1])] = float(sparse[key])
	return result

static func _sparse_mat_t_vec(rows: Array, vector: Array, cols: int) -> Array:
	var result := _zero_vector(cols)
	for r in range(rows.size()):
		for c in rows[r].keys(): result[int(c)] += float(rows[r][c]) * float(vector[r])
	return result

static func _sparse_row_entry_count(rows: Array) -> int:
	var count := 0
	for row in rows: count += row.size()
	return count

static func _relative_contact_component(world: Dictionary, free: Dictionary, c: Dictionary, d: Vector3) -> float:
	var va := _point_velocity(world, free, String(c["body_a"]), c["r_a"])
	var vb := _point_velocity(world, free, String(c["body_b"]), c["r_b"])
	return d.dot(va - vb)

static func _point_velocity(world: Dictionary, free: Dictionary, body_id: String, r: Vector3) -> Vector3:
	if body_id.begins_with("@static/"): return Vector3.ZERO
	var v: Dictionary = free[body_id]
	return v["linear"] + v["angular"].cross(r)

static func _project_cone(q: Vector3, mu: float) -> Vector3:
	var n := q.x
	var t := Vector2(q.y,q.z)
	var tn := t.length()
	if mu <= EPS: return Vector3(maxf(n,0.0),0.0,0.0)
	if n >= 0.0 and tn <= mu*n: return q
	var pn := (n + mu*tn) / (1.0 + mu*mu)
	if pn <= 0.0: return Vector3.ZERO
	if tn <= EPS: return Vector3(pn,0.0,0.0)
	var s := mu*pn/tn
	return Vector3(pn,t.x*s,t.y*s)

static func _tangent_basis(n: Vector3) -> Array:
	var normal := n.normalized()
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var ref: Vector3 = axes[0]
	var best := absf(normal.dot(ref))
	for i in range(1,3):
		var score := absf(normal.dot(axes[i]))
		if score < best: best=score; ref=axes[i]
	var t1 := normal.cross(ref).normalized()
	var t2 := normal.cross(t1).normalized()
	return [t1,t2]

static func _contact_ids(contacts: Array) -> Array:
	var ids: Array = []
	for c in contacts: ids.append(String(c["id"]))
	ids.sort(); return ids

static func _cholesky(matrix: Array) -> Dictionary:
	var n := matrix.size(); var l: Array = []
	for r in range(n): l.append(_zero_vector(n))
	for i in range(n):
		for j in range(i+1):
			var sum := float(matrix[i][j])
			for k in range(j): sum -= float(l[i][k])*float(l[j][k])
			if i==j:
				if sum <= EPS: return {"ok":false}
				l[i][j]=sqrt(sum)
			else: l[i][j]=sum/float(l[j][j])
	return {"ok":true,"l":l}

static func _cholesky_solve(l: Array, rhs: Array) -> Array:
	var n := rhs.size()
	var y := _zero_vector(n)
	for i in range(n):
		var value := float(rhs[i])
		for k in range(i):
			value -= float(l[i][k]) * float(y[k])
		y[i] = value / float(l[i][i])
	var x := _zero_vector(n)
	for ii in range(n):
		var i := n - 1 - ii
		var value := float(y[i])
		for k in range(i + 1, n):
			value -= float(l[k][i]) * float(x[k])
		x[i] = value / float(l[i][i])
	return x

static func _zero_vector(size: int) -> Array:
	var r:Array=[]; r.resize(size); r.fill(0.0); return r

# =============================================================================
# CANONICAL STATE / RECOVERY EVIDENCE
# =============================================================================

static func world_hash(world: Dictionary) -> String:
	var bodies: Array = []
	var ids: Array = world["bodies"].keys(); ids.sort()
	for id in ids:
		var b: Dictionary = world["bodies"][id]
		if not bool(b["dynamic"]): continue
		bodies.append({
			"id":String(id),
			"p":_v(b["position"]),
			"v":_v(b["linear_velocity"]),
			"w":_v(b["angular_velocity"]),
		})
	var contacts: Array=[]
	var cids:Array=world["contact_cache"].keys(); cids.sort()
	for cid in cids:
		var c:Dictionary=world["contact_cache"][cid]
		contacts.append({"id":String(cid),"age":int(c["age_steps"]),"warm":_v(c["warm_impulse"])})
	var payload:=JSON.stringify({"time":float(world["time"]),"step":int(world["step"]),"bodies":bodies,"contacts":contacts},"",false)
	var ctx:=HashingContext.new(); ctx.start(HashingContext.HASH_SHA256); ctx.update(payload.to_utf8_buffer()); return ctx.finish().hex_encode()

static func _v(v: Vector3) -> Array: return [v.x,v.y,v.z]
