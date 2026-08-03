extends RefCounted

const DefinitionScript = preload("res://scripts/construction/composites/construction_composite_definition.gd")
const PartSlotScript = preload("res://scripts/construction/composites/composite_part_slot.gd")
const ParameterScript = preload("res://scripts/construction/composites/composite_parameter_definition.gd")
const InstantiationScript = preload("res://scripts/construction/composites/construction_composite_instantiation.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const CapabilityCompilerScript = preload("res://scripts/construction/compilation/construction_capability_compiler.gd")
const BuildStageScript = preload("res://scripts/construction/build/construction_build_stage.gd")
const BuildPlanScript = preload("res://scripts/construction/build/construction_build_plan.gd")


static func compile(
	definition: Dictionary,
	instantiation_id: String,
	build_plan_id: String,
	construct_id: String,
	root_item_instance_id: String,
	ghost_relation: Dictionary,
	available_source_projections: Array,
	parameter_values: Dictionary = {}
) -> Dictionary:
	var definition_validation: Dictionary = DefinitionScript.validate(definition)
	if not bool(definition_validation.get("success", false)):
		return definition_validation
	if String(definition["root_definition_id"]) != "construct_root":
		return _failure("UNSUPPORTED_COMPOSITE_ROOT_DEFINITION")
	var parameter_result: Dictionary = _resolve_parameter_values(definition, parameter_values)
	if not bool(parameter_result.get("success", false)):
		return parameter_result
	var resolved_parameter_values: Dictionary = parameter_result["parameter_values"]
	for pair in [
		[instantiation_id, "composite-instantiation/"],
		[build_plan_id, "build-plan/"],
		[construct_id, "construct/"],
		[root_item_instance_id, "item/"],
	]:
		if not _is_identifier(String(pair[0]), String(pair[1])):
			return _failure("INVALID_COMPOSITE_COMPILATION_IDENTITY")
	if not _is_path_safe_instance_namespace(construct_id):
		return _failure("COMPOSITE_INSTANCE_NAMESPACE_NOT_PATH_SAFE")
	var relation_validation: Dictionary = ProjectionScript.validate_relation(ghost_relation)
	if not bool(relation_validation.get("success", false)):
		return relation_validation
	if String(ghost_relation.get("kind", "")) != ProjectionScript.WORLD:
		return _failure("COMPOSITE_BUILD_GHOST_MUST_USE_WORLD_RELATION")
	var source_result: Dictionary = _source_projection_map(available_source_projections)
	if not bool(source_result.get("success", false)):
		return source_result
	var sources: Dictionary = source_result["sources"]
	if sources.has(root_item_instance_id):
		return _failure("COMPOSITE_BUILD_ROOT_ALREADY_EXISTS")
	var used_item_ids: Dictionary = {}
	var selected_source_ids: Dictionary = {}
	var slot_to_part: Dictionary = {}
	var slot_to_item: Dictionary = {}
	var part_bindings: Array = []
	var parts: Array = []
	for slot in definition["part_slots"]:
		var selected_id: String = _select_part_source(slot, sources, used_item_ids)
		if selected_id.is_empty():
			return _failure("COMPOSITE_PART_SLOT_UNSATISFIED", {"slot_id": String(slot["slot_id"])})
		used_item_ids[selected_id] = true
		selected_source_ids[selected_id] = true
		var part_id: String = _part_id_for(construct_id, String(slot["slot_id"]))
		slot_to_part[String(slot["slot_id"])] = part_id
		slot_to_item[String(slot["slot_id"])] = selected_id
		parts.append(PartScript.create(
			part_id,
			selected_id,
			String(slot["part_kind"]),
			String(slot["role"]),
			float(slot["mass_kg"]),
			Array(slot["local_position_m"]),
			Dictionary(slot["metadata"])
		))
		part_bindings.append({
			"slot_id": String(slot["slot_id"]),
			"item_instance_id": selected_id,
			"part_id": part_id,
		})
	var template_to_bond: Dictionary = {}
	var bonds: Array = []
	for bond_template in definition["bond_templates"]:
		var template_id: String = String(bond_template["bond_template_id"])
		var bond_id: String = _bond_id_for(construct_id, template_id)
		template_to_bond[template_id] = bond_id
		bonds.append(BondScript.create(
			bond_id,
			String(slot_to_part[String(bond_template["part_a_slot_id"])]),
			String(slot_to_part[String(bond_template["part_b_slot_id"])]),
			String(bond_template["bond_kind"]),
			float(bond_template["strength_n"]),
			"INTACT",
			Dictionary(bond_template["metadata"])
		))
	var compiled_result: Dictionary = CapabilityCompilerScript.compile(parts, bonds)
	if not bool(compiled_result.get("success", false)):
		return compiled_result
	var compiled_facets: Dictionary = Dictionary(compiled_result["compiled"]).duplicate(true)
	compiled_facets["composite_definition_id"] = String(definition["composite_definition_id"])
	compiled_facets["composite_definition_version"] = int(definition["definition_version"])
	compiled_facets["composite_definition_checksum"] = String(definition["checksum"])
	compiled_facets["composite_instantiation_id"] = instantiation_id
	compiled_facets["composite_parameters"] = resolved_parameter_values.duplicate(true)
	var compiled_ports: Array = []
	for port in definition["exposed_ports"]:
		compiled_ports.append({
			"port_id": String(port["port_id"]),
			"part_id": String(slot_to_part[String(port["slot_id"])]),
			"port_kind": String(port["port_kind"]),
			"local_position_m": Array(port["local_position_m"]).duplicate(true),
			"metadata": Dictionary(port["metadata"]).duplicate(true),
		})
	compiled_facets["composite_exposed_ports"] = compiled_ports
	var target_snapshot: Dictionary = SnapshotScript.create(
		construct_id,
		root_item_instance_id,
		0,
		"OPERATIONAL",
		parts,
		bonds,
		compiled_facets
	)
	var target_validation: Dictionary = SnapshotScript.validate(target_snapshot)
	if not bool(target_validation.get("success", false)):
		return target_validation
	var allocated_by_item: Dictionary = {}
	var material_bindings: Array = []
	var stages: Array = []
	for stage_template in definition["stage_templates"]:
		var allocations: Array = []
		for requirement in stage_template["material_requirements"]:
			var allocated: Dictionary = _allocate_material_requirement(
				String(requirement["definition_id"]),
				int(requirement["quantity"]),
				sources,
				used_item_ids,
				allocated_by_item
			)
			if not bool(allocated.get("success", false)):
				return allocated
			for allocation in allocated["allocations"]:
				allocations.append(allocation)
				var item_id: String = String(allocation["item_instance_id"])
				selected_source_ids[item_id] = true
				material_bindings.append({
					"stage_template_id": String(stage_template["stage_template_id"]),
					"definition_id": String(allocation["definition_id"]),
					"item_instance_id": item_id,
					"quantity": int(allocation["quantity"]),
				})
		var included_part_ids: Array = []
		for slot_id in stage_template["included_part_slot_ids"]:
			included_part_ids.append(String(slot_to_part[String(slot_id)]))
		var included_bond_ids: Array = []
		for template_id in stage_template["included_bond_template_ids"]:
			included_bond_ids.append(String(template_to_bond[String(template_id)]))
		stages.append(BuildStageScript.create(
			_stage_id_for(build_plan_id, String(stage_template["stage_template_id"])),
			int(stage_template["sequence_index"]),
			String(stage_template["display_name"]),
			String(stage_template["semantic_state"]),
			included_part_ids,
			included_bond_ids,
			allocations,
			Array(stage_template["required_capabilities"])
		))
	var selected_sources: Array = []
	var selected_ids: Array = selected_source_ids.keys()
	selected_ids.sort()
	for item_id in selected_ids:
		selected_sources.append(Dictionary(sources[item_id]).duplicate(true))
	var build_plan: Dictionary = BuildPlanScript.create(
		build_plan_id,
		String(definition["root_display_name"]),
		ghost_relation,
		target_snapshot,
		selected_sources,
		stages
	)
	var plan_validation: Dictionary = BuildPlanScript.validate(build_plan)
	if not bool(plan_validation.get("success", false)):
		return plan_validation
	var instantiation: Dictionary = InstantiationScript.create(
		instantiation_id,
		definition,
		build_plan,
		part_bindings,
		material_bindings,
		resolved_parameter_values
	)
	var instantiation_validation: Dictionary = InstantiationScript.validate_against(instantiation, definition, build_plan)
	if not bool(instantiation_validation.get("success", false)):
		return instantiation_validation
	return _success({
		"build_plan": build_plan,
		"instantiation": instantiation,
		"part_bindings": instantiation["part_bindings"].duplicate(true),
		"material_bindings": instantiation["material_bindings"].duplicate(true),
		"parameter_values": resolved_parameter_values.duplicate(true),
		"exposed_ports": compiled_ports.duplicate(true),
	})


static func _resolve_parameter_values(definition: Dictionary, overrides: Dictionary) -> Dictionary:
	if typeof(overrides) != TYPE_DICTIONARY:
		return _failure("INVALID_COMPOSITE_PARAMETER_OVERRIDES")
	var parameters: Dictionary = DefinitionScript.parameter_map(definition)
	for raw_parameter_id in overrides.keys():
		var parameter_id: String = String(raw_parameter_id)
		if not parameters.has(parameter_id):
			return _failure("UNKNOWN_COMPOSITE_PARAMETER_OVERRIDE", {"parameter_id": parameter_id})
	var resolved: Dictionary = {}
	var parameter_ids: Array = parameters.keys()
	parameter_ids.sort()
	for raw_parameter_id in parameter_ids:
		var parameter_id: String = String(raw_parameter_id)
		var parameter: Dictionary = parameters[parameter_id]
		var raw_value = overrides.get(parameter_id, parameter["default_value"])
		var validation: Dictionary = ParameterScript.validate_value(parameter, raw_value)
		if not bool(validation.get("success", false)):
			return validation
		resolved[parameter_id] = ParameterScript.normalize_value(parameter, raw_value)
	return _success({"parameter_values": resolved})


static func _select_part_source(slot: Dictionary, sources: Dictionary, used_item_ids: Dictionary) -> String:
	var ids: Array = sources.keys()
	ids.sort()
	for raw_id in ids:
		var item_id: String = String(raw_id)
		if used_item_ids.has(item_id):
			continue
		var projection: Dictionary = sources[item_id]
		if not _is_transferable(projection):
			continue
		if PartSlotScript.matches_projection(slot, projection):
			return item_id
	return ""


static func _allocate_material_requirement(
	definition_id: String,
	quantity: int,
	sources: Dictionary,
	part_item_ids: Dictionary,
	allocated_by_item: Dictionary
) -> Dictionary:
	var remaining: int = quantity
	var allocations: Array = []
	var ids: Array = sources.keys()
	ids.sort()
	for raw_id in ids:
		var item_id: String = String(raw_id)
		if part_item_ids.has(item_id):
			continue
		var projection: Dictionary = sources[item_id]
		if String(projection["definition_id"]) != definition_id or not _is_transferable(projection):
			continue
		var already_allocated: int = int(allocated_by_item.get(item_id, 0))
		var available: int = int(projection["quantity"]) - already_allocated - 1
		if available <= 0:
			continue
		var take: int = mini(remaining, available)
		if take <= 0:
			continue
		allocations.append({
			"item_instance_id": item_id,
			"definition_id": definition_id,
			"quantity": take,
		})
		allocated_by_item[item_id] = already_allocated + take
		remaining -= take
		if remaining == 0:
			break
	if remaining > 0:
		return _failure("COMPOSITE_MATERIAL_REQUIREMENT_UNSATISFIED", {
			"definition_id": definition_id,
			"required_quantity": quantity,
			"missing_quantity": remaining,
		})
	return _success({"allocations": allocations})


static func _source_projection_map(values: Array) -> Dictionary:
	var sources: Dictionary = {}
	for raw in values:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_COMPOSITE_SOURCE_PROJECTION")
		var projection: Dictionary = raw
		var validation: Dictionary = ProjectionScript.validate(projection)
		if not bool(validation.get("success", false)):
			return validation
		var item_id: String = String(projection["item_instance_id"])
		if sources.has(item_id):
			return _failure("DUPLICATE_COMPOSITE_SOURCE_PROJECTION")
		sources[item_id] = projection.duplicate(true)
	return _success({"sources": sources})


static func _is_transferable(projection: Dictionary) -> bool:
	return not [ProjectionScript.ATTACHMENT, ProjectionScript.DESTROYED].has(
		String(projection.get("relation", {}).get("kind", ""))
	)


static func _part_id_for(construct_id: String, slot_id: String) -> String:
	return "part/%s/%s" % [construct_id.trim_prefix("construct/"), slot_id.trim_prefix("slot/")]


static func _bond_id_for(construct_id: String, template_id: String) -> String:
	return "bond/%s/%s" % [construct_id.trim_prefix("construct/"), template_id.trim_prefix("bond-template/")]


static func _stage_id_for(build_plan_id: String, template_id: String) -> String:
	return "stage/%s/%s" % [build_plan_id.trim_prefix("build-plan/"), template_id.trim_prefix("stage-template/")]


static func _is_path_safe_instance_namespace(construct_id: String) -> bool:
	var tail: String = construct_id.trim_prefix("construct/")
	if tail.is_empty() or tail.contains("//") or tail != tail.to_lower():
		return false
	for segment in tail.split("/", true):
		if segment.is_empty():
			return false
		for character in segment:
			if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_":
				return false
	return true


static func _is_identifier(value: String, prefix: String) -> bool:
	return value.begins_with(prefix) and value.length() > prefix.length() and value == value.strip_edges()


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
