extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const InstanceScript = preload("res://scripts/construction/parametric/construction_parametric_member_instance.gd")

const SCHEMA := "planet_simulator.construction_parametric_repair_plan.v1"
const FIELDS: Array[String] = ["schema", "repair_plan_id", "parent_instance", "segment_instance_checksums", "segment_item_instance_ids", "checksum"]

static func create(repair_plan_id: String, parent_instance: Dictionary, segments: Array) -> Dictionary:
	var checksums: Array = []; var item_ids: Array = []
	for segment in segments:
		checksums.append(String(segment["checksum"])); item_ids.append(String(segment["item_instance_id"]))
	var value := {"schema": SCHEMA, "repair_plan_id": repair_plan_id, "parent_instance": parent_instance.duplicate(true), "segment_instance_checksums": checksums, "segment_item_instance_ids": item_ids, "checksum": ""}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return ParametricUtils.failure("UNSUPPORTED_CONSTRUCTION_PARAMETRIC_REPAIR_PLAN_SCHEMA")
	if not ParametricUtils.path_id(String(value.get("repair_plan_id", "")), "parametric-repair/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_REPAIR_PLAN_ID")
	if typeof(value.get("parent_instance")) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_REPAIR_PARENT")
	var checked := InstanceScript.validate(value["parent_instance"]); if not bool(checked.get("success", false)): return checked
	for field in ["segment_instance_checksums", "segment_item_instance_ids"]:
		if typeof(value.get(field)) != TYPE_ARRAY or Array(value[field]).size() < 2: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_REPAIR_SEGMENTS")
	if Array(value["segment_instance_checksums"]).size() != Array(value["segment_item_instance_ids"]).size(): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_REPAIR_SEGMENT_COUNT_MISMATCH")
	var checksums := {}; var items := {}
	for index in range(value["segment_instance_checksums"].size()):
		var checksum := String(value["segment_instance_checksums"][index]); var item_id := String(value["segment_item_instance_ids"][index])
		if checksum.length() != 64 or checksums.has(checksum): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_REPAIR_SEGMENT_CHECKSUM")
		if not ParametricUtils.path_id(item_id, "item/") or items.has(item_id): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_REPAIR_SEGMENT_ITEM")
		checksums[checksum] = true; items[item_id] = true
	if String(value.get("checksum", "")) != compute_checksum(value): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_REPAIR_PLAN_CHECKSUM_MISMATCH")
	return ParametricUtils.success()

static func resolve(value: Dictionary, available_segments: Array) -> Dictionary:
	var checked := validate(value)
	if not bool(checked.get("success", false)): return checked
	var by_checksum := {}
	for segment in available_segments:
		if typeof(segment) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_REPAIR_SEGMENT")
		checked = InstanceScript.validate(segment); if not bool(checked.get("success", false)): return checked
		by_checksum[String(segment["checksum"])] = segment
	for index in range(value["segment_instance_checksums"].size()):
		var checksum := String(value["segment_instance_checksums"][index])
		if not by_checksum.has(checksum): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_REPAIR_SEGMENT_MISSING")
		if String(by_checksum[checksum]["item_instance_id"]) != String(value["segment_item_instance_ids"][index]): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_REPAIR_SEGMENT_IDENTITY_MISMATCH")
	return ParametricUtils.success({"restored_instance": Dictionary(value["parent_instance"]).duplicate(true)})

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
