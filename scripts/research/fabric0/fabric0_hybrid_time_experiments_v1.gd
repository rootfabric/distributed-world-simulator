class_name Fabric0HybridTimeExperimentsV1
extends RefCounted

const TimeFabric = preload("res://scripts/research/fabric0/fabric0_hybrid_time_v1.gd")
const Physical = preload("res://scripts/research/fabric0/fabric0_nonsmooth_fabric_v1.gd")

static func build_bouncing_ball() -> Dictionary:
	var t := TimeFabric.new_timeline()
	assert(TimeFabric.add_state(t, "h", 1.0, TimeFabric.dim_length(), 1.0))
	assert(TimeFabric.add_state(t, "v", -1.0, TimeFabric.dim_velocity(), 1.0))
	assert(TimeFabric.add_parameter(t, "g", 9.81, TimeFabric.dim_acceleration()))
	assert(TimeFabric.add_parameter(t, "e", 0.8, TimeFabric.dim_dimensionless()))
	assert(TimeFabric.add_mode(t, "flight", {
		"h": TimeFabric.expr_state("v"),
		"v": TimeFabric.expr_neg(TimeFabric.expr_parameter("g")),
	}))
	assert(TimeFabric.set_initial_mode(t, "flight"))
	assert(TimeFabric.add_transition(t, {
		"id": "impact",
		"from_modes": ["flight"],
		"to_mode": "flight",
		"guard": {"expr": TimeFabric.expr_state("h"), "nominal": 1.0, "direction": -1},
		"resets": {
			"h": TimeFabric.expr_constant(0.0, TimeFabric.dim_length()),
			"v": TimeFabric.expr_mul(
				TimeFabric.expr_neg(TimeFabric.expr_parameter("e")),
				TimeFabric.expr_state("v")
			),
		},
		"topology_ops": [],
		"priority": 0,
	}))
	return t

static func build_schmitt() -> Dictionary:
	var t := TimeFabric.new_timeline()
	assert(TimeFabric.add_state(t, "x", 0.0, TimeFabric.dim_dimensionless(), 1.0))
	assert(TimeFabric.add_parameter(t, "rate", 1.0, TimeFabric.dim_div(TimeFabric.dim_dimensionless(), TimeFabric.dim_time())))
	assert(TimeFabric.add_parameter(t, "upper", 1.0, TimeFabric.dim_dimensionless()))
	assert(TimeFabric.add_parameter(t, "lower", 0.2, TimeFabric.dim_dimensionless()))
	assert(TimeFabric.add_mode(t, "off", {"x": TimeFabric.expr_parameter("rate")}))
	assert(TimeFabric.add_mode(t, "on", {"x": TimeFabric.expr_parameter("rate")}))
	assert(TimeFabric.set_initial_mode(t, "off"))
	assert(TimeFabric.add_transition(t, {
		"id": "switch_on",
		"from_modes": ["off"],
		"to_mode": "on",
		"guard": {"expr": TimeFabric.expr_sub(TimeFabric.expr_state("x"), TimeFabric.expr_parameter("upper")), "nominal": 1.0, "direction": 1},
		"resets": {}, "topology_ops": [], "priority": 0,
	}))
	assert(TimeFabric.add_transition(t, {
		"id": "switch_off",
		"from_modes": ["on"],
		"to_mode": "off",
		"guard": {"expr": TimeFabric.expr_sub(TimeFabric.expr_state("x"), TimeFabric.expr_parameter("lower")), "nominal": 1.0, "direction": -1},
		"resets": {}, "topology_ops": [], "priority": 0,
	}))
	return t

static func build_simple_physical_network() -> Dictionary:
	var net := Physical.new_network()
	assert(Physical.register_domain(net, "electrical", "voltage", "current", Physical.dim_voltage(), Physical.dim_current(), "V", "A"))
	assert(Physical.add_element(net, Physical.equilibrium_terminal("source", "electrical", 5.0, 1.0)))
	assert(Physical.add_element(net, Physical.equilibrium_terminal("load", "electrical", 0.0, 1.0)))
	assert(Physical.link_ports(net, "fuse_link", "source", "p", "load", "p"))
	return net

static func build_breaker() -> Dictionary:
	var net := build_simple_physical_network()
	var t := TimeFabric.new_timeline(net)
	assert(TimeFabric.add_state(t, "damage", 0.0, TimeFabric.dim_dimensionless(), 1.0))
	assert(TimeFabric.add_parameter(t, "damage_rate", 2.0, TimeFabric.dim_div(TimeFabric.dim_dimensionless(), TimeFabric.dim_time())))
	assert(TimeFabric.add_parameter(t, "trip", 1.0, TimeFabric.dim_dimensionless()))
	assert(TimeFabric.add_mode(t, "armed", {"damage": TimeFabric.expr_parameter("damage_rate")}))
	assert(TimeFabric.add_mode(t, "tripped", {}))
	assert(TimeFabric.set_initial_mode(t, "armed"))
	assert(TimeFabric.add_transition(t, {
		"id": "trip_breaker",
		"from_modes": ["armed"],
		"to_mode": "tripped",
		"guard": {"expr": TimeFabric.expr_sub(TimeFabric.expr_state("damage"), TimeFabric.expr_parameter("trip")), "nominal": 1.0, "direction": 1},
		"resets": {"damage": TimeFabric.expr_parameter("trip")},
		"topology_ops": [{"op": "set_bond_active", "bond_id": "fuse_link", "active": false}],
		"priority": 0,
	}))
	return t

static func build_simultaneous_swap() -> Dictionary:
	var t := TimeFabric.new_timeline()
	assert(TimeFabric.add_state(t, "a", 1.0, TimeFabric.dim_dimensionless(), 1.0))
	assert(TimeFabric.add_state(t, "b", 2.0, TimeFabric.dim_dimensionless(), 1.0))
	assert(TimeFabric.add_state(t, "clock", 0.0, TimeFabric.dim_time(), 1.0))
	assert(TimeFabric.add_mode(t, "run", {"clock": TimeFabric.expr_constant(1.0, TimeFabric.dim_dimensionless())}))
	assert(TimeFabric.set_initial_mode(t, "run"))
	assert(TimeFabric.add_transition(t, {
		"id": "swap",
		"from_modes": ["run"],
		"to_mode": "run",
		"guard": {"expr": TimeFabric.expr_sub(TimeFabric.expr_state("clock"), TimeFabric.expr_constant(1.0, TimeFabric.dim_time())), "nominal": 1.0, "direction": 1},
		"resets": {
			"a": TimeFabric.expr_state("b"),
			"b": TimeFabric.expr_state("a"),
			"clock": TimeFabric.expr_constant(0.0, TimeFabric.dim_time()),
		},
		"topology_ops": [],
		"priority": 0,
	}))
	return t

static func build_invalid_topology_transaction() -> Dictionary:
	var net := build_simple_physical_network()
	var t := TimeFabric.new_timeline(net)
	assert(TimeFabric.add_state(t, "clock", 0.0, TimeFabric.dim_time(), 1.0))
	assert(TimeFabric.add_mode(t, "armed", {"clock": TimeFabric.expr_constant(1.0, TimeFabric.dim_dimensionless())}))
	assert(TimeFabric.add_mode(t, "broken", {}))
	assert(TimeFabric.set_initial_mode(t, "armed"))
	assert(TimeFabric.add_transition(t, {
		"id": "bad_break",
		"from_modes": ["armed"],
		"to_mode": "broken",
		"guard": {"expr": TimeFabric.expr_sub(TimeFabric.expr_state("clock"), TimeFabric.expr_constant(0.5, TimeFabric.dim_time())), "nominal": 1.0, "direction": 1},
		"resets": {},
		"topology_ops": [
			{"op": "set_bond_active", "bond_id": "fuse_link", "active": false},
			{"op": "set_bond_active", "bond_id": "missing_link", "active": false},
		],
		"priority": 0,
	}))
	return t

static func build_event_storm() -> Dictionary:
	var t := TimeFabric.new_timeline()
	assert(TimeFabric.add_state(t, "clock", 0.0, TimeFabric.dim_time(), 0.01))
	assert(TimeFabric.add_mode(t, "run", {"clock": TimeFabric.expr_constant(1.0, TimeFabric.dim_dimensionless())}))
	assert(TimeFabric.set_initial_mode(t, "run"))
	assert(TimeFabric.add_transition(t, {
		"id": "tick",
		"from_modes": ["run"],
		"to_mode": "run",
		"guard": {"expr": TimeFabric.expr_sub(TimeFabric.expr_state("clock"), TimeFabric.expr_constant(0.01, TimeFabric.dim_time())), "nominal": 0.01, "direction": 1},
		"resets": {"clock": TimeFabric.expr_constant(0.0, TimeFabric.dim_time())},
		"topology_ops": [],
		"priority": 0,
	}))
	return t
