extends SceneTree
const Index = preload("res://scripts/research/fabric_bake0/r5_6_1_r2_dynamic_aggregate_index_v1.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
var cases : Array = []
var failures : Array = []
func check(x: float):
    var a=Part.create("part/test/a", "item/test/a", "BEAM", "member", 1.0,[x, 0.0, 0.0])
    var b=Part.create("part/test/b", "item/test/b", "BEAM", "member", 1.0,[x+1.0, 0.0, 0.0])
    var snap=Snapshot.create("construct/test","item/test/root",0,"OPERATIONAL",[a,b],[],{})
    var valid=Snapshot.validate(snap)
    var i=Index.new()
    var init=i.initialize(snap)
    var actual=i.query_range(0,2) if init.success else {}
    var inertia_y = float(actual.details.inertia_tensor_body[1][1]) if actual.get("success",false) else -9999.0
    var deviation = absf(inertia_y-0.5)
    cases.append({"offset":x,"source_valid":valid.success,"index_init":init.success,"query_ok":actual.get("success",false),"expected_inertia_yy":0.5,"actual_inertia_yy":inertia_y,"error":deviation})
    if valid.success and init.success and actual.get("success",false) and deviation>1e-3:
        failures.append("UNSAFE_INERTIA_ACCEPTED_AT_OFFSET_"+str(x))
func _initialize():
    for x in [1.0,1.0e5,1.0e7,1.0e8,1.0e9]:check(x)
    print("FABRIC_R56_R2_OFFSET_REVIEW="+JSON.stringify({"cases":cases,"failures":failures}))
    quit(0 if failures.is_empty() else 1)
