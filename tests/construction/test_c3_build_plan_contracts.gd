extends SceneTree

const FixtureScript = preload("res://tests/construction/fixtures/c3_table_build_fixture.gd")
const StageScript = preload("res://scripts/construction/build/construction_build_stage.gd")
const BuildPlanScript = preload("res://scripts/construction/build/construction_build_plan.gd")
const GhostScript = preload("res://scripts/construction/build/construction_ghost_state.gd")
const StoreScript = preload("res://scripts/construction/build/construction_build_plan_store.gd")
const SnapshotBuilderScript = preload("res://scripts/construction/build/construction_stage_snapshot_builder.gd")
const StagePlannerScript = preload("res://scripts/construction/build/construction_stage_transaction_planner.gd")
const TransactionPlanScript = preload("res://scripts/construction/item_graph/construction_item_transaction_plan.gd")
const PersistenceScript = preload("res://scripts/construction/build/construction_build_plan_persistence.gd")

class MemoryStateStore:
	extends RefCounted
	var states: Dictionary = {}

	func save_state(key: String, state: Dictionary) -> Dictionary:
		states[key] = state.duplicate(true)
		return {"success": true}

	func load_state(key: String) -> Dictionary:
		if not states.has(key):
			return {"success": false, "error_code": "STATE_NOT_FOUND"}
		return {"success": true, "state": Dictionary(states[key]).duplicate(true)}

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_stage_contract()
	_test_build_plan_contract()
	_test_ghost_contract()
	_test_stage_snapshot_builder()
	_test_stage_transaction_planner()
	_test_store_and_persistence()
	_test_runner_contracts()
	_finish()


func _test_stage_contract() -> void:
	var stage: Dictionary = FixtureScript.build_plan()["stages"][0]
	_assert_ok(StageScript.validate(stage), "Valid build stage rejected")
	_assert(stage["material_allocations"][0]["item_instance_id"] == FixtureScript.FASTENER_ID, "Stage allocations not canonical")
	var wrong_index: Dictionary = stage.duplicate(true)
	wrong_index["sequence_index"] = -1
	_assert_error(StageScript.validate(wrong_index), "INVALID_CONSTRUCTION_BUILD_STAGE_INDEX", "Negative stage index accepted")
	var duplicate_parts: Dictionary = stage.duplicate(true)
	duplicate_parts["included_part_ids"] = ["part/table/top", "part/table/top"]
	_assert_error(StageScript.validate(duplicate_parts), "INVALID_BUILD_STAGE_PART_IDS", "Duplicate stage part accepted")
	var unsorted_caps: Dictionary = stage.duplicate(true)
	unsorted_caps["required_capabilities"] = ["WELD", "FASTEN"]
	_assert_error(StageScript.validate(unsorted_caps), "BUILD_STAGE_REQUIRED_CAPABILITIES_NOT_SORTED", "Unsorted capability set accepted")
	var duplicate_material: Dictionary = stage.duplicate(true)
	duplicate_material["material_allocations"] = [stage["material_allocations"][0], stage["material_allocations"][0]]
	_assert_error(StageScript.validate(duplicate_material), "DUPLICATE_BUILD_STAGE_MATERIAL_ITEM", "Duplicate material source accepted")


func _test_build_plan_contract() -> void:
	var plan: Dictionary = FixtureScript.build_plan()
	_assert_ok(BuildPlanScript.validate(plan), "Valid C3 build plan rejected")
	_assert(String(plan["construct_id"]) == FixtureScript.CONSTRUCT_ID, "Build plan construct identity mismatch")
	_assert(String(plan["root_item_instance_id"]) == FixtureScript.ROOT_ID, "Build plan root identity mismatch")
	_assert(plan["stages"].size() == 3, "Build plan stage count mismatch")
	_assert(BuildPlanScript.source_projection_map(plan).size() == 7, "Build plan source map lost items")
	var mutated: Dictionary = plan.duplicate(true)
	mutated["display_name"] = "Changed"
	_assert_error(BuildPlanScript.validate(mutated), "CONSTRUCTION_BUILD_PLAN_CHECKSUM_MISMATCH", "Mutated build plan accepted stale checksum")
	var regressed: Dictionary = plan.duplicate(true)
	regressed["stages"][1]["included_part_ids"] = ["part/table/top"]
	regressed["checksum"] = BuildPlanScript.compute_checksum(regressed)
	_assert_error(BuildPlanScript.validate(regressed), "BUILD_PLAN_STAGE_CONTENT_REGRESSED", "Regressing stage accepted")
	var incomplete: Dictionary = plan.duplicate(true)
	incomplete["stages"][-1]["included_part_ids"].erase("part/table/leg-d")
	incomplete["checksum"] = BuildPlanScript.compute_checksum(incomplete)
	_assert_error(BuildPlanScript.validate(incomplete), "BUILD_PLAN_STAGE_CONTENT_REGRESSED", "Final stage with removed part accepted")
	var exhausted: Dictionary = plan.duplicate(true)
	exhausted["stages"][0]["material_allocations"][0]["quantity"] = 9
	exhausted["checksum"] = BuildPlanScript.compute_checksum(exhausted)
	_assert_error(BuildPlanScript.validate(exhausted), "BUILD_PLAN_MATERIAL_WOULD_EXHAUST_STACK", "Plan allowed complete stack exhaustion")
	var unused: Dictionary = plan.duplicate(true)
	unused["source_item_projections"].append(unused["source_item_projections"][0].duplicate(true))
	unused["source_item_projections"][-1]["item_instance_id"] = "item/c3-unused"
	unused["source_item_projections"].sort_custom(func(a, b): return String(a["item_instance_id"]) < String(b["item_instance_id"]))
	unused["checksum"] = BuildPlanScript.compute_checksum(unused)
	_assert_error(BuildPlanScript.validate(unused), "BUILD_PLAN_HAS_UNUSED_SOURCE_ITEMS", "Unused source projection accepted")


func _test_ghost_contract() -> void:
	var plan: Dictionary = FixtureScript.build_plan()
	var ghost: Dictionary = GhostScript.create(plan)
	_assert_ok(GhostScript.validate(ghost), "Fresh ghost state rejected")
	_assert(String(ghost["status"]) == GhostScript.STATUS_GHOST, "Fresh ghost status mismatch")
	_assert(int(ghost["next_stage_index"]) == 0, "Fresh ghost has progress")
	_assert(ghost["completed_stage_ids"].is_empty(), "Fresh ghost has completed stages")
	var progressed: Dictionary = GhostScript.with_progress(
		ghost,
		["stage/table/foundation"],
		["operation/c3/stage-0"],
		["a".repeat(64)],
		3
	)
	_assert_ok(GhostScript.validate(progressed), "Progressed ghost rejected")
	_assert(String(progressed["status"]) == GhostScript.STATUS_IN_PROGRESS, "Progressed ghost status mismatch")
	var completed: Dictionary = GhostScript.with_progress(
		progressed,
		["stage/table/foundation", "stage/table/frame", "stage/table/commissioning"],
		["operation/c3/stage-0", "operation/c3/stage-1", "operation/c3/stage-2"],
		["a".repeat(64), "b".repeat(64), "c".repeat(64)],
		3
	)
	_assert_ok(GhostScript.validate(completed), "Completed ghost rejected")
	_assert(String(completed["status"]) == GhostScript.STATUS_COMPLETE, "Completed ghost status mismatch")
	var mismatched: Dictionary = completed.duplicate(true)
	mismatched["completed_operation_ids"].pop_back()
	mismatched["checksum"] = GhostScript.compute_checksum(mismatched)
	_assert_error(GhostScript.validate(mismatched), "CONSTRUCTION_GHOST_COMPLETION_COLLECTION_SIZE_MISMATCH", "Mismatched completion arrays accepted")


func _test_stage_snapshot_builder() -> void:
	var plan: Dictionary = FixtureScript.build_plan()
	var stage_zero: Dictionary = SnapshotBuilderScript.build_for_stage(plan, 0)
	_assert_ok(stage_zero, "Stage zero snapshot failed")
	_assert(int(stage_zero["snapshot"]["state_revision"]) == 0, "Stage zero snapshot revision mismatch")
	_assert(String(stage_zero["snapshot"]["build_state"]) == "PARTIAL", "Stage zero must be partial")
	_assert(stage_zero["snapshot"]["parts"].size() == 3, "Stage zero part count mismatch")
	_assert(stage_zero["snapshot"]["compiled_facets"]["capabilities"].is_empty(), "Partial construct exposed capabilities")
	_assert(not bool(stage_zero["snapshot"]["compiled_facets"]["operational"]), "Partial construct marked operational")
	var stage_one: Dictionary = SnapshotBuilderScript.build_for_stage(plan, 1)
	_assert_ok(stage_one, "Stage one snapshot failed")
	_assert(stage_one["snapshot"]["parts"].size() == 5, "Frame stage part count mismatch")
	_assert(stage_one["snapshot"]["compiled_facets"]["capabilities"].is_empty(), "Frame stage exposed operational capabilities")
	var final_stage: Dictionary = SnapshotBuilderScript.build_for_stage(plan, 2)
	_assert_ok(final_stage, "Final stage snapshot failed")
	_assert(String(final_stage["snapshot"]["build_state"]) == "OPERATIONAL", "Final stage not operational")
	_assert(bool(final_stage["snapshot"]["compiled_facets"]["operational"]), "Final compiled facet not operational")
	_assert(final_stage["snapshot"]["compiled_facets"]["capabilities"] == ["PLACE_ITEMS", "SUPPORT_SURFACE", "WORK_SURFACE"], "Final capabilities mismatch")
	_assert(int(SnapshotBuilderScript.completed_stage_count(plan, {}).get("completed_stage_count", -1)) == 0, "Empty construct did not resolve zero stages")
	_assert(int(SnapshotBuilderScript.completed_stage_count(plan, stage_one["snapshot"]).get("completed_stage_count", -1)) == 2, "Frame snapshot did not resolve two stages")
	var diverged: Dictionary = stage_one["snapshot"].duplicate(true)
	diverged["compiled_facets"]["operational"] = true
	diverged["checksum"] = preload("res://scripts/construction/contracts/construct_snapshot.gd").compute_checksum(diverged)
	_assert_error(SnapshotBuilderScript.completed_stage_count(plan, diverged), "CONSTRUCTION_BUILD_PLAN_CONSTRUCT_DIVERGED", "Diverged construct matched a stage")


func _test_stage_transaction_planner() -> void:
	var plan: Dictionary = FixtureScript.build_plan()
	var stage_zero: Dictionary = StagePlannerScript.build_stage_transaction_plan(plan, 0, "operation/c3/contracts/stage-0")
	_assert_ok(stage_zero, "Stage zero transaction plan failed")
	var tx0: Dictionary = stage_zero["transaction_plan"]
	_assert_ok(TransactionPlanScript.validate(tx0), "Stage zero transaction plan rejected")
	_assert(String(tx0["command_type"]) == TransactionPlanScript.COMMAND_ADVANCE_STAGE, "Stage command type mismatch")
	_assert(String(tx0["construct_mutation"]["operation_kind"]) == "CREATE", "First stage must create construct")
	_assert(tx0["item_mutations"].size() == 5, "First stage must create root, attach three parts and consume material")
	var stage_one: Dictionary = StagePlannerScript.build_stage_transaction_plan(plan, 1, "operation/c3/contracts/stage-1")
	_assert_ok(stage_one, "Stage one transaction plan failed")
	var tx1: Dictionary = stage_one["transaction_plan"]
	_assert(String(tx1["construct_mutation"]["operation_kind"]) == "UPDATE", "Later stage must update construct")
	_assert(tx1["item_mutations"].size() == 3, "Frame stage mutation count mismatch")
	var fastener_before: Dictionary = {}
	for mutation in tx1["item_mutations"]:
		if String(mutation["item_instance_id"]) == FixtureScript.FASTENER_ID:
			fastener_before = mutation["before_projection"]
	_assert(int(fastener_before.get("quantity", -1)) == 8, "Second stage did not derive cumulative material quantity")
	_assert(int(fastener_before.get("revision", -1)) == 1, "Second stage did not derive cumulative material revision")
	var deterministic: Dictionary = StagePlannerScript.build_stage_transaction_plan(plan, 1, "operation/c3/contracts/stage-1")
	_assert(String(deterministic["transaction_plan"]["checksum"]) == String(tx1["checksum"]), "Stage planner not deterministic")
	_assert_error(StagePlannerScript.build_stage_transaction_plan(plan, 3, "operation/c3/contracts/out-of-range"), "INVALID_CONSTRUCTION_BUILD_STAGE_INDEX", "Out-of-range stage accepted")


func _test_store_and_persistence() -> void:
	var plan: Dictionary = FixtureScript.build_plan()
	var store = StoreScript.new()
	_assert_ok(store.setup(), "Build plan store setup failed")
	var registered: Dictionary = store.register_plan(plan)
	_assert_ok(registered, "Build plan registration failed")
	_assert(not bool(registered["replay"]), "First registration marked replay")
	_assert(int(store.get_generation()) == 1, "Registration did not advance store generation")
	_assert_ok(store.register_plan(plan), "Exact build plan registration replay failed")
	_assert(int(store.get_generation()) == 1, "Registration replay advanced generation")
	var conflict: Dictionary = plan.duplicate(true)
	conflict["display_name"] = "Conflict"
	conflict["checksum"] = BuildPlanScript.compute_checksum(conflict)
	_assert_error(store.register_plan(conflict), "CONSTRUCTION_BUILD_PLAN_ID_CONFLICT", "Conflicting build plan ID accepted")
	_assert_ok(store.record_stage_success(FixtureScript.BUILD_PLAN_ID, 0, "operation/c3/store/stage-0", "1".repeat(64)), "Store did not record stage success")
	_assert(int(store.get_ghost(FixtureScript.BUILD_PLAN_ID)["next_stage_index"]) == 1, "Store progress did not advance")
	_assert_ok(store.record_stage_success(FixtureScript.BUILD_PLAN_ID, 0, "operation/c3/store/stage-0", "1".repeat(64)), "Stage success replay failed")
	_assert_error(store.record_stage_success(FixtureScript.BUILD_PLAN_ID, 2, "operation/c3/store/stage-2", "2".repeat(64)), "CONSTRUCTION_BUILD_STAGE_ORDER_VIOLATION", "Out-of-order stage accepted")
	var state: Dictionary = store.to_dict()
	_assert_ok(StoreScript.validate_state(state), "Build plan store state rejected")
	var restored = StoreScript.new()
	_assert_ok(restored.load_dict(state), "Build plan store round-trip failed")
	_assert(restored.to_dict() == state, "Build plan store round-trip changed state")
	var tampered: Dictionary = state.duplicate(true)
	tampered["generation"] = int(tampered["generation"]) + 1
	_assert_error(restored.load_dict(tampered), "CONSTRUCTION_BUILD_PLAN_STORE_CHECKSUM_MISMATCH", "Tampered build plan store accepted")
	_assert(restored.to_dict() == state, "Rejected store load mutated active state")
	var memory_store = MemoryStateStore.new()
	var persistence = PersistenceScript.new()
	_assert_ok(persistence.setup(store, memory_store, "c3-store"), "Build plan persistence setup failed")
	_assert_ok(persistence.save(), "Build plan persistence save failed")
	var loaded_store = StoreScript.new()
	_assert_ok(loaded_store.setup(), "Loaded store setup failed")
	var loaded_persistence = PersistenceScript.new()
	_assert_ok(loaded_persistence.setup(loaded_store, memory_store, "c3-store"), "Loaded persistence setup failed")
	_assert_ok(loaded_persistence.load(), "Build plan persistence load failed")
	_assert(loaded_store.to_dict() == store.to_dict(), "Build plan persistence changed state")


func _test_runner_contracts() -> void:
	var focused_runner: String = FileAccess.get_file_as_string("res://RUN_C3_BUILD_PLAN_TESTS.ps1")
	var world_runner: String = FileAccess.get_file_as_string("res://RUN_WORLD_REGRESSION_TESTS.ps1")
	_assert(not focused_runner.is_empty(), "C3 focused runner missing")
	_assert(focused_runner.contains("test_c3_build_plan_contracts.gd"), "C3 focused runner omits contract test")
	_assert(focused_runner.contains("test_c3_build_plan_integration.gd"), "C3 focused runner omits integration test")
	_assert(world_runner.contains("test_c3_build_plan_contracts.gd"), "World regression omits C3 contract test")
	_assert(world_runner.contains("test_c3_build_plan_integration.gd"), "World regression omits C3 integration test")


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
		print("C3 BuildPlan contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C3 BuildPlan contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
