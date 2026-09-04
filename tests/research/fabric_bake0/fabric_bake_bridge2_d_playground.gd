extends SceneTree

const InvalidationFixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge2_d_fixture.gd")

func _initialize() -> void:
	var b := InvalidationFixture.build()
	if not bool(b.get("success", false)):
		printerr("BRIDGE-2-D playground failed: %s" % str(b))
		quit(1)
		return
	var trace: Dictionary = b["trace"]
	print("BRIDGE-2-D INVALIDATION / REFINEMENT ORDERING PLAYGROUND")
	print("event=%s" % trace["event_id"])
	print("previous_frontier=%s" % trace["previous_source_frontier_hash"])
	print("current_frontier=%s" % trace["current_source_frontier_hash"])
	for phase in trace["phase_records"]:
		print("phase[%d]=%s proof=%s" % [phase["phase_index"], phase["phase_kind"], phase["proof_hash"]])
	print("structural_stale=%s" % b["structural_stale"].get("error_code", ""))
	print("contact_stale=%s" % b["contact_stale"].get("code", ""))
	print("dynamic_stale=%s" % b["dynamic_stale"].get("error_code", ""))
	print("hybrid_stale=%s" % b["hybrid_stale"].get("error_code", ""))
	print("fresh_structural_artifacts=%d" % int(b["topology_runtime"]["diagnostics"]["executable_physical_bake_artifact_count"]))
	print("trace_hash=%s" % trace["trace_hash"])
	print("FABRIC-BAKE BRIDGE-2-D Playground: PASS")
	quit(0)
