extends SceneTree

const E=preload("res://scripts/research/fabric0/fabric0_simultaneous_impact_event_set_experiments_v1.gd")

func _init()->void:
	var coarse:=E.five_body_probe(1.0e-3)
	var fine:=E.five_body_probe(1.0e-9)
	var reference:=E.five_body_probe(1.0e-11)
	print("=== FABRIC0.17-A SIMULTANEOUS IMPACT EVENT SET ===")
	print("coarse_set=",coarse.pair_ids," time=",coarse.time," classification=",coarse.classification," spread=",coarse.temporal_spread)
	print("fine_set=",fine.pair_ids," time=",fine.time," classification=",fine.classification," deferred=",fine.deferred_events)
	print("reference_set=",reference.pair_ids," time=",reference.time," deferred_time=",reference.deferred_events[0].time)
	print("signature=",reference.signature)
	print("FABRIC0_17_A_SIMULTANEOUS_IMPACT_EVENT_SET_PLAYGROUND_PASS")
	quit(0)
