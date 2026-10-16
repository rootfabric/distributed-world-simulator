extends SceneTree
## R5.6.1 R1 — externally committed canonical transitions; derived graph only.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Delta = preload("res://scripts/research/fabric_bake0/r5_6_1_canonical_delta_contract_v1.gd")
const Session = preload("res://scripts/research/fabric_bake0/r5_6_1_canonical_delta_session_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_adapter_v1.gd")
const Store = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const Mutation = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Bond = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const MatterComposition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const MatterBatch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")

var checks := 0
var failures: Array = []

func ck(valid: bool, label: String, cause = null) -> void:
	checks += 1
	if not valid:
		failures.append(label)
		push_error("R5.6.1: " + label + ": " + JSON.stringify(cause))

func failure(got: Dictionary, code: String, label: String) -> void:
	ck(not bool(got.get("success", false)) and String(got.get("error_code", "")) == code, label, got)

func fixture(name: String, count: int, extra: int) -> Dictionary:
	var parts: Array = []
	for i in range(count):
		parts.append(Part.create("part/r56-" + name + "/%02d" % i, "item/r56-" + name + "-%02d" % i,
			"BEAM", "fabric_boundary" if i in [0,count-1] else "member", 1.0,
			[float(i) * 1.25, float((i * extra) % 3) * 0.75, 0.0]))
	var bonds: Array = []
	for i in range(count - 1):
		bonds.append(Bond.create("bond/r56-" + name + "/link-%02d" % i,
			String(parts[i].part_id), String(parts[i+1].part_id), "GENERIC_COUPLING", 50.0 + float(i)))
	for i in range(extra):
		bonds.append(Bond.create("bond/r56-" + name + "/bypass-%02d" % i,
			String(parts[i].part_id), String(parts[i+2].part_id), "GENERIC_COUPLING", 15.0))
	var source: Dictionary = Snapshot.create("construct/r56/" + name, "item/r56-root-" + name,
		0, "OPERATIONAL", parts, bonds, {"reference": "r56-generic-source-r1"})
	var matter: Dictionary = MatterBatch.create({
		"batch_id": "batch/r56/"+name, "container_id": "container/r56/"+name,
		"source_body_id": "body/r56/"+name, "source_operation_id": "operation/r56/"+name,
		"total_mass_kg": float(count), "bulk_volume_m3": 0.1,
		"composition": MatterComposition.create([{"material_id": "material/r56-steel", "mass_fraction": 1.0}]),
		"temperature_k": 293.15,
	})
	return {"source": source, "matter": matter, "authority": Adapter.authority_for(source, matter, "server/r56-owner", 13)}

func new_session(f: Dictionary) -> Dictionary:
	var store = Store.new()
	var created: Dictionary = store.apply_mutation(Mutation.create(Mutation.OP_CREATE, String(f.source.construct_id), {}, f.source))
	ck(created.success, "external authoritative CREATE", created)
	var session = Session.new()
	var started: Dictionary = session.start(store, String(f.source.construct_id), f.matter, f.authority)
	ck(started.success, "derived consumer start from external source", started)
	ck(session.status().canonical_writes == 0, "consumer never writes canonical store")
	return {"store": store, "session": session, "fixture": f}

func transition(env: Dictionary, action: String, bond_id: String, event_id: String, strength_n: float = 0.0) -> void:
	var store = env.store
	var session = env.session
	var f: Dictionary = env.fixture
	var before: Dictionary = store.get_snapshot(String(f.source.construct_id))
	var old_bind: Dictionary = session.read_binding()
	ck(old_bind.success, "precondition graph binding valid")
	var prep: Dictionary = session.prepare(action, bond_id, event_id, strength_n)
	ck(prep.success, "generic delta proposal prepared", prep)
	if not prep.success: return
	ck(store.get_snapshot(String(f.source.construct_id)) == before, "proposal does not write canonical state")
	ck(prep.details.proposal.canonical == false and prep.details.proposal.write_authorized == false, "proposal is not authoritative")
	failure(session.observe_external_commit(event_id, f.matter, f.authority), "R56_EXTERNAL_COMMIT_NOT_OBSERVED", "cannot self-approve proposal without external write")
	var changed: Dictionary = store.apply_mutation(prep.details.proposal.mutation)
	ck(changed.success, "external ConstructionConstructStore committed", changed)
	ck(session.status().stale, "old derived binding becomes stale immediately")
	failure(session.read_binding(), "R56_STALE_CANONICAL_SOURCE", "stale derived graph cannot be read")
	var observed: Dictionary = session.observe_external_commit(event_id, f.matter, f.authority)
	ck(observed.success, "new canonical source derived graph accepted", observed)
	var bound: Dictionary = session.read_binding()
	ck(bound.success, "new derived graph available")
	if bound.success:
		ck(bound.details.graph.graph_hash != old_bind.details.graph.graph_hash, "changed graph has new derived identity")
		var oracle: Dictionary = Adapter.compile_authoritative(store.get_snapshot(String(f.source.construct_id)), f.matter, f.authority, session.status().events)
		ck(oracle.success and oracle.details.spec.graph_hash == bound.details.graph.graph_hash and oracle.details.binding.checksum == bound.details.binding.checksum,
			"fresh independent BRIDGE4 compile matches derived graph")
	ck(int(session.status().revision) == int(before.state_revision) + 1, "canonical revision advances exactly once")
	failure(session.observe_external_commit(event_id, f.matter, f.authority), "R56_NO_MATCHING_PROPOSAL", "replay cannot reobserve same event")
	var stale_commit = store.apply_mutation(prep.details.proposal.mutation)
	ck(not stale_commit.success, "Construction owner rejects stale duplicate mutation")

func scenario(f: Dictionary) -> Dictionary:
	var env: Dictionary = new_session(f)
	var store = env.store
	var session = env.session
	var id: String = String(f.source.construct_id)
	var baseline: Dictionary = session.read_binding()
	ck(baseline.success, "initial derived source binding")
	var bond_a := "bond/r56-" + id.get_slice("/", 2) + "/link-01"
	var bond_b := "bond/r56-" + id.get_slice("/", 2) + "/link-03"
	failure(session.prepare(Delta.BREAK, "bond/missing", "event/r56/missing"), "R56_UNKNOWN_BOND", "unknown bond rejected")
	failure(session.prepare(Delta.SET_STRENGTH, bond_b, "event/r56/nan", NAN), "R56_STRENGTH_INVALID", "nonfinite strength rejected")
	failure(session.prepare(Delta.REPAIR, bond_a, "event/r56/early-repair"), "R56_BOND_NOT_BROKEN", "invalid repair rejected")
	ck(not session.status().pending, "invalid proposals do not create pending state")
	transition(env, Delta.BREAK, bond_a, "event/r56/" + id.get_slice("/", 2) + "-break")
	ck(String(store.get_snapshot(id).build_state) == "DAMAGED", "damage is canonical")
	transition(env, Delta.SET_STRENGTH, bond_b, "event/r56/" + id.get_slice("/", 2) + "-strength", 123.0)
	transition(env, Delta.REPAIR, bond_a, "event/r56/" + id.get_slice("/", 2) + "-repair")
	ck(String(store.get_snapshot(id).build_state) == "OPERATIONAL", "repair restores canonical structural state")
	ck(session.status().events.size() == 3 and int(session.status().observed_changes) == 3, "three sequential canonical events accepted")
	failure(session.prepare(Delta.BREAK, bond_b, "event/r56/" + id.get_slice("/", 2) + "-break"),
		"R56_EVENT_ID_REPLAY_OR_BUDGET", "already applied event ID cannot be reused")
	ck(not session.status().stale and session.status().canonical_writes == 0, "external source stays authoritative")
	return {"snapshot": store.get_snapshot(id), "graph_hash": session.status().graph_hash, "events": session.status().events}

func negative_external_divergence() -> void:
	var f: Dictionary = fixture("adversarial", 9, 2)
	var env := new_session(f)
	var store = env.store
	var session = env.session
	var bond_id := "bond/r56-adversarial/link-01"
	var before_binding: Dictionary = session.read_binding()
	var prepared: Dictionary = session.prepare(Delta.BREAK, bond_id, "event/r56/diverged")
	ck(prepared.success, "legitimate delta staged for divergence test")
	if not prepared.success: return
	# The external owner makes a DIFFERENT but valid mutation. The session MUST
	# not accept it as if it had authorized the original proposal.
	var alternative: Dictionary = Delta.prepare(f.source, f.matter, f.authority, [], "event/r56/other",
		Delta.SET_STRENGTH, "bond/r56-adversarial/link-03", 88.0)
	ck(alternative.success, "external divergent mutation is itself a valid canonical source")
	if not alternative.success: return
	ck(store.apply_mutation(alternative.details.mutation).success, "external owner applied divergent source")
	var before_status: Dictionary = session.status().duplicate(true)
	var denied: Dictionary = session.observe_external_commit("event/r56/diverged", f.matter, f.authority)
	failure(denied, "R56_AUTHORITATIVE_SUCCESSOR_MISMATCH", "unrelated externally committed source cannot satisfy pending proposal")
	ck(session.status() == before_status, "failed observation does not publish derived source")
	failure(session.read_binding(), "R56_STALE_CANONICAL_SOURCE", "stale derived state remains fenced")
	failure(session.abandon_proposal(), "R56_STALE_CANONICAL_SOURCE", "cannot erase pending event after divergent canonical commit")
	ck(String(before_binding.details.binding.checksum) != String(alternative.details.binding_checksum), "changed external graph has distinct binding")

func negative_stale_authority() -> void:
	var f := fixture("auth", 8, 1)
	var env := new_session(f)
	var session = env.session
	var prepared: Dictionary = session.prepare(Delta.BREAK, "bond/r56-auth/link-01", "event/r56/authority")
	ck(prepared.success, "authority test proposal created")
	if not prepared.success: return
	ck(env.store.apply_mutation(prepared.details.proposal.mutation).success, "external authority applied change")
	var forged: Dictionary = f.authority.duplicate(true)
	forged["execution_owner"] = "server/forged"
	failure(session.observe_external_commit("event/r56/authority", f.matter, forged), "R56_AUTHORITY_CHANGED_REBIND_REQUIRED", "forged authority rejects without publication")
	var different_matter: Dictionary = f.matter.duplicate(true)
	different_matter.temperature_k = 299.0
	failure(session.observe_external_commit("event/r56/authority", different_matter, f.authority), "R56_MATTER_CHANGED_REBIND_REQUIRED", "changed matter requires explicit rebind")
	ck(session.status().stale and int(session.status().revision) == 0, "authorization failure keeps old derived state fenced")
	ck(session.observe_external_commit("event/r56/authority", f.matter, f.authority).success, "authorized observation recovers correct canonical revision")

func negative_detached_preview() -> void:
	var f: Dictionary = fixture("detached", 8, 1)
	var env: Dictionary = new_session(f)
	var session = env.session
	var pending: Dictionary = session.prepare(Delta.BREAK, "bond/r56-detached/link-01", "event/r56/detached")
	ck(pending.success, "detached preview created")
	if not pending.success: return
	var canonical_mutation: Dictionary = pending.details.proposal.mutation.duplicate(true)
	pending.details.proposal.mutation.after_snapshot.bonds[0].strength_n = 999.0
	ck(U.canonical_hash(canonical_mutation) == U.canonical_hash(session._pending.mutation), "caller cannot mutate internal pending proposal by alias")
	ck(env.store.apply_mutation(canonical_mutation).success, "external owner applies original detached proposal")
	ck(session.observe_external_commit("event/r56/detached", f.matter, f.authority).success, "detached preview mutation cannot affect true commit")

func _initialize() -> void:
	negative_detached_preview()
	var first: Dictionary = scenario(fixture("alpha", 8, 1))
	var second: Dictionary = scenario(fixture("beta", 11, 3))
	ck(String(first.graph_hash) != String(second.graph_hash), "different valid topologies produce different graphs")
	var repeat: Dictionary = scenario(fixture("alpha", 8, 1))
	ck(U.canonical_hash(first) == U.canonical_hash(repeat), "full multi-event replay determinism across fresh sources")
	negative_external_divergence()
	negative_stale_authority()
	var result := {"schema": "fabric.r5_6_1.canonical_delta.result.v1", "checks": checks, "failures": failures,
		"scenario_a_final_hash": String(first.graph_hash), "scenario_b_final_hash": String(second.graph_hash),
		"sequence_events": 3, "independent_variants": 2}
	print("FABRIC_R5_6_1_RESULT=" + JSON.stringify(result))
	print("FABRIC_R5_6_1_RESULT_HASH=" + U.canonical_hash(result))
	quit(0 if failures.is_empty() else 1)
