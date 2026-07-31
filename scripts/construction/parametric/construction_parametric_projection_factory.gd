extends RefCounted

const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const InstanceScript = preload("res://scripts/construction/parametric/construction_parametric_member_instance.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")

static func create_projection(instance: Dictionary, display_name: String, relation: Dictionary, revision: int = 0) -> Dictionary:
	var checked := InstanceScript.validate(instance)
	if not bool(checked.get("success", false)): return checked
	var definition_id := "parametric_%s" % String(instance["member_kind"]).to_lower()
	var projection := ProjectionScript.create(String(instance["item_instance_id"]), definition_id, display_name, 1, relation, {"condition": "INTACT", "parametric_member": instance.duplicate(true)}, revision)
	checked = ProjectionScript.validate(projection)
	if not bool(checked.get("success", false)): return checked
	return ParametricUtils.success({"projection": projection})

static func create_part_record(instance: Dictionary, part_id: String, role: String, local_position_m: Array) -> Dictionary:
	var checked := InstanceScript.validate(instance)
	if not bool(checked.get("success", false)): return checked
	var metadata := {
		"condition": "INTACT",
		"parametric_member_id": String(instance["member_instance_id"]),
		"parametric_definition_id": String(instance["member_definition_id"]),
		"parametric_member_checksum": String(instance["checksum"]),
		"geometry": Dictionary(instance["geometry"]).duplicate(true),
		"material_usage": Array(instance["material_usage"]).duplicate(true),
	}
	var part := PartScript.create(part_id, String(instance["item_instance_id"]), String(instance["member_kind"]), role, float(instance["mass_kg"]), local_position_m, metadata)
	checked = PartScript.validate(part)
	if not bool(checked.get("success", false)): return checked
	return ParametricUtils.success({"part": part})

static func validate_projection(projection: Dictionary) -> Dictionary:
	var checked := ProjectionScript.validate(projection)
	if not bool(checked.get("success", false)): return checked
	var components = projection.get("components", {})
	if not components is Dictionary or not Dictionary(components).has("parametric_member"): return ParametricUtils.failure("PARAMETRIC_MEMBER_COMPONENT_REQUIRED")
	var instance = Dictionary(components)["parametric_member"]
	if not instance is Dictionary: return ParametricUtils.failure("INVALID_PARAMETRIC_MEMBER_COMPONENT")
	checked = InstanceScript.validate(instance)
	if not bool(checked.get("success", false)): return checked
	if String(instance["item_instance_id"]) != String(projection["item_instance_id"]): return ParametricUtils.failure("PARAMETRIC_MEMBER_ITEM_ID_MISMATCH")
	return ParametricUtils.success({"instance": Dictionary(instance).duplicate(true)})
