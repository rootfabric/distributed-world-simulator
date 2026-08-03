extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const RecipeScript = preload("res://scripts/construction/fabrication/construction_fabrication_recipe.gd")
const ProfileScript = preload("res://scripts/construction/fabrication/construction_fabrication_machine_profile.gd")
const JobScript = preload("res://scripts/construction/fabrication/construction_fabrication_job.gd")
const PlannerScript = preload("res://scripts/construction/fabrication/construction_fabrication_transaction_planner.gd")

var _adapter
var _catalog
var _queue
var _configured := false

func setup(item_graph_adapter, catalog, queue_store) -> Dictionary:
	if item_graph_adapter == null or not item_graph_adapter.has_method("apply_plan") or not item_graph_adapter.has_method("get_item_projection") or not item_graph_adapter.has_method("get_construct_snapshot"): return _failure("CONSTRUCTION_FABRICATION_ITEM_GRAPH_ADAPTER_REQUIRED")
	if catalog == null or not catalog.has_method("get_recipe") or not catalog.has_method("publish"): return _failure("CONSTRUCTION_FABRICATION_CATALOG_REQUIRED")
	if queue_store == null or not queue_store.has_method("enqueue") or not queue_store.has_method("replace_job"): return _failure("CONSTRUCTION_FABRICATION_QUEUE_REQUIRED")
	_adapter = item_graph_adapter; _catalog = catalog; _queue = queue_store; _configured = true; return _success()

func enqueue_job(job_id: String, recipe_id: String, recipe_version: int, machine_profile: Dictionary, available_inputs: Array, output_item_ids: Dictionary, priority: int = 100) -> Dictionary:
	if not _configured: return _failure("CONSTRUCTION_FABRICATION_PROCESS_NOT_CONFIGURED")
	var profile_checked := ProfileScript.validate(machine_profile); if not bool(profile_checked.get("success", false)): return profile_checked
	var recipe: Dictionary = _catalog.get_recipe(recipe_id, recipe_version)
	if recipe.is_empty(): return _failure("CONSTRUCTION_FABRICATION_RECIPE_NOT_FOUND")
	if not Array(machine_profile["supported_recipe_ids"]).has(recipe_id): return _failure("CONSTRUCTION_FABRICATION_RECIPE_NOT_SUPPORTED")
	var allocated := _allocate_inputs(recipe, available_inputs)
	if not bool(allocated.get("success", false)): return allocated
	var outputs: Array = []
	for product in recipe["output_products"]:
		var key := String(product["product_key"])
		if not output_item_ids.has(key) or not String(output_item_ids[key]).begins_with("item/"): return _failure("CONSTRUCTION_FABRICATION_OUTPUT_ITEM_ID_REQUIRED")
		outputs.append({"product_key": key, "item_instance_id": String(output_item_ids[key])})
	if output_item_ids.size() != outputs.size(): return _failure("CONSTRUCTION_FABRICATION_UNKNOWN_OUTPUT_BINDING")
	var job := JobScript.create(job_id, recipe, machine_profile, priority, allocated["bindings"], outputs)
	var checked := JobScript.validate(job); if not bool(checked.get("success", false)): return checked
	return _queue.enqueue(job)

func reserve_job(job_id: String, machine_profile: Dictionary, failure_mode: String = "") -> Dictionary:
	var ready := _ready_job(job_id, machine_profile, ["QUEUED", "BLOCKED"])
	if not bool(ready.get("success", false)): return ready
	if String(machine_profile["status"]) != "ONLINE": return _block(job_id, "FABRICATION_MACHINE_NOT_ONLINE")
	var job: Dictionary = ready["job"]; var recipe: Dictionary = ready["recipe"]
	var snapshot: Dictionary = _adapter.get_construct_snapshot(String(job["machine_construct_id"]))
	if snapshot.is_empty(): return _failure("CONSTRUCTION_FABRICATION_MACHINE_SNAPSHOT_NOT_FOUND")
	var projections: Array = []
	for binding in job["input_bindings"]:
		var projection: Dictionary = _adapter.get_item_projection(String(binding["item_instance_id"]))
		if projection.is_empty(): return _failure("CONSTRUCTION_FABRICATION_INPUT_NOT_FOUND")
		projections.append(projection)
	var operation_id := _operation_id(job_id, "reserve")
	var planned := PlannerScript.build_reservation_plan(_plan_id(job_id, "reserve"), operation_id, snapshot, job, recipe, projections, String(machine_profile["input_container_id"]))
	if not bool(planned.get("success", false)): return planned
	var applied: Dictionary = _adapter.apply_plan(planned["plan"], failure_mode)
	if not bool(applied.get("success", false)):
		if String(applied.get("status", "")) == "RETRYABLE": return applied
		return applied
	var current: Dictionary = _queue.get_job(job_id)
	var next := JobScript.with_updates(current, {"status": "RESERVED", "reservation_operation_id": operation_id, "machine_profile_checksum": String(machine_profile["checksum"]), "last_error_code": ""})
	return _queue.replace_job(String(current["checksum"]), next)

func advance_job(job_id: String, machine_profile: Dictionary, work_units: int, operation_id: String) -> Dictionary:
	var ready := _ready_job(job_id, machine_profile, ["RESERVED", "PROCESSING", "BLOCKED"])
	if not bool(ready.get("success", false)): return ready
	if String(machine_profile["status"]) == "OFFLINE": return _block(job_id, "FABRICATION_MACHINE_OFFLINE")
	return _queue.advance(job_id, work_units, operation_id)

func complete_job(job_id: String, machine_profile: Dictionary, failure_mode: String = "") -> Dictionary:
	var ready := _ready_job(job_id, machine_profile, ["PROCESSING", "BLOCKED"])
	if not bool(ready.get("success", false)): return ready
	if String(machine_profile["status"]) == "OFFLINE": return _block(job_id, "FABRICATION_MACHINE_OFFLINE")
	var job: Dictionary = ready["job"]
	if int(job["work_completed"]) < int(job["work_required"]): return _failure("CONSTRUCTION_FABRICATION_WORK_INCOMPLETE")
	var snapshot: Dictionary = _adapter.get_construct_snapshot(String(job["machine_construct_id"]))
	if snapshot.is_empty(): return _failure("CONSTRUCTION_FABRICATION_MACHINE_SNAPSHOT_NOT_FOUND")
	var projections: Array = []
	for binding in job["input_bindings"]:
		var projection: Dictionary = _adapter.get_item_projection(String(binding["item_instance_id"]))
		if projection.is_empty(): return _failure("CONSTRUCTION_FABRICATION_RESERVED_INPUT_NOT_FOUND")
		projections.append(projection)
	var operation_id := _operation_id(job_id, "complete")
	var planned := PlannerScript.build_completion_plan(_plan_id(job_id, "complete"), operation_id, snapshot, job, ready["recipe"], projections, String(machine_profile["output_container_id"]))
	if not bool(planned.get("success", false)): return planned
	var applied: Dictionary = _adapter.apply_plan(planned["plan"], failure_mode)
	if not bool(applied.get("success", false)): return applied
	var current: Dictionary = _queue.get_job(job_id)
	var next := JobScript.with_updates(current, {"status": "COMPLETED", "completion_operation_id": operation_id, "last_error_code": ""})
	var stored: Dictionary = _queue.replace_job(String(current["checksum"]), next)
	if bool(stored.get("success", false)): stored["fabrication_result"] = applied
	return stored

func cancel_job(job_id: String, machine_profile: Dictionary, failure_mode: String = "") -> Dictionary:
	var ready := _ready_job(job_id, machine_profile, ["QUEUED", "RESERVED", "PROCESSING", "BLOCKED"])
	if not bool(ready.get("success", false)): return ready
	var job: Dictionary = ready["job"]
	if String(job["status"]) == "QUEUED":
		var next := JobScript.with_updates(job, {"status": "CANCELLED", "cancellation_operation_id": _operation_id(job_id, "cancel"), "last_error_code": ""})
		return _queue.replace_job(String(job["checksum"]), next)
	var snapshot: Dictionary = _adapter.get_construct_snapshot(String(job["machine_construct_id"]))
	var projections: Array = []
	for binding in job["input_bindings"]:
		var projection: Dictionary = _adapter.get_item_projection(String(binding["item_instance_id"]))
		if projection.is_empty(): return _failure("CONSTRUCTION_FABRICATION_RESERVED_INPUT_NOT_FOUND")
		projections.append(projection)
	var operation_id := _operation_id(job_id, "cancel")
	var planned := PlannerScript.build_release_plan(_plan_id(job_id, "cancel"), operation_id, snapshot, job, projections)
	if not bool(planned.get("success", false)): return planned
	var applied: Dictionary = _adapter.apply_plan(planned["plan"], failure_mode)
	if not bool(applied.get("success", false)): return applied
	var current: Dictionary = _queue.get_job(job_id)
	var next := JobScript.with_updates(current, {"status": "CANCELLED", "cancellation_operation_id": operation_id, "last_error_code": ""})
	return _queue.replace_job(String(current["checksum"]), next)

func reconcile_job(job_id: String) -> Dictionary:
	if not _configured: return _failure("CONSTRUCTION_FABRICATION_PROCESS_NOT_CONFIGURED")
	var job: Dictionary = _queue.get_job(job_id); if job.is_empty(): return _failure("CONSTRUCTION_FABRICATION_JOB_NOT_FOUND")
	var snapshot: Dictionary = _adapter.get_construct_snapshot(String(job["machine_construct_id"])); if snapshot.is_empty(): return _failure("CONSTRUCTION_FABRICATION_MACHINE_SNAPSHOT_NOT_FOUND")
	var runtime: Dictionary = snapshot["compiled_facets"].get("fabrication_runtime", {})
	var updates: Dictionary = {}
	if String(runtime.get("last_completed_job_id", "")) == job_id:
		updates = {"status": "COMPLETED", "completion_operation_id": _operation_id(job_id, "complete"), "last_error_code": ""}
	elif String(runtime.get("last_cancelled_job_id", "")) == job_id:
		updates = {"status": "CANCELLED", "cancellation_operation_id": _operation_id(job_id, "cancel"), "last_error_code": ""}
	elif String(runtime.get("active_job_id", "")) == job_id:
		updates = {"status": "PROCESSING" if int(job["work_completed"]) > 0 else "RESERVED", "reservation_operation_id": _operation_id(job_id, "reserve"), "last_error_code": ""}
	else:
		return _success({"replay": true, "no_change": true, "job": job})
	var next := JobScript.with_updates(job, updates)
	return _queue.replace_job(String(job["checksum"]), next)

func _ready_job(job_id: String, profile: Dictionary, allowed_statuses: Array) -> Dictionary:
	if not _configured: return _failure("CONSTRUCTION_FABRICATION_PROCESS_NOT_CONFIGURED")
	var checked := ProfileScript.validate(profile); if not bool(checked.get("success", false)): return checked
	var job: Dictionary = _queue.get_job(job_id); if job.is_empty(): return _failure("CONSTRUCTION_FABRICATION_JOB_NOT_FOUND")
	if not allowed_statuses.has(String(job["status"])): return _failure("CONSTRUCTION_FABRICATION_JOB_STATE_CONFLICT")
	if String(job["machine_construct_id"]) != String(profile["construct_id"]): return _failure("CONSTRUCTION_FABRICATION_JOB_MACHINE_MISMATCH")
	var recipe: Dictionary = _catalog.get_recipe(String(job["recipe_id"]), int(job["recipe_version"])); if recipe.is_empty() or String(recipe["checksum"]) != String(job["recipe_checksum"]): return _failure("CONSTRUCTION_FABRICATION_JOB_RECIPE_NOT_AVAILABLE")
	return _success({"job": job, "recipe": recipe})
func _allocate_inputs(recipe: Dictionary, available: Array) -> Dictionary:
	var candidates: Array = available.duplicate(true); candidates.sort_custom(func(a,b): return String(a.get("item_instance_id", "")) < String(b.get("item_instance_id", "")))
	var remaining_by_id: Dictionary = {}; for projection in candidates: remaining_by_id[String(projection["item_instance_id"])] = int(projection["quantity"])
	var bindings: Array = []
	for requirement in recipe["input_requirements"]:
		var remaining := int(requirement["quantity"])
		for projection in candidates:
			if remaining <= 0: break
			if String(projection["definition_id"]) != String(requirement["definition_id"]): continue
			if not _contains_exact(Dictionary(projection["components"]), Dictionary(requirement["components_exact"])): continue
			var id := String(projection["item_instance_id"]); var take := mini(remaining, int(remaining_by_id[id])); if take <= 0: continue
			bindings.append({"item_instance_id": id, "definition_id": String(projection["definition_id"]), "quantity": take, "components": Dictionary(projection["components"]).duplicate(true), "original_relation": Dictionary(projection["relation"]).duplicate(true), "source_revision": int(projection["revision"]), "source_fingerprint": UtilsScript.payload_hash(projection)})
			remaining_by_id[id] = int(remaining_by_id[id]) - take; remaining -= take
		if remaining > 0: return _failure("CONSTRUCTION_FABRICATION_INPUT_REQUIREMENT_UNSATISFIED")
	bindings.sort_custom(func(a,b): return String(a["item_instance_id"]) < String(b["item_instance_id"]))
	return _success({"bindings": bindings})
func _contains_exact(source: Dictionary, required: Dictionary) -> bool:
	for key in required:
		if not source.has(key) or UtilsScript.canonical_json(source[key]) != UtilsScript.canonical_json(required[key]): return false
	return true
func _block(job_id: String, code: String) -> Dictionary:
	var marked: Dictionary = _queue.mark_blocked(job_id, code)
	return _failure(code, {"job": marked.get("job", {})})
func _operation_id(job_id: String, phase: String) -> String: return "operation/fabrication/%s/%s" % [job_id.trim_prefix("fabrication-job/"), phase]
func _plan_id(job_id: String, phase: String) -> String: return "plan/fabrication/%s/%s" % [job_id.trim_prefix("fabrication-job/"), phase]
func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result
func _failure(code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true), "status": "RETRYABLE" if code in ["FABRICATION_MACHINE_NOT_ONLINE", "FABRICATION_MACHINE_OFFLINE"] else "REJECTED"}
