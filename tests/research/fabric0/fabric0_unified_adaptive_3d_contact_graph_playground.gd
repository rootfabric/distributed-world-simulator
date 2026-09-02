extends SceneTree
const F=preload("res://scripts/research/fabric0/fabric0_unified_adaptive_3d_contact_graph_v1.gd")
const E=preload("res://scripts/research/fabric0/fabric0_unified_adaptive_3d_contact_graph_experiments_v1.gd")
func _init():
 var x=E.run(1e-9,0.7);var w=x.world;var r=x.result
 print("=== FABRIC0.13 UNIFIED ADAPTIVE 3D CONTACT GRAPH ===")
 for ev in w.events:print(ev.kind," t=",ev.time," ",ev)
 print("contacts=",F.current_contact_ids(w)," state=",w.state," quaternion=",F.quaternion_audit(w))
 print("sparse residual=",r.max_constraint_residual," pcg=",r.pcg_calls,"/",r.pcg_iterations," pattern=",r.pattern_hits,"/",r.pattern_misses)
 var p=F.parallel_island_snapshot(w,false);var q=F.parallel_island_snapshot(w,true);print("parallel threads=",p.threads_started," hash=",p.hash," reverse_identical=",p.hash==q.hash)
 print("state hash=",r.state_hash)
 print("FABRIC0_13_UNIFIED_ADAPTIVE_3D_CONTACT_GRAPH_PLAYGROUND_PASS")
 quit(0)
