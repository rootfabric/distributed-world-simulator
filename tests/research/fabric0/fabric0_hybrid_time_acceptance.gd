extends SceneTree

const TimeFabric = preload("res://scripts/research/fabric0/fabric0_hybrid_time_v1.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_hybrid_time_experiments_v1.gd")

func bond_active(timeline: Dictionary, bond_id: String) -> bool:
	for bond in timeline["physical_network"]["bonds"]:
		if String(bond["id"]) == bond_id:
			return bool(bond["active"])
	return false

func _init() -> void:
	var checks := 0

	# Dimension checking for continuous flows and reset maps.
	var bad := TimeFabric.new_timeline()
	assert(TimeFabric.add_state(bad, "x", 0.0, TimeFabric.dim_length())); checks += 1
	assert(not TimeFabric.add_mode(bad, "bad", {"x": TimeFabric.expr_constant(1.0, TimeFabric.dim_length())})); checks += 1
	assert(String(bad["diagnostics"][0]["code"]) == "FLOW_DIMENSION_MISMATCH"); checks += 1
	var reset_bad := TimeFabric.new_timeline()
	assert(TimeFabric.add_state(reset_bad, "x", 0.0, TimeFabric.dim_length())); checks += 1
	assert(TimeFabric.add_mode(reset_bad, "run", {})); checks += 1
	assert(TimeFabric.set_initial_mode(reset_bad, "run")); checks += 1
	assert(not TimeFabric.add_transition(reset_bad, {
		"id": "bad_reset", "from_modes": ["run"], "to_mode": "run",
		"guard": {"expr": TimeFabric.expr_state("x"), "nominal": 1.0, "direction": 1},
		"resets": {"x": TimeFabric.expr_constant(1.0, TimeFabric.dim_time())},
		"topology_ops": []
	})); checks += 1
	assert(String(reset_bad["diagnostics"][0]["code"]) == "RESET_DIMENSION_MISMATCH"); checks += 1

	# Bouncing impact: locate exact event inside the macro-step and reset velocity.
	var ball := Experiments.build_bouncing_ball()
	var ball_result := TimeFabric.advance(ball, 0.6)
	assert(bool(ball_result["ok"])); checks += 1
	assert(int(ball_result["events"]) == 1); checks += 1
	assert(ball["events"].size() == 1); checks += 1
	var impact: Dictionary = ball["events"][0]
	assert(String(impact["transition_id"]) == "impact"); checks += 1
	assert(absf(float(impact["time"]) - 0.3609505622728941) <= 2.0e-10); checks += 1
	assert(is_equal_approx(float(impact["pre_states"]["h"]), 0.0)); checks += 1
	assert(absf(float(impact["pre_states"]["v"]) - (-4.540925015897091)) <= 2.0e-9); checks += 1
	assert(is_equal_approx(float(impact["post_states"]["h"]), 0.0)); checks += 1
	assert(absf(float(impact["post_states"]["v"]) - 3.632740012717673) <= 2.0e-9); checks += 1
	assert(absf(float(impact["post_states"]["v"]) + 0.8 * float(impact["pre_states"]["v"])) <= 2.0e-9); checks += 1
	var pre_ke := 0.5 * pow(float(impact["pre_states"]["v"]), 2.0)
	var post_ke := 0.5 * pow(float(impact["post_states"]["v"]), 2.0)
	assert(absf(post_ke / pre_ke - 0.64) <= 2.0e-9); checks += 1
	assert(absf(TimeFabric.read_state(ball, "h") - 0.5881100292600682) <= 2.0e-8); checks += 1
	assert(absf(TimeFabric.read_state(ball, "v") - 1.2876650286147648) <= 2.0e-8); checks += 1
	assert(absf(float(ball["time"]) - 0.6) <= 1.0e-12); checks += 1
	assert(String(impact["event_id"]) == "fabric0/event/000001/impact"); checks += 1
	assert(String(impact["pre_state_hash"]).length() == 64); checks += 1
	assert(String(impact["post_state_hash"]).length() == 64); checks += 1

	# Hysteresis: switch on at upper, remain on in deadband, switch off at lower.
	var schmitt := Experiments.build_schmitt()
	var up := TimeFabric.advance(schmitt, 1.2)
	assert(bool(up["ok"])); checks += 1
	assert(int(up["events"]) == 1); checks += 1
	assert(TimeFabric.read_mode(schmitt) == "on"); checks += 1
	assert(absf(float(schmitt["events"][0]["time"]) - 1.0) <= 2.0e-10); checks += 1
	assert(absf(TimeFabric.read_state(schmitt, "x") - 1.2) <= 1.0e-10); checks += 1
	assert(TimeFabric.set_parameter_value(schmitt, "rate", -1.0)); checks += 1
	var band := TimeFabric.advance(schmitt, 0.5)
	assert(bool(band["ok"])); checks += 1
	assert(int(band["events"]) == 0); checks += 1
	assert(TimeFabric.read_mode(schmitt) == "on"); checks += 1
	assert(absf(TimeFabric.read_state(schmitt, "x") - 0.7) <= 1.0e-10); checks += 1
	var down := TimeFabric.advance(schmitt, 0.6)
	assert(bool(down["ok"])); checks += 1
	assert(int(down["events"]) == 1); checks += 1
	assert(TimeFabric.read_mode(schmitt) == "off"); checks += 1
	assert(schmitt["events"].size() == 2); checks += 1
	assert(absf(float(schmitt["events"][1]["time"]) - 2.2) <= 2.0e-10); checks += 1
	assert(absf(TimeFabric.read_state(schmitt, "x") - 0.1) <= 1.0e-9); checks += 1

	# Irreversible breaker: event-localized topology mutation is atomic and persistent.
	var breaker := Experiments.build_breaker()
	assert(bond_active(breaker, "fuse_link")); checks += 1
	var breaker_result := TimeFabric.advance(breaker, 1.0)
	assert(bool(breaker_result["ok"])); checks += 1
	assert(int(breaker_result["events"]) == 1); checks += 1
	assert(TimeFabric.read_mode(breaker) == "tripped"); checks += 1
	assert(not bond_active(breaker, "fuse_link")); checks += 1
	assert(int(breaker["topology_revision"]) == 1); checks += 1
	assert(absf(float(breaker["events"][0]["time"]) - 0.5) <= 2.0e-10); checks += 1
	assert(int(breaker["events"][0]["topology_revision_before"]) == 0); checks += 1
	assert(int(breaker["events"][0]["topology_revision_after"]) == 1); checks += 1
	assert(is_equal_approx(TimeFabric.read_state(breaker, "damage"), 1.0)); checks += 1
	var after_trip := TimeFabric.advance(breaker, 2.0)
	assert(bool(after_trip["ok"])); checks += 1
	assert(int(after_trip["events"]) == 0); checks += 1
	assert(TimeFabric.read_mode(breaker) == "tripped"); checks += 1
	assert(not bond_active(breaker, "fuse_link")); checks += 1
	assert(is_equal_approx(TimeFabric.read_state(breaker, "damage"), 1.0)); checks += 1

	# Simultaneous reset semantics: both RHS read the same pre-event snapshot.
	var swap := Experiments.build_simultaneous_swap()
	var swap_result := TimeFabric.advance(swap, 1.1)
	assert(bool(swap_result["ok"])); checks += 1
	assert(int(swap_result["events"]) == 1); checks += 1
	assert(is_equal_approx(float(swap["events"][0]["pre_states"]["a"]), 1.0)); checks += 1
	assert(is_equal_approx(float(swap["events"][0]["pre_states"]["b"]), 2.0)); checks += 1
	assert(is_equal_approx(float(swap["events"][0]["post_states"]["a"]), 2.0)); checks += 1
	assert(is_equal_approx(float(swap["events"][0]["post_states"]["b"]), 1.0)); checks += 1
	assert(is_equal_approx(TimeFabric.read_state(swap, "a"), 2.0)); checks += 1
	assert(is_equal_approx(TimeFabric.read_state(swap, "b"), 1.0)); checks += 1
	assert(absf(TimeFabric.read_state(swap, "clock") - 0.1) <= 2.0e-9); checks += 1

	# Invalid topology transaction rolls back the entire macro-step.
	var invalid_tx := Experiments.build_invalid_topology_transaction()
	var before_hash := TimeFabric.state_hash(invalid_tx)
	assert(bond_active(invalid_tx, "fuse_link")); checks += 1
	var invalid_result := TimeFabric.advance(invalid_tx, 1.0)
	assert(not bool(invalid_result["ok"])); checks += 1
	assert(bool(invalid_result["rolled_back"])); checks += 1
	assert(String(invalid_result["code"]) == "TOPOLOGY_TRANSACTION_UNKNOWN_BOND"); checks += 1
	assert(bond_active(invalid_tx, "fuse_link")); checks += 1
	assert(TimeFabric.read_mode(invalid_tx) == "armed"); checks += 1
	assert(is_equal_approx(TimeFabric.read_state(invalid_tx, "clock"), 0.0)); checks += 1
	assert(is_equal_approx(float(invalid_tx["time"]), 0.0)); checks += 1
	assert(invalid_tx["events"].is_empty()); checks += 1
	assert(TimeFabric.state_hash(invalid_tx) == before_hash); checks += 1

	# Event-storm / Zeno protection also rolls back the macro-step.
	var storm := Experiments.build_event_storm()
	var storm_hash := TimeFabric.state_hash(storm)
	var storm_result := TimeFabric.advance(storm, 1.0)
	assert(not bool(storm_result["ok"])); checks += 1
	assert(bool(storm_result["rolled_back"])); checks += 1
	assert(String(storm_result["code"]) == "ZENO_OR_EVENT_STORM"); checks += 1
	assert(is_equal_approx(float(storm["time"]), 0.0)); checks += 1
	assert(is_equal_approx(TimeFabric.read_state(storm, "clock"), 0.0)); checks += 1
	assert(storm["events"].is_empty()); checks += 1
	assert(TimeFabric.state_hash(storm) == storm_hash); checks += 1

	# Deterministic replay: impact timeline and event identities/hashes are stable.
	var replay_a := Experiments.build_bouncing_ball()
	var replay_b := Experiments.build_bouncing_ball()
	assert(bool(TimeFabric.advance(replay_a, 1.0)["ok"])); checks += 1
	assert(bool(TimeFabric.advance(replay_b, 1.0)["ok"])); checks += 1
	assert(replay_a["events"].size() == replay_b["events"].size()); checks += 1
	assert(replay_a["events"].size() >= 1); checks += 1
	assert(TimeFabric.state_hash(replay_a) == TimeFabric.state_hash(replay_b)); checks += 1
	assert(JSON.stringify(replay_a["events"]) == JSON.stringify(replay_b["events"])); checks += 1

	print("FABRIC0.7 Hybrid Time Acceptance: PASS (%d assertions) impact_t=%.12f bounce_v=%.9f schmitt=%s breaker=%s storm=%s hash=%s" % [
		checks,
		float(impact["time"]),
		float(impact["post_states"]["v"]),
		TimeFabric.read_mode(schmitt),
		TimeFabric.read_mode(breaker),
		String(storm_result["code"]),
		TimeFabric.state_hash(replay_a),
	])
	quit(0)
