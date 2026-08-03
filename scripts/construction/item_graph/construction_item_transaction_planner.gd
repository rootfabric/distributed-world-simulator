extends RefCounted

const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const ItemMutationScript = preload("res://scripts/construction/item_graph/construction_item_mutation.gd")
const ConstructMutationScript = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const PlanScript = preload("res://scripts/construction/item_graph/construction_item_transaction_plan.gd")

static func create_root_projection(
	root_item_instance_id: String,
	construct_id: String,
	display_name: String,
	relation: Dictionary = {}
) -> Dictionary:
	var resolved_relation: Dictionary = relation if not relation.is_empty() else ProjectionScript.world_relation()
	return ProjectionScript.create(
		root_item_instance_id,
		"construct_root",
		display_name,
		1,
		resolved_relation,
		{
			"construction_root": {
				"schema": "planet_simulator.construction_root_component.v1",
				"construct_id": construct_id,
			}
		},
		0
	)

static func build_assembly_plan(
	plan_id: String,
	operation_id: String,
	construct_snapshot: Dictionary,
	root_item_projection: Dictionary,
	part_source_projections: Array,
	material_consumptions: Dictionary = {}
) -> Dictionary:
	var snapshot_validation: Dictionary = SnapshotScript.validate(construct_snapshot)
	if not bool(snapshot_validation.get("success", false)):
		return snapshot_validation
	var root_validation: Dictionary = ProjectionScript.validate(root_item_projection)
	if not bool(root_validation.get("success", false)):
		return root_validation
	var construct_id: String = String(construct_snapshot["construct_id"])
	var root_item_id: String = String(construct_snapshot["root_item_instance_id"])
	if String(root_item_projection["item_instance_id"]) != root_item_id:
		return _failure("ASSEMBLY_ROOT_ITEM_ID_MISMATCH")
	var root_component = root_item_projection["components"].get("construction_root", {})
	if not root_component is Dictionary or String(Dictionary(root_component).get("construct_id", "")) != construct_id:
		return _failure("ASSEMBLY_ROOT_COMPONENT_MISMATCH")
	var sources_result: Dictionary = _projection_map(part_source_projections)
	if not bool(sources_result.get("success", false)):
		return sources_result
	var sources: Dictionary = sources_result["projections"]
	if sources.has(root_item_id):
		return _failure("ASSEMBLY_ROOT_ALREADY_EXISTS_IN_SOURCE_ITEMS")
	var mutations: Array = [ItemMutationScript.create(
		ItemMutationScript.OP_CREATE,
		ItemMutationScript.PURPOSE_CREATE_ROOT,
		root_item_id,
		{},
		root_item_projection
	)]
	for part in construct_snapshot["parts"]:
		var item_id: String = String(part["item_instance_id"])
		if not sources.has(item_id):
			return _failure("ASSEMBLY_PART_SOURCE_ITEM_MISSING", {"item_instance_id": item_id})
		if material_consumptions.has(item_id):
			return _failure("ASSEMBLY_PART_CANNOT_ALSO_BE_CONSUMABLE", {"item_instance_id": item_id})
		var before: Dictionary = sources[item_id]
		var after: Dictionary = before.duplicate(true)
		after["relation"] = ProjectionScript.attachment_relation(construct_id, root_item_id, String(part["part_id"]))
		after["revision"] = int(before["revision"]) + 1
		mutations.append(ItemMutationScript.create(
			ItemMutationScript.OP_UPDATE,
			ItemMutationScript.PURPOSE_ATTACH_PART,
			item_id,
			before,
			after
		))
	var consumable_ids: Array = material_consumptions.keys()
	consumable_ids.sort()
	for raw_item_id in consumable_ids:
		var item_id: String = String(raw_item_id)
		if not sources.has(item_id):
			return _failure("ASSEMBLY_CONSUMABLE_SOURCE_ITEM_MISSING", {"item_instance_id": item_id})
		var amount_value = material_consumptions[item_id]
		if typeof(amount_value) != TYPE_INT or int(amount_value) < 1:
			return _failure("INVALID_ASSEMBLY_CONSUMPTION_QUANTITY", {"item_instance_id": item_id})
		var before: Dictionary = sources[item_id]
		if int(before["quantity"]) <= int(amount_value):
			return _failure("ASSEMBLY_CONSUMPTION_WOULD_EXHAUST_STACK", {"item_instance_id": item_id})
		var after: Dictionary = before.duplicate(true)
		after["quantity"] = int(before["quantity"]) - int(amount_value)
		after["revision"] = int(before["revision"]) + 1
		mutations.append(ItemMutationScript.create(
			ItemMutationScript.OP_UPDATE,
			ItemMutationScript.PURPOSE_CONSUME_MATERIAL,
			item_id,
			before,
			after
		))
	var construct_mutation: Dictionary = ConstructMutationScript.create(
		ConstructMutationScript.OP_CREATE,
		construct_id,
		{},
		construct_snapshot
	)
	var plan: Dictionary = PlanScript.create(
		plan_id,
		operation_id,
		PlanScript.COMMAND_ASSEMBLE,
		construct_mutation,
		mutations
	)
	var validation: Dictionary = PlanScript.validate(plan)
	if not bool(validation.get("success", false)):
		return validation
	return _success({"plan": plan})

static func build_deconstruction_plan(
	plan_id: String,
	operation_id: String,
	construct_snapshot: Dictionary,
	root_item_projection: Dictionary,
	part_attached_projections: Array,
	destination_relation: Dictionary
) -> Dictionary:
	var snapshot_validation: Dictionary = SnapshotScript.validate(construct_snapshot)
	if not bool(snapshot_validation.get("success", false)):
		return snapshot_validation
	var root_validation: Dictionary = ProjectionScript.validate(root_item_projection)
	if not bool(root_validation.get("success", false)):
		return root_validation
	var destination_validation: Dictionary = ProjectionScript.validate_relation(destination_relation)
	if not bool(destination_validation.get("success", false)):
		return destination_validation
	if not [ProjectionScript.CONTAINER, ProjectionScript.WORLD].has(String(destination_relation.get("kind", ""))):
		return _failure("INVALID_DECONSTRUCTION_DESTINATION")
	var construct_id: String = String(construct_snapshot["construct_id"])
	var root_item_id: String = String(construct_snapshot["root_item_instance_id"])
	if String(root_item_projection["item_instance_id"]) != root_item_id:
		return _failure("DECONSTRUCTION_ROOT_ITEM_ID_MISMATCH")
	var sources_result: Dictionary = _projection_map(part_attached_projections)
	if not bool(sources_result.get("success", false)):
		return sources_result
	var sources: Dictionary = sources_result["projections"]
	var mutations: Array = [ItemMutationScript.create(
		ItemMutationScript.OP_DELETE,
		ItemMutationScript.PURPOSE_DESTROY_ROOT,
		root_item_id,
		root_item_projection,
		{}
	)]
	for part in construct_snapshot["parts"]:
		var item_id: String = String(part["item_instance_id"])
		if not sources.has(item_id):
			return _failure("DECONSTRUCTION_PART_ITEM_MISSING", {"item_instance_id": item_id})
		var before: Dictionary = sources[item_id]
		var relation: Dictionary = before["relation"]
		if (
			String(relation.get("kind", "")) != ProjectionScript.ATTACHMENT
			or String(relation.get("assembly_id", "")) != construct_id
			or String(relation.get("parent_item_id", "")) != root_item_id
			or String(relation.get("socket_id", "")) != String(part["part_id"])
		):
			return _failure("DECONSTRUCTION_PART_BINDING_MISMATCH", {"item_instance_id": item_id})
		var after: Dictionary = before.duplicate(true)
		after["relation"] = destination_relation.duplicate(true)
		after["revision"] = int(before["revision"]) + 1
		mutations.append(ItemMutationScript.create(
			ItemMutationScript.OP_UPDATE,
			ItemMutationScript.PURPOSE_DETACH_PART,
			item_id,
			before,
			after
		))
	var construct_mutation: Dictionary = ConstructMutationScript.create(
		ConstructMutationScript.OP_DELETE,
		construct_id,
		construct_snapshot,
		{}
	)
	var plan: Dictionary = PlanScript.create(
		plan_id,
		operation_id,
		PlanScript.COMMAND_DECONSTRUCT,
		construct_mutation,
		mutations
	)
	var validation: Dictionary = PlanScript.validate(plan)
	if not bool(validation.get("success", false)):
		return validation
	return _success({"plan": plan})

static func _projection_map(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for value in values:
		if typeof(value) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_ITEM_PROJECTION_COLLECTION")
		var validation: Dictionary = ProjectionScript.validate(value)
		if not bool(validation.get("success", false)):
			return validation
		var item_id: String = String(value["item_instance_id"])
		if result.has(item_id):
			return _failure("DUPLICATE_CONSTRUCTION_ITEM_PROJECTION", {"item_instance_id": item_id})
		result[item_id] = value.duplicate(true)
	return _success({"projections": result})

static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": false, "error_code": code, "message": code}
	for key in details:
		result[key] = details[key]
	return result
