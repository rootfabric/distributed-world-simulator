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
		post_generalized[i] = float(post_generalized[i]) + float(minv[i]) * float(generalized_impulse[i])
	var post_linear := Vector3(float(post_generalized[0]), float(post_generalized[1]), float(post_generalized[2]))
	var post_angular := Vector3(float(post_generalized[3]), float(post_generalized[4]), float(post_generalized[5]))

	var contact_results: Array = []
	var impulse_by_id := {}
	var total_impulse := Vector3.ZERO
	var total_torque_impulse := Vector3.ZERO
	var max_cone_violation := 0.0
	var active_count := 0
	var sliding_count := 0
	for contact_index in range(contacts.size()):
		var contact: Dictionary = contacts[contact_index]
		var base := 3 * contact_index
		var jn := float(z[base])
		var jt1 := float(z[base + 1])
		var jt2 := float(z[base + 2])
		var tangential_norm := sqrt(jt1 * jt1 + jt2 * jt2)
		var cone_limit := float(contact["friction"]) * jn
		max_cone_violation = maxf(max_cone_violation, maxf(-jn, tangential_norm - cone_limit))
		var active := jn > ACTIVE_IMPULSE_EPSILON
		var sliding := active and absf(tangential_norm - cone_limit) <= SLIDING_TOLERANCE * maxf(1.0, cone_limit)
		if active:
			active_count += 1
		if sliding:
			sliding_count += 1
		var n: Vector3 = contact["normal"]
		var t1: Vector3 = contact["tangent_1"]
		var t2: Vector3 = contact["tangent_2"]
		var world_impulse := n * jn + t1 * jt1 + t2 * jt2
		var r: Vector3 = contact["r"]
		total_impulse += world_impulse
		total_torque_impulse += r.cross(world_impulse)
		var pre_v: Vector3 = pre_contact_velocity[String(contact["id"])]
		var post_v := Vector3(
			_dot(jacobian[base], post_generalized),
			_dot(jacobian[base + 1], post_generalized),
			_dot(jacobian[base + 2], post_generalized)
		)
		var result := {
			"id": String(contact["id"]),
			"plane_id": String(contact["plane_id"]),
			"vertex_id": String(contact["vertex_id"]),
			"gap": float(contact["gap"]),
			"j_n": jn,
			"j_t1": jt1,
			"j_t2": jt2,
			"tangent_norm": tangential_norm,
			"cone_limit": cone_limit,
			"active": active,
			"sliding": sliding,
			"world_impulse": world_impulse,
			"pre_contact_velocity": pre_v,
			"post_contact_velocity": post_v,
		}
		contact_results.append(result)
		impulse_by_id[String(contact["id"])] = {
			"j_n": jn,
			"j_t1": jt1,
			"j_t2": jt2,
		}

	var delta_linear_momentum: Vector3 = mass * (post_linear - body_linear)
	var delta_angular_momentum := Vector3(
		inertia.x * (post_angular.x - body_angular.x),
		inertia.y * (post_angular.y - body_angular.y),
		inertia.z * (post_angular.z - body_angular.z)
	)
	var linear_impulse_residual: Vector3 = delta_linear_momentum - total_impulse
	var angular_impulse_residual: Vector3 = delta_angular_momentum - total_torque_impulse
	var energy_pre := _kinetic_energy(mass, inertia, body_linear, body_angular)
	var energy_post := _kinetic_energy(mass, inertia, post_linear, post_angular)

	var result := {
		"ok": true,
		"contacts": contact_results,
		"contact_count": contacts.size(),
		"active_contact_count": active_count,
		"sliding_contact_count": sliding_count,
		"post_linear_velocity": post_linear,
		"post_angular_velocity": post_angular,
		"total_impulse": total_impulse,
		"total_torque_impulse": total_torque_impulse,
		"linear_impulse_residual": linear_impulse_residual,
		"angular_impulse_residual": angular_impulse_residual,
		"energy_pre": energy_pre,
		"energy_post": energy_post,
		"energy_delta": energy_post - energy_pre,
		"max_cone_violation": maxf(max_cone_violation, 0.0),
		"matrix_rank": rank,
		"impulse_unknown_count": size,
		"redundant_impulse_manifold": rank < size,
		"iterations": iterations,
		"primal_residual": primal_residual,
		"dual_residual": dual_residual,
		"rho": rho,
		"tolerance": tolerance,
		"impulse_by_id": impulse_by_id,
	}
	result["state_hash"] = result_hash(result)
	return result

# Exact Euclidean projection onto {jn >= 0, ||jt|| <= mu*jn}.
static func _project_friction_cone(value: Vector3, mu: float) -> Vector3:
	var normal := value.x
	var tangent := Vector2(value.y, value.z)
	var tangent_norm := tangent.length()
	if mu <= EPSILON:
		return Vector3(maxf(normal, 0.0), 0.0, 0.0)
	if normal >= 0.0 and tangent_norm <= mu * normal:
		return value
	var projected_normal := (normal + mu * tangent_norm) / (1.0 + mu * mu)
	if projected_normal <= 0.0:
		return Vector3.ZERO
	if tangent_norm <= EPSILON:
		return Vector3(projected_normal, 0.0, 0.0)
	var scale := mu * projected_normal / tangent_norm
	return Vector3(projected_normal, tangent.x * scale, tangent.y * scale)

# =============================================================================
# AUDIT / CANONICAL RESULT
# =============================================================================

static func result_hash(result: Dictionary) -> String:
	var contacts: Array = []
	for contact in result.get("contacts", []):
		contacts.append({
			"id": String(contact["id"]),
			"j_n": float(contact["j_n"]),
			"j_t1": float(contact["j_t1"]),
			"j_t2": float(contact["j_t2"]),
			"active": bool(contact["active"]),
			"sliding": bool(contact["sliding"]),
		})
	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["id"]) < String(b["id"])
	)
	var payload := JSON.stringify({
		"post_linear_velocity": _vector_array(result.get("post_linear_velocity", Vector3.ZERO)),
		"post_angular_velocity": _vector_array(result.get("post_angular_velocity", Vector3.ZERO)),
		"total_impulse": _vector_array(result.get("total_impulse", Vector3.ZERO)),
		"total_torque_impulse": _vector_array(result.get("total_torque_impulse", Vector3.ZERO)),
		"contacts": contacts,
	}, "", false)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(payload.to_utf8_buffer())
	return context.finish().hex_encode()

static func _vector_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

# =============================================================================
# LINEAR ALGEBRA
# =============================================================================

static func _generalized_velocity(linear: Vector3, angular: Vector3) -> Array:
	return [linear.x, linear.y, linear.z, angular.x, angular.y, angular.z]

static func _jacobian_row(direction: Vector3, r: Vector3) -> Array:
