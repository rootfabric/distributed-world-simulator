class_name Fabric0MultiContactConeV1
extends RefCounted

const EPSILON := 1.0e-12
const DEFAULT_CONTACT_TOLERANCE := 1.0e-9
const DEFAULT_ADMM_RHO := 0.1
const DEFAULT_ADMM_TOLERANCE := 1.0e-9
const DEFAULT_ADMM_MAX_ITERATIONS := 12000
const ACTIVE_IMPULSE_EPSILON := 1.0e-8
const SLIDING_TOLERANCE := 1.0e-7

# =============================================================================
# BODY / GEOMETRY DESCRIPTORS
# =============================================================================

static func new_box_body(
	body_id: String,
	mass: float,
	inertia_diag_world: Vector3,
	position: Vector3,
	linear_velocity: Vector3,
	angular_velocity: Vector3,
	half_extents: Vector3,
	basis: Basis = Basis.IDENTITY
) -> Dictionary:
	return {
		"id": body_id,
		"mass": mass,
		"inertia_diag_world": inertia_diag_world,
		"position": position,
		"linear_velocity": linear_velocity,
		"angular_velocity": angular_velocity,
		"half_extents": half_extents,
		"basis": basis,
	}

static func new_plane(
	plane_id: String,
	normal: Vector3,
	offset: float,
	friction: float,
	restitution: float
) -> Dictionary:
	return {
		"id": plane_id,
		"normal": normal,
		"offset": offset,
		"friction": friction,
		"restitution": restitution,
	}

static func validate_body(body: Dictionary) -> Dictionary:
	if String(body.get("id", "")).is_empty():
		return {"ok": false, "code": "BODY_ID_EMPTY"}
	if float(body.get("mass", 0.0)) <= 0.0:
		return {"ok": false, "code": "BODY_MASS_NONPOSITIVE"}
	var inertia: Vector3 = body.get("inertia_diag_world", Vector3.ZERO)
	if inertia.x <= 0.0 or inertia.y <= 0.0 or inertia.z <= 0.0:
		return {"ok": false, "code": "BODY_INERTIA_NONPOSITIVE"}
	var h: Vector3 = body.get("half_extents", Vector3.ZERO)
	if h.x <= 0.0 or h.y <= 0.0 or h.z <= 0.0:
		return {"ok": false, "code": "BOX_HALF_EXTENT_NONPOSITIVE"}
	return {"ok": true}

# =============================================================================
# GEOMETRY -> CONTACT MANIFOLD
# =============================================================================

static func compile_box_plane_manifold(
	body: Dictionary,
	planes: Array,
	contact_tolerance: float = DEFAULT_CONTACT_TOLERANCE
) -> Dictionary:
	var body_check := validate_body(body)
	if not bool(body_check.get("ok", false)):
		return body_check
	if contact_tolerance <= 0.0:
		return {"ok": false, "code": "CONTACT_TOLERANCE_NONPOSITIVE"}

	var vertices := _box_vertices(body)
	var contacts: Array = []
	var diagnostics: Array = []
	var seen_plane_ids := {}

	for raw_plane in planes:
		var plane: Dictionary = raw_plane
		var plane_id := String(plane.get("id", ""))
		if plane_id.is_empty() or seen_plane_ids.has(plane_id):
			return {"ok": false, "code": "PLANE_ID_INVALID_OR_DUPLICATE", "plane_id": plane_id}
		seen_plane_ids[plane_id] = true
		var raw_normal: Vector3 = plane.get("normal", Vector3.ZERO)
		var normal_length := raw_normal.length()
		if normal_length <= EPSILON:
			return {"ok": false, "code": "PLANE_NORMAL_ZERO", "plane_id": plane_id}
		var normal := raw_normal / normal_length
		var offset := float(plane.get("offset", 0.0))
		var mu := float(plane.get("friction", -1.0))
		var restitution := float(plane.get("restitution", -1.0))
		if mu < 0.0:
			return {"ok": false, "code": "NEGATIVE_FRICTION", "plane_id": plane_id}
		if restitution < 0.0 or restitution > 1.0:
			return {"ok": false, "code": "RESTITUTION_OUT_OF_RANGE", "plane_id": plane_id}
		var tangent_basis := _tangent_basis(normal)

		for vertex in vertices:
			var point: Vector3 = vertex["world"]
			var gap := normal.dot(point) - offset
			if gap < -contact_tolerance:
				diagnostics.append({
					"code": "GEOMETRY_PENETRATION_OUTSIDE_EVENT_TOLERANCE",
					"plane_id": plane_id,
					"vertex_id": String(vertex["id"]),
					"gap": gap,
				})
				continue
			if absf(gap) <= contact_tolerance:
				contacts.append({
					"id": "%s::%s" % [plane_id, String(vertex["id"])],
					"plane_id": plane_id,
					"vertex_id": String(vertex["id"]),
					"point": point,
					"r": point - body["position"],
					"gap": gap,
					"normal": normal,
					"tangent_1": tangent_basis[0],
					"tangent_2": tangent_basis[1],
					"friction": mu,
					"restitution": restitution,
				})

	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["id"]) < String(b["id"])
	)

	var ids: Array = []
	for contact in contacts:
		ids.append(String(contact["id"]))
	return {
		"ok": true,
		"contacts": contacts,
		"contact_ids": ids,
		"diagnostics": diagnostics,
		"contact_count": contacts.size(),
	}

static func _box_vertices(body: Dictionary) -> Array:
	var h: Vector3 = body["half_extents"]
	var basis: Basis = body.get("basis", Basis.IDENTITY)
	var position: Vector3 = body["position"]
	var result: Array = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var local := Vector3(sx * h.x, sy * h.y, sz * h.z)
				var r := basis * local
				result.append({
					"id": "%sx_%sy_%sz" % [_sign_token(sx), _sign_token(sy), _sign_token(sz)],
					"local": local,
					"world": position + r,
				})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["id"]) < String(b["id"])
	)
	return result

static func _sign_token(value: float) -> String:
	return "m" if value < 0.0 else "p"

# Deterministic orthonormal tangent basis. Pick the global axis least aligned
# with n so the result is stable and avoids a near-zero cross product.
static func _tangent_basis(normal: Vector3) -> Array:
	var n := normal.normalized()
	var axes := [Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0)]
	var ref: Vector3 = axes[0]
	var best := absf(n.dot(ref))
	for i in range(1, axes.size()):
		var candidate: Vector3 = axes[i]
		var score := absf(n.dot(candidate))
		if score < best:
			best = score
			ref = candidate
	var t1 := n.cross(ref).normalized()
	var t2 := n.cross(t1).normalized()
	return [t1, t2]

# =============================================================================
# GLOBAL MULTI-CONTACT IMPULSE / FRICTION-CONE SOLVE
# =============================================================================

# Solve the convex research impact problem:
#
#   minimize  1/2 lambda^T (J M^-1 J^T) lambda + b^T lambda
#   subject to each contact impulse lying in
#       j_n >= 0
#       ||j_t|| <= mu * j_n
#
# b_n = (1+e) * v_n^- ; b_t = v_t^-.
#
# This is a maximum-dissipation / cone-projected impact candidate. It is not a
# claim of a complete production rigid-body impact law. The important FABRIC0.9
# property is that ALL contacts are assembled and solved together, not visited
# sequentially as object callbacks.
static func solve_impact(body: Dictionary, input_contacts: Array, options: Dictionary = {}) -> Dictionary:
	var body_check := validate_body(body)
	if not bool(body_check.get("ok", false)):
		return body_check
	if input_contacts.is_empty():
		return {"ok": false, "code": "EMPTY_CONTACT_MANIFOLD"}

	var contacts: Array = []
	var seen := {}
	for source in input_contacts:
		var contact: Dictionary = source.duplicate(true)
		var contact_id := String(contact.get("id", ""))
		if contact_id.is_empty() or seen.has(contact_id):
			return {"ok": false, "code": "CONTACT_ID_INVALID_OR_DUPLICATE", "contact_id": contact_id}
		seen[contact_id] = true
		if float(contact.get("friction", -1.0)) < 0.0:
			return {"ok": false, "code": "NEGATIVE_FRICTION", "contact_id": contact_id}
		var restitution := float(contact.get("restitution", -1.0))
		if restitution < 0.0 or restitution > 1.0:
			return {"ok": false, "code": "RESTITUTION_OUT_OF_RANGE", "contact_id": contact_id}
		contacts.append(contact)
	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["id"]) < String(b["id"])
	)

	var rho := float(options.get("rho", DEFAULT_ADMM_RHO))
	var tolerance := float(options.get("tolerance", DEFAULT_ADMM_TOLERANCE))
	var max_iterations := int(options.get("max_iterations", DEFAULT_ADMM_MAX_ITERATIONS))
	if rho <= 0.0 or tolerance <= 0.0 or max_iterations < 1:
		return {"ok": false, "code": "BAD_SOLVER_OPTIONS"}

	var mass := float(body["mass"])
	var body_linear: Vector3 = body["linear_velocity"]
	var body_angular: Vector3 = body["angular_velocity"]
	var inertia: Vector3 = body["inertia_diag_world"]
	var minv := [1.0 / mass, 1.0 / mass, 1.0 / mass, 1.0 / inertia.x, 1.0 / inertia.y, 1.0 / inertia.z]
	var pre_generalized := _generalized_velocity(body_linear, body_angular)

	var jacobian: Array = []
	var b: Array = []
	var pre_contact_velocity := {}
	for contact in contacts:
		var r: Vector3 = contact["r"]
		var n: Vector3 = contact["normal"]
		var t1: Vector3 = contact["tangent_1"]
		var t2: Vector3 = contact["tangent_2"]
		var row_n := _jacobian_row(n, r)
		var row_t1 := _jacobian_row(t1, r)
		var row_t2 := _jacobian_row(t2, r)
		jacobian.append(row_n)
		jacobian.append(row_t1)
		jacobian.append(row_t2)
		var vn := _dot(row_n, pre_generalized)
		var vt1 := _dot(row_t1, pre_generalized)
		var vt2 := _dot(row_t2, pre_generalized)
		pre_contact_velocity[String(contact["id"])] = Vector3(vn, vt1, vt2)
		b.append((1.0 + float(contact["restitution"])) * vn)
		b.append(vt1)
		b.append(vt2)

	var a := _effective_mass_matrix(jacobian, minv)
	var rank := _matrix_rank(a, 1.0e-10)
	var h := a.duplicate(true)
	for i in range(h.size()):
		h[i][i] = float(h[i][i]) + rho
	var chol := _cholesky(h)
	if not bool(chol.get("ok", false)):
		return {"ok": false, "code": "CONE_ADMM_FACTOR_FAILED"}
	var l: Array = chol["l"]

	var size := b.size()
	var lambda := _zero_vector(size)
	var z := _zero_vector(size)
	var u := _zero_vector(size)
	var primal_residual := INF
	var dual_residual := INF
	var iterations := 0

	for iteration in range(max_iterations):
		iterations = iteration + 1
		var rhs := _zero_vector(size)
		for i in range(size):
			rhs[i] = rho * (float(z[i]) - float(u[i])) - float(b[i])
		lambda = _cholesky_solve(l, rhs)
		var z_previous: Array = z.duplicate(true)
		for contact_index in range(contacts.size()):
			var base := 3 * contact_index
			var q := Vector3(
				float(lambda[base]) + float(u[base]),
				float(lambda[base + 1]) + float(u[base + 1]),
				float(lambda[base + 2]) + float(u[base + 2])
			)
			var projected := _project_friction_cone(q, float(contacts[contact_index]["friction"]))
			z[base] = projected.x
			z[base + 1] = projected.y
			z[base + 2] = projected.z
		for i in range(size):
			u[i] = float(u[i]) + float(lambda[i]) - float(z[i])
		primal_residual = 0.0
		dual_residual = 0.0
		for i in range(size):
			primal_residual = maxf(primal_residual, absf(float(lambda[i]) - float(z[i])))
			dual_residual = maxf(dual_residual, rho * absf(float(z[i]) - float(z_previous[i])))
		if maxf(primal_residual, dual_residual) <= tolerance:
			break

	if maxf(primal_residual, dual_residual) > tolerance:
		return {
			"ok": false,
			"code": "CONE_ADMM_NO_CONVERGENCE",
			"iterations": iterations,
			"primal_residual": primal_residual,
			"dual_residual": dual_residual,
		}

	var generalized_impulse := _mat_t_vec(jacobian, z)
	var post_generalized: Array = pre_generalized.duplicate(true)
	for i in range(6):
