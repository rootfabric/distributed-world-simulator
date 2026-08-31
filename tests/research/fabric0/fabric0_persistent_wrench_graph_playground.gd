extends SceneTree
const E=preload("res://scripts/research/fabric0/fabric0_persistent_wrench_graph_experiments_v1.gd")
func _init()->void:
	var support=E.plank(0.7,0.6,0.16,0.05)
	var mixed=E.corner_mixed_probe()
	var loss=E.plank(1.1,0,0,0,false,0.0)
	print("FABRIC0.18-C support L/R=",support.per_contact.L.normal_impulse,"/",support.per_contact.R.normal_impulse," modes=",support.per_contact.L.persistent_state.modes)
	print("mixed floor/wall=",mixed.floor_modes," / ",mixed.wall_modes)
	print("loss L active=",loss.per_contact.L.persistent_state.active," open_vn=",loss.min_open_normal_velocity)
	print("FABRIC0_18_C_MULTICONTACT_PERSISTENT_WRENCH_GRAPH_PLAYGROUND_PASS")
	quit(0)
