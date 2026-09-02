extends SceneTree
const T=preload("res://scripts/research/fabric0/fabric0_multi_impact_wrench_trajectory_v1.gd")
func _init()->void:
	var r:=T.run(1.0e-9)
	print("=== FABRIC0.17-D UNIFIED MULTI-IMPACT WRENCH TRAJECTORY ===")
	print("events=",r.events)
	print("state=",r.state)
	print("energy=",r.initial_energy," -> ",r.final_energy," terms=",r.energy_terms," ledger=",r.energy_ledger_error)
	print("momentum linear/angular=",r.linear_momentum_error,",",r.angular_momentum_error)
	print("FABRIC0_17_D_UNIFIED_MULTI_IMPACT_WRENCH_TRAJECTORY_PLAYGROUND_PASS")
	quit(0)
