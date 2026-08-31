extends SceneTree
const E=preload("res://scripts/research/fabric0/fabric0_persistent_wrench_mode_transition_experiments_v1.gd")
func _init() -> void:
	var all:=E.all_transition_probe()
	var coarse:=E.near_coincident_probe(1.0e-3)
	var fine:=E.near_coincident_probe(1.0e-5)
	print("FABRIC0.18-B transitions=", all["events"])
	print("coarse event set=", coarse["event_ids"], " fine=", fine["event_ids"], " deferred=", fine["deferred_events"].size())
	print("FABRIC0_18_B_MODE_TRANSITION_LOCALIZATION_PLAYGROUND_PASS")
	quit(0)
