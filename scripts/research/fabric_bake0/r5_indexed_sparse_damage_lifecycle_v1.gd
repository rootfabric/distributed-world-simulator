extends "res://scripts/research/fabric_bake0/complex3_sparse_damage_lifecycle_v1.gd"
## R5.1 successor lifecycle. Closed COMPLEX3 remains immutable.
## Residual aggregate queries use a shared derived range index instead of O(N)
## rescans during local UNBAKE/ReBAKE.

const RangeIndex = preload("res://scripts/research/fabric_bake0/r5_range_aggregate_index_v1.gd")
const R5U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const R5H = preload("res://scripts/research/fabric_bake0/bridge3_rigid_handoff_v1.gd")
const R5Slot = preload("res://scripts/research/fabric_bake0/bridge3_recoverable_execution_slot_v1.gd")
const R5Source = preload("res://scripts/research/fabric_bake0/complex3_streaming_canonical_structure_v1.gd")

var _r5_range_index: Dictionary = {}

func attach_range_index(index: Dictionary, subject: Dictionary) -> Dictionary:
	var checked := RangeIndex.validate(index, subject.spec)
	if not checked.success:
		return checked
	_r5_range_index = index
	if not _work.has("range_query_count"):
		_work["range_query_count"] = 0
	if not _work.has("range_query_prefix_reads"):
		_work["range_query_prefix_reads"] = 0
	return R5U.success({"summary_hash": String(index.summary_hash)})

func _r5_query(spec: Dictionary, first: int, end_exclusive: int) -> Dictionary:
	if _r5_range_index.is_empty():
		return R5U.failure("R5_1_RANGE_INDEX_NOT_ATTACHED")
	var result := RangeIndex.aggregate(_r5_range_index, spec, first, end_exclusive)
	if result.success:
		_work["range_query_count"] = int(_work.get("range_query_count", 0)) + 1
		_work["range_query_prefix_reads"] = int(_work.get("range_query_prefix_reads", 0)) + int(result.details.prefix_reads)
	return result

func local_unbake(tick: int, impact_load: float = IMPACT_LOAD) -> Dictionary:
	if not _slot.can_execute(_subject.get("frontier", {})) or _slot.snapshot().get("mode") != "STRUCTURAL_BAKE":
		return R5U.failure("COMPLEX3_LOCAL_UNBAKE_REQUIRES_BAKE")
	if not is_finite(impact_load) or impact_load / WEAK_FORCE_CAPACITY < TRIGGER_RATIO:
		return R5U.failure("COMPLEX3_CERTIFIED_GUARD_NOT_TRIGGERED")
	var count := int(_subject.spec.part_count)
	var first := R5Source.target_region_start(count)
	var end := mini(first + R5Source.REGION_SIZE, count)
	var full: Dictionary = {}
	for index in range(first, end):
		full[R5Source.part_id(index)] = R5Source.local_part_state(_parent_state, _parent.center_of_mass, index)
	var residual: Dictionary = {}
	var descriptors: Array = []
	if first > 0:
		var left := _r5_query(_subject.spec, 0, first)
		if not left.success: return left
		var ld: Dictionary = left.details.descriptor
		residual["component/complex3-left"] = {"descriptor": ld, "state": R5Source.span_state(_parent_state, _parent.center_of_mass, ld)}
		descriptors.append({"component_id": "component/complex3-left", "descriptor": ld})
	if end < count:
		var right := _r5_query(_subject.spec, end, count)
		if not right.success: return right
		var rd: Dictionary = right.details.descriptor
		residual["component/complex3-right"] = {"descriptor": rd, "state": R5Source.span_state(_parent_state, _parent.center_of_mass, rd)}
		descriptors.append({"component_id": "component/complex3-right", "descriptor": rd})
	var continuity := _continuity(full, residual, first, end)
	if not continuity.success: return continuity
	var owned := _ownership(_subject, "LOCAL_FULL", descriptors)
	if not owned.success: return owned
	var payload := {"parent_descriptor": _parent.duplicate(true), "parent_state": _parent_state.duplicate(true),
		"full": full, "residual": residual, "ownership": owned.details.contract}
	var prepared := _slot.prepare("transition/complex3-unbake-%d" % tick, "LOCAL_FULL", payload, tick, _subject.frontier)
	if not prepared.success: return prepared
	var committed := _slot.commit(prepared.details.ticket, _subject.frontier)
	if committed.success and committed.details.applied:
		_work.local_reconstructed_parts += full.size()
		_work.active_full_peak = maxi(int(_work.active_full_peak), full.size())
		_work.residual_state_transfers += residual.size()
		_work.actual_transitions += 1
		committed.details.continuity = continuity.details
	return committed

func rebake_after_settle(settled: bool = false) -> Dictionary:
	if _pending_mutation.is_empty(): return R5U.failure("COMPLEX3_NO_PENDING_MUTATION")
	if not settled: return R5U.failure("COMPLEX3_REBAKE_REQUIRES_SETTLE")
	var old_cell: Dictionary = _pending_mutation.checkpoint.cell
	var old_payload: Dictionary = old_cell.payload
	var successor: Dictionary = _pending_mutation.successor
	var count := int(successor.spec.part_count)
	var cut := int(successor.spec.break_index)
	var left := _r5_query(successor.spec, 0, cut)
	if not left.success: return left
	var right := _r5_query(successor.spec, cut, count)
	if not right.success: return right
	var descriptors := [
		{"component_id": "component/complex3-rebaked-left", "descriptor": left.details.descriptor},
		{"component_id": "component/complex3-rebaked-right", "descriptor": right.details.descriptor},
	]
	var residual: Dictionary = {}
	for row in descriptors:
		var desc: Dictionary = row.descriptor
		residual[row.component_id] = {"descriptor": desc, "state": R5Source.span_state(_parent_state, _parent.center_of_mass, desc)}
	var local_validations := 0
	for part_key in old_payload.full:
		var index := int(String(part_key).get_slice("-", 1))
		var chosen: Dictionary = left.details.descriptor if index < cut else right.details.descriptor
		var candidate_state := R5Source.span_state(_parent_state, _parent.center_of_mass, chosen)
		var from_candidate := R5H.shift(candidate_state, R5H.a(R5H.v(R5Source.part_position(index)) - R5H.v(chosen.center_of_mass)))
		if R5H.error(from_candidate, old_payload.full[part_key]) > ABS_TOL:
			return R5U.failure("COMPLEX3_REBAKE_LOCAL_CONTINUITY_FAILED", {"part_id": part_key})
		local_validations += 1
	var owned := _ownership(successor, "REBAKED", descriptors)
	if not owned.success: return owned
	var payload := {"parent_descriptor": _parent.duplicate(true), "parent_state": _parent_state.duplicate(true),
		"full": {}, "residual": residual, "ownership": owned.details.contract,
		"event_id": _pending_mutation.event_id}
	var next := R5Slot.new()
	var rebound := next.rebind(old_cell, _pending_mutation.checkpoint.receipts, _pending_mutation.checkpoint.tickets,
		successor.frontier, successor.authority, "REBAKED", payload, int(_pending_mutation.tick), String(_pending_mutation.event_id))
	if not rebound.success: return rebound
	_slot = next
	_subject = successor.duplicate(true)
	_applied_events.append(String(_pending_mutation.event_id)); _applied_events.sort()
	_work.rebake_local_validations += local_validations
	_work.rebaked_components += 2
	_work.actual_transitions += 1
	_pending_mutation = {}
	return R5U.success({"local_validations": local_validations, "component_count": 2, "receipt": rebound.details.receipt})
