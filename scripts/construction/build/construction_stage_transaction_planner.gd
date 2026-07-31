extends RefCounted

const BuildPlanScript = preload("res://scripts/construction/build/construction_build_plan.gd")
const StageScript = preload("res://scripts/construction/build/construction_build_stage.gd")
const SnapshotBuilderScript = preload("res://scripts/construction/build/construction_stage_snapshot_builder.gd")
const BasePlannerScript = preload("res://scripts/construction/item_graph/construction_item_transaction_planner.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const ItemMutationScript = preload("res://scripts/construction/item_graph/construction_item_mutation.gd")
const ConstructMutationScript = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const TransactionPlanScript = preload("res://scripts/construction/item_graph/construction_item_transaction_plan.gd")


static func build_stage_transaction_plan(
	build_plan: Dictionary,
	stage_index: int,
	operation_id: String
) -> Dictionary:
	var plan_validation: Dictionary = BuildPlanScript.validate(build_plan)
	if not bool(plan_validation.get("success", false)):
		return plan_validation
	if stage_index < 0 or stage_index >= build_plan["stages"].size():
		return _failure("INVALID_CONSTRUCTION_BUILD_STAGE_INDEX")
	if not operation_id.begins_with("operation/") or operation_id.length() <= 10 or operation_id != operation_id.strip_edges():
		return _failure("INVALID_CONSTRUCTION_BUILD_STAGE_OPERATION_ID")
	var stage: Dictionary = build_plan["stages"][stage_index]
	var source_map: Dictionary = BuildPlanScript.source_projection_map(build_plan)
	var after_result: Dictionary = SnapshotBuilderScript.build_for_stage(build_plan, stage_index)
	if not bool(after_result.get("success", false)):
		return after_result
	var after_snapshot: Dictionary = after_result["snapshot"]
	var before_snapshot: Dictionary = {}
	if stage_index > 0:
		var before_result: Dictionary = SnapshotBuilderScript.build_for_stage(build_plan, stage_index - 1)
		if not bool(before_result.get("success", false)):
			return before_result
		before_snapshot = before_result["snapshot"]
	var mutations: Array = []
	if stage_index == 0:
		var root: Dictionary = BasePlannerScript.create_root_projection(
			String(build_plan["root_item_instance_id"]),
			String(build_plan["construct_id"]),
			String(build_plan["display_name"]),
			Dictionary(build_plan["ghost_relation"])
		)
		var root_validation: Dictionary = ProjectionScript.validate(root)
		if not bool(root_validation.get("success", false)):
			return root_validation
		mutations.append(ItemMutationScript.create(
			ItemMutationScript.OP_CREATE,
			ItemMutationScript.PURPOSE_CREATE_ROOT,
			String(build_plan["root_item_instance_id"]),
			{},
			root
		))
	var previous_part_ids: Dictionary = {}
	if stage_index > 0:
		previous_part_ids = _set_from_array(build_plan["stages"][stage_index - 1]["included_part_ids"])
	var part_records: Dictionary = {}
	for part in build_plan["target_snapshot"]["parts"]:
		part_records[String(part["part_id"])] = part
	for part_id in stage["included_part_ids"]:
		if previous_part_ids.has(String(part_id)):
			continue
		var part: Dictionary = part_records[String(part_id)]
		var item_id: String = String(part["item_instance_id"])
		if not source_map.has(item_id):
			return _failure("CONSTRUCTION_BUILD_STAGE_PART_SOURCE_MISSING")
		var before: Dictionary = source_map[item_id].duplicate(true)
		var after: Dictionary = before.duplicate(true)
		after["relation"] = ProjectionScript.attachment_relation(
			String(build_plan["construct_id"]),
			String(build_plan["root_item_instance_id"]),
			String(part_id)
		)
		after["revision"] = int(before["revision"]) + 1
		mutations.append(ItemMutationScript.create(
			ItemMutationScript.OP_UPDATE,
			ItemMutationScript.PURPOSE_ATTACH_PART,
			item_id,
			before,
			after
		))
	for allocation in stage["material_allocations"]:
		var item_id: String = String(allocation["item_instance_id"])
		if not source_map.has(item_id):
			return _failure("CONSTRUCTION_BUILD_STAGE_MATERIAL_SOURCE_MISSING")
		var initial: Dictionary = source_map[item_id]
		var consumed_before: int = 0
		var previous_mutations: int = 0
		for previous_index in range(stage_index):
			var quantity: int = StageScript.allocation_quantity_for(build_plan["stages"][previous_index], item_id)
			consumed_before += quantity
			if quantity > 0:
				previous_mutations += 1
		var before: Dictionary = initial.duplicate(true)
		before["quantity"] = int(initial["quantity"]) - consumed_before
		before["revision"] = int(initial["revision"]) + previous_mutations
		var after: Dictionary = before.duplicate(true)
		after["quantity"] = int(before["quantity"]) - int(allocation["quantity"])
		after["revision"] = int(before["revision"]) + 1
		mutations.append(ItemMutationScript.create(
			ItemMutationScript.OP_UPDATE,
			ItemMutationScript.PURPOSE_CONSUME_MATERIAL,
			item_id,
			before,
			after
		))
	if mutations.is_empty():
		return _failure("CONSTRUCTION_BUILD_STAGE_HAS_NO_ITEM_MUTATIONS")
	var construct_mutation: Dictionary = ConstructMutationScript.create(
		ConstructMutationScript.OP_CREATE if stage_index == 0 else ConstructMutationScript.OP_UPDATE,
		String(build_plan["construct_id"]),
		before_snapshot,
		after_snapshot
	)
	var transaction_plan_id: String = "plan/build-stage/%s/%d/%s" % [
		String(build_plan["build_plan_id"]).trim_prefix("build-plan/"),
		stage_index,
		operation_id.trim_prefix("operation/").replace("/", ":"),
	]
	var transaction_plan: Dictionary = TransactionPlanScript.create(
		transaction_plan_id,
		operation_id,
		TransactionPlanScript.COMMAND_ADVANCE_STAGE,
		construct_mutation,
		mutations
	)
	var validation: Dictionary = TransactionPlanScript.validate(transaction_plan)
	if not bool(validation.get("success", false)):
		return validation
	return _success({
		"transaction_plan": transaction_plan,
		"stage_id": String(stage["stage_id"]),
		"stage_index": stage_index,
		"after_snapshot": after_snapshot,
	})


static func _set_from_array(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for value in values:
		result[String(value)] = true
	return result


static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
