extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const InstanceScript = preload("res://scripts/construction/parametric/construction_parametric_member_instance.gd")
const RepairPlanScript = preload("res://scripts/construction/parametric/construction_parametric_repair_plan.gd")

const SCHEMA := "planet_simulator.construction_parametric_segmentation_plan.v1"
const FIELDS: Array[String] = ["schema", "plan_id", "parent_instance", "cut_offsets_m", "segments", "repair_plan", "checksum"]
const SEGMENT_FIELDS: Array[String] = ["segment_index", "start_offset_m", "end_offset_m", "member_instance"]

static func create(plan_id: String, parent_instance: Dictionary, cut_offsets_m: Array, segments: Array, repair_plan: Dictionary) -> Dictionary:
	var value := {"schema": SCHEMA, "plan_id": plan_id, "parent_instance": parent_instance.duplicate(true), "cut_offsets_m": cut_offsets_m.duplicate(true), "segments": segments.duplicate(true), "repair_plan": repair_plan.duplicate(true), "checksum": ""}
	value["checksum"] = compute_checksum(value)
	return value

static func segment_row(segment_index: int, start_offset_m: float, end_offset_m: float, member_instance: Dictionary) -> Dictionary:
	return {"segment_index": segment_index, "start_offset_m": ParametricUtils.metric(start_offset_m), "end_offset_m": ParametricUtils.metric(end_offset_m), "member_instance": member_instance.duplicate(true)}

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return ParametricUtils.failure("UNSUPPORTED_CONSTRUCTION_PARAMETRIC_SEGMENTATION_PLAN_SCHEMA")
	if not ParametricUtils.path_id(String(value.get("plan_id", "")), "parametric-segmentation/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_SEGMENTATION_PLAN_ID")
	if typeof(value.get("parent_instance")) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_SEGMENTATION_PARENT")
	var checked := InstanceScript.validate(value["parent_instance"]); if not bool(checked.get("success", false)): return checked
	if typeof(value.get("cut_offsets_m")) != TYPE_ARRAY or Array(value["cut_offsets_m"]).is_empty(): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_CUTS_REQUIRED")
	var parent_length := float(value["parent_instance"]["geometry"]["length_m"]); var previous := 0.0
	for cut in value["cut_offsets_m"]:
		if not ParametricUtils.positive_number(cut) or float(cut) <= previous or float(cut) >= parent_length: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_CUT_OFFSET")
		previous = float(cut)
	if typeof(value.get("segments")) != TYPE_ARRAY or Array(value["segments"]).size() != Array(value["cut_offsets_m"]).size() + 1: return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_SEGMENT_COUNT_MISMATCH")
	var total_mass := 0.0; var total_volume := 0.0; var total_usage := {}; var expected_start := 0.0; var instance_ids := {}; var item_ids := {}
	for index in range(value["segments"].size()):
		var row = value["segments"][index]
		if typeof(row) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_SEGMENT")
		var row_exact := UtilsScript.validate_exact_fields(row, SEGMENT_FIELDS); if not bool(row_exact.get("success", false)): return row_exact
		if not UtilsScript.is_json_integer(row.get("segment_index")) or int(row["segment_index"]) != index: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_SEGMENT_INDEX")
		if not ParametricUtils.non_negative_number(row.get("start_offset_m")) or not ParametricUtils.positive_number(row.get("end_offset_m")): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_SEGMENT_RANGE")
		if not ParametricUtils.nearly_equal(float(row["start_offset_m"]), expected_start) or float(row["end_offset_m"]) <= float(row["start_offset_m"]): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_SEGMENT_RANGE_GAP")
		if typeof(row.get("member_instance")) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_SEGMENT_INSTANCE")
		checked = InstanceScript.validate(row["member_instance"]); if not bool(checked.get("success", false)): return checked
		var instance: Dictionary = row["member_instance"]
		if String(instance["member_definition_id"]) != String(value["parent_instance"]["member_definition_id"]) or String(instance["definition_checksum"]) != String(value["parent_instance"]["definition_checksum"]) or String(instance["member_kind"]) != String(value["parent_instance"]["member_kind"]): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_SEGMENT_DEFINITION_MISMATCH")
		var segment_length := float(row["end_offset_m"]) - float(row["start_offset_m"])
		if not ParametricUtils.nearly_equal(float(instance["geometry"]["length_m"]), segment_length): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_SEGMENT_LENGTH_MISMATCH")
		var instance_id := String(instance["member_instance_id"]); var item_id := String(instance["item_instance_id"])
		if instance_ids.has(instance_id) or item_ids.has(item_id): return ParametricUtils.failure("DUPLICATE_CONSTRUCTION_PARAMETRIC_SEGMENT_IDENTITY")
		instance_ids[instance_id] = true; item_ids[item_id] = true
		total_mass += float(instance["mass_kg"]); total_volume += float(instance["geometry"]["volume_m3"])
		for usage in instance["material_usage"]:
			var material_id := String(usage["material_id"])
			var aggregate: Dictionary = total_usage.get(material_id, {"mass_kg": 0.0, "volume_m3": 0.0})
			aggregate["mass_kg"] = float(aggregate["mass_kg"]) + float(usage["mass_kg"]); aggregate["volume_m3"] = float(aggregate["volume_m3"]) + float(usage["volume_m3"]); total_usage[material_id] = aggregate
		expected_start = float(row["end_offset_m"])
	if not ParametricUtils.nearly_equal(expected_start, parent_length): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_SEGMENTS_DO_NOT_COVER_PARENT")
	if not ParametricUtils.nearly_equal(total_mass, float(value["parent_instance"]["mass_kg"])) or not ParametricUtils.nearly_equal(total_volume, float(value["parent_instance"]["geometry"]["volume_m3"])): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_SEGMENTATION_NOT_CONSERVATIVE")
	for usage in value["parent_instance"]["material_usage"]:
		var material_id := String(usage["material_id"])
		if not total_usage.has(material_id) or not ParametricUtils.nearly_equal(float(total_usage[material_id]["mass_kg"]), float(usage["mass_kg"])) or not ParametricUtils.nearly_equal(float(total_usage[material_id]["volume_m3"]), float(usage["volume_m3"])): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_SEGMENTATION_MATERIAL_NOT_CONSERVED")
	if typeof(value.get("repair_plan")) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_SEGMENTATION_REPAIR_PLAN")
	checked = RepairPlanScript.validate(value["repair_plan"]); if not bool(checked.get("success", false)): return checked
	if String(value["repair_plan"]["parent_instance"]["checksum"]) != String(value["parent_instance"]["checksum"]): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_SEGMENTATION_REPAIR_PARENT_MISMATCH")
	if String(value.get("checksum", "")) != compute_checksum(value): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_SEGMENTATION_PLAN_CHECKSUM_MISMATCH")
	return ParametricUtils.success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
