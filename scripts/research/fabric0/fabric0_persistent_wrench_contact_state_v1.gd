class_name Fabric0PersistentWrenchContactStateV1
extends RefCounted

const EPS := 1.0e-12
const DEFAULT_VELOCITY_TOLERANCE := 1.0e-10
const DEFAULT_SATURATION_TOLERANCE := 1.0e-9

static func observation_from_fabric_manifold(manifold: Dictionary) -> Dictionary:
	if not bool(manifold.get("ok", false)):
		return {"ok": false, "code": "BAD_FABRIC_MANIFOLD"}
	var pair_id := String(manifold.get("pair_id", ""))
	var split := pair_id.split("|")
	if split.size() != 2 or String(split[0]).is_empty() or String(split[1]).is_empty():
		return {"ok": false, "code": "BAD_FABRIC_MANIFOLD_PAIR_ID"}
	var points = manifold.get("points", [])
	if not (points is Array) or Array(points).is_empty():
		return {"ok": false, "code": "EMPTY_FABRIC_MANIFOLD"}
	var members: Array = []
	for point_any in Array(points):
		if not (point_any is Dictionary):
			return {"ok": false, "code": "BAD_FABRIC_MANIFOLD_POINT"}
		var point: Dictionary = point_any
		var id := String(point.get("id", ""))
		if id.is_empty():
			return {"ok": false, "code": "FABRIC_MANIFOLD_POINT_ID_MISSING"}
		members.append(id)
	return {"ok": true, "body_a": String(split[0]), "body_b": String(split[1]), "members": members}

static func solved_from_generalized_wrench(result: Dictionary) -> Dictionary:
	if not bool(result.get("ok", false)):
		return {"ok": false, "code": "BAD_GENERALIZED_WRENCH_RESULT"}
	for key in ["normal_impulse", "generalized_impulse", "generalized_velocity_after", "limits"]:
		if not result.has(key):
			return {"ok": false, "code": "INCOMPLETE_GENERALIZED_WRENCH_RESULT", "missing": key}
	return {
		"ok": true,
		"normal_support": result["normal_impulse"],
		"generalized_impulse": Array(result["generalized_impulse"]).duplicate(),
		"generalized_velocity_after": Array(result["generalized_velocity_after"]).duplicate(),
		"limits": Dictionary(result["limits"]).duplicate(true),
	}

static func begin(observation: Dictionary, solved: Dictionary, time: float, options: Dictionary = {}) -> Dictionary:
	var checked := _validate_common(observation, solved, time, options)
	if not bool(checked.get("ok", false)):
		return checked
	var identity := _identity(observation)
	if not bool(identity.get("ok", false)):
		return identity
	var classified := classify_modes(
		Array(solved["generalized_velocity_after"]),
		Array(solved["generalized_impulse"]),
		Dictionary(solved["limits"]),
		options
	)
	if not bool(classified.get("ok", false)):
		return classified
	var active := float(solved["normal_support"]) > float(options.get("normal_support_tolerance", EPS))
	return {
		"ok": true,
		"kind": "PERSISTENT_WRENCH_CONTACT_STATE",
		"active": active,
		"pair_id": identity["pair_id"],
		"manifold_identity": identity["manifold_identity"],
		"member_ids": identity["member_ids"],
		"first_seen_time": time,
		"last_seen_time": time,
		"contact_age": 0.0,
		"update_count": 0,
		"identity_epoch": 0,
		"identity_continued": false,
		"normal_support": float(solved["normal_support"]),
		"accepted_generalized_impulse": Array(solved["generalized_impulse"]).duplicate(),
		"generalized_velocity_after": Array(solved["generalized_velocity_after"]).duplicate(),
		"limits": Dictionary(solved["limits"]).duplicate(true),
		"modes": classified["modes"],
		"mode_transition_hypothesis": {},
		"warm_start_proposal": _zero_impulse(),
		"warm_start_source": "NONE_INITIAL_STATE",
		"solver_refresh_required": true,
		"signature": _signature(identity["pair_id"], identity["manifold_identity"], 0, time, solved, classified["modes"]),
	}

static func advance(previous: Dictionary, observation: Dictionary, solved: Dictionary, time: float, options: Dictionary = {}) -> Dictionary:
	if not bool(previous.get("ok", false)) or String(previous.get("kind", "")) != "PERSISTENT_WRENCH_CONTACT_STATE":
		return {"ok": false, "code": "BAD_PREVIOUS_STATE"}
	if time + EPS < float(previous.get("last_seen_time", 0.0)):
		return {"ok": false, "code": "TIME_REVERSAL", "previous_time": previous.get("last_seen_time"), "time": time}
	var checked := _validate_common(observation, solved, time, options)
	if not bool(checked.get("ok", false)):
		return checked
	var identity := _identity(observation)
	if not bool(identity.get("ok", false)):
		return identity
	var classified := classify_modes(
		Array(solved["generalized_velocity_after"]),
		Array(solved["generalized_impulse"]),
		Dictionary(solved["limits"]),
		options
	)
	if not bool(classified.get("ok", false)):
		return classified
	var continued := String(previous.get("pair_id", "")) == String(identity["pair_id"]) and String(previous.get("manifold_identity", "")) == String(identity["manifold_identity"])
	var support_tolerance := float(options.get("normal_support_tolerance", EPS))
	var active := float(solved["normal_support"]) > support_tolerance
	var first_seen := time
	var epoch := int(previous.get("identity_epoch", 0))
	var warm := _zero_impulse()
	var warm_source := "NONE_IDENTITY_RESET"
	var old_modes: Dictionary = {}
	if continued:
		first_seen = float(previous.get("first_seen_time", time))
		warm = _project_impulse(Array(previous.get("accepted_generalized_impulse", _zero_impulse())), Dictionary(solved["limits"]))
		warm_source = "PREVIOUS_ACCEPTED_PROJECTED_PROPOSAL"
		old_modes = Dictionary(previous.get("modes", {}))
	else:
		epoch += 1
	var hypothesis := _mode_transition_hypothesis(old_modes, Dictionary(classified["modes"])) if continued else {}
	return {
		"ok": true,
		"kind": "PERSISTENT_WRENCH_CONTACT_STATE",
		"active": active,
		"pair_id": identity["pair_id"],
		"manifold_identity": identity["manifold_identity"],
		"member_ids": identity["member_ids"],
		"first_seen_time": first_seen,
		"last_seen_time": time,
		"contact_age": maxf(0.0, time - first_seen),
		"update_count": int(previous.get("update_count", 0)) + 1 if continued else 0,
		"identity_epoch": epoch,
		"identity_continued": continued,
		"normal_support": float(solved["normal_support"]),
		"accepted_generalized_impulse": Array(solved["generalized_impulse"]).duplicate(),
		"generalized_velocity_after": Array(solved["generalized_velocity_after"]).duplicate(),
		"limits": Dictionary(solved["limits"]).duplicate(true),
		"modes": classified["modes"],
		"mode_transition_hypothesis": hypothesis,
		"warm_start_proposal": warm,
		"warm_start_source": warm_source,
		"solver_refresh_required": true,
		"signature": _signature(identity["pair_id"], identity["manifold_identity"], epoch, time, solved, classified["modes"]),
	}

static func separate(previous: Dictionary, time: float) -> Dictionary:
	if not bool(previous.get("ok", false)) or String(previous.get("kind", "")) != "PERSISTENT_WRENCH_CONTACT_STATE":
		return {"ok": false, "code": "BAD_PREVIOUS_STATE"}
	if time + EPS < float(previous.get("last_seen_time", 0.0)):
		return {"ok": false, "code": "TIME_REVERSAL"}
	var out := previous.duplicate(true)
	out["active"] = false
	out["last_seen_time"] = time
	out["contact_age"] = maxf(0.0, time - float(previous.get("first_seen_time", time)))
	out["normal_support"] = 0.0
	out["accepted_generalized_impulse"] = _zero_impulse()
	out["generalized_velocity_after"] = _zero_impulse()
	out["modes"] = {"tangent": "open", "rolling": "open", "torsion": "open"}
	out["mode_transition_hypothesis"] = {"contact": "SEPARATION_CANDIDATE"}
	out["warm_start_proposal"] = _zero_impulse()
	out["warm_start_source"] = "NONE_SEPARATED"
	out["solver_refresh_required"] = true
	out["signature"] = JSON.stringify({"pair": out["pair_id"], "manifold": out["manifold_identity"], "epoch": out["identity_epoch"], "time": time, "active": false}, "", false)
	return out

static func classify_modes(generalized_velocity_after: Array, generalized_impulse: Array, limits: Dictionary, options: Dictionary = {}) -> Dictionary:
	if generalized_velocity_after.size() != 5 or generalized_impulse.size() != 5:
		return {"ok": false, "code": "BAD_GENERALIZED_DIMENSION"}
	for value in generalized_velocity_after + generalized_impulse:
		if not _finite_number(value):
			return {"ok": false, "code": "NONFINITE_GENERALIZED_VALUE"}
	var parsed := _limits(limits)
	if not bool(parsed.get("ok", false)):
		return parsed
	var velocity_tolerance := float(options.get("velocity_tolerance", DEFAULT_VELOCITY_TOLERANCE))
	var saturation_tolerance := float(options.get("saturation_tolerance", DEFAULT_SATURATION_TOLERANCE))
	if velocity_tolerance <= 0.0 or saturation_tolerance <= 0.0:
		return {"ok": false, "code": "BAD_MODE_TOLERANCE"}
	var tangent_speed := Vector2(float(generalized_velocity_after[0]), float(generalized_velocity_after[1])).length()
	var rolling_speed := Vector2(float(generalized_velocity_after[2]), float(generalized_velocity_after[3])).length()
	var torsion_speed := absf(float(generalized_velocity_after[4]))
	var tangent_impulse := Vector2(float(generalized_impulse[0]), float(generalized_impulse[1])).length()
	var rolling_impulse := Vector2(float(generalized_impulse[2]), float(generalized_impulse[3])).length()
	var torsion_impulse := absf(float(generalized_impulse[4]))
	var tangent := _mode("tangent", tangent_speed, tangent_impulse, float(parsed["tangent"]), velocity_tolerance, saturation_tolerance, "slide")
	if not bool(tangent.get("ok", false)): return tangent
	var rolling := _mode("rolling", rolling_speed, rolling_impulse, float(parsed["rolling"]), velocity_tolerance, saturation_tolerance, "roll")
	if not bool(rolling.get("ok", false)): return rolling
	var torsion := _mode("torsion", torsion_speed, torsion_impulse, float(parsed["torsion"]), velocity_tolerance, saturation_tolerance, "spin")
	if not bool(torsion.get("ok", false)): return torsion
	return {"ok": true, "modes": {"tangent": tangent["mode"], "rolling": rolling["mode"], "torsion": torsion["mode"]}}

static func _mode(channel: String, speed: float, impulse: float, limit: float, velocity_tolerance: float, saturation_tolerance: float, moving_mode: String) -> Dictionary:
	if limit <= EPS:
		if impulse > saturation_tolerance:
			return {"ok": false, "code": "IMPULSE_EXCEEDS_ZERO_LIMIT", "channel": channel}
		return {"ok": true, "mode": "unconstrained" if speed > velocity_tolerance else "stick"}
	var saturated := impulse >= limit - saturation_tolerance * maxf(1.0, limit)
	if impulse > limit + saturation_tolerance * maxf(1.0, limit):
		return {"ok": false, "code": "IMPULSE_OUTSIDE_LIMIT", "channel": channel, "impulse": impulse, "limit": limit}
	if speed <= velocity_tolerance:
		return {"ok": true, "mode": "stick"}
	if not saturated:
		return {"ok": false, "code": "MODE_CONSTRAINT_UNRESOLVED", "channel": channel, "speed": speed, "impulse": impulse, "limit": limit}
	return {"ok": true, "mode": moving_mode}

static func _validate_common(observation: Dictionary, solved: Dictionary, time: float, options: Dictionary) -> Dictionary:
	if not is_finite(time) or time < 0.0:
		return {"ok": false, "code": "BAD_TIME"}
	if float(options.get("normal_support_tolerance", EPS)) < 0.0:
		return {"ok": false, "code": "BAD_NORMAL_SUPPORT_TOLERANCE"}
	if not solved.has("normal_support") or not _finite_number(solved["normal_support"]) or float(solved["normal_support"]) < 0.0:
		return {"ok": false, "code": "BAD_NORMAL_SUPPORT"}
	if not solved.has("generalized_impulse") or not solved.has("generalized_velocity_after") or not solved.has("limits"):
		return {"ok": false, "code": "INCOMPLETE_SOLVED_STATE"}
	if not observation.has("body_a") or not observation.has("body_b") or not observation.has("members"):
		return {"ok": false, "code": "INCOMPLETE_OBSERVATION"}
	return {"ok": true}

static func _identity(observation: Dictionary) -> Dictionary:
	var a := String(observation.get("body_a", ""))
	var b := String(observation.get("body_b", ""))
	if a.is_empty() or b.is_empty() or a == b:
		return {"ok": false, "code": "BAD_PAIR_IDENTITY"}
	var pair := a + "|" + b if a < b else b + "|" + a
	var members_raw = observation.get("members", [])
	if not (members_raw is Array) or Array(members_raw).is_empty():
		return {"ok": false, "code": "EMPTY_MANIFOLD_MEMBERS"}
	var members: Array = []
	for member_any in Array(members_raw):
		var member := String(member_any)
		if member.is_empty():
			return {"ok": false, "code": "EMPTY_MANIFOLD_MEMBER_ID"}
		members.append(member)
	members.sort()
	for i in range(1, members.size()):
		if members[i] == members[i - 1]:
			return {"ok": false, "code": "DUPLICATE_MANIFOLD_MEMBER_ID", "member": members[i]}
	var manifold_identity := pair + "::" + ",".join(members)
	return {"ok": true, "pair_id": pair, "member_ids": members, "manifold_identity": manifold_identity}

static func _limits(limits: Dictionary) -> Dictionary:
	for key in ["tangent", "rolling", "torsion"]:
		if not limits.has(key) or not _finite_number(limits[key]) or float(limits[key]) < 0.0:
			return {"ok": false, "code": "BAD_WRENCH_LIMIT", "channel": key}
	return {"ok": true, "tangent": float(limits["tangent"]), "rolling": float(limits["rolling"]), "torsion": float(limits["torsion"])}

static func _project_impulse(source: Array, limits: Dictionary) -> Array:
	if source.size() != 5:
		return _zero_impulse()
	var parsed := _limits(limits)
	if not bool(parsed.get("ok", false)):
		return _zero_impulse()
	var out := source.duplicate()
	var tangent := Vector2(float(out[0]), float(out[1]))
	var tangent_limit := float(parsed["tangent"])
	if tangent.length() > tangent_limit and tangent.length() > EPS:
		tangent *= tangent_limit / tangent.length()
	out[0] = tangent.x
	out[1] = tangent.y
	var rolling := Vector2(float(out[2]), float(out[3]))
	var rolling_limit := float(parsed["rolling"])
	if rolling.length() > rolling_limit and rolling.length() > EPS:
		rolling *= rolling_limit / rolling.length()
	out[2] = rolling.x
	out[3] = rolling.y
	out[4] = clampf(float(out[4]), -float(parsed["torsion"]), float(parsed["torsion"]))
	return out

static func _mode_transition_hypothesis(old_modes: Dictionary, new_modes: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for channel in ["tangent", "rolling", "torsion"]:
		var before := String(old_modes.get(channel, ""))
		var after := String(new_modes.get(channel, ""))
		if not before.is_empty() and before != after:
			out[channel] = before.to_upper() + "_TO_" + after.to_upper() + "_CANDIDATE"
	return out

static func _signature(pair_id: String, manifold_identity: String, epoch: int, time: float, solved: Dictionary, modes: Dictionary) -> String:
	return JSON.stringify({
		"pair": pair_id,
		"manifold": manifold_identity,
		"epoch": epoch,
		"time": time,
		"normal_support": solved["normal_support"],
		"accepted_generalized_impulse": solved["generalized_impulse"],
		"generalized_velocity_after": solved["generalized_velocity_after"],
		"limits": solved["limits"],
		"modes": modes,
	}, "", false)

static func _zero_impulse() -> Array:
	return [0.0, 0.0, 0.0, 0.0, 0.0]

static func _finite_number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))
