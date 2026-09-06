extends SceneTree
# Diagnostic characterization, not an acceptance test or closure gate.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_graph_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_adapter_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_compiler_v1.gd")
const F1 = preload("res://scripts/research/fabric_bake0/fabric1_generalized_runtime_v1.gd")
const Protocol = preload("res://scripts/research/fabric_bake0/unseen_machine_challenge_protocol_v1.gd")
const Reducer = preload("res://scripts/research/fabric_bake0/exact_boundary_reducer_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Bond = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const Batch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")

func _initialize() -> void:
	var source := _snapshot(104, 1.0, 100.0)
	var material := _matter(104, "material/steel")
	var initial := Adapter.compile(source, material, "server/audit-authority", 7)
	if not initial.get("success", false):
		print("AUDIT_SETUP_ERROR=", JSON.stringify(initial)); quit(1); return
	var geometry := Adapter.compile(_snapshot(104, 10.0, 100.0), material, "server/audit-authority", 7)
	var changed_material := Adapter.compile(source, _matter(104, "material/rubber"), "server/audit-authority", 7)
	var stronger := Adapter.compile(_snapshot(104, 1.0, 200.0), material, "server/audit-authority", 7)
	var small := _snapshot(6, 1.0, 100.0)
	var small_result := Adapter.compile(small, _matter(6, "material/steel"), "server/audit-authority", 7)
	for result in [geometry, changed_material, stronger]:
		if not result.get("success", false):
			print("AUDIT_VARIANT_ERROR=", JSON.stringify(result)); quit(2); return
	var context := Compiler.build_context(initial.details.spec)
	if not context.get("success", false):
		print("AUDIT_COMPILER_ERROR=", JSON.stringify(context)); quit(3); return
	var compiled := Compiler.compile(initial.details.spec)
	if compiled.get("status", "") != "BAKE_READY":
		print("AUDIT_BAKE_ERROR=", JSON.stringify(compiled)); quit(4); return
	var base_full := Reducer.evaluate_full(Graph.to_linear_system(initial.details.spec), [1.0, 0.0], Compiler.PIVOT_TOLERANCE)
	var strong_full := Reducer.evaluate_full(Graph.to_linear_system(stronger.details.spec), [1.0, 0.0], Compiler.PIVOT_TOLERANCE)
	if not base_full.get("success", false) or not strong_full.get("success", false):
		print("AUDIT_SOLVE_ERROR"); quit(5); return
	var desc: Dictionary = compiled.compile_result.diagnostics.reduction
	var original := F1.new()
	var spec: Dictionary = initial.details.spec
	var started := original.start_baked(spec, 0)
	var refined := original.refine_to_full("AUDIT_PENDING_FAILURE", 1)
	if not started.success or not refined.success:
		print("AUDIT_RUNTIME_SETUP_ERROR"); quit(6); return
	var captured := original.capture_capsule()
	if not captured.success:
		print("AUDIT_CAPTURE_ERROR"); quit(7); return
	var restored_runtime := F1.new()
	var restored := restored_runtime.restore(spec, captured.details.capsule)
	if not restored.success:
		print("AUDIT_RESTORE_SETUP_ERROR=", JSON.stringify(restored)); quit(8); return
	var edges: Array = spec.edges.duplicate(true)
	var failure_id: String = edges[0].edge_id
	edges[0].active = false
	var successor := Graph.create(spec.machine_id, 2, spec.boundary_node_ids, spec.internal_node_ids, edges, ["event/audit-new"])
	var control_mutation := original.apply_canonical_failure(successor, "event/audit-new", [failure_id], 2)
	var recovered_mutation := restored_runtime.apply_canonical_failure(successor, "event/audit-new", [failure_id], 2)
	var with_history := Graph.create(spec.machine_id, 1, spec.boundary_node_ids, spec.internal_node_ids, spec.edges, ["event/audit-old"])
	var forged := Graph.create(spec.machine_id, 2, spec.boundary_node_ids, spec.internal_node_ids, edges, ["event/audit-new", "event/audit-forged"])
	var valid_history := Graph.create(spec.machine_id, 2, spec.boundary_node_ids, spec.internal_node_ids, edges, ["event/audit-new", "event/audit-old"])
	var forged_ledger := Protocol.validate_successor(with_history, forged, "event/audit-new", [failure_id])
	var valid_ledger := Protocol.validate_successor(with_history, valid_history, "event/audit-new", [failure_id])
	var report := {
		"diagnostic_only": true,
		"full_capsule_restore_success": restored.success,
		"control_mutation_without_restart_success": control_mutation.success,
		"mutation_after_full_restore_success": recovered_mutation.success,
		"mutation_after_full_restore_error": recovered_mutation.get("error_code", ""),
		"valid_ledger_successor_accepted": valid_ledger.success,
		"dropped_old_event_and_inserted_forged_event_accepted": forged_ledger.success,
		"history_before": with_history.applied_event_ids,
		"history_after_forgery": forged.applied_event_ids,
		"geometry_length_multiplier": 10,
		"geometry_changed_canonical_checksum": source.checksum != _snapshot(104, 10.0, 100.0).checksum,
		"geometry_changed_physical_graph": initial.details.spec.graph_hash != geometry.details.spec.graph_hash,
		"material_changed_outer_binding": initial.details.binding.checksum != changed_material.details.binding.checksum,
		"material_changed_physical_graph": initial.details.spec.graph_hash != changed_material.details.spec.graph_hash,
		"strength_multiplier": 2,
		"flow_multiplier": float(strong_full.details.boundary_flow[0]) / float(base_full.details.boundary_flow[0]),
		"small_canonical_snapshot_valid": Snapshot.validate(small).success,
		"small_graph_accepted": small_result.success,
		"small_graph_rejection": small_result.get("error_code", ""),
		"outer_owner": initial.details.authority.execution_owner,
		"inner_owner": context.details.authority.execution_owner,
		"outer_epoch": initial.details.authority.source_authority_frontier[0].authority_epoch,
		"inner_epoch": context.details.authority.source_authority_frontier[0].authority_epoch,
		"outer_readonly_sources": initial.details.authority.readonly_source_ids,
		"inner_readonly_sources": context.details.authority.readonly_source_ids,
		"outer_mutable_sources": initial.details.authority.mutable_source_ids,
		"inner_mutable_sources": context.details.authority.mutable_source_ids,
		"outer_frontier_matches_inner": initial.details.frontier.frontier_hash == context.details.frontier.frontier_hash,
		"full_work_units": desc["runtime_full_work_units"],
		"reduced_work_units": desc["runtime_reduced_work_units"],
	}
	print("FABRIC_COMPLEXITY_AUDIT_OBSERVATIONS=", JSON.stringify(report))
	print("FABRIC_COMPLEXITY_AUDIT_DIAGNOSTIC_COMPLETE")
	quit(0)

func _snapshot(count: int, length_scale: float, strength: float) -> Dictionary:
	var parts: Array = []
	for i in range(count):
		parts.append(Part.create("part/audit/%03d" % i, "item/audit-%03d" % i, "BEAM",
			"fabric_boundary" if i == 0 or i == count - 1 else "member", 1.0,
			[float(i) * length_scale, 0.0, 0.0]))
	var bonds: Array = []
	for i in range(count - 1):
		bonds.append(Bond.create("bond/audit/%03d" % i, "part/audit/%03d" % i,
			"part/audit/%03d" % (i + 1), "GENERIC_COUPLING", strength))
	return Snapshot.create("construct/audit", "item/audit-root", 0, "OPERATIONAL", parts, bonds, {})

func _matter(count: int, material: String) -> Dictionary:
	return Batch.create({"batch_id": "batch/audit", "container_id": "container/audit",
		"source_body_id": "body/audit", "source_operation_id": "operation/audit",
		"total_mass_kg": float(count), "bulk_volume_m3": 0.013,
		"composition": Composition.create([{"material_id": material, "mass_fraction": 1.0}]),
		"temperature_k": 293.15})
