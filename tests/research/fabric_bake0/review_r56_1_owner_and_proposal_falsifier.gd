extends SceneTree
## Independent R5.6.1 review falsifier; untracked, NOT product code.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Session = preload("res://scripts/research/fabric_bake0/r5_6_1_canonical_delta_session_v1.gd")
const Delta = preload("res://scripts/research/fabric_bake0/r5_6_1_canonical_delta_contract_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_adapter_v1.gd")
const Store = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const Mutation = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Bond = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const MatterComposition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const MatterBatch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")

class SpoofStore:
    extends RefCounted
    var state: Dictionary = {}
    func get_snapshot(_construct_id: String) -> Dictionary:
        return state.duplicate(true)
    func publish(snapshot: Dictionary) -> void:
        state = snapshot.duplicate(true)

var checks := 0
var failures: Array = []
var observations: Dictionary = {}

func expect(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures.append(label)
        push_error("R56 REVIEW: " + label)

func fixture(name: String) -> Dictionary:
    var parts: Array = []
    for i in range(8):
        parts.append(Part.create("part/rv56-" + name + "/%02d" % i, "item/rv56-" + name + "-%02d" % i,
            "BEAM", "fabric_boundary" if i in [0, 7] else "member", 1.0, [float(i) * 1.25, float(i % 3) * 0.5, 0.0]))
    var bonds: Array = []
    for i in range(7):
        bonds.append(Bond.create("bond/rv56-" + name + "/link-%02d" % i,
            String(parts[i].part_id), String(parts[i+1].part_id), "GENERIC_COUPLING", 40.0 + float(i)))
    bonds.append(Bond.create("bond/rv56-" + name + "/bypass-00",
        String(parts[0].part_id), String(parts[2].part_id), "GENERIC_COUPLING", 15.0))
    var s: Dictionary = Snapshot.create("construct/rv56/" + name, "item/rv56-root-" + name,
        0, "OPERATIONAL", parts, bonds, {"reference": "independent-r56-review"})
    var m: Dictionary = MatterBatch.create({
        "batch_id": "batch/rv56/" + name, "container_id": "container/rv56/" + name,
        "source_body_id": "body/rv56/" + name, "source_operation_id": "operation/rv56/" + name,
        "total_mass_kg": 8.0, "bulk_volume_m3": 0.12,
        "composition": MatterComposition.create([{"material_id": "material/rv56-steel", "mass_fraction": 1.0}]),
        "temperature_k": 293.15,
    })
    var authority: Dictionary = Adapter.authority_for(s, m, "server/r56-reviewer", 17)
    return {"source": s, "matter": m, "authority": authority}

func _initialize() -> void:
    var f: Dictionary = fixture("spoof")
    var fake = SpoofStore.new()
    fake.publish(f.source)
    var session = Session.new()
    var start: Dictionary = session.start(fake, String(f.source.construct_id), f.matter, f.authority)
    observations["duck_store_start_accepted"] = bool(start.get("success", false))
    # A derived consumer promising a real ConstructionConstructStore must not
    # accept any object implementing only get_snapshot as proof of authority.
    expect(not start.success, "reject duck-typed fake canonical store")
    if start.success:
        var p: Dictionary = session.prepare(Delta.BREAK, "bond/rv56-spoof/link-01", "event/rv56/spoof")
        var prepared: bool = bool(p.get("success", false))
        observations["fake_proposal_prepared"] = prepared
        if prepared:
            fake.publish(p.details.proposal.mutation.after_snapshot)
            var accepted: Dictionary = session.observe_external_commit("event/rv56/spoof", f.matter, f.authority)
            observations["fake_commit_observed"] = bool(accepted.get("success", false))
            observations["fake_commit_error"] = accepted.get("error_code", "")
            expect(not accepted.success, "reject fake-store commit as authoritative")

    var f2: Dictionary = fixture("pending")
    var real_store = Store.new()
    var create: Dictionary = real_store.apply_mutation(Mutation.create(Mutation.OP_CREATE, String(f2.source.construct_id), {}, f2.source))
    expect(create.success, "real canonical Store.create precondition")
    if not create.success:
        finish(); return
    var s2 = Session.new()
    var good_start: Dictionary = s2.start(real_store, String(f2.source.construct_id), f2.matter, f2.authority)
    expect(good_start.success, "real Store session start")
    if not good_start.success:
        finish(); return
    var event_id := "event/rv56/pending-01"
    var original: Dictionary = s2.prepare(Delta.BREAK, "bond/rv56-pending/link-01", event_id)
    expect(original.success, "original bond BREAK proposal staged")
    var alternative: Dictionary = Delta.prepare(f2.source, f2.matter, f2.authority, [], event_id,
        Delta.SET_STRENGTH, "bond/rv56-pending/link-03", 123.0)
    expect(alternative.success, "divergent canonical mutation prepared separately")
    if not original.success or not alternative.success:
        finish(); return
    var external: Dictionary = real_store.apply_mutation(alternative.details.mutation)
    expect(external.success, "different external Construction mutation applied")
    var canonical_before: Dictionary = real_store.get_snapshot(String(f2.source.construct_id))
    observations["original_prepared_action"] = original.details.proposal.action
    observations["external_actual_action"] = alternative.details.action
    observations["canonical_changed"] = int(canonical_before.state_revision) == 1
    # The original pending proposal was BREAK. Changing the in-memory pending
    # candidate to a fully coherent alternative with the same event id must
    # NOT authorize that alternate source after the fact.
    s2._pending = alternative.details.duplicate(true)
    var observed: Dictionary = s2.observe_external_commit(event_id, f2.matter, f2.authority)
    observations["forged_pending_observed"] = bool(observed.get("success", false))
    observations["forged_pending_error"] = observed.get("error_code", "")
    observations["accepted_graph_hash"] = String(s2.status().graph_hash)
    expect(not observed.success, "reject coordinated post-prepare pending rewrite")
    if observed.success:
        expect(s2.read_binding().success, "characterization: forged-pending derived binding becomes executable")
    finish()

func finish() -> void:
    print("FABRIC_R56_REVIEW_FALSIFIER=" + JSON.stringify({"checks":checks, "failures":failures, "observations":observations}))
    quit(0 if failures.is_empty() else 1)
