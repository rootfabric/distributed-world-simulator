extends SceneTree

const TimeFabric = preload("res://scripts/research/fabric0/fabric0_hybrid_time_v1.gd")
const Experiments = preload("res://scripts/research/fabric0/fabric0_hybrid_time_experiments_v1.gd")

func bond_active(timeline: Dictionary, bond_id: String) -> bool:
	for bond in timeline["physical_network"]["bonds"]:
		if String(bond["id"]) == bond_id: return bool(bond["active"])
	return false

func _init() -> void:
	print("=== FABRIC0.7 STATEFUL HYBRID TIME ===")
	print("Macrostep = transaction. Event = localized flow -> simultaneous reset/mode/topology jump -> remaining flow.\n")

	var ball := Experiments.build_bouncing_ball()
	TimeFabric.advance(ball, 0.6)
	var impact: Dictionary = ball["events"][0]
	print("[1] BOUNCING IMPACT + RESTITUTION")
	print("    event_time=%.12f pre_v=%.9f post_v=%.9f final=(h=%.9f,v=%.9f)" % [impact["time"], impact["pre_states"]["v"], impact["post_states"]["v"], TimeFabric.read_state(ball,"h"), TimeFabric.read_state(ball,"v")])
	print("    event_id=%s" % impact["event_id"])

	var schmitt := Experiments.build_schmitt()
	TimeFabric.advance(schmitt, 1.2)
	print("\n[2] SCHMITT-LIKE HYSTERESIS")
	print("    ramp up -> mode=%s x=%.3f event@%.3f" % [TimeFabric.read_mode(schmitt), TimeFabric.read_state(schmitt,"x"), schmitt["events"][0]["time"]])
	TimeFabric.set_parameter_value(schmitt, "rate", -1.0)
	TimeFabric.advance(schmitt, 0.5)
	print("    deadband -> mode=%s x=%.3f (no transition)" % [TimeFabric.read_mode(schmitt), TimeFabric.read_state(schmitt,"x")])
	TimeFabric.advance(schmitt, 0.6)
	print("    cross lower -> mode=%s x=%.3f second_event@%.3f" % [TimeFabric.read_mode(schmitt), TimeFabric.read_state(schmitt,"x"), schmitt["events"][1]["time"]])

	var breaker := Experiments.build_breaker()
	TimeFabric.advance(breaker, 1.0)
	print("\n[3] IRREVERSIBLE BREAKER / TOPOLOGY TRANSACTION")
	print("    mode=%s damage=%.3f bond_active=%s event@%.3f topology_revision=%d" % [TimeFabric.read_mode(breaker), TimeFabric.read_state(breaker,"damage"), str(bond_active(breaker,"fuse_link")), breaker["events"][0]["time"], breaker["topology_revision"]])

	var swap := Experiments.build_simultaneous_swap()
	TimeFabric.advance(swap, 1.1)
	print("\n[4] SIMULTANEOUS RESET")
	print("    pre=(a=%.1f,b=%.1f) post=(a=%.1f,b=%.1f) final_clock=%.3f" % [swap["events"][0]["pre_states"]["a"], swap["events"][0]["pre_states"]["b"], swap["events"][0]["post_states"]["a"], swap["events"][0]["post_states"]["b"], TimeFabric.read_state(swap,"clock")])

	var invalid_tx := Experiments.build_invalid_topology_transaction()
	var tx := TimeFabric.advance(invalid_tx, 1.0)
	print("\n[5] INVALID TOPOLOGY TRANSACTION")
	print("    ok=%s code=%s rolled_back=%s bond_active=%s time=%.1f" % [str(tx["ok"]), tx["code"], str(tx["rolled_back"]), str(bond_active(invalid_tx,"fuse_link")), invalid_tx["time"]])

	var storm := Experiments.build_event_storm()
	var storm_result := TimeFabric.advance(storm, 1.0)
	print("\n[6] EVENT STORM / ZENO GUARD")
	print("    ok=%s code=%s rolled_back=%s time=%.1f events=%d" % [str(storm_result["ok"]), storm_result["code"], str(storm_result["rolled_back"]), storm["time"], storm["events"].size()])

	print("\n    deterministic ball hash: %s" % TimeFabric.state_hash(ball))
	print("\nFABRIC0_7_HYBRID_TIME_PLAYGROUND_PASS")
	quit(0)
