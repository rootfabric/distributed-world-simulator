class_name QuaterniusLayeredBodySuppressionAdapter
extends QuaterniusEquipmentRigAdapter

const RegionClipMaterial = preload("res://scripts/characters/equipment/quaternius_region_clip_material.gd")

const REGION_TORSO_CORE := "body.region.torso.core"
const REGION_THIGHS_CORE := "body.region.thighs.core"
const REGION_SHINS_CORE := "body.region.shins.core"
const REGION_FEET_CORE := "body.region.feet.core"
const LAYERED_BODY_REGIONS := [
	REGION_TORSO_CORE,
	REGION_THIGHS_CORE,
	REGION_SHINS_CORE,
	REGION_FEET_CORE,
]


func supports_body_region(region_id: String) -> bool:
	return region_id in LAYERED_BODY_REGIONS or super.supports_body_region(region_id)


func resolve_composite_body_suppression(
	_character_visual_root: Node,
	region_ids: Array
) -> Dictionary:
	var regions: Array[String] = []
	for raw_region in region_ids:
		var region_id := String(raw_region)
		if not supports_body_region(region_id):
			return _result(false, "UNSUPPORTED_BODY_REGION", {"body_region": region_id})
		if region_id not in regions:
			regions.append(region_id)
	regions.sort()
	if regions.is_empty():
		return _result(false, "COMPOSITE_BODY_SUPPRESSION_REQUIRES_REGION")

	var body_mesh := _resolve_base_body_mesh()
	if body_mesh == null:
		return _result(false, "COMPOSITE_BODY_MESH_NOT_FOUND")
	var material_result: Dictionary = RegionClipMaterial.create_from_mesh(body_mesh, regions)
	if not bool(material_result.get("success", false)):
		return material_result
	var material_details: Dictionary = material_result.get("details", {})
	var material = material_details.get("material")
	if not material is ShaderMaterial:
		return _result(false, "COMPOSITE_BODY_MATERIAL_NOT_SHADER")
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"key": "quaternius_region_clip:%d" % body_mesh.get_instance_id(),
		"node": body_mesh,
		"material_override": material,
		"active_regions": regions,
		"debug": {
			"kind": "QUATERNIUS_FUSED_BODY_REGION_CLIP",
			"mesh_name": String(body_mesh.name),
			"thresholds": material_details.get("thresholds", {}),
			"protected_bands": material_details.get("protected_bands", {}),
			"opaque_discard": bool(material_details.get("opaque_discard", false)),
		}
	})


func create_report() -> Dictionary:
	var report := super.create_report()
	report["composite_body_suppression"] = true
	report["composite_body_suppression_mode"] = "REGION_MATERIAL_OVERRIDE"
	report["layered_body_regions"] = LAYERED_BODY_REGIONS.duplicate()
	return report
