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
