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

