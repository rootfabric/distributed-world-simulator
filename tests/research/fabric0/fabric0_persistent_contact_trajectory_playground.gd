extends SceneTree
const T=preload("res://scripts/research/fabric0/fabric0_persistent_contact_trajectory_v1.gd")
func _init()->void:
	var r:=T.run(1.0e-9)
	print("FABRIC0.18-D timeline=",r.get("timeline_ids",[]))
	print("times=",r.get("timeline_times",[]))
	if bool(r.get("ok",false)):
		for e in r["events"]: print(e["event_id"]," modes=",e["left_modes"]," support=",e["left_support"],"/",e["right_support"])
		print("final L/R=",r["final_left_state"]["modes"]," / ",r["final_right_state"]["modes"])
	print("FABRIC0_18_D_UNIFIED_PERSISTENT_CONTACT_TRAJECTORY_PLAYGROUND_PASS")
	quit(0 if bool(r.get("ok",false)) else 1)
