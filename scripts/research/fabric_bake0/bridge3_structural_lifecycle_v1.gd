extends RefCounted
## Stateful consumer of closed FABRIC compilers. Immutable geometry is indexed once.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Slot = preload("res://scripts/research/fabric_bake0/bridge3_execution_slot_v1.gd")
const H = preload("res://scripts/research/fabric_bake0/bridge3_rigid_handoff_v1.gd")
const R = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/structural_aggregate_descriptor_v1.gd")
const GuardField = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_field_descriptor_v1.gd")
const Guard = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_runtime_v1.gd")
const Plan = preload("res://scripts/research/fabric_bake0/structural_local_unbake_plan_v1.gd")
const SourceView = preload("res://scripts/research/fabric_bake0/physical_source_view_v1.gd")
const Lifecycle = preload("res://scripts/research/fabric_bake0/physical_source_lifecycle_v1.gd")
const Envelope = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_envelope_v1.gd")
const Selector = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_selector_v1.gd")
const Controller = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_controller_v1.gd")
const Ownership = preload("res://scripts/research/fabric_bake0/mixed_representation_ownership_contract_v1.gd")
const ABS_TOL := 1.0e-8
const REL_TOL := 1.0e-12
var _slot := Slot.new()
var _bundle: Dictionary = {}
var _plan: Dictionary = {}
var _field: Dictionary = {}
var _index: Dictionary = {}
var _target_index: Dictionary = {}
var _anchor_index: Dictionary = {}
var _controller: Dictionary = {}
var _parent_state: Dictionary = {}
var _pending_controller: Dictionary = {}
var _pending_ticket := ""
var _work := {"metadata_parts_indexed": 0, "projected_parts": 0, "reconstructed_parts": 0,
	"residual_state_transfers": 0, "guard_parts_evaluated": 0, "full_snapshot_parts": 0,
	"actual_transitions": 0, "global_physical_rebuilds": 0, "duplicate_ownership_count": 0}

func start(bundle: Dictionary, guard_field: Dictionary, plan: Dictionary, full_states: Dictionary, tick: int = 0) -> Dictionary:
	if not _bundle.is_empty() or not bundle.has_all(["aggregate", "source_view", "artifact"]):
		return U.failure("BRIDGE3_INVALID_BUNDLE")
	if typeof(bundle.aggregate) != TYPE_DICTIONARY or typeof(bundle.source_view) != TYPE_DICTIONARY or typeof(bundle.artifact) != TYPE_DICTIONARY:
		return U.failure("BRIDGE3_INVALID_BUNDLE_FIELDS")
	var view_check := _check_view(bundle.source_view)
	if not view_check.success:
		return view_check
	var ag: Dictionary = bundle.aggregate
	if not ag.has_all(["descriptor", "reconstruction_mapping"]) or typeof(ag.descriptor) != TYPE_DICTIONARY or typeof(ag.reconstruction_mapping) != TYPE_DICTIONARY:
		return U.failure("BRIDGE3_INVALID_AGGREGATE")
	for result in [Descriptor.validate(ag.descriptor), R.validate(ag.reconstruction_mapping),
		GuardField.validate(guard_field), Plan.validate(plan)]:
		if not result.get("success", false):
			return result
	var frontier: Dictionary = bundle.source_view.frontier
	if plan.parent_structural_descriptor_hash != ag.descriptor.checksum or plan.parent_reconstruction_mapping_hash != ag.reconstruction_mapping.checksum or plan.guard_field_hash != guard_field.checksum or plan.source_frontier_hash != frontier.frontier_hash or guard_field.source_frontier_hash != frontier.frontier_hash or guard_field.structural_descriptor_hash != ag.descriptor.checksum or guard_field.reconstruction_mapping_hash != ag.reconstruction_mapping.checksum:
		return U.failure("BRIDGE3_BINDING_MISMATCH")
	var projected := R.project(ag.reconstruction_mapping, full_states, ABS_TOL)
	if not projected.get("success", false):
		return projected
	var executable := Lifecycle.execute(bundle, projected.details.reduced_state)
	if not executable.get("success", false):
		return executable
	var source: Dictionary = {}
	for item in frontier.sources:
		if item.source_domain == "CONSTRUCTION":
			source = item
	var controller := Controller.create(source, "FULL_FABRIC", Controller.DEFAULT_CONFIG, tick)
	if not controller.get("success", false):
		return controller
	var payload := {"full": full_states, "reduced": {}, "residual": {}, "ownership": {}}
	var owned := _ownership(frontier, bundle.source_view.authority_envelope, "FULL", [])
	if not owned.get("success", false):
		return owned
	payload.ownership = owned.details.contract
	var started := _slot.start(frontier, bundle.source_view.authority_envelope, "FULL", payload, tick)
	if not started.success:
		return started
	_bundle = bundle.duplicate(true)
	_plan = plan.duplicate(true)
	_field = guard_field.duplicate(true)
	_controller = controller.details.state
	_parent_state = projected.details.reduced_state.duplicate(true)
	var targets: Dictionary = {}
	for id in _plan.target_part_ids:
		targets[id] = true
	for mapping in ag.reconstruction_mapping.part_mappings:
		_index[mapping.part_id] = mapping.duplicate(true)
		if targets.has(mapping.part_id):
			_target_index[mapping.part_id] = _index[mapping.part_id]
	for component in _plan.residual_components:
		for anchor in component.descriptor.boundary_anchors:
			_anchor_index[component.component_id + "|" + anchor.anchor_id] = anchor.duplicate(true)
	_work.metadata_parts_indexed = _index.size()
	_work.projected_parts = full_states.size()
	return U.success({"writer": _slot.writer()})

# A/B/C are reused for scheduling; only FULL and STRUCTURAL are supported here.
func consider_bake(tick: int, context: Dictionary) -> Dictionary:
	if not _slot.can_execute(_frontier()) or _slot.snapshot().mode != "FULL":
		return U.failure("BRIDGE3_BAKE_REQUIRES_FULL")
	_slot.abort()
	_pending_ticket = ""
	_pending_controller = {}
	var checked := _assess(tick, context)
	if not checked.success:
		return checked
	var result: Dictionary = checked.details
	if result.transition.is_empty():
		_controller = result.state
		return U.success({"ready": false})
	var full: Dictionary = _slot.snapshot().payload.full
	var projected := R.project(_bundle.aggregate.reconstruction_mapping, full, ABS_TOL)
	_work.projected_parts += full.size()
	if not projected.success:
		return projected
	var gate := Lifecycle.execute(_bundle, projected.details.reduced_state)
	if not gate.success:
		return gate
	var owned := _ownership(_frontier(), _authority(), "STRUCTURAL_BAKE", [])
	if not owned.success:
		return owned
	var payload := {"full": {}, "reduced": projected.details.reduced_state, "residual": {}, "ownership": owned.details.contract}
	var prepared := _slot.prepare("transition/bake-%d" % tick, "STRUCTURAL_BAKE", payload, tick, _frontier())
	if not prepared.success:
		return prepared
	_pending_controller = result.state
	_pending_ticket = prepared.details.ticket
	return U.success({"ready": true, "ticket": _pending_ticket})

func commit(ticket: String, live_frontier: Dictionary) -> Dictionary:
	var committed := _slot.commit(ticket, live_frontier)
	if committed.success and committed.details.applied:
		_controller = _pending_controller
		_pending_controller = {}
		_pending_ticket = ""
		_work.actual_transitions += 1
	return committed

func local_unbake(tick: int, context: Dictionary, live_frontier: Dictionary) -> Dictionary:
	if not _slot.can_execute(live_frontier) or _slot.snapshot().mode != "STRUCTURAL_BAKE":
		return U.failure("BRIDGE3_UNBAKE_REQUIRES_LIVE_BAKE")
	var guard := _evaluate_guard(context, _parent_state)
	if not guard.success:
		return guard
	if guard.status != Guard.REFINEMENT_REQUIRED or guard.refinement_requests.size() != 1 or guard.refinement_requests[0].mapped_source_region != _plan.target_region_id:
		return U.failure("BRIDGE3_CERTIFIED_LOCAL_GUARD_REQUIRED")
	var assessment := _assess_guard(tick, guard)
	if not assessment.success or assessment.details.transition.is_empty():
		return U.failure("BRIDGE3_IMMEDIATE_PROMOTION_REQUIRED")
	var parent: Dictionary = _slot.snapshot().payload.reduced
	var full: Dictionary = {}
	for id in _target_index:
		full[id] = H.part_state(parent, _target_index[id])
	_work.reconstructed_parts += full.size()
	var residual: Dictionary = {}
	for component in _plan.residual_components:
		var delta := H.v(component.descriptor.center_of_mass) - H.v(_bundle.aggregate.descriptor.center_of_mass)
		residual[component.component_id] = H.shift(parent, H.a(delta))
	_work.residual_state_transfers += residual.size()
	var evidence := _continuity(parent, full, residual)
	if not evidence.success:
		return evidence
	var owned := _ownership(_frontier(), _authority(), "LOCAL_FULL", _plan.residual_components)
	if not owned.success:
		return owned
	var payload := {"full": full, "reduced": {}, "residual": residual, "ownership": owned.details.contract}
	var prepared := _slot.prepare("transition/unbake-%d" % tick, "LOCAL_FULL", payload, tick, live_frontier)
	if not prepared.success:
		return prepared
	_pending_ticket = prepared.details.ticket
	_pending_controller = assessment.details.state
	var committed := commit(_pending_ticket, live_frontier)
	if committed.success:
		committed.details.continuity = evidence.details
	return committed

# Accept output from an existing authoritative solver, not a new integrator.
# The old writer token and any old preparation are fenced at the same publication.
func accept_baked_solver_state(expected_writer: String, state: Dictionary, tick: int, context: Dictionary, live_frontier: Dictionary) -> Dictionary:
	if not _slot.can_execute(live_frontier) or _slot.snapshot().mode != "STRUCTURAL_BAKE":
		return U.failure("BRIDGE3_SOLVER_REQUIRES_LIVE_BAKE")
	var checked := R._validate_state(state)
	if not checked.success:
		return checked
	var guard := _evaluate_guard(context, state)
	if not guard.success or guard.status != Guard.SAFE:
		return U.failure("BRIDGE3_REFINEMENT_REQUIRED_BEFORE_EXECUTION")
	var payload: Dictionary = _slot.snapshot().payload
	payload.reduced = state.duplicate(true)
	var written := _slot.accept_physical_state(expected_writer, payload, tick, live_frontier)
	if written.success:
		_parent_state = state.duplicate(true)
		_pending_controller = {}
		_pending_ticket = ""
	return written

func execute_boundary(live_frontier: Dictionary) -> Dictionary:
	if not _slot.can_execute(live_frontier) or _slot.snapshot().mode != "STRUCTURAL_BAKE":
		return U.failure("BRIDGE3_BOUNDARY_REQUIRES_LIVE_BAKE")
	return Lifecycle.execute(_bundle, _slot.snapshot().payload.reduced)

# Explicit diagnostic/oracle surface, never called by local_unbake.
func full_snapshot(live_frontier: Dictionary) -> Dictionary:
	if not _slot.can_execute(live_frontier):
		return U.failure("BRIDGE3_STALE_SNAPSHOT")
	var cell := _slot.snapshot()
	var full: Dictionary = cell.payload.full.duplicate(true)
	if cell.mode == "STRUCTURAL_BAKE":
		var r := R.reconstruct(_bundle.aggregate.reconstruction_mapping, cell.payload.reduced)
		if not r.success:
			return r
		full = r.details.full_states
	elif cell.mode == "LOCAL_FULL":
		for component in _plan.residual_components:
			var r := R.reconstruct(component.reconstruction_mapping, cell.payload.residual[component.component_id])
			if not r.success:
				return r
			for id in r.details.full_states:
				if full.has(id):
					_work.duplicate_ownership_count += 1
					return U.failure("BRIDGE3_DUPLICATE_PART_OWNER")
				full[id] = r.details.full_states[id]
	_work.full_snapshot_parts += full.size()
	return U.success({"full_states": full})

func status() -> Dictionary:
	if _bundle.is_empty():
		return {"mode": "UNINITIALIZED", "writer": "", "work": _work.duplicate(true)}
	var cell := _slot.snapshot()
	return {"mode": cell.mode, "writer": _slot.writer(), "transition_epoch": cell.transition_epoch,
		"transition_count": cell.transition_count, "transition_hash": cell.transition_hash,
		"active_full_parts": cell.payload.full.size(),
		"active_reduced_bodies": cell.payload.residual.size() + (0 if cell.payload.reduced.is_empty() else 1),
		"work": _work.duplicate(true), "ownership": cell.payload.ownership.duplicate(true)}

func invalidate() -> void:
	_slot.invalidate()
	_pending_controller = {}
	_pending_ticket = ""

func _assess(tick: int, context: Dictionary) -> Dictionary:
	var guard := _evaluate_guard(context, _parent_state)
	return _assess_guard(tick, guard)

func _evaluate_guard(context: Dictionary, state: Dictionary) -> Dictionary:
	if not Slot.json_safe(context) or typeof(context.get("angular_velocity_body")) != TYPE_ARRAY or context.angular_velocity_body.size() != 3:
		return U.failure("BRIDGE3_INVALID_GUARD_CONTEXT")
	for number in context.angular_velocity_body:
		if not U.is_finite_number(number):
			return U.failure("BRIDGE3_INVALID_GUARD_ANGULAR_VELOCITY")
	if H.v(context.angular_velocity_body).distance_to(H.q(state.orientation).inverse() * H.v(state.angular_velocity)) > ABS_TOL:
		return U.failure("BRIDGE3_GUARD_PHYSICAL_STATE_MISMATCH")
	_work.guard_parts_evaluated += _index.size()
	return Guard.evaluate(_field, context)

func _assess_guard(tick: int, guard: Dictionary) -> Dictionary:
	if not guard.success:
		return guard
	var candidates: Array = []
	for level in Envelope.LEVELS:
		candidates.append({"fidelity_id": level, "available": level == "FULL_FABRIC" or (level == "STRUCTURAL_BAKE" and guard.status == Guard.SAFE),
			"source_fresh": true, "reconstruction_ready": true, "passive_stable": true,
			"error_bound": 0.0, "allowed_error_bound": ABS_TOL, "validity_margin": 1.0,
			"guard_margin": 1.0, "pending_refinement_guards": [], "causal_dependencies": [],
			"dormancy_certified": false, "estimated_cost": 100.0 if level == "FULL_FABRIC" else 1.0})
	var envelope := Envelope.compile(_controller.current_fidelity, candidates)
	if not envelope.success:
		return envelope
	var decision := Selector.select(envelope.details.envelope, _controller.current_fidelity, "CHEAPEST_SAFE")
	if not decision.success:
		return decision
	return Controller.evaluate(_controller, envelope.details.envelope, decision.details.decision, tick)

func _continuity(parent: Dictionary, full: Dictionary, residual: Dictionary) -> Dictionary:
	var boundary_error := 0.0
	for edge in _plan.cut_interfaces:
		var anchor: Dictionary = _anchor_index[edge.residual_component_id + "|" + edge.residual_anchor_id]
		var left := H.shift(full[edge.full_part_id], edge.full_position_local)
		var right := H.shift(residual[edge.residual_component_id], anchor.position_from_com)
		boundary_error = maxf(boundary_error, H.v(left.position).distance_to(H.v(right.position)))
		boundary_error = maxf(boundary_error, H.v(left.linear_velocity).distance_to(H.v(right.linear_velocity)))
	if boundary_error > ABS_TOL:
		return U.failure("BRIDGE3_INTERFACE_DISCONTINUITY")
	var descriptor: Dictionary = _bundle.aggregate.descriptor
	var before := H.totals(descriptor.total_mass, descriptor.inertia_tensor_body, parent, parent.position)
	var rows: Array = []
	for part in _plan.target_part_models:
		rows.append(H.totals(part.mass, part.inertia_tensor, full[part.part_id], parent.position))
	for component in _plan.residual_components:
		rows.append(H.totals(component.descriptor.total_mass, component.descriptor.inertia_tensor_body,
			residual[component.component_id], parent.position))
	var after := H.sum_totals(rows)
	var errors := H.conservation_error(before, after)
	for field in errors:
		var scale: float = before[field] if field in ["mass", "energy"] else H.v(before[field]).length()
		if errors[field] > ABS_TOL + REL_TOL * absf(scale):
			return U.failure("BRIDGE3_PHYSICAL_HANDOFF_DISCONTINUITY", {"errors": errors})
	return U.success({"boundary_error": boundary_error, "conservation_error": errors})

func _ownership(frontier: Dictionary, authority: Dictionary, mode: String, components: Array) -> Dictionary:
	var reps: Array = []
	var regions: Array = []
	var rows: Array = [{"id": "region/bridge3-all", "kind": "FULL" if mode == "FULL" else "STRUCTURAL_BAKE"}]
	if mode == "LOCAL_FULL":
		rows = [{"id": "region/bridge3-local", "kind": "FULL"}]
		for component in components:
			rows.append({"id": component.component_id, "kind": "STRUCTURAL_BAKE"})
	for row in rows:
		var id: String = "representation/bridge3-" + row.id.replace("/", "-")
		reps.append({"representation_id": id, "representation_kind": row.kind, "derived_only": true,
			"canonical_write_authorized": false, "source_frontier_hash": frontier.frontier_hash,
			"authority_epoch_binding": authority.authority_epoch_binding})
		regions.append({"region_id": row.id, "representation_id": id, "ownership_role": "ACTIVE_EXECUTION"})
	return Ownership.compile(frontier, authority, reps, regions)

func _frontier() -> Dictionary:
	return _bundle.source_view.frontier if not _bundle.is_empty() else {}
func _authority() -> Dictionary:
	return _bundle.source_view.authority_envelope if not _bundle.is_empty() else {}

static func _check_view(view: Dictionary) -> Dictionary:
	if not view.has_all(["frontier", "authority_envelope", "payload_by_key"]) or typeof(view.frontier) != TYPE_DICTIONARY or typeof(view.authority_envelope) != TYPE_DICTIONARY or typeof(view.payload_by_key) != TYPE_DICTIONARY:
		return U.failure("BRIDGE3_INVALID_SOURCE_VIEW")
	var checked := Slot.Frontier.validate(view.frontier)
	if not checked.success:
		return checked
	var records: Array = []
	for source in view.frontier.sources:
		var key := U.source_key(source.source_domain, source.source_id)
		if not view.payload_by_key.has(key):
			return U.failure("BRIDGE3_SOURCE_PAYLOAD_MISSING")
		records.append({"source_domain": source.source_domain, "source_id": source.source_id, "payload": view.payload_by_key[key]})
	checked = SourceView.create({"canonical_source_frontier": view.frontier, "authority_envelope": view.authority_envelope, "payloads": records})
	if not checked.success:
		return checked
	if U.canonical_hash(checked) != U.canonical_hash(view):
		return U.failure("BRIDGE3_SOURCE_VIEW_IDENTITY_MISMATCH")
	return U.success()
