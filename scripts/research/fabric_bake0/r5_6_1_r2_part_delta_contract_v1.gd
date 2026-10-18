extends RefCounted
## FABRIC R5.6.1 R2 — bounded physical part delta PROPOSALS only.
## Construction owns all canonical writes. Matter is held constant for this
## slice: mass can be *transferred* between two parts, never minted or deleted.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Mutation = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_adapter_v1.gd")
const Moments = preload("res://scripts/research/fabric_bake0/r5_6_1_r2_dynamic_aggregate_index_v1.gd")

const SCHEMA := "planet_simulator.fabric_r56_r2_part_delta_proposal.v1"
const MOVE_PART := "MOVE_PART"
const TRANSFER_MASS := "TRANSFER_MASS"
const MAX_EVENTS := 32

static func prepare(before: Dictionary, matter: Dictionary, authority: Dictionary,
		events: Array, event_id: String, action: String, first_part_id: String,
		second_part_id: String = "", new_position: Array = [], delta_mass_kg: float = 0.0) -> Dictionary:
	if not U.is_canonical_id(event_id, 2) or events.has(event_id) or events.size() >= MAX_EVENTS:
		return U.failure("R56_R2_EVENT_REPLAY_OR_BUDGET")
	if not [MOVE_PART, TRANSFER_MASS].has(action) or not U.is_canonical_id(first_part_id, 2):
		return U.failure("R56_R2_ACTION_OR_PART_INVALID")
	var initial := Adapter.compile_authoritative(before, matter, authority, events)
	if not initial.success:
		return U.failure("R56_R2_INITIAL_BINDING_INVALID", {"cause": initial.get("error_code", "")})
	if before.parts.is_empty():
		return U.failure("R56_R2_EMPTY_STRUCTURE")
	var first := -1
	var second := -1
	var parts: Array = before.parts.duplicate(true)
	for i in range(parts.size()):
		if String(parts[i].part_id) == first_part_id:
			first = i
		if String(parts[i].part_id) == second_part_id:
			second = i
	if first < 0:
		return U.failure("R56_R2_FIRST_PART_UNKNOWN")
	var changed: Array = []
	match action:
		MOVE_PART:
			if not second_part_id.is_empty() or not U.is_finite_number(delta_mass_kg) or delta_mass_kg != 0.0:
				return U.failure("R56_R2_MOVE_ARGUMENTS_INVALID")
			if new_position.size() != 3:
				return U.failure("R56_R2_POSITION_INVALID")
			for coordinate in new_position:
				if not U.is_finite_number(coordinate):
					return U.failure("R56_R2_POSITION_INVALID")
			if U.canonical_hash(parts[first].local_position_m) == U.canonical_hash(new_position):
				return U.failure("R56_R2_NO_EFFECT")
			var previous: Dictionary = parts[first].duplicate(true)
			parts[first].local_position_m = new_position.duplicate(true)
			changed.append({"before": previous, "after": parts[first].duplicate(true)})
		TRANSFER_MASS:
			if not U.is_canonical_id(second_part_id, 2) or first_part_id == second_part_id or second < 0:
				return U.failure("R56_R2_SECOND_PART_INVALID")
			if not new_position.is_empty() or not U.is_finite_number(delta_mass_kg) or delta_mass_kg <= 0.0 or delta_mass_kg >= float(parts[first].mass_kg):
				return U.failure("R56_R2_TRANSFER_ARGUMENTS_INVALID")
			var old_first: Dictionary = parts[first].duplicate(true)
			var old_second: Dictionary = parts[second].duplicate(true)
			parts[first].mass_kg = float(old_first.mass_kg) - delta_mass_kg
			parts[second].mass_kg = float(old_second.mass_kg) + delta_mass_kg
			# No new matter is created. A compensated numeric tolerance is checked
			# by the authoritative bridge and by the index just before commit.
			changed.append({"before": old_first, "after": parts[first].duplicate(true)})
			changed.append({"before": old_second, "after": parts[second].duplicate(true)})
	changed.sort_custom(func(a,b): return String(a.before.part_id) < String(b.before.part_id))
	for entry in changed:
		if not Part.validate(entry.after).success:
			return U.failure("R56_R2_NEW_PART_INVALID")
		if Moments._moment(entry.after).size() != Moments.MOMENTS.size():
			return U.failure("R56_R2_PHYSICAL_MOMENT_INVALID")
	var after := Snapshot.create(String(before.construct_id), String(before.root_item_instance_id),
		int(before.state_revision) + 1, String(before.build_state), parts, before.bonds, before.compiled_facets)
	if not Snapshot.validate(after).success:
		return U.failure("R56_R2_SUCCESSOR_INVALID")
	var next_events: Array = events.duplicate()
	next_events.append(event_id)
	next_events.sort()
	var compiled := Adapter.compile_authoritative(after, matter, authority, next_events)
	if not compiled.success:
		return U.failure("R56_R2_RESULT_BINDING_INVALID", {"cause": compiled.get("error_code", "")})
	var mutation := Mutation.create(Mutation.OP_UPDATE, String(before.construct_id), before, after)
	if not Mutation.validate(mutation).success:
		return U.failure("R56_R2_MUTATION_INVALID")
	return U.success({
		"schema": SCHEMA, "event_id": event_id,
		"action": action, "first_part_id": first_part_id, "second_part_id": second_part_id,
		"new_position": new_position.duplicate(true), "delta_mass_kg": delta_mass_kg,
		"canonical": false, "write_authorized": false,
		"before_checksum": String(before.checksum), "after_checksum": String(after.checksum),
		"mutation": mutation, "changed_rows": changed, "next_events": next_events,
		"expected_graph_hash": String(compiled.details.spec.graph_hash),
		"expected_binding_checksum": String(compiled.details.binding.checksum),
	})

static func validate_external(before: Dictionary, after: Dictionary, matter: Dictionary,
		authority: Dictionary, events: Array, proposal: Dictionary) -> Dictionary:
	if proposal.get("schema") != SCHEMA or proposal.get("canonical", true) != false or proposal.get("write_authorized", true) != false:
		return U.failure("R56_R2_PROPOSAL_SCHEMA_INVALID")
	if not Mutation.validate(proposal.get("mutation", {})).success:
		return U.failure("R56_R2_PROPOSAL_MUTATION_INVALID")
	if not U.is_finite_number(proposal.get("delta_mass_kg", null)):
		return U.failure("R56_R2_PROPOSAL_MASS_INVALID")
	if typeof(proposal.get("new_position")) != TYPE_ARRAY:
		return U.failure("R56_R2_PROPOSAL_POSITION_INVALID")
	var prepared := prepare(before, matter, authority, events,
		String(proposal.get("event_id", "")), String(proposal.get("action", "")),
		String(proposal.get("first_part_id", "")), String(proposal.get("second_part_id", "")),
		proposal.get("new_position", []), float(proposal.get("delta_mass_kg", 0.0)))
	if not prepared.success:
		return prepared
	if U.canonical_hash(prepared.details) != U.canonical_hash(proposal):
		return U.failure("R56_R2_PROPOSAL_CONTENT_MISMATCH")
	if U.canonical_hash(after) != U.canonical_hash(prepared.details.mutation.after_snapshot):
		return U.failure("R56_R2_EXTERNAL_SUCCESSOR_MISMATCH")
	return prepared
