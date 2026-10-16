extends RefCounted
## R5.6.1 R1 — bounded, data-driven Construction bond deltas.
## PROPOSALS ONLY. An external ConstructionConstructStore owner authorizes and
## commits changes; FABRIC only validates and derives a new source-bound graph.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Mutation = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_adapter_v1.gd")

const SCHEMA := "planet_simulator.fabric_r5_6_1_canonical_delta_proposal.v1"
const BREAK := "BREAK_BOND"
const REPAIR := "REPAIR_BOND"
const SET_STRENGTH := "SET_BOND_STRENGTH"
const MAX_EVENTS := 32

static func prepare(before: Dictionary, matter: Dictionary, authority: Dictionary,
		events: Array, event_id: String, action: String, bond_id: String,
		strength_n: float = 0.0) -> Dictionary:
	if not U.is_canonical_id(event_id, 2) or events.has(event_id) or events.size() >= MAX_EVENTS:
		return U.failure("R56_EVENT_ID_REPLAY_OR_BUDGET")
	if not [BREAK, REPAIR, SET_STRENGTH].has(action):
		return U.failure("R56_ACTION_UNSUPPORTED")
	if not U.is_canonical_id(bond_id, 2):
		return U.failure("R56_BOND_ID_INVALID")
	if not ["OPERATIONAL", "DAMAGED"].has(String(before.get("build_state", ""))):
		return U.failure("R56_BUILD_STATE_UNSUPPORTED")
	# Canonical credentials are supplied by the owning caller, never minted from
	# the proposal or derived graph. Bridge-4 verifies the source + authority.
	var previous := Adapter.compile_authoritative(before, matter, authority, events)
	if not previous.success:
		return U.failure("R56_PREVIOUS_SOURCE_INVALID", {"cause": previous.get("error_code", "")})
	# R1 understands only bond-state-driven damage; an unknown prior damage
	# cause must not be "repaired" by changing a bond and silently clearing it.
	var had_break := false
	for existing in before.bonds:
		if String(existing.state) == "BROKEN":
			had_break = true
	if (String(before.build_state) == "DAMAGED") != had_break:
		return U.failure("R56_DAMAGE_CAUSE_OUT_OF_SCOPE")
	var bonds: Array = before.bonds.duplicate(true)
	var position := -1
	for i in range(bonds.size()):
		if String(bonds[i].bond_id) == bond_id:
			position = i
			break
	if position < 0:
		return U.failure("R56_UNKNOWN_BOND")
	var bond: Dictionary = bonds[position]
	match action:
		BREAK:
			if String(bond.state) == "BROKEN":
				return U.failure("R56_BOND_ALREADY_BROKEN")
			bond.state = "BROKEN"
		REPAIR:
			if String(bond.state) != "BROKEN":
				return U.failure("R56_BOND_NOT_BROKEN")
			bond.state = "INTACT"
		SET_STRENGTH:
			if not is_finite(strength_n) or strength_n <= 0.0:
				return U.failure("R56_STRENGTH_INVALID")
			if float(bond.strength_n) == strength_n:
				return U.failure("R56_NO_EFFECT")
			bond.strength_n = strength_n
	bonds[position] = bond
	var any_broken := false
	for b in bonds:
		if String(b.state) == "BROKEN":
			any_broken = true
			break
	var next_state := "DAMAGED" if any_broken else "OPERATIONAL"
	var after: Dictionary = Snapshot.create(String(before.construct_id), String(before.root_item_instance_id),
		int(before.state_revision) + 1, next_state, before.parts, bonds, before.compiled_facets)
	if not Snapshot.validate(after).success:
		return U.failure("R56_SUCCESSOR_SNAPSHOT_INVALID")
	var next_events := events.duplicate()
	next_events.append(event_id)
	next_events.sort()
	var compiled := Adapter.compile_authoritative(after, matter, authority, next_events)
	if not compiled.success:
		return U.failure("R56_SUCCESSOR_GRAPH_INVALID", {"cause": compiled.get("error_code", "")})
	var mutation: Dictionary = Mutation.create(Mutation.OP_UPDATE, String(before.construct_id), before, after)
	if not Mutation.validate(mutation).success:
		return U.failure("R56_MUTATION_INVALID")
	return U.success({
		"schema": SCHEMA, "canonical": false, "write_authorized": false,
		"event_id": event_id, "action": action, "bond_id": bond_id,
		"strength_n": strength_n if action == SET_STRENGTH else 0.0,
		"expected_before_checksum": String(before.checksum),
		"candidate_after_checksum": String(after.checksum),
		"mutation": mutation,
		"next_events": next_events,
		"graph_hash": String(compiled.details.spec.graph_hash),
		"binding_checksum": String(compiled.details.binding.checksum),
		"changed_bonds": 1,
	})

static func validate_external(before: Dictionary, after: Dictionary, matter: Dictionary,
		authority: Dictionary, events: Array, proposal: Dictionary) -> Dictionary:
	if proposal.get("schema") != SCHEMA or proposal.get("canonical", true) != false or proposal.get("write_authorized", true) != false:
		return U.failure("R56_PROPOSAL_SCHEMA_INVALID")
	if not Mutation.validate(proposal.get("mutation", {})).success:
		return U.failure("R56_PROPOSAL_MUTATION_INVALID")
	if not U.is_finite_number(proposal.get("strength_n", null)):
		return U.failure("R56_PROPOSAL_STRENGTH_INVALID")
	var expected := prepare(before, matter, authority, events,
		String(proposal.get("event_id", "")), String(proposal.get("action", "")),
		String(proposal.get("bond_id", "")), float(proposal.get("strength_n", 0.0)))
	if not expected.success:
		return expected
	var value: Dictionary = expected.details
	if U.canonical_hash(value) != U.canonical_hash(proposal):
		return U.failure("R56_PROPOSAL_CONTENT_MISMATCH")
	if U.canonical_hash(after) != U.canonical_hash(value.mutation.after_snapshot):
		return U.failure("R56_AUTHORITATIVE_SUCCESSOR_MISMATCH")
	return expected
