extends RefCounted

const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const InstanceScript = preload("res://scripts/construction/parametric/construction_parametric_member_instance.gd")
const RepairPlanScript = preload("res://scripts/construction/parametric/construction_parametric_repair_plan.gd")
const PlanScript = preload("res://scripts/construction/parametric/construction_parametric_segmentation_plan.gd")

static func split(plan_id: String, repair_plan_id: String, parent_instance: Dictionary, cut_offsets_m: Array, child_member_instance_ids: Array, child_item_instance_ids: Array) -> Dictionary:
	var checked := InstanceScript.validate(parent_instance)
	if not bool(checked.get("success", false)): return checked
	if cut_offsets_m.is_empty(): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_CUTS_REQUIRED")
	var segment_count := cut_offsets_m.size() + 1
	if child_member_instance_ids.size() != segment_count or child_item_instance_ids.size() != segment_count: return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_SEGMENT_ID_COUNT_MISMATCH")
	var parent_length := float(parent_instance["geometry"]["length_m"])
	var boundaries: Array = [0.0]
	var previous := 0.0
	for raw_cut in cut_offsets_m:
		if not ParametricUtils.positive_number(raw_cut): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_CUT_OFFSET")
		var cut := ParametricUtils.metric(float(raw_cut))
		if cut <= previous or cut >= parent_length: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_CUT_OFFSET")
		boundaries.append(cut); previous = cut
	boundaries.append(parent_length)
	var rows: Array = []; var segments: Array = []
	var remaining_mass := float(parent_instance["mass_kg"])
	var remaining_volume := float(parent_instance["geometry"]["volume_m3"])
	var remaining_usage: Dictionary = {}
	for usage in parent_instance["material_usage"]:
		remaining_usage[String(usage["material_id"])] = {"mass_kg": float(usage["mass_kg"]), "volume_m3": float(usage["volume_m3"])}
	for index in range(segment_count):
		var start := float(boundaries[index]); var finish := float(boundaries[index + 1]); var length := ParametricUtils.metric(finish - start)
		var ratio := length / parent_length
		var is_last := index == segment_count - 1
		var child_mass := ParametricUtils.metric(remaining_mass if is_last else float(parent_instance["mass_kg"]) * ratio)
		var child_volume := ParametricUtils.metric(remaining_volume if is_last else float(parent_instance["geometry"]["volume_m3"]) * ratio)
		remaining_mass = ParametricUtils.metric(remaining_mass - child_mass); remaining_volume = ParametricUtils.metric(remaining_volume - child_volume)
		var usage_rows: Array = []
		for parent_usage in parent_instance["material_usage"]:
			var material_id := String(parent_usage["material_id"]); var remaining: Dictionary = remaining_usage[material_id]
			var usage_mass := ParametricUtils.metric(float(remaining["mass_kg"]) if is_last else float(parent_usage["mass_kg"]) * ratio)
			var usage_volume := ParametricUtils.metric(float(remaining["volume_m3"]) if is_last else float(parent_usage["volume_m3"]) * ratio)
			remaining["mass_kg"] = ParametricUtils.metric(float(remaining["mass_kg"]) - usage_mass); remaining["volume_m3"] = ParametricUtils.metric(float(remaining["volume_m3"]) - usage_volume); remaining_usage[material_id] = remaining
			var unit_mass := float(parent_usage["mass_kg"]) / float(parent_usage["stock_units"])
			usage_rows.append({"material_id": material_id, "stock_definition_id": String(parent_usage["stock_definition_id"]), "volume_m3": usage_volume, "mass_kg": usage_mass, "stock_units": maxi(1, int(ceil(usage_mass / unit_mass)))})
		var geometry: Dictionary = Dictionary(parent_instance["geometry"]).duplicate(true)
		geometry["length_m"] = length
		geometry["volume_m3"] = child_volume
		geometry["surface_area_m2"] = ParametricUtils.metric(float(parent_instance["geometry"]["surface_area_m2"]) * ratio)
		var box: Array = Array(geometry["bounding_box_m"]).duplicate(true); box[0] = length; geometry["bounding_box_m"] = box
		var parameters: Dictionary = Dictionary(parent_instance["parameter_values"]).duplicate(true); parameters["length_m"] = length
		var provenance: Dictionary = Dictionary(parent_instance["provenance"]).duplicate(true)
		provenance["segmentation"] = {"parent_member_instance_id": String(parent_instance["member_instance_id"]), "parent_checksum": String(parent_instance["checksum"]), "segment_index": index, "start_offset_m": start, "end_offset_m": finish}
		var child := parent_instance.duplicate(true)
		child["member_instance_id"] = String(child_member_instance_ids[index]); child["item_instance_id"] = String(child_item_instance_ids[index]); child["parameter_values"] = parameters; child["material_usage"] = usage_rows; child["geometry"] = geometry; child["mass_kg"] = child_mass; child["provenance"] = provenance; child["checksum"] = InstanceScript.compute_checksum(child)
		checked = InstanceScript.validate(child); if not bool(checked.get("success", false)): return checked
		segments.append(child); rows.append(PlanScript.segment_row(index, start, finish, child))
	var repair_plan := RepairPlanScript.create(repair_plan_id, parent_instance, segments)
	checked = RepairPlanScript.validate(repair_plan); if not bool(checked.get("success", false)): return checked
	var plan := PlanScript.create(plan_id, parent_instance, cut_offsets_m, rows, repair_plan)
	checked = PlanScript.validate(plan); if not bool(checked.get("success", false)): return checked
	return ParametricUtils.success({"plan": plan, "segments": segments, "repair_plan": repair_plan})
