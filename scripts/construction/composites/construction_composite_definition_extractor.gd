extends RefCounted

const DefinitionScript = preload("res://scripts/construction/composites/construction_composite_definition.gd")
const PartSlotScript = preload("res://scripts/construction/composites/composite_part_slot.gd")
const BondTemplateScript = preload("res://scripts/construction/composites/composite_bond_template.gd")
const StageTemplateScript = preload("res://scripts/construction/composites/composite_stage_template.gd")
const BuildPlanScript = preload("res://scripts/construction/build/construction_build_plan.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const SnapshotBuilderScript = preload("res://scripts/construction/build/construction_stage_snapshot_builder.gd")


static func extract_from_completed_build(
	composite_definition_id: String,
	definition_version: int,
	display_name: String,
	root_display_name: String,
	completed_snapshot: Dictionary,
	build_plan: Dictionary,
	created_by: String
) -> Dictionary:
	var plan_validation: Dictionary = BuildPlanScript.validate(build_plan)
	if not bool(plan_validation.get("success", false)):
		return plan_validation
	var snapshot_validation: Dictionary = SnapshotScript.validate(completed_snapshot)
	if not bool(snapshot_validation.get("success", false)):
		return snapshot_validation
	var completed: Dictionary = SnapshotBuilderScript.completed_stage_count(build_plan, completed_snapshot)
	if not bool(completed.get("success", false)):
		return completed
	if int(completed.get("completed_stage_count", 0)) != build_plan["stages"].size():
		return _failure("COMPOSITE_DEFINITION_SOURCE_BUILD_NOT_COMPLETE")
	if String(completed_snapshot.get("build_state", "")) != "OPERATIONAL":
		return _failure("COMPOSITE_DEFINITION_SOURCE_NOT_OPERATIONAL")
	var source_map: Dictionary = BuildPlanScript.source_projection_map(build_plan)
	var part_id_to_slot: Dictionary = {}
	var part_slots: Array = []
	var used_slot_ids: Dictionary = {}
	for part in completed_snapshot["parts"]:
		var item_id: String = String(part["item_instance_id"])
		if not source_map.has(item_id):
			return _failure("COMPOSITE_DEFINITION_PART_SOURCE_MISSING")
		var source: Dictionary = source_map[item_id]
		var slot_id: String = "slot/%s" % _leaf(String(part["part_id"]))
		if used_slot_ids.has(slot_id):
			return _failure("COMPOSITE_DEFINITION_DERIVED_SLOT_ID_CONFLICT")
		used_slot_ids[slot_id] = true
		part_id_to_slot[String(part["part_id"])] = slot_id
		var part_metadata: Dictionary = Dictionary(part.get("metadata", {}))
		var required_components: Dictionary = {}
		if part_metadata.get("required_components", {}) is Dictionary:
			required_components = Dictionary(part_metadata.get("required_components", {})).duplicate(true)
			part_metadata.erase("required_components")
		part_slots.append(PartSlotScript.create(
			slot_id,
			String(source["definition_id"]),
			String(source["display_name"]),
			String(part["part_kind"]),
			String(part["role"]),
			float(part["mass_kg"]),
			Array(part["local_position_m"]),
			required_components,
			part_metadata
		))
	var bond_id_to_template: Dictionary = {}
	var bond_templates: Array = []
	var used_bond_ids: Dictionary = {}
	for bond in completed_snapshot["bonds"]:
		var template_id: String = "bond-template/%s" % _leaf(String(bond["bond_id"]))
		if used_bond_ids.has(template_id):
			return _failure("COMPOSITE_DEFINITION_DERIVED_BOND_ID_CONFLICT")
		if not part_id_to_slot.has(String(bond["part_a_id"])) or not part_id_to_slot.has(String(bond["part_b_id"])):
			return _failure("COMPOSITE_DEFINITION_BOND_SOURCE_PART_MISSING")
		used_bond_ids[template_id] = true
		bond_id_to_template[String(bond["bond_id"])] = template_id
		bond_templates.append(BondTemplateScript.create(
			template_id,
			String(part_id_to_slot[String(bond["part_a_id"])]),
			String(part_id_to_slot[String(bond["part_b_id"])]),
			String(bond["bond_kind"]),
			float(bond["strength_n"]),
			Dictionary(bond.get("metadata", {}))
		))
	var stage_templates: Array = []
	var used_stage_ids: Dictionary = {}
	for stage in build_plan["stages"]:
		var stage_template_id: String = "stage-template/%s" % _leaf(String(stage["stage_id"]))
		if used_stage_ids.has(stage_template_id):
			return _failure("COMPOSITE_DEFINITION_DERIVED_STAGE_ID_CONFLICT")
		used_stage_ids[stage_template_id] = true
		var included_slots: Array = []
		for part_id in stage["included_part_ids"]:
			if not part_id_to_slot.has(String(part_id)):
				return _failure("COMPOSITE_DEFINITION_STAGE_PART_MAPPING_MISSING")
			included_slots.append(String(part_id_to_slot[String(part_id)]))
		var included_bonds: Array = []
		for bond_id in stage["included_bond_ids"]:
			if not bond_id_to_template.has(String(bond_id)):
				return _failure("COMPOSITE_DEFINITION_STAGE_BOND_MAPPING_MISSING")
			included_bonds.append(String(bond_id_to_template[String(bond_id)]))
		var requirements_by_definition: Dictionary = {}
		for allocation in stage["material_allocations"]:
			var definition_id: String = String(allocation["definition_id"])
			requirements_by_definition[definition_id] = int(requirements_by_definition.get(definition_id, 0)) + int(allocation["quantity"])
		var requirements: Array = []
		var requirement_ids: Array = requirements_by_definition.keys()
		requirement_ids.sort()
		for definition_id in requirement_ids:
			requirements.append({
				"definition_id": String(definition_id),
				"quantity": int(requirements_by_definition[definition_id]),
			})
		stage_templates.append(StageTemplateScript.create(
			stage_template_id,
			int(stage["sequence_index"]),
			String(stage["display_name"]),
			String(stage["semantic_state"]),
			included_slots,
			included_bonds,
			requirements,
			Array(stage["required_capabilities"])
		))
	var definition: Dictionary = DefinitionScript.create(
		composite_definition_id,
		definition_version,
		display_name,
		"construct_root",
		root_display_name,
		part_slots,
		bond_templates,
		stage_templates,
		{
			"source_kind": DefinitionScript.SOURCE_BUILD_PLAN_COMPLETION,
			"source_construct_checksum": String(completed_snapshot["checksum"]),
			"source_build_plan_checksum": String(build_plan["checksum"]),
			"created_by": created_by,
		}
	)
	var validation: Dictionary = DefinitionScript.validate(definition)
	if not bool(validation.get("success", false)):
		return validation
	return _success({"definition": definition})


static func _leaf(value: String) -> String:
	var parts: PackedStringArray = value.split("/", false)
	return String(parts[-1]) if not parts.is_empty() else ""


static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
