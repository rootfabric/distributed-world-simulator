extends RefCounted

const BuildPlanScript = preload("res://scripts/construction/build/construction_build_plan.gd")
const StageScript = preload("res://scripts/construction/build/construction_build_stage.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const CapabilityCompilerScript = preload("res://scripts/construction/compilation/construction_capability_compiler.gd")


static func build_for_stage(build_plan: Dictionary, stage_index: int) -> Dictionary:
	var plan_validation: Dictionary = BuildPlanScript.validate(build_plan)
	if not bool(plan_validation.get("success", false)):
		return plan_validation
	if stage_index < 0 or stage_index >= build_plan["stages"].size():
		return _failure("INVALID_CONSTRUCTION_BUILD_STAGE_INDEX")
	var stage: Dictionary = build_plan["stages"][stage_index]
	var target: Dictionary = build_plan["target_snapshot"]
	var included_parts: Dictionary = _set_from_array(stage["included_part_ids"])
	var included_bonds: Dictionary = _set_from_array(stage["included_bond_ids"])
	var parts: Array = []
	for part in target["parts"]:
		if included_parts.has(String(part["part_id"])):
			parts.append(part.duplicate(true))
	var bonds: Array = []
	for bond in target["bonds"]:
		if included_bonds.has(String(bond["bond_id"])):
			bonds.append(bond.duplicate(true))
	var compiled_result: Dictionary = CapabilityCompilerScript.compile(parts, bonds)
	if not bool(compiled_result.get("success", false)):
		return compiled_result
	var compiled: Dictionary = Dictionary(compiled_result["compiled"]).duplicate(true)
	var operational: bool = String(stage["semantic_state"]) == StageScript.SEMANTIC_OPERATIONAL
	compiled["construction_stage_id"] = String(stage["stage_id"])
	compiled["construction_stage_index"] = stage_index
	compiled["construction_semantic_state"] = String(stage["semantic_state"])
	compiled["operational"] = operational
	if not operational:
		compiled["capabilities"] = []
	var snapshot: Dictionary = SnapshotScript.create(
		String(build_plan["construct_id"]),
		String(build_plan["root_item_instance_id"]),
		stage_index,
		"OPERATIONAL" if operational else "PARTIAL",
		parts,
		bonds,
		compiled
	)
	var validation: Dictionary = SnapshotScript.validate(snapshot)
	if not bool(validation.get("success", false)):
		return validation
	return _success({"snapshot": snapshot})


static func all_stage_snapshots(build_plan: Dictionary) -> Dictionary:
	var validation: Dictionary = BuildPlanScript.validate(build_plan)
	if not bool(validation.get("success", false)):
		return validation
	var snapshots: Array = []
	for index in range(build_plan["stages"].size()):
		var built: Dictionary = build_for_stage(build_plan, index)
		if not bool(built.get("success", false)):
			return built
		snapshots.append(built["snapshot"])
	return _success({"snapshots": snapshots})


static func completed_stage_count(build_plan: Dictionary, current_snapshot: Dictionary) -> Dictionary:
	var validation: Dictionary = BuildPlanScript.validate(build_plan)
	if not bool(validation.get("success", false)):
		return validation
	if current_snapshot.is_empty():
		return _success({"completed_stage_count": 0})
	var snapshot_validation: Dictionary = SnapshotScript.validate(current_snapshot)
	if not bool(snapshot_validation.get("success", false)):
		return snapshot_validation
	if (
		String(current_snapshot["construct_id"]) != String(build_plan["construct_id"])
		or String(current_snapshot["root_item_instance_id"]) != String(build_plan["root_item_instance_id"])
	):
		return _failure("CONSTRUCTION_BUILD_PLAN_CONSTRUCT_DIVERGED")
	for index in range(build_plan["stages"].size()):
		var expected: Dictionary = build_for_stage(build_plan, index)
		if not bool(expected.get("success", false)):
			return expected
		if String(expected["snapshot"]["checksum"]) == String(current_snapshot["checksum"]):
			return _success({"completed_stage_count": index + 1})
	return _failure("CONSTRUCTION_BUILD_PLAN_CONSTRUCT_DIVERGED")


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
