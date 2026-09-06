extends RefCounted
## COMPLEX3 large-scale sparse lifecycle. BRIDGE-3 already proves FULL→BAKE;
## this scale subject begins in a certified baked state and stresses local reveal/rebake.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const H = preload("res://scripts/research/fabric_bake0/bridge3_rigid_handoff_v1.gd")
const Slot = preload("res://scripts/research/fabric_bake0/bridge3_recoverable_execution_slot_v1.gd")
const Ownership = preload("res://scripts/research/fabric_bake0/mixed_representation_ownership_contract_v1.gd")
const Source = preload("res://scripts/research/fabric_bake0/complex3_streaming_canonical_structure_v1.gd")

const IMPACT_LOAD := 36.0
const WEAK_FORCE_CAPACITY := 40.0
const TRIGGER_RATIO := 0.80
const ABS_TOL := 1.0e-8
const REL_TOL := 1.0e-12

var _slot := Slot.new()
var _subject: Dictionary = {}
var _parent: Dictionary = {}
var _parent_state: Dictionary = {}
var _pending_mutation: Dictionary = {}
var _applied_events: Array = []
var _work := {"metadata_parts_scanned": 0, "active_full_peak": 0, "local_reconstructed_parts": 0,
	"residual_state_transfers": 0, "rebake_local_validations": 0, "rebaked_components": 0,
	"invalidated_artifacts": 0, "canonical_mutations_observed": 0, "global_physical_rebuilds": 0,
	"duplicate_ownership_count": 0, "actual_transitions": 0}

func start_baked(subject: Dictionary, parent_descriptor: Dictionary, parent_state: Dictionary, tick: int = 0) -> Dictionary:
	if not _subject.is_empty() or not Source.validate_subject(subject, false).success or not _state_ok(parent_state):
		return U.failure("COMPLEX3_START_INVALID")
	if parent_descriptor.get("schema") != Source.AGGREGATE_SCHEMA or parent_descriptor.get("source_checksum") != subject.spec.checksum or int(parent_descriptor.get("first_part", -1)) != 0 or int(parent_descriptor.get("end_exclusive", -1)) != int(subject.spec.part_count):
		return U.failure("COMPLEX3_PARENT_BINDING_INVALID")
	var owned := _ownership(subject, "STRUCTURAL_BAKE", [])
	if not owned.success: return owned
	var payload := {"parent_descriptor": parent_descriptor.duplicate(true), "parent_state": parent_state.duplicate(true),
		"full": {}, "residual": {"component/complex3-parent": {"descriptor": parent_descriptor.duplicate(true), "state": parent_state.duplicate(true)}},
		"ownership": owned.details.contract}
	var started := _slot.start(subject.frontier, subject.authority, "STRUCTURAL_BAKE", payload, tick)
	if not started.success: return started
	_subject = subject.duplicate(true)
	_parent = parent_descriptor.duplicate(true)
	_parent_state = parent_state.duplicate(true)
	return U.success({"writer": _slot.writer()})

func local_unbake(tick: int, impact_load: float = IMPACT_LOAD) -> Dictionary:
	if not _slot.can_execute(_subject.get("frontier", {})) or _slot.snapshot().get("mode") != "STRUCTURAL_BAKE":
		return U.failure("COMPLEX3_LOCAL_UNBAKE_REQUIRES_BAKE")
	if not is_finite(impact_load) or impact_load / WEAK_FORCE_CAPACITY < TRIGGER_RATIO:
		return U.failure("COMPLEX3_CERTIFIED_GUARD_NOT_TRIGGERED")
	var count := int(_subject.spec.part_count)
	var first := Source.target_region_start(count)
	var end := mini(first + Source.REGION_SIZE, count)
	var full: Dictionary = {}
	for index in range(first, end):
		full[Source.part_id(index)] = Source.local_part_state(_parent_state, _parent.center_of_mass, index)
	var residual: Dictionary = {}
	var descriptors: Array = []
	if first > 0:
		var left := Source.aggregate_span(_subject.spec, 0, first)
		if not left.success: return left
		_work.metadata_parts_scanned += int(left.details.parts_scanned)
		var ld: Dictionary = left.details.descriptor
		residual["component/complex3-left"] = {"descriptor": ld, "state": Source.span_state(_parent_state, _parent.center_of_mass, ld)}
		descriptors.append({"component_id": "component/complex3-left", "descriptor": ld})
	if end < count:
		var right := Source.aggregate_span(_subject.spec, end, count)
		if not right.success: return right
		_work.metadata_parts_scanned += int(right.details.parts_scanned)
		var rd: Dictionary = right.details.descriptor
		residual["component/complex3-right"] = {"descriptor": rd, "state": Source.span_state(_parent_state, _parent.center_of_mass, rd)}
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

func observe_canonical_break(successor: Dictionary, event_id: String, tick: int) -> Dictionary:
	if not _pending_mutation.is_empty() or _slot.snapshot().get("mode") != "LOCAL_FULL" or _applied_events.has(event_id):
		return U.failure("COMPLEX3_MUTATION_ORDER_INVALID")
	if not U.is_canonical_id(event_id, 2) or not U.is_json_integer(tick) or tick <= int(_slot.snapshot().get("tick", -1)):
		return U.failure("COMPLEX3_MUTATION_ORDER_INVALID")
	if not Source.is_successor(_subject, successor):
		return U.failure("COMPLEX3_MUTATION_SOURCE_INVALID")
	if String(successor.spec.broken_bond_id) != String(_subject.spec.break_bond_id):
		return U.failure("COMPLEX3_MUTATION_BREAK_INVALID")
	var saved := _slot.checkpoint()
	if not saved.success: return saved
	_pending_mutation = {"previous_subject": _subject.duplicate(true), "successor": successor.duplicate(true),
		"event_id": event_id, "tick": tick, "checkpoint": saved.details.duplicate(true)}
	_slot.invalidate()
	_work.canonical_mutations_observed += 1
	_work.invalidated_artifacts += 1
	return U.success({"old_writer_fenced": _slot.writer().is_empty()})

func rebake_after_settle(settled: bool = false) -> Dictionary:
	if _pending_mutation.is_empty(): return U.failure("COMPLEX3_NO_PENDING_MUTATION")
	if not settled: return U.failure("COMPLEX3_REBAKE_REQUIRES_SETTLE")
	var old_cell: Dictionary = _pending_mutation.checkpoint.cell
	var old_payload: Dictionary = old_cell.payload
	var successor: Dictionary = _pending_mutation.successor
	var count := int(successor.spec.part_count)
	var cut := int(successor.spec.break_index)
	var left := Source.aggregate_span(successor.spec, 0, cut)
	if not left.success: return left
	var right := Source.aggregate_span(successor.spec, cut, count)
	if not right.success: return right
	_work.metadata_parts_scanned += int(left.details.parts_scanned) + int(right.details.parts_scanned)
	var descriptors := [
		{"component_id": "component/complex3-rebaked-left", "descriptor": left.details.descriptor},
		{"component_id": "component/complex3-rebaked-right", "descriptor": right.details.descriptor},
	]
	var residual: Dictionary = {}
	for row in descriptors:
		var desc: Dictionary = row.descriptor
		residual[row.component_id] = {"descriptor": desc, "state": Source.span_state(_parent_state, _parent.center_of_mass, desc)}
	var local_validations := 0
	for part_key in old_payload.full:
		var index := int(String(part_key).get_slice("-", 1))
		var chosen: Dictionary = left.details.descriptor if index < cut else right.details.descriptor
		var candidate_state := Source.span_state(_parent_state, _parent.center_of_mass, chosen)
		var from_candidate := H.shift(candidate_state, H.a(H.v(Source.part_position(index)) - H.v(chosen.center_of_mass)))
		if H.error(from_candidate, old_payload.full[part_key]) > ABS_TOL:
			return U.failure("COMPLEX3_REBAKE_LOCAL_CONTINUITY_FAILED", {"part_id": part_key})
		local_validations += 1
	var owned := _ownership(successor, "REBAKED", descriptors)
	if not owned.success: return owned
	var payload := {"parent_descriptor": _parent.duplicate(true), "parent_state": _parent_state.duplicate(true),
		"full": {}, "residual": residual, "ownership": owned.details.contract,
		"event_id": _pending_mutation.event_id}
	var next := Slot.new()
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
	return U.success({"local_validations": local_validations, "component_count": 2, "receipt": rebound.details.receipt})

func capture_capsule() -> Dictionary:
	var phase := "ACTIVE"
	var binding := _subject
	var checkpoint: Dictionary = {}
	var pending: Dictionary = {}
	if not _pending_mutation.is_empty():
		phase = "MUTATION_FENCED"
		binding = _pending_mutation.successor
		checkpoint = _pending_mutation.checkpoint.duplicate(true)
		pending = {"previous_subject": _pending_mutation.previous_subject.duplicate(true), "event_id": _pending_mutation.event_id, "tick": _pending_mutation.tick}
	else:
		var saved := _slot.checkpoint()
		if not saved.success: return saved
		checkpoint = saved.details.duplicate(true)
	var capsule := {"schema": "planet_simulator.fabric_complex3_runtime_capsule.v1", "canonical": false,
		"derived": true, "discardable": true, "phase": phase, "subject_checksum": binding.spec.checksum,
		"frontier_checksum": binding.frontier.checksum, "authority_checksum": binding.authority.checksum,
		"checkpoint": checkpoint, "pending": pending, "parent": _parent.duplicate(true), "parent_state": _parent_state.duplicate(true),
		"applied_events": _applied_events.duplicate(), "work": _work.duplicate(true), "checksum": ""}
	capsule.checksum = U.compute_checksum(capsule)
	return U.success({"capsule": capsule})

func restore_capsule(subject: Dictionary, capsule: Dictionary) -> Dictionary:
	if not _subject.is_empty() or not Source.validate_subject(subject, false).success:
		return U.failure("COMPLEX3_RESTORE_REQUIRES_NEW_RUNTIME")
	if capsule.get("schema") != "planet_simulator.fabric_complex3_runtime_capsule.v1" or capsule.get("canonical") != false or capsule.get("derived") != true or capsule.get("discardable") != true or not U.validate_checksum(capsule).success:
		return U.failure("COMPLEX3_CAPSULE_INVALID")
	if capsule.subject_checksum != subject.spec.checksum or capsule.frontier_checksum != subject.frontier.checksum or capsule.authority_checksum != subject.authority.checksum:
		return U.failure("COMPLEX3_CAPSULE_STALE")
	var restored := Slot.new()
	if capsule.phase == "ACTIVE":
		var r := restored.restore(capsule.checkpoint, subject.frontier, subject.authority)
		if not r.success: return r
		_slot = restored
	elif capsule.phase == "MUTATION_FENCED":
		if typeof(capsule.get("pending")) != TYPE_DICTIONARY or not capsule.pending.has_all(["previous_subject", "event_id", "tick"]):
			return U.failure("COMPLEX3_CAPSULE_PENDING_INVALID")
		var previous: Dictionary = capsule.pending.previous_subject
		if not Source.is_successor(previous, subject): return U.failure("COMPLEX3_CAPSULE_PENDING_SOURCE_INVALID")
		var r := restored.restore(capsule.checkpoint, previous.frontier, previous.authority)
		if not r.success: return r
		restored.invalidate(); _slot = restored
		_pending_mutation = {"previous_subject": previous.duplicate(true), "successor": subject.duplicate(true),
			"event_id": capsule.pending.event_id, "tick": capsule.pending.tick, "checkpoint": capsule.checkpoint.duplicate(true)}
	else:
		return U.failure("COMPLEX3_CAPSULE_PHASE_INVALID")
	_subject = subject.duplicate(true)
	_parent = capsule.parent.duplicate(true)
	_parent_state = capsule.parent_state.duplicate(true)
	_applied_events = capsule.applied_events.duplicate()
	_work = capsule.work.duplicate(true)
	return U.success({"mode": "MUTATION_FENCED" if capsule.phase == "MUTATION_FENCED" else _slot.snapshot().mode, "writer": _slot.writer()})

func execute_boundary(subject: Dictionary) -> Dictionary:
	if subject.get("spec", {}).get("checksum", "") != _subject.get("spec", {}).get("checksum", "") or not _slot.can_execute(subject.get("frontier", {})):
		return U.failure("COMPLEX3_STALE_EXECUTION")
	var mode: String = _slot.snapshot().mode
	if not ["STRUCTURAL_BAKE", "LOCAL_FULL", "REBAKED"].has(mode): return U.failure("COMPLEX3_MODE_NOT_EXECUTABLE")
	return U.success({"mode": mode})

func status() -> Dictionary:
	if _subject.is_empty(): return {"mode": "UNINITIALIZED", "writer": "", "work": _work.duplicate(true)}
	var cell: Dictionary = _slot.snapshot()
	var mode := "MUTATION_FENCED" if not _pending_mutation.is_empty() else String(cell.get("mode", ""))
	var full_count: int = 0 if not cell.has("payload") else int(cell.payload.get("full", {}).size())
	var reduced_count: int = 0 if not cell.has("payload") else int(cell.payload.get("residual", {}).size())
	return {"mode": mode, "writer": _slot.writer(), "transition_count": int(cell.get("transition_count", 0)),
		"transition_hash": String(cell.get("transition_hash", "")), "active_full_parts": full_count,
		"active_reduced_bodies": reduced_count, "applied_events": _applied_events.duplicate(), "work": _work.duplicate(true),
		"source_checksum": _subject.spec.checksum, "ownership": cell.get("payload", {}).get("ownership", {}).duplicate(true)}

func _continuity(full: Dictionary, residual: Dictionary, first: int, end: int) -> Dictionary:
	var rows: Array = []
	for id in full:
		var index := int(String(id).get_slice("-", 1))
		var part := Source.part_model(index)
		rows.append(H.totals(part.mass, part.inertia_tensor, full[id], _parent_state.position))
	for id in residual:
		var row: Dictionary = residual[id]
		rows.append(H.totals(row.descriptor.total_mass, row.descriptor.inertia_tensor_body, row.state, _parent_state.position))
	var before := H.totals(_parent.total_mass, _parent.inertia_tensor_body, _parent_state, _parent_state.position)
	var after := H.sum_totals(rows)
	var errors := H.conservation_error(before, after)
	for field in errors:
		var scale := absf(float(before[field])) if field in ["mass", "energy"] else H.v(before[field]).length()
		if float(errors[field]) > ABS_TOL + REL_TOL * maxf(1.0, scale):
			return U.failure("COMPLEX3_HANDOFF_CONSERVATION_FAILED", {"field": field, "errors": errors, "before": before, "after": after})
	var boundary_error := 0.0
	if first > 0:
		boundary_error = maxf(boundary_error, _interface_error(first - 1, first, residual["component/complex3-left"], full[Source.part_id(first)]))
	if end < int(_subject.spec.part_count):
		boundary_error = maxf(boundary_error, _interface_error(end, end - 1, residual["component/complex3-right"], full[Source.part_id(end - 1)]))
	if boundary_error > ABS_TOL: return U.failure("COMPLEX3_BOUNDARY_DISCONTINUITY", {"error": boundary_error})
	return U.success({"conservation_error": errors, "boundary_error": boundary_error})

func _interface_error(residual_index: int, local_index: int, residual: Dictionary, local_state: Dictionary) -> float:
	var midpoint := (H.v(Source.part_position(residual_index)) + H.v(Source.part_position(local_index))) * 0.5
	var residual_point := H.shift(residual.state, H.a(midpoint - H.v(residual.descriptor.center_of_mass)))
	var local_point := H.shift(local_state, H.a(midpoint - H.v(Source.part_position(local_index))))
	return H.error(residual_point, local_point)

func _ownership(subject: Dictionary, mode: String, components: Array) -> Dictionary:
	var reps: Array = []; var regions: Array = []
	var rows: Array = []
	if mode == "STRUCTURAL_BAKE": rows = [{"id": "region/complex3-all", "kind": "STRUCTURAL_BAKE"}]
	elif mode == "LOCAL_FULL":
		rows = [{"id": "region/complex3-local", "kind": "FULL"}]
		for component in components: rows.append({"id": component.component_id, "kind": "STRUCTURAL_BAKE"})
	elif mode == "REBAKED":
		for component in components: rows.append({"id": component.component_id, "kind": "STRUCTURAL_BAKE"})
	else: return U.failure("COMPLEX3_OWNERSHIP_MODE_INVALID")
	for row in rows:
		var rid := "representation/" + String(row.id).replace("/", "-")
		reps.append({"representation_id": rid, "representation_kind": row.kind, "derived_only": true,
			"canonical_write_authorized": false, "source_frontier_hash": subject.frontier.frontier_hash,
			"authority_epoch_binding": subject.authority.authority_epoch_binding})
		regions.append({"region_id": row.id, "representation_id": rid, "ownership_role": "ACTIVE_EXECUTION"})
	return Ownership.compile(subject.frontier, subject.authority, reps, regions)

static func _state_ok(value: Dictionary) -> bool:
	return value.has_all(["position", "orientation", "linear_velocity", "angular_velocity"]) and Slot.json_safe(value)
