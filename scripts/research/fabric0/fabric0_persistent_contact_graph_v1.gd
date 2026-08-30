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
