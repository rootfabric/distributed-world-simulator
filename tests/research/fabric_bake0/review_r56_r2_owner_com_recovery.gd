extends SceneTree
## Independent integration falsifier: a real ConstructionConstructStore must
## accept two successive owner changes, even if the interim derived COM cannot
## be published in R2's bounded absolute Float64 descriptor.
const Session = preload("res://scripts/research/fabric_bake0/r5_6_1_r2_dynamic_aggregate_session_v1.gd")
const Delta = preload("res://scripts/research/fabric_bake0/r5_6_1_r2_part_delta_contract_v1.gd")
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
var observations: Dictionary = {}
func ck(ok: bool, label: String, details = null) -> void:
    checks += 1
    if not ok:
        failures.append(label)
        push_error("REVIEW_R56_R2_OWNER_COM_RECOVERY: " + label + ": " + JSON.stringify(details))
func _initialize() -> void:
    var offset := 1000000000000.0
    var small := 0.0001220703125
    var parts: Array = []
    for i in range(8):
        parts.append(Part.create("part/review/com-recovery/%02d"%i,"item/review/com-recovery-%02d"%i,
           "BEAM","fabric_boundary" if i in [0,7] else "member",1.0,
           [offset+0.5*float(i),0.0,0.0]))
    var bonds: Array = []
    for i in range(7):
        bonds.append(Bond.create("bond/review/com-recovery/link-%02d"%i,
           String(parts[i].part_id),String(parts[i+1].part_id),"GENERIC_COUPLING",60.0))
    var source: Dictionary = Snapshot.create("construct/review/com-recovery", "item/review/com-root",0,
        "OPERATIONAL",parts,bonds,{"review":"com-recovery"})
    ck(Snapshot.validate(source).success, "canonical source valid")
    var matter: Dictionary = MatterBatch.create({
        "batch_id":"batch/review/com", "container_id":"container/review/com",
        "source_body_id":"body/review/com", "source_operation_id":"operation/review/com",
        "total_mass_kg":8.0, "bulk_volume_m3":0.2,
        "composition":Composition.create([{"material_id":"material/steel","mass_fraction":1.0}]),
        "temperature_k":293.15})
    var auth: Dictionary = Adapter.authority_for(source,matter,"server/review/com",24)
    var owner=Store.new()
    var created: Dictionary = owner.apply_mutation(Mutation.create(Mutation.OP_CREATE,
        String(source.construct_id),{},source))
    ck(created.success, "real Construction owner creates canonical source",created)
    if not created.success: finish(); return
    var session=Session.new()
    var start: Dictionary = session.start(owner,String(source.construct_id),matter,auth)
    observations["session_start_error"] = start.get("error_code", "")
    ck(start.success, "derived R2 session binds real owner",start)
    if not start.success: finish(); return
    var initial: Dictionary = session.query_range(0,8)
    ck(initial.success,"initial absolute COM can be published",initial)
    if not initial.success: finish(); return
    var part_id: String = String(parts[7].part_id)
    var p1: Dictionary = session.prepare(Delta.MOVE_PART,part_id,"event/review/com/1","",[offset+small,0.0,0.0])
    observations["first_prepare_error"] = p1.get("error_code", "")
    ck(p1.success,"prepare owner event into unsafe COM",p1)
    if not p1.success: finish(); return
    var m1: Dictionary = owner.apply_mutation(p1.details.proposal.mutation)
    ck(m1.success,"owner commits legitimate first state",m1)
    if not m1.success: finish(); return
    var stale: Dictionary = session.query_range(0,8)
    ck(not stale.success and String(stale.error_code)=="R56_R2_STALE_CANONICAL_SOURCE", "derived old state fenced after owner update",stale)
    var o1: Dictionary = session.observe_external_commit("event/review/com/1",matter,auth)
    observations["first_observe_error"] = o1.get("error_code", "")
    ck(o1.success,"derived consumer admits exact first external commit",o1)
    if not o1.success: finish(); return
    var unsafe: Dictionary = session.query_range(0,8)
    observations["unsafe_query_error"] = unsafe.get("error_code", "")
    ck(not unsafe.success and String(unsafe.error_code)=="R56_R2_RANGE_CENTER_PRECISION_UNSAFE", "unsafe interim COM is withheld",unsafe)
    var p2: Dictionary = session.prepare(Delta.MOVE_PART,part_id,"event/review/com/2","",[offset+3.5,0.0,0.0])
    observations["second_prepare_error"] = p2.get("error_code", "")
    ck(p2.success,"second owner-approved repair prepared from unsafe COM state",p2)
    if not p2.success: finish(); return
    var m2: Dictionary = owner.apply_mutation(p2.details.proposal.mutation)
    ck(m2.success,"owner commits restoring position",m2)
    if not m2.success: finish(); return
    var o2: Dictionary = session.observe_external_commit("event/review/com/2",matter,auth)
    observations["second_observe_error"] = o2.get("error_code", "")
    ck(o2.success,"derived R2 rebind accepts recovery into safe COM",o2)
    if o2.success:
        var good: Dictionary = session.query_range(0,8)
        ck(good.success,"safe COM publication restored",good)
        if good.success:
            ck(absf(float(good.details.center_of_mass[0])-(offset+1.75))<=0.000001,
                "COM matches independently computed eight-mass centroid",good)
            ck(absf(float(good.details.total_mass)-8.0)<=1.0e-8,"matter mass conserved",good)
        ck(int(session.status().commits)==2 and int(session.status().index.accepted_updates)==2,
            "two external events, two derived sparse commits",session.status())
        ck(int(session.status().canonical_writes)==0,"FABRIC did not write canonical world",session.status())
        var replay: Dictionary = session.observe_external_commit("event/review/com/2",matter,auth)
        ck(not replay.success and String(replay.error_code)=="R56_R2_NO_MATCHING_PROPOSAL",
            "repeat event rejected",replay)
    finish()
func finish() -> void:
    print("FABRIC_R56_R2_INDEPENDENT_OWNER_COM_RECOVERY="+JSON.stringify({"checks":checks,"failures":failures,"observations":observations}))
    quit(0 if failures.is_empty() else 1)
