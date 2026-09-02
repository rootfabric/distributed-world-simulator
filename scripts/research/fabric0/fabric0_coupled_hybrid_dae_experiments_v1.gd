class_name Fabric0CoupledHybridDAEExperimentsV1
extends RefCounted

const Fabric = preload("res://scripts/research/fabric0/fabric0_coupled_hybrid_dae_v1.gd")
const Physical = preload("res://scripts/research/fabric0/fabric0_nonsmooth_fabric_v1.gd")

static func build_drive_network() -> Dictionary:
	var net := Physical.new_network()
	assert(Physical.register_domain(net, "mechanical", "velocity", "force", Physical.dim_velocity(), Physical.dim_force(), "m/s", "N"))
	assert(Physical.add_element(net, Physical.equilibrium_terminal("drive_source", "mechanical", 1.0, 1.0)))
	assert(Physical.add_element(net, Physical.equilibrium_terminal("drive_sink", "mechanical", 0.0, 1.0)))
	assert(Physical.link_ports(net, "drive_link", "drive_source", "p", "drive_sink", "p"))
	return net

static func build_two_body_impact() -> Dictionary:
	var s := Fabric.new_system(build_drive_network())
	# Differential state.
	assert(Fabric.add_state(s, "x_a", 0.0, Fabric.dim_length(), 1.0))
	assert(Fabric.add_state(s, "x_b", 2.0, Fabric.dim_length(), 1.0))
	assert(Fabric.add_state(s, "v_n_a", 3.0, Fabric.dim_velocity(), 1.0))
	assert(Fabric.add_state(s, "v_n_b", -1.0, Fabric.dim_velocity(), 1.0))
	assert(Fabric.add_state(s, "v_t_a", 2.0, Fabric.dim_velocity(), 1.0))
	assert(Fabric.add_state(s, "v_t_b", -1.0, Fabric.dim_velocity(), 1.0))
	assert(Fabric.add_state(s, "last_j_n", 0.0, Fabric.dim_impulse(), 1.0))
	assert(Fabric.add_state(s, "last_j_t", 0.0, Fabric.dim_impulse(), 1.0))

	# Algebraic force unknowns. These are solved at every RK stage.
	assert(Fabric.add_algebraic(s, "f_a", 0.0, Fabric.dim_force(), 1.0))
	assert(Fabric.add_algebraic(s, "f_b", 0.0, Fabric.dim_force(), 1.0))

	assert(Fabric.add_parameter(s, "m_a", 2.0, Fabric.dim_mass()))
	assert(Fabric.add_parameter(s, "m_b", 1.0, Fabric.dim_mass()))
	assert(Fabric.add_parameter(s, "drive_force", 2.0, Fabric.dim_force()))
	assert(Fabric.add_parameter(s, "restitution", 0.5, Fabric.dim_dimensionless()))
	assert(Fabric.add_parameter(s, "mu", 0.3, Fabric.dim_dimensionless()))
	assert(Fabric.add_parameter(s, "break_impulse", 4.0, Fabric.dim_impulse()))

	var flows := {
		"x_a": Fabric.expr_state("v_n_a"),
		"x_b": Fabric.expr_state("v_n_b"),
		"v_n_a": Fabric.expr_div(Fabric.expr_algebraic("f_a"), Fabric.expr_parameter("m_a")),
		"v_n_b": Fabric.expr_div(Fabric.expr_algebraic("f_b"), Fabric.expr_parameter("m_b")),
	}
	var dae_rows: Array = [
		Fabric.residual(
			Fabric.expr_sub(
				Fabric.expr_algebraic("f_a"),
				Fabric.expr_mul(Fabric.expr_parameter("drive_force"), Fabric.expr_bond_active("drive_link"))
			), 1.0
		),
		Fabric.residual(Fabric.expr_algebraic("f_b"), 1.0),
	]
	# Same equations in both modes. The physical bond, not the mode name, gates the force.
	assert(Fabric.add_mode(s, "intact", flows, dae_rows))
	assert(Fabric.add_mode(s, "broken", flows, dae_rows))
	assert(Fabric.set_initial_mode(s, "intact"))

	# Generic branch-based impulse map.
	var ma := Fabric.expr_parameter("m_a")
	var mb := Fabric.expr_parameter("m_b")
	var e := Fabric.expr_parameter("restitution")
	var mu := Fabric.expr_parameter("mu")
	var jn := Fabric.expr_jump("j_n")
	var jt := Fabric.expr_jump("j_t")
	var post_rel_n := Fabric.expr_sub(Fabric.expr_post_state("v_n_b"), Fabric.expr_post_state("v_n_a"))
	var pre_rel_n := Fabric.expr_sub(Fabric.expr_pre_state("v_n_b"), Fabric.expr_pre_state("v_n_a"))
	var post_rel_t := Fabric.expr_sub(Fabric.expr_post_state("v_t_b"), Fabric.expr_post_state("v_t_a"))
	var shared: Array = [
		Fabric.residual(Fabric.expr_add(Fabric.expr_mul(ma, Fabric.expr_sub(Fabric.expr_post_state("v_n_a"), Fabric.expr_pre_state("v_n_a"))), jn), 1.0),
		Fabric.residual(Fabric.expr_sub(Fabric.expr_mul(mb, Fabric.expr_sub(Fabric.expr_post_state("v_n_b"), Fabric.expr_pre_state("v_n_b"))), jn), 1.0),
		Fabric.residual(Fabric.expr_add(post_rel_n, Fabric.expr_mul(e, pre_rel_n)), 1.0),
		Fabric.residual(Fabric.expr_add(Fabric.expr_mul(ma, Fabric.expr_sub(Fabric.expr_post_state("v_t_a"), Fabric.expr_pre_state("v_t_a"))), jt), 1.0),
		Fabric.residual(Fabric.expr_sub(Fabric.expr_mul(mb, Fabric.expr_sub(Fabric.expr_post_state("v_t_b"), Fabric.expr_pre_state("v_t_b"))), jt), 1.0),
		Fabric.residual(Fabric.expr_sub(Fabric.expr_post_state("last_j_n"), jn), 1.0),
		Fabric.residual(Fabric.expr_sub(Fabric.expr_post_state("last_j_t"), jt), 1.0),
	]
	var normal_nonnegative := Fabric.inequality(jn, 1.0, "normal_impulse_nonnegative")
	var stick_rows := shared.duplicate(true)
	stick_rows.append(Fabric.residual(post_rel_t, 1.0))
	var slide_neg_rows := shared.duplicate(true)
	slide_neg_rows.append(Fabric.residual(Fabric.expr_sub(jt, Fabric.expr_mul(mu, jn)), 1.0))
	var slide_pos_rows := shared.duplicate(true)
	slide_pos_rows.append(Fabric.residual(Fabric.expr_add(jt, Fabric.expr_mul(mu, jn)), 1.0))
	var jump_branches: Array = [
		Fabric.jump_branch("stick", stick_rows, [
			normal_nonnegative,
			Fabric.inequality(Fabric.expr_sub(Fabric.expr_mul(mu, jn), jt), 1.0, "upper_friction_cone"),
			Fabric.inequality(Fabric.expr_add(Fabric.expr_mul(mu, jn), jt), 1.0, "lower_friction_cone"),
		], 0),
		Fabric.jump_branch("slide_neg", slide_neg_rows, [
			normal_nonnegative,
			Fabric.inequality(Fabric.expr_neg(post_rel_t), 1.0, "negative_slip"),
		], 1),
		Fabric.jump_branch("slide_pos", slide_pos_rows, [
			normal_nonnegative,
			Fabric.inequality(post_rel_t, 1.0, "positive_slip"),
		], 1),
	]
	assert(Fabric.add_transition(s, {
		"id":"impact",
		"from_modes":["intact"],
		"to_mode":"intact",
		"guard":{
			"expr":Fabric.expr_sub(Fabric.expr_state("x_b"), Fabric.expr_state("x_a")),
			"nominal":1.0,
			"direction":-1,
			"kind":"crossing",
		},
		"jump":{
			"post_states":["v_n_a","v_n_b","v_t_a","v_t_b","last_j_n","last_j_t"],
			"unknowns":{
				"j_n":{"dimension":Fabric.dim_impulse(),"nominal":1.0,"initial":4.0},
				"j_t":{"dimension":Fabric.dim_impulse(),"nominal":1.0,"initial":1.0},
			},
			"branches":jump_branches,
		},
		"topology_ops":[],
		"priority":0,
	}))

	# Same-time condition: use solved impulse from the first jump to break topology.
	assert(Fabric.add_transition(s, {
		"id":"break_on_impulse",
		"from_modes":["intact"],
		"to_mode":"broken",
		"guard":{
			"expr":Fabric.expr_sub(Fabric.expr_state("last_j_n"), Fabric.expr_parameter("break_impulse")),
			"nominal":1.0,
			"direction":0,
			"kind":"condition",
		},
		"jump":{},
		"topology_ops":[{"op":"set_bond_active","bond_id":"drive_link","active":false}],
		"priority":1,
	}))
	return s

static func bond_active(system: Dictionary, bond_id: String) -> bool:
	for bond in system["physical_network"]["bonds"]:
		if String(bond["id"]) == bond_id: return bool(bond["active"])
	return false

static func build_algebraic_guard() -> Dictionary:
	var s := Fabric.new_system()
	assert(Fabric.add_state(s, "x", 0.0, Fabric.dim_length(), 1.0))
	assert(Fabric.add_algebraic(s, "reaction", 0.0, Fabric.dim_force(), 1.0))
	assert(Fabric.add_parameter(s, "speed", 1.0, Fabric.dim_velocity()))
	assert(Fabric.add_parameter(s, "k", 2.0, Fabric.dim_div(Fabric.dim_force(), Fabric.dim_length())))
	assert(Fabric.add_parameter(s, "threshold", 2.0, Fabric.dim_force()))
	var flows := {"x":Fabric.expr_parameter("speed")}
	var rows := [Fabric.residual(Fabric.expr_sub(Fabric.expr_algebraic("reaction"), Fabric.expr_mul(Fabric.expr_parameter("k"), Fabric.expr_state("x"))),1.0)]
	assert(Fabric.add_mode(s,"low",flows,rows))
	assert(Fabric.add_mode(s,"high",flows,rows))
	assert(Fabric.set_initial_mode(s,"low"))
	assert(Fabric.add_transition(s,{
		"id":"reaction_threshold",
		"from_modes":["low"],
		"to_mode":"high",
		"guard":{"expr":Fabric.expr_sub(Fabric.expr_algebraic("reaction"),Fabric.expr_parameter("threshold")),"nominal":1.0,"direction":1,"kind":"crossing"},
		"jump":{},"topology_ops":[],"priority":0,
	}))
	return s
