extends SceneTree
const U=preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const C=preload("res://scripts/research/fabric_bake0/fabric1_component_contract_v1.gd")
const P=preload("res://scripts/research/fabric_bake0/fabric1_generalized_composer_v1.gd")
const G=preload("res://scripts/research/fabric_bake0/unseen_machine_generic_graph_v1.gd")
const K=preload("res://scripts/research/fabric_bake0/unseen_machine_generic_compiler_v1.gd")
const R=preload("res://scripts/research/fabric_bake0/fabric1_generalized_runtime_v1.gd")
const T:=2.0e-8
var n:=0; var bad:Array[String]=[]
func _initialize()->void:
 var s:=subject(); ok(not s.is_empty(),"independent public-contract subject")
 if s.is_empty(): return done()
 var q:Array=s.parts.duplicate(true); q.reverse()
 var reordered:=P.compose("machine/sync1-freeze",1,q,s.links,[])
 ok(bool(reordered.get("success",false)),"reordered components compose")
 if bool(reordered.get("success",false)): ok(reordered.details.spec.graph_hash==s.spec.graph_hash,"composition order invariant")
 var compiled:=K.compile(s.spec); ok(compiled.get("status","")=="BAKE_READY","automatic exact bake")
 if compiled.get("status","")=="BAKE_READY":
  var d:Dictionary=compiled.compile_result.diagnostics.reduction
  ok(int(d.reduced_equation_count)==4,"four boundary equations")
  ok(int(d.full_equation_count)>100 and float(d.runtime_work_ratio)>700.0,"meaningful reduction")
 lifecycle(s); replay_restart(s); done()
func lifecycle(s:Dictionary)->void:
 var r:=R.new(); ok(bool(r.start_baked(s.spec,0).get("success",false)),"start baked")
 if r.status().get("mode","")!="BAKED": return
 ok(int(r.status().canonical_writes)==0,"zero canonical writes")
 var b:=r.execute(s.x); ok(bool(b.get("success",false)),"baked execute")
 ok(bool(r.refine_to_full("SYNC1_GUARD",1).get("success",false)),"refine to full")
 var f:=r.execute(s.x); ok(bool(f.get("success",false)),"full execute")
 if bool(b.get("success",false)) and bool(f.get("success",false)):
  ok(delta(b.details.boundary_flow,f.details.boundary_flow)<=T,"BAKE/FULL flow parity")
  ok(absf(float(b.details.boundary_power)-float(f.details.boundary_power))<=T,"BAKE/FULL power parity")
 var next:=successor(s); ok(not next.is_empty(),"external canonical successor")
 if next.is_empty(): return
 var m:=r.apply_canonical_failure(next,s.event,[s.cut],2); ok(bool(m.get("success",false)),"observe canonical failure")
 if bool(m.get("success",false)): ok(m.details.stale_error=="STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN","stale bake fenced")
 ok(int(r.status().canonical_writes)==0,"mutation observation remains noncanonical")
 var after:=r.execute(s.x); ok(bool(after.get("success",false)),"successor full execute")
 ok(not bool(r.apply_canonical_failure(next,s.event,[s.cut],3).get("success",false)),"exactly-once event")
 ok(bool(r.rebake(3).get("success",false)),"successor rebakes")
 var rb:=r.execute(s.x); ok(bool(rb.get("success",false)),"rebaked execute")
 if bool(after.get("success",false)) and bool(rb.get("success",false)): ok(delta(after.details.boundary_flow,rb.details.boundary_flow)<=T,"successor FULL/BAKE parity")
func replay_restart(s:Dictionary)->void:
 var a:=run(s,10); var b:=run(s,10)
 ok(not a.is_empty() and not b.is_empty(),"twin lifecycle runs")
 ok(U.canonical_hash(a)==U.canonical_hash(b),"fresh lifecycle deterministic")
 var r:=R.new(); r.start_baked(s.spec,20); r.refine_to_full("SYNC1_RESTART",21)
 var next:=successor(s); r.apply_canonical_failure(next,s.event,[s.cut],22); r.rebake(23)
 var capr:=r.capture_capsule(); ok(bool(capr.get("success",false)),"capture derived capsule")
 if not bool(capr.get("success",false)): return
 var c:Dictionary=capr.details.capsule
 ok(c.canonical==false and c.derived==true and c.discardable==true,"capsule noncanonical derived disposable")
 var fresh:=R.new(); ok(bool(fresh.restore(next,c).get("success",false)),"restore from authoritative successor")
 ok(fresh.status().transition_hash==r.status().transition_hash,"restart transition identity")
 var stale:=R.new().restore(s.spec,c); ok(stale.get("error_code","")=="FABRIC1_CAPSULE_STALE","capsule cannot rewind source")
 var corrupt:=c.duplicate(true); corrupt.transition_count=int(corrupt.transition_count)+1
 ok(R.new().restore(next,corrupt).get("error_code","")=="FABRIC1_CAPSULE_CHECKSUM_INVALID","corrupt capsule fail closed")
 print("FABRIC1_SYNC1_ARCH_HASH=",U.canonical_hash({"a":a,"b":b,"capsule":c.checksum}))
func run(s:Dictionary,t:int)->Dictionary:
 var r:=R.new(); if not bool(r.start_baked(s.spec,t).get("success",false)): return {}
 if not bool(r.refine_to_full("SYNC1_REPLAY",t+1).get("success",false)): return {}
 var next:=successor(s); if not bool(r.apply_canonical_failure(next,s.event,[s.cut],t+2).get("success",false)): return {}
 if not bool(r.rebake(t+3).get("success",false)): return {}
 var e:=r.execute(s.y); return {"status":r.status(),"flow":e.get("details",{}).get("boundary_flow",[]),"power":e.get("details",{}).get("boundary_power",0.0)} if bool(e.get("success",false)) else {}
func subject()->Dictionary:
 var a:=part("a",["port/s1-a-in","port/s1-a-link"],52,1,false)
 var b:=part("b",["port/s1-b-link","port/s1-b-sense-a","port/s1-b-sense-b","port/s1-b-out"],54,3,true)
 if a.is_empty() or b.is_empty(): return {}
 var links:=[{"connector_id":"edge/s1-link-ab","port_a":"port/s1-a-link","port_b":"port/s1-b-link","conductance":0.91,"active":true}]
 var c:=P.compose("machine/sync1-freeze",1,[a,b],links,[]); if not bool(c.get("success",false)): return {}
 return {"parts":[a,b],"links":links,"spec":c.details.spec,"cut":"edge/s1-b-critical","event":"event/s1-output-loss","x":[8.0,0.0,0.0,0.0],"y":[1.0,-0.5,0.75,-0.25]}
func successor(s:Dictionary)->Dictionary:
 var es:Array=[]
 for raw in s.spec.edges:
  var e:Dictionary=Dictionary(raw).duplicate(true); if e.edge_id==s.cut: e.active=false
  es.append(e)
 return G.create(s.spec.machine_id,int(s.spec.revision)+1,s.spec.boundary_node_ids,s.spec.internal_node_ids,es,[s.event])
func part(label:String,ports:Array,w:int,salt:int,critical:bool)->Dictionary:
 var ns:Array=[]; for i in range(w): ns.append("node/s1-%s-%02d"%[label,i])
 var es:Array=[]
 for i in range(w-1): es.append(edge("edge/s1-%s-chain-%02d"%[label,i],ns[i],ns[i+1],0.8+0.01*float((i+salt)%9)))
 for p in range(ports.size()):
  var id:="edge/s1-%s-port-%02d"%[label,p]
  if critical and String(ports[p])=="port/s1-b-out": id="edge/s1-b-critical"
  es.append(edge(id,String(ports[p]),ns[(p*7+salt)%w],0.9+0.03*float((p+salt)%5)))
 return C.create("component/s1-%s"%label,ports,ns,es)
func edge(id:String,a:String,b:String,g:float)->Dictionary: return {"edge_id":id,"node_a":a,"node_b":b,"conductance":g,"active":true}
func delta(a:Array,b:Array)->float:
 if a.size()!=b.size(): return INF
 var d:=0.0; for i in range(a.size()): d=maxf(d,absf(float(a[i])-float(b[i])))
 return d
func ok(v:bool,label:String)->void: n+=1; if not v: bad.append(label)
func done()->void:
 if bad.is_empty(): print("FABRIC1-SYNC1 Independent Architecture: PASS (%d assertions)"%n); quit(0); return
 for x in bad: push_error("FABRIC1-SYNC1 FAIL: "+x)
 print("FABRIC1-SYNC1 Independent Architecture: FAIL (%d/%d)"%[bad.size(),n]); quit(1)
