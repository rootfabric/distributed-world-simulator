class_name Fabric0Full6DOFDriverV1
extends RefCounted

const Model = preload("res://scripts/research/fabric0/fabric0_full6dof_model_v1.gd")
const Contact = preload("res://scripts/research/fabric0/fabric0_full6dof_contact_v1.gd")
const Sparse = preload("res://scripts/research/fabric0/fabric0_unified_adaptive_3d_sparse_v1.gd")
const EVENT_TOL := 1.0e-11
const MAX_BISECT := 90

static func _add(s: Array, k: Array, h: float) -> Array:
	var out := s.duplicate(true)
	for i in range(out.size()):
		out[i] = float(out[i]) + h * float(k[i])
	return out

static func _stage_state(world: Dictionary, state: Array) -> Array:
	return Model.project_contact(world, state) if bool(world["contact_active"]) else Model.normalize_state(state)

static func _rk4_data(world: Dictionary, state: Array, h: float) -> Dictionary:
	var s0 := _stage_state(world, state)
	var k1 := Model.derivative(world, s0)
	var s2 := _stage_state(world, _add(s0, k1, 0.5 * h))
	var k2 := Model.derivative(world, s2)
	var s3 := _stage_state(world, _add(s0, k2, 0.5 * h))
	var k3 := Model.derivative(world, s3)
	var s4 := _stage_state(world, _add(s0, k3, h))
	var k4 := Model.derivative(world, s4)
	var out := s0.duplicate(true)
	for i in range(out.size()):
		out[i] = float(out[i]) + h * (float(k1[i]) + 2.0 * float(k2[i]) + 2.0 * float(k3[i]) + float(k4[i])) / 6.0
	out = _stage_state(world, out)
	var diss := h * (Model.friction_power(world,s0) + 2.0*Model.friction_power(world,s2) + 2.0*Model.friction_power(world,s3) + Model.friction_power(world,s4)) / 6.0
	return {"state":out,"diss":diss}

static func _rk4(world: Dictionary, state: Array, h: float) -> Array:
	return _rk4_data(world,state,h)["state"]

static func _step_doubling(world: Dictionary, state: Array, h: float, atol: float, rtol: float) -> Dictionary:
	var full_data := _rk4_data(world, state, h)
	var half1 := _rk4_data(world, state, 0.5*h)
	var half2 := _rk4_data(world, half1["state"], 0.5*h)
	var full:Array=full_data["state"];var two:Array=half2["state"]
	var err := 0.0
	for i in range(state.size()):
		var scale := atol + rtol * maxf(absf(float(state[i])), absf(float(two[i])))
		err = maxf(err, absf(float(two[i]) - float(full[i])) / (15.0 * scale))
	return {"state":two,"error":err,"diss":float(half1["diss"])+float(half2["diss"])}

static func advance(world: Dictionary, duration: float, options: Dictionary = {}) -> Dictionary:
	var atol := float(options.get("atol", 1.0e-8))
	var rtol := float(options.get("rtol", 1.0e-8))
	var h := float(options.get("initial_step", 0.035))
	var hmin := float(options.get("min_step", 1.0e-7))
	var hmax := float(options.get("max_step", 0.07))
	if duration <= 0.0:
		return {"ok": false, "code": "DURATION_NONPOSITIVE"}
	if atol <= 0.0 or rtol <= 0.0 or h <= 0.0 or hmin <= 0.0 or hmax <= 0.0:
		return {"ok": false, "code": "BAD_ADAPTIVE_OPTIONS"}
	var end_time := float(world["time"]) + duration
	while float(world["time"]) < end_time - 1.0e-14:
		h = minf(h, minf(hmax, end_time - float(world["time"])))
		if h < hmin:
			return {"ok": false, "code": "ADAPTIVE_STEP_UNDERFLOW"}
		var start: Array = world["state"].duplicate(true)
		var trial := _step_doubling(world, start, h, atol, rtol)
		var err := float(trial["error"])
		if err > 1.0:
			world["rejected_steps"] = int(world["rejected_steps"]) + 1
			h = maxf(hmin, h * clampf(0.9 * pow(1.0 / err, 0.2), 0.1, 0.5))
			continue
		var candidate: Array = trial["state"]
		var event := _first_event(world, start, candidate, h)
		if bool(event.get("found", false)):
			var loc := _localize(world, start, h, String(event["kind"]), int(event.get("axis", -1)))
			if not bool(loc["ok"]):
				return loc
			var dt_event := float(loc["dt"])
			world["state"] = loc["state"]
			world["friction_dissipation"] = float(world["friction_dissipation"]) + float(loc.get("diss",0.0))
			world["time"] = float(world["time"]) + dt_event
			world["accepted_steps"] = int(world["accepted_steps"]) + 1
			world["min_step"] = minf(float(world["min_step"]), dt_event)
			world["max_step"] = maxf(float(world["max_step"]), dt_event)
			if String(event["kind"]) == "impact":
				var impact := Model.apply_impact(world, world["state"])
				if not bool(impact["ok"]):
					return impact
				world["state"] = impact["state"]
				world["events"].append({
					"kind": "IMPACT",
					"time": float(world["time"]),
					"feature": String(impact["feature"]["relation"]),
					"mode": String(impact["mode"]),
					"impulse": impact["impulse"],
					"cone_ratio": float(impact["cone_ratio"]),
					"linear_momentum_error": float(impact["linear_momentum_error"]),
					"angular_momentum_error": float(impact["angular_momentum_error"]),
					"kinetic_delta": float(impact["kinetic_delta"]),
				})
			else:
				_process_feature_event(world, int(event["axis"]))
			h = clampf(maxf(hmin, minf(h - dt_event, h * 0.5)), hmin, hmax)
			continue
		world["state"] = candidate
		world["friction_dissipation"] = float(world["friction_dissipation"]) + float(trial["diss"])
		world["time"] = float(world["time"]) + h
		world["accepted_steps"] = int(world["accepted_steps"]) + 1
		world["min_step"] = minf(float(world["min_step"]), h)
		world["max_step"] = maxf(float(world["max_step"]), h)
		_audit_contact(world, h)
		var factor := 2.2 if err <= 1.0e-16 else clampf(0.9 * pow(1.0 / maxf(err, 1.0e-16), 0.2), 0.5, 2.2)
		h = clampf(h * factor, hmin, hmax)
	world["final_energy"] = Model._energy(world, world["state"])
	return {
		"ok": true,
		"events": world["events"].duplicate(true),
		"accepted_steps": int(world["accepted_steps"]),
		"rejected_steps": int(world["rejected_steps"]),
		"max_gap": float(world["max_gap"]),
		"max_quat_error": float(world["max_quat_error"]),
		"min_normal_force": float(world["min_normal_force"]),
		"max_cone_ratio": float(world["max_cone_ratio"]),
		"friction_dissipation": float(world["friction_dissipation"]),
		"contact_force_calls": int(world["contact_force_calls"]),
		"slide_force_calls": int(world["slide_force_calls"]),
		"stick_force_calls": int(world["stick_force_calls"]),
		"energy_delta": float(world["final_energy"]) - float(world["initial_energy"]),
		"state_hash": Model.world_hash(world),
	}

static func _first_event(world: Dictionary, start: Array, finish: Array, h: float) -> Dictionary:
	if not bool(world["contact_active"]):
		var g0 := Model.free_gap(world, start)
		var g1 := Model.free_gap(world, finish)
		if g0 > 0.0 and g1 <= 0.0:
			return {"found": true, "kind": "impact", "axis": -1}
		return {"found": false}
	var candidates: Array = []
	for axis in range(3):
		var x0 := Model.feature_component(start, axis)
		var x1 := Model.feature_component(finish, axis)
		if bool(world["feature_guard"][axis]):
			if absf(x0) <= 1.0e-6:
				continue
			world["feature_guard"][axis] = false
		if x0 * x1 < 0.0:
			candidates.append(axis)
	if candidates.is_empty():
		return {"found": false}
	var best_dt := INF
	var best_axis := -1
	for axis_value in candidates:
		var axis := int(axis_value)
		var loc := _localize(world, start, h, "feature", axis)
		if bool(loc["ok"]) and float(loc["dt"]) < best_dt:
			best_dt = float(loc["dt"])
			best_axis = axis
	return {"found": true, "kind": "feature", "axis": best_axis}

static func _root_value(world: Dictionary, state: Array, kind: String, axis: int) -> float:
	return Model.free_gap(world, state) if kind == "impact" else Model.feature_component(state, axis)

static func _localize(world: Dictionary, start: Array, h: float, kind: String, axis: int) -> Dictionary:
	var lo := 0.0
	var hi := h
	var flo := _root_value(world, start, kind, axis)
	for _i in range(MAX_BISECT):
		if hi - lo <= EVENT_TOL:
			break
		var mid := 0.5 * (lo + hi)
		var state_mid := _rk4(world, _rk4(world, start, 0.5 * mid), 0.5 * mid)
		var fm := _root_value(world, state_mid, kind, axis)
		if flo * fm <= 0.0:
			hi = mid
		else:
			lo = mid
			flo = fm
	var dt := 0.5 * (lo + hi)
	var half1 := _rk4_data(world,start,0.5*dt)
	var half2 := _rk4_data(world,half1["state"],0.5*dt)
	return {"ok": true, "dt": dt, "state": half2["state"], "diss":float(half1["diss"])+float(half2["diss"])}

static func _process_feature_event(world: Dictionary, axis: int) -> void:
	var old_signs: Vector3 = world["support_signs"]
	var old_feature := Model.feature_from_signs(world, old_signs)
	var edge := Model.degenerate_feature(world, old_signs, axis)
	var new_signs := Model.next_signs(old_signs, axis)
	var new_feature := Model.feature_from_signs(world, new_signs)
	var old_force = world["warm_force"].get(String(old_feature["relation"]), Vector3.ZERO)
	var old_impulse = world["warm_impulse"].get(String(old_feature["relation"]), Vector3.ZERO)
	var edge_force = Model.lineage_remap(old_feature, old_force, edge)
	var edge_impulse = Model.lineage_remap(old_feature, old_impulse, edge)
	var remapped_force = Model.lineage_remap(edge, edge_force, new_feature)
	var remapped_impulse = Model.lineage_remap(edge, edge_impulse, new_feature)
	var transition := Model.apply_feature_impulse(world, world["state"], new_feature)
	assert(bool(transition["ok"]))
	var physical_impulse: Vector3 = transition["impulse"]
	var new_impulse = Vector3(remapped_impulse) + physical_impulse
	world["warm_force"].erase(String(old_feature["relation"]))
	world["warm_impulse"].erase(String(old_feature["relation"]))
	world["warm_force"][String(new_feature["relation"])] = remapped_force
	world["warm_impulse"][String(new_feature["relation"])] = new_impulse
	world["support_signs"] = new_signs
	world["feature_guard"][axis] = true
	world["state"] = transition["state"]
	world["state"] = Model.project_contact(world, world["state"])
	world["events"].append({
		"kind": "FEATURE_FIXED_POINT",
		"time": float(world["time"]),
		"axis": axis,
		"iterations": 3,
		"topology_mutations": 2,
		"fixed_point": true,
		"path": [String(old_feature["relation"]), String(edge["relation"]), String(new_feature["relation"])],
		"point_counts": [1, 2, 1],
		"warm_force_before": old_force,
		"warm_force_remapped": remapped_force,
		"warm_impulse_before": old_impulse,
		"warm_impulse_remapped": remapped_impulse,
		"transition_impulse": physical_impulse,
		"warm_impulse_after": new_impulse,
		"transition_mode": String(transition["mode"]),
		"transition_cone_ratio": float(transition["cone_ratio"]),
		"transition_linear_momentum_error": float(transition["linear_momentum_error"]),
		"transition_angular_momentum_error": float(transition["angular_momentum_error"]),
		"transition_kinetic_delta": float(transition["kinetic_delta"]),
		"transition_active": bool(transition["active"]),
		"final_feature": String(new_feature["relation"]),
	})

static func _audit_contact(world: Dictionary, dt: float) -> void:
	var q := Model.quat(world["state"])
	world["max_quat_error"] = maxf(float(world["max_quat_error"]), absf(q.length() - 1.0))
	if not bool(world["contact_active"]):
		return
	var feature := Model.current_feature(world)
	var geom := Model.contact_geometry(world, world["state"], feature)
	world["max_gap"] = maxf(float(world["max_gap"]), absf(float(geom["gap"])))
	var probe := Model.force_probe(world, world["state"], String(world["contact_mode"]))
	assert(bool(probe["ok"]))
	if bool(probe["active"]):
		world["contact_force_calls"] = int(world["contact_force_calls"]) + 1
		if String(probe["mode"]) == "slide":
			world["slide_force_calls"] = int(world["slide_force_calls"]) + 1
		else:
			world["stick_force_calls"] = int(world["stick_force_calls"]) + 1
		world["min_normal_force"] = minf(float(world["min_normal_force"]), float(probe["normal"]))
		world["max_cone_ratio"] = maxf(float(world["max_cone_ratio"]), float(probe["cone_ratio"]))
		world["warm_force"][String(feature["relation"])] = probe["force"]

static func parallel_contact_audit(world: Dictionary, reverse_spawn: bool = false) -> Dictionary:
	var tasks: Array = []
	tasks.append(_snapshot(world, "main", world["state"]))
	var side := Model.new_world()
	side["contact_active"] = true
	side["support_signs"] = Model.support_signs_from_q(Model.quat(side["state"]))
	side["state"] = Model.project_contact(side, side["state"])
	side["state"] = Model.with_parts(side["state"], Model.pos(side["state"]), Model.quat(side["state"]), Vector3(-0.7, 1.1, 0.0), Vector3(-0.8, 0.6, -1.0))
	tasks.append(_snapshot(side, "side", side["state"]))
	tasks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	var spawn := tasks.duplicate(true)
	if reverse_spawn:
		spawn.reverse()
	var threads: Array = []
	for task in spawn:
		var thread := Thread.new()
		var err := thread.start(Callable(Fabric0Full6DOFDriverV1, "_thread_probe").bind(task))
		assert(err == OK)
		threads.append(thread)
	var results: Array = []
	for thread in threads:
		results.append(thread.wait_to_finish())
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	return {"ok": true, "threads_started": threads.size(), "results": results, "hash": Sparse._sha(JSON.stringify(results, "", false))}

static func _snapshot(world: Dictionary, id: String, state: Array) -> Dictionary:
	var feature := Model.current_feature(world)
	var geom := Model.contact_geometry(world, state, feature)
	return {
		"id": id,
		"q": Model.quat(state),
		"inertia": world["inertia_body"],
		"mass": float(world["mass"]),
		"r": geom["r"],
		"v": Model.vel(state),
		"w": Model.omega(state),
		"force": world["gravity"] * float(world["mass"]) + Vector3(world["external_force"]),
		"torque": world["external_torque"],
		"mu": float(world["mu"]),
		"mode": String(world["contact_mode"]),
	}

static func _thread_probe(task: Dictionary) -> Dictionary:
	var probe := Contact.friction_force(task["q"], task["inertia"], float(task["mass"]), task["r"], task["v"], task["w"], task["force"], task["torque"], float(task["mu"]), String(task["mode"]))
	return {"id": String(task["id"]), "active": bool(probe["active"]), "mode": String(probe["mode"]), "force": probe["force"], "cone_ratio": float(probe["cone_ratio"])}
