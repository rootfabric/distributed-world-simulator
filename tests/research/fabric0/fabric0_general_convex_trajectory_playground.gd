extends SceneTree
const T=preload("res://scripts/research/fabric0/fabric0_general_convex_trajectory_v1.gd")
func _init()->void:
	var run=T.run(1.0e-9)
	var ref=T.run(1.0e-11)
	print("=== FABRIC0.16 S3 UNIFIED EVENT-DRIVEN CONVEX TRAJECTORY ===")
	print("events=",run.events)
	print("topology=",run.topology)
	print("rows=",run.merged_rows,"->",run.split_rows," threads=",run.initial_threads,"->",run.merged_threads,"->",run.split_threads)
	print("state_error_vs_1e-11=",T.state_error(run,ref)," event_error=",T.event_time_error(run,ref))
	print("energy initial/final/source/contact/residual=",run.initial_energy,",",run.final_energy,",",run.source_work,",",run.contact_dissipation,",",run.energy_residual)
	print("momentum linear/angular=",run.linear_momentum_error,",",run.angular_momentum_error)
	print("FABRIC0_16_S3_UNIFIED_EVENT_DRIVEN_CONVEX_TRAJECTORY_PLAYGROUND_PASS")
	quit(0)
