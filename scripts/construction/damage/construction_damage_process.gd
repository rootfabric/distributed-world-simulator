extends RefCounted

const PlannerScript = preload("res://scripts/construction/damage/construction_damage_planner.gd")

var _adapter
var _configured := false

func setup(adapter) -> Dictionary:
	if adapter == null or not adapter.has_method("get_construct_snapshot") or not adapter.has_method("get_item_projection") or not adapter.has_method("apply_damage_plan"):
		return _failure("CONSTRUCTION_DAMAGE_TRANSACTION_ADAPTER_REQUIRED")
	_adapter = adapter
	_configured = true
	return _success()

func apply_damage(plan_id: String, operation_id: String, request: Dictionary, failure_mode: String = "") -> Dictionary:
	if not _configured: return _failure("CONSTRUCTION_DAMAGE_PROCESS_NOT_CONFIGURED")
	if _adapter.has_method("get_operation_result"):
		var prior: Dictionary = _adapter.get_operation_result(operation_id)
		if not prior.is_empty():
			var current: Dictionary = _adapter.get_construct_snapshot(String(request.get("construct_id", "")))
			var facets: Dictionary = current.get("compiled_facets", {}) if not current.is_empty() else {}
			if String(facets.get("damage_request_checksum", "")) == String(request.get("checksum", "")):
				return _success({
					"replay": true, "result": prior,
					"components": Array(facets.get("damage_components", [])).duplicate(true),
					"repair_plan": Dictionary(facets.get("damage_repair_plan", {})).duplicate(true),
					"salvage_item_ids": Array(facets.get("damage_salvage_item_ids", [])).duplicate(),
					"split_construct_ids": Array(facets.get("damage_split_construct_ids", [])).duplicate(),
				})
			return _failure("CONSTRUCTION_DAMAGE_OPERATION_REPLAY_CONFLICT")
	var snapshot: Dictionary = _adapter.get_construct_snapshot(String(request.get("construct_id", "")))
	if snapshot.is_empty(): return _failure("CONSTRUCTION_DAMAGE_CONSTRUCT_NOT_FOUND")
	var projections: Array = []
	for part in snapshot["parts"]:
		var projection: Dictionary = _adapter.get_item_projection(String(part["item_instance_id"]))
		if projection.is_empty(): return _failure("CONSTRUCTION_DAMAGE_PART_ITEM_MISSING")
		projections.append(projection)
	var planned := PlannerScript.build_damage_plan(plan_id, operation_id, request, snapshot, projections)
	if not bool(planned.get("success", false)): return planned
	var applied: Dictionary = _adapter.apply_damage_plan(planned["plan"], failure_mode)
	if not bool(applied.get("success", false)): return applied
	return _success({"result": applied, "components": planned["components"], "repair_plan": planned["repair_plan"], "salvage_item_ids": planned["salvage_item_ids"], "split_construct_ids": planned["split_construct_ids"]})

func apply_repair(plan_id: String, operation_id: String, repair_plan: Dictionary, failure_mode: String = "") -> Dictionary:
	if not _configured: return _failure("CONSTRUCTION_DAMAGE_PROCESS_NOT_CONFIGURED")
	if _adapter.has_method("get_operation_result"):
		var prior: Dictionary = _adapter.get_operation_result(operation_id)
		if not prior.is_empty():
			var restored: Dictionary = _adapter.get_construct_snapshot(String(repair_plan.get("target_construct_id", "")))
			return _success({"replay": true, "result": prior, "restored_snapshot": restored})
	var snapshots: Array = []
	var target: Dictionary = _adapter.get_construct_snapshot(String(repair_plan.get("target_construct_id", "")))
	if target.is_empty(): return _failure("CONSTRUCTION_REPAIR_TARGET_NOT_FOUND")
	snapshots.append(target)
	for construct_id in repair_plan.get("split_construct_ids", []):
		var snapshot: Dictionary = _adapter.get_construct_snapshot(String(construct_id))
		if snapshot.is_empty(): return _failure("CONSTRUCTION_REPAIR_SPLIT_CONSTRUCT_NOT_FOUND")
		snapshots.append(snapshot)
	var projections: Array = []
	for item_id in repair_plan.get("required_part_item_ids", []):
		var projection: Dictionary = _adapter.get_item_projection(String(item_id))
		if projection.is_empty(): return _failure("CONSTRUCTION_REPAIR_PART_ITEM_MISSING")
		projections.append(projection)
	for root_id in repair_plan.get("split_root_item_ids", []):
		var root: Dictionary = _adapter.get_item_projection(String(root_id))
		if root.is_empty(): return _failure("CONSTRUCTION_REPAIR_SPLIT_ROOT_NOT_FOUND")
		projections.append(root)
	var planned := PlannerScript.build_repair_plan(plan_id, operation_id, repair_plan, snapshots, projections)
	if not bool(planned.get("success", false)): return planned
	var applied: Dictionary = _adapter.apply_damage_plan(planned["plan"], failure_mode)
	if not bool(applied.get("success", false)): return applied
	return _success({"result": applied, "restored_snapshot": planned["restored_snapshot"]})

static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": ""}
	for key in details: result[key] = details[key]
	return result
static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
