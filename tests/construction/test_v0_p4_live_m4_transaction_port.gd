extends SceneTree

const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const P4ItemGraphScript = preload("res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_p4.gd")
const AllocatorScript = preload("res://scripts/runtime/networked_gameplay/m4/v0_p4_construction_material_allocator.gd")
const LivePortScript = preload("res://scripts/runtime/networked_gameplay/m4/v0_p4_live_m4_construction_transaction_port.gd")
const InMemoryAdapterScript = preload("res://scripts/construction/item_graph/in_memory_construction_item_graph_adapter.gd")
const BuildPlanScript = preload("res://scripts/construction/build/construction_build_plan.gd")
const StageScript = preload("res://scripts/construction/build/construction_build_stage.gd")
const StagePlannerScript = preload("res://scripts/construction/build/construction_stage_transaction_planner.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const FixtureScript = preload("res://tests/construction/fixtures/c3_table_build_fixture.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_atomic_success_uses_one_live_m4()
	_test_toctou_rejects_without_mutation()
	_test_construction_failure_rolls_back_both_domains()
	_test_injected_post_m4_failure_rolls_back()
	_test_duplicate_is_exact_once()
	_test_operation_id_payload_conflict_is_rejected()
	_test_foreign_player_cannot_rebind_allocation()
	_test_client_command_surface_cannot_consume_construction_materials()
	_finish()


func _test_atomic_success_uses_one_live_m4() -> void:
	var env := _environment("atomic")
	_assert_ok(env, "environment setup failed")
	if not bool(env.get("success", false)):
		return
	var item_graph = env["item_graph"]
	var adapter = env["adapter"]
	var port = env["port"]
	_assert(port.is_bound_to_item_graph(item_graph), "port must retain exact canonical M4 object identity")
	var allocation: Dictionary = AllocatorScript.allocate_r1(item_graph, "alpha", 3)
	_assert_ok(allocation, "allocator failed")
	if not bool(allocation.get("success", false)):
		return
	var planned := _planned_stage(port, allocation, "operation/v0-p4/live/atomic")
	_assert_ok(planned, "stage planning failed")
	if not bool(planned.get("success", false)):
		return
	var selected: Array = allocation["details"]["allocations"]
	_assert(selected.size() == 2, "3 ore must allocate across two deterministic stacks")
	for row in selected:
		_assert(adapter.get_item_projection(String(row["item_id"])).is_empty(), "M4 ore must never be copied into Construction adapter")
	var before_revision := int(item_graph.create_snapshot()["revision"])
	var applied: Dictionary = port.apply_live_plan(planned["transaction_plan"], allocation, "alpha")
	_assert_ok(applied, "live M4 transaction failed")
	if not bool(applied.get("success", false)):
		return
	var first_id := String(selected[0]["item_id"])
	var second_id := String(selected[1]["item_id"])
	var after: Dictionary = item_graph.create_snapshot()
	_assert(int(after["revision"]) == before_revision + 1, "one compound material debit must advance M4 exactly once")
	_assert(_snapshot_item(after, first_id).is_empty(), "exactly exhausted first stack must be deleted from M4")
	_assert(int(_snapshot_item(after, second_id).get("quantity", -1)) == 2, "second stack must be partially debited to quantity 2")
	_assert(not adapter.get_construct_snapshot(FixtureScript.CONSTRUCT_ID).is_empty(), "Construction state must advance in same accepted operation")
	for row in selected:
		_assert(adapter.get_item_projection(String(row["item_id"])).is_empty(), "Construction adapter must remain free of M4 material shadow state after commit")
	_assert(bool(applied["details"].get("single_item_graph_identity", false)), "success must report single live Item Graph identity")


func _test_toctou_rejects_without_mutation() -> void:
	var env := _environment("stale")
	if not _assert_env(env): return
	var item_graph = env["item_graph"]
	var adapter = env["adapter"]
	var port = env["port"]
	var allocation: Dictionary = AllocatorScript.allocate_r1(item_graph, "alpha", 1)
	var planned := _planned_stage(port, allocation, "operation/v0-p4/live/stale")
	if not _assert_planned(allocation, planned): return
	var changed: Dictionary = item_graph.apply_server_output("operation/v0-p4/test/stale-bump", "alpha", "item/beacon", 1, "test/stale")
	_assert_ok(changed, "failed to advance M4 after allocation")
	var before_item: Dictionary = item_graph.create_snapshot()
	var before_construction: Dictionary = adapter.export_state()
	var applied: Dictionary = port.apply_live_plan(planned["transaction_plan"], allocation, "alpha")
	_assert(not bool(applied.get("success", false)), "stale allocator snapshot must reject")
	_assert(String(applied.get("error_code", "")) == "CONSTRUCTION_MATERIAL_SNAPSHOT_STALE", "stale rejection code mismatch")
	_assert(_canonical_equal(item_graph.create_snapshot(), before_item), "stale rejection must not mutate M4")
	_assert(_canonical_equal(adapter.export_state(), before_construction), "stale rejection must not mutate Construction")


func _test_construction_failure_rolls_back_both_domains() -> void:
	var env := _environment("construction-failure")
	if not _assert_env(env): return
	var item_graph = env["item_graph"]
	var adapter = env["adapter"]
	var port = env["port"]
	var allocation: Dictionary = AllocatorScript.allocate_r1(item_graph, "alpha", 3)
	var planned := _planned_stage(port, allocation, "operation/v0-p4/live/construction-failure")
	if not _assert_planned(allocation, planned): return
	var before_item: Dictionary = item_graph.create_snapshot()
	var before_replay: Dictionary = item_graph.export_replay_state()
	var before_construction: Dictionary = adapter.export_state()
	var applied: Dictionary = port.apply_live_plan(
		planned["transaction_plan"], allocation, "alpha", {"construction_failure_mode": "BEFORE_COMMIT"}
	)
	_assert(not bool(applied.get("success", false)), "injected Construction failure must reject")
	_assert(String(applied.get("error_code", "")) == "INJECTED_CONSTRUCTION_COMMIT_FAILURE", "Construction failure code must be preserved")
	_assert(bool(applied.get("details", {}).get("rolled_back", false)), "Construction failure must report rollback")
	_assert(_canonical_equal(item_graph.create_snapshot(), before_item), "Construction failure must restore exact M4 snapshot")
	_assert(_canonical_equal(item_graph.export_replay_state(), before_replay), "Construction failure must restore M4 replay ledger")
	_assert(_canonical_equal(adapter.export_state(), before_construction), "Construction failure must restore Construction state and replay record")


func _test_injected_post_m4_failure_rolls_back() -> void:
	var env := _environment("post-m4")
	if not _assert_env(env): return
	var item_graph = env["item_graph"]
	var adapter = env["adapter"]
	var port = env["port"]
	var allocation: Dictionary = AllocatorScript.allocate_r1(item_graph, "alpha", 2)
	var planned := _planned_stage(port, allocation, "operation/v0-p4/live/post-m4")
	if not _assert_planned(allocation, planned): return
	var before_item: Dictionary = item_graph.create_snapshot()
	var before_construction: Dictionary = adapter.export_state()
	var applied: Dictionary = port.apply_live_plan(
		planned["transaction_plan"], allocation, "alpha", {"failure_point": LivePortScript.FAILURE_AFTER_M4_COMMIT}
	)
	_assert(not bool(applied.get("success", false)), "injected post-M4 failure must reject")
	_assert(String(applied.get("error_code", "")) == "INJECTED_P4_FAILURE_AFTER_M4_COMMIT", "injected failure code mismatch")
	_assert(bool(applied.get("details", {}).get("rolled_back", false)), "post-M4 injected failure must report rollback")
	_assert(_canonical_equal(item_graph.create_snapshot(), before_item), "post-M4 failure must restore M4")
	_assert(_canonical_equal(adapter.export_state(), before_construction), "post-M4 failure must leave Construction unchanged")


func _test_duplicate_is_exact_once() -> void:
	var env := _environment("duplicate")
	if not _assert_env(env): return
	var item_graph = env["item_graph"]
	var adapter = env["adapter"]
	var port = env["port"]
	var allocation: Dictionary = AllocatorScript.allocate_r1(item_graph, "alpha", 2)
	var planned := _planned_stage(port, allocation, "operation/v0-p4/live/duplicate")
	if not _assert_planned(allocation, planned): return
	var first: Dictionary = port.apply_live_plan(planned["transaction_plan"], allocation, "alpha")
	_assert_ok(first, "first exact-once execution failed")
	if not bool(first.get("success", false)): return
	var after_first_item: Dictionary = item_graph.create_snapshot()
	var after_first_construction: Dictionary = adapter.export_state()
	var second: Dictionary = port.apply_live_plan(planned["transaction_plan"], allocation, "alpha")
	_assert_ok(second, "duplicate exact-once execution must replay")
	if not bool(second.get("success", false)): return
	_assert(bool(second["details"].get("replay", false)), "duplicate must be reported as replay")
	_assert(_canonical_equal(item_graph.create_snapshot(), after_first_item), "duplicate must not debit ore twice")
	_assert(_canonical_equal(adapter.export_state(), after_first_construction), "duplicate must not advance Construction twice")


func _test_operation_id_payload_conflict_is_rejected() -> void:
	var env := _environment("conflict")
	if not _assert_env(env): return
	var item_graph = env["item_graph"]
	var adapter = env["adapter"]
	var port = env["port"]
	var op := "operation/v0-p4/live/conflict"
	var allocation: Dictionary = AllocatorScript.allocate_r1(item_graph, "alpha", 2)
	var planned := _planned_stage(port, allocation, op)
	if not _assert_planned(allocation, planned): return
	var first: Dictionary = port.apply_live_plan(planned["transaction_plan"], allocation, "alpha")
	_assert_ok(first, "conflict baseline execution failed")
	if not bool(first.get("success", false)): return
	var before_item: Dictionary = item_graph.create_snapshot()
	var before_construction: Dictionary = adapter.export_state()
	var different: Dictionary = AllocatorScript.allocate_r1(item_graph, "alpha", 1)
	var different_plan := _planned_stage(port, different, op)
	if not _assert_planned(different, different_plan): return
	var conflict: Dictionary = port.apply_live_plan(different_plan["transaction_plan"], different, "alpha")
	_assert(not bool(conflict.get("success", false)), "same operation id with different allocation must conflict")
	_assert(String(conflict.get("error_code", "")) == "OPERATION_REPLAY_CONFLICT", "M4 operation conflict code mismatch")
	_assert(_canonical_equal(item_graph.create_snapshot(), before_item), "operation conflict must not mutate M4")
	_assert(_canonical_equal(adapter.export_state(), before_construction), "operation conflict must not mutate Construction")


func _test_foreign_player_cannot_rebind_allocation() -> void:
	var env := _environment("foreign")
	if not _assert_env(env): return
	var item_graph = env["item_graph"]
	var adapter = env["adapter"]
	var port = env["port"]
	item_graph.ensure_player_for_join("beta")
	var foreign_output: Dictionary = item_graph.apply_server_output("operation/v0-p4/test/foreign-beta", "beta", "item/ore", 10, "test/foreign")
	_assert_ok(foreign_output, "failed to seed beta ore")
	var allocation: Dictionary = AllocatorScript.allocate_r1(item_graph, "alpha", 2)
	var planned := _planned_stage(port, allocation, "operation/v0-p4/live/foreign")
	if not _assert_planned(allocation, planned): return
	var before_item: Dictionary = item_graph.create_snapshot()
	var before_construction: Dictionary = adapter.export_state()
	var applied: Dictionary = port.apply_live_plan(planned["transaction_plan"], allocation, "beta")
	_assert(not bool(applied.get("success", false)), "foreign player must not reuse alpha allocation")
	_assert(String(applied.get("error_code", "")) == "P4_ALLOCATOR_PLAYER_MISMATCH", "foreign player rejection code mismatch")
	_assert(_canonical_equal(item_graph.create_snapshot(), before_item), "foreign player rejection must not mutate M4")
	_assert(_canonical_equal(adapter.export_state(), before_construction), "foreign player rejection must not mutate Construction")


func _test_client_command_surface_cannot_consume_construction_materials() -> void:
	var env := _environment("client-fence")
	if not _assert_env(env): return
	var item_graph = env["item_graph"]
	var before: Dictionary = item_graph.create_snapshot()
	var result: Dictionary = item_graph.execute(
		"alpha",
		1,
		"operation/v0-p4/client/fence",
		P4ItemGraphScript.TRUSTED_CONSTRUCTION_CONSUME_COMMAND_TYPE,
		{}
	)
	_assert(not bool(result.get("success", false)), "trusted construction consume must not be exposed through client execute")
	_assert(String(result.get("error_code", "")) == "UNSUPPORTED_ITEM_COMMAND", "client construction-consume fence error mismatch")
	_assert(_canonical_equal(item_graph.create_snapshot(), before), "client construction-consume probe must not mutate M4")


func _environment(suffix: String) -> Dictionary:
	var item_graph = P4ItemGraphScript.new()
	var setup: Dictionary = item_graph.setup("authority/v0-p4-test/%s" % suffix, 1, {"playable_sandbox": false})
	if not bool(setup.get("success", false)):
		return setup
	var joined: Dictionary = item_graph.ensure_player_for_join("alpha")
	if not bool(joined.get("success", false)):
		return joined
	for row in [["a", 2], ["b", 3]]:
		var output: Dictionary = item_graph.apply_server_output(
			"operation/v0-p4/test/%s/%s" % [suffix, row[0]],
			"alpha",
			"item/ore",
			int(row[1]),
			"test/%s/%s" % [suffix, row[0]]
		)
		if not bool(output.get("success", false)):
			return output
	var structural_sources: Array = []
	for projection_value in FixtureScript.source_projections():
		var projection: Dictionary = projection_value
		if String(projection.get("item_instance_id", "")) in FixtureScript.PART_ITEM_IDS:
			structural_sources.append(projection.duplicate(true))
	var adapter = InMemoryAdapterScript.new()
	setup = adapter.setup(structural_sources, [])
	if not bool(setup.get("success", false)):
		return setup
	var port = LivePortScript.new()
	setup = port.setup(item_graph, adapter)
	if not bool(setup.get("success", false)):
		return setup
	return {"success": true, "error_code": "", "item_graph": item_graph, "adapter": adapter, "port": port}


func _planned_stage(port, allocation: Dictionary, operation_id: String) -> Dictionary:
	if not bool(allocation.get("success", false)):
		return allocation
	var details: Dictionary = allocation.get("details", {})
	var sources: Array = []
	for projection_value in FixtureScript.source_projections():
		var projection: Dictionary = projection_value
		if String(projection.get("item_instance_id", "")) in FixtureScript.PART_ITEM_IDS:
			sources.append(projection.duplicate(true))
	var material_allocations: Array = []
	for allocation_value in details.get("allocations", []):
		var row: Dictionary = allocation_value
		var item_id := String(row.get("item_id", ""))
		var projected: Dictionary = port.get_item_projection(item_id)
		if projected.is_empty():
			return {"success": false, "error_code": "TEST_M4_PROJECTION_MISSING"}
		sources.append(projected)
		material_allocations.append({
			"item_instance_id": item_id,
			"definition_id": LivePortScript.R1_CONSTRUCTION_DEFINITION_ID,
			"quantity": int(row.get("quantity", 0)),
		})
	var stages: Array = [
		StageScript.create(
			"stage/v0-p4/live/foundation", 0, "P4 live foundation", StageScript.SEMANTIC_FOUNDATION,
			["part/table/top", "part/table/leg-a", "part/table/leg-b"],
			["bond/table/leg-a", "bond/table/leg-b"],
			material_allocations, ["FASTEN"]
		),
		StageScript.create(
			"stage/v0-p4/live/frame", 1, "P4 live frame", StageScript.SEMANTIC_FRAME,
			["part/table/top", "part/table/leg-a", "part/table/leg-b", "part/table/leg-c"],
			["bond/table/leg-a", "bond/table/leg-b", "bond/table/leg-c"],
			[], ["FASTEN"]
		),
		StageScript.create(
			"stage/v0-p4/live/operational", 2, "P4 live operational", StageScript.SEMANTIC_OPERATIONAL,
			["part/table/top", "part/table/leg-a", "part/table/leg-b", "part/table/leg-c", "part/table/leg-d"],
			["bond/table/leg-a", "bond/table/leg-b", "bond/table/leg-c", "bond/table/leg-d"],
			[], ["INSPECT"]
		),
	]
	var build_plan := BuildPlanScript.create(
		"build-plan/v0-p4/live",
		"V0 P4 live M4 transaction",
		ProjectionScript.world_relation(),
		FixtureScript.target_snapshot(),
		sources,
		stages
	)
	var build_validation: Dictionary = BuildPlanScript.validate(build_plan)
	if not bool(build_validation.get("success", false)):
		return build_validation
	return StagePlannerScript.build_stage_transaction_plan(build_plan, 0, operation_id)


func _snapshot_item(snapshot: Dictionary, item_id: String) -> Dictionary:
	for item_value in snapshot.get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			return Dictionary(item_value).duplicate(true)
	return {}


func _canonical_equal(left, right) -> bool:
	return NetworkUtils.canonical_json(left) == NetworkUtils.canonical_json(right)


func _assert_env(env: Dictionary) -> bool:
	_assert_ok(env, "environment setup failed")
	return bool(env.get("success", false))


func _assert_planned(allocation: Dictionary, planned: Dictionary) -> bool:
	_assert_ok(allocation, "allocator failed")
	_assert_ok(planned, "stage planning failed")
	return bool(allocation.get("success", false)) and bool(planned.get("success", false))


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("V0-P4 live M4 transaction port: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("V0-P4 live M4 transaction port: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
