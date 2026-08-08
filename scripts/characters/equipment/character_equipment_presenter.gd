class_name CharacterEquipmentPresenter
extends Node3D

var character_visual_root: Node3D
var rig_adapter: CharacterRigAdapter
var presentation_catalog: WearablePresentationCatalog

var _visuals_by_item: Dictionary = {}
var _entry_lines_by_item: Dictionary = {}
var _last_snapshot_fingerprint := ""


func setup(
	p_character_visual_root: Node3D,
	p_rig_adapter: CharacterRigAdapter,
	p_presentation_catalog: WearablePresentationCatalog
) -> Dictionary:
	if p_character_visual_root == null:
		return _result(false, "MISSING_CHARACTER_VISUAL_ROOT")
	if p_rig_adapter == null or p_rig_adapter.rig_profile_id.is_empty():
		return _result(false, "INVALID_RIG_ADAPTER")
	if p_presentation_catalog == null:
		return _result(false, "MISSING_PRESENTATION_CATALOG")
	character_visual_root = p_character_visual_root
	rig_adapter = p_rig_adapter
	presentation_catalog = p_presentation_catalog
	return _result(true, CharacterEquipmentDomain.RESULT_OK)


func apply_snapshot(snapshot: CharacterEquipmentDomain.Snapshot) -> Dictionary:
	if snapshot == null:
		return _result(false, "INVALID_EQUIPMENT_SNAPSHOT")
	if character_visual_root == null or rig_adapter == null or presentation_catalog == null:
		return _result(false, "PRESENTER_NOT_CONFIGURED")

	var fingerprint := snapshot.fingerprint()
	if fingerprint == _last_snapshot_fingerprint and _presentation_is_intact():
		return _result(true, CharacterEquipmentDomain.RESULT_OK, {
			"changed": false,
			"created": 0,
			"removed": 0,
			"reused": _visuals_by_item.size(),
		})

	var desired: Dictionary = {}
	for raw_entry in snapshot.entries():
		if not raw_entry is CharacterEquipmentDomain.Entry:
			return _result(false, "INVALID_EQUIPMENT_ENTRY")
		if raw_entry.item_id.is_empty() or desired.has(raw_entry.item_id):
			return _result(false, "DUPLICATE_EQUIPMENT_ITEM", {"item_id": raw_entry.item_id})
		desired[raw_entry.item_id] = raw_entry

	var creation_plans: Dictionary = {}
	for item_id in desired.keys():
		var entry: CharacterEquipmentDomain.Entry = desired[item_id]
		var line := entry.canonical_line()
		if _entry_lines_by_item.get(item_id, "") == line and _has_live_visual(item_id):
			continue
		var resolved: Dictionary = presentation_catalog.resolve(entry.presentation_id, rig_adapter.rig_profile_id)
		if not bool(resolved.get("success", false)):
			return _result(false, String(resolved.get("code", "UNSUPPORTED_PRESENTATION")), resolved.get("details", {}))
		var resolved_details: Dictionary = resolved.get("details", {})
		var strategy := String(resolved_details.get("strategy", ""))
		if strategy != WearablePresentationCatalog.STRATEGY_RIGID_ATTACHMENT:
			return _result(false, "PRESENTATION_STRATEGY_NOT_IMPLEMENTED", {
				"strategy": strategy,
				"item_id": item_id,
			})
		var anchor := rig_adapter.resolve_anchor(character_visual_root, entry.anchor_id)
		if anchor == null:
			return _result(false, CharacterEquipmentDomain.RESULT_UNSUPPORTED_ANCHOR, {
				"anchor": entry.anchor_id,
				"item_id": item_id,
				"rig_profile_id": rig_adapter.rig_profile_id,
			})
		var scene = resolved_details.get("scene")
		if not scene is PackedScene:
			return _result(false, "MISSING_PRESENTATION_SCENE", {"item_id": item_id})
		creation_plans[item_id] = {
			"entry": entry,
			"line": line,
			"anchor": anchor,
			"scene": scene,
			"local_transform": resolved_details.get("local_transform", Transform3D.IDENTITY),
		}

	var removed := 0
	var existing_ids := _visuals_by_item.keys().duplicate()
	for raw_item_id in existing_ids:
		var item_id := String(raw_item_id)
		var remove_visual := not desired.has(item_id)
		if desired.has(item_id):
			var desired_entry: CharacterEquipmentDomain.Entry = desired[item_id]
			remove_visual = _entry_lines_by_item.get(item_id, "") != desired_entry.canonical_line()
		if remove_visual:
			_remove_visual(item_id)
			removed += 1

	var created := 0
	for raw_item_id in creation_plans.keys():
		var item_id := String(raw_item_id)
		var plan: Dictionary = creation_plans[item_id]
		var scene: PackedScene = plan["scene"]
		var instance = scene.instantiate()
		if not instance is Node3D:
			instance.free()
			return _result(false, "PRESENTATION_ROOT_NOT_NODE3D", {"item_id": item_id})
		var visual := instance as Node3D
		visual.name = _visual_name(item_id)
		visual.transform = plan.get("local_transform", Transform3D.IDENTITY)
		var anchor: Node3D = plan["anchor"]
		anchor.add_child(visual)
		_visuals_by_item[item_id] = visual
		_entry_lines_by_item[item_id] = String(plan["line"])
		created += 1

	_last_snapshot_fingerprint = fingerprint
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"changed": created > 0 or removed > 0,
		"created": created,
		"removed": removed,
		"reused": _visuals_by_item.size() - created,
		"visual_count": _visuals_by_item.size(),
	})


func clear() -> Dictionary:
	var item_ids := _visuals_by_item.keys().duplicate()
	for raw_item_id in item_ids:
		_remove_visual(String(raw_item_id))
	_last_snapshot_fingerprint = ""
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {"removed": item_ids.size()})


func get_visual(item_id: String) -> Node3D:
	var visual = _visuals_by_item.get(item_id)
	return visual as Node3D if visual is Node3D and is_instance_valid(visual) else null


func create_report() -> Dictionary:
	var item_ids: Array[String] = []
	for raw_item_id in _visuals_by_item.keys():
		if _has_live_visual(String(raw_item_id)):
			item_ids.append(String(raw_item_id))
	item_ids.sort()
	return {
		"schema": "planet_simulator.character_equipment_presenter.v1",
		"rig_profile_id": rig_adapter.rig_profile_id if rig_adapter != null else "",
		"snapshot_fingerprint": _last_snapshot_fingerprint,
		"visual_item_ids": item_ids,
		"visual_count": item_ids.size(),
		"moves_gameplay_body": false,
		"reads_input": false,
		"owns_network_state": false,
	}


func _presentation_is_intact() -> bool:
	for raw_item_id in _visuals_by_item.keys():
		if not _has_live_visual(String(raw_item_id)):
			return false
	return true


func _has_live_visual(item_id: String) -> bool:
	if not _visuals_by_item.has(item_id):
		return false
	var visual = _visuals_by_item[item_id]
	return visual is Node3D and is_instance_valid(visual) and not visual.is_queued_for_deletion()


func _remove_visual(item_id: String) -> void:
	if _visuals_by_item.has(item_id):
		var visual = _visuals_by_item[item_id]
		if visual is Node and is_instance_valid(visual):
			var parent := (visual as Node).get_parent()
			if parent != null:
				parent.remove_child(visual)
			(visual as Node).queue_free()
	_visuals_by_item.erase(item_id)
	_entry_lines_by_item.erase(item_id)


func _visual_name(item_id: String) -> String:
	var safe := item_id.replace("/", "_").replace(":", "_").replace(".", "_").replace("-", "_")
	return "Equipment_%s" % safe


func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": success,
		"code": code,
		"details": details.duplicate(true),
	}
