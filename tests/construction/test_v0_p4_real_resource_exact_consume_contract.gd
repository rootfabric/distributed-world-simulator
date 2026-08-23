extends SceneTree

const FixtureScript = preload("res://tests/construction/fixtures/c3_table_build_fixture.gd")
const BuildPlanScript = preload("res://scripts/construction/build/construction_build_plan.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const StagePlannerScript = preload("res://scripts/construction/build/construction_stage_transaction_planner.gd")
const ItemMutationScript = preload("res://scripts/construction/item_graph/construction_item_mutation.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_partial_consumption_remains_update()
	_test_exact_consumption_is_valid_delete()
	_test_consume_material_delete_contract()
	_finish()


func _test_partial_consumption_remains_update() -> void:
	var plan := _plan_with_sealant_quantity(2, "partial")
	_assert_ok(BuildPlanScript.validate(plan), "Partial-consume BuildPlan must stay valid")
	var planned: Dictionary = StagePlannerScript.build_stage_transaction_plan(
		plan,
		2,
		"operation/v0-p4/exact-consume/partial"
	)
	_assert_ok(planned, "Partial-consume stage planning failed")
	if not bool(planned.get("success", false)):
		return
	var mutation := _find_material_mutation(
		Dictionary(planned.get("transaction_plan", {})),
		FixtureScript.SEALANT_ID
	)
	_assert(not mutation.is_empty(), "Partial-consume material mutation missing")
	if mutation.is_empty():
		return
	_assert(
		String(mutation.get("operation_kind", "")) == ItemMutationScript.OP_UPDATE,
		"Partial consume must remain UPDATE"
	)
	_assert(
		int(Dictionary(mutation.get("after_projection", {})).get("quantity", -1)) == 1,
		"Partial consume must leave quantity 1"
	)


func _test_exact_consumption_is_valid_delete() -> void:
	var plan := _plan_with_sealant_quantity(1, "exact")
	var validation: Dictionary = BuildPlanScript.validate(plan)
	_assert_ok(
		validation,
		"Exact exhaustion must be a valid BuildPlan; only material shortfall may reject"
	)

	var planned: Dictionary = StagePlannerScript.build_stage_transaction_plan(
		plan,
		2,
		"operation/v0-p4/exact-consume/exact"
	)
	_assert_ok(planned, "Exact-consume stage planning must produce a valid transaction")
	if not bool(planned.get("success", false)):
		return
	var mutation := _find_material_mutation(
		Dictionary(planned.get("transaction_plan", {})),
		FixtureScript.SEALANT_ID
	)
	_assert(not mutation.is_empty(), "Exact-consume material mutation missing")
	if mutation.is_empty():
		return
	_assert(
		String(mutation.get("operation_kind", "")) == ItemMutationScript.OP_DELETE,
		"Exact consume must DELETE the exhausted stack instead of UPDATE quantity to zero"
	)
	_assert(
		Dictionary(mutation.get("after_projection", {})).is_empty(),
		"Exact-consume DELETE must have an empty after projection"
	)


func _test_consume_material_delete_contract() -> void:
	var source: Dictionary = _source_projection(FixtureScript.SEALANT_ID, 1)
	_assert(not source.is_empty(), "Exact-consume source projection fixture missing")
	if source.is_empty():
		return
	var mutation := ItemMutationScript.create(
		ItemMutationScript.OP_DELETE,
		ItemMutationScript.PURPOSE_CONSUME_MATERIAL,
		FixtureScript.SEALANT_ID,
		source,
		{}
	)
	_assert_ok(
		ItemMutationScript.validate(mutation),
		"Bounded material exhaustion DELETE must be a valid Construction item mutation"
	)


func _plan_with_sealant_quantity(quantity: int, suffix: String) -> Dictionary:
	var base: Dictionary = FixtureScript.build_plan()
	var sources: Array = FixtureScript.source_projections()
	for index in range(sources.size()):
		var source: Dictionary = Dictionary(sources[index]).duplicate(true)
		if String(source.get("item_instance_id", "")) != FixtureScript.SEALANT_ID:
			continue
		source["quantity"] = quantity
		sources[index] = source
		break
	return BuildPlanScript.create(
		"build-plan/v0-p4/exact-consume/%s" % suffix,
		"V0 P4 exact-consume contract",
		Dictionary(base.get("ghost_relation", {})),
		Dictionary(base.get("target_snapshot", {})),
		sources,
		Array(base.get("stages", []))
	)


func _source_projection(item_id: String, quantity: int) -> Dictionary:
	for raw in FixtureScript.source_projections():
		var source: Dictionary = raw
		if String(source.get("item_instance_id", "")) != item_id:
			continue
		return ProjectionScript.create(
			String(source.get("item_instance_id", "")),
			String(source.get("definition_id", "")),
			String(source.get("display_name", "")),
			quantity,
			Dictionary(source.get("relation", {})),
			Dictionary(source.get("components", {})),
			int(source.get("revision", 0))
		)
	return {}


func _find_material_mutation(transaction_plan: Dictionary, item_id: String) -> Dictionary:
	for raw in transaction_plan.get("item_mutations", []):
		if not raw is Dictionary:
			continue
		var mutation: Dictionary = raw
		if (
			String(mutation.get("purpose", "")) == ItemMutationScript.PURPOSE_CONSUME_MATERIAL
			and String(mutation.get("item_instance_id", "")) == item_id
		):
			return mutation.duplicate(true)
	return {}


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("V0-P4 exact-consume contract: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print(
		"V0-P4 exact-consume contract: FAIL (%d failures, %d assertions)"
		% [failures.size(), assertions]
	)
	quit(1)
