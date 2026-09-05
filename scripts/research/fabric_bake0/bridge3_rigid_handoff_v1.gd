extends RefCounted
## Rigid coordinate changes only. No integration, damping, impulses or source writes.
static func v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])
static func q(a: Array) -> Quaternion:
	return Quaternion(a[0], a[1], a[2], a[3])
static func a(vv: Vector3) -> Array:
	return [vv.x, vv.y, vv.z]
static func aq(qq: Quaternion) -> Array:
	qq = qq.normalized()
	if qq.w < 0.0:
		qq = Quaternion(-qq.x, -qq.y, -qq.z, -qq.w)
	return [qq.x, qq.y, qq.z, qq.w]

static func shift(state: Dictionary, offset: Array) -> Dictionary:
	var r := q(state.orientation) * v(offset)
	return {"position": a(v(state.position) + r), "orientation": state.orientation.duplicate(),
		"linear_velocity": a(v(state.linear_velocity) + v(state.angular_velocity).cross(r)),
		"angular_velocity": state.angular_velocity.duplicate()}

static func part_state(state: Dictionary, mapping: Dictionary) -> Dictionary:
	var out := shift(state, mapping.position_from_com)
	out.orientation = aq(q(state.orientation) * q(mapping.orientation_from_aggregate))
	return out

static func error(left: Dictionary, right: Dictionary) -> float:
	var e := 0.0
	for f in ["position", "linear_velocity", "angular_velocity"]:
		e = maxf(e, v(left[f]).distance_to(v(right[f])))
	return maxf(e, 1.0 - absf(q(left.orientation).dot(q(right.orientation))))

static func totals(mass: float, inertia: Array, state: Dictionary, origin: Array) -> Dictionary:
	var rot := Basis(q(state.orientation))
	var ib := Basis(Vector3(inertia[0][0], inertia[1][0], inertia[2][0]),
		Vector3(inertia[0][1], inertia[1][1], inertia[2][1]),
		Vector3(inertia[0][2], inertia[1][2], inertia[2][2]))
	var omega := v(state.angular_velocity)
	var spin := rot * ib * rot.transposed() * omega
	var p := mass * v(state.linear_velocity)
	return {"mass": mass, "linear": a(p), "angular": a(spin + (v(state.position) - v(origin)).cross(p)),
		"energy": 0.5 * mass * v(state.linear_velocity).length_squared() + 0.5 * omega.dot(spin)}

static func sum_totals(rows: Array) -> Dictionary:
	var result := {"mass": 0.0, "linear": [0.0, 0.0, 0.0], "angular": [0.0, 0.0, 0.0], "energy": 0.0}
	for row in rows:
		result.mass += row.mass
		result.energy += row.energy
		result.linear = a(v(result.linear) + v(row.linear))
		result.angular = a(v(result.angular) + v(row.angular))
	return result

static func conservation_error(left: Dictionary, right: Dictionary) -> Dictionary:
	return {"mass": absf(left.mass - right.mass), "linear": v(left.linear).distance_to(v(right.linear)),
		"angular": v(left.angular).distance_to(v(right.angular)), "energy": absf(left.energy - right.energy)}
