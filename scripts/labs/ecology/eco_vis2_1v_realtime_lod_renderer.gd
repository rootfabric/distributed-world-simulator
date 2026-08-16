extends "res://scripts/labs/ecology/eco_vis1_8a_realtime_proxy_renderer.gd"

const STAGE := "ECO.VIS2.1-V"
const PROFILE_ID := "TREATMENT_REALTIME_NEAR_MID_FAR"
const NEAR_LOD_END_M := 110.0
const MID_LOD_BEGIN_M := 75.0
const MID_LOD_END_M := 240.0
const FAR_LOD_BEGIN_M := 190.0
const NEAR_END_MARGIN_M := 18.0
const MID_BEGIN_MARGIN_M := 15.0
const MID_END_MARGIN_M := 25.0
const FAR_BEGIN_MARGIN_M := 30.0

var _mid_mesh: SphereMesh
var _far_mesh: SphereMesh


func _create_proxy(record: Dictionary) -> Node3D:
	_ensure_lod_resources()
	var root := super._create_proxy(record)
	root.set_meta("vis21v_realtime_lod", true)
	root.set_meta("realtime_lod_profile", PROFILE_ID)
	_configure_near_tier(root)
	_add_mid_tier(root)
	_add_far_tier(root)
	return root


func _update_proxy(field: Node, node: Node3D, record: Dictionary, generation: int) -> void:
	super._update_proxy(field, node, record, generation)
	var population_id := String(record.get("population_id", ""))
	var canopy := node.get_node_or_null("Canopy") as MeshInstance3D
	if canopy == null:
		return
	var mid := node.get_node_or_null("MidCanopy") as MeshInstance3D
	if mid != null:
		mid.position = canopy.position
		mid.scale = canopy.scale * Vector3(1.08, 0.94, 1.08)
		mid.material_override = field.call("_lod_proxy_material", population_id, 0.82) as Material
	var far := node.get_node_or_null("FarCanopy") as MeshInstance3D
	if far != null:
		far.position = canopy.position
		far.scale = canopy.scale * Vector3(1.18, 0.86, 1.18)
		far.material_override = field.call("_lod_proxy_material", population_id, 0.62) as Material


func lod_summary() -> Dictionary:
	var live_proxy_count := 0
	var near_tier_count := 0
	var mid_tier_count := 0
	var far_tier_count := 0
	for node_variant in nodes_by_id.values():
		var node := node_variant as Node3D
		if not is_instance_valid(node):
			continue
		live_proxy_count += 1
		if node.get_node_or_null("Trunk") != null and node.get_node_or_null("Canopy") != null:
			near_tier_count += 1
		if node.get_node_or_null("MidCanopy") != null:
			mid_tier_count += 1
		if node.get_node_or_null("FarCanopy") != null:
			far_tier_count += 1
	return {
		"stage": STAGE,
		"profile_id": PROFILE_ID,
		"enabled": true,
		"live_proxy_count": live_proxy_count,
		"near_tier_count": near_tier_count,
		"mid_tier_count": mid_tier_count,
		"far_tier_count": far_tier_count,
		"near_lod_end_m": NEAR_LOD_END_M,
		"mid_lod_begin_m": MID_LOD_BEGIN_M,
		"mid_lod_end_m": MID_LOD_END_M,
		"far_lod_begin_m": FAR_LOD_BEGIN_M,
	}


func _ensure_lod_resources() -> void:
	if _mid_mesh == null:
		_mid_mesh = SphereMesh.new()
		_mid_mesh.radius = 1.0
		_mid_mesh.height = 2.2
		_mid_mesh.radial_segments = 8
		_mid_mesh.rings = 4
	if _far_mesh == null:
		_far_mesh = SphereMesh.new()
		_far_mesh.radius = 1.0
		_far_mesh.height = 2.0
		_far_mesh.radial_segments = 6
		_far_mesh.rings = 3


func _configure_near_tier(root: Node3D) -> void:
	for child_name in ["Trunk", "Canopy"]:
		var geometry := root.get_node_or_null(child_name) as GeometryInstance3D
		if geometry == null:
			continue
		geometry.visibility_range_end = NEAR_LOD_END_M
		geometry.visibility_range_end_margin = NEAR_END_MARGIN_M
		geometry.set_meta("realtime_lod_tier", "NEAR")
	var birth_marker := root.get_node_or_null("BirthMarker") as GeometryInstance3D
	if birth_marker != null:
		birth_marker.visibility_range_end = MID_LOD_END_M
		birth_marker.visibility_range_end_margin = MID_END_MARGIN_M


func _add_mid_tier(root: Node3D) -> void:
	var proxy := MeshInstance3D.new()
	proxy.name = "MidCanopy"
	proxy.mesh = _mid_mesh
	proxy.visibility_range_begin = MID_LOD_BEGIN_M
	proxy.visibility_range_begin_margin = MID_BEGIN_MARGIN_M
	proxy.visibility_range_end = MID_LOD_END_M
	proxy.visibility_range_end_margin = MID_END_MARGIN_M
	proxy.set_meta("realtime_lod_tier", "MID")
	proxy.set_meta("derived_presentation_only", true)
	root.add_child(proxy)


func _add_far_tier(root: Node3D) -> void:
	var proxy := MeshInstance3D.new()
	proxy.name = "FarCanopy"
	proxy.mesh = _far_mesh
	proxy.visibility_range_begin = FAR_LOD_BEGIN_M
	proxy.visibility_range_begin_margin = FAR_BEGIN_MARGIN_M
	proxy.set_meta("realtime_lod_tier", "FAR")
	proxy.set_meta("derived_presentation_only", true)
	root.add_child(proxy)
