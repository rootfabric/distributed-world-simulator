class_name LayeredBodySuppressionCoordinator
extends RefCounted

# Keep CH8C's new collaborators capability-typed instead of class-name typed.
# Focused headless scripts can run before an editor import/class cache refresh,
# so compile-time references to newly introduced class_name symbols here would
# make the public setup() member itself impossible for GDScript to resolve.
var character_visual_root: Node3D
var rig_adapter
var coverage_catalog

var _target: GeometryInstance3D
var _original_material_override: Material
var _applied_material: Material
var _active_regions: Array[String] = []
var _last_snapshot_fingerprint := ""


func setup(
	p_character_visual_root: Node3D,
	p_rig_adapter,
	p_coverage_catalog
) -> Dictionary:
	clear()
	if p_character_visual_root == null:
		return _result(false, "MISSING_CHARACTER_VISUAL_ROOT")
	if p_rig_adapter == null or not p_rig_adapter.has_method("supports_body_region"):
		return _result(false, "INVALID_RIG_ADAPTER")
	var rig_profile_id := String(p_rig_adapter.get("rig_profile_id"))
	if rig_profile_id.is_empty():
		return _result(false, "INVALID_RIG_ADAPTER")
	if (
		p_coverage_catalog == null
		or not p_coverage_catalog.has_method("has")
		or not p_coverage_catalog.has_method("resolve")
	):
		return _result(false, "MISSING_BODY_COVERAGE_CATALOG")
	character_visual_root = p_character_visual_root
	rig_adapter = p_rig_adapter
	coverage_catalog = p_coverage_catalog
	return _result(true, CharacterEquipmentDomain.RESULT_OK)


func apply_snapshot(snapshot: CharacterEquipmentDomain.Snapshot) -> Dictionary:
	if snapshot == null:
		return _result(false, "INVALID_EQUIPMENT_SNAPSHOT")
	if character_visual_root == null or rig_adapter == null or coverage_catalog == null:
		return _result(false, "BODY_SUPPRESSION_COORDINATOR_NOT_CONFIGURED")

	var fingerprint := snapshot.fingerprint()
	if fingerprint == _last_snapshot_fingerprint and _presentation_is_intact():
		return _result(true, CharacterEquipmentDomain.RESULT_OK, {
			"changed": false,
			"active_regions": _active_regions.duplicate(),
		})

	var rig_profile_id := _rig_profile_id()
	var region_set: Dictionary = {}
	for raw_entry in snapshot.entries():
		if not raw_entry is CharacterEquipmentDomain.Entry:
			return _result(false, "INVALID_EQUIPMENT_ENTRY")
		var entry := raw_entry as CharacterEquipmentDomain.Entry
		if not coverage_catalog.has(entry.presentation_id, rig_profile_id):
			continue
		var coverage: Dictionary = coverage_catalog.resolve(entry.presentation_id, rig_profile_id)
		if not bool(coverage.get("success", false)):
			return coverage
		var details: Dictionary = coverage.get("details", {})
		for raw_region in details.get("body_regions", []):
			var region_id := String(raw_region)
			if not rig_adapter.supports_body_region(region_id):
				return _result(false, "UNSUPPORTED_BODY_REGION", {
					"body_region": region_id,
					"presentation_id": entry.presentation_id,
				})
			region_set[region_id] = true

	var regions: Array[String] = []
	for raw_region in region_set.keys():
		regions.append(String(raw_region))
	regions.sort()

	if regions == _active_regions and _presentation_is_intact():
		_last_snapshot_fingerprint = fingerprint
		return _result(true, CharacterEquipmentDomain.RESULT_OK, {
			"changed": false,
			"active_regions": _active_regions.duplicate(),
		})

	if regions.is_empty():
		var restored := _restore_original_material()
		_active_regions.clear()
		_last_snapshot_fingerprint = fingerprint
		return _result(true, CharacterEquipmentDomain.RESULT_OK, {
			"changed": restored,
			"active_regions": [],
			"restored_original": restored,
		})

	if not rig_adapter.has_method("resolve_composite_body_suppression"):
		return _result(false, "COMPOSITE_BODY_SUPPRESSION_UNSUPPORTED", {
			"rig_profile_id": rig_profile_id,
			"active_regions": regions,
		})
	var composite: Dictionary = rig_adapter.call(
		"resolve_composite_body_suppression",
		character_visual_root,
		regions
	)
	if not bool(composite.get("success", false)):
		return composite
	var composite_details: Dictionary = composite.get("details", {})
	var raw_node = composite_details.get("node")
	var raw_material = composite_details.get("material_override")
	if not raw_node is GeometryInstance3D:
		return _result(false, "COMPOSITE_SUPPRESSION_TARGET_INVALID")
	if not raw_material is Material:
		return _result(false, "COMPOSITE_SUPPRESSION_MATERIAL_INVALID")
	var next_target := raw_node as GeometryInstance3D
	var next_material := raw_material as Material

	if _target != null and is_instance_valid(_target) and _target != next_target:
		_restore_original_material()
	if _target == null or not is_instance_valid(_target):
		_target = next_target
		_original_material_override = next_target.material_override
	else:
		_target = next_target
	_target.material_override = next_material
	_applied_material = next_material
	_active_regions = regions
	_last_snapshot_fingerprint = fingerprint
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"changed": true,
		"active_regions": _active_regions.duplicate(),
		"target_name": String(_target.name),
		"target_key": String(composite_details.get("key", "")),
		"material_name": String(_applied_material.resource_name),
	})


func clear() -> Dictionary:
	var restored := _restore_original_material()
	character_visual_root = null
	rig_adapter = null
	coverage_catalog = null
	_active_regions.clear()
	_last_snapshot_fingerprint = ""
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {"restored_original": restored})


func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.layered_body_suppression_coordinator.v1",
		"rig_profile_id": _rig_profile_id(),
		"active_regions": _active_regions.duplicate(),
		"target_ready": _target != null and is_instance_valid(_target),
		"target_name": String(_target.name) if _target != null and is_instance_valid(_target) else "",
		"material_applied": _applied_material != null,
		"snapshot_fingerprint": _last_snapshot_fingerprint,
		"moves_gameplay_body": false,
		"reads_input": false,
		"owns_network_state": false,
	}


func _presentation_is_intact() -> bool:
	if _active_regions.is_empty():
		return _target == null or not is_instance_valid(_target) or _target.material_override == _original_material_override
	return (
		_target != null
		and is_instance_valid(_target)
		and _applied_material != null
		and _target.material_override == _applied_material
	)


func _restore_original_material() -> bool:
	var restored := false
	if _target != null and is_instance_valid(_target):
		_target.material_override = _original_material_override
		restored = true
	_target = null
	_original_material_override = null
	_applied_material = null
	return restored


func _rig_profile_id() -> String:
	if rig_adapter == null:
		return ""
	return String(rig_adapter.get("rig_profile_id"))


func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": success,
		"code": code,
		"details": details.duplicate(true),
	}
