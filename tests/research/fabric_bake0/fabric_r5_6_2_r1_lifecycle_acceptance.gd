extends SceneTree
## R5.6.2 R1: mixed damage/pose/mass/repair, two layouts, 3 crash windows.
## FULL oracle uses direct centered sums, never the FABRIC Fenwick moments.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Life = preload("res://scripts/research/fabric_bake0/r5_6_2_r1_event_lifecycle_v1.gd")
const BondDelta = preload("res://scripts/research/fabric_bake0/r5_6_1_canonical_delta_contract_v1.gd")
const PartDelta = preload("res://scripts/research/fabric_bake0/r5_6_1_r2_part_delta_contract_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_adapter_v1.gd")
const Store = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const Mutation = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Bond = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const MatterBatch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")

var checks := 0
var failures: Array = []
var restarts := 0
var events := 0
var oracle_queries := 0
var disk_roundtrips := 0
var denied := 0

func ck(condition: bool, label: String, got = null) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("R562 R1 " + label + ": " + JSON.stringify(got))

func neg(result: Dictionary, code: String, label: String) -> void:
	var valid := not bool(result.get("success", false)) and String(result.get("error_code", "")) == code
	ck(valid, label, result)
	if valid:
		denied += 1

func fixture(label: String, n: int) -> Dictionary:
	var parts: Array = []
	var total_mass := 0.0
	for i in range(n):
		var mass: float = 1.0 + 0.125 * float(i % 5)
		total_mass += mass
		parts.append(Part.create("part/r562/%s/%04d" % [label,i],
			"item/r562/%s/%04d" % [label,i], "BEAM",
			"fabric_boundary" if i in [0, n-1] else "member", mass,
			[0.8*float(i), 0.17*float(i%7), -0.12*float(i%3)]))
	var bonds: Array = []
	for i in range(n-1):
		bonds.append(Bond.create("bond/r562/%s/%04d" % [label,i],
			String(parts[i].part_id), String(parts[i+1].part_id),
			"GENERIC_COUPLING", 50.0+float(i)))
	var source := Snapshot.create("construct/r562/"+label,"item/r562/root-"+label,
		0,"OPERATIONAL",parts,bonds,{"r562":"lifecycle"})
	var matter := MatterBatch.create({"batch_id":"batch/r562/"+label,
		"container_id":"container/r562/"+label,
		"source_body_id":"body/r562/"+label,
		"source_operation_id":"operation/r562/"+label,
		"total_mass_kg": total_mass,"bulk_volume_m3": 0.2,
		"composition":Composition.create([{"material_id":"material/steel","mass_fraction":1.0}]),
		"temperature_k":293.15})
	return {"name":label,"source":source,"matter":matter,
		"authority":Adapter.authority_for(source,matter,"server/r562-owner",25),
		"count":n}

func near(a: float,b: float) -> bool:
	return is_finite(a) and is_finite(b) and absf(a-b) < 1.0e-8 + 1.0e-9*maxf(absf(a),absf(b))

func oracle(session, snapshot: Dictionary, label: String) -> void:
	var n: int = snapshot.parts.size()
	var query: Dictionary = session.query_range(0,n)
	ck(query.success,label+": physical descriptor available",query)
	if not query.success:
		return
	var mass:=0.0
	var sums: Array = [0.0,0.0,0.0]
	for raw in snapshot.parts:
		var part: Dictionary = raw
		var m: float = float(part.mass_kg)
		mass += m
		for j in range(3):
			sums[j] += m * float(part.local_position_m[j])
	var com: Array = [sums[0]/mass,sums[1]/mass,sums[2]/mass]
	var inertia: Array = [[0.0,0.0,0.0],[0.0,0.0,0.0],[0.0,0.0,0.0]]
	for raw in snapshot.parts:
		var part: Dictionary = raw
		var v: Array = []
		for axis in range(3):
			v.append(float(part.local_position_m[axis])-float(com[axis]))
		var m: float = float(part.mass_kg)
		for j in range(3):
			for k in range(3):
				var term: float = -m*v[j]*v[k]
				if j==k:
					term += m*(v[0]*v[0]+v[1]*v[1]+v[2]*v[2])
				inertia[j][k] += term
	var desc: Dictionary = query.details
	ck(near(float(desc.total_mass),mass),label+": mass conservation")
	ck(String(desc.source_checksum)==String(snapshot.checksum) and \
		int(desc.revision)==int(snapshot.state_revision), label+": exact owner source identity")
	for j in range(3):
		ck(near(float(desc.center_of_mass[j]),float(com[j])),label+": COM "+str(j))
		for k in range(3):
			ck(near(float(desc.inertia_tensor_body[j][k]),float(inertia[j][k])),
				label+": I"+str(j)+str(k),[desc.inertia_tensor_body[j][k],inertia[j][k]])
	oracle_queries+=1

## FileAccess flush is a PROCESS-crash fixture; power-loss fsync and durability
## of the canonical owner transaction are deliberately NOT claimed here.
func disk_copy(value: Dictionary, label: String) -> Dictionary:
	var path := "user://fabric_r562_r1_"+label+"_"+str(disk_roundtrips)+".json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	ck(file != null,label+": open journal file")
	if file == null:
		return {}
	file.store_string(JSON.stringify(value))
	file.flush()
	file.close()
	var reader := FileAccess.open(path,FileAccess.READ)
	ck(reader != null,label+": read journal file")
	if reader == null:
		return {}
	var raw := reader.get_as_text()
	reader.close()
	var parsed = JSON.parse_string(raw)
	ck(typeof(parsed)==TYPE_DICTIONARY,label+": parsed durable journal",raw)
	disk_roundtrips+=1
	return parsed if typeof(parsed)==TYPE_DICTIONARY else {}

func rehydrate_store(store, label: String):
	var disk := disk_copy(store.to_dict(),label+"_owner")
	if disk.is_empty():
		return null
	var next_store = Store.new()
	var loaded: Dictionary = next_store.load_dict(disk)
	ck(loaded.success,label+": canonical owner cold load",loaded)
	return next_store if loaded.success else null

func fresh(f: Dictionary) -> Dictionary:
	var store=Store.new()
	ck(store.apply_mutation(Mutation.create(Mutation.OP_CREATE,
		String(f.source.construct_id),{},f.source)).success,f.name+": owner create")
	var session=Life.new()
	var initialized: Dictionary = session.bootstrap(store,String(f.source.construct_id),f.matter,f.authority)
	ck(initialized.success,f.name+": bootstrap",initialized)
	ck(int(session.status().canonical_writes)==0,f.name+": no FABRIC owner writes")
	if initialized.success:
		oracle(session,store.get_snapshot(String(f.source.construct_id)),f.name+": initial")
	return {"store":store,"session":session,"journal":initialized.details.journal if initialized.success else {},
		"f":f}

## Each event is interrupted before external commit, and again after owner
## commit but before ACK. The next process independently reconstructs intent.
func transition(env: Dictionary, kind: String, action: String, a: int, b: int,
		seq: int, pos: Array = [], mass_delta: float = 0.0) -> void:
	var f: Dictionary=env.f
	var store=env.store
	var session=env.session
	var source: Dictionary=store.get_snapshot(String(f.source.construct_id))
	var event_id := "event/r562/%s/%02d" % [f.name,seq]
	var prepared: Dictionary
	if kind==Life.BOND:
		prepared=session.prepare_bond(action,String(source.bonds[a].bond_id),event_id)
	else:
		prepared=session.prepare_part(action,String(source.parts[a].part_id),event_id,
			String(source.parts[b].part_id) if b>=0 else "",pos,mass_delta)
	ck(prepared.success,f.name+": proposed mixed event "+str(seq),prepared)
	if not prepared.success:
		return
	ck(source==store.get_snapshot(String(f.source.construct_id)),f.name+": prepare is read only")
	var durable_pending=disk_copy(prepared.details.journal,f.name+"_prepare")
	if durable_pending.is_empty():return
	ck(session.mark_prepared_durable(String(durable_pending.checksum)).success,
		f.name+": durable PREPARE barrier")
	neg(session.query_range(0,f.count),"R562_PHYSICS_NOT_READY",
		f.name+": physical execution blocked during prepare")
	var before_owner = rehydrate_store(store,f.name+"_before_"+str(seq))
	if before_owner == null:return
	store=before_owner
	env.store=store
	var before_restart=Life.new()
	var resumed: Dictionary=before_restart.recover(store,String(f.source.construct_id),
		f.matter,f.authority,durable_pending)
	ck(resumed.success,f.name+": restart BEFORE external commit",resumed)
	if not resumed.success:return
	restarts+=1
	ck(before_restart.status().mode=="PENDING_OWNER",f.name+": pending owner decision")
	neg(before_restart.make_ack_journal(),"R562_EXTERNAL_COMMIT_MISSING",
		f.name+": cannot fabricate a commit")
	var owner_commit: Dictionary=store.apply_mutation(prepared.details.owner_mutation)
	ck(owner_commit.success,f.name+": ConstructionStore exactly one accepted commit",owner_commit)
	if not owner_commit.success:return
	neg(store.apply_mutation(prepared.details.owner_mutation),"CONSTRUCT_STORE_UPDATE_PRECONDITION_FAILED",
		f.name+": canonical CAS prevents duplicate owner mutation")
	neg(before_restart.query_range(0,f.count),"R562_PHYSICS_NOT_READY",
		f.name+": stale old physical index is nonexecutable")
	var after_owner = rehydrate_store(store,f.name+"_after_"+str(seq))
	if after_owner == null:return
	store=after_owner
	env.store=store
	var after_restart=Life.new()
	var recovered: Dictionary=after_restart.recover(store,String(f.source.construct_id),
		f.matter,f.authority,durable_pending)
	ck(recovered.success,f.name+": restart AFTER owner commit",recovered)
	if not recovered.success:return
	restarts+=1
	ck(after_restart.status().mode=="OWNER_COMMITTED_PENDING_ACK",
		f.name+": recover unacknowledged owner commit")
	neg(after_restart.query_range(0,f.count),"R562_PHYSICS_NOT_READY",
		f.name+": not executable before ACK")
	var ack: Dictionary=after_restart.make_ack_journal()
	ck(ack.success,f.name+": deterministic external ACK candidate",ack)
	if not ack.success:return
	var durable_ack=disk_copy(ack.details.journal,f.name+"_ack")
	if durable_ack.is_empty():return
	ck(after_restart.adopt_persisted_ack(durable_ack).success,
		f.name+": publish only after ACK barrier")
	neg(after_restart.make_ack_journal(),"R562_ACK_PHASE_INVALID",
		f.name+": duplicate ACK refused")
	var next_session=Life.new()
	var restarted:Dictionary=next_session.recover(store,String(f.source.construct_id),
		f.matter,f.authority,durable_ack)
	ck(restarted.success,f.name+": fresh cold recovery from ACK",restarted)
	if not restarted.success:return
	restarts+=1
	ck(next_session.status().mode=="READY",f.name+": physics ready after ACK replay")
	ck(int(next_session.status().committed)==seq,f.name+": no duplicated events")
	ck(next_session.status().events.size()==seq,f.name+": exactly one derived event ID per owner revision")
	oracle(next_session,store.get_snapshot(String(f.source.construct_id)),
		f.name+": after event "+str(seq))
	ck(not next_session.prepare_bond(BondDelta.BREAK,
		String(store.get_snapshot(String(f.source.construct_id)).bonds[0].bond_id),event_id).success,
		f.name+": reuse of event ID rejected")
	events+=1
	env.session=next_session
	env.journal=durable_ack

func negatives(env: Dictionary) -> void:
	var f:Dictionary=env.f
	var journal:Dictionary=env.journal
	if journal.is_empty():return
	var tampered=journal.duplicate(true)
	tampered.committed[0].event_id="event/r562/forged"
	neg(Life.new().recover(env.store,String(f.source.construct_id),f.matter,f.authority,tampered),
		"R562_JOURNAL_CHECKSUM_INVALID",f.name+": tamper without checksum")
	tampered.checksum=U.compute_checksum(tampered)
	neg(Life.new().recover(env.store,String(f.source.construct_id),f.matter,f.authority,tampered),
		"R562_ENTRY_ID_MISMATCH",f.name+": replay catches forged ID even after rehash")
	var alien=Store.new()
	neg(Life.new().recover(alien,String(f.source.construct_id),f.matter,f.authority,journal),
		"R562_OWNER_DIVERGED",f.name+": journal cannot forge missing owner")
	var wrong_authority=f.authority.duplicate(true)
	wrong_authority.checksum="0".repeat(64)
	neg(Life.new().recover(env.store,String(f.source.construct_id),f.matter,
		wrong_authority,journal),"R562_OWNER_CONTEXT_DRIFT",f.name+": authority mismatch")

func conflict(f: Dictionary) -> void:
	var env=fresh(f)
	var source:Dictionary=env.store.get_snapshot(String(f.source.construct_id))
	var part_id:String=String(source.parts[3].part_id)
	var proposed:Dictionary=env.session.prepare_part(PartDelta.MOVE_PART,part_id,
		"event/r562/conflict", "",[12.0,3.0,-2.0])
	ck(proposed.success,f.name+": conflict prepare")
	if not proposed.success:return
	var durable=disk_copy(proposed.details.journal,f.name+"_conflict")
	var alternative:=PartDelta.prepare(source,f.matter,f.authority,[],
		"event/r562/conflict",PartDelta.MOVE_PART,part_id,"",[23.0,5.0,-3.0])
	ck(alternative.success,f.name+": conflicting real owner alternative")
	if not alternative.success:return
	ck(env.store.apply_mutation(alternative.details.mutation).success,
		f.name+": alternative authoritative mutation")
	var resumed=Life.new()
	neg(resumed.recover(env.store,String(f.source.construct_id),f.matter,f.authority,durable),
		"R562_OWNER_DIVERGED",f.name+": competing owner successor rejected")
	neg(env.session.query_range(0,f.count),"R562_PHYSICS_NOT_READY",
		f.name+": prepared session cannot publish competing source")

func _initialize() -> void:
	for f in [fixture("alpha",18),fixture("beta",25)]:
		var env=fresh(f)
		if not env.session.status().executable:
			continue
		transition(env,Life.BOND,BondDelta.BREAK,0,-1,1)
		transition(env,Life.PART,PartDelta.MOVE_PART,4,-1,2,[7.25,-1.0,2.5])
		transition(env,Life.PART,PartDelta.TRANSFER_MASS,5,12,3,[],0.125)
		transition(env,Life.BOND,BondDelta.REPAIR,0,-1,4)
		transition(env,Life.BOND,BondDelta.BREAK,3,-1,5)
		negatives(env)
		conflict(f)
	var report := {"schema":"fabric.r56_2_r1.lifecycle.acceptance.v1",
		"checks":checks,"failures":failures,"committed_events":events,
		"cold_restarts":restarts,"disk_roundtrips":disk_roundtrips,
		"full_oracle_queries":oracle_queries,"negative_rejections":denied}
	print("FABRIC_R562_R1_RESULT="+JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
