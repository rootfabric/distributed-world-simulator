class_name Fabric0GraphMcpV1
extends RefCounted

const Model = preload("res://scripts/research/fabric0/fabric0_general_convex_model_v1.gd")
const EPS := 1.0e-12

static func solve(bodies:Array, contacts:Array, dt:float, options:Dictionary={}) -> Dictionary:
	if dt <= 0.0:
		return {"ok":false, "code":"BAD_STEP"}
	if contacts.is_empty():
		return {
			"ok":true,
			"blocks":{},
			"normal_solver":"ACTIVE_SET_LCP",
			"normal_iterations":0,
			"coupling_iterations":0,
			"normal_residual":0.0,
			"max_complementarity_violation":0.0,
			"max_cone_violation":0.0,
			"max_normal_velocity_violation":0.0,
		}

	var work := contacts.duplicate(true)
	work.sort_custom(func(a:Dictionary, b:Dictionary) -> bool:
		return String(a["id"]) < String(b["id"])
	)

	var beta := float(options.get("beta", 0.18))
	var regularization := float(options.get("normal_regularization", 1.0e-9))
	if regularization < 0.0:
		return {"ok":false, "code":"NEGATIVE_NORMAL_REGULARIZATION"}

	var normal_tolerance := float(options.get("normal_tolerance", 1.0e-10))
	var normal_iterations := int(options.get("normal_iterations", 128))
	var tangent_iterations := int(options.get("tangent_iterations", 32))
	var coupling_iterations := int(options.get("coupling_iterations", 32))
	var coupling_tolerance := float(options.get("coupling_tolerance", 1.0e-9))
	if normal_iterations <= 0 or tangent_iterations < 0 or coupling_iterations <= 0:
		return {"ok":false, "code":"BAD_SOLVER_BUDGET"}

	var basis:Array = []
	for contact in work:
		basis.append(Model.tangent_basis(Vector3(contact["normal"])))

	var wmat := _normal_matrix(bodies, work, regularization)
	var base_state := _velocity_state(bodies)
	var pn:Array = []
	var pt:Array = []
	for _i in range(work.size()):
		pn.append(0.0)
		pt.append(Vector2.ZERO)

	var total_normal_iterations := 0
	var last_normal:Dictionary = {}
	var completed_coupling_iterations := 0
	var converged := false

	for outer in range(coupling_iterations):
		completed_coupling_iterations = outer + 1
		var previous_pn := pn.duplicate()
		var previous_pt := pt.duplicate()

		_restore_velocity_state(bodies, base_state)
		_apply_tangent_impulses(bodies, work, basis, pt)
		var q := _normal_q(bodies, work, dt, beta)
		var normal := _solve_lcp_active_set(wmat, q, normal_tolerance, normal_iterations)
		if not bool(normal["ok"]):
			return normal
		last_normal = normal
		total_normal_iterations += int(normal["iterations"])
		pn = normal["lambda"].duplicate()

		_restore_velocity_state(bodies, base_state)
		_apply_normal_impulses(bodies, work, pn)
		pt = _solve_tangent_fixed_normal(bodies, work, basis, pn, tangent_iterations)

		var impulse_delta := _max_impulse_delta(previous_pn, previous_pt, pn, pt)
		var audit := _audit_solution(bodies, work, pn, pt, dt, beta, regularization)
		if impulse_delta <= coupling_tolerance and float(audit["max_complementarity_violation"]) <= normal_tolerance * 10.0:
			converged = true
			break

	if not converged:
		var final_audit := _audit_solution(bodies, work, pn, pt, dt, beta, regularization)
		if float(final_audit["max_complementarity_violation"]) > normal_tolerance * 10.0:
			_restore_velocity_state(bodies, base_state)
			return {
				"ok":false,
				"code":"MCP_COUPLING_DID_NOT_CONVERGE",
				"coupling_iterations":completed_coupling_iterations,
				"max_complementarity_violation":float(final_audit["max_complementarity_violation"]),
			}

	var audit := _audit_solution(bodies, work, pn, pt, dt, beta, regularization)
	var blocks:Dictionary = {}
	for i in range(work.size()):
		var contact:Dictionary = work[i]
		var id := String(contact["id"])
		var tangent:Vector2 = pt[i]
		var limit := float(contact.get("mu", 0.5)) * float(pn[i])
		blocks[id] = {
			"pn":float(pn[i]),
			"pt":tangent,
			"t1":basis[i][0],
			"t2":basis[i][1],
			"mode":"slide" if limit > EPS and tangent.length() >= limit - 1.0e-8 else "stick",
			"normal_w":float(audit["normal_w"][i]),
			"vn_after":float(audit["normal_velocity"][i]),
		}

	return {
		"ok":true,
		"blocks":blocks,
		"normal_solver":"ACTIVE_SET_LCP",
		"friction_coupling":"OUTER_FIXED_POINT",
		"normal_iterations":total_normal_iterations,
		"coupling_iterations":completed_coupling_iterations,
		"normal_residual":float(last_normal.get("residual", 0.0)),
		"max_complementarity_violation":float(audit["max_complementarity_violation"]),
		"max_cone_violation":float(audit["max_cone_violation"]),
		"max_normal_velocity_violation":float(audit["max_normal_velocity_violation"]),
		"normal_matrix":wmat,
		"normal_regularization":regularization,
		"canonical_ids":work.map(func(c:Dictionary) -> String:return String(c["id"])),
	}

static func _normal_matrix(bodies:Array, contacts:Array, regularization:float) -> Array:
	var matrix:Array = []
	for i in range(contacts.size()):
		var row:Array = []
		for j in range(contacts.size()):
			var value := _w_entry(
				bodies,
				contacts[i],
				contacts[j],
				Vector3(contacts[i]["normal"]),
				Vector3(contacts[j]["normal"])
			)
			if i == j:
				value += regularization
			row.append(value)
		matrix.append(row)
	return matrix

static func _normal_q(bodies:Array, contacts:Array, dt:float, beta:float) -> Array:
	var q:Array = []
	for contact in contacts:
		var normal := Vector3(contact["normal"])
		var vn := Model.contact_velocity(bodies, contact).dot(normal)
		var penetration := maxf(0.0, -float(contact.get("gap", 0.0)))
		var desired := beta * penetration / dt
		q.append(vn - desired)
	return q

static func _solve_tangent_fixed_normal(
	bodies:Array,
	contacts:Array,
	basis:Array,
	pn:Array,
	iterations:int
) -> Array:
	var pt:Array = []
	for _i in range(contacts.size()):
		pt.append(Vector2.ZERO)
	for _iteration in range(iterations):
		for i in range(contacts.size()):
			var contact:Dictionary = contacts[i]
			var t1:Vector3 = basis[i][0]
			var t2:Vector3 = basis[i][1]
			var relative_velocity := Model.contact_velocity(bodies, contact)
			var tangent_velocity := Vector2(relative_velocity.dot(t1), relative_velocity.dot(t2))
			var effective := Model.effective_tangent2(bodies, contact, t1, t2)
			var delta := Model.solve2(effective, -tangent_velocity)
			var old:Vector2 = pt[i]
			var trial := old + delta
			var limit := float(contact.get("mu", 0.5)) * float(pn[i])
			var next := trial
			if trial.length() > limit and trial.length() > EPS:
				next = trial * (limit / trial.length())
			var difference := next - old
			pt[i] = next
			if difference.length() > EPS:
				Model.apply_impulse(bodies, contact, t1 * difference.x + t2 * difference.y)
	return pt

static func _apply_normal_impulses(bodies:Array, contacts:Array, pn:Array) -> void:
	for i in range(contacts.size()):
		if float(pn[i]) > EPS:
			Model.apply_impulse(bodies, contacts[i], Vector3(contacts[i]["normal"]) * float(pn[i]))

static func _apply_tangent_impulses(bodies:Array, contacts:Array, basis:Array, pt:Array) -> void:
	for i in range(contacts.size()):
		var tangent:Vector2 = pt[i]
		if tangent.length() <= EPS:
			continue
		var impulse := Vector3(basis[i][0]) * tangent.x + Vector3(basis[i][1]) * tangent.y
		Model.apply_impulse(bodies, contacts[i], impulse)

static func _audit_solution(
	bodies:Array,
	contacts:Array,
	pn:Array,
	pt:Array,
	dt:float,
	beta:float,
	regularization:float
) -> Dictionary:
	var normal_w:Array = []
	var normal_velocity:Array = []
	var max_complementarity := 0.0
	var max_cone := 0.0
	var max_normal_velocity_violation := 0.0
	for i in range(contacts.size()):
		var contact:Dictionary = contacts[i]
		var normal := Vector3(contact["normal"])
		var vn := Model.contact_velocity(bodies, contact).dot(normal)
		var penetration := maxf(0.0, -float(contact.get("gap", 0.0)))
		var desired := beta * penetration / dt
		var wi := vn - desired + regularization * float(pn[i])
		normal_w.append(wi)
		normal_velocity.append(vn)
		max_complementarity = maxf(max_complementarity, maxf(0.0, -float(pn[i])))
		max_complementarity = maxf(max_complementarity, maxf(0.0, -wi))
		max_complementarity = maxf(max_complementarity, absf(float(pn[i]) * wi))
		var limit := float(contact.get("mu", 0.5)) * float(pn[i])
		max_cone = maxf(max_cone, maxf(0.0, Vector2(pt[i]).length() - limit))
		max_normal_velocity_violation = maxf(max_normal_velocity_violation, maxf(0.0, desired - vn))
	return {
		"normal_w":normal_w,
		"normal_velocity":normal_velocity,
		"max_complementarity_violation":max_complementarity,
		"max_cone_violation":max_cone,
		"max_normal_velocity_violation":max_normal_velocity_violation,
	}

static func _max_impulse_delta(old_pn:Array, old_pt:Array, new_pn:Array, new_pt:Array) -> float:
	var maximum := 0.0
	for i in range(new_pn.size()):
		maximum = maxf(maximum, absf(float(new_pn[i]) - float(old_pn[i])))
		maximum = maxf(maximum, (Vector2(new_pt[i]) - Vector2(old_pt[i])).length())
	return maximum

static func _velocity_state(bodies:Array) -> Array:
	var state:Array = []
	for body in bodies:
		state.append({"v":Vector3(body["v"]), "w":Vector3(body["w"])})
	return state

static func _restore_velocity_state(bodies:Array, state:Array) -> void:
	for i in range(bodies.size()):
		bodies[i]["v"] = Vector3(state[i]["v"])
		bodies[i]["w"] = Vector3(state[i]["w"])

static func _w_entry(
	bodies:Array,
	contact_i:Dictionary,
	contact_j:Dictionary,
	direction_i:Vector3,
	direction_j:Vector3
) -> float:
	var total := 0.0
	for body_index in range(bodies.size()):
		var sign_j := _contact_sign(contact_j, body_index)
		if sign_j == 0.0:
			continue
		var sign_i := _contact_sign(contact_i, body_index)
		if sign_i == 0.0:
			continue
		var body:Dictionary = bodies[body_index]
		var rj := Vector3(contact_j["rb"]) if int(contact_j["b"]) == body_index else Vector3(contact_j["ra"])
		var ri := Vector3(contact_i["rb"]) if int(contact_i["b"]) == body_index else Vector3(contact_i["ra"])
		var linear_delta := direction_j * sign_j * float(body["inv_mass"])
		var angular_delta := Model.inertia_inv_mul(body, rj.cross(direction_j * sign_j))
		total += sign_i * direction_i.dot(linear_delta + angular_delta.cross(ri))
	return total

static func _contact_sign(contact:Dictionary, body_index:int) -> float:
	if int(contact["b"]) == body_index:
		return 1.0
	if int(contact["a"]) == body_index:
		return -1.0
	return 0.0

static func _solve_lcp_active_set(w:Array, q:Array, tolerance:float, max_iterations:int) -> Dictionary:
	var count := q.size()
	var active:Array = []
	for i in range(count):
		if float(q[i]) < 0.0:
			active.append(i)
	active.sort()

	var x:Array = []
	for _i in range(count):
		x.append(0.0)

	for iteration in range(max_iterations):
		for i in range(count):
			x[i] = 0.0

		if not active.is_empty():
			var restricted_matrix:Array = []
			var restricted_rhs:Array = []
			for row_index in active:
				var row:Array = []
				for column_index in active:
					row.append(float(w[int(row_index)][int(column_index)]))
				restricted_matrix.append(row)
				restricted_rhs.append(-float(q[int(row_index)]))
			var restricted := _solve_dense(restricted_matrix, restricted_rhs)
			if not bool(restricted["ok"]):
				return {
					"ok":false,
					"code":"MCP_SINGULAR_ACTIVE_SET",
					"iterations":iteration + 1,
					"detail":String(restricted.get("code", "DENSE_SOLVE_FAILED")),
				}
			for k in range(active.size()):
				x[int(active[k])] = float(restricted["x"][k])

		var remove_index := -1
		var most_negative := -tolerance
		for index in active:
			var value := float(x[int(index)])
			if value < most_negative:
				most_negative = value
				remove_index = int(index)
		if remove_index >= 0:
			active.erase(remove_index)
			continue

		var y := _mat_vec(w, x, q)
		var add_index := -1
		var most_violating := -tolerance
		for i in range(count):
			if active.has(i):
				continue
			var value := float(y[i])
			if value < most_violating:
				most_violating = value
				add_index = i
		if add_index >= 0:
			active.append(add_index)
			active.sort()
			continue

		var residual := 0.0
		for i in range(count):
			residual = maxf(residual, maxf(0.0, -float(x[i])))
			residual = maxf(residual, maxf(0.0, -float(y[i])))
			residual = maxf(residual, absf(float(x[i]) * float(y[i])))
		return {
			"ok":true,
			"lambda":x,
			"w":y,
			"iterations":iteration + 1,
			"residual":residual,
			"active":active.duplicate(),
		}

	return {"ok":false, "code":"MCP_ACTIVE_SET_DID_NOT_CONVERGE", "iterations":max_iterations}

static func _mat_vec(a:Array, x:Array, q:Array) -> Array:
	var out:Array = []
	for i in range(a.size()):
		var sum := float(q[i])
		for j in range(x.size()):
			sum += float(a[i][j]) * float(x[j])
		out.append(sum)
	return out

static func _solve_dense(a:Array, b:Array) -> Dictionary:
	var count := b.size()
	if a.size() != count:
		return {"ok":false, "code":"DENSE_DIMENSION_MISMATCH"}
	var matrix:Array = []
	for i in range(count):
		if a[i].size() != count:
			return {"ok":false, "code":"DENSE_DIMENSION_MISMATCH"}
		var row:Array = []
		for j in range(count):
			row.append(float(a[i][j]))
		row.append(float(b[i]))
		matrix.append(row)

	for column in range(count):
		var pivot := column
		var best := absf(float(matrix[column][column]))
		for row_index in range(column + 1, count):
			var candidate := absf(float(matrix[row_index][column]))
			if candidate > best:
				best = candidate
				pivot = row_index
		if best < 1.0e-14:
			return {"ok":false, "code":"DENSE_SINGULAR"}
		if pivot != column:
			var temporary = matrix[column]
			matrix[column] = matrix[pivot]
			matrix[pivot] = temporary

		var inverse_pivot := 1.0 / float(matrix[column][column])
		for j in range(column, count + 1):
			matrix[column][j] = float(matrix[column][j]) * inverse_pivot

		for row_index in range(count):
			if row_index == column:
				continue
			var factor := float(matrix[row_index][column])
			if absf(factor) <= EPS:
				continue
			for j in range(column, count + 1):
				matrix[row_index][j] = float(matrix[row_index][j]) - factor * float(matrix[column][j])

	var x:Array = []
	for i in range(count):
		x.append(float(matrix[i][count]))
	return {"ok":true, "x":x}
