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
