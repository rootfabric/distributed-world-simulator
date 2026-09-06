extends SceneTree
const Source = preload("res://scripts/research/fabric_bake0/complex3_streaming_canonical_structure_v1.gd")
const Life = preload("res://scripts/research/fabric_bake0/complex3_sparse_damage_lifecycle_v1.gd")
const Ownership = preload("res://scripts/research/fabric_bake0/mixed_representation_ownership_contract_v1.gd")
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
    checks+=1
    if not ok: failed=true; push_error("COMPLEX3-SCALE: "+label)
func now_us()->int: return Time.get_ticks_usec()
func mem_bytes()->int: return int(Performance.get_monitor(Performance.MEMORY_STATIC))
func fingerprint(run:Object)->Dictionary:
    var s:Dictionary=run.status()
    return {"mode":s.mode,"writer":s.writer,"transition_count":s.transition_count,"transition_hash":s.transition_hash,
        "active_full_parts":s.active_full_parts,"active_reduced_bodies":s.active_reduced_bodies,
        "applied_events":s.applied_events,"work":s.work,"source_checksum":s.source_checksum}
func _initialize()->void:
    var count:=5000
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--count="): count=int(arg.get_slice("=",1))
    check(Source.ALLOWED_COUNTS.has(count),"authorized count")
    if failed: quit(1); return
    var observation:Dictionary={"parts":count,"memory_before":mem_bytes()}
    var t:=now_us(); var base:=Source.create_subject(count,false); observation.source_base_ms=float(now_us()-t)/1000.0
    check(base.success and Source.validate_subject(base,false).success,"base canonical source")
    var canonical_before:=U.canonical_hash(base)
    t=now_us(); var parent:=Source.aggregate_span(base.spec,0,count); observation.parent_aggregate_ms=float(now_us()-t)/1000.0
    check(parent.success and int(parent.details.parts_scanned)==count,"parent aggregate")
    observation.memory_after_parent=mem_bytes()
    var state:=Source.reference_state(); var run:=Life.new(); t=now_us()
    check(run.start_baked(base,parent.details.descriptor,state).success,"start certified bake"); observation.start_ms=float(now_us()-t)/1000.0
    check(run.execute_boundary(base).success,"bake executable")
    var initial:=run.status(); check(Ownership.validate(initial.ownership).success,"initial single-owner contract")
    check(initial.active_full_parts==0 and initial.active_reduced_bodies==1,"initial sparse bake")
    check(not run.local_unbake(1,10.0).success,"sub-threshold guard rejected")
    t=now_us(); var local:=run.local_unbake(1,Life.IMPACT_LOAD); observation.local_unbake_ms=float(now_us()-t)/1000.0
    check(local.success,"certified local unbake")
    if not local.success: print(local); quit(1); return
    var ls:=run.status(); observation.memory_during_local=mem_bytes()
    check(ls.active_full_parts==Source.REGION_SIZE and ls.active_reduced_bodies==2,"20 FULL plus two residuals")
    check(ls.work.local_reconstructed_parts==Source.REGION_SIZE and ls.work.active_full_peak==Source.REGION_SIZE,"bounded physical reveal")
    check(ls.work.global_physical_rebuilds==0 and ls.work.duplicate_ownership_count==0,"no global rebuild or duplicate owner")
    check(Ownership.validate(ls.ownership).success,"local ownership contract")
    check(float(local.details.continuity.boundary_error)<1.0e-8,"boundary continuity")
    var local_cap:=run.capture_capsule(); check(local_cap.success,"local capsule")
    var local_hash:=U.canonical_hash(fingerprint(run)); var restarted:=Life.new()
    check(restarted.restore_capsule(base,local_cap.details.capsule).success,"local restart")
    check(U.canonical_hash(fingerprint(restarted))==local_hash,"local restart exact")
    run=restarted
    t=now_us(); var successor:=Source.create_subject(count,true); observation.source_successor_ms=float(now_us()-t)/1000.0
    check(successor.success and Source.is_successor(base,successor),"external canonical successor")
    var event_id:="topology-event/complex3-%06d-break"%count
    var old_writer:String=run.status().writer
    t=now_us(); var observed:=run.observe_canonical_break(successor,event_id,2); observation.fence_ms=float(now_us()-t)/1000.0
    check(observed.success and observed.details.old_writer_fenced,"canonical mutation fences writer")
    check(old_writer!="" and run.status().writer=="","old writer revoked")
    check(not run.execute_boundary(base).success and not run.execute_boundary(successor).success,"no execution while mutation fenced")
    var fenced_cap:=run.capture_capsule(); check(fenced_cap.success and fenced_cap.details.capsule.phase=="MUTATION_FENCED","fenced capsule")
    var stale:=Life.new(); check(not stale.restore_capsule(base,fenced_cap.details.capsule).success,"fenced capsule cannot bind old source")
    var fenced:=Life.new(); check(fenced.restore_capsule(successor,fenced_cap.details.capsule).success,"fenced restart on successor")
    check(fenced.status().writer=="","fenced restart stays non-executable")
    check(not fenced.rebake_after_settle(false).success,"premature rebake rejected")
    t=now_us(); var rebaked:=fenced.rebake_after_settle(true); observation.rebake_ms=float(now_us()-t)/1000.0
    check(rebaked.success and rebaked.details.component_count==2,"settled rebake")
    if not rebaked.success: print(rebaked); quit(1); return
    var fs:=fenced.status(); observation.memory_after_rebake=mem_bytes()
    check(fs.mode=="REBAKED" and fs.active_full_parts==0 and fs.active_reduced_bodies==2,"final sparse representation")
    check(fs.transition_count==2 and fs.applied_events==[event_id],"exactly-once lifecycle")
    check(fs.work.metadata_parts_scanned==2*count-Source.REGION_SIZE,"declared O(N) metadata only")
    check(fs.work.rebake_local_validations==Source.REGION_SIZE and fs.work.rebaked_components==2,"bounded local rebake validation")
    check(fs.work.invalidated_artifacts==1 and fs.work.canonical_mutations_observed==1,"one invalidation and mutation")
    check(fs.work.global_physical_rebuilds==0 and fs.work.duplicate_ownership_count==0,"no global physical rebuild")
    check(Ownership.validate(fs.ownership).success,"final ownership contract")
    check(fenced.execute_boundary(successor).success and not fenced.execute_boundary(base).success,"only fresh source executes")
    var final_cap:=fenced.capture_capsule(); check(final_cap.success,"final capsule")
    var final_hash:=U.canonical_hash(fingerprint(fenced)); var final_restart:=Life.new()
    check(final_restart.restore_capsule(successor,final_cap.details.capsule).success,"final restart")
    check(U.canonical_hash(fingerprint(final_restart))==final_hash,"final restart exact")
    var corrupt:Dictionary=final_cap.details.capsule.duplicate(true); corrupt.work.actual_transitions+=1
    check(not Life.new().restore_capsule(successor,corrupt).success,"corrupt capsule rejected")
    check(U.canonical_hash(base)==canonical_before,"FABRIC did not mutate canonical source")
    var residual:Dictionary=final_cap.details.capsule.checkpoint.cell.payload.residual
    var component_counts:Array=[]; var component_hashes:Array=[]
    for key in residual:
        component_counts.append(int(residual[key].descriptor.part_count)); component_hashes.append(String(residual[key].descriptor.checksum))
    component_counts.sort(); component_hashes.sort()
    var deterministic:={"schema":"dws.fabric.complex3.scale_case.v1","parts":count,"base_source":base.spec.checksum,
        "successor_source":successor.spec.checksum,"parent_aggregate":parent.details.descriptor.checksum,"target_full_parts":Source.REGION_SIZE,
        "residual_bodies":2,"final_baked_bodies":2,"component_counts":component_counts,"component_hashes":component_hashes,
        "transition_count":fs.transition_count,"transition_hash":fs.transition_hash,"applied_events":fs.applied_events,"work":fs.work}
    observation.total_metadata_scans=count+int(fs.work.metadata_parts_scanned)
    observation.memory_peak=maxi(int(observation.memory_before),maxi(int(observation.memory_after_parent),maxi(int(observation.memory_during_local),int(observation.memory_after_rebake))))
    print("COMPLEX3_CASE="+JSON.stringify(deterministic))
    print("COMPLEX3_CASE_HASH="+U.canonical_hash(deterministic))
    print("COMPLEX3_OBSERVATION="+JSON.stringify(observation))
    if not failed: print("FABRIC COMPLEX3 SCALE CASE: PASS (%d assertions)"%checks)
    quit(1 if failed else 0)
