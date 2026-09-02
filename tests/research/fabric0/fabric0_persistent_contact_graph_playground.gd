extends SceneTree
const Fabric=preload("res://scripts/research/fabric0/fabric0_persistent_contact_graph_v1.gd")
const E=preload("res://scripts/research/fabric0/fabric0_persistent_contact_graph_experiments_v1.gd")
func _init():
 var run=E.run_sequence()
 print("=== FABRIC0.10 PERSISTENT CONTACT GRAPH + SPARSE HYBRID CONTACT STEP ===")
 for i in range(run["results"].size()):
  var r=run["results"][i]
  print("[%d] islands=%d iterations=%d warm=%d life +%s =%s -%s" % [i,r["solver_stats"]["island_count"],r["solver_stats"]["iterations"],r["solver_stats"]["warm_start_contacts"],str(r["lifecycle"]["appeared"]),str(r["lifecycle"]["persisted"]),str(r["lifecycle"]["disappeared"])])
  for island in r["islands"]:
   print("    %s bodies=%s contacts=%s sparseA=%d/%d it=%d warm=%d" % [island["island_id"],str(island["body_ids"]),str(island["contact_ids"]),island["sparse_effective_mass_entries"],island["dense_effective_mass_capacity"],island["iterations"],island["warm_start_contacts"]])
 print("\nresting stack A p=%s v=%s B p=%s v=%s" % [str(run["world"]["bodies"]["A"]["position"]),str(run["world"]["bodies"]["A"]["linear_velocity"]),str(run["world"]["bodies"]["B"]["position"]),str(run["world"]["bodies"]["B"]["linear_velocity"])])
 var rev=E.run_sequence(true,true)
 print("order invariant hash=%s / %s identical=%s" % [run["hash"],rev["hash"],str(run["hash"]==rev["hash"])])
 var fall=Fabric.new_world(Vector3(0,-9.81,0)); Fabric.add_body(fall,Fabric.new_sphere_body("fall",1.0,0.5,Vector3(0,2,0),Vector3(0,-1,0)))
 var ev=Fabric.advance_contact_free_to_first_plane_event(fall,E.floor_planes(),1.0,{"rho":0.2,"tolerance":1e-9,"max_iterations":10000})
 print("event bridge t=%.12f appeared=%s final_p=%s final_v=%s" % [ev["event_time"],str(ev["event_contact_ids"]),str(fall["bodies"]["fall"]["position"]),str(fall["bodies"]["fall"]["linear_velocity"])])
 print("\nFABRIC0_10_PERSISTENT_CONTACT_GRAPH_PLAYGROUND_PASS")
 quit(0)
