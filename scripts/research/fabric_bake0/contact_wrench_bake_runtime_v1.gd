class_name FabricBakeContactWrenchRuntimeV1
extends RefCounted

const Compiler = preload("res://scripts/research/fabric_bake0/contact_wrench_bake_compiler_v1.gd")
const EPS := 1.0e-12

static func support(artifact: Dictionary, direction: Array) -> Dictionary:
	var checked := Compiler.validate_model(artifact)
	if not bool(checked.get("ok", false)):
		return checked
	var parsed := _six(direction)
	if not bool(parsed.get("ok", false)):
		return parsed
	var qf := Vector3(float(direction[0]), float(direction[1]), float(direction[2]))
	var qm := Vector3(float(direction[3]), float(direction[4]), float(direction[5]))
	var normal := _vec3(artifact["normal"])
	var t1 := _vec3(artifact["t1"])
	var t2 := _vec3(artifact["t2"])
	var mu_t := float(artifact["mu_tangent"])
	var mu_r := float(artifact["mu_rolling"])
	var mu_tau := float(artifact["mu_torsion"])
	var reff := float(artifact["effective_radius"])
	var best_score := 0.0
	var best: Dictionary = {}
	for generator_any in artifact["generators"]:
		var generator: Dictionary = generator_any
		var r := _vec3(generator["r"])
		var force_query := qf + qm.cross(r)
		var tangent_query := Vector2(force_query.dot(t1), force_query.dot(t2))
		var rolling_query := Vector2(qm.dot(t1), qm.dot(t2))
		var torsion_query := qm.dot(normal)
		var score := force_query.dot(normal) + mu_t * tangent_query.length() + mu_r * reff * rolling_query.length() + mu_tau * reff * absf(torsion_query)
		if score > best_score + EPS or (absf(score - best_score) <= EPS and (best.is_empty() or String(generator["member_id"]) < String(best["member_id"]))):
			best_score = score
			best = generator
	var support_value := 0.0
	var force := Vector3.ZERO
	var moment := Vector3.ZERO
	var local := {"normal": 0.0, "tangent": [0.0, 0.0], "rolling": [0.0, 0.0], "torsion": 0.0}
	if not best.is_empty() and best_score > EPS:
		var pn := float(artifact["normal_support_limit"])
		var r := _vec3(best["r"])
		var force_query := qf + qm.cross(r)
		var tangent_query := Vector2(force_query.dot(t1), force_query.dot(t2))
		var rolling_query := Vector2(qm.dot(t1), qm.dot(t2))
		var tangent := Vector2.ZERO
		if tangent_query.length() > EPS and mu_t > 0.0:
			tangent = tangent_query.normalized() * (mu_t * pn)
		var rolling := Vector2.ZERO
		if rolling_query.length() > EPS and mu_r > 0.0 and reff > 0.0:
			rolling = rolling_query.normalized() * (mu_r * pn * reff)
		var torsion := 0.0
		var torsion_query := qm.dot(normal)
		if absf(torsion_query) > EPS and mu_tau > 0.0 and reff > 0.0:
			torsion = signf(torsion_query) * mu_tau * pn * reff
		force = normal * pn + t1 * tangent.x + t2 * tangent.y
		var explicit_moment := t1 * rolling.x + t2 * rolling.y + normal * torsion
		moment = r.cross(force) + explicit_moment
		support_value = qf.dot(force) + qm.dot(moment)
		local = {"normal": pn, "tangent": [tangent.x, tangent.y], "rolling": [rolling.x, rolling.y], "torsion": torsion}
	var formula_value := maxf(0.0, best_score) * float(artifact["normal_support_limit"])
	var projection_error := absf(support_value - formula_value)
	if projection_error > 2.0e-10 * maxf(1.0, absf(formula_value)):
		return {"ok": false, "code": "B0_3_SUPPORT_WITNESS_PROJECTION_MISMATCH", "error": projection_error}
	return {
		"ok": true,
		"kind": "B0_3_BOUNDARY_WRENCH_SUPPORT",
		"support": formula_value,
		"wrench": [force.x, force.y, force.z, moment.x, moment.y, moment.z],
		"selected_generator": String(best.get("member_id", "NONE")),
		"local_witness": local,
		"noncanonical_witness": true,
		"projection_error": projection_error,
	}

static func maximum_dissipation_wrench(artifact: Dictionary, twist: Array) -> Dictionary:
	var parsed := _six(twist)
	if not bool(parsed.get("ok", false)):
		return parsed
	var direction: Array = []
	for value in twist:
		direction.append(-float(value))
	var result := support(artifact, direction)
	if not bool(result.get("ok", false)):
		return result
	var wrench: Array = result["wrench"]
	var power := 0.0
	for i in range(6):
		power += float(twist[i]) * float(wrench[i])
	if power > 1.0e-10:
		return {"ok": false, "code": "B0_3_PASSIVITY_VIOLATION", "power": power}
	var out := result.duplicate(true)
	out["kind"] = "B0_3_MAXIMUM_DISSIPATION_WRENCH"
	out["contact_power"] = power
	out["dissipation"] = maxf(0.0, -power)
	return out

static func normal_support_guard(artifact: Dictionary, demanded_normal_support: float, support_tolerance: float = 1.0e-12) -> Dictionary:
	var checked := Compiler.validate_model(artifact)
	if not bool(checked.get("ok", false)):
		return checked
	if not is_finite(demanded_normal_support) or support_tolerance < 0.0 or not is_finite(support_tolerance):
		return {"ok": false, "code": "B0_3_BAD_SUPPORT_GUARD_INPUT"}
	var limit := float(artifact["normal_support_limit"])
	var support_guard := demanded_normal_support - support_tolerance
	var capacity_margin := limit - demanded_normal_support
	return {
		"ok": true,
		"kind": "B0_3_NORMAL_SUPPORT_GUARD",
		"support_guard": support_guard,
		"capacity_margin": capacity_margin,
		"persistent_contact_feasible": support_guard > 0.0,
		"separation_candidate": support_guard <= 0.0,
		"capacity_exceeded": capacity_margin < -support_tolerance,
		"event_semantics": "SUPPORT_TO_SEPARATION" if support_guard <= 0.0 else "PERSISTENT_SUPPORT",
	}

static func directional_wrench_guard(artifact: Dictionary, direction: Array, demanded_projection: float, tolerance: float = 1.0e-10) -> Dictionary:
	if not is_finite(demanded_projection) or not is_finite(tolerance) or tolerance < 0.0:
		return {"ok": false, "code": "B0_3_BAD_DIRECTIONAL_GUARD_INPUT"}
	var capacity := support(artifact, direction)
	if not bool(capacity.get("ok", false)):
		return capacity
	var margin := float(capacity["support"]) - demanded_projection
	return {
		"ok": true,
		"kind": "B0_3_DIRECTIONAL_WRENCH_GUARD",
		"capacity": float(capacity["support"]),
		"demanded_projection": demanded_projection,
		"margin": margin,
		"feasible": margin >= -tolerance,
		"refinement_required": margin < -tolerance,
		"event_semantics": "WRENCH_CAPACITY_EXIT" if margin < -tolerance else "PERSISTENT_WRENCH_FEASIBLE",
	}

static func wrench_projection(wrench: Array, direction: Array) -> Dictionary:
	var a := _six(wrench)
	if not bool(a.get("ok", false)):
		return a
	var b := _six(direction)
	if not bool(b.get("ok", false)):
		return b
	var value := 0.0
	for i in range(6):
		value += float(wrench[i]) * float(direction[i])
	return {"ok": true, "value": value}

static func _six(value) -> Dictionary:
	if not (value is Array) or Array(value).size() != 6:
		return {"ok": false, "code": "B0_3_BAD_6D_VECTOR"}
	for component in Array(value):
		if not (component is int or component is float) or not is_finite(float(component)):
			return {"ok": false, "code": "B0_3_NONFINITE_6D_VECTOR"}
	return {"ok": true}

static func _vec3(value) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
