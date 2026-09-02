extends SceneTree
const F=preload("res://scripts/research/fabric0/fabric0_unified_adaptive_3d_contact_graph_v1.gd")
const E=preload("res://scripts/research/fabric0/fabric0_unified_adaptive_3d_contact_graph_experiments_v1.gd")
func close(a:float,b:float,t:float=1e-10)->bool:return absf(a-b)<=t
func max_event_error(run:Dictionary,ref:Array)->float:
 var m:=0.0;var ev:Array=run.world.events
 for i in range(ref.size()):m=maxf(m,absf(float(ev[i].time)-float(ref[i])))
 return m
func max_state_error(run:Dictionary,ref:Array)->float:
 var m:=0.0
 for i in range(ref.size()):
  m=maxf(m,absf(float(run.world.state[i])-float(ref[i])))
 return m
func _init():
 var checks:=0
 var ultra=E.run(1e-12,0.7);checks+=1;assert(ultra.world.events.size()==3);checks+=1
 var ref_times=[];for ev in ultra.world.events:ref_times.append(float(ev.time))
 var ref_state:Array=ultra.world.state.duplicate(true)
 var coarse=E.run(1e-7,0.7);var fine=E.run(1e-9,0.7);var finer=E.run(1e-11,0.7)
 for run in [coarse,fine,finer]:assert(bool(run.result.ok));checks+=1;assert(run.world.events.size()==3);checks+=1
 var e1=max_event_error(coarse,ref_times);var e2=max_event_error(fine,ref_times);var e3=max_event_error(finer,ref_times)
 assert(e2<e1);checks+=1;assert(e3<e2);checks+=1;assert(e1<1e-7);checks+=1;assert(e2<4e-9);checks+=1;assert(e3<7e-11);checks+=1
 var s1=max_state_error(coarse,ref_state);var s2=max_state_error(fine,ref_state);var s3=max_state_error(finer,ref_state)
 assert(s2<s1);checks+=1;assert(s3<s2);checks+=1;assert(s3<1e-9);checks+=1
 var w:Dictionary=fine.world;var r:Dictionary=fine.result
 assert(close(float(w.time),0.7,1e-12));checks+=1
 assert(int(r.accepted_steps)==37);checks+=1;assert(int(r.rejected_steps)==1);checks+=1
 assert(close(float(w.events[0].time),0.12770032218309,2e-14));checks+=1
 assert(close(float(w.events[1].time),0.15171711003539,2e-14));checks+=1
 assert(close(float(w.events[2].time),0.58519759521384,2e-14));checks+=1
 var impact:Dictionary=w.events[0]
 assert(String(impact.kind)=="CONTACT_APPEAR");checks+=1
 assert(impact.appeared==["pair:B|C|edge:back_bottom"]);checks+=1
 assert(impact.persisted==["floor|A","pair:A|B"]);checks+=1
 assert(impact.island_before==["A","B"]);checks+=1;assert(impact.island_after==["A","B","C"]);checks+=1
 assert(int(impact.point_count)==2);checks+=1
 assert(close(float(impact.old_force_preserved["floor|A"]),19.62,1e-12));checks+=1
 assert(close(float(impact.old_force_preserved["pair:A|B"]),9.81,1e-12));checks+=1
 for idx in [1,2]:
  var ev:Dictionary=w.events[idx]
  assert(String(ev.kind)=="MANIFOLD_FIXED_POINT");checks+=1;assert(bool(ev.fixed_point));checks+=1
  assert(int(ev.iterations)==3);checks+=1;assert(int(ev.topology_mutations)==2);checks+=1;assert(ev.transitions.size()==2);checks+=1
  assert(int(ev.transitions[0].point_count_before)==2);checks+=1;assert(int(ev.transitions[0].point_count_after)==4);checks+=1
  assert(int(ev.transitions[1].point_count_before)==4);checks+=1;assert(int(ev.transitions[1].point_count_after)==2);checks+=1
  assert(close(float(ev.warm_force_before),float(ev.warm_force_after),1e-12));checks+=1
  assert(close(float(ev.warm_impulse_before),float(ev.warm_impulse_after),1e-12));checks+=1
 assert(String(w.events[1].transitions[0].old)=="pair:B|C|edge:back_bottom");checks+=1
 assert(String(w.events[1].transitions[0].new)=="pair:B|C|face:bottom");checks+=1
 assert(String(w.events[1].transitions[1].new)=="pair:B|C|edge:front_bottom");checks+=1
 assert(String(w.events[2].transitions[0].old)=="pair:B|C|edge:front_bottom");checks+=1
 assert(String(w.events[2].transitions[1].new)=="pair:B|C|edge:back_bottom");checks+=1
 assert(F.current_contact_ids(w)==["floor|A","pair:A|B","pair:B|C|edge:back_bottom"]);checks+=1
 assert(absf(F.free_support_gap(w,w.state))<=1e-12);checks+=1
 assert(float(r.max_constraint_residual)<=2e-14);checks+=1
 assert(float(w.min_contact_force)>2.9);checks+=1
 assert(int(r.pattern_misses)==2);checks+=1;assert(int(r.pattern_hits)==36);checks+=1
 assert(int(r.pcg_calls)==38);checks+=1;assert(int(r.pcg_iterations)==95);checks+=1
 assert(close(float(w.warm_force["floor|A"]),26.5710523718944,1e-11));checks+=1
 assert(close(float(w.warm_force["pair:A|B"]),16.7610523718944,1e-11));checks+=1
 assert(close(float(w.warm_force["pair:B|C|edge:back_bottom"]),6.95105237189441,1e-11));checks+=1
 var qa=F.quaternion_audit(w);assert(close(float(qa.length),1.0,1e-14));checks+=1
 assert(close(float(qa.y),0.0,1e-15));checks+=1;assert(close(float(qa.z),0.0,1e-15));checks+=1
 assert(String(r.state_hash)=="f486303b7f133d28148d63362ad368d82e946132f2a12f9c164ae5edc2819483");checks+=1
 var replay=E.run(1e-9,0.7);assert(String(replay.result.state_hash)==String(r.state_hash));checks+=1
 assert(JSON.stringify(replay.world.events)==JSON.stringify(w.events));checks+=1
 var physical_hash_before=F.world_hash(w);var p=F.parallel_island_snapshot(w,false);var q=F.parallel_island_snapshot(w,true)
 assert(bool(p.ok) and bool(q.ok));checks+=1;assert(int(p.threads_started)==2 and int(q.threads_started)==2);checks+=1
 assert(String(p.hash)=="6ef3fd35474a179a7bf02675d5bde9ecb457f235fdb7cc70f017a69757f92757");checks+=1
 assert(String(q.hash)==String(p.hash));checks+=1
 assert(p.results[0].id=="island:A" and p.results[1].id=="island:D");checks+=1
 assert(int(p.results[0].iterations)==3);checks+=1;assert(int(p.results[1].iterations)==2);checks+=1
 assert(close(float(p.results[0].x[0]),26.5710523718944,1e-11));checks+=1
 assert(close(float(p.results[0].x[1]),16.7610523718944,1e-11));checks+=1
 assert(close(float(p.results[0].x[2]),6.95105237189441,1e-11));checks+=1
 assert(close(float(p.results[1].x[0]),19.62,1e-12));checks+=1;assert(close(float(p.results[1].x[1]),9.81,1e-12));checks+=1
 assert(F.world_hash(w)==physical_hash_before);checks+=1
 var tracker=F.new_sleep_tracker();var a=F.update_sleep(tracker,"island:A",0,0);var b=F.update_sleep(tracker,"island:A",0,0);var c=F.update_sleep(tracker,"island:A",0,0);var d=F.update_sleep(tracker,"island:A",1,0)
 assert(not bool(a.sleeping) and not bool(b.sleeping));checks+=1;assert(bool(c.sleeping) and bool(c.slept));checks+=1;assert(bool(d.woke) and not bool(d.sleeping));checks+=1
 assert(F.world_hash(w)==physical_hash_before);checks+=1
 var bad=F.new_world();var badr=F.advance_adaptive(bad,0.1,{"atol":0.0});assert(not bool(badr.ok));checks+=1;assert(String(badr.code)=="BAD_ADAPTIVE_OPTIONS");checks+=1
 var cache={"entries":{},"hits":0,"misses":0};var badprep=F._prepare_pattern(cache,"bad",[{0:0.0}],true);assert(not bool(badprep.ok));checks+=1;assert(String(badprep.code)=="PATTERN_NONPOSITIVE_DIAGONAL");checks+=1
 print("FABRIC0.13 Unified Adaptive 3D Contact Graph Acceptance: PASS (%d assertions) events=(%.12f,%.12f,%.12f) refine=(%s,%s,%s) state_refine=(%s,%s,%s) steps=%d/%d pcg=%d/%d pattern=%d/%d parallel=%s hash=%s" % [checks,float(w.events[0].time),float(w.events[1].time),float(w.events[2].time),String.num_scientific(e1),String.num_scientific(e2),String.num_scientific(e3),String.num_scientific(s1),String.num_scientific(s2),String.num_scientific(s3),int(r.accepted_steps),int(r.rejected_steps),int(r.pcg_calls),int(r.pcg_iterations),int(r.pattern_hits),int(r.pattern_misses),String(p.hash),String(r.state_hash)])
 quit(0)
