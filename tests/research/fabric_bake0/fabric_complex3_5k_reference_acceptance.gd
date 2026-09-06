extends SceneTree
const Stream = preload("res://scripts/research/fabric_bake0/complex3_streaming_canonical_structure_v1.gd")
const F = preload("res://tests/research/fabric_bake0/fabric_bake_complex0_fixture.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/structural_aggregate_compiler_v1.gd")
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
    checks+=1
    if not ok: failed=true; push_error("COMPLEX3-5K-REF: "+label)
func max_matrix_error(a:Array,b:Array)->float:
    var e:=0.0
    for i in 3:
        for j in 3: e=maxf(e,absf(float(a[i][j])-float(b[i][j])))
    return e
func _initialize()->void:
    var c3=Stream.create_subject(5000,false); check(c3.success,"stream source")
    var stream=Stream.aggregate_span(c3.spec,0,5000); check(stream.success,"stream aggregate")
    var f=F.build(5000); check(f.success,"explicit predecessor fixture")
    if failed: quit(1); return
    var ag=Compiler.compile({"descriptor_id":"aggregate/complex3-reference-005000","mapping_id":"mapping/complex3-reference-005000","source_frontier_hash":f.frontier.frontier_hash,"construct_id":f.construct_id,"parts":f.parts,"bonds":f.bonds,"boundary_anchors":f.anchors,"reconstruction_version":"FABRIC_COMPLEX3_REFERENCE_R1","minimum_part_count":100})
    check(ag.success,"explicit predecessor aggregate")
    if not ag.success: print(ag); quit(1); return
    var sd:Dictionary=stream.details.descriptor; var ed:Dictionary=ag.descriptor
    check(absf(float(sd.total_mass)-float(ed.total_mass)) < 1.0e-8,"mass parity")
    var cv=Vector3(sd.center_of_mass[0],sd.center_of_mass[1],sd.center_of_mass[2]); var ev=Vector3(ed.center_of_mass[0],ed.center_of_mass[1],ed.center_of_mass[2])
    check(cv.distance_to(ev) < 1.0e-10,"center parity")
    var ie=max_matrix_error(sd.inertia_tensor_body,ed.inertia_tensor_body)
    check(ie < 1.0e-6,"inertia parity")
    check(int(sd.part_count)==int(ed.part_count) and int(ed.part_count)==5000,"part count")
    print("COMPLEX3_5K_REFERENCE_ERROR="+JSON.stringify({"mass":absf(float(sd.total_mass)-float(ed.total_mass)),"center":cv.distance_to(ev),"inertia":ie}))
    print("COMPLEX3_5K_REFERENCE_HASH="+U.canonical_hash({"stream_mass":sd.total_mass,"stream_com":sd.center_of_mass,"stream_inertia":sd.inertia_tensor_body,"explicit_mass":ed.total_mass,"explicit_com":ed.center_of_mass,"explicit_inertia":ed.inertia_tensor_body}))
    if not failed: print("FABRIC COMPLEX3-5K REFERENCE: PASS (%d assertions)"%checks)
    quit(1 if failed else 0)
