extends SceneTree
## Fresh independent review: two disjoint local ranges can independently lose
## and regain a representable COM after real source-revision updates.
const Index = preload("res://scripts/research/fabric_bake0/r5_6_1_r2_dynamic_aggregate_index_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const O := 1.0e12
const TINY := 0.0001220703125
var checks := 0
var failures: Array = []
var observations: Array = []
func ck(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures.append(message)
        push_error("R56_REVIEW_COM_RANGE: " + message)
func sample(index: int, y: float) -> Dictionary:
    return Part.create("part/range/%d" % index, "item/range/%d" % index, "BEAM", "member", 1.0, [0.0, y, 0.0])
func state(revision: int, y1: float, y3: float) -> Dictionary:
    return Snapshot.create("construct/range-recovery", "item/range-root", revision, "OPERATIONAL", [
        sample(0,O), sample(1,y1), sample(2,O+10.0), sample(3,y3)
    ], [], {})
func check_range(index, first: int, end: int, good: bool, tag: String, center_rel: float=0.0, ixx: float=0.0) -> void:
    var result: Dictionary = index.query_range(first,end)
    observations.append({"name":tag,"success":result.success,"error":String(result.get("error_code",""))})
    if good:
        ck(result.success, tag+" query succeeds")
        if result.success:
            var com: Array = result.details.center_of_mass
            ck(absf((float(com[1])-O)-center_rel)<1.0e-6, tag+" COM canonical")
            ck(absf(float(result.details.total_mass)-2.0)<1.0e-12, tag+" mass conserved")
            ck(absf(float(result.details.inertia_tensor_body[0][0])-ixx)<1.0e-6, tag+" centered full inertia")
    else:
        ck(not result.success, tag+" query refused")
        if not result.success:
            ck(String(result.error_code) in ["R56_R2_RANGE_CENTER_PRECISION_UNSAFE","R56_R2_RANGE_NUMERIC_PRECISION_UNSAFE"], tag+" numeric fail-closed")
func update(index, before: Dictionary, after: Dictionary, changed_index: int, tag: String) -> void:
    var result: Dictionary = index.apply_owner_verified([{"before":before.parts[changed_index],"after":after.parts[changed_index]}],
        String(before.checksum),String(after.checksum),int(after.state_revision),4.0)
    ck(result.success,tag+" legitimate successor allowed")
    if result.success:
        ck(int(index.status().revision)==int(after.state_revision),tag+" revision advanced")
        ck(String(index.status().source_checksum)==String(after.checksum),tag+" exact successor checksum")
func _initialize() -> void:
    var s0 := state(0,O+1.0,O+12.0)
    var s1 := state(1,O+TINY,O+12.0)
    var s2 := state(2,O+1.0,O+12.0)
    var s3 := state(3,O+1.0,O+10.0+TINY)
    var s4 := state(4,O+1.0,O+12.0)
    for s in [s0,s1,s2,s3,s4]:
        ck(Snapshot.validate(s).success,"all real canonical source revisions valid")
    var index = Index.new()
    ck(index.initialize(s0).success,"initialize index from four-part source")
    check_range(index,0,2,true,"initial region A",0.5,0.5)
    check_range(index,2,4,true,"initial region B",11.0,2.0)
    update(index,s0,s1,1,"A enters COM unsafe")
    check_range(index,0,2,false,"A withheld")
    check_range(index,2,4,true,"B unaffected",11.0,2.0)
    var snapshot = index.status().duplicate(true)
    var wrong_mass = index.apply_owner_verified([{"before":s1.parts[1],"after":s2.parts[1]}], String(s1.checksum),String(s2.checksum),2,3.0)
    ck(not wrong_mass.success and String(wrong_mass.error_code)=="R56_R2_MATTER_MASS_MISMATCH", "bad Matter refused while A unsafe")
    ck(index.status()==snapshot,"bad Matter leaves all index status unchanged")
    update(index,s1,s2,1,"A safely recovers")
    check_range(index,0,2,true,"recovered A",0.5,0.5)
    update(index,s2,s3,3,"B enters COM unsafe")
    check_range(index,0,2,true,"A stays safe",0.5,0.5)
    check_range(index,2,4,false,"B withheld")
    update(index,s3,s4,3,"B safely recovers")
    check_range(index,2,4,true,"recovered B",11.0,2.0)
    var last=index.status().duplicate(true)
    var replay=index.apply_owner_verified([{"before":s3.parts[3],"after":s4.parts[3]}],String(s3.checksum),String(s4.checksum),4,4.0)
    ck(not replay.success and String(replay.error_code)=="R56_R2_INDEX_SOURCE_STALE", "repeat replay rejected")
    ck(index.status()==last,"replay leaves complete index status untouched")
    ck(int(last.accepted_updates)==4 and int(last.update_full_moment_scans)==0,"four owner updates and no full scans")
    print("FABRIC_R56_R2_FRESH_MULTI_RANGE_REVIEW="+JSON.stringify({"checks":checks,"failures":failures,"observations":observations}))
    quit(0 if failures.is_empty() else 1)
