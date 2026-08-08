class_name CharacterEquipmentPresenter
extends Node3D

const SkinnedGarmentPoseBridge = preload("res://scripts/characters/equipment/skinned_garment_pose_bridge.gd")

var character_visual_root: Node3D
var rig_adapter: CharacterRigAdapter
var presentation_catalog: WearablePresentationCatalog

var _visuals_by_item: Dictionary = {}
var _entry_lines_by_item: Dictionary = {}
var _strategies_by_item: Dictionary = {}
var _suppression_keys_by_item: Dictionary = {}
var _body_suppression_state_by_key: Dictionary = {}
var _body_replacement_nodes_by_item: Dictionary = {}
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
		var scene = resolved_details.get("scene")
		if not scene is PackedScene:
			return _result(false, "MISSING_PRESENTATION_SCENE", {"item_id": item_id})

		if strategy == WearablePresentationCatalog.STRATEGY_RIGID_ATTACHMENT:
			var anchor := rig_adapter.resolve_anchor(character_visual_root, entry.anchor_id)
			if anchor == null:
				return _result(false, CharacterEquipmentDomain.RESULT_UNSUPPORTED_ANCHOR, {
					"anchor": entry.anchor_id,
					"item_id": item_id,
					"rig_profile_id": rig_adapter.rig_profile_id,
				})
			creation_plans[item_id] = {
				"entry": entry,
				"line": line,
				"strategy": strategy,
				"parent": anchor,
				"scene": scene,
				"local_transform": resolved_details.get("local_transform", Transform3D.IDENTITY),
			}
		elif strategy == WearablePresentationCatalog.STRATEGY_SKINNED_GARMENT:
			var source_skeleton := rig_adapter.resolve_pose_skeleton(character_visual_root)
			var skinned_parent := rig_adapter.resolve_skinned_parent(character_visual_root)
			if source_skeleton == null:
				return _result(false, "SKINNED_SOURCE_SKELETON_UNAVAILABLE", {"item_id": item_id})
			if skinned_parent == null:
				return _result(false, "SKINNED_PRESENTATION_PARENT_UNAVAILABLE", {"item_id": item_id})

			var hidden_regions: Array = resolved_details.get("hide_body_regions", [])
			var suppression_targets: Array[Dictionary] = []
			var seen_suppression_keys: Dictionary = {}
			for raw_region in hidden_regions:
				var region_id := String(raw_region)
				if not rig_adapter.supports_body_region(region_id):
					return _result(false, "UNSUPPORTED_BODY_REGION", {
						"item_id": item_id,
						"body_region": region_id,
						"rig_profile_id": rig_adapter.rig_profile_id,
					})
				var targets: Array[Dictionary] = rig_adapter.resolve_body_region_suppression_targets(
					character_visual_root,
					region_id
				)
				if targets.is_empty():
					return _result(false, "BODY_REGION_HAS_NO_SUPPRESSION_TARGETS", {
						"item_id": item_id,
						"body_region": region_id,
						"rig_profile_id": rig_adapter.rig_profile_id,
					})
				for target in targets:
					var target_key := String(target.get("key", ""))
					var target_mode := String(target.get("mode", ""))
					var target_node = target.get("node")
					if target_key.is_empty() or not target_node is GeometryInstance3D:
						return _result(false, "INVALID_BODY_SUPPRESSION_TARGET", {
							"item_id": item_id,
							"body_region": region_id,
						})
					if target_mode not in [
						CharacterRigAdapter.BODY_SUPPRESSION_VISIBILITY,
						CharacterRigAdapter.BODY_SUPPRESSION_MATERIAL_OVERRIDE,
					]:
						return _result(false, "UNSUPPORTED_BODY_SUPPRESSION_MODE", {
							"item_id": item_id,
							"mode": target_mode,
						})
					if target_mode == CharacterRigAdapter.BODY_SUPPRESSION_MATERIAL_OVERRIDE:
						var target_material = target.get("material_override")
						if not target_material is Material:
							return _result(false, "BODY_SUPPRESSION_MATERIAL_MISSING", {
								"item_id": item_id,
								"body_region": region_id,
							})
					if not seen_suppression_keys.has(target_key):
						seen_suppression_keys[target_key] = true
						suppression_targets.append(target.duplicate())

			var replacement_scene = resolved_details.get("body_replacement_scene")
			if replacement_scene != null and not replacement_scene is PackedScene:
				return _result(false, "INVALID_BODY_REPLACEMENT_SCENE", {"item_id": item_id})
			creation_plans[item_id] = {
				"entry": entry,
				"line": line,
				"strategy": strategy,
				"parent": skinned_parent,
				"source_skeleton": source_skeleton,
				"scene": scene,
				"local_transform": resolved_details.get("local_transform", Transform3D.IDENTITY),
				"suppression_targets": suppression_targets,
				"body_replacement_scene": replacement_scene,
				"body_replacement_transform": resolved_details.get("body_replacement_transform", Transform3D.IDENTITY),
			}
		else:
			return _result(false, "PRESENTATION_STRATEGY_NOT_IMPLEMENTED", {
				"strategy": strategy,
				"item_id": item_id,
			})

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
		var strategy := String(plan.get("strategy", ""))
		var parent: Node3D = plan["parent"]
		var visual: Node3D

		if strategy == WearablePresentationCatalog.STRATEGY_RIGID_ATTACHMENT:
			var rigid_scene: PackedScene = plan["scene"]
			var instance = rigid_scene.instantiate()
			if not instance is Node3D:
				if instance is Node:
					(instance as Node).free()
				return _result(false, "PRESENTATION_ROOT_NOT_NODE3D", {"item_id": item_id})
			visual = instance as Node3D
			visual.transform = plan.get("local_transform", Transform3D.IDENTITY)
			parent.add_child(visual)
		elif strategy == WearablePresentationCatalog.STRATEGY_SKINNED_GARMENT:
			var bridge = SkinnedGarmentPoseBridge.new()
			parent.add_child(bridge)
			var bridge_result: Dictionary = bridge.setup(
				plan["source_skeleton"] as Skeleton3D,
				plan["scene"] as PackedScene,
				plan.get("local_transform", Transform3D.IDENTITY)
			)
			if not bool(bridge_result.get("success", false)):
				parent.remove_child(bridge)
				bridge.queue_free()
				return _result(false, String(bridge_result.get("code", "SKINNED_GARMENT_SETUP_FAILED")), bridge_result.get("details", {}))

			var replacement_scene = plan.get("body_replacement_scene")
			if replacement_scene is PackedScene:
				var replacement_bridge = SkinnedGarmentPoseBridge.new()
				replacement_bridge.name = "BodyReplacement"
				bridge.add_child(replacement_bridge)
				var replacement_result: Dictionary = replacement_bridge.setup(
					plan["source_skeleton"] as Skeleton3D,
					replacement_scene as PackedScene,
					plan.get("body_replacement_transform", Transform3D.IDENTITY)
				)
				if not bool(replacement_result.get("success", false)):
					bridge.remove_child(replacement_bridge)
					replacement_bridge.queue_free()
					parent.remove_child(bridge)
					bridge.queue_free()
					return _result(false, "BODY_REPLACEMENT_SETUP_FAILED", {
						"item_id": item_id,
						"cause": replacement_result,
					})
				_body_replacement_nodes_by_item[item_id] = replacement_bridge

			var suppression_result := _apply_body_suppression(item_id, plan.get("suppression_targets", []))
			if not bool(suppression_result.get("success", false)):
				_body_replacement_nodes_by_item.erase(item_id)
				parent.remove_child(bridge)
				bridge.queue_free()
				return suppression_result
			visual = bridge
		else:
			return _result(false, "PRESENTATION_STRATEGY_NOT_IMPLEMENTED", {"item_id": item_id, "strategy": strategy})

		visual.name = _visual_name(item_id)
		_visuals_by_item[item_id] = visual
		_entry_lines_by_item[item_id] = String(plan["line"])
		_strategies_by_item[item_id] = strategy
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
	var strategies: Dictionary = {}
	var replacement_item_ids: Array[String] = []
	for raw_item_id in _visuals_by_item.keys():
		var item_id := String(raw_item_id)
		if _has_live_visual(item_id):
			item_ids.append(item_id)
			strategies[item_id] = String(_strategies_by_item.get(item_id, ""))
			if _has_live_body_replacement(item_id):
				replacement_item_ids.append(item_id)
	item_ids.sort()
	replacement_item_ids.sort()
	var hidden_count := 0
	var material_clip_count := 0
	for state_value in _body_suppression_state_by_key.values():
		if not state_value is Dictionary:
			continue
		var mode := String((state_value as Dictionary).get("mode", ""))
		if mode == CharacterRigAdapter.BODY_SUPPRESSION_VISIBILITY:
			hidden_count += 1
		elif mode == CharacterRigAdapter.BODY_SUPPRESSION_MATERIAL_OVERRIDE:
			material_clip_count += 1
	return {
		"schema": "planet_simulator.character_equipment_presenter.v2",
		"rig_profile_id": rig_adapter.rig_profile_id if rig_adapter != null else "",
		"snapshot_fingerprint": _last_snapshot_fingerprint,
		"visual_item_ids": item_ids,
		"visual_strategies": strategies,
		"visual_count": item_ids.size(),
		"hidden_body_visual_count": hidden_count,
		"material_clipped_body_visual_count": material_clip_count,
		"suppressed_body_target_count": _body_suppression_state_by_key.size(),
		"body_replacement_item_ids": replacement_item_ids,
		"body_replacement_item_count": replacement_item_ids.size(),
		"moves_gameplay_body": false,
		"reads_input": false,
		"owns_network_state": false,
	}


func _presentation_is_intact() -> bool:
	for raw_item_id in _visuals_by_item.keys():
		var item_id := String(raw_item_id)
		if not _has_live_visual(item_id):
			return false
		if _body_replacement_nodes_by_item.has(item_id) and not _has_live_body_replacement(item_id):
			return false
		if not _body_suppression_is_intact(item_id):
			return false
	return true


func _has_live_visual(item_id: String) -> bool:
	if not _visuals_by_item.has(item_id):
		return false
	var visual = _visuals_by_item[item_id]
	return visual is Node3D and is_instance_valid(visual) and not visual.is_queued_for_deletion()


func _has_live_body_replacement(item_id: String) -> bool:
	if not _body_replacement_nodes_by_item.has(item_id):
		return false
	var replacement = _body_replacement_nodes_by_item[item_id]
	return replacement is Node3D and is_instance_valid(replacement) and not replacement.is_queued_for_deletion()


func _apply_body_suppression(item_id: String, targets: Array) -> Dictionary:
	var item_keys: Array[String] = []
	for raw_target in targets:
		if not raw_target is Dictionary:
			return _result(false, "INVALID_BODY_SUPPRESSION_TARGET", {"item_id": item_id})
		var target: Dictionary = raw_target
		var key := String(target.get("key", ""))
		var mode := String(target.get("mode", ""))
		var node = target.get("node")
		if key.is_empty() or not node is GeometryInstance3D:
			return _result(false, "INVALID_BODY_SUPPRESSION_TARGET", {"item_id": item_id})
		var geometry := node as GeometryInstance3D
		var state: Dictionary = _body_suppression_state_by_key.get(key, {})
		if state.is_empty():
			state = {
				"node": geometry,
				"mode": mode,
				"ref_count": 0,
			}
			if mode == CharacterRigAdapter.BODY_SUPPRESSION_VISIBILITY:
				state["original_visible"] = geometry.visible
			elif mode == CharacterRigAdapter.BODY_SUPPRESSION_MATERIAL_OVERRIDE:
				var applied_material = target.get("material_override")
				if not applied_material is Material:
					return _result(false, "BODY_SUPPRESSION_MATERIAL_MISSING", {"item_id": item_id})
				state["original_material_override"] = geometry.material_override
				state["applied_material"] = applied_material
			else:
				return _result(false, "UNSUPPORTED_BODY_SUPPRESSION_MODE", {
					"item_id": item_id,
					"mode": mode,
				})
		else:
			if String(state.get("mode", "")) != mode:
				return _result(false, "BODY_SUPPRESSION_MODE_CONFLICT", {"item_id": item_id, "key": key})
			if mode == CharacterRigAdapter.BODY_SUPPRESSION_MATERIAL_OVERRIDE:
				var existing_material = state.get("applied_material")
				var requested_material = target.get("material_override")
				if existing_material != requested_material:
					return _result(false, "BODY_SUPPRESSION_MATERIAL_CONFLICT", {"item_id": item_id, "key": key})

		state["ref_count"] = int(state.get("ref_count", 0)) + 1
		_body_suppression_state_by_key[key] = state
		if mode == CharacterRigAdapter.BODY_SUPPRESSION_VISIBILITY:
			geometry.visible = false
		else:
			geometry.material_override = state.get("applied_material") as Material
		item_keys.append(key)
	_suppression_keys_by_item[item_id] = item_keys
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {"target_count": item_keys.size()})


func _restore_body_suppression(item_id: String) -> void:
	var keys: Array = _suppression_keys_by_item.get(item_id, [])
	for raw_key in keys:
		var key := String(raw_key)
		if not _body_suppression_state_by_key.has(key):
			continue
		var state: Dictionary = _body_suppression_state_by_key[key]
		var ref_count := int(state.get("ref_count", 0)) - 1
		if ref_count <= 0:
			var node = state.get("node")
			if node is GeometryInstance3D and is_instance_valid(node):
				var geometry := node as GeometryInstance3D
				var mode := String(state.get("mode", ""))
				if mode == CharacterRigAdapter.BODY_SUPPRESSION_VISIBILITY:
					geometry.visible = bool(state.get("original_visible", true))
				elif mode == CharacterRigAdapter.BODY_SUPPRESSION_MATERIAL_OVERRIDE:
					geometry.material_override = state.get("original_material_override") as Material
			_body_suppression_state_by_key.erase(key)
		else:
			state["ref_count"] = ref_count
			_body_suppression_state_by_key[key] = state
	_suppression_keys_by_item.erase(item_id)


func _body_suppression_is_intact(item_id: String) -> bool:
	if not _suppression_keys_by_item.has(item_id):
		return true
	var keys: Array = _suppression_keys_by_item[item_id]
	for raw_key in keys:
		var key := String(raw_key)
		if not _body_suppression_state_by_key.has(key):
			return false
		var state: Dictionary = _body_suppression_state_by_key[key]
		var node = state.get("node")
		if not node is GeometryInstance3D or not is_instance_valid(node):
			return false
		var geometry := node as GeometryInstance3D
		var mode := String(state.get("mode", ""))
		if mode == CharacterRigAdapter.BODY_SUPPRESSION_VISIBILITY and geometry.visible:
			return false
		if mode == CharacterRigAdapter.BODY_SUPPRESSION_MATERIAL_OVERRIDE:
			if geometry.material_override != state.get("applied_material"):
				return false
	return true


func _remove_visual(item_id: String) -> void:
	_restore_body_suppression(item_id)
	_body_replacement_nodes_by_item.erase(item_id)
	if _visuals_by_item.has(item_id):
		var visual = _visuals_by_item[item_id]
		if visual is Node and is_instance_valid(visual):
			var parent := (visual as Node).get_parent()
			if parent != null:
				parent.remove_child(visual)
			(visual as Node).queue_free()
	_visuals_by_item.erase(item_id)
	_entry_lines_by_item.erase(item_id)
	_strategies_by_item.erase(item_id)


func _visual_name(item_id: String) -> String:
	var safe := item_id.replace("/", "_").replace(":", "_").replace(".", "_").replace("-", "_")
	return "Equipment_%s" % safe


func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": success,
		"code": code,
		"details": details.duplicate(true),
	}
