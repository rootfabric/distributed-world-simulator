class_name FabricConstruct0ToyboxRuntime
extends RefCounted

const AggregateScript = preload("res://scripts/construction/domain/construct_aggregate.gd")
const Fabric = preload("res://scripts/research/fabric0/fabric0_coupled_hybrid_dae_v1.gd")
const ContactCompiler = preload("res://scripts/research/fabric_bake0/contact_wrench_bake_compiler_v1.gd")
const StructuralLoadCase = preload("res://scripts/construction/structural/construction_structural_load_case.gd")
const StructuralCompiler = preload("res://scripts/construction/structural/construction_structural_compiler.gd")

const AUTHORITY_HASH := "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
const EPS := 1.0e-10

var _experiment: Dictionary = {}
var _initial_experiment: Dictionary = {}
var _aggregate
var _system: Dictionary = {}
var _time := 0.0
var _tool_force_n := 0.0
var _tool_torque_nm := 0.0
var _added_load_n := 0.0
var _events: Array = []
var _released := false
var _last_state: Dictionary = {}

func setup(experiment: Dictionary) -> Dictionary:
	_initial_experiment = experiment.duplicate(true)
	_experiment = experiment.duplicate(true)
	_aggregate = AggregateScript.new()
	var loaded := _aggregate.load_snapshot(_experiment["snapshot"])
	if not bool(loaded.get("success", false)):
		return loaded
	_time = 0.0
	_tool_force_n = 0.0
	_tool_torque_nm = 0.0
	_added_load_n = 0.0
	_events = []
	_released = false
	_system = {}
	var built := _build_runtime()
	if not bool(built.get("success", false)):
		return built
	_last_state = _compose_state()
	return {
		"success": true,
		"experiment_id": String(_experiment["experiment_id"]),
		"runtime_kind": String(_experiment["runtime_kind"]),
		"canonical_revision": int(_aggregate.state_revision),
		"state": _last_state.duplicate(true),
	}

func reset() -> Dictionary:
	if _initial_experiment.is_empty():
		return _failure("TOYBOX_RUNTIME_NOT_INITIALIZED")
	return setup(_initial_experiment)

func advance(delta: float) -> Dictionary:
	if not is_finite(delta) or delta <= 0.0:
		return _failure("TOYBOX_INVALID_DELTA")
	if String(_experiment["runtime_kind"]) == "STRUCTURAL_LOAD":
		_time += delta
		_last_state = _compose_state()
		return _success_state()
	if _system.is_empty():
		return _failure("TOYBOX_DAE_NOT_BUILT")
	var result := Fabric.advance(_system, delta)
	if not bool(result.get("ok", false)):
		return _failure("TOYBOX_DAE_ADVANCE_FAILED", {"fabric": result})
	_time = float(_system["time"])
	_after_dae_advance()
	_last_state = _compose_state()
	return _success_state()

func apply_tool(tool: String, magnitude: float = 1.0) -> Dictionary:
	if not bool(Dictionary(_experiment["controls"]).get(tool, false)):
		return _failure("TOYBOX_TOOL_NOT_AVAILABLE", {"tool": tool})
	if not is_finite(magnitude):
		return _failure("TOYBOX_TOOL_NONFINITE")
	match tool:
		"FORCE":
			_tool_force_n += magnitude
			return _rebuild_preserving_dynamic_state("FORCE")
		"IMPULSE":
			return _apply_impulse(magnitude)
		"TORQUE":
			_tool_torque_nm += magnitude
			return _rebuild_preserving_dynamic_state("TORQUE")
		"ADD_LOAD":
			if String(_experiment["runtime_kind"]) == "STRUCTURAL_LOAD":
				_added_load_n += magnitude
				var evaluated := _evaluate_bridge(true)
				if not bool(evaluated.get("success", false)):
					return evaluated
				_last_state = _compose_state()
				return _success_state()
			_added_load_n += magnitude
			return _rebuild_preserving_dynamic_state("ADD_LOAD")
		"BREAK_BOND":
			return _break_selected_bond()
		_:
			return _failure("TOYBOX_UNKNOWN_TOOL", {"tool": tool})

func state() -> Dictionary:
	return _last_state.duplicate(true)

func canonical_snapshot() -> Dictionary:
	if _aggregate == null:
		return {}
	return _aggregate.export_snapshot()

func state_hash() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(_canonical_state_payload(), "", false).to_utf8_buffer())
	return context.finish().hex_encode()

func _build_runtime() -> Dictionary:
	match String(_experiment["runtime_kind"]):
		"SLIDER_FRICTION":
			return _build_slider_friction()
		"HINGE_OSCILLATOR":
			return _build_hinge(false)
		"ROLLING_CART":
			return _build_cart()
		"HINGE_SPRING_RELEASE":
			return _build_catapult()
		"STRUCTURAL_LOAD":
			return _evaluate_bridge(false)
		_:
			return _failure("TOYBOX_RUNTIME_KIND_UNSUPPORTED")

func _build_slider_friction() -> Dictionary:
	var params: Dictionary = _experiment["runtime_params"]
	var environment: Dictionary = _experiment["environment"]["parameters"]
	var mass := float(params["mass_kg"])
	var angle := deg_to_rad(float(environment["angle_deg"]))
	var gravity := float(environment["gravity_m_s2"])
	var mu := float(environment["mu_tangent"])
	var normal_support := mass * gravity * cos(angle)
	var tangent_demand := mass * gravity * sin(angle) + _tool_force_n
	var b0 := _compile_ramp_contact(normal_support, mu, angle)
	if not bool(b0.get("success", false)):
		return b0
	var friction_capacity := float(b0["friction_capacity"])
	var acceleration := 0.0
	var contact_mode := "STICK"
	if absf(tangent_demand) > friction_capacity + EPS:
		var sign_value := 1.0 if tangent_demand >= 0.0 else -1.0
		acceleration = (tangent_demand - sign_value * friction_capacity) / mass
		contact_mode = "SLIDE"

	_system = Fabric.new_system()
	assert(Fabric.add_state(_system, "q", float(params["initial_position_m"]), Fabric.dim_length(), 1.0))
	assert(Fabric.add_state(_system, "qd", float(params["initial_velocity_m_s"]), Fabric.dim_velocity(), 1.0))
	assert(Fabric.add_parameter(_system, "accel", acceleration, Fabric.dim_acceleration()))
	var flows := {
		"q": Fabric.expr_state("qd"),
		"qd": Fabric.expr_parameter("accel"),
	}
	assert(Fabric.add_mode(_system, contact_mode.to_lower(), flows, []))
	assert(Fabric.set_initial_mode(_system, contact_mode.to_lower()))
	_experiment["_runtime_observables"] = {
		"contact_mode": contact_mode,
		"normal_support_n": normal_support,
		"tangent_demand_n": tangent_demand,
		"friction_capacity_n": friction_capacity,
		"b0_3_model_hash": String(b0["model_hash"]),
		"b0_3_generator_count": int(b0["generator_count"]),
	}
	return {"success": true}

func _build_hinge(preserve_state: bool) -> Dictionary:
	var params: Dictionary = _experiment["runtime_params"]
	var angle := float(params["initial_angle_rad"])
	var omega := float(params["initial_omega_rad_s"])
	if preserve_state and not _system.is_empty():
		angle = Fabric.read_state(_system, "q")
		omega = Fabric.read_state(_system, "qd")

	var inertia_dim := Fabric.dim_mul(Fabric.dim_mass(), Fabric.dim_pow(Fabric.dim_length(), 2))
	var omega_dim := Fabric.dim_div(Fabric.dim_dimensionless(), Fabric.dim_time())
	var angular_accel_dim := Fabric.dim_div(omega_dim, Fabric.dim_time())
	var damping_dim := Fabric.dim_mul(Fabric.dim_energy(), Fabric.dim_time())

	_system = Fabric.new_system()
	assert(Fabric.add_state(_system, "q", angle, Fabric.dim_dimensionless(), 1.0))
	assert(Fabric.add_state(_system, "qd", omega, omega_dim, 1.0))
	assert(Fabric.add_parameter(_system, "inertia", float(params["inertia_kg_m2"]), inertia_dim))
	assert(Fabric.add_parameter(_system, "tau", float(params.get("constant_torque_nm", 0.0)) + _tool_torque_nm, Fabric.dim_energy()))
	assert(Fabric.add_parameter(_system, "damping", float(params.get("damping_nm_s", 0.0)), damping_dim))
	assert(Fabric.add_parameter(_system, "spring", float(params.get("spring_nm_rad", 0.0)), Fabric.dim_energy()))
	assert(Fabric.add_parameter(_system, "rest_q", float(params.get("rest_angle_rad", 0.0)), Fabric.dim_dimensionless()))

	var torque := Fabric.expr_sub(
		Fabric.expr_sub(
			Fabric.expr_parameter("tau"),
			Fabric.expr_mul(Fabric.expr_parameter("damping"), Fabric.expr_state("qd"))
		),
		Fabric.expr_mul(
			Fabric.expr_parameter("spring"),
			Fabric.expr_sub(Fabric.expr_state("q"), Fabric.expr_parameter("rest_q"))
		)
	)
	var alpha := Fabric.expr_div(torque, Fabric.expr_parameter("inertia"))
	var flows := {
		"q": Fabric.expr_state("qd"),
		"qd": alpha,
	}
	assert(Fabric.dim_equal(angular_accel_dim, Fabric.dim_div(Fabric.dim_energy(), inertia_dim)))
	assert(Fabric.add_mode(_system, "free", flows, []))
	assert(Fabric.set_initial_mode(_system, "free"))
	return {"success": true}

func _build_cart() -> Dictionary:
	var params: Dictionary = _experiment["runtime_params"]
	var mass := float(params["mass_kg"]) + _added_load_n / 9.81
	var rolling := float(params["rolling_resistance"])
	var drive := float(params["force_n"]) + _tool_force_n
	var resistance := rolling * mass * 9.81
	var net_force := drive - resistance
	var accel := net_force / maxf(mass, EPS)

	_system = Fabric.new_system()
	assert(Fabric.add_state(_system, "q", float(params["initial_position_m"]), Fabric.dim_length(), 1.0))
	assert(Fabric.add_state(_system, "qd", float(params["initial_velocity_m_s"]), Fabric.dim_velocity(), 1.0))
	assert(Fabric.add_state(_system, "wheel_q", 0.0, Fabric.dim_dimensionless(), 1.0))
	assert(Fabric.add_parameter(_system, "accel", accel, Fabric.dim_acceleration()))
	var wheel_rate_dim := Fabric.dim_div(Fabric.dim_dimensionless(), Fabric.dim_time())
	assert(Fabric.add_parameter(_system, "inv_radius", 1.0 / float(params["wheel_radius_m"]), Fabric.dim_pow(Fabric.dim_length(), -1)))
	var flows := {
		"q": Fabric.expr_state("qd"),
		"qd": Fabric.expr_parameter("accel"),
		"wheel_q": Fabric.expr_mul(Fabric.expr_state("qd"), Fabric.expr_parameter("inv_radius")),
	}
	assert(Fabric.dim_equal(
		wheel_rate_dim,
		Fabric.dim_mul(Fabric.dim_velocity(), Fabric.dim_pow(Fabric.dim_length(), -1))
	))
	assert(Fabric.add_mode(_system, "rolling", flows, []))
	assert(Fabric.set_initial_mode(_system, "rolling"))
	_experiment["_runtime_observables"] = {
		"net_force_n": net_force,
		"rolling_resistance_n": resistance,
		"effective_mass_kg": mass,
	}
	return {"success": true}

func _build_catapult() -> Dictionary:
	var params: Dictionary = _experiment["runtime_params"]
	var inertia_dim := Fabric.dim_mul(Fabric.dim_mass(), Fabric.dim_pow(Fabric.dim_length(), 2))
	var omega_dim := Fabric.dim_div(Fabric.dim_dimensionless(), Fabric.dim_time())
	var damping_dim := Fabric.dim_mul(Fabric.dim_energy(), Fabric.dim_time())

	_system = Fabric.new_system()
	assert(Fabric.add_state(_system, "q", float(params["initial_angle_rad"]), Fabric.dim_dimensionless(), 1.0))
	assert(Fabric.add_state(_system, "qd", float(params["initial_omega_rad_s"]), omega_dim, 1.0))
	assert(Fabric.add_state(_system, "px", 0.0, Fabric.dim_length(), 1.0))
	assert(Fabric.add_state(_system, "py", 0.0, Fabric.dim_length(), 1.0))
	assert(Fabric.add_state(_system, "pvx", 0.0, Fabric.dim_velocity(), 1.0))
	assert(Fabric.add_state(_system, "pvy", 0.0, Fabric.dim_velocity(), 1.0))
	assert(Fabric.add_parameter(_system, "inertia", float(params["inertia_kg_m2"]), inertia_dim))
	assert(Fabric.add_parameter(_system, "tau", _tool_torque_nm, Fabric.dim_energy()))
	assert(Fabric.add_parameter(_system, "damping", float(params["damping_nm_s"]), damping_dim))
	assert(Fabric.add_parameter(_system, "spring", float(params["spring_nm_rad"]), Fabric.dim_energy()))
	assert(Fabric.add_parameter(_system, "rest_q", float(params["rest_angle_rad"]), Fabric.dim_dimensionless()))
	assert(Fabric.add_parameter(_system, "gravity", float(params["gravity_m_s2"]), Fabric.dim_acceleration()))
	assert(Fabric.add_parameter(_system, "arm_length", float(params["arm_length_m"]), Fabric.dim_length()))
	assert(Fabric.add_parameter(_system, "launch_scale", 0.72, Fabric.dim_dimensionless()))

	var torque := Fabric.expr_sub(
		Fabric.expr_sub(
			Fabric.expr_parameter("tau"),
			Fabric.expr_mul(Fabric.expr_parameter("damping"), Fabric.expr_state("qd"))
		),
		Fabric.expr_mul(
			Fabric.expr_parameter("spring"),
			Fabric.expr_sub(Fabric.expr_state("q"), Fabric.expr_parameter("rest_q"))
		)
	)
	var alpha := Fabric.expr_div(torque, Fabric.expr_parameter("inertia"))
	var latched_flows := {
		"q": Fabric.expr_state("qd"),
		"qd": alpha,
	}
	var released_flows := {
		"q": Fabric.expr_state("qd"),
		"qd": alpha,
		"px": Fabric.expr_state("pvx"),
		"py": Fabric.expr_state("pvy"),
		"pvy": Fabric.expr_neg(Fabric.expr_parameter("gravity")),
	}
	assert(Fabric.add_mode(_system, "latched", latched_flows, []))
	assert(Fabric.add_mode(_system, "released", released_flows, []))
	assert(Fabric.set_initial_mode(_system, "latched"))

	var launch_velocity := Fabric.expr_mul(
		Fabric.expr_mul(Fabric.expr_parameter("arm_length"), Fabric.expr_pre_state("qd")),
		Fabric.expr_parameter("launch_scale")
	)
	var jump_rows: Array = [
		Fabric.residual(Fabric.expr_post_state("px"), 1.0),
		Fabric.residual(Fabric.expr_post_state("py"), 1.0),
		Fabric.residual(Fabric.expr_sub(Fabric.expr_post_state("pvx"), launch_velocity), 1.0),
		Fabric.residual(Fabric.expr_sub(Fabric.expr_post_state("pvy"), launch_velocity), 1.0),
	]
	assert(Fabric.add_transition(_system, {
		"id": "release_breakable_payload",
		"from_modes": ["latched"],
		"to_mode": "released",
		"guard": {
			"expr": Fabric.expr_sub(
				Fabric.expr_state("q"),
				Fabric.expr_constant(float(params["release_angle_rad"]), Fabric.dim_dimensionless())
			),
			"nominal": 1.0,
			"direction": 1,
			"kind": "crossing",
		},
		"jump": {
			"post_states": ["px", "py", "pvx", "pvy"],
			"unknowns": {},
			"branches": [Fabric.jump_branch("release", jump_rows, [], 0)],
		},
		"topology_ops": [],
		"priority": 0,
	}))
	return {"success": true}

func _compile_ramp_contact(normal_support: float, mu: float, angle: float) -> Dictionary:
	var tangent := Vector3(cos(angle), -sin(angle), 0.0).normalized()
	var normal := Vector3(sin(angle), cos(angle), 0.0).normalized()
	var t2 := Vector3(0.0, 0.0, 1.0)
	var points: Array = []
	for iz in range(5):
		for ix in range(5):
			var u := lerpf(-0.35, 0.35, float(ix) / 4.0)
			var v := lerpf(-0.35, 0.35, float(iz) / 4.0)
			points.append({
				"id": "ramp/%02d/%02d" % [iz, ix],
				"position": tangent * u + t2 * v,
			})
	var snapshot := _aggregate.export_snapshot()
	var request := {
		"model_id": "artifact/construct0/play1/ramp",
		"patch_id": "patch/construct0/play1/ramp",
		"source_frontier_hash": String(snapshot["checksum"]),
		"physical_graph_hash": _hash({"snapshot": snapshot["checksum"], "kind": "ramp"}),
		"parent_artifact_checksum": _hash({"parent": snapshot["checksum"]}),
		"authority_checksum": AUTHORITY_HASH,
		"origin": Vector3.ZERO,
		"normal": normal,
		"t1": tangent,
		"t2": t2,
		"points": points,
		"normal_support_limit": normal_support,
		"mu_tangent": mu,
		"mu_rolling": 0.02,
		"mu_torsion": 0.02,
		"effective_radius": 0.35,
		"minimum_reduction_ratio": 2.0,
	}
	var baked := ContactCompiler.compile(request)
	if not bool(baked.get("ok", false)):
		return _failure("TOYBOX_RAMP_B0_3_FAILED", {"b0_3": baked})
	var model: Dictionary = baked["model"]
	return {
		"success": true,
		"model_hash": String(model["model_hash"]),
		"generator_count": int(model["generator_count"]),
		"friction_capacity": mu * normal_support,
	}

func _evaluate_bridge(allow_break: bool) -> Dictionary:
	var params: Dictionary = _experiment["runtime_params"]
	var snapshot := _aggregate.export_snapshot()
	var external := {
		String(params["load_part_id"]): float(params["initial_external_load_n"]) + _added_load_n,
	}
	var load_case := StructuralLoadCase.create(
		"load-case/construct0/toybox/breakable-bridge",
		String(snapshot["construct_id"]),
		String(snapshot["checksum"]),
		9.81,
		Array(params["support_part_ids"]).duplicate(true),
		external,
		float(params["safety_factor"]),
		float(params["degraded_capacity_factor"])
	)
	var compiled := StructuralCompiler.compile(snapshot, load_case)
	if not bool(compiled.get("success", false)):
		return compiled
	var profile: Dictionary = compiled["profile"]
	var max_utilization := 0.0
	var max_bond_id := ""
	var overloaded_bond_id := ""
	for state_any in profile["bond_states"]:
		var state: Dictionary = state_any
		var utilization := float(state["utilization"])
		if utilization > max_utilization:
			max_utilization = utilization
			max_bond_id = String(state["bond_id"])
		if String(state["state"]) == "OVERLOADED" and overloaded_bond_id.is_empty():
			overloaded_bond_id = String(state["bond_id"])
	if allow_break and not overloaded_bond_id.is_empty():
		var before_revision := _aggregate.state_revision
		var broken := _aggregate.break_bond(
			"toybox/bridge/auto-break/%06d" % before_revision,
			before_revision,
			overloaded_bond_id
		)
		if not bool(broken.get("success", false)):
			return broken
		_events.append({
			"time": _time,
			"event": "BREAKABLE_BOND_FAILED",
			"bond_id": overloaded_bond_id,
			"revision": _aggregate.state_revision,
		})
		snapshot = _aggregate.export_snapshot()
		load_case = StructuralLoadCase.create(
			"load-case/construct0/toybox/breakable-bridge-after-break",
			String(snapshot["construct_id"]),
			String(snapshot["checksum"]),
			9.81,
			Array(params["support_part_ids"]).duplicate(true),
			external,
			float(params["safety_factor"]),
			float(params["degraded_capacity_factor"])
		)
		compiled = StructuralCompiler.compile(snapshot, load_case)
		if not bool(compiled.get("success", false)):
			return compiled
		profile = compiled["profile"]
	_experiment["_runtime_observables"] = {
		"structural_state": String(profile["structural_state"]),
		"external_load_n": float(external[String(params["load_part_id"])]),
		"max_bond_utilization": max_utilization,
		"max_bond_id": max_bond_id,
		"intact_bonds": _intact_bond_count(snapshot),
	}
	return {"success": true}

func _after_dae_advance() -> void:
	var kind := String(_experiment["runtime_kind"])
	if kind == "HINGE_OSCILLATOR":
		var params: Dictionary = _experiment["runtime_params"]
		var q := Fabric.read_state(_system, "q")
		var qd := Fabric.read_state(_system, "qd")
		var min_q := float(params["min_angle_rad"])
		var max_q := float(params["max_angle_rad"])
		if q < min_q or q > max_q:
			q = clampf(q, min_q, max_q)
			_system["states"]["q"]["value"] = q
			_system["states"]["qd"]["value"] = -0.25 * qd
			_events.append({"time": _time, "event": "HINGE_LIMIT"})
	if kind == "HINGE_SPRING_RELEASE" and not _released and Fabric.read_mode(_system) == "released":
		_released = true
		var latch_id := String(_experiment["runtime_params"]["latch_bond_id"])
		var broken := _aggregate.break_bond(
			"toybox/catapult/release/%06d" % _aggregate.state_revision,
			_aggregate.state_revision,
			latch_id
		)
		if bool(broken.get("success", false)):
			_events.append({
				"time": _time,
				"event": "BREAKABLE_LATCH_RELEASED",
				"bond_id": latch_id,
				"revision": _aggregate.state_revision,
			})

func _apply_impulse(impulse: float) -> Dictionary:
	if _system.is_empty():
		return _failure("TOYBOX_IMPULSE_NO_DYNAMIC_SYSTEM")
	var kind := String(_experiment["runtime_kind"])
	match kind:
		"SLIDER_FRICTION", "ROLLING_CART":
			var mass := float(_experiment["runtime_params"]["mass_kg"]) + _added_load_n / 9.81
			_system["states"]["qd"]["value"] = Fabric.read_state(_system, "qd") + impulse / maxf(mass, EPS)
		"HINGE_OSCILLATOR", "HINGE_SPRING_RELEASE":
			var inertia := float(_experiment["runtime_params"]["inertia_kg_m2"])
			_system["states"]["qd"]["value"] = Fabric.read_state(_system, "qd") + impulse / maxf(inertia, EPS)
		_:
			return _failure("TOYBOX_IMPULSE_UNSUPPORTED")
	_events.append({"time": _time, "event": "IMPULSE", "magnitude": impulse})
	_last_state = _compose_state()
	return _success_state()

func _rebuild_preserving_dynamic_state(reason: String) -> Dictionary:
	if String(_experiment["runtime_kind"]) == "HINGE_OSCILLATOR":
		var q := Fabric.read_state(_system, "q") if not _system.is_empty() else float(_experiment["runtime_params"]["initial_angle_rad"])
		var qd := Fabric.read_state(_system, "qd") if not _system.is_empty() else float(_experiment["runtime_params"]["initial_omega_rad_s"])
		_experiment["runtime_params"]["initial_angle_rad"] = q
		_experiment["runtime_params"]["initial_omega_rad_s"] = qd
	elif String(_experiment["runtime_kind"]) in ["SLIDER_FRICTION", "ROLLING_CART"]:
		if not _system.is_empty():
			_experiment["runtime_params"]["initial_position_m"] = Fabric.read_state(_system, "q")
			_experiment["runtime_params"]["initial_velocity_m_s"] = Fabric.read_state(_system, "qd")
	var built := _build_runtime()
	if not bool(built.get("success", false)):
		return built
	_events.append({"time": _time, "event": "%s_CHANGED" % reason})
	_last_state = _compose_state()
	return _success_state()

func _break_selected_bond() -> Dictionary:
	var snapshot := _aggregate.export_snapshot()
	for bond_any in snapshot["bonds"]:
		var bond: Dictionary = bond_any
		if String(bond["state"]) == "BROKEN":
			continue
		if String(bond["bond_kind"]) != "BREAKABLE":
			continue
		var result := _aggregate.break_bond(
			"toybox/debug-break/%06d" % _aggregate.state_revision,
			_aggregate.state_revision,
			String(bond["bond_id"])
		)
		if not bool(result.get("success", false)):
			return result
		_events.append({
			"time": _time,
			"event": "BREAK_BOND_TOOL",
			"bond_id": String(bond["bond_id"]),
			"revision": _aggregate.state_revision,
		})
		_last_state = _compose_state()
		return _success_state()
	return _failure("TOYBOX_NO_BREAKABLE_BOND")

func _compose_state() -> Dictionary:
	var kind := String(_experiment.get("runtime_kind", ""))
	var overrides := {}
	var metrics := Dictionary(_experiment.get("_runtime_observables", {})).duplicate(true)
	if kind == "SLIDER_FRICTION" and not _system.is_empty():
		var params: Dictionary = _experiment["runtime_params"]
		var environment: Dictionary = _experiment["environment"]["parameters"]
		var q := Fabric.read_state(_system, "q")
		var angle := deg_to_rad(float(environment["angle_deg"]))
		var base := _base_position(String(params["moving_part_id"]))
		overrides[String(params["moving_part_id"])] = {
			"position": base + Vector3(cos(angle), -sin(angle), 0.0) * q,
			"rotation": Quaternion(Vector3.BACK, angle),
		}
		metrics["coordinate_m"] = q
		metrics["velocity_m_s"] = Fabric.read_state(_system, "qd")
	elif kind == "HINGE_OSCILLATOR" and not _system.is_empty():
		var params: Dictionary = _experiment["runtime_params"]
		var q := Fabric.read_state(_system, "q")
		_hinge_overrides(overrides, params, q)
		metrics["angle_rad"] = q
		metrics["omega_rad_s"] = Fabric.read_state(_system, "qd")
	elif kind == "ROLLING_CART" and not _system.is_empty():
		var params: Dictionary = _experiment["runtime_params"]
		var q := Fabric.read_state(_system, "q")
		var wheel_q := Fabric.read_state(_system, "wheel_q")
		var moving_ids: Array = [String(params["moving_part_id"])]
		moving_ids.append_array(Array(params.get("dependent_part_ids", [])))
		moving_ids.append_array(Array(params.get("wheel_part_ids", [])))
		for raw_id in moving_ids:
			var part_id := String(raw_id)
			overrides[part_id] = {"position": _base_position(part_id) + Vector3(q, 0.0, 0.0)}
		for raw_id in params["wheel_part_ids"]:
			var wheel_id := String(raw_id)
			overrides[wheel_id]["rotation"] = Quaternion(Vector3.BACK, wheel_q)
		metrics["coordinate_m"] = q
		metrics["velocity_m_s"] = Fabric.read_state(_system, "qd")
		metrics["wheel_angle_rad"] = wheel_q
	elif kind == "HINGE_SPRING_RELEASE" and not _system.is_empty():
		var params: Dictionary = _experiment["runtime_params"]
		var q := Fabric.read_state(_system, "q")
		_hinge_overrides(overrides, params, q)
		var payload_id := String(params["payload_part_id"])
		if _released:
			var pivot := _vec3(params["pivot"])
			overrides[payload_id] = {
				"position": pivot + Vector3(
					Fabric.read_state(_system, "px"),
					Fabric.read_state(_system, "py"),
					0.0
				),
			}
		else:
			var pivot := _vec3(params["pivot"])
			var arm_length := float(params["arm_length_m"])
			overrides[payload_id] = {
				"position": pivot + Vector3(cos(q), sin(q), 0.0) * arm_length,
			}
		metrics["angle_rad"] = q
		metrics["omega_rad_s"] = Fabric.read_state(_system, "qd")
		metrics["released"] = _released
		metrics["mode"] = Fabric.read_mode(_system)
	elif kind == "STRUCTURAL_LOAD":
		metrics.merge(Dictionary(_experiment.get("_runtime_observables", {})), true)

	return {
		"time": _time,
		"experiment_id": String(_experiment.get("experiment_id", "")),
		"runtime_kind": kind,
		"part_overrides": overrides,
		"metrics": metrics,
		"events": _events.duplicate(true),
		"canonical_revision": int(_aggregate.state_revision) if _aggregate != null else -1,
		"canonical_checksum": String(_aggregate.export_snapshot()["checksum"]) if _aggregate != null else "",
		"fabric_state_hash": Fabric.state_hash(_system) if not _system.is_empty() else "",
	}

func _hinge_overrides(overrides: Dictionary, params: Dictionary, q: float) -> void:
	var pivot := _vec3(params["pivot"])
	var axis := _vec3(params["axis"]).normalized()
	var rotation := Quaternion(axis, q)
	var moving_id := String(params["moving_part_id"])
	var moving_base := _base_position(moving_id)
	overrides[moving_id] = {
		"position": pivot + rotation * (moving_base - pivot),
		"rotation": rotation,
	}
	for raw_id in params.get("dependent_part_ids", []):
		var part_id := String(raw_id)
		var base := _base_position(part_id)
		overrides[part_id] = {
			"position": pivot + rotation * (base - pivot),
			"rotation": rotation,
		}

func _base_position(part_id: String) -> Vector3:
	var snapshot: Dictionary = _initial_experiment["snapshot"]
	for part_any in snapshot["parts"]:
		var part: Dictionary = part_any
		if String(part["part_id"]) == part_id:
			return _vec3(part["local_position_m"])
	return Vector3.ZERO

func _intact_bond_count(snapshot: Dictionary) -> int:
	var count := 0
	for bond_any in snapshot["bonds"]:
		if String(Dictionary(bond_any)["state"]) != "BROKEN":
			count += 1
	return count

func _canonical_state_payload() -> Dictionary:
	var state_value := _compose_state()
	return {
		"experiment_id": state_value["experiment_id"],
		"time": state_value["time"],
		"metrics": state_value["metrics"],
		"events": state_value["events"],
		"canonical_revision": state_value["canonical_revision"],
		"canonical_checksum": state_value["canonical_checksum"],
		"fabric_state_hash": state_value["fabric_state_hash"],
	}

func _vec3(value) -> Vector3:
	if value is Vector3:
		return value
	var a: Array = value
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _hash(value) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(value, "", false).to_utf8_buffer())
	return context.finish().hex_encode()

func _success_state() -> Dictionary:
	return {"success": true, "state": _last_state.duplicate(true)}

func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
