extends SceneTree

const FixtureScript = preload("res://tests/construction/fixtures/c3_table_build_fixture.gd")
const AdapterScript = preload("res://scripts/construction/item_graph/in_memory_construction_item_graph_adapter.gd")
const StoreScript = preload("res://scripts/construction/build/construction_build_plan_store.gd")
const ProcessScript = preload("res://scripts/construction/build/construction_build_process.gd")
const GhostScript = preload("res://scripts/construction/build/construction_ghost_state.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const BuilderAgentScript = preload("res://scripts/construction/build/construction_builder_agent.gd")
const StagePlannerScript = preload("res://scripts/construction/build/construction_stage_transaction_planner.gd")
const TransactionPlanScript = preload("res://scripts/construction/item_graph/construction_item_transaction_plan.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_staged_table_construction_and_recovery()
	_test_canonical_precondition_comparison()
	_test_cancel_and_divergence_guards()
	_test_builder_agent_executes_plan()
	_finish()


func _test_staged_table_construction_and_recovery() -> void:
	var adapter = AdapterScript.new()
	_assert_ok(adapter.setup(FixtureScript.source_projections()), "C3 adapter fixture setup failed")
	var store = StoreScript.new()
	_assert_ok(store.setup(), "C3 build store setup failed")
	var process = ProcessScript.new()
	_assert_ok(process.setup(adapter, store), "C3 build process setup failed")
	var plan: Dictionary = FixtureScript.build_plan()
	_assert_ok(process.register_plan(plan), "C3 build plan registration failed")
	var preview: Dictionary = process.get_ghost_projection(FixtureScript.BUILD_PLAN_ID)
	_assert(String(preview.status) == GhostScript.STATUS_GHOST, "Fresh preview status mismatch")
	_assert(not bool(preview.physical), "Fresh ghost became physical")
	_assert(float(preview.mass_kg) == 0.0, "Fresh ghost acquired mass")
	_assert(preview.capabilities.is_empty(), "Fresh ghost exposed capabilities")
	_assert(adapter.get_construct_snapshot(FixtureScript.CONSTRUCT_ID).is_empty(), "Fresh ghost created authoritative construct")
	_assert(adapter.get_item_projection(FixtureScript.ROOT_ID).is_empty(), "Fresh ghost created root item")
	var requirements_zero: Dictionary = process.get_stage_requirements(FixtureScript.BUILD_PLAN_ID, 0)
	_assert(requirements_zero.part_ids.size() == 3, "Foundation requirement part count mismatch")
	_assert(requirements_zero.material_allocations[0].quantity == 2, "Foundation material requirement mismatch")
	_assert(requirements_zero.required_capabilities == ["FASTEN"], "Foundation capability requirement mismatch")

	var missing_tool: Dictionary = process.advance_stage(
		FixtureScript.BUILD_PLAN_ID,
		0,
		"operation/c3/integration/foundation",
		[]
	)
	_assert_error(missing_tool, "CONSTRUCTION_BUILD_STAGE_CAPABILITY_MISSING", "Stage advanced without required tool capability")
	_assert(String(missing_tool.status) == ProcessScript.STATUS_RETRYABLE, "Missing tool capability must be retryable")
	_assert(adapter.get_generation() == 0, "Missing capability mutated authoritative adapter")
	_assert(int(store.get_ghost(FixtureScript.BUILD_PLAN_ID).next_stage_index) == 0, "Missing capability advanced ghost")

	var foundation: Dictionary = process.advance_stage(
		FixtureScript.BUILD_PLAN_ID,
		0,
		"operation/c3/integration/foundation",
		["FASTEN"]
	)
	_assert_ok(foundation, "Foundation stage failed")
	_assert(not bool(foundation.replay), "First foundation stage marked replay")
	_assert(adapter.get_generation() == 1, "Foundation did not commit exactly once")
	var foundation_snapshot: Dictionary = adapter.get_construct_snapshot(FixtureScript.CONSTRUCT_ID)
	_assert(foundation_snapshot.parts.size() == 3, "Foundation materialized wrong part count")
	_assert(String(foundation_snapshot.build_state) == "PARTIAL", "Foundation construct not partial")
	_assert(foundation_snapshot.compiled_facets.capabilities.is_empty(), "Foundation exposed capabilities")
	_assert(adapter.get_item_projection(FixtureScript.ROOT_ID).size() > 0, "Foundation did not create construct root")
	for item_id in [FixtureScript.TOP_ID, FixtureScript.LEG_A_ID, FixtureScript.LEG_B_ID]:
		_assert(String(adapter.get_item_projection(item_id).relation.kind) == "ATTACHMENT", "Foundation part not attached: %s" % item_id)
	for item_id in [FixtureScript.LEG_C_ID, FixtureScript.LEG_D_ID]:
		_assert(String(adapter.get_item_projection(item_id).relation.kind) == "CONTAINER", "Future part moved early: %s" % item_id)
	_assert(int(adapter.get_item_projection(FixtureScript.FASTENER_ID).quantity) == 8, "Foundation fastener consumption mismatch")
	_assert(int(store.get_ghost(FixtureScript.BUILD_PLAN_ID).next_stage_index) == 1, "Foundation did not advance ghost")
	_assert(String(store.get_ghost(FixtureScript.BUILD_PLAN_ID).status) == GhostScript.STATUS_IN_PROGRESS, "Foundation ghost status mismatch")

	var foundation_replay: Dictionary = process.advance_stage(
		FixtureScript.BUILD_PLAN_ID,
		0,
		"operation/c3/integration/foundation",
		["FASTEN"]
	)
	_assert_ok(foundation_replay, "Foundation exact replay failed")
	_assert(bool(foundation_replay.replay), "Foundation replay not identified")
	_assert(adapter.get_generation() == 1, "Foundation replay advanced authoritative generation")
	_assert(int(adapter.get_item_projection(FixtureScript.FASTENER_ID).quantity) == 8, "Foundation replay consumed fasteners again")
	var different_foundation_operation: Dictionary = process.advance_stage(
		FixtureScript.BUILD_PLAN_ID,
		0,
		"operation/c3/integration/foundation-other",
		["FASTEN"]
	)
	_assert_error(different_foundation_operation, "CONSTRUCTION_BUILD_STAGE_OPERATION_CONFLICT", "Completed stage accepted another operation ID")

	var store_before_crash: Dictionary = store.to_dict()
	var frame_crash: Dictionary = process.advance_stage(
		FixtureScript.BUILD_PLAN_ID,
		1,
		"operation/c3/integration/frame",
		["FASTEN"],
		{"failure_point": ProcessScript.FAILURE_AFTER_AUTHORITATIVE_COMMIT}
	)
	_assert_error(frame_crash, "INJECTED_FAILURE_AFTER_AUTHORITATIVE_STAGE_COMMIT", "Post-authoritative stage crash not surfaced")
	_assert(String(frame_crash.status) == ProcessScript.STATUS_RETRYABLE, "Post-authoritative crash must be retryable")
	_assert(adapter.get_generation() == 2, "Frame stage did not reach authoritative adapter before crash")
	_assert(adapter.get_construct_snapshot(FixtureScript.CONSTRUCT_ID).parts.size() == 5, "Authoritative frame stage missing after crash")
	_assert(int(adapter.get_item_projection(FixtureScript.FASTENER_ID).quantity) == 6, "Frame stage material not committed before crash")
	_assert(int(store.get_ghost(FixtureScript.BUILD_PLAN_ID).next_stage_index) == 1, "Post-authoritative crash incorrectly advanced ghost")
	_assert(store.to_dict() == store_before_crash, "Post-authoritative crash mutated build plan store")

	var restored_store = StoreScript.new()
	_assert_ok(restored_store.load_dict(store_before_crash), "Crash fixture store restore failed")
	var restored_process = ProcessScript.new()
	_assert_ok(restored_process.setup(adapter, restored_store), "Restored C3 process setup failed")
	var reconciled: Dictionary = restored_process.reconcile_plan(FixtureScript.BUILD_PLAN_ID)
	_assert_ok(reconciled, "Ghost reconciliation after authoritative crash failed")
	_assert(int(reconciled.completed_stage_count) == 2, "Reconciliation did not discover committed frame stage")
	var reconciled_ghost: Dictionary = restored_store.get_ghost(FixtureScript.BUILD_PLAN_ID)
	_assert(int(reconciled_ghost.next_stage_index) == 2, "Reconciliation did not advance ghost")
	_assert(String(reconciled_ghost.completed_operation_ids[1]).is_empty(), "Reconciliation invented unknown operation ID")
	var recovered_replay: Dictionary = restored_process.advance_stage(
		FixtureScript.BUILD_PLAN_ID,
		1,
		"operation/c3/integration/frame",
		["FASTEN"]
	)
	_assert_ok(recovered_replay, "Committed frame stage did not replay after reconciliation")
	_assert(bool(recovered_replay.replay), "Recovered frame result not marked replay")
	_assert(String(restored_store.get_ghost(FixtureScript.BUILD_PLAN_ID).completed_operation_ids[1]) == "operation/c3/integration/frame", "Recovered operation ID not bound to ghost")
	_assert(adapter.get_generation() == 2, "Recovered frame replay advanced authoritative generation")
	_assert(int(adapter.get_item_projection(FixtureScript.FASTENER_ID).quantity) == 6, "Recovered frame replay consumed material again")

	var wrong_commissioning_tool: Dictionary = restored_process.advance_stage(
		FixtureScript.BUILD_PLAN_ID,
		2,
		"operation/c3/integration/commission",
		["FASTEN"]
	)
	_assert_error(wrong_commissioning_tool, "CONSTRUCTION_BUILD_STAGE_CAPABILITY_MISSING", "Commissioning accepted wrong capability")
	_assert(adapter.get_generation() == 2, "Wrong commissioning capability mutated authority")
	var commissioned: Dictionary = restored_process.advance_stage(
		FixtureScript.BUILD_PLAN_ID,
		2,
		"operation/c3/integration/commission",
		["INSPECT"]
	)
	_assert_ok(commissioned, "Commissioning stage failed")
	_assert(adapter.get_generation() == 3, "Commissioning did not commit exactly once")
	var completed_snapshot: Dictionary = adapter.get_construct_snapshot(FixtureScript.CONSTRUCT_ID)
	_assert(String(completed_snapshot.build_state) == "OPERATIONAL", "Completed table not operational")
	_assert(bool(completed_snapshot.compiled_facets.operational), "Completed table facet not operational")
	_assert(completed_snapshot.compiled_facets.capabilities == ["PLACE_ITEMS", "SUPPORT_SURFACE", "WORK_SURFACE"], "Completed table capabilities mismatch")
	_assert(int(adapter.get_item_projection(FixtureScript.SEALANT_ID).quantity) == 2, "Commissioning material consumption mismatch")
	var completed_ghost: Dictionary = restored_store.get_ghost(FixtureScript.BUILD_PLAN_ID)
	_assert(String(completed_ghost.status) == GhostScript.STATUS_COMPLETE, "Completed ghost status mismatch")
	_assert(int(completed_ghost.next_stage_index) == 3, "Completed ghost progress mismatch")
	var final_preview: Dictionary = restored_process.get_ghost_projection(FixtureScript.BUILD_PLAN_ID)
	_assert(bool(final_preview.physical), "Completed construct preview not materialized")
	_assert(final_preview.capabilities.is_empty(), "Ghost projection duplicated construct capabilities")
	_assert(float(final_preview.mass_kg) == 0.0, "Ghost projection duplicated construct mass")

	var commission_replay: Dictionary = restored_process.advance_stage(
		FixtureScript.BUILD_PLAN_ID,
		2,
		"operation/c3/integration/commission",
		["INSPECT"]
	)
	_assert_ok(commission_replay, "Commissioning replay failed")
	_assert(bool(commission_replay.replay), "Commissioning replay not identified")
	_assert(adapter.get_generation() == 3, "Commissioning replay advanced generation")
	_assert(int(adapter.get_item_projection(FixtureScript.SEALANT_ID).quantity) == 2, "Commissioning replay consumed sealant again")
	var stale_future: Dictionary = restored_process.advance_stage(
		FixtureScript.BUILD_PLAN_ID,
		1,
		"operation/c3/integration/frame-new",
		["FASTEN"]
	)
	_assert_error(stale_future, "CONSTRUCTION_BUILD_STAGE_OPERATION_CONFLICT", "Completed frame accepted a new operation")

	var persisted: Dictionary = restored_store.to_dict()
	var roundtrip_store = StoreScript.new()
	_assert_ok(roundtrip_store.load_dict(persisted), "Completed build store did not load")
	var roundtrip_process = ProcessScript.new()
	_assert_ok(roundtrip_process.setup(adapter, roundtrip_store), "Roundtrip process setup failed")
	_assert_ok(roundtrip_process.reconcile_all(), "Roundtrip reconcile all failed")
	_assert(roundtrip_store.to_dict() == persisted, "Stable reconcile changed completed build store")


func _test_canonical_precondition_comparison() -> void:
	var adapter = AdapterScript.new()
	_assert_ok(adapter.setup(FixtureScript.source_projections()), "Canonical precondition adapter setup failed")
	var build_plan: Dictionary = FixtureScript.build_plan()
	var foundation_planned: Dictionary = StagePlannerScript.build_stage_transaction_plan(
		build_plan,
		0,
		"operation/c3/canonical-precondition/foundation"
	)
	_assert_ok(foundation_planned, "Canonical precondition foundation plan failed")
	_assert_ok(adapter.apply_plan(foundation_planned.transaction_plan), "Canonical precondition foundation apply failed")
	var frame_planned: Dictionary = StagePlannerScript.build_stage_transaction_plan(
		build_plan,
		1,
		"operation/c3/canonical-precondition/frame"
	)
	_assert_ok(frame_planned, "Canonical precondition frame plan failed")
	var frame_plan: Dictionary = Dictionary(frame_planned.transaction_plan).duplicate(true)
	var before_snapshot: Dictionary = frame_plan.construct_mutation.before_snapshot
	before_snapshot.state_revision = float(before_snapshot.state_revision)
	frame_plan.construct_mutation.before_snapshot = before_snapshot
	for mutation in frame_plan.item_mutations:
		var before_projection: Dictionary = mutation.before_projection
		if not before_projection.is_empty():
			before_projection.revision = float(before_projection.revision)
			mutation.before_projection = before_projection
	frame_plan.checksum = TransactionPlanScript.compute_checksum(frame_plan)
	_assert_ok(TransactionPlanScript.validate(frame_plan), "Type-varied canonical frame plan rejected structurally")
	var applied: Dictionary = adapter.apply_plan(frame_plan)
	_assert_ok(applied, "Canonical-equivalent construct/item preconditions did not match")
	_assert(adapter.get_generation() == 2, "Canonical precondition frame did not commit exactly once")
	_assert(adapter.get_construct_snapshot(FixtureScript.CONSTRUCT_ID).parts.size() == 5, "Canonical precondition frame did not materialize all parts")


func _test_cancel_and_divergence_guards() -> void:
	var adapter = AdapterScript.new()
	_assert_ok(adapter.setup(FixtureScript.source_projections()), "Cancel fixture adapter setup failed")
	var store = StoreScript.new()
	_assert_ok(store.setup(), "Cancel fixture store setup failed")
	var process = ProcessScript.new()
	_assert_ok(process.setup(adapter, store), "Cancel fixture process setup failed")
	_assert_ok(process.register_plan(FixtureScript.build_plan()), "Cancel fixture plan registration failed")
	_assert_ok(store.cancel_ghost(FixtureScript.BUILD_PLAN_ID), "Fresh ghost cancellation failed")
	_assert(String(store.get_ghost(FixtureScript.BUILD_PLAN_ID).status) == GhostScript.STATUS_CANCELLED, "Cancelled ghost status mismatch")
	var cancelled_stage: Dictionary = process.advance_stage(
		FixtureScript.BUILD_PLAN_ID,
		0,
		"operation/c3/cancelled/foundation",
		["FASTEN"]
	)
	_assert_error(cancelled_stage, "CONSTRUCTION_GHOST_CANCELLED", "Cancelled ghost advanced")
	_assert(adapter.get_generation() == 0, "Cancelled ghost mutated authority")

	var divergence_adapter = AdapterScript.new()
	_assert_ok(divergence_adapter.setup(FixtureScript.source_projections()), "Divergence adapter setup failed")
	var divergence_store = StoreScript.new()
	_assert_ok(divergence_store.setup(), "Divergence store setup failed")
	var divergence_process = ProcessScript.new()
	_assert_ok(divergence_process.setup(divergence_adapter, divergence_store), "Divergence process setup failed")
	_assert_ok(divergence_process.register_plan(FixtureScript.build_plan()), "Divergence plan registration failed")
	_assert_ok(divergence_process.advance_stage(FixtureScript.BUILD_PLAN_ID, 0, "operation/c3/divergence/foundation", ["FASTEN"]), "Divergence foundation setup failed")
	var state: Dictionary = divergence_adapter.export_state()
	var construct: Dictionary = state.constructs[0]
	construct.compiled_facets["construction_semantic_state"] = "FRAME"
	construct.checksum = SnapshotScript.compute_checksum(construct)
	state.constructs[0] = construct
	state.checksum = divergence_adapter.compute_state_checksum(state)
	_assert_ok(divergence_adapter.load_state(state), "Diverged authoritative fixture load failed")
	var diverged: Dictionary = divergence_process.reconcile_plan(FixtureScript.BUILD_PLAN_ID)
	_assert_error(diverged, "CONSTRUCTION_BUILD_PLAN_CONSTRUCT_DIVERGED", "Diverged construct reconciled as a valid stage")
	_assert(int(divergence_store.get_ghost(FixtureScript.BUILD_PLAN_ID).next_stage_index) == 1, "Divergence rejection changed ghost progress")


func _test_builder_agent_executes_plan() -> void:
	var adapter = AdapterScript.new()
	_assert_ok(adapter.setup(FixtureScript.source_projections()), "Builder fixture adapter setup failed")
	var store = StoreScript.new()
	_assert_ok(store.setup(), "Builder fixture store setup failed")
	var process = ProcessScript.new()
	_assert_ok(process.setup(adapter, store), "Builder fixture process setup failed")
	_assert_ok(process.register_plan(FixtureScript.build_plan()), "Builder fixture plan registration failed")
	var builder = BuilderAgentScript.new()
	_assert_ok(builder.setup(process, "actor/c3-builder", ["INSPECT", "FASTEN"]), "Builder agent setup failed")
	var completed: Dictionary = builder.run_until_complete(FixtureScript.BUILD_PLAN_ID)
	_assert_ok(completed, "Builder agent did not complete plan")
	_assert(bool(completed.complete), "Builder agent result not complete")
	_assert(completed.stage_results.size() == 3, "Builder agent executed wrong stage count")
	_assert(String(store.get_ghost(FixtureScript.BUILD_PLAN_ID).status) == GhostScript.STATUS_COMPLETE, "Builder agent did not complete ghost")
	_assert(adapter.get_generation() == 3, "Builder agent did not commit three authoritative stages")
	var replay: Dictionary = builder.run_until_complete(FixtureScript.BUILD_PLAN_ID)
	_assert_ok(replay, "Completed builder replay failed")
	_assert(replay.stage_results.is_empty(), "Completed builder replay executed stages again")
	_assert(adapter.get_generation() == 3, "Completed builder replay advanced authority")


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_error(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("C3 BuildPlan integration: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C3 BuildPlan integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
