extends SceneTree
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const Fixture=preload("res://tests/construction/fixtures/c16_interaction_fixture.gd")
const Target=preload("res://scripts/construction/interaction/construction_snap_target.gd")
const Request=preload("res://scripts/construction/interaction/construction_placement_request.gd")
const Solution=preload("res://scripts/construction/interaction/construction_placement_solution.gd")
const Resolver=preload("res://scripts/construction/interaction/construction_semantic_snap_resolver.gd")
const Materials=preload("res://scripts/construction/interaction/construction_material_overlay_model.gd")
const C3=preload("res://tests/construction/fixtures/c3_table_build_fixture.gd")
var assertions=0;var failures:Array[String]=[]
func _init():
 _test_target();_test_request();_test_resolver();_test_materials();_finish()
func _test_target():
 var t=Fixture.target();_ok(Target.validate(t),"target");_assert(t.target_kind=="SURFACE","kind");_assert(t.compatible_placement_kinds==["FURNITURE","STRUCTURAL"],"sort");_assert(t.checksum.length()==64,"checksum");_assert(not Utils.canonical_json(t).is_empty(),"json")
 var x=t.duplicate(true);x["extra"]=1;_err(Target.validate(x),"UNEXPECTED_FIELD","extra")
 var axes=t.duplicate(true);axes.up=[0.0,1.0,0.0];axes.checksum=Target.compute_checksum(axes);_err(Target.validate(axes),"CONSTRUCTION_SNAP_TARGET_AXES_NOT_ORTHOGONAL","axes")
 var n=t.duplicate(true);n.normal=[0.0,2.0,0.0];n.checksum=Target.compute_checksum(n);_err(Target.validate(n),"INVALID_CONSTRUCTION_SNAP_TARGET_GEOMETRY","normal")
 var p=t.duplicate(true);p.priority=1001;p.checksum=Target.compute_checksum(p);_err(Target.validate(p),"INVALID_CONSTRUCTION_SNAP_TARGET_PROPERTIES","priority")
func _test_request():
 var r=Fixture.placement();_ok(Request.validate(r),"request");_assert(r.allowed_target_kinds==["PORT","SURFACE"],"allowed sort");_assert(float(r.grid_step_m)==0.5,"grid");_assert(r.checksum.length()==64,"request checksum")
 var bad=r.duplicate(true);bad.snap_radius_m=0.0;bad.checksum=Request.compute_checksum(bad);_err(Request.validate(bad),"INVALID_CONSTRUCTION_PLACEMENT_REQUEST_DISTANCE","radius")
 var kind=r.duplicate(true);kind.allowed_target_kinds=["INVALID"];kind.checksum=Request.compute_checksum(kind);_err(Request.validate(kind),"INVALID_CONSTRUCTION_PLACEMENT_TARGET_KIND","target kind")
func _test_resolver():
 var r=Fixture.placement();var near=Fixture.target("near",[2.0,0.0,3.0],100);var high=Fixture.target("high",[2.4,0.0,3.0],200)
 var solved=Resolver.resolve(r,[near,high]);_ok(solved,"resolve");var s:Dictionary=solved.solution;_ok(Solution.validate(s),"solution");_assert(s.valid,"valid");_assert(s.target_id==high.target_id,"priority");_assert(absf(float(s.position_m[0])-2.5)<0.000001 and absf(float(s.position_m[1]))<0.000001 and absf(float(s.position_m[2])-3.0)<0.000001,"grid snapped");_assert(s.rotation_quat.size()==4,"quat");_assert(float(s.score)>0,"score")
 var reversed=Resolver.resolve(r,[high,near]);_assert(reversed.solution.checksum==s.checksum,"deterministic")
 var incompatible=Fixture.target("bad",[2.0,0.0,3.0],999);incompatible.compatible_placement_kinds=["VEHICLE"];incompatible.checksum=Target.compute_checksum(incompatible)
 var none=Resolver.resolve(r,[incompatible]);_ok(none,"no target result");_assert(not none.solution.valid,"no target invalid");_ok(Solution.validate(none.solution),"invalid solution valid contract")
 var tamper=s.duplicate(true);tamper.position_m=[9,9,9];_err(Solution.validate(tamper),"CONSTRUCTION_PLACEMENT_SOLUTION_CHECKSUM_MISMATCH","tamper")
func _test_materials():
 var plan=C3.build_plan();var ids=[];for p in plan.source_item_projections:ids.append(String(p.item_instance_id))
 var full=Materials.from_build_plan(plan,ids);_ok(full,"build materials");_ok(Materials.validate(full.overlay),"build overlay");_assert(full.overlay.ready,"build ready");_assert(int(full.overlay.summary.missing_count)==0,"build missing")
 var required_id=String(plan.stages[0].material_allocations[0].item_instance_id);ids.erase(required_id);var partial=Materials.from_build_plan(plan,ids);_assert(not partial.overlay.ready,"partial not ready");_assert(int(partial.overlay.summary.missing_count)>0,"partial missing")
 var repair=Materials.from_repair_ghost(Fixture.repair_ghost());_ok(repair,"repair materials");_ok(Materials.validate(repair.overlay),"repair overlay");_assert(not repair.overlay.ready,"repair not ready");_assert(int(repair.overlay.summary.required_count)==2,"repair count");_assert(int(repair.overlay.summary.missing_count)==1,"repair missing")
 var bad=repair.overlay.duplicate(true);bad.ready=true;bad.checksum=Materials.compute_checksum(bad);_err(Materials.validate(bad),"CONSTRUCTION_MATERIAL_OVERLAY_SUMMARY_MISMATCH","summary")
func _ok(r,m):_assert(bool(r.get("success",false)),"%s: %s"%[m,r])
func _err(r,c,m):_assert(not bool(r.get("success",false)) and String(r.get("error_code",""))==c,"%s: %s"%[m,r])
func _assert(v,m):assertions+=1;if not v:failures.append(m)
func _finish():
 if failures.is_empty():print("C16 interaction UX contracts: PASS (%d assertions)"%assertions);quit(0);return
 for f in failures:push_error(f)
 print("C16 interaction UX contracts: FAIL (%d failures, %d assertions)"%[failures.size(),assertions]);quit(1)
