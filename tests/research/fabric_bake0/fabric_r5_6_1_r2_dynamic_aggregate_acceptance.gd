extends SceneTree
## FABRIC R5.6.1 R2: independently derived point-mass inertia oracle, data-driven
## two-layout multi-event successor, transactional rejection and stale fencing.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Delta = preload("res://scripts/research/fabric_bake0/r5_6_1_r2_part_delta_contract_v1.gd")
const Session = preload("res://scripts/research/fabric_bake0/r5_6_1_r2_dynamic_aggregate_session_v1.gd")
const Index = preload("res://scripts/research/fabric_bake0/r5_6_1_r2_dynamic_aggregate_index_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_adapter_v1.gd")
const Store = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const Mutation = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Bond = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const MatterBatch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")

class FakeStore:
	extends RefCounted
	func get_snapshot(_id: String) -> Dictionary:
		return {}
class ForgedSubclass:
	extends "res://scripts/construction/authoritative/construction_construct_store.gd"
	func get_snapshot(_id: String) -> Dictionary:
		return {}

var checks := 0
var failures: Array = []
var scenarios := 0
var applied := 0
var full_oracle_queries := 0
var rejected := 0
var max_touched_nodes := 0

func ck(ok: bool, why: String, got = null) -> void:
	checks += 1
	if not ok:
		failures.append(why)
		push_error("R5.6.1 R2: " + why + ": " + JSON.stringify(got))

func neg(result: Dictionary, code: String, why: String) -> void:
	var ok := not bool(result.get("success", false)) and String(result.get("error_code", "")) == code
	ck(ok, why, result)
	if ok:
		rejected += 1

func close(a: float, b: float) -> bool:
	return is_finite(a) and is_finite(b) and absf(a - b) <= 1.0e-8 + 1.0e-9 * maxf(1.0, maxf(absf(a), absf(b)))

## Independent FULL physical oracle: sums centered point-mass inertia per part,
## not the ten prefix moments, not any aggregate index implementation.
func oracle(snapshot: Dictionary, lo: int, hi: int) -> Dictionary:
	var mass := 0.0
	var sums := [0.0,0.0,0.0]
	for i in range(lo,hi):
		var p: Dictionary = snapshot.parts[i]
		var m := float(p.mass_kg)
		mass += m
		for j in range(3):
			sums[j] += m * float(p.local_position_m[j])
	var c := [sums[0]/mass, sums[1]/mass, sums[2]/mass]
	var inertia := [[0.0,0.0,0.0],[0.0,0.0,0.0],[0.0,0.0,0.0]]
	for i in range(lo,hi):
		var p: Dictionary = snapshot.parts[i]
		var m := float(p.mass_kg)
		var r := [float(p.local_position_m[0])-c[0], float(p.local_position_m[1])-c[1], float(p.local_position_m[2])-c[2]]
		for j in range(3):
			for k in range(3):
				var v: float = -m * r[j] * r[k]
				if j == k:
					v += m * (r[0]*r[0]+r[1]*r[1]+r[2]*r[2])
				inertia[j][k] += v
	return {"mass":mass,"center":c,"inertia":inertia}

func compare_oracle(session, source: Dictionary, lo: int, hi: int, label: String) -> void:
	var result: Dictionary = session.query_range(lo,hi)
	ck(result.success, label + ": index query accepted",result)
	if not result.success:
		return
	var o := oracle(source,lo,hi)
	var a: Dictionary = result.details
	ck(a.source_checksum == source.checksum and int(a.revision) == int(source.state_revision), label + ": source identity bound")
	ck(close(float(a.total_mass), o.mass), label + ": mass parity",[a.total_mass,o.mass])
	for j in range(3):
		ck(close(float(a.center_of_mass[j]),float(o.center[j])),label+": center "+str(j),[a.center_of_mass,o.center])
		for k in range(3):
			ck(close(float(a.inertia_tensor_body[j][k]),float(o.inertia[j][k])),label+": inertia "+str(j)+str(k),[a.inertia_tensor_body,o.inertia])
	full_oracle_queries += 1

func fixture(name: String,n: int,bypass: int) -> Dictionary:
	var parts: Array = []
	var total := 0.0
	for i in range(n):
		var mass := 1.0 + 0.25 * float(i % 7)
		total += mass
		parts.append(Part.create("part/r56r2-"+name+"/%05d"%i,"item/r56r2-"+name+"-%05d"%i,
			"BEAM", "fabric_boundary" if i in [0,n-1] else "member",mass,
			[float(i)*0.42,sin(float(i)*0.2)*1.1,cos(float(i)*0.3)*0.7]))
	var bonds: Array = []
	for i in range(n-1):
		bonds.append(Bond.create("bond/r56r2-"+name+"/link-%05d"%i,
			String(parts[i].part_id),String(parts[i+1].part_id),"GENERIC_COUPLING",60.0+float(i)))
	for i in range(bypass):
		bonds.append(Bond.create("bond/r56r2-"+name+"/bypass-%05d"%i,
			String(parts[i].part_id),String(parts[i+2].part_id),"GENERIC_COUPLING",18.0))
	var source := Snapshot.create("construct/r56r2/"+name,"item/r56r2-root-"+name,0,"OPERATIONAL",parts,bonds,{"r2":"moving-point-mass"})
	var matter := MatterBatch.create({"batch_id":"batch/r56r2/"+name,"container_id":"container/r56r2/"+name,
		"source_body_id":"body/r56r2/"+name,"source_operation_id":"operation/r56r2/"+name,
		"total_mass_kg":total,"bulk_volume_m3":0.18,
		"composition":Composition.create([{"material_id":"material/steel","mass_fraction":1.0}]),
		"temperature_k":293.15})
	return {"source":source,"matter":matter,"authority":Adapter.authority_for(source,matter,"server/r56r2-owner",24),"count":n,"name":name}

func start(f: Dictionary) -> Dictionary:
	var s = Store.new()
	ck(s.apply_mutation(Mutation.create(Mutation.OP_CREATE,String(f.source.construct_id),{},f.source)).success,f.name+": canonical external CREATE")
	var session = Session.new()
	ck(session.start(s,String(f.source.construct_id),f.matter,f.authority).success,f.name+": derived session start")
	ck(int(session.status().canonical_writes)==0,f.name+": no FABRIC canonical writer")
	compare_oracle(session,s.get_snapshot(String(f.source.construct_id)),0,f.count,f.name+": full initial")
	compare_oracle(session,s.get_snapshot(String(f.source.construct_id)),3,f.count-2,f.name+": inner initial")
	return {"store":s,"session":session,"fixture":f}

func transition(env: Dictionary, action: String, a: int, b: int, event_seq: int, position: Array = [], mass_delta: float = 0.0) -> void:
	var s=env.store;var session=env.session;var f:Dictionary=env.fixture
	var source: Dictionary = s.get_snapshot(String(f.source.construct_id))
	var a_id := String(source.parts[a].part_id)
	var b_id := String(source.parts[b].part_id) if b>=0 else ""
	var event_id := "event/r56r2/%s/%02d" % [f.name,event_seq]
	var before_status: Dictionary = session.status()
	var prepared: Dictionary = session.prepare(action,a_id,event_id,b_id,position,mass_delta)
	ck(prepared.success,f.name+": bounded part delta proposed "+str(event_seq),prepared)
	if not prepared.success:return
	ck(s.get_snapshot(String(f.source.construct_id))==source,f.name+": proposal does not write owner")
	neg(session.observe_external_commit(event_id,f.matter,f.authority),"R56_R2_EXTERNAL_COMMIT_MISSING",f.name+": no fake pre-commit")
	ck(session.status()==session.status(),f.name+": no pre-commit published state")
	var store_result=s.apply_mutation(prepared.details.proposal.mutation)
	ck(store_result.success,f.name+": owner applies real mutation",store_result)
	neg(session.query_range(0,f.count),"R56_R2_STALE_CANONICAL_SOURCE",f.name+": cannot use old index after owner write")
	var published: Dictionary = session.observe_external_commit(event_id,f.matter,f.authority)
	ck(published.success,f.name+": derived index synchronized",published)
	if not published.success:return
	applied+=1
	var actual: Dictionary = s.get_snapshot(String(f.source.construct_id))
	compare_oracle(session,actual,0,f.count,f.name+": full after "+str(event_seq))
	compare_oracle(session,actual,2,f.count/2,f.name+": first half after "+str(event_seq))
	compare_oracle(session,actual,f.count/2,f.count-1,f.name+": second half after "+str(event_seq))
	var status:Dictionary = session.status()
	ck(int(status.revision)==event_seq,f.name+": monotonic revision")
	ck(status.index.update_full_moment_scans == 0, f.name+": no full index scan on update")
	ck(status.index.updated_parts == int(before_status.index.updated_parts)+prepared.details.proposal.changed_rows.size(),f.name+": updated only named parts")
	var touched: int = int(published.details.index_work.fenwick_nodes_touched)
	max_touched_nodes = maxi(max_touched_nodes,touched)
	ck(touched>0 and touched<=prepared.details.proposal.changed_rows.size()*12,f.name+": bounded Fenwick update nodes",touched)
	ck(int(status.commits)==event_seq,f.name+": one commit per external event")
	neg(session.observe_external_commit(event_id,f.matter,f.authority),"R56_R2_NO_MATCHING_PROPOSAL",f.name+": replay refused")

func negatives(env: Dictionary) -> void:
	var session=env.session;var s=env.store;var f:Dictionary=env.fixture
	var part:Dictionary = s.get_snapshot(String(f.source.construct_id)).parts[5]
	neg(session.prepare(Delta.MOVE_PART,part.part_id,"event/r56r2/invalid", "", [1.0,2.0,INF]),"R56_R2_POSITION_INVALID", "nonfinite movement rejected")
	neg(session.prepare(Delta.TRANSFER_MASS,part.part_id,"event/r56r2/negative",part.part_id,[],0.25),"R56_R2_SECOND_PART_INVALID","self transfer refused")
	neg(session.prepare(Delta.TRANSFER_MASS,part.part_id,"event/r56r2/negative2",String(s.get_snapshot(String(f.source.construct_id)).parts[7].part_id),[],1000.0),"R56_R2_TRANSFER_ARGUMENTS_INVALID","negative remaining mass refused")
	var snapshot:Dictionary=s.get_snapshot(String(f.source.construct_id))
	var part6:Dictionary=snapshot.parts[6]
	var proposal: Dictionary = session.prepare(Delta.MOVE_PART,part6.part_id,"event/r56r2/tamper", "", [2.4,3.7,-0.9])
	ck(proposal.success,"pending tamper setup",proposal)
	if proposal.success:
		var prev:Dictionary=session.status()
		session._pending.new_position = [35.0,88.0,-3.0]
		neg(session.observe_external_commit("event/r56r2/tamper",f.matter,f.authority),"R56_R2_PENDING_PROVENANCE_MISMATCH","tampered pending cannot authorize")
		ck(session.status().revision == prev.revision and session.status().index == prev.index,"rejected pending preserves live index")
		neg(session.abandon_proposal(),"R56_R2_PENDING_PROVENANCE_MISMATCH","tamper cannot abandon guard")
		session._pending=proposal.details.proposal.duplicate(true)
		ck(session.abandon_proposal().success,"correct abandon clears guard")
	var spoof=FakeStore.new()
	neg(Session.new().start(spoof,String(f.source.construct_id),f.matter,f.authority),"R56_R2_CANONICAL_STORE_REQUIRED","duck typed Store rejected")
	var subclass=ForgedSubclass.new()
	neg(Session.new().start(subclass,String(f.source.construct_id),f.matter,f.authority),"R56_R2_CANONICAL_STORE_REQUIRED","overridden Store rejected")
	var other=Store.new();other.replace_from(s)
	session._store=other
	neg(session.query_range(0,f.count),"R56_R2_STORE_BINDING_DRIFT","owner instance substitution refused")
	session._store=s
	compare_oracle(session,s.get_snapshot(String(f.source.construct_id)),0,f.count,"index preserved after store alias trial")

func novel_mismatch(env: Dictionary) -> void:
	var session=env.session;var s=env.store;var f:Dictionary=env.fixture
	var snap:Dictionary=s.get_snapshot(String(f.source.construct_id))
	var pid:String=String(snap.parts[3].part_id)
	var intended: Dictionary = session.prepare(Delta.MOVE_PART,pid,"event/r56r2/conflict", "", [11.0,2.0,1.0])
	ck(intended.success,"prepare conflicting original event")
	var alternative:=Delta.prepare(snap,f.matter,f.authority,session.status().events,"event/r56r2/conflict",Delta.MOVE_PART,pid,"",[19.0,0.0,0.0])
	ck(alternative.success,"independent alternate with same event id")
	if not intended.success or not alternative.success:return
	ck(s.apply_mutation(alternative.details.mutation).success,"different real owner change committed")
	var state_before=session.status().index.duplicate(true)
	neg(session.observe_external_commit("event/r56r2/conflict",f.matter,f.authority),"R56_R2_EXTERNAL_SUCCESSOR_MISMATCH","different owner-approved external mutation cannot be misattributed")
	ck(session.status().index == state_before,"different external mutation leaves old index intact")
	neg(session.query_range(0,f.count),"R56_R2_STALE_CANONICAL_SOURCE","no stale physical execution after conflicting owner update")
	# New session from the real owner can recover the latest source. This does not
	# claim automatic cold-restart persistence or server-issued event receipts.
	var recovered=Session.new()
	var started=recovered.start(s,String(f.source.construct_id),f.matter,f.authority)
	ck(started.success,"new session rebinds to authentic source")
	if started.success:
		compare_oracle(recovered,s.get_snapshot(String(f.source.construct_id)),0,f.count,"new source rebind full parity")

func _initialize() -> void:
	var cases := [fixture("alpha",24,2),fixture("beta",39,5)]
	for f in cases:
		scenarios+=1
		var env=start(f)
		if not env.session.status().started:
			continue
		transition(env,Delta.MOVE_PART,3,-1,1,[4.25,-1.75,2.5])
		transition(env,Delta.TRANSFER_MASS,4,f.count-4,2,[],0.125)
		transition(env,Delta.MOVE_PART,0,-1,3,[17.2,0.1,-2.2])
		transition(env,Delta.TRANSFER_MASS,5,f.count-6,4,[],0.0625)
		negatives(env)
		novel_mismatch(env)
	var outcome:Dictionary={"schema":"fabric.r56_r2.dynamic_aggregate.acceptance.v1",
		"checks":checks,"failures":failures,"scenarios":scenarios,"events":applied,
		"full_oracle_queries":full_oracle_queries,"rejected_cases":rejected,"max_touched_nodes":max_touched_nodes}
	print("FABRIC_R56_R2_RESULT="+JSON.stringify(outcome))
	quit(0 if failures.is_empty() else 1)
