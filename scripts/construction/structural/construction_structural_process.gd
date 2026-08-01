extends RefCounted

const CompilerScript = preload("res://scripts/construction/structural/construction_structural_compiler.gd")
const CascadePlannerScript = preload("res://scripts/construction/structural/construction_structural_cascade_planner.gd")
const DamageProcessScript = preload("res://scripts/construction/damage/construction_damage_process.gd")

var _adapter
var _damage_process
var _configured := false

func setup(adapter) -> Dictionary:
	if adapter == null or not adapter.has_method("get_construct_snapshot") or not adapter.has_method("get_operation_result") or not adapter.has_method("apply_damage_plan"):
		return _failure("CONSTRUCTION_STRUCTURAL_TRANSACTION_ADAPTER_REQUIRED")
	_adapter = adapter
	_damage_process = DamageProcessScript.new()
	var setup_result: Dictionary = _damage_process.setup(adapter); if not bool(setup_result.get("success", false)): return setup_result
	_configured = true
	return _success()

func evaluate(load_case: Dictionary) -> Dictionary:
	if not _configured: return _failure("CONSTRUCTION_STRUCTURAL_PROCESS_NOT_CONFIGURED")
	var snapshot: Dictionary = _adapter.get_construct_snapshot(String(load_case.get("construct_id", "")))
	if snapshot.is_empty(): return _failure("CONSTRUCTION_STRUCTURAL_CONSTRUCT_NOT_FOUND")
	return CompilerScript.compile(snapshot, load_case)

func apply_cascade(plan_id: String, operation_id: String, cascade_id: String, load_case: Dictionary, failure_mode: String = "") -> Dictionary:
	if not _configured: return _failure("CONSTRUCTION_STRUCTURAL_PROCESS_NOT_CONFIGURED")
	var prior: Dictionary = _adapter.get_operation_result(operation_id)
	if not prior.is_empty():
		var current: Dictionary = _adapter.get_construct_snapshot(String(load_case.get("construct_id", "")))
		var facets: Dictionary = current.get("compiled_facets", {}) if not current.is_empty() else {}
		var repair_plan: Dictionary = facets.get("damage_repair_plan", {}) if facets.get("damage_repair_plan", {}) is Dictionary else {}
		var original: Dictionary = repair_plan.get("target_snapshot_template", {}) if not repair_plan.is_empty() else {}
		if original.is_empty(): return _failure("CONSTRUCTION_STRUCTURAL_OPERATION_REPLAY_CONTEXT_MISSING")
		var replay_plan := CascadePlannerScript.build(cascade_id, original, load_case)
		if not bool(replay_plan.get("success", false)): return _failure("CONSTRUCTION_STRUCTURAL_OPERATION_REPLAY_CONFLICT")
		var expected_request: Dictionary = replay_plan["plan"]["damage_request"]
		if expected_request.is_empty() or String(expected_request.get("checksum", "")) != String(facets.get("damage_request_checksum", "")):
			return _failure("CONSTRUCTION_STRUCTURAL_OPERATION_REPLAY_CONFLICT")
		return _success({"replay": true, "result": prior, "cascade_plan": replay_plan["plan"], "profile": replay_plan["final_profile"]})
	var snapshot: Dictionary = _adapter.get_construct_snapshot(String(load_case.get("construct_id", "")))
	if snapshot.is_empty(): return _failure("CONSTRUCTION_STRUCTURAL_CONSTRUCT_NOT_FOUND")
	var planned := CascadePlannerScript.build(cascade_id, snapshot, load_case)
	if not bool(planned.get("success", false)): return planned
	var cascade_plan: Dictionary = planned["plan"]
	if bool(cascade_plan["stable"]): return _success({"replay": false, "stable": true, "cascade_plan": cascade_plan, "profile": planned["final_profile"]})
	var applied: Dictionary = _damage_process.apply_damage(plan_id, operation_id, cascade_plan["damage_request"], failure_mode)
	if not bool(applied.get("success", false)): return applied
	return _success({"replay": false, "stable": false, "cascade_plan": cascade_plan, "profile": planned["final_profile"], "damage_result": applied})

static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}; for key in details: result[key] = details[key]
	return result
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code, "details": {}}
