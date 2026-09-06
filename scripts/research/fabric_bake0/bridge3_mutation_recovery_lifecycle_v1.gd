extends "res://scripts/research/fabric_bake0/bridge3_structural_lifecycle_v1.gd"
## BRIDGE-3 E/F extension. Canonical mutation is external; this class only fences,
## validates sparse state handoff and publishes derived rebaked execution.
const RecSlot = preload("res://scripts/research/fabric_bake0/bridge3_recoverable_execution_slot_v1.gd")
const MTopologyTransaction = preload("res://scripts/research/fabric_bake0/structural_topology_rebake_transaction_v1.gd")
const MDependencySet = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const MBakeExecutionGate = preload("res://scripts/research/fabric_bake0/bake_execution_gate_v1.gd")
const MRuntimeErrorEstimator = preload("res://scripts/research/fabric_bake0/runtime_error_estimator_v1.gd")
const RH = preload("res://scripts/research/fabric_bake0/bridge3_rigid_handoff_v1.gd")
const RR = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const RDescriptor = preload("res://scripts/research/fabric_bake0/structural_aggregate_descriptor_v1.gd")
const RGuardField = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_field_descriptor_v1.gd")
const RPlan = preload("res://scripts/research/fabric_bake0/structural_local_unbake_plan_v1.gd")
const ROwnership = preload("res://scripts/research/fabric_bake0/mixed_representation_ownership_contract_v1.gd")
var _mr_live_frontier: Dictionary = {}
var _mr_live_authority: Dictionary = {}
var _mr_mutation: Dictionary = {}
var _mr_applied_events: Array = []

func _init() -> void:
	_slot = RecSlot.new()
	for key in ["canonical_mutations_observed", "stale_owner_fences", "rebaked_components",
		"rebake_local_part_validations", "rebake_metadata_parts_touched"]:
		_work[key] = 0

func start(bundle: Dictionary, guard_field: Dictionary, plan: Dictionary, full_states: Dictionary, tick: int = 0) -> Dictionary:
	if typeof(bundle.get("source_view")) != TYPE_DICTIONARY:
		return U.failure("BRIDGE3_INVALID_BUNDLE")
	_mr_live_frontier = bundle.source_view.get("frontier", {}).duplicate(true)
	_mr_live_authority = bundle.source_view.get("authority_envelope", {}).duplicate(true)
	return super.start(bundle, guard_field, plan, full_states, tick)

func observe_canonical_mutation(current_frontier: Dictionary, current_authority: Dictionary, event_id: String, tick: int) -> Dictionary:
	if not _mr_mutation.is_empty() or _slot.snapshot().get("mode", "") != "LOCAL_FULL":
		return U.failure("BRIDGE3_MUTATION_REQUIRES_LOCAL_FULL")
	if not U.is_canonical_id(event_id, 2) or not U.is_json_integer(tick) or tick <= int(_slot.snapshot().get("tick", -1)):
		return U.failure("BRIDGE3_MUTATION_ORDER_INVALID")
	if not _frontier_successor(_frontier(), current_frontier) or not _authority_matches(current_frontier, current_authority):
		return U.failure("BRIDGE3_MUTATION_SOURCE_INVALID")
	if _mr_applied_events.has(event_id):
		return U.failure("BRIDGE3_MUTATION_EVENT_ALREADY_APPLIED")
	var saved := _slot.checkpoint()
	if not saved.success:
		return saved
	_mr_mutation = {"previous_frontier": _frontier().duplicate(true), "current_frontier": current_frontier.duplicate(true),
		"current_authority": current_authority.duplicate(true), "event_id": event_id, "tick": tick,
		"slot_checkpoint": saved.details.duplicate(true)}
	_slot.invalidate()
	_work.canonical_mutations_observed += 1
	_work.stale_owner_fences += 1
	return U.success({"old_writer_fenced": _slot.writer().is_empty(), "event_id": event_id})

func rebake_after_mutation(transaction: Dictionary, live_dependency_set: Dictionary, settled: bool = false) -> Dictionary:
	if _mr_mutation.is_empty():
		return U.failure("BRIDGE3_NO_PENDING_CANONICAL_MUTATION")
	if not settled:
		return U.failure("BRIDGE3_REBAKE_REQUIRES_SETTLED_COMPONENTS")
	var checked := MTopologyTransaction.validate(transaction)
	if not checked.success:
		return checked
	checked = MDependencySet.validate(live_dependency_set)
	if not checked.success:
		return checked
	var event: Dictionary = transaction.event
	if event.event_id != _mr_mutation.event_id or int(event.event_tick) != int(_mr_mutation.tick):
		return U.failure("BRIDGE3_MUTATION_EVENT_BINDING_MISMATCH")
	if transaction.previous_source_frontier_hash != _mr_mutation.previous_frontier.frontier_hash or transaction.current_source_frontier_hash != _mr_mutation.current_frontier.frontier_hash:
		return U.failure("BRIDGE3_MUTATION_FRONTIER_BINDING_MISMATCH")
	if _mr_applied_events.has(event.event_id):
		return U.failure("BRIDGE3_MUTATION_EVENT_ALREADY_APPLIED")
	var old_checkpoint: Dictionary = _mr_mutation.slot_checkpoint
	var old_cell: Dictionary = old_checkpoint.cell
	var old_payload: Dictionary = old_cell.payload
	var residual_by_piece: Dictionary = {}
	for index in range(_plan.residual_components.size()):
		var old_component: Dictionary = _plan.residual_components[index]
		residual_by_piece["piece/b0-2-d-residual-%03d" % index] = old_component
	var new_states: Dictionary = {}
	var runtime_components: Array = []
	var local_validations := 0
	var metadata_touched := 0
	for component in transaction.rebaked_components:
		metadata_touched += component.part_ids.size()
		var predecessor_residuals: Array = []
		for piece_id in component.predecessor_piece_ids:
			if residual_by_piece.has(piece_id):
				predecessor_residuals.append(piece_id)
		if predecessor_residuals.size() != 1:
			return U.failure("BRIDGE3_REBAKE_REQUIRES_ONE_RESIDUAL_PREDECESSOR", {"component_id": component.component_id})
		var old_component: Dictionary = residual_by_piece[predecessor_residuals[0]]
		if not old_payload.residual.has(old_component.component_id):
			return U.failure("BRIDGE3_REBAKE_RESIDUAL_STATE_MISSING")
		var new_set: Dictionary = {}
		for part_id in component.part_ids:
			new_set[part_id] = true
		for part_id in old_component.part_ids:
			if not new_set.has(part_id):
				return U.failure("BRIDGE3_REBAKE_SPLIT_OLD_RESIDUAL_FORBIDDEN")
		var delta := RH.v(component.descriptor.center_of_mass) - RH.v(old_component.descriptor.center_of_mass)
		var candidate := RH.shift(old_payload.residual[old_component.component_id], RH.a(delta))
		var mapping_by_id: Dictionary = {}
		for mapping in component.reconstruction_mapping.part_mappings:
			mapping_by_id[mapping.part_id] = mapping
		var target_seen := 0
		for part_id in component.part_ids:
			if old_payload.full.has(part_id):
				if not mapping_by_id.has(part_id):
					return U.failure("BRIDGE3_REBAKE_TARGET_MAPPING_MISSING")
				if RH.error(RH.part_state(candidate, mapping_by_id[part_id]), old_payload.full[part_id]) > float(transaction.continuity_tolerance):
					return U.failure("BRIDGE3_REBAKE_LOCAL_COMPONENT_NOT_SETTLED", {"component_id": component.component_id, "part_id": part_id})
				target_seen += 1
				local_validations += 1
		if target_seen == 0:
			return U.failure("BRIDGE3_REBAKE_COMPONENT_HAS_NO_LOCAL_WITNESS")
		var gate := _gate_rebaked_component(component, candidate, _mr_mutation.current_frontier, _mr_mutation.current_authority, live_dependency_set)
		if not gate.success:
			return gate
		new_states[component.component_id] = candidate
		runtime_components.append({"component_id": component.component_id, "part_ids": component.part_ids.duplicate(),
			"descriptor": component.descriptor.duplicate(true), "reconstruction_mapping": component.reconstruction_mapping.duplicate(true),
			"guard_field": component.guard_field.duplicate(true), "physical_bake_artifact": component.physical_bake_artifact.duplicate(true),
			"execution_gate": gate.details.duplicate(true)})
	var owned := _ownership(_mr_mutation.current_frontier, _mr_mutation.current_authority, "REBAKED", transaction.rebaked_components)
	if not owned.success:
		return owned
	var payload := {"full": {}, "reduced": {}, "residual": new_states, "rebaked": runtime_components,
		"ownership": owned.details.contract, "event_id": event.event_id, "event_hash": event.event_hash}
	var next_slot := RecSlot.new()
	var rebound := next_slot.rebind(old_cell, old_checkpoint.receipts, old_checkpoint.tickets,
		_mr_mutation.current_frontier, _mr_mutation.current_authority, "REBAKED", payload, int(event.event_tick), event.event_id)
	if not rebound.success:
		return rebound
	_slot = next_slot
	_mr_live_frontier = _mr_mutation.current_frontier.duplicate(true)
	_mr_live_authority = _mr_mutation.current_authority.duplicate(true)
	_mr_applied_events.append(event.event_id)
	_mr_applied_events.sort()
	_work.actual_transitions += 1
	_work.rebaked_components += runtime_components.size()
	_work.rebake_local_part_validations += local_validations
	_work.rebake_metadata_parts_touched += metadata_touched
	_mr_mutation = {}
	return U.success({"receipt": rebound.details.receipt, "rebaked_component_count": runtime_components.size(),
		"local_part_validations": local_validations, "metadata_parts_touched": metadata_touched})

func capture_capsule() -> Dictionary:
	var saved: Dictionary = {}
	var phase := "ACTIVE"
	var frontier := _frontier()
	var authority := _authority()
	var mutation_record: Dictionary = {}
	if not _mr_mutation.is_empty():
		phase = "MUTATION_FENCED"
		saved = _mr_mutation.slot_checkpoint.duplicate(true)
		frontier = _mr_mutation.current_frontier
		authority = _mr_mutation.current_authority
		mutation_record = {"previous_frontier": _mr_mutation.previous_frontier.duplicate(true), "event_id": _mr_mutation.event_id, "tick": _mr_mutation.tick}
	else:
		var checkpoint_result := _slot.checkpoint()
		if not checkpoint_result.success:
			return checkpoint_result
		saved = checkpoint_result.details.duplicate(true)
	var capsule := {"schema": "planet_simulator.fabric_bridge3_runtime_capsule.v1", "canonical": false,
		"derived": true, "discardable": true, "phase": phase, "frontier_checksum": frontier.checksum,
		"authority_checksum": authority.checksum, "slot_checkpoint": saved, "mutation": mutation_record,
		"controller": _controller.duplicate(true), "parent_state": _parent_state.duplicate(true),
		"applied_events": _mr_applied_events.duplicate(), "work": _work.duplicate(true), "checksum": ""}
	capsule.checksum = U.compute_checksum(capsule)
	return U.success({"capsule": capsule})

func restore_capsule(bundle: Dictionary, guard_field: Dictionary, plan: Dictionary, capsule: Dictionary,
	live_frontier: Dictionary, live_authority: Dictionary) -> Dictionary:
	if not _bundle.is_empty():
		return U.failure("BRIDGE3_RESTORE_REQUIRES_NEW_RUNTIME")
	if capsule.get("schema") != "planet_simulator.fabric_bridge3_runtime_capsule.v1" or capsule.get("canonical") != false or capsule.get("derived") != true or capsule.get("discardable") != true:
		return U.failure("BRIDGE3_INVALID_CAPSULE")
	if not ["ACTIVE", "MUTATION_FENCED"].has(capsule.get("phase")) or not U.validate_checksum(capsule).success or capsule.get("frontier_checksum") != live_frontier.get("checksum") or capsule.get("authority_checksum") != live_authority.get("checksum"):
		return U.failure("BRIDGE3_STALE_OR_CORRUPT_CAPSULE")
	var configured := _configure_metadata(bundle, guard_field, plan)
	if not configured.success:
		return configured
	var restored_slot := RecSlot.new()
	if capsule.phase == "ACTIVE":
		var restored := restored_slot.restore(capsule.slot_checkpoint, live_frontier, live_authority)
		if not restored.success:
			return restored
		_slot = restored_slot
	else:
		if typeof(capsule.get("mutation")) != TYPE_DICTIONARY or not capsule.mutation.has_all(["previous_frontier", "event_id", "tick"]):
			return U.failure("BRIDGE3_INVALID_MUTATION_CAPSULE")
		var old_cell: Dictionary = capsule.slot_checkpoint.get("cell", {})
		if typeof(old_cell.get("frontier")) != TYPE_DICTIONARY or typeof(old_cell.get("authority")) != TYPE_DICTIONARY:
			return U.failure("BRIDGE3_INVALID_MUTATION_CAPSULE")
		var restored_old := restored_slot.restore(capsule.slot_checkpoint, old_cell.frontier, old_cell.authority)
		if not restored_old.success:
			return restored_old
		if not _frontier_successor(capsule.mutation.previous_frontier, live_frontier) or capsule.mutation.previous_frontier.checksum != old_cell.frontier.checksum:
			return U.failure("BRIDGE3_MUTATION_CAPSULE_FRONTIER_INVALID")
		restored_slot.invalidate()
		_slot = restored_slot
		_mr_mutation = {"previous_frontier": capsule.mutation.previous_frontier.duplicate(true), "current_frontier": live_frontier.duplicate(true),
			"current_authority": live_authority.duplicate(true), "event_id": capsule.mutation.event_id, "tick": capsule.mutation.tick,
			"slot_checkpoint": capsule.slot_checkpoint.duplicate(true)}
	_mr_live_frontier = live_frontier.duplicate(true)
	_mr_live_authority = live_authority.duplicate(true)
	_controller = capsule.controller.duplicate(true)
	_parent_state = capsule.parent_state.duplicate(true)
	_mr_applied_events = capsule.applied_events.duplicate()
	_work = capsule.work.duplicate(true)
	return U.success({"writer": _slot.writer(), "mode": "MUTATION_FENCED" if capsule.phase == "MUTATION_FENCED" else _slot.snapshot().mode})

func execute_boundary(live_frontier: Dictionary) -> Dictionary:
	if not _slot.can_execute(live_frontier):
		return U.failure("BRIDGE3_BOUNDARY_REQUIRES_LIVE_BAKE")
	var cell := _slot.snapshot()
	if cell.mode == "STRUCTURAL_BAKE":
		return Lifecycle.execute(_bundle, cell.payload.reduced)
	if cell.mode == "REBAKED":
		for component in cell.payload.get("rebaked", []):
			if typeof(component.get("execution_gate")) != TYPE_DICTIONARY:
				return U.failure("BRIDGE3_REBAKED_GATE_MISSING")
		return U.success({"component_count": cell.payload.residual.size(), "event_id": cell.payload.get("event_id", "")})
	return U.failure("BRIDGE3_BOUNDARY_REQUIRES_LIVE_BAKE")

func full_snapshot(live_frontier: Dictionary) -> Dictionary:
	if not _slot.can_execute(live_frontier):
		return U.failure("BRIDGE3_STALE_SNAPSHOT")
	var cell := _slot.snapshot()
	if cell.mode != "REBAKED":
		return super.full_snapshot(live_frontier)
	var full: Dictionary = {}
	for component in cell.payload.get("rebaked", []):
		if not cell.payload.residual.has(component.component_id):
			return U.failure("BRIDGE3_REBAKED_STATE_MISSING")
		var restored := RR.reconstruct(component.reconstruction_mapping, cell.payload.residual[component.component_id])
		if not restored.success:
			return restored
		for id in restored.details.full_states:
			if full.has(id):
				_work.duplicate_ownership_count += 1
				return U.failure("BRIDGE3_DUPLICATE_PART_OWNER")
			full[id] = restored.details.full_states[id]
	_work.full_snapshot_parts += full.size()
	return U.success({"full_states": full})

func status() -> Dictionary:
	var result := super.status()
	if not _mr_mutation.is_empty():
		result.mode = "MUTATION_FENCED"
	result.applied_events = _mr_applied_events.duplicate()
	return result

func _ownership(frontier: Dictionary, authority: Dictionary, mode: String, components: Array) -> Dictionary:
	if mode != "REBAKED":
		return super._ownership(frontier, authority, mode, components)
	var reps: Array = []
	var regions: Array = []
	for component in components:
		var id: String = "representation/bridge3-" + String(component.component_id).replace("/", "-")
		reps.append({"representation_id": id, "representation_kind": "STRUCTURAL_BAKE", "derived_only": true,
			"canonical_write_authorized": false, "source_frontier_hash": frontier.frontier_hash,
			"authority_epoch_binding": authority.authority_epoch_binding})
		regions.append({"region_id": component.component_id, "representation_id": id, "ownership_role": "ACTIVE_EXECUTION"})
	return ROwnership.compile(frontier, authority, reps, regions)

func _frontier() -> Dictionary:
	return _mr_live_frontier if not _mr_live_frontier.is_empty() else super._frontier()
func _authority() -> Dictionary:
	return _mr_live_authority if not _mr_live_authority.is_empty() else super._authority()

func _gate_rebaked_component(component: Dictionary, state: Dictionary, current_frontier: Dictionary,
	current_authority: Dictionary, live_dependency_set: Dictionary) -> Dictionary:
	var artifact: Dictionary = component.physical_bake_artifact
	var guard_values: Dictionary = {}
	for guard in artifact.refinement_guards:
		guard_values[guard.guard_id] = 0.0
	var estimator := MRuntimeErrorEstimator.create("estimator/bridge3-" + String(component.component_id).replace("/", "-"),
		0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 0.5)
	var gate := MBakeExecutionGate.can_execute(artifact, {"artifact_state": "READY", "canonical_source_frontier": current_frontier,
		"authority_envelope": current_authority, "dependency_set": live_dependency_set,
		"fabric_graph_hash": artifact.source_binding.fabric_graph_hash, "fabric_compiler_version": artifact.source_binding.fabric_compiler_version,
		"boundary_contract_hash": artifact.source_binding.boundary_contract_hash, "bake_policy_hash": artifact.source_binding.bake_policy_hash,
		"runtime_domain": {"source_frontier_hash": current_frontier.frontier_hash, "fabric_graph_hash": artifact.source_binding.fabric_graph_hash,
			"elapsed_s": 0.0, "mode": "RIGID", "quantities": {}}, "runtime_error_estimator": estimator,
		"guard_values": guard_values, "invalidations": []})
	if not gate.success:
		return U.failure("BRIDGE3_REBAKED_ARTIFACT_NOT_EXECUTABLE", {"component_id": component.component_id, "cause": gate})
	return gate

func _configure_metadata(bundle: Dictionary, guard_field: Dictionary, plan: Dictionary) -> Dictionary:
	if not bundle.has_all(["aggregate", "source_view", "artifact"]):
		return U.failure("BRIDGE3_INVALID_BUNDLE")
	var checked := _check_view(bundle.source_view)
	if not checked.success:
		return checked
	var ag: Dictionary = bundle.aggregate
	for result in [RDescriptor.validate(ag.descriptor), RR.validate(ag.reconstruction_mapping), RGuardField.validate(guard_field), RPlan.validate(plan)]:
		if not result.get("success", false):
			return result
	if plan.parent_structural_descriptor_hash != ag.descriptor.checksum or plan.parent_reconstruction_mapping_hash != ag.reconstruction_mapping.checksum or plan.guard_field_hash != guard_field.checksum:
		return U.failure("BRIDGE3_BINDING_MISMATCH")
	_bundle = bundle.duplicate(true)
	_plan = plan.duplicate(true)
	_field = guard_field.duplicate(true)
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
	return U.success()

func _frontier_successor(previous: Dictionary, current: Dictionary) -> bool:
	if not RecSlot.Frontier.validate(previous).success or not RecSlot.Frontier.validate(current).success or previous.sources.size() != current.sources.size():
		return false
	var before: Dictionary = {}
	for source in previous.sources:
		before[U.source_key(source.source_domain, source.source_id)] = source
	var advanced := 0
	for source in current.sources:
		var key := U.source_key(source.source_domain, source.source_id)
		if not before.has(key):
			return false
		var old: Dictionary = before[key]
		if int(source.authority_epoch) < int(old.authority_epoch) or int(source.source_revision) < int(old.source_revision):
			return false
		if int(source.source_revision) == int(old.source_revision) + 1:
			advanced += 1
		elif int(source.source_revision) != int(old.source_revision):
			return false
	return advanced == 1

func _authority_matches(frontier: Dictionary, authority: Dictionary) -> bool:
	if not RecSlot.Authority.validate_b0_safety(authority).success:
		return false
	var epochs: Dictionary = {}
	for row in authority.source_authority_frontier:
		epochs[U.source_key(row.source_domain, row.source_id)] = int(row.authority_epoch)
	for source in frontier.sources:
		if epochs.get(U.source_key(source.source_domain, source.source_id), -1) != int(source.authority_epoch):
			return false
	return epochs.size() == frontier.sources.size()
