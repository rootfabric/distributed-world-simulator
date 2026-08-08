class_name LayeredBodyTopologyOcclusionCoordinator
extends RefCounted

const Builder = preload("res://scripts/characters/equipment/garment_topology_occlusion_builder.gd")

var character_visual_root: Node3D
var rig_adapter
var topology_catalog

var _target: MeshInstance3D
var _original_mesh: Mesh
var _applied_mesh: Mesh
var _active_presentations: Array[String] = []
var _active_key := ""
var _last_removed_triangles := 0
var _last_total_triangles := 0
var _last_descriptor_reports: Array[Dictionary] = []


func setup(
	p_character_visual_root: Node3D,
	p_rig_adapter,
	p_topology_catalog
) -> Dictionary:
	clear()
	if p_character_visual_root == null:
		return _result(false, "MISSING_CHARACTER_VISUAL_ROOT")
	if p_rig_adapter == null or not p_rig_adapter.has_method("resolve_topology_occlusion_target"):
		return _result(false, "TOPOLOGY_RIG_ADAPTER_UNSUPPORTED")
	if (
		p_topology_catalog == null
		or not p_topology_catalog.has_method("has")
		or not p_topology_catalog.has_method("resolve")
	):
		return _result(false, "MISSING_TOPOLOGY_OCCLUSION_CATALOG")
	character_visual_root = p_character_visual_root
	rig_adapter = p_rig_adapter
	topology_catalog = p_topology_catalog
	var target_result: Dictionary = rig_adapter.call("resolve_topology_occlusion_target", character_visual_root)
	if not bool(target_result.get("success", false)):
		clear()
		return target_result
	var raw_node = target_result.get("details", {}).get("node")
	if not raw_node is MeshInstance3D:
		clear()
		return _result(false, "TOPOLOGY_OCCLUSION_TARGET_INVALID")
	_target = raw_node as MeshInstance3D
	_original_mesh = _target.mesh
	if _original_mesh == null:
		clear()
		return _result(false, "TOPOLOGY_OCCLUSION_ORIGINAL_MESH_MISSING")
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"target_name": String(_target.name),
		"original_mesh_name": String(_original_mesh.resource_name),
	})


func apply_snapshot(snapshot: CharacterEquipmentDomain.Snapshot) -> Dictionary:
	if snapshot == null:
		return _result(false, "INVALID_EQUIPMENT_SNAPSHOT")
	if character_visual_root == null or rig_adapter == null or topology_catalog == null:
		return _result(false, "TOPOLOGY_OCCLUSION_COORDINATOR_NOT_CONFIGURED")
	if _target == null or not is_instance_valid(_target) or _original_mesh == null:
		return _result(false, "TOPOLOGY_OCCLUSION_TARGET_UNAVAILABLE")

	var rig_profile_id := String(rig_adapter.get("rig_profile_id"))
	var descriptors: Array[Dictionary] = []
	var active_presentations: Array[String] = []
	var key_parts: Array[String] = []
	for raw_entry in snapshot.entries():
		if not raw_entry is CharacterEquipmentDomain.Entry:
			return _result(false, "INVALID_EQUIPMENT_ENTRY")
		var entry := raw_entry as CharacterEquipmentDomain.Entry
		if not topology_catalog.has(entry.presentation_id, rig_profile_id):
			continue
		var resolved: Dictionary = topology_catalog.resolve(entry.presentation_id, rig_profile_id)
		if not bool(resolved.get("success", false)):
			return resolved
		var details: Dictionary = resolved.get("details", {})
		var scene = details.get("scene")
		if not scene is PackedScene:
			return _result(false, "TOPOLOGY_OCCLUSION_SCENE_INVALID", {
				"presentation_id": entry.presentation_id,
			})
		var threshold_m := float(details.get("threshold_m", 0.0))
		var boundary_pad_m := float(details.get("boundary_pad_m", 0.0))
		var coverage_mode := String(details.get("coverage_mode", "ROBUST"))
		var upper_y_pad_m := float(details.get("upper_y_pad_m", 0.0))
		var upper_bias_fraction := float(details.get("upper_bias_fraction", 1.0))
		descriptors.append({
			"presentation_id": entry.presentation_id,
			"scene": scene,
			"threshold_m": threshold_m,
			"boundary_pad_m": boundary_pad_m,
			"coverage_mode": coverage_mode,
			"upper_y_pad_m": upper_y_pad_m,
			"upper_bias_fraction": upper_bias_fraction,
		})
		active_presentations.append(entry.presentation_id)
		key_parts.append("%s@%.5f@%.5f@%s@%.5f@%.5f" % [
			entry.presentation_id,
			threshold_m,
			boundary_pad_m,
			coverage_mode,
			upper_y_pad_m,
			upper_bias_fraction,
		])
	active_presentations.sort()
	key_parts.sort()
	var next_key := "|".join(key_parts)

	if next_key == _active_key and _presentation_is_intact():
		return _result(true, CharacterEquipmentDomain.RESULT_OK, {
			"changed": false,
			"active_presentations": _active_presentations.duplicate(),
			"removed_triangles": _last_removed_triangles,
			"total_triangles": _last_total_triangles,
			"descriptor_reports": _last_descriptor_reports.duplicate(true),
		})

	if descriptors.is_empty():
		var restored := _restore_original_mesh()
		_active_presentations.clear()
		_active_key = ""
		_last_removed_triangles = 0
		_last_total_triangles = 0
		_last_descriptor_reports.clear()
		return _result(true, CharacterEquipmentDomain.RESULT_OK, {
			"changed": restored,
			"restored_original": restored,
			"active_presentations": [],
			"descriptor_reports": [],
		})

	var build_result: Dictionary = Builder.create_masked_mesh(
		_target,
		character_visual_root,
		descriptors,
		_original_mesh
	)
	if not bool(build_result.get("success", false)):
		return build_result
	var details: Dictionary = build_result.get("details", {})
	var raw_mesh = details.get("mesh")
	if not raw_mesh is Mesh:
		return _result(false, "TOPOLOGY_OCCLUSION_BUILD_MESH_INVALID")
	_applied_mesh = raw_mesh as Mesh
	_target.mesh = _applied_mesh
	_active_presentations = active_presentations
	_active_key = next_key
	_last_removed_triangles = int(details.get("removed_triangles", 0))
	_last_total_triangles = int(details.get("total_triangles", 0))
	_last_descriptor_reports.clear()
	for raw_report in details.get("descriptor_reports", []):
		if raw_report is Dictionary:
			_last_descriptor_reports.append((raw_report as Dictionary).duplicate(true))
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"changed": true,
		"active_presentations": _active_presentations.duplicate(),
		"removed_triangles": _last_removed_triangles,
		"remaining_triangles": int(details.get("remaining_triangles", 0)),
		"total_triangles": _last_total_triangles,
		"removed_ratio": float(details.get("removed_ratio", 0.0)),
		"sample_count": int(details.get("sample_count", 0)),
		"descriptor_reports": _last_descriptor_reports.duplicate(true),
		"target_name": String(_target.name),
	})


func clear() -> Dictionary:
	var restored := _restore_original_mesh()
	character_visual_root = null
	rig_adapter = null
	topology_catalog = null
	_target = null
	_original_mesh = null
	_applied_mesh = null
	_active_presentations.clear()
	_active_key = ""
	_last_removed_triangles = 0
	_last_total_triangles = 0
	_last_descriptor_reports.clear()
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {"restored_original": restored})


func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.layered_body_topology_occlusion.v2",
		"rig_profile_id": String(rig_adapter.get("rig_profile_id")) if rig_adapter != null else "",
		"target_ready": _target != null and is_instance_valid(_target),
		"target_name": String(_target.name) if _target != null and is_instance_valid(_target) else "",
		"mesh_applied": _applied_mesh != null,
		"active_presentations": _active_presentations.duplicate(),
		"removed_triangles": _last_removed_triangles,
		"total_triangles": _last_total_triangles,
		"descriptor_reports": _last_descriptor_reports.duplicate(true),
		"moves_gameplay_body": false,
		"reads_input": false,
		"owns_network_state": false,
	}


func _presentation_is_intact() -> bool:
	if _active_presentations.is_empty():
		return _target == null or not is_instance_valid(_target) or _target.mesh == _original_mesh
	return (
		_target != null
		and is_instance_valid(_target)
		and _applied_mesh != null
		and _target.mesh == _applied_mesh
	)


func _restore_original_mesh() -> bool:
	if _target == null or not is_instance_valid(_target) or _original_mesh == null:
		_applied_mesh = null
		return false
	var changed := _target.mesh != _original_mesh
	_target.mesh = _original_mesh
	_applied_mesh = null
	return changed


func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": success,
		"code": code,
		"details": details,
	}
