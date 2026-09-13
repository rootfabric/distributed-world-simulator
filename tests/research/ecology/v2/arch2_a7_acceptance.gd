extends SceneTree
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Model = preload("res://scripts/research/ecology/v2/observatory_session_v1.gd")
const P = preload("res://scripts/research/ecology/v2/observatory_protocol_v1.gd")
var assertions := 0
var failed := 0
func check(ok: bool, label: String) -> void:
 assertions += 1
 if not ok:
  failed += 1
  print("FAIL: ",label)
func grow(t: Dictionary, steps: int):
 var m=Model.new()
 check(m.start(t),"start")
 for i in steps:
  if not m.advance(): check(false,"advance " + m.last_error); break
 return m
func study(site: Dictionary) -> Dictionary:
 for e in site.entries:
  if e.id=="study":return e
 return {}
func _initialize() -> void:
 var protocol=P.manifest()
 check(protocol.seeds==[20260912,104729,130363],"predeclared seeds")
 var parent=C.digest(P.ancestor())
 for seed in protocol.seeds:
  var main=grow(P.treatment(seed),5)
  var view=main.observe()
  check(view.success,"real observation")
  if not view.success: continue
  var wet=study(view.sites[0]);var dry=study(view.sites[1]);var dark=study(view.sites[2])
  check(wet.phenotype.statistics.module_count>dry.phenotype.statistics.module_count,"wet vs dry growth")
  check(wet.phenotype.statistics.module_count>dark.phenotype.statistics.module_count,"wet vs dark growth")
  check(wet.phenotype.genome_hash==dry.phenotype.genome_hash and wet.phenotype.genome_hash==dark.phenotype.genome_hash,"same genome across environments")
  check(view.founder_mutation.event.child_hash!=view.founder_mutation.event.parent_hash,"actual A3 mutation")
  check(view.founder_mutation.event.operator=="module_parameter","A3 operator")
  check(view.sites[0].corpses.size()==1 and view.sites[0].returned.organic_mg>0,"actual donor death and return")
  for site in view.sites:
   for key in ["material_mg","water_mg","energy_mj"]:
    check(site.balance.initial[key]+site.balance.external[key]==site.balance.current[key]+site.balance.sinks[key],"balance "+site.id+" "+key)
   for e in site.entries:
    check(e.phenotype.body_hash==C.digest(e.phenotype.representation.modules),"same body for metrics/render")
  var garden=grow(P.treatment(seed,true),5)
  var g=garden.observe()
  check(g.success,"garden observe")
  check(study(g.sites[0]).phenotype.body_hash==study(g.sites[1]).phenotype.body_hash and study(g.sites[1]).phenotype.body_hash==study(g.sites[2]).phenotype.body_hash,"common-garden equal body")
  check(g.sites[0].field.cells==g.sites[1].field.cells and g.sites[1].field.cells==g.sites[2].field.cells,"common-garden equal fields")
  var off=grow(P.treatment(seed,false,false),5)
  var no=off.observe()
  check(no.success,"effects-off observe")
  check(wet.ledger.field_intake.nutrient_mg>study(no.sites[0]).ledger.field_intake.nutrient_mg,"effects-off causal intake")
  check(no.sites[0].returned.organic_mg==0 and no.sites[0].mineralized_mg==0,"effects-off is actual A6 policy")
  var neutral=grow(P.treatment(seed,false,true,false),5)
  var n=neutral.observe()
  check(n.founder_mutation.event.parent_hash==n.founder_mutation.event.child_hash,"mutation-off exact neutrality")
  check(n.founder_mutation.event.operator=="none","mutation-off A3 none")
  check(n.step==view.step,"paired mutation-off horizon")
  check(parent==C.digest(P.ancestor()),"parent untouched")
  var before=main.source_hashes(); view.sites[0].entries[0].ledger.initial.material_mg+=1
  check(main.source_hashes()==before,"observation is deep copy")
  check(main.observe().success,"observation tamper does not affect source")
  var snapshot=main.save_text()
  check(not snapshot.is_empty(),"save canonical")
  var restored=Model.new()
  check(restored.load_text(snapshot,main.experiment_hash(),5),"anchored restore")
  check(restored.source_hashes()==main.source_hashes(),"restored source equality")
  check(main.advance() and restored.advance(),"both continue")
  check(main.source_hashes()==restored.source_hashes(),"restart equivalence")
  print("SEED_PASS ",seed," wet_modules=",wet.phenotype.statistics.module_count," dry_modules=",dry.phenotype.statistics.module_count," dark_modules=",dark.phenotype.statistics.module_count)
 _negative_controls()
 print("EVO_ARCH2_A7_EXACT assertions=%d failed=%d" %[assertions,failed])
 quit(1 if failed else 0)
func _negative_controls() -> void:
 var m=grow(P.treatment(),2)
 var text=m.save_text();var original=m.source_hashes();var anchor=m.experiment_hash()
 for bad in [P.treatment(1),{"seed":20260912,"common_garden":1,"effects_enabled":true,"mutations_enabled":true},{}]:
  check(not m.start(bad),"bad treatment rejected")
  check(m.source_hashes()==original,"bad start mutation free")
 check(not m.load_text(text,"0".repeat(64),2),"foreign experiment")
 check(not m.load_text(text,anchor,1),"stale revision")
 check(not m.load_text(" ",anchor,2),"invalid json")
 check(not m.load_text("x".repeat(C.MAX_BYTES+1),anchor,2),"byte budget")
 var d=C.decode(text).value
 var bad=d.duplicate(true);bad.sessions.erase("dark")
 check(not m.load_text(C.encode(bad),anchor,2),"missing site")
 bad=d.duplicate(true);bad.sessions.wet=d.sessions.dark
 check(not m.load_text(C.encode(bad),anchor,2),"site splice")
 bad=d.duplicate(true);bad.protocol_hash="0".repeat(64)
 check(not m.load_text(C.encode(bad),anchor,2),"wrong protocol")
 bad=d.duplicate(true);bad.treatment.effects_enabled=false
 check(not m.load_text(C.encode(bad),anchor,2),"treatment rebind")
 bad=d.duplicate(true);bad.extra=true
 check(not m.load_text(C.encode(bad),anchor,2),"unknown field")
 bad=d.duplicate(true)
 var s=C.decode(bad.sessions.dry).value
 s.frame.returned.organic_mg+=1;s.erase("integrity_hash");s["integrity_hash"]=C.digest(s)
 bad.sessions.dry=C.encode(s)
 check(not m.load_text(C.encode(bad),anchor,2),"coherent rehash fails replay")
 check(m.source_hashes()==original,"all failed restores atomic")
 m._sessions.dry.frame.returned.organic_mg+=1
 var state_before=C.encode(m._sessions)
 check(not m.advance(),"later-site failure")
 check(C.encode(m._sessions)==state_before,"all sites rollback")
 check(m.observe().get("success")==false,"invalid source not visualized")
 check(m.save_text().is_empty(),"invalid source not saved")
 var limit=grow(P.treatment(),16)
 var last=limit.source_hashes()
 check(not limit.advance() and limit.last_error=="A7_HORIZON_BUDGET","explicit horizon")
 check(limit.source_hashes()==last and limit.step_index()==16,"budget not biology")
 var report=C.decode(limit.export_report())
 check(report.success and report.value.step==16,"bounded source-bound export")
 check(report.value.scope=="FOUNDER_CONTROLS_NOT_MULTI_GENERATION_EVOLUTION","truth boundary")
 check(study(report.value.sites[0]).reproduction_count==report.value.sites[0].pending_propagules and report.value.sites[0].pending_propagules>0,"paid births retained in outbox")
 print("HORIZON_OBSERVATION modules=%d births=%d" % [study(report.value.sites[0]).phenotype.statistics.module_count,report.value.sites[0].pending_propagules])
