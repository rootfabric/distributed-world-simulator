extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const StageScript = preload("res://scripts/construction/build/construction_build_stage.gd")

const SCHEMA: String = "planet_simulator.construction_build_plan.v1"
const FIELDS: Array[String] = [
	"schema",
	"build_plan_id",
	"construct_id",
	"root_item_instance_id",
	"display_name",
	"ghost_relation",
	"target_snapshot",
	"source_item_projections",
	"stages",
	"checksum",
]


static func create(
	build_plan_id: String,
	display_name: String,
	ghost_relation: Dictionary,
	target_snapshot: Dictionary,
	source_item_projections: Array,
	stages: Array
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"build_plan_id": build_plan_id,
		"construct_id": String(target_snapshot.get("construct_id", "")),
		"root_item_instance_id": String(target_snapshot.get("root_item_instance_id", "")),
		"display_name": display_name,
		"ghost_relation": ghost_relation.duplicate(true),
		"target_snapshot": target_snapshot.duplicate(true),
		"source_item_projections": _sorted_projections(source_item_projections),
		"stages": _sorted_stages(stages),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_BUILD_PLAN_SCHEMA")
	if not _is_identifier(String(value.get("build_plan_id", "")), "build-plan/"):
		return _failure("INVALID_CONSTRUCTION_BUILD_PLAN_ID")
	if typeof(value.get("display_name")) != TYPE_STRING or String(value["display_name"]).strip_edges().is_empty():
		return _failure("CONSTRUCTION_BUILD_PLAN_NAME_REQUIRED")
	if typeof(value.get("ghost_relation")) != TYPE_DICTIONARY:
		return _failure("INVALID_CONSTRUCTION_BUILD_PLAN_GHOST_RELATION")
	var relation_validation: Dictionary = ProjectionScript.validate_relation(value["ghost_relation"])
	if not bool(relation_validation.get("success", false)):
		return relation_validation
	if String(value["ghost_relation"].get("kind", "")) != ProjectionScript.WORLD:
		return _failure("BUILD_PLAN_GHOST_MUST_USE_WORLD_RELATION")
	if typeof(value.get("target_snapshot")) != TYPE_DICTIONARY:
		return _failure("INVALID_CONSTRUCTION_BUILD_PLAN_TARGET")
	var target: Dictionary = value["target_snapshot"]
	var target_validation: Dictionary = SnapshotScript.validate(target)
	if not bool(target_validation.get("success", false)):
		return target_validation
	if String(value.get("construct_id", "")) != String(target["construct_id"]):
		return _failure("BUILD_PLAN_CONSTRUCT_ID_MISMATCH")
	if String(value.get("root_item_instance_id", "")) != String(target["root_item_instance_id"]):
		return _failure("BUILD_PLAN_ROOT_ITEM_ID_MISMATCH")
	if String(target["build_state"]) != "OPERATIONAL":
		return _failure("BUILD_PLAN_TARGET_MUST_BE_OPERATIONAL")
	var source_result: Dictionary = _source_projection_map(value.get("source_item_projections"))
	if not bool(source_result.get("success", false)):
		return source_result
	var sources: Dictionary = source_result["sources"]
	if sources.has(String(target["root_item_instance_id"])):
		return _failure("BUILD_PLAN_ROOT_ALREADY_EXISTS_IN_SOURCE_ITEMS")
	var target_parts: Dictionary = {}
	var target_part_items: Dictionary = {}
	for part in target["parts"]:
		var part_id: String = String(part["part_id"])
		var item_id: String = String(part["item_instance_id"])
		target_parts[part_id] = part
		if target_part_items.has(item_id):
			return _failure("BUILD_PLAN_TARGET_REUSES_ITEM")
		target_part_items[item_id] = true
		if not sources.has(item_id):
			return _failure("BUILD_PLAN_PART_SOURCE_MISSING")
		var source: Dictionary = sources[item_id]
		if int(source["quantity"]) != 1:
			return _failure("BUILD_PLAN_PART_SOURCE_MUST_BE_SINGLE_ITEM")
		if String(source["relation"].get("kind", "")) in [ProjectionScript.ATTACHMENT, ProjectionScript.DESTROYED]:
			return _failure("BUILD_PLAN_PART_SOURCE_NOT_TRANSFERABLE")
	var target_bonds: Dictionary = {}
	for bond in target["bonds"]:
		target_bonds[String(bond["bond_id"])] = bond
	if typeof(value.get("stages")) != TYPE_ARRAY or value["stages"].is_empty():
		return _failure("CONSTRUCTION_BUILD_PLAN_STAGES_REQUIRED")
	var stage_ids: Dictionary = {}
	var previous_parts: Dictionary = {}
	var previous_bonds: Dictionary = {}
	var material_totals: Dictionary = {}
	var referenced_source_ids: Dictionary = target_part_items.duplicate(true)
	var previous_semantic_state: String = ""
	for index in range(value["stages"].size()):
		var stage_value = value["stages"][index]
		if typeof(stage_value) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_BUILD_PLAN_STAGE")
		var stage: Dictionary = stage_value
		var stage_validation: Dictionary = StageScript.validate(stage)
		if not bool(stage_validation.get("success", false)):
			return stage_validation
		if int(stage["sequence_index"]) != index:
			return _failure("BUILD_PLAN_STAGE_INDEX_GAP")
		var stage_id: String = String(stage["stage_id"])
		if stage_ids.has(stage_id):
			return _failure("DUPLICATE_BUILD_PLAN_STAGE_ID")
		stage_ids[stage_id] = true
		var current_parts: Dictionary = _set_from_array(stage["included_part_ids"])
		var current_bonds: Dictionary = _set_from_array(stage["included_bond_ids"])
		if index == 0 and current_parts.is_empty():
			return _failure("BUILD_PLAN_FIRST_STAGE_MUST_INCLUDE_PART")
		if not _is_subset(previous_parts, current_parts) or not _is_subset(previous_bonds, current_bonds):
			return _failure("BUILD_PLAN_STAGE_CONTENT_REGRESSED")
		for part_id in current_parts:
			if not target_parts.has(part_id):
				return _failure("BUILD_PLAN_STAGE_REFERENCES_UNKNOWN_PART")
		for bond_id in current_bonds:
			if not target_bonds.has(bond_id):
				return _failure("BUILD_PLAN_STAGE_REFERENCES_UNKNOWN_BOND")
			var bond: Dictionary = target_bonds[bond_id]
			if not current_parts.has(String(bond["part_a_id"])) or not current_parts.has(String(bond["part_b_id"])):
				return _failure("BUILD_PLAN_STAGE_BOND_ENDPOINT_NOT_INCLUDED")
		var made_progress: bool = (
			current_parts.size() > previous_parts.size()
			or not stage["material_allocations"].is_empty()
		)
		if not made_progress:
			return _failure("BUILD_PLAN_STAGE_MAKES_NO_PROGRESS")
		for allocation in stage["material_allocations"]:
			var item_id: String = String(allocation["item_instance_id"])
			if target_part_items.has(item_id):
				return _failure("BUILD_PLAN_PART_CANNOT_BE_CONSUMABLE")
			if not sources.has(item_id):
				return _failure("BUILD_PLAN_MATERIAL_SOURCE_MISSING")
			var source: Dictionary = sources[item_id]
			if String(source["definition_id"]) != String(allocation["definition_id"]):
				return _failure("BUILD_PLAN_MATERIAL_DEFINITION_MISMATCH")
			if String(source["relation"].get("kind", "")) in [ProjectionScript.ATTACHMENT, ProjectionScript.DESTROYED]:
				return _failure("BUILD_PLAN_MATERIAL_SOURCE_NOT_TRANSFERABLE")
			material_totals[item_id] = int(material_totals.get(item_id, 0)) + int(allocation["quantity"])
			if int(material_totals[item_id]) > int(source["quantity"]):
				return _failure("BUILD_PLAN_MATERIAL_WOULD_EXHAUST_STACK")
			referenced_source_ids[item_id] = true
		previous_parts = current_parts
		previous_bonds = current_bonds
		previous_semantic_state = String(stage["semantic_state"])
	var final_stage: Dictionary = value["stages"][-1]
	if String(final_stage["semantic_state"]) != StageScript.SEMANTIC_OPERATIONAL:
		return _failure("BUILD_PLAN_FINAL_STAGE_NOT_OPERATIONAL")
	if _set_from_array(final_stage["included_part_ids"]) != _set_from_array(target_parts.keys()):
		return _failure("BUILD_PLAN_FINAL_STAGE_PART_SET_INCOMPLETE")
	if _set_from_array(final_stage["included_bond_ids"]) != _set_from_array(target_bonds.keys()):
		return _failure("BUILD_PLAN_FINAL_STAGE_BOND_SET_INCOMPLETE")
	if referenced_source_ids.size() != sources.size():
		return _failure("BUILD_PLAN_HAS_UNUSED_SOURCE_ITEMS")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value):
		return _failure("CONSTRUCTION_BUILD_PLAN_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("CONSTRUCTION_BUILD_PLAN_NOT_JSON_SAFE")
	return _success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


static func source_projection_map(plan: Dictionary) -> Dictionary:
	var result: Dictionary = _source_projection_map(plan.get("source_item_projections"))
	return Dictionary(result.get("sources", {})).duplicate(true) if bool(result.get("success", false)) else {}


static func stage_at(plan: Dictionary, index: int) -> Dictionary:
	if index < 0 or index >= plan.get("stages", []).size():
		return {}
	return Dictionary(plan["stages"][index]).duplicate(true)


static func _source_projection_map(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("INVALID_BUILD_PLAN_SOURCE_ITEM_PROJECTIONS")
	var sources: Dictionary = {}
	var previous_item_id: String = ""
	for projection_value in value:
		if typeof(projection_value) != TYPE_DICTIONARY:
			return _failure("INVALID_BUILD_PLAN_SOURCE_ITEM_PROJECTION")
		var projection: Dictionary = projection_value
		var validation: Dictionary = ProjectionScript.validate(projection)
		if not bool(validation.get("success", false)):
			return validation
		var item_id: String = String(projection["item_instance_id"])
		if sources.has(item_id):
			return _failure("DUPLICATE_BUILD_PLAN_SOURCE_ITEM")
		if not previous_item_id.is_empty() and item_id < previous_item_id:
			return _failure("BUILD_PLAN_SOURCE_ITEMS_NOT_SORTED")
		sources[item_id] = projection.duplicate(true)
		previous_item_id = item_id
	return _success({"sources": sources})


static func _sorted_projections(values: Array) -> Array:
	var result: Array = values.duplicate(true)
	result.sort_custom(func(left, right):
		return String(left.get("item_instance_id", "")) < String(right.get("item_instance_id", ""))
	)
	return result


static func _sorted_stages(values: Array) -> Array:
	var result: Array = values.duplicate(true)
	result.sort_custom(func(left, right):
		return int(left.get("sequence_index", -1)) < int(right.get("sequence_index", -1))
	)
	return result


static func _set_from_array(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for value in values:
		result[String(value)] = true
	return result


static func _is_subset(left: Dictionary, right: Dictionary) -> bool:
	for key in left:
		if not right.has(key):
			return false
	return true


static func _is_identifier(value: String, prefix: String) -> bool:
	return value.begins_with(prefix) and value.length() > prefix.length() and value == value.strip_edges()


static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
