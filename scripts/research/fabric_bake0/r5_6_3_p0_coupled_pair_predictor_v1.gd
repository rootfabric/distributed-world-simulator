extends RefCounted
## FABRIC R5.6.3 P0: read-only, two-point-mass coupled spring/damper predictor.
## No owner writes, journal, authoritative state, collision response or 6DOF claims.
## The caller must separately validate the canonical Construction snapshot and
## source/epoch fencing before using these proposed positions anywhere else.
const MAX_DT_S := 0.1
const MAX_STIFFNESS_NUMBER := 0.1
const MAX_DAMPING_NUMBER := 0.1
const MAX_ABS_COORD_M := 1.0e9
const MAX_ABS_VELOCITY_MPS := 1.0e8
const MAX_MASS_KG := 1.0e12

static func _fail(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "details": {}}

static func _ok(value: Dictionary) -> Dictionary:
	return {"success": true, "error_code": "", "details": value}

static func _finite_number(value) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value))

static func _vector(value, bound: float) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return _fail("R563_VECTOR_INVALID")
	for component in value:
		if not _finite_number(component) or absf(float(component)) > bound:
			return _fail("R563_VECTOR_UNSAFE")
	return _ok({"vector": Vector3(float(value[0]), float(value[1]), float(value[2]))})

static func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

## Exact input keys: a/b each {part_id,mass_kg,position_m,velocity_mps};
## link {stiffness_npm,rest_length_m,damping_nspm}; dt_s float.
## Semi-implicit Euler intentionally bounded by dimensionless omega*dt and
## c*dt*(1/m_a+1/m_b) guards; this is a proposed *local* integration, not an
## invariant energy integrator. Energy is diagnostic only.
static func predict(a: Dictionary, b: Dictionary, link: Dictionary, dt_s: float) -> Dictionary:
	var fields := ["part_id", "mass_kg", "position_m", "velocity_mps"]
	if a.keys().size() != 4 or b.keys().size() != 4:
		return _fail("R563_BODY_FIELDS_INVALID")
	for field in fields:
		if not a.has(field) or not b.has(field):
			return _fail("R563_BODY_FIELDS_INVALID")
	if link.keys().size() != 3 or not link.has("stiffness_npm") or \
			not link.has("rest_length_m") or not link.has("damping_nspm"):
		return _fail("R563_LINK_FIELDS_INVALID")
	if typeof(a.part_id) != TYPE_STRING or typeof(b.part_id) != TYPE_STRING or \
			String(a.part_id) == String(b.part_id) or \
			not String(a.part_id).begins_with("part/") or \
			not String(b.part_id).begins_with("part/"):
		return _fail("R563_PART_IDS_INVALID")
	if not _finite_number(a.mass_kg) or not _finite_number(b.mass_kg) or \
			float(a.mass_kg) <= 0.0 or float(b.mass_kg) <= 0.0 or \
			float(a.mass_kg) > MAX_MASS_KG or float(b.mass_kg) > MAX_MASS_KG:
		return _fail("R563_MASS_UNSAFE")
	if not _finite_number(link.stiffness_npm) or not _finite_number(link.rest_length_m) or \
			not _finite_number(link.damping_nspm) or float(link.stiffness_npm) <= 0.0 or \
			float(link.rest_length_m) < 0.0 or float(link.damping_nspm) < 0.0:
		return _fail("R563_LINK_UNSAFE")
	if not is_finite(dt_s) or dt_s <= 0.0 or dt_s > MAX_DT_S:
		return _fail("R563_DT_UNSAFE")
	var pa_result := _vector(a.position_m, MAX_ABS_COORD_M)
	var pb_result := _vector(b.position_m, MAX_ABS_COORD_M)
	var va_result := _vector(a.velocity_mps, MAX_ABS_VELOCITY_MPS)
	var vb_result := _vector(b.velocity_mps, MAX_ABS_VELOCITY_MPS)
	for result in [pa_result, pb_result, va_result, vb_result]:
		if not result.success:
			return result
	var ma: float = float(a.mass_kg)
	var mb: float = float(b.mass_kg)
	var k: float = float(link.stiffness_npm)
	var c: float = float(link.damping_nspm)
	var rest: float = float(link.rest_length_m)
	var inv_mass_sum: float = 1.0 / ma + 1.0 / mb
	var stiffness_number: float = dt_s * sqrt(k * inv_mass_sum)
	var damping_number: float = dt_s * c * inv_mass_sum
	if not is_finite(stiffness_number) or not is_finite(damping_number) or \
			stiffness_number > MAX_STIFFNESS_NUMBER or \
			damping_number > MAX_DAMPING_NUMBER:
		return _fail("R563_UNSTABLE_STEP")
	var pa: Vector3 = pa_result.details.vector
	var pb: Vector3 = pb_result.details.vector
	var va: Vector3 = va_result.details.vector
	var vb: Vector3 = vb_result.details.vector
	var axis: Vector3 = pb - pa
	var dist: float = axis.length()
	if not is_finite(dist) or dist <= 1.0e-12:
		return _fail("R563_DIRECTION_DEGENERATE")
	var normal: Vector3 = axis / dist
	var relative_radial_speed: float = (vb - va).dot(normal)
	var force_a: Vector3 = normal * (k * (dist - rest) + c * relative_radial_speed)
	var force_b: Vector3 = -force_a
	var next_va: Vector3 = va + force_a * (dt_s / ma)
	var next_vb: Vector3 = vb + force_b * (dt_s / mb)
	var next_pa: Vector3 = pa + next_va * dt_s
	var next_pb: Vector3 = pb + next_vb * dt_s
	for candidate in [next_va.x, next_va.y, next_va.z, next_vb.x, next_vb.y, next_vb.z]:
		if not is_finite(candidate) or absf(candidate) > MAX_ABS_VELOCITY_MPS:
			return _fail("R563_OUTPUT_UNSAFE")
	for candidate in [next_pa.x, next_pa.y, next_pa.z, next_pb.x, next_pb.y, next_pb.z]:
		if not is_finite(candidate) or absf(candidate) > MAX_ABS_COORD_M:
			return _fail("R563_OUTPUT_UNSAFE")
	var p_before: Vector3 = ma * va + mb * vb
	var p_after: Vector3 = ma * next_va + mb * next_vb
	var tolerance: float = 1.0e-10 * maxf(1.0, p_before.length())
	if not is_finite(p_after.length()) or (p_after - p_before).length() > tolerance:
		return _fail("R563_MOMENTUM_BUDGET_UNSAFE")
	var energy_before: float = 0.5 * ma * va.length_squared() + \
			0.5 * mb * vb.length_squared() + 0.5 * k * pow(dist - rest, 2.0)
	var length_after: float = (next_pb - next_pa).length()
	var energy_after: float = 0.5 * ma * next_va.length_squared() + \
			0.5 * mb * next_vb.length_squared() + 0.5 * k * pow(length_after - rest, 2.0)
	if not is_finite(energy_before) or not is_finite(energy_after):
		return _fail("R563_ENERGY_NONFINITE")
	return _ok({
		"part_a": {"part_id": a.part_id, "position_m": _array(next_pa), "velocity_mps": _array(next_va)},
		"part_b": {"part_id": b.part_id, "position_m": _array(next_pb), "velocity_mps": _array(next_vb)},
		"force_on_a_n": _array(force_a), "force_on_b_n": _array(force_b),
		"momentum_before_kgmps": _array(p_before), "momentum_after_kgmps": _array(p_after),
		"energy_before_j": energy_before, "energy_after_j": energy_after,
		"stiffness_number": stiffness_number, "damping_number": damping_number,
		"canonical_writes": 0, "authority": "DERIVED_PREDICTION_ONLY",
	})
