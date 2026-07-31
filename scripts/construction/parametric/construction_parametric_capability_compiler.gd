extends RefCounted

const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const InstanceScript = preload("res://scripts/construction/parametric/construction_parametric_member_instance.gd")
const CapabilityScript = preload("res://scripts/construction/behavior/construction_capability_descriptor.gd")

static func compile(instance: Dictionary, part_id: String) -> Dictionary:
	var checked := InstanceScript.validate(instance)
	if not bool(checked.get("success", false)): return checked
	if not ParametricUtils.path_id(part_id, "part/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_CAPABILITY_PART")
	var kind := String(instance["member_kind"])
	var capability_kind: String = String({
		"BEAM": "LOAD_BEARING_MEMBER",
		"PANEL": "STRUCTURAL_PANEL",
		"PIPE": "FLUID_CONDUIT",
		"CABLE": "SIGNAL_CONDUIT",
		"LAYERED_WALL": "ENCLOSURE_ASSEMBLY",
	}.get(kind, ""))
	if capability_kind.is_empty(): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MEMBER_KIND")
	var suffix := String(instance["member_instance_id"]).trim_prefix("parametric-member/").replace("/", "-")
	var properties := {
		"member_instance_id": String(instance["member_instance_id"]),
		"member_kind": kind,
		"mass_kg": float(instance["mass_kg"]),
		"geometry": Dictionary(instance["geometry"]).duplicate(true),
		"material_usage": Array(instance["material_usage"]).duplicate(true),
	}
	var local_geometry = Dictionary(instance.get("provenance", {})).get("local_geometry_edit_state", {})
	if local_geometry is Dictionary and not Dictionary(local_geometry).is_empty():
		properties["local_geometry"] = Dictionary(local_geometry).duplicate(true)
	var capability := CapabilityScript.create("capability/parametric/%s" % suffix, String(capability_kind), [part_id], [], properties)
	checked = CapabilityScript.validate(capability)
	if not bool(checked.get("success", false)): return checked
	return ParametricUtils.success({"capability": capability})
