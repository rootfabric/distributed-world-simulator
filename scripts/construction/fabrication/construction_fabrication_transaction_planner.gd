extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const ItemMutationScript = preload("res://scripts/construction/item_graph/construction_item_mutation.gd")
const ConstructMutationScript = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const PlanScript = preload("res://scripts/construction/item_graph/construction_item_transaction_plan.gd")
const RecipeScript = preload("res://scripts/construction/fabrication/construction_fabrication_recipe.gd")
const JobScript = preload("res://scripts/construction/fabrication/construction_fabrication_job.gd")

static func build_reservation_plan(plan_id: String, operation_id: String, machine_snapshot: Dictionary, job: Dictionary, recipe: Dictionary, input_projections: Array, input_container_id: String) -> Dictionary:
	var checked := _validate_context(machine_snapshot, job, recipe)
	if not bool(checked.get("success", false)): return checked
	var projections := _projection_map(input_projections)
	if not bool(projections.get("success", false)): return projections
	var mutations: Array = []
	for binding in job["input_bindings"]:
		var item_id := String(binding["item_instance_id"])
		if not projections["map"].has(item_id): return _failure("FABRICATION_INPUT_PROJECTION_MISSING")
		var before: Dictionary = projections["map"][item_id]
		if String(before["definition_id"]) != String(binding["definition_id"]): return _failure("FABRICATION_INPUT_DEFINITION_MISMATCH")
		if int(before["quantity"]) < int(binding["quantity"]): return _failure("FABRICATION_INPUT_QUANTITY_INSUFFICIENT")
		if String(before["relation"].get("kind", "")) != ProjectionScript.CONTAINER: return _failure("FABRICATION_INPUT_NOT_IN_CONTAINER")
		if UtilsScript.canonical_json(before["components"]) != UtilsScript.canonical_json(binding["components"]): return _failure("FABRICATION_INPUT_COMPONENTS_MISMATCH")
		var after := before.duplicate(true)
		after["relation"] = ProjectionScript.container_relation(input_container_id)
		after["revision"] = int(before["revision"]) + 1
		mutations.append(ItemMutationScript.create(ItemMutationScript.OP_UPDATE, ItemMutationScript.PURPOSE_TRANSFER_FABRICATION_INPUT, item_id, before, after))
	var after_snapshot := _snapshot_with_runtime(machine_snapshot, {
		"active_job_id": String(job["job_id"]),
		"job_status": "RESERVED",
		"recipe_id": String(recipe["recipe_id"]),
		"recipe_checksum": String(recipe["checksum"]),
		"input_item_ids": _binding_ids(job["input_bindings"], "item_instance_id"),
		"output_item_ids": _binding_ids(job["output_bindings"], "item_instance_id"),
	})
	return _create_plan(plan_id, operation_id, PlanScript.COMMAND_FABRICATION_RESERVE, machine_snapshot, after_snapshot, mutations)

static func build_completion_plan(plan_id: String, operation_id: String, machine_snapshot: Dictionary, job: Dictionary, recipe: Dictionary, reserved_input_projections: Array, output_container_id: String) -> Dictionary:
	var checked := _validate_context(machine_snapshot, job, recipe)
	if not bool(checked.get("success", false)): return checked
	var runtime: Dictionary = machine_snapshot["compiled_facets"].get("fabrication_runtime", {})
	if String(runtime.get("active_job_id", "")) != String(job["job_id"]): return _failure("FABRICATION_MACHINE_ACTIVE_JOB_MISMATCH")
	var projections := _projection_map(reserved_input_projections)
	if not bool(projections.get("success", false)): return projections
	var mutations: Array = []
	for binding in job["input_bindings"]:
		var item_id := String(binding["item_instance_id"])
		if not projections["map"].has(item_id): return _failure("FABRICATION_RESERVED_INPUT_MISSING")
		var before: Dictionary = projections["map"][item_id]
		if int(before["quantity"]) < int(binding["quantity"]): return _failure("FABRICATION_RESERVED_INPUT_QUANTITY_INSUFFICIENT")
		if int(before["quantity"]) == int(binding["quantity"]):
			mutations.append(ItemMutationScript.create(ItemMutationScript.OP_DELETE, ItemMutationScript.PURPOSE_CONSUME_FABRICATION_INPUT, item_id, before, {}))
		else:
			var after := before.duplicate(true)
			after["quantity"] = int(before["quantity"]) - int(binding["quantity"])
			after["revision"] = int(before["revision"]) + 1
			mutations.append(ItemMutationScript.create(ItemMutationScript.OP_UPDATE, ItemMutationScript.PURPOSE_CONSUME_FABRICATION_INPUT, item_id, before, after))
	var products_by_key: Dictionary = {}
	for product in recipe["output_products"]: products_by_key[String(product["product_key"])] = product
	for binding in job["output_bindings"]:
		var key := String(binding["product_key"])
		if not products_by_key.has(key): return _failure("FABRICATION_OUTPUT_BINDING_UNKNOWN_PRODUCT")
		var product: Dictionary = products_by_key[key]
		var components: Dictionary = Dictionary(product["components"]).duplicate(true)
		components["fabrication_origin"] = {"schema": "planet_simulator.fabrication_origin.v1", "job_id": String(job["job_id"]), "recipe_id": String(recipe["recipe_id"]), "recipe_version": int(recipe["recipe_version"]), "recipe_checksum": String(recipe["checksum"]), "machine_construct_id": String(machine_snapshot["construct_id"])}
		var projection := ProjectionScript.create(String(binding["item_instance_id"]), String(product["definition_id"]), String(product["display_name"]), int(product["quantity"]), ProjectionScript.container_relation(output_container_id), components, 0)
		mutations.append(ItemMutationScript.create(ItemMutationScript.OP_CREATE, ItemMutationScript.PURPOSE_CREATE_FABRICATED_ITEM, String(binding["item_instance_id"]), {}, projection))
	var after_snapshot := _snapshot_with_runtime(machine_snapshot, {
		"active_job_id": "",
		"job_status": "COMPLETED",
		"last_completed_job_id": String(job["job_id"]),
		"recipe_id": String(recipe["recipe_id"]),
		"recipe_checksum": String(recipe["checksum"]),
		"output_item_ids": _binding_ids(job["output_bindings"], "item_instance_id"),
	})
	return _create_plan(plan_id, operation_id, PlanScript.COMMAND_FABRICATION_COMPLETE, machine_snapshot, after_snapshot, mutations)

static func build_release_plan(plan_id: String, operation_id: String, machine_snapshot: Dictionary, job: Dictionary, reserved_input_projections: Array) -> Dictionary:
	var checked := SnapshotScript.validate(machine_snapshot)
	if not bool(checked.get("success", false)): return checked
	checked = JobScript.validate(job)
	if not bool(checked.get("success", false)): return checked
	var projections := _projection_map(reserved_input_projections)
	if not bool(projections.get("success", false)): return projections
	var mutations: Array = []
	for binding in job["input_bindings"]:
		var item_id := String(binding["item_instance_id"])
		if not projections["map"].has(item_id): return _failure("FABRICATION_RESERVED_INPUT_MISSING")
		var before: Dictionary = projections["map"][item_id]
		var after := before.duplicate(true)
		after["relation"] = Dictionary(binding["original_relation"]).duplicate(true)
		after["revision"] = int(before["revision"]) + 1
		mutations.append(ItemMutationScript.create(ItemMutationScript.OP_UPDATE, ItemMutationScript.PURPOSE_TRANSFER_FABRICATION_INPUT, item_id, before, after))
	var after_snapshot := _snapshot_with_runtime(machine_snapshot, {"active_job_id": "", "job_status": "CANCELLED", "last_cancelled_job_id": String(job["job_id"])})
	return _create_plan(plan_id, operation_id, PlanScript.COMMAND_FABRICATION_RELEASE, machine_snapshot, after_snapshot, mutations)

static func _create_plan(plan_id: String, operation_id: String, command: String, before_snapshot: Dictionary, after_snapshot: Dictionary, mutations: Array) -> Dictionary:
	var construct_mutation := ConstructMutationScript.create(ConstructMutationScript.OP_UPDATE, String(before_snapshot["construct_id"]), before_snapshot, after_snapshot)
	var plan := PlanScript.create(plan_id, operation_id, command, construct_mutation, mutations)
	var checked := PlanScript.validate(plan)
	return _success({"plan": plan}) if bool(checked.get("success", false)) else checked
static func _snapshot_with_runtime(snapshot: Dictionary, runtime: Dictionary) -> Dictionary:
	var facets: Dictionary = Dictionary(snapshot["compiled_facets"]).duplicate(true)
	facets["fabrication_runtime"] = runtime.duplicate(true)
	return SnapshotScript.create(String(snapshot["construct_id"]), String(snapshot["root_item_instance_id"]), int(snapshot["state_revision"]) + 1, String(snapshot["build_state"]), Array(snapshot["parts"]).duplicate(true), Array(snapshot["bonds"]).duplicate(true), facets)
static func _validate_context(snapshot: Dictionary, job: Dictionary, recipe: Dictionary) -> Dictionary:
	var checked := SnapshotScript.validate(snapshot); if not bool(checked.get("success", false)): return checked
	checked = JobScript.validate(job); if not bool(checked.get("success", false)): return checked
	checked = RecipeScript.validate(recipe); if not bool(checked.get("success", false)): return checked
	if String(job["machine_construct_id"]) != String(snapshot["construct_id"]): return _failure("FABRICATION_JOB_MACHINE_MISMATCH")
	if String(job["recipe_checksum"]) != String(recipe["checksum"]): return _failure("FABRICATION_JOB_RECIPE_MISMATCH")
	return _success()
static func _projection_map(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw in values:
		if typeof(raw) != TYPE_DICTIONARY: return _failure("INVALID_FABRICATION_ITEM_PROJECTION")
		var checked := ProjectionScript.validate(raw); if not bool(checked.get("success", false)): return checked
		var id := String(raw["item_instance_id"]); if result.has(id): return _failure("DUPLICATE_FABRICATION_ITEM_PROJECTION")
		result[id] = Dictionary(raw).duplicate(true)
	return _success({"map": result})
static func _binding_ids(values: Array, field: String) -> Array:
	var result: Array = []
	for row in values:
		result.append(String(row[field]))
	result.sort()
	return result
static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}
