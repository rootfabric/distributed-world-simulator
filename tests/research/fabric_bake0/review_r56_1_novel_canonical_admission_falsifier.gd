extends SceneTree
## Fresh Ubuntu Reviewer NOVEL falsifier: external same-ID fork, caller-owned DTO alias, post-commit fence. Untracked; NOT product code.
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
    # A: Caller-owned binding/graph DTO must NOT alias the derived live cache.
    var fa: Dictionary = fixture("novel-detached")
    var st = Store.new()
    expect(st.apply_mutation(Mutation.create(Mutation.OP_CREATE, String(fa.source.construct_id), {}, fa.source)).success,
        "A create genuine Construction Store")
    var sa = Session.new()
    expect(sa.start(st, String(fa.source.construct_id), fa.matter, fa.authority).success,
        "A start canonical consumer")
    var original: Dictionary = sa.read_binding()
    expect(original.success, "A read valid boundary binding")
    if original.success:
        var baseline: String = U.canonical_hash(original.details)
        original.details.graph.edges[0].conductance = 9999999.0
        original.details.binding.checksum = "f".repeat(64)
        original.details.events.append("event/rv56/spoof-detached")
        var unchanged: Dictionary = sa.read_binding()
        expect(unchanged.success and U.canonical_hash(unchanged.details) == baseline,
            "A mutated read DTO cannot corrupt live derived boundary")
        expect(sa.status().events.is_empty() and not sa.status().stale,
            "A mutation of detached DTO does not mint event or stale state")
        observations["caller_dto_alias_accepted"] = unchanged.success and U.canonical_hash(unchanged.details) != baseline
    # B: A real Store commits a DIFFERENT action with SAME event ID. The
    # initially prepared intent is untouched. Does admission remain exact?
    var fb: Dictionary = fixture("novel-same-id")
    var stb = Store.new()
    expect(stb.apply_mutation(Mutation.create(Mutation.OP_CREATE, String(fb.source.construct_id), {}, fb.source)).success,
        "B create real owner")
    var sb = Session.new()
    expect(sb.start(stb, String(fb.source.construct_id), fb.matter, fb.authority).success,
        "B bind to real owner")
    var eid := "event/rv56/same-id"
    var p: Dictionary = sb.prepare(Delta.BREAK, "bond/rv56-novel-same-id/link-01", eid)
    expect(p.success, "B prepared original BREAK intent")
    var alt: Dictionary = Delta.prepare(fb.source, fb.matter, fb.authority, [], eid,
        Delta.SET_STRENGTH, "bond/rv56-novel-same-id/link-05", 77.0)
    expect(alt.success, "B alternate action separately valid under identical event id")
    if p.success and alt.success:
        var before_hash: String = String(sb.status().graph_hash)
        expect(stb.apply_mutation(alt.details.mutation).success,
            "B real Construction owner commits different same-id mutation")
        var before_observed: Dictionary = sb.status().duplicate(true)
        var denied: Dictionary = sb.observe_external_commit(eid, fb.matter, fb.authority)
        observations["same_event_alternate_commit_accepted"] = bool(denied.get("success", false))
        observations["same_event_alternate_error"] = String(denied.get("error_code", ""))
        expect(not denied.success and denied.error_code == "R56_AUTHORITATIVE_SUCCESSOR_MISMATCH",
            "B same-event but different authoritative action rejected")
        expect(sb.status() == before_observed and String(sb.status().graph_hash) == before_hash,
            "B wrong successor never publishes derived graph or events")
        var fenced: Dictionary = sb.read_binding()
        expect(not fenced.success and fenced.error_code == "R56_STALE_CANONICAL_SOURCE",
            "B old graph fenced after unexpected real authoritative event")
        var fresh = Session.new()
        var rebound: Dictionary = fresh.start(stb, String(fb.source.construct_id), fb.matter, fb.authority)
        expect(rebound.success and fresh.read_binding().success,
            "B explicit new session can bind to real externally updated world")
        if rebound.success:
            expect(String(fresh.status().graph_hash) != before_hash,
                "B fresh source's derived graph reflects real strength change")
    # C: After a valid external commit, a caller passes altered Matter.
    # Observation must be rejected, then exact original inputs may retry once.
    var fc: Dictionary = fixture("novel-matter-retry")
    var stc = Store.new()
    expect(stc.apply_mutation(Mutation.create(Mutation.OP_CREATE, String(fc.source.construct_id), {}, fc.source)).success,
        "C create canonical Store")
    var sc = Session.new()
    expect(sc.start(stc, String(fc.source.construct_id), fc.matter, fc.authority).success,
        "C start canonical consumer")
    var proposed: Dictionary = sc.prepare(Delta.BREAK, "bond/rv56-novel-matter-retry/link-02", "event/rv56/retry-once")
    expect(proposed.success, "C prepare one legitimate damage event")
    if proposed.success:
        var pre_hash: String = String(sc.status().graph_hash)
        expect(stc.apply_mutation(proposed.details.proposal.mutation).success,
            "C canonical owner commits proposed mutation")
        var corrupt_matter: Dictionary = fc.matter.duplicate(true)
        corrupt_matter.temperature_k = 2000.0
        var denial: Dictionary = sc.observe_external_commit("event/rv56/retry-once", corrupt_matter, fc.authority)
        expect(not denial.success and denial.error_code == "R56_MATTER_CHANGED_REBIND_REQUIRED",
            "C changed Matter rejected without source publication")
        expect(String(sc.status().graph_hash) == pre_hash and int(sc.status().observed_changes) == 0,
            "C rejected attempt leaves physical graph/revision counters intact")
        var success: Dictionary = sc.observe_external_commit("event/rv56/retry-once", fc.matter, fc.authority)
        expect(success.success and int(sc.status().observed_changes) == 1,
            "C clean same-event retry correctly observes once")
        if success.success:
            var actual: Dictionary = stc.get_snapshot(String(fc.source.construct_id))
            var oracle: Dictionary = Adapter.compile_authoritative(actual, fc.matter, fc.authority, sc.status().events)
            expect(oracle.success and oracle.details.spec.graph_hash == sc.status().graph_hash,
                "C fresh independent BRIDGE-4 oracle matches published derived graph")
            var replay: Dictionary = sc.observe_external_commit("event/rv56/retry-once", fc.matter, fc.authority)
            expect(not replay.success and int(sc.status().observed_changes) == 1,
                "C duplicated observe cannot double publish after successful retry")
            # D: After success a distinct outside owner event invalidates existing binding.
            var next_delta: Dictionary = Delta.prepare(actual, fc.matter, fc.authority, sc.status().events,
                "event/rv56/after-success", Delta.SET_STRENGTH, "bond/rv56-novel-matter-retry/link-04", 88.0)
            expect(next_delta.success and stc.apply_mutation(next_delta.details.mutation).success,
                "D genuine owner commits new event unseen by current session")
            var old_state: Dictionary = sc.read_binding()
            expect(not old_state.success and old_state.error_code == "R56_STALE_CANONICAL_SOURCE",
                "D derived graph invalidated on new canonical revision without prepare")
            expect(sc.status().stale and int(sc.status().observed_changes) == 1,
                "D stale source does not undo or duplicate previously published event")
    finish()
func finish() -> void:
    print("FABRIC_R56_REVIEW_FALSIFIER=" + JSON.stringify({"checks":checks, "failures":failures, "observations":observations}))
    quit(0 if failures.is_empty() else 1)