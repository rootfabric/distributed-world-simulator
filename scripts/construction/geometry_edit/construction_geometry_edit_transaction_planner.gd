extends RefCounted

const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const InstanceScript = preload("res://scripts/construction/parametric/construction_parametric_member_instance.gd")
const RequestScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_request.gd")
const RecordScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_record.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const ItemMutationScript = preload("res://scripts/construction/item_graph/construction_item_mutation.gd")
const ConstructMutationScript = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const TransactionScript = preload("res://scripts/construction/item_graph/construction_item_transaction_plan.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")

static func plan(plan_id: String, request: Dictionary, before_projection: Dictionary, before_snapshot: Dictionary, compiler_result: Dictionary) -> Dictionary:
	var checked := RequestScript.validate(request); if not bool(checked.get("success", false)): return checked
	checked = ProjectionScript.validate(before_projection); if not bool(checked.get("success", false)): return checked
	checked = SnapshotScript.validate(before_snapshot); if not bool(checked.get("success", false)): return checked
	var updated_instance: Dictionary = compiler_result.get("updated_instance", {})
	checked = InstanceScript.validate(updated_instance); if not bool(checked.get("success", false)): return checked
	if String(before_projection["item_instance_id"]) != String(request["item_instance_id"]) or int(before_projection["revision"]) != int(request["expected_item_revision"]): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_ITEM_PRECONDITION_MISMATCH")
	if String(before_snapshot["construct_id"]) != String(request["construct_id"]) or String(before_snapshot["checksum"]) != String(request["expected_construct_checksum"]): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_CONSTRUCT_PRECONDITION_MISMATCH")
	var relation: Dictionary = before_projection["relation"]
	if String(relation.get("kind", "")) != ProjectionScript.ATTACHMENT or String(relation.get("assembly_id", "")) != String(request["construct_id"]) or String(relation.get("socket_id", "")) != String(request["part_id"]): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_TARGET_NOT_ATTACHED")
	var after_projection := before_projection.duplicate(true)
	var components: Dictionary = Dictionary(after_projection["components"]).duplicate(true)
	components["parametric_member"] = updated_instance.duplicate(true)
	after_projection["components"] = components
	after_projection["revision"] = int(before_projection["revision"]) + 1
	checked = ProjectionScript.validate(after_projection); if not bool(checked.get("success", false)): return checked
	var after_parts: Array = []; var target_found := false
	for part in before_snapshot["parts"]:
		var next_part: Dictionary = Dictionary(part).duplicate(true)
		if String(part["part_id"]) == String(request["part_id"]):
			if String(part["item_instance_id"]) != String(request["item_instance_id"]): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_PART_ITEM_MISMATCH")
			target_found = true
			var metadata: Dictionary = Dictionary(part["metadata"]).duplicate(true)
			metadata["parametric_member_checksum"] = String(updated_instance["checksum"])
			metadata["geometry"] = Dictionary(updated_instance["geometry"]).duplicate(true)
			metadata["material_usage"] = Array(updated_instance["material_usage"]).duplicate(true)
			metadata["local_geometry_edit_state"] = Dictionary(compiler_result["after_state"]).duplicate(true)
			next_part = PartScript.create(String(part["part_id"]), String(part["item_instance_id"]), String(part["part_kind"]), String(part["role"]), float(updated_instance["mass_kg"]), Array(part["local_position_m"]).duplicate(true), metadata)
			checked = PartScript.validate(next_part); if not bool(checked.get("success", false)): return checked
		after_parts.append(next_part)
	if not target_found: return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_PART_NOT_FOUND")
	var facets: Dictionary = Dictionary(before_snapshot["compiled_facets"]).duplicate(true)
	var record := RecordScript.create(request, Dictionary(before_projection["components"]["parametric_member"]), updated_instance, compiler_result["before_state"], compiler_result["after_state"], int(before_projection["revision"]), String(before_snapshot["checksum"]), int(before_snapshot["state_revision"]) + 1, compiler_result["material_deltas"])
	var edits: Dictionary = Dictionary(facets.get("geometry_edits", {})).duplicate(true)
	edits[String(request["operation_id"])] = record.duplicate(true)
	facets["geometry_edits"] = edits
	var after_snapshot := SnapshotScript.create(String(before_snapshot["construct_id"]), String(before_snapshot["root_item_instance_id"]), int(before_snapshot["state_revision"]) + 1, String(before_snapshot["build_state"]), after_parts, Array(before_snapshot["bonds"]).duplicate(true), facets)
	checked = RecordScript.validate(record); if not bool(checked.get("success", false)): return checked
	checked = SnapshotScript.validate(after_snapshot); if not bool(checked.get("success", false)): return checked
	var item_mutation := ItemMutationScript.create(ItemMutationScript.OP_UPDATE, ItemMutationScript.PURPOSE_EDIT_PARAMETRIC_MEMBER, String(request["item_instance_id"]), before_projection, after_projection)
	checked = ItemMutationScript.validate(item_mutation); if not bool(checked.get("success", false)): return checked
	var construct_mutation := ConstructMutationScript.create(ConstructMutationScript.OP_UPDATE, String(request["construct_id"]), before_snapshot, after_snapshot)
	checked = ConstructMutationScript.validate(construct_mutation); if not bool(checked.get("success", false)): return checked
	var transaction := TransactionScript.create(plan_id, String(request["operation_id"]), TransactionScript.COMMAND_EDIT_PARAMETRIC_MEMBER, construct_mutation, [item_mutation])
	checked = TransactionScript.validate(transaction); if not bool(checked.get("success", false)): return checked
	return ParametricUtils.success({"plan": transaction, "record": record, "after_projection": after_projection, "after_snapshot": after_snapshot})
