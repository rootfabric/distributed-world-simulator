extends SceneTree
const Fabric=preload("res://scripts/research/fabric0/fabric0_event_sparse_islands_v1.gd")
const E=preload("res://scripts/research/fabric0/fabric0_event_sparse_islands_experiments_v1.gd")
func _init():
 var r=E.run_impact_sequence(false,false,false)
 var e=r["event"]
 print("=== FABRIC0.11 GENERAL EVENT-LOCALIZED CONTACT ISLANDS + SPARSE BACKEND ===")
 print("existing contacts: ",e["start_contact_ids"])
 print("event t=%.12f (dt=%.12f probes=%d) appeared=%s" % [e["event_time"],e["event_dt"],e["localization_probes"],str(e["appeared"])])
 print("old gaps at event: ",e["old_contact_gap_audit"]," new gap: ",e["appeared_contact_gap_audit"])
 print("island: ",e["start_islands"]," -> ",e["event_islands"])
 print("same-time warm remap: ",e["warm_contacts_preserved"])
 var s=e["event_resolve"]["solver_stats"]
 print("sparse event solve: backend=%s A=%d/%d pcg_calls=%d pcg_iters=%d dense=%d" % [s["linear_backend"],s["sparse_effective_mass_entries"],s["dense_effective_mass_capacity"],s["pcg_calls"],s["pcg_iterations"],s["dense_materializations"]])
 print("remaining %.9f sec in %d constrained substeps, final positions A/B/C=%s / %s / %s" % [e["remaining_dt"],e["continuation"]["substeps"],str(r["world"]["bodies"]["A"]["position"]),str(r["world"]["bodies"]["B"]["position"]),str(r["world"]["bodies"]["C"]["position"])])
 var p=E.solve_two_stacks(false,false,false); var q=E.solve_two_stacks(true,true,true)
 print("independent-island schedule hash: %s / %s identical=%s" % [p["hash"],q["hash"],str(p["hash"]==q["hash"])])
 print("world hash: ",r["hash"])
 print("\nFABRIC0_11_EVENT_SPARSE_ISLANDS_PLAYGROUND_PASS")
 quit(0)
