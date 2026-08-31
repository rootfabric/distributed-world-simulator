extends SceneTree
const Lifecycle = preload("res://scripts/research/fabric_bake0/physical_source_lifecycle_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge1_fixture.gd")
func _init() -> void:
	var a := Fixture.build(0)
	var b := Fixture.build(1)
	var compiled := Lifecycle.compile(a["view_request"])
	var executed := Lifecycle.execute(compiled, Fixture.reduced_state())
	var rebuilt := Lifecycle.rebuild_same_topology(compiled, Fixture.reduced_state(), Fixture.invalidation(a,b), b["view_request"])
	print("BRIDGE-1 artifact=", compiled.get("artifact",{}).get("artifact_id",""), " graph=", compiled.get("physical_graph",{}).get("graph_hash",""))
	print("execute=", executed.get("status",""), " rebuild=", rebuilt.get("status",""), " handoff=", rebuilt.get("handoff_error",-1.0))
	print("FABRIC_BAKE_BRIDGE1_PHYSICAL_SOURCE_LIFECYCLE_PLAYGROUND_PASS")
	quit(0 if bool(rebuilt.get("success",false)) else 1)
