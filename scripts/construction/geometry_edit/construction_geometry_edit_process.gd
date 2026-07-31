extends RefCounted

const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const InstanceScript = preload("res://scripts/construction/parametric/construction_parametric_member_instance.gd")
const ProjectionFactoryScript = preload("res://scripts/construction/parametric/construction_parametric_projection_factory.gd")
const RequestScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_request.gd")
const RecordScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_record.gd")
const CompilerScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_compiler.gd")
const PlannerScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_transaction_planner.gd")

var _adapter
var _catalog
var _history

func setup(adapter, catalog, history = null) -> Dictionary:
	if adapter == null or not adapter.has_method("get_item_projection") or not adapter.has_method("get_construct_snapshot") or not adapter.has_method("apply_plan"): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_ADAPTER_REQUIRED")
	if catalog == null or not catalog.has_method("get_definition") or not catalog.has_method("get_materials_for_definition"): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_CATALOG_REQUIRED")
	if history != null and not history.has_method("publish"): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_HISTORY_REQUIRED")
	_adapter = adapter; _catalog = catalog; _history = history; return ParametricUtils.success()

func apply_edit(plan_id: String, request: Dictionary, failure_mode: String = "") -> Dictionary:
	var checked := RequestScript.validate(request); if not bool(checked.get("success", false)): return checked
	var replay := _resolve_replay(request)
	if bool(replay.get("found", false)): return replay["result"]
	var projection: Dictionary = _adapter.get_item_projection(String(request["item_instance_id"]))
	if projection.is_empty(): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_ITEM_NOT_FOUND")
	checked = ProjectionFactoryScript.validate_projection(projection); if not bool(checked.get("success", false)): return checked
	if int(projection["revision"]) != int(request["expected_item_revision"]): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_ITEM_PRECONDITION_MISMATCH")
	var current_instance: Dictionary = checked["instance"]
	var snapshot: Dictionary = _adapter.get_construct_snapshot(String(request["construct_id"]))
	if snapshot.is_empty(): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_CONSTRUCT_NOT_FOUND")
	if String(snapshot["checksum"]) != String(request["expected_construct_checksum"]): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_CONSTRUCT_PRECONDITION_MISMATCH")
	var definition: Dictionary = _catalog.get_definition(String(current_instance["member_definition_id"]), int(current_instance["definition_version"]))
	if definition.is_empty(): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_DEFINITION_NOT_FOUND")
	var materials: Array = _catalog.get_materials_for_definition(definition)
	var compiled := CompilerScript.compile(current_instance, definition, materials, request); if not bool(compiled.get("success", false)): return compiled
	var planned := PlannerScript.plan(plan_id, request, projection, snapshot, compiled); if not bool(planned.get("success", false)): return planned
	var applied: Dictionary = _adapter.apply_plan(planned["plan"], failure_mode)
	if not bool(applied.get("success", false)): return applied
	if _history != null:
		var stored: Dictionary = _history.publish(planned["record"]); if not bool(stored.get("success", false)): return stored
	var result := applied.duplicate(true)
	result["record"] = Dictionary(planned["record"]).duplicate(true)
	result["updated_instance"] = Dictionary(compiled["updated_instance"]).duplicate(true)
	result["geometry_state"] = Dictionary(compiled["after_state"]).duplicate(true)
	result["replay"] = false
	return result

func _resolve_replay(request: Dictionary) -> Dictionary:
	if not _adapter.has_method("get_operation_result"): return {"found": false}
	var operation_result: Dictionary = _adapter.get_operation_result(String(request["operation_id"]))
	if operation_result.is_empty(): return {"found": false}
	if not bool(operation_result.get("success", false)):
		return {"found": true, "result": operation_result.duplicate(true)}
	var snapshot: Dictionary = _adapter.get_construct_snapshot(String(request["construct_id"]))
	var records: Variant = snapshot.get("compiled_facets", {}).get("geometry_edits", {}) if not snapshot.is_empty() else {}
	if not records is Dictionary or not Dictionary(records).has(String(request["operation_id"])): return {"found": true, "result": ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_REPLAY_RECORD_MISSING")}
	var record: Dictionary = Dictionary(records)[String(request["operation_id"])]
	var checked := RecordScript.validate(record); if not bool(checked.get("success", false)): return {"found": true, "result": checked}
	if String(record["request_checksum"]) != String(request["checksum"]): return {"found": true, "result": ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_OPERATION_ID_CONFLICT")}
	var projection: Dictionary = _adapter.get_item_projection(String(request["item_instance_id"]))
	var instance: Variant = Dictionary(projection.get("components", {})).get("parametric_member", {}) if not projection.is_empty() else {}
	if _history != null:
		var stored: Dictionary = _history.publish(record)
		if not bool(stored.get("success", false)):
			return {"found": true, "result": stored}
	var result: Dictionary = operation_result.duplicate(true)
	result["record"] = record.duplicate(true)
	result["updated_instance"] = Dictionary(instance).duplicate(true) if instance is Dictionary else {}
	result["geometry_state"] = Dictionary(record["after_state"]).duplicate(true)
	result["replay"] = true
	return {"found": true, "result": result}
