extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const FixtureScript = preload("res://tests/construction/fixtures/c9_damage_split_repair_fixture.gd")
const PolicyScript = preload("res://scripts/construction/damage/construction_salvage_policy.gd")
const RequestScript = preload("res://scripts/construction/damage/construction_damage_request.gd")
const ComponentScript = preload("res://scripts/construction/damage/construction_damage_component.gd")
const RepairPlanScript = preload("res://scripts/construction/damage/construction_repair_plan.gd")
const TransactionScript = preload("res://scripts/construction/damage/construction_damage_transaction_plan.gd")
const PlannerScript = preload("res://scripts/construction/damage/construction_damage_planner.gd")
const GhostScript = preload("res://scripts/construction/damage/construction_repair_ghost_state.gd")
const RecordScript = preload("res://scripts/construction/damage/construction_damage_record.gd")
const HistoryScript = preload("res://scripts/construction/damage/construction_damage_history_store.gd")
const PersistenceScript = preload("res://scripts/construction/damage/construction_damage_persistence.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const ItemMutationScript = preload("res://scripts/construction/item_graph/construction_item_mutation.gd")
const TranslatorScript = preload("res://scripts/construction/authoritative/construction_m0_batch_translator.gd")
const BatchScript = preload("res://scripts/simulation/transactions/mutation_batch.gd")

class MemoryStore:
	var states: Dictionary = {}
	func save_state(key: String, state: Dictionary) -> Dictionary:
		states[key] = state.duplicate(true)
		return {"success": true, "error_code": "", "message": ""}
	func load_state(key: String) -> Dictionary:
		if not states.has(key): return {"success": false, "error_code": "NOT_FOUND", "message": "NOT_FOUND"}
		return {"success": true, "error_code": "", "message": "", "state": Dictionary(states[key]).duplicate(true)}

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_policy_and_request()
	_test_planner_contracts()
	_test_ghost_record_and_persistence()
	_test_m0_multi_aggregate_translation()
	_finish()

func _test_policy_and_request() -> void:
	var policy := PolicyScript.create(2, ProjectionScript.world_relation(), false)
	_assert_ok(PolicyScript.validate(policy), "Valid salvage policy rejected")
	_assert(int(policy.minimum_split_parts) == 2, "Policy minimum mismatch")
	_assert(String(policy.checksum).length() == 64, "Policy checksum invalid")
	var policy_roundtrip = JSON.parse_string(JSON.stringify(policy, "", true, true))
	_assert(policy_roundtrip is Dictionary, "Policy JSON roundtrip failed")
	_assert_ok(PolicyScript.validate(policy_roundtrip), "Policy JSON roundtrip rejected")
	var unexpected := policy.duplicate(true); unexpected["unexpected_field"] = true
	_assert_error(PolicyScript.validate(unexpected), "UNEXPECTED_FIELD", "Policy accepted unexpected field")
	var bad_min := policy.duplicate(true); bad_min.minimum_split_parts = 0; bad_min.checksum = PolicyScript.compute_checksum(bad_min)
	_assert_error(PolicyScript.validate(bad_min), "INVALID_CONSTRUCTION_SALVAGE_MINIMUM_SPLIT_PARTS", "Policy accepted zero minimum")
	var bad_relation := policy.duplicate(true); bad_relation.salvage_relation = {"kind": "DESTROYED"}; bad_relation.checksum = PolicyScript.compute_checksum(bad_relation)
	_assert_error(PolicyScript.validate(bad_relation), "CONSTRUCTION_SALVAGE_RELATION_NOT_TRANSFERABLE", "Policy accepted destroyed relation")
	var tampered := policy.duplicate(true); tampered.allow_destroyed_salvage = true
	_assert_error(PolicyScript.validate(tampered), "CONSTRUCTION_SALVAGE_POLICY_CHECKSUM_MISMATCH", "Policy accepted tamper")

	var snapshot := FixtureScript.snapshot()
	var request := FixtureScript.request("a", snapshot)
	_assert_ok(RequestScript.validate(request), "Valid damage request rejected")
	_assert(String(request.construct_id) == String(snapshot.construct_id), "Request construct mismatch")
	_assert(request.broken_bond_ids.size() == 2, "Request broken bond count mismatch")
	_assert(String(request.broken_bond_ids[0]) < String(request.broken_bond_ids[1]), "Request bonds not sorted")
	_assert(request.part_conditions.keys() == request.part_conditions.keys().duplicate(), "Request part conditions unavailable")
	_assert(String(request.checksum).length() == 64, "Request checksum invalid")
	var request_roundtrip = JSON.parse_string(JSON.stringify(request, "", true, true))
	_assert(request_roundtrip is Dictionary, "Request JSON roundtrip failed")
	_assert_ok(RequestScript.validate(request_roundtrip), "Request roundtrip rejected")
	_assert(UtilsScript.canonical_json(request_roundtrip) == UtilsScript.canonical_json(request), "Request roundtrip changed")
	var overlap := request.duplicate(true); overlap.degraded_bond_ids = [overlap.broken_bond_ids[0]]; overlap.checksum = RequestScript.compute_checksum(overlap)
	_assert_error(RequestScript.validate(overlap), "CONSTRUCTION_DAMAGE_BOND_STATE_CONFLICT", "Request accepted conflicting bond states")
	var duplicate_target := request.duplicate(true); duplicate_target.split_targets.append(duplicate_target.split_targets[0].duplicate(true)); duplicate_target.checksum = RequestScript.compute_checksum(duplicate_target)
	_assert_error(RequestScript.validate(duplicate_target), "DUPLICATE_CONSTRUCTION_DAMAGE_SPLIT_TARGET", "Request accepted duplicate split target")
	var bad_condition := request.duplicate(true); bad_condition.part_conditions[bad_condition.part_conditions.keys()[0]] = "VAPORIZED"; bad_condition.checksum = RequestScript.compute_checksum(bad_condition)
	_assert_error(RequestScript.validate(bad_condition), "INVALID_CONSTRUCTION_DAMAGE_PART_CONDITION", "Request accepted invalid condition")
	var bad_source := request.duplicate(true); bad_source.source_snapshot_checksum = "0".repeat(64); bad_source.checksum = RequestScript.compute_checksum(bad_source)
	_assert_ok(RequestScript.validate(bad_source), "Structurally valid stale request rejected too early")

func _test_planner_contracts() -> void:
	var snapshot := FixtureScript.snapshot()
	var items := FixtureScript.items()
	var request := FixtureScript.request("a", snapshot)
	var planned := PlannerScript.build_damage_plan("plan/c9/damage/a", "operation/c9/damage/a", request, snapshot, items)
	_assert_ok(planned, "Damage planning failed")
	var plan: Dictionary = planned.plan
	_assert_ok(TransactionScript.validate(plan), "Damage transaction rejected")
	_assert(String(plan.command_type) == TransactionScript.COMMAND_DAMAGE_SPLIT, "Damage command mismatch")
	_assert(plan.construct_mutations.size() == 2, "Damage construct mutation count mismatch")
	_assert(plan.item_mutations.size() == 5, "Damage item mutation count mismatch")
	_assert(planned.components.size() == 3, "Damage component count mismatch")
	_assert(String(planned.components[0].outcome) == "RETAINED", "Retained component missing")
	_assert(String(planned.components[1].outcome) == "SPLIT_CONSTRUCT", "Split component missing")
	_assert(String(planned.components[2].outcome) == "SALVAGE", "Salvage component missing")
	for component in planned.components:
		_assert_ok(ComponentScript.validate(component), "Damage component rejected")
	_assert(planned.salvage_item_ids == ["item/bridge/a/sensor"], "Salvage item mismatch")
	_assert(planned.split_construct_ids == ["construct/bridge/a/split-arm"], "Split construct mismatch")
	_assert_ok(RepairPlanScript.validate(planned.repair_plan), "Generated repair plan rejected")
	_assert(planned.repair_plan.required_part_item_ids.size() == 6, "Repair required part count mismatch")
	_assert(planned.repair_plan.split_root_item_ids == ["item/bridge/a/split-root"], "Repair split root mismatch")
	var purposes: Array = []
	for mutation in plan.item_mutations: purposes.append(String(mutation.purpose))
	_assert(purposes.has(ItemMutationScript.PURPOSE_APPLY_DAMAGE), "Damage mutation missing")
	_assert(purposes.has(ItemMutationScript.PURPOSE_REBIND_SPLIT_PART), "Split rebind mutation missing")
	_assert(purposes.has(ItemMutationScript.PURPOSE_SALVAGE_PART), "Salvage mutation missing")
	_assert(purposes.has(ItemMutationScript.PURPOSE_CREATE_ROOT), "Split root mutation missing")
	var unexpected := plan.duplicate(true); unexpected["unexpected_field"] = true
	_assert_error(TransactionScript.validate(unexpected), "UNEXPECTED_FIELD", "Damage plan accepted unexpected field")
	var duplicate := plan.duplicate(true); duplicate.construct_mutations.append(duplicate.construct_mutations[0].duplicate(true)); duplicate.construct_mutations.sort_custom(func(a,b): return String(a.construct_id) < String(b.construct_id)); duplicate.checksum = TransactionScript.compute_checksum(duplicate)
	_assert_error(TransactionScript.validate(duplicate), "DUPLICATE_CONSTRUCTION_DAMAGE_CONSTRUCT_MUTATION", "Damage plan accepted duplicate construct mutation")
	var tampered := plan.duplicate(true); tampered.plan_id = "plan/c9/tampered"
	_assert_error(TransactionScript.validate(tampered), "CONSTRUCTION_DAMAGE_TRANSACTION_CHECKSUM_MISMATCH", "Damage plan accepted checksum tamper")
	var exhausted := request.duplicate(true); exhausted.split_targets = []; exhausted.checksum = RequestScript.compute_checksum(exhausted)
	_assert_error(PlannerScript.build_damage_plan("plan/c9/exhausted", "operation/c9/exhausted", exhausted, snapshot, items), "CONSTRUCTION_DAMAGE_SPLIT_TARGETS_EXHAUSTED", "Planner accepted missing split target")
	var stale := request.duplicate(true); stale.source_snapshot_checksum = "1".repeat(64); stale.checksum = RequestScript.compute_checksum(stale)
	_assert_error(PlannerScript.build_damage_plan("plan/c9/stale", "operation/c9/stale", stale, snapshot, items), "CONSTRUCTION_DAMAGE_SOURCE_CHECKSUM_MISMATCH", "Planner accepted stale source checksum")
	var unknown_bond := request.duplicate(true); unknown_bond.broken_bond_ids = ["bond/unknown"]; unknown_bond.checksum = RequestScript.compute_checksum(unknown_bond)
	_assert_error(PlannerScript.build_damage_plan("plan/c9/unknown", "operation/c9/unknown", unknown_bond, snapshot, items), "CONSTRUCTION_DAMAGE_BOND_NOT_FOUND", "Planner accepted unknown bond")
	var degraded_only := RequestScript.create(
		"damage/bridge/a/weaken", String(snapshot.construct_id), String(snapshot.checksum), "part/bridge/a/anchor",
		[], ["bond/bridge/a/core-joint"], {}, [], PolicyScript.create(2, ProjectionScript.world_relation(), false)
	)
	var weakened := PlannerScript.build_damage_plan("plan/c9/weaken", "operation/c9/weaken", degraded_only, snapshot, items)
	_assert_ok(weakened, "Bond weakening planning failed")
	_assert(weakened.plan.construct_mutations.size() == 1, "Bond weakening created extra constructs")
	_assert(weakened.plan.item_mutations.is_empty(), "Bond weakening mutated items")
	var weakened_state := ""
	for bond in weakened.plan.construct_mutations[0].after_snapshot.bonds:
		if String(bond.bond_id) == "bond/bridge/a/core-joint": weakened_state = String(bond.state)
	_assert(weakened_state == "DEGRADED", "Bond weakening state missing")
	var destroyed_forbidden := RequestScript.create(
		"damage/bridge/a/destroy-sensor", String(snapshot.construct_id), String(snapshot.checksum), "part/bridge/a/anchor",
		["bond/bridge/a/core-sensor"], [], {"part/bridge/a/sensor": "DESTROYED"}, [], PolicyScript.create(2, ProjectionScript.world_relation(), false)
	)
	_assert_error(PlannerScript.build_damage_plan("plan/c9/destroy-forbidden", "operation/c9/destroy-forbidden", destroyed_forbidden, snapshot, items), "CONSTRUCTION_DAMAGE_DESTROYED_SALVAGE_FORBIDDEN", "Planner salvaged destroyed part against policy")
	var destroyed_allowed := destroyed_forbidden.duplicate(true)
	destroyed_allowed.salvage_policy = PolicyScript.create(2, ProjectionScript.world_relation(), true)
	destroyed_allowed.checksum = RequestScript.compute_checksum(destroyed_allowed)
	var destroyed_plan := PlannerScript.build_damage_plan("plan/c9/destroy-allowed", "operation/c9/destroy-allowed", destroyed_allowed, snapshot, items)
	_assert_ok(destroyed_plan, "Allowed destroyed salvage planning failed")
	_assert(destroyed_plan.salvage_item_ids == ["item/bridge/a/sensor"], "Destroyed salvage item mismatch")

func _test_ghost_record_and_persistence() -> void:
	var snapshot := FixtureScript.snapshot()
	var items := FixtureScript.items()
	var request := FixtureScript.request("a", snapshot)
	var planned := PlannerScript.build_damage_plan("plan/c9/history", "operation/c9/history", request, snapshot, items)
	_assert_ok(planned, "History fixture planning failed")
	var ghost_result := GhostScript.compile(planned.repair_plan, items)
	_assert_ok(ghost_result, "Repair ghost compile failed")
	_assert_ok(GhostScript.validate(ghost_result.ghost), "Repair ghost rejected")
	_assert(bool(ghost_result.ghost.ready), "Complete repair ghost not ready")
	_assert(ghost_result.ghost.part_states.size() == 6, "Repair ghost part count mismatch")
	var missing_items := items.duplicate(true); missing_items.remove_at(missing_items.size() - 1)
	var missing := GhostScript.compile(planned.repair_plan, missing_items)
	_assert_ok(missing, "Missing repair ghost compile failed")
	_assert(not bool(missing.ghost.ready), "Missing repair ghost marked ready")
	_assert(String(missing.ghost.part_states[-1].status) == "MISSING", "Missing repair part not marked")
	var component_checksums: Array = []
	for component in planned.components: component_checksums.append(String(component.checksum))
	var record := RecordScript.create(String(request.damage_id), String(request.checksum), String(planned.plan.checksum), planned.repair_plan, component_checksums, 1)
	_assert_ok(RecordScript.validate(record), "Damage record rejected")
	var history = HistoryScript.new(); _assert_ok(history.setup(), "History setup failed")
	var appended := history.append(record); _assert_ok(appended, "History append failed")
	_assert(not bool(appended.replay), "First history append marked replay")
	_assert(int(history.get_generation()) == 1, "History generation mismatch")
	var replay := history.append(record); _assert_ok(replay, "History replay failed")
	_assert(bool(replay.replay), "History replay not detected")
	_assert(int(history.get_generation()) == 1, "History replay advanced generation")
	var repaired := history.mark_repaired(String(record.damage_id), String(record.checksum), 2); _assert_ok(repaired, "History repair mark failed")
	_assert(String(repaired.record.status) == "REPAIRED", "History repair status mismatch")
	_assert(int(history.get_generation()) == 2, "History repair generation mismatch")
	_assert_error(history.mark_repaired(String(record.damage_id), "0".repeat(64), 3), "CONSTRUCTION_DAMAGE_RECORD_PRECONDITION_MISMATCH", "History accepted stale record checksum")
	var state := history.to_dict(); _assert_ok(HistoryScript.validate_state(state), "History state rejected")
	var restored = HistoryScript.new(); restored.setup(); _assert_ok(restored.load_dict(state), "History state load failed")
	_assert(UtilsScript.canonical_json(restored.to_dict()) == UtilsScript.canonical_json(state), "History roundtrip changed")
	var memory = MemoryStore.new()
	var persistence = PersistenceScript.new(); _assert_ok(persistence.setup(history, memory, "c9-history"), "Persistence setup failed")
	_assert_ok(persistence.save(), "Persistence save failed")
	var history2 = HistoryScript.new(); history2.setup()
	var persistence2 = PersistenceScript.new(); persistence2.setup(history2, memory, "c9-history")
	_assert_ok(persistence2.load(), "Persistence load failed")
	_assert(UtilsScript.canonical_json(history2.to_dict()) == UtilsScript.canonical_json(history.to_dict()), "Persistence roundtrip changed")
	var tampered: Dictionary = memory.states["c9-history"].duplicate(true); tampered.records[0].request_checksum = "0".repeat(64); memory.states["c9-history"] = tampered
	var history3 = HistoryScript.new(); history3.setup()
	var persistence3 = PersistenceScript.new(); persistence3.setup(history3, memory, "c9-history")
	_assert_error(persistence3.load(), "CONSTRUCTION_DAMAGE_RECORD_CHECKSUM_MISMATCH", "Persistence accepted tampered record")
	_assert(history3.list_records().is_empty(), "Rejected persistence mutated history")

func _test_m0_multi_aggregate_translation() -> void:
	var snapshot := FixtureScript.snapshot("m0")
	var request := FixtureScript.request("m0", snapshot)
	var planned := PlannerScript.build_damage_plan("plan/c9/m0", "operation/c9/m0", request, snapshot, FixtureScript.items("m0"))
	_assert_ok(planned, "M0 damage fixture planning failed")
	var item_before := _wrapped_item_graph("before")
	var item_after := _wrapped_item_graph("after")
	var ledger_before := _wrapped_ledger("before")
	var ledger_after := _wrapped_ledger("after")
	var translated := TranslatorScript.build_damage_batch(
		planned.plan, item_before, item_after, ledger_before, ledger_after,
		"authority/construction-c9", 2, 11, 12, 90, {String(snapshot.construct_id): 4}
	)
	_assert_ok(translated, "C9 multi-aggregate M0 translation failed")
	var batch: Dictionary = translated.batch
	_assert_ok(BatchScript.validate(batch), "C9 M0 batch rejected")
	_assert(batch.preconditions.size() == 4, "C9 M0 batch precondition count mismatch")
	_assert(batch.operations.size() == 4, "C9 M0 batch operation count mismatch")
	var aggregate_ids: Array = []
	for operation in batch.operations:
		aggregate_ids.append(String(operation.aggregate_id))
	var sorted_ids := aggregate_ids.duplicate(); sorted_ids.sort()
	_assert(aggregate_ids == sorted_ids, "C9 M0 operations not sorted")
	_assert(aggregate_ids.has(TranslatorScript.ITEM_GRAPH_AGGREGATE_ID), "C9 M0 batch omits Item Graph")
	_assert(aggregate_ids.has(TranslatorScript.LEDGER_AGGREGATE_ID), "C9 M0 batch omits ledger")
	_assert(aggregate_ids.has(TranslatorScript.aggregate_id_for_construct(String(snapshot.construct_id))), "C9 M0 batch omits source construct")
	_assert(aggregate_ids.has(TranslatorScript.aggregate_id_for_construct("construct/bridge/m0/split-arm")), "C9 M0 batch omits split construct")
	_assert(String(batch.batch_id) == TranslatorScript.batch_id_for_plan(planned.plan), "C9 M0 batch ID not deterministic")

func _wrapped_item_graph(marker: String) -> Dictionary:
	var state := {"schema": TranslatorScript.ITEM_GRAPH_STATE_SCHEMA, "item_registry": {"marker": marker}, "container_registry": {"marker": marker}, "checksum": ""}
	state.checksum = _section_checksum(state)
	return state

func _wrapped_ledger(marker: String) -> Dictionary:
	var state := {"schema": TranslatorScript.LEDGER_STATE_SCHEMA, "operation_ledger": {"marker": marker}, "checksum": ""}
	state.checksum = _section_checksum(state)
	return state

func _section_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.checksum = ""
	return UtilsScript.payload_hash(payload)

func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _assert_error(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])
func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty():
		print("C9 damage split repair contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures: push_error(failure)
	print("C9 damage split repair contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
