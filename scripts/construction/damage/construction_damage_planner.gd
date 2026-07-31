extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const CapabilityCompilerScript = preload("res://scripts/construction/compilation/construction_capability_compiler.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const ItemMutationScript = preload("res://scripts/construction/item_graph/construction_item_mutation.gd")
const ConstructMutationScript = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const ItemPlannerScript = preload("res://scripts/construction/item_graph/construction_item_transaction_planner.gd")
const RequestScript = preload("res://scripts/construction/damage/construction_damage_request.gd")
const ComponentScript = preload("res://scripts/construction/damage/construction_damage_component.gd")
const RepairPlanScript = preload("res://scripts/construction/damage/construction_repair_plan.gd")
const TransactionScript = preload("res://scripts/construction/damage/construction_damage_transaction_plan.gd")

static func build_damage_plan(
	plan_id: String,
	operation_id: String,
	request: Dictionary,
	before_snapshot: Dictionary,
	item_projections: Array
) -> Dictionary:
	var request_validation := RequestScript.validate(request)
	if not bool(request_validation.get("success", false)):
		return request_validation
	var snapshot_validation := SnapshotScript.validate(before_snapshot)
	if not bool(snapshot_validation.get("success", false)):
		return snapshot_validation
	if String(before_snapshot["construct_id"]) != String(request["construct_id"]):
		return _failure("CONSTRUCTION_DAMAGE_REQUEST_CONSTRUCT_MISMATCH")
	if String(before_snapshot["checksum"]) != String(request["source_snapshot_checksum"]):
		return _failure("CONSTRUCTION_DAMAGE_SOURCE_CHECKSUM_MISMATCH")
	var items_result := _items_by_id(item_projections)
	if not bool(items_result.get("success", false)):
		return items_result
	var items: Dictionary = items_result["items"]
	var parts: Dictionary = {}
	for raw_part in before_snapshot["parts"]:
		var part: Dictionary = raw_part.duplicate(true)
		parts[String(part["part_id"])] = part
		if not items.has(String(part["item_instance_id"])):
			return _failure("CONSTRUCTION_DAMAGE_PART_ITEM_MISSING", {"part_id": part["part_id"]})
	if not parts.has(String(request["retained_part_id"])):
		return _failure("CONSTRUCTION_DAMAGE_RETAINED_PART_NOT_FOUND")
	for part_id in request["part_conditions"]:
		if not parts.has(String(part_id)):
			return _failure("CONSTRUCTION_DAMAGE_PART_NOT_FOUND", {"part_id": part_id})
		var part: Dictionary = parts[part_id].duplicate(true)
		var metadata: Dictionary = part["metadata"].duplicate(true)
		metadata["condition"] = String(request["part_conditions"][part_id])
		part["metadata"] = metadata
		parts[part_id] = part
	if _part_condition(parts[String(request["retained_part_id"])]) == "DESTROYED":
		return _failure("CONSTRUCTION_DAMAGE_RETAINED_PART_DESTROYED")
	var bonds: Dictionary = {}
	for raw_bond in before_snapshot["bonds"]:
		var bond: Dictionary = raw_bond.duplicate(true)
		bonds[String(bond["bond_id"])] = bond
	for bond_id in request["degraded_bond_ids"]:
		if not bonds.has(String(bond_id)):
			return _failure("CONSTRUCTION_DAMAGE_BOND_NOT_FOUND", {"bond_id": bond_id})
		var bond: Dictionary = bonds[bond_id].duplicate(true)
		bond["state"] = "DEGRADED"
		bonds[bond_id] = bond
	for bond_id in request["broken_bond_ids"]:
		if not bonds.has(String(bond_id)):
			return _failure("CONSTRUCTION_DAMAGE_BOND_NOT_FOUND", {"bond_id": bond_id})
		var bond: Dictionary = bonds[bond_id].duplicate(true)
		bond["state"] = "BROKEN"
		bonds[bond_id] = bond
	var component_rows := _connected_components(parts, bonds)
	if component_rows.is_empty():
		return _failure("CONSTRUCTION_DAMAGE_REMOVED_ALL_PARTS")
	var retained_index := -1
	for index in range(component_rows.size()):
		if component_rows[index].has(String(request["retained_part_id"])):
			retained_index = index
			break
	if retained_index < 0:
		return _failure("CONSTRUCTION_DAMAGE_RETAINED_COMPONENT_MISSING")
	var ordered_components: Array = [component_rows[retained_index]]
	for index in range(component_rows.size()):
		if index != retained_index:
			ordered_components.append(component_rows[index])
	var policy: Dictionary = request["salvage_policy"]
	if not bool(policy["allow_destroyed_salvage"]):
		for index in range(1, ordered_components.size()):
			for part_id in ordered_components[index]:
				if _part_condition(parts[part_id]) == "DESTROYED":
					return _failure("CONSTRUCTION_DAMAGE_DESTROYED_SALVAGE_FORBIDDEN", {"part_id": part_id})
	var required_split_targets := 0
	for index in range(1, ordered_components.size()):
		if ordered_components[index].size() >= int(policy["minimum_split_parts"]):
			required_split_targets += 1
	if request["split_targets"].size() < required_split_targets:
		return _failure("CONSTRUCTION_DAMAGE_SPLIT_TARGETS_EXHAUSTED")
	var source_id := String(before_snapshot["construct_id"])
	var source_root := String(before_snapshot["root_item_instance_id"])
	var components: Array = []
	var construct_mutations: Array = []
	var item_mutations: Array = []
	var split_construct_ids: Array = []
	var split_root_ids: Array = []
	var salvage_item_ids: Array = []
	var target_cursor := 0
	for index in range(ordered_components.size()):
		var part_ids: Array = ordered_components[index]
		var component_bonds := _internal_live_bonds(part_ids, bonds)
		var component_id := "damage-component/%s/%02d" % [String(request["damage_id"]).trim_prefix("damage/"), index]
		if index == 0:
			var after_source := _snapshot_for_component(before_snapshot, source_id, source_root, int(before_snapshot["state_revision"]) + 1, part_ids, component_bonds, request, "RETAINED")
			construct_mutations.append(ConstructMutationScript.create(ConstructMutationScript.OP_UPDATE, source_id, before_snapshot, after_source))
			components.append(ComponentScript.create(component_id, "RETAINED", source_id, source_root, part_ids, _ids(component_bonds, "bond_id")))
			_append_part_mutations(item_mutations, part_ids, parts, items, source_id, source_root, request, "RETAINED", policy)
		elif part_ids.size() >= int(policy["minimum_split_parts"]):
			var target: Dictionary = request["split_targets"][target_cursor]
			target_cursor += 1
			var new_construct_id := String(target["construct_id"])
			var new_root_id := String(target["root_item_instance_id"])
			var split_snapshot := _snapshot_for_component(before_snapshot, new_construct_id, new_root_id, 0, part_ids, component_bonds, request, "SPLIT_CONSTRUCT")
			construct_mutations.append(ConstructMutationScript.create(ConstructMutationScript.OP_CREATE, new_construct_id, {}, split_snapshot))
			var root_projection := ItemPlannerScript.create_root_projection(new_root_id, new_construct_id, "Split construct root")
			item_mutations.append(ItemMutationScript.create(ItemMutationScript.OP_CREATE, ItemMutationScript.PURPOSE_CREATE_ROOT, new_root_id, {}, root_projection))
			_append_part_mutations(item_mutations, part_ids, parts, items, new_construct_id, new_root_id, request, "SPLIT_CONSTRUCT", policy)
			components.append(ComponentScript.create(component_id, "SPLIT_CONSTRUCT", new_construct_id, new_root_id, part_ids, _ids(component_bonds, "bond_id")))
			split_construct_ids.append(new_construct_id)
			split_root_ids.append(new_root_id)
		else:
			_append_part_mutations(item_mutations, part_ids, parts, items, "", "", request, "SALVAGE", policy)
			components.append(ComponentScript.create(component_id, "SALVAGE", "", "", part_ids, _ids(component_bonds, "bond_id")))
			for part_id in part_ids:
				salvage_item_ids.append(String(parts[part_id]["item_instance_id"]))
	var required_item_ids: Array = []
	for part in before_snapshot["parts"]:
		required_item_ids.append(String(part["item_instance_id"]))
	var repair_plan := RepairPlanScript.create(
		"repair/%s" % String(request["damage_id"]).trim_prefix("damage/"),
		String(request["damage_id"]),
		before_snapshot,
		split_construct_ids,
		split_root_ids,
		required_item_ids,
		request["broken_bond_ids"],
		String(request["checksum"])
	)
	for mutation_index in range(construct_mutations.size()):
		var mutation: Dictionary = construct_mutations[mutation_index]
		if String(mutation["construct_id"]) != source_id:
			continue
		var source_after: Dictionary = mutation["after_snapshot"]
		var source_facets: Dictionary = source_after["compiled_facets"].duplicate(true)
		source_facets["damage_request_checksum"] = String(request["checksum"])
		source_facets["damage_components"] = components.duplicate(true)
		source_facets["damage_salvage_item_ids"] = _sorted_strings(salvage_item_ids)
		source_facets["damage_split_construct_ids"] = _sorted_strings(split_construct_ids)
		source_facets["damage_repair_plan"] = repair_plan.duplicate(true)
		var decorated_snapshot := SnapshotScript.create(
			String(source_after["construct_id"]), String(source_after["root_item_instance_id"]), int(source_after["state_revision"]),
			String(source_after["build_state"]), source_after["parts"], source_after["bonds"], source_facets
		)
		construct_mutations[mutation_index] = ConstructMutationScript.create(ConstructMutationScript.OP_UPDATE, source_id, before_snapshot, decorated_snapshot)
		break
	var plan := TransactionScript.create(plan_id, operation_id, TransactionScript.COMMAND_DAMAGE_SPLIT, source_id, construct_mutations, item_mutations, repair_plan)
	var validation := TransactionScript.validate(plan)
	if not bool(validation.get("success", false)):
		return validation
	return _success({
		"plan": plan,
		"components": components,
		"repair_plan": repair_plan,
		"salvage_item_ids": _sorted_strings(salvage_item_ids),
		"split_construct_ids": _sorted_strings(split_construct_ids),
	})

static func build_repair_plan(
	plan_id: String,
	operation_id: String,
	repair_plan: Dictionary,
	current_snapshots: Array,
	item_projections: Array
) -> Dictionary:
	var repair_validation := RepairPlanScript.validate(repair_plan)
	if not bool(repair_validation.get("success", false)):
		return repair_validation
	var snapshots: Dictionary = {}
	for snapshot in current_snapshots:
		var checked := SnapshotScript.validate(snapshot)
		if not bool(checked.get("success", false)):
			return checked
		snapshots[String(snapshot["construct_id"])] = snapshot.duplicate(true)
	var target_id := String(repair_plan["target_construct_id"])
	if not snapshots.has(target_id):
		return _failure("CONSTRUCTION_REPAIR_TARGET_NOT_FOUND")
	for split_id in repair_plan["split_construct_ids"]:
		if not snapshots.has(String(split_id)):
			return _failure("CONSTRUCTION_REPAIR_SPLIT_CONSTRUCT_NOT_FOUND", {"construct_id": split_id})
	var items_result := _items_by_id(item_projections)
	if not bool(items_result.get("success", false)):
		return items_result
	var items: Dictionary = items_result["items"]
	for item_id in repair_plan["required_part_item_ids"]:
		if not items.has(String(item_id)):
			return _failure("CONSTRUCTION_REPAIR_PART_ITEM_MISSING", {"item_instance_id": item_id})
	var current_target: Dictionary = snapshots[target_id]
	var template: Dictionary = repair_plan["target_snapshot_template"]
	var restored_snapshot := SnapshotScript.create(
		target_id,
		String(repair_plan["target_root_item_instance_id"]),
		int(current_target["state_revision"]) + 1,
		String(template["build_state"]),
		template["parts"],
		template["bonds"],
		template["compiled_facets"]
	)
	var construct_mutations: Array = [ConstructMutationScript.create(ConstructMutationScript.OP_UPDATE, target_id, current_target, restored_snapshot)]
	for split_id in repair_plan["split_construct_ids"]:
		construct_mutations.append(ConstructMutationScript.create(ConstructMutationScript.OP_DELETE, String(split_id), snapshots[String(split_id)], {}))
	var item_mutations: Array = []
	var target_root := String(repair_plan["target_root_item_instance_id"])
	for part in template["parts"]:
		var item_id := String(part["item_instance_id"])
		var before: Dictionary = items[item_id]
		var after: Dictionary = before.duplicate(true)
		after["relation"] = ProjectionScript.attachment_relation(target_id, target_root, String(part["part_id"]))
		var components: Dictionary = after["components"].duplicate(true)
		components["condition"] = "INTACT"
		after["components"] = components
		after["revision"] = int(before["revision"]) + 1
		if UtilsScript.canonical_json(before) != UtilsScript.canonical_json(after):
			item_mutations.append(ItemMutationScript.create(ItemMutationScript.OP_UPDATE, ItemMutationScript.PURPOSE_REPAIR_PART, item_id, before, after))
	for root_item_id in repair_plan["split_root_item_ids"]:
		if not items.has(String(root_item_id)):
			return _failure("CONSTRUCTION_REPAIR_SPLIT_ROOT_NOT_FOUND", {"item_instance_id": root_item_id})
		item_mutations.append(ItemMutationScript.create(ItemMutationScript.OP_DELETE, ItemMutationScript.PURPOSE_DESTROY_ROOT, String(root_item_id), items[String(root_item_id)], {}))
	var plan := TransactionScript.create(plan_id, operation_id, TransactionScript.COMMAND_REPAIR_SPLIT, target_id, construct_mutations, item_mutations, repair_plan)
	var validation := TransactionScript.validate(plan)
	if not bool(validation.get("success", false)):
		return validation
	return _success({"plan": plan, "restored_snapshot": restored_snapshot})

static func _snapshot_for_component(before: Dictionary, construct_id: String, root_id: String, revision: int, part_ids: Array, bonds: Array, request: Dictionary, outcome: String) -> Dictionary:
	var part_map := {}
	for part in before["parts"]:
		part_map[String(part["part_id"])] = part
	var selected_parts: Array = []
	for part_id in part_ids:
		var part: Dictionary = part_map[part_id].duplicate(true)
		if request["part_conditions"].has(part_id):
			var metadata: Dictionary = part["metadata"].duplicate(true)
			metadata["condition"] = String(request["part_conditions"][part_id])
			part["metadata"] = metadata
		selected_parts.append(part)
	var compiled_result: Dictionary = CapabilityCompilerScript.compile(selected_parts, bonds)
	var facets: Dictionary = Dictionary(compiled_result.get("compiled", {})).duplicate(true)
	var source_facets: Dictionary = before["compiled_facets"]
	for raw_key in source_facets.keys():
		var key: String = String(raw_key)
		if key.begins_with("composite_") and key != "composite_exposed_ports":
			facets[key] = source_facets[raw_key]
	if source_facets.get("composite_exposed_ports", []) is Array:
		var member_ids: Dictionary = {}
		for part_id in part_ids:
			member_ids[part_id] = true
		var filtered_ports: Array = []
		for port in source_facets.get("composite_exposed_ports", []):
			if port is Dictionary and member_ids.has(String(port.get("part_id", ""))):
				filtered_ports.append(Dictionary(port).duplicate(true))
		facets["composite_exposed_ports"] = filtered_ports
	if outcome == "RETAINED" and source_facets.has("fabrication_runtime"):
		facets["fabrication_runtime"] = Dictionary(source_facets["fabrication_runtime"]).duplicate(true)
	facets["source_compiled_facets_checksum"] = UtilsScript.payload_hash(source_facets)
	facets["damage_origin"] = {
		"damage_id": String(request["damage_id"]),
		"source_construct_id": String(before["construct_id"]),
		"source_snapshot_checksum": String(before["checksum"]),
		"damage_request_checksum": String(request["checksum"]),
		"outcome": outcome,
	}
	return SnapshotScript.create(construct_id, root_id, revision, "DAMAGED", selected_parts, bonds, facets)

static func _append_part_mutations(output: Array, part_ids: Array, parts: Dictionary, items: Dictionary, target_construct_id: String, target_root_id: String, request: Dictionary, outcome: String, policy: Dictionary) -> void:
	for part_id in part_ids:
		var part: Dictionary = parts[part_id]
		var item_id := String(part["item_instance_id"])
		var before: Dictionary = items[item_id]
		var after: Dictionary = before.duplicate(true)
		var components: Dictionary = after["components"].duplicate(true)
		if request["part_conditions"].has(part_id):
			components["condition"] = String(request["part_conditions"][part_id])
		after["components"] = components
		var purpose := ""
		match outcome:
			"RETAINED":
				if UtilsScript.canonical_json(before["components"]) == UtilsScript.canonical_json(after["components"]):
					continue
				purpose = ItemMutationScript.PURPOSE_APPLY_DAMAGE
			"SPLIT_CONSTRUCT":
				after["relation"] = ProjectionScript.attachment_relation(target_construct_id, target_root_id, part_id)
				purpose = ItemMutationScript.PURPOSE_REBIND_SPLIT_PART
			"SALVAGE":
				after["relation"] = policy["salvage_relation"].duplicate(true)
				purpose = ItemMutationScript.PURPOSE_SALVAGE_PART
		after["revision"] = int(before["revision"]) + 1
		output.append(ItemMutationScript.create(ItemMutationScript.OP_UPDATE, purpose, item_id, before, after))

static func _connected_components(parts: Dictionary, bonds: Dictionary) -> Array:
	var active: Dictionary = {}
	for part_id in parts:
		if _part_condition(parts[part_id]) != "DESTROYED":
			active[part_id] = true
	var adjacency: Dictionary = {}
	for part_id in active:
		adjacency[part_id] = []
	for bond in bonds.values():
		if String(bond["state"]) == "BROKEN":
			continue
		var a := String(bond["part_a_id"])
		var b := String(bond["part_b_id"])
		if active.has(a) and active.has(b):
			adjacency[a].append(b)
			adjacency[b].append(a)
	var remaining := active.keys()
	remaining.sort()
	var visited := {}
	var components: Array = []
	for start in remaining:
		if visited.has(start):
			continue
		var stack: Array = [start]
		var component: Array = []
		visited[start] = true
		while not stack.is_empty():
			var current = stack.pop_back()
			component.append(current)
			var neighbors: Array = adjacency[current].duplicate()
			neighbors.sort()
			for neighbor in neighbors:
				if not visited.has(neighbor):
					visited[neighbor] = true
					stack.append(neighbor)
		component.sort()
		components.append(component)
	for part_id in parts:
		if _part_condition(parts[part_id]) == "DESTROYED":
			components.append([part_id])
	components.sort_custom(func(a,b): return String(a[0]) < String(b[0]))
	return components

static func _internal_live_bonds(part_ids: Array, bonds: Dictionary) -> Array:
	var members := {}
	for part_id in part_ids:
		members[part_id] = true
	var output: Array = []
	for bond in bonds.values():
		if String(bond["state"]) != "BROKEN" and members.has(String(bond["part_a_id"])) and members.has(String(bond["part_b_id"])):
			output.append(bond.duplicate(true))
	output.sort_custom(func(a,b): return String(a["bond_id"]) < String(b["bond_id"]))
	return output

static func _items_by_id(values: Array) -> Dictionary:
	var items := {}
	for value in values:
		if typeof(value) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_DAMAGE_ITEM_PROJECTION")
		var checked := ProjectionScript.validate(value)
		if not bool(checked.get("success", false)):
			return checked
		var item_id := String(value["item_instance_id"])
		if items.has(item_id):
			return _failure("DUPLICATE_CONSTRUCTION_DAMAGE_ITEM_PROJECTION")
		items[item_id] = value.duplicate(true)
	return _success({"items": items})

static func _part_condition(part: Dictionary) -> String:
	return String(part.get("metadata", {}).get("condition", "INTACT"))
static func _ids(values: Array, field: String) -> Array:
	var output: Array = []
	for value in values:
		output.append(String(value[field]))
	output.sort()
	return output
static func _sorted_strings(values: Array) -> Array:
	var output := values.duplicate(); output.sort(); return output
static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result
static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	var result := {"success": false, "error_code": code, "message": code}
	for key in details:
		result[key] = details[key]
	return result
