extends SceneTree
const F=preload("res://scripts/research/fabric0/fabric0_adaptive_multievent_manifold_v1.gd")
const E=preload("res://scripts/research/fabric0/fabric0_adaptive_multievent_manifold_experiments_v1.gd")
func _init():
 var run=E.run_tolerance(1e-9); var s=run.system; var r=run.result
 print("=== FABRIC0.12 ADAPTIVE MULTI-EVENT MANIFOLD DAE ===")
 print("adaptive steps accepted=%d rejected=%d energy_drift=%s constraint_residual=%s" % [r.accepted_steps,r.rejected_steps,str(r.energy_drift),str(r.max_constraint_residual)])
 for ev in s.events:
  print("event %s t=%.12f dir=%d iterations=%d mutations=%d fixed=%s" % [ev.event_id,ev.time,ev.direction,ev.iterations,ev.topology_mutations,str(ev.fixed_point)])
  for tr in ev.transitions:
   print("    %s: -%s +%s warm=%s" % [tr.kind,str(tr.disappeared),str(tr.appeared),str(tr.warm_after)])
 var refs=F.analytic_zero_times(-0.3,1.2,4.0,1.2)
 print("analytic refs: ",refs)
 print("event errors: ",[abs(s.events[0].time-refs[0]),abs(s.events[1].time-refs[1])])
 var cache=F.new_pattern_cache(); var solver=F.new(); var tasks=E.parallel_tasks(1.0)
 var p=solver.solve_islands_parallel(tasks,cache,false); var q=solver.solve_islands_parallel(tasks,cache,true)
 print("parallel threads=%d cache cold=%d/%d warm=%d/%d hash identical=%s" % [p.threads_started,p.cache_hits,p.cache_misses,q.cache_hits,q.cache_misses,str(p.hash==q.hash)])
 var sleep=F.new_sleep_tracker(); F.update_sleep_state(sleep,"island:A",0,0); F.update_sleep_state(sleep,"island:A",0,0); var asleep=F.update_sleep_state(sleep,"island:A",0,0); var wake=F.update_sleep_state(sleep,"island:A",1,0)
 print("derived sleep=%s wake=%s" % [str(asleep.sleeping),str(wake.woke)])
 print("state hash: ",r.state_hash)
 print("parallel hash: ",p.hash)
 print("\nFABRIC0_12_ADAPTIVE_MULTIEVENT_MANIFOLD_PLAYGROUND_PASS")
 quit(0)
